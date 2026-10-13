create or replace function family_private.profile_save(data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare oldrow family_private.member_details; g text; n text;begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول';end if;
 select * into oldrow from family_private.member_details where id=auth.uid() for update;
 if oldrow.phone is not null and oldrow.phone is distinct from data->>'phone' then raise exception 'تغيير رقم الجوال يتطلب طلبًا للمدير';end if;
 g=data->>'gender';n=family_private.normalize_name(data->>'full_name');
 if cardinality(string_to_array(n,' '))<>4 or g not in ('male','female') or g is null then raise exception 'أدخل الاسم الرباعي والجنس';end if;
 if coalesce(data->>'phone','') !~ '^\+[1-9][0-9]{7,14}$' then raise exception 'أدخل رقم الجوال بصيغة دولية';end if;
 if oldrow.gender is not null and oldrow.gender<>g then raise exception 'تغيير الجنس يحتاج مراجعة المدير';end if;
 if g='female' and (coalesce(data->>'reference_name','')='' or coalesce(data->>'relationship','') not in ('father','husband','brother','uncle','maternal_uncle')) then raise exception 'أدخل اسم المعرّف وصلة القرابة';end if;
 update family_private.member_details set full_name=n,phone=nullif(data->>'phone',''),gender=g,reference_name=data->>'reference_name',relationship=nullif(data->>'relationship','') where id=auth.uid();
 update public.profiles set display_name=n where id=auth.uid();
 if (select auto_activate from public.family_settings where id) and family_private.registration_valid(auth.uid()) then update public.profiles set status='active' where id=auth.uid() and status='pending';end if;
 return family_private.profile_get();
exception when unique_violation then raise exception 'رقم الجوال مسجل لحساب آخر';end $$;

create or replace function family_private.registration_valid(member uuid) returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from family_private.member_details d join auth.users u on u.id=d.id where not(select endorsements_enabled from public.family_settings where id) and d.id=member and u.email_confirmed_at is not null and d.phone is not null and d.gender is not null and cardinality(string_to_array(family_private.normalize_name(d.full_name),' '))=4 and exists(select 1 from public.allowed_families f where family_private.normalize_name(f.name)=split_part(family_private.normalize_name(d.full_name),' ',4)) and (d.gender='male' or (d.relationship is not null and exists(select 1 from family_private.member_details r join public.profiles p on p.id=r.id where r.gender='male' and p.status='active' and family_private.normalize_name(r.full_name)=family_private.normalize_name(d.reference_name)))))
$$;

create or replace function family_private.chat_read(thread uuid,before_id bigint default null) returns jsonb language plpgsql stable security definer set search_path='' as $$declare peer uuid;begin
 if family_private.access_role() is null or not (select chat_enabled from public.family_settings where id) then raise exception 'الدردشة موقوفة';end if;
 if thread is null then
  if not (select public_chat_enabled from public.family_settings where id) then raise exception 'الدردشة العامة موقوفة';end if;
 else
  select case when member_a=auth.uid() then member_b else member_a end into peer from family_private.chat_threads where id=thread and auth.uid() in(member_a,member_b);
  if peer is null or not family_private.chat_pair_allowed(peer) or not (select private_chat_enabled from public.family_settings where id) then raise exception 'المحادثة غير متاحة';end if;
 end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from (select m.id,m.sender_id,m.body,m.created_at,p.display_name,p.avatar_path from family_private.chat_messages m join public.profiles p on p.id=m.sender_id where m.group_id is null and m.thread_id is not distinct from thread and (before_id is null or m.id<before_id) and family_private.chat_pair_allowed(m.sender_id) order by m.id desc limit 50)x),'[]'::jsonb);
end $$;

create or replace function family_private.chat_search(term text) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if family_private.access_role() is null then raise exception 'حساب غير معتمد';end if;
 if not (select chat_enabled and private_chat_enabled from public.family_settings where id) then return '[]'::jsonb;end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (select p.id,p.display_name,p.avatar_path from public.profiles p join family_private.member_details d on d.id=p.id where p.id<>auth.uid() and family_private.chat_pair_allowed(p.id) and (p.display_name ilike '%'||left(term,80)||'%' or d.phone=term) order by p.display_name limit 30)x),'[]'::jsonb);
end $$;

create or replace function family_private.chat_list() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if family_private.access_role() is null then raise exception 'حساب غير معتمد';end if;
 if not (select chat_enabled and private_chat_enabled from public.family_settings where id) then return '[]'::jsonb;end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (select t.id,p.display_name,p.avatar_path,p.id as member_id from family_private.chat_threads t join public.profiles p on p.id=case when t.member_a=auth.uid() then t.member_b else t.member_a end where auth.uid() in(t.member_a,t.member_b) and family_private.chat_pair_allowed(p.id) order by t.created_at desc limit 100)x),'[]'::jsonb);
end $$;
