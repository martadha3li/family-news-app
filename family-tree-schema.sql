create table public.kinship_options(code text primary key check(code ~ '^[a-z][a-z0-9_]{0,39}$'),label text not null check(char_length(label) between 1 and 60),generation int not null check(generation between -4 and 4),for_reference boolean not null default false,enabled boolean not null default true);
alter table public.kinship_options enable row level security;
revoke all on public.kinship_options from anon,authenticated;
grant select on public.kinship_options to anon,authenticated;
grant insert,update on public.kinship_options to authenticated;
create policy kinship_read on public.kinship_options for select to anon,authenticated using(true);
create policy kinship_insert on public.kinship_options for insert to authenticated with check((select family_private.access_role())='admin');
create policy kinship_update on public.kinship_options for update to authenticated using((select family_private.access_role())='admin') with check((select family_private.access_role())='admin');
insert into public.kinship_options(code,label,generation,for_reference) values ('father','أب',-1,true),('husband','زوج',0,true),('brother','أخ',0,true),('uncle','عم',-1,true),('maternal_uncle','خال',-1,true),('mother','أم',-1,false),('grandfather','جد',-2,false),('grandmother','جدة',-2,false),('sister','أخت',0,false),('wife','زوجة',0,false),('son','ابن',1,false),('daughter','ابنة',1,false),('cousin','ابن / ابنة عم',0,false),('grandchild','حفيد / حفيدة',2,false);
alter table family_private.member_details drop constraint member_details_relationship_check;
alter table family_private.member_details add constraint member_details_relationship_fkey foreign key(relationship) references public.kinship_options(code);
create table family_private.personal_kinship(owner_id uuid references public.profiles(id) on delete cascade,member_id uuid references public.profiles(id) on delete cascade,relation text references public.kinship_options(code),created_at timestamptz not null default now(),primary key(owner_id,member_id),check(owner_id<>member_id));
alter table family_private.personal_kinship enable row level security;
create policy kinship_private_lock on family_private.personal_kinship for all using(false) with check(false);
revoke all on family_private.personal_kinship from public,anon,authenticated;
create function family_private.phone_prefix(term text) returns text language sql immutable set search_path='' as $$select case when translate(trim(term),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789') ~ '^0[0-9]*$' then '+966'||substr(translate(trim(term),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789'),2) else translate(trim(term),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789') end$$;
create or replace function family_private.chat_search(term text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare q text:=trim(left(term,80));begin
 if family_private.access_role() is null then raise exception 'حساب غير معتمد';end if;
 if q='' or not(select chat_enabled and private_chat_enabled from public.family_settings where id) then return '[]';end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from(select p.id,p.display_name,p.avatar_path from public.profiles p join family_private.member_details d on d.id=p.id where p.id<>auth.uid() and family_private.chat_pair_allowed(p.id) and (strpos(family_private.normalize_name(p.display_name),family_private.normalize_name(q))>0 or (q ~ '^[+0-9٠-٩۰-۹]+$' and starts_with(d.phone,family_private.phone_prefix(q)))) order by p.display_name limit 30)x),'[]');
end$$;
create function family_private.name_score(a text,b text) returns float language plpgsql immutable set search_path='' as $$
declare x text:=left(family_private.normalize_name(a),80);y text:=left(family_private.normalize_name(b),80);v int[];w int[];i int;j int;begin
 if x='' or y='' or x is null or y is null then return 0;end if;
 v:=array(select generate_series(0,length(y)));
 for i in 1..length(x) loop w:=array[i];for j in 1..length(y) loop w:=array_append(w,least(w[j]+1,v[j+1]+1,v[j]+case when substr(x,i,1)=substr(y,j,1) then 0 else 1 end));end loop;v:=w;end loop;
 return 1-v[length(y)+1]::float/greatest(length(x),length(y));
end$$;
create function family_private.family_action(action text,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();own text[];q text:=trim(left(payload->>'term',80));target uuid;rel text;begin
 if uid is null or not exists(select 1 from public.profiles where id=uid and status in('pending','active')) or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null) then raise exception 'أكد بريدك وسجل الدخول';end if;
 if action='referees' then
 if coalesce(q,'')='' then return '[]';end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from(select p.id,p.display_name from public.profiles p join family_private.member_details d on d.id=p.id where p.status='active' and d.gender='male' and p.id<>uid and (strpos(family_private.normalize_name(p.display_name),family_private.normalize_name(q))>0 or (q ~ '^[+0-9٠-٩۰-۹]+$' and starts_with(d.phone,family_private.phone_prefix(q)))) order by p.display_name limit 10)x),'[]');
 end if;
 if family_private.access_role() is null then raise exception 'شجرة العائلة للأعضاء المعتمدين';end if;
 if action='similar' then
 select string_to_array(family_private.normalize_name(full_name),' ') into own from family_private.member_details where id=uid;
 if cardinality(own)<>4 then return '[]';end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from(select p.id,p.display_name,round((100*(family_private.name_score(own[2],split_part(family_private.normalize_name(d.full_name),' ',2))+family_private.name_score(own[3],split_part(family_private.normalize_name(d.full_name),' ',3))+family_private.name_score(own[4],split_part(family_private.normalize_name(d.full_name),' ',4)))/3)::numeric,1) as score from public.profiles p join family_private.member_details d on d.id=p.id where p.id<>uid and p.status='active' and cardinality(string_to_array(family_private.normalize_name(d.full_name),' '))=4)x where score>=70),'[]');
 elsif action='tree' then
 return coalesce((select jsonb_agg(to_jsonb(x)) from(select p.id,p.display_name,k.relation,o.label,o.generation from family_private.personal_kinship k join public.profiles p on p.id=k.member_id join public.kinship_options o on o.code=k.relation where k.owner_id=uid and p.status='active' order by o.generation,p.display_name)x),'[]');
 elsif action='link' then
 target=(payload->>'member')::uuid;rel=payload->>'relation';
 if target=uid or not exists(select 1 from public.profiles where id=target and status='active') or not exists(select 1 from public.kinship_options where code=rel and enabled) then raise exception 'اختر عضوًا معتمدًا وصلة قرابة مفعّلة';end if;
 insert into family_private.personal_kinship(owner_id,member_id,relation) values(uid,target,rel) on conflict(owner_id,member_id) do update set relation=excluded.relation;return 'true';
 elsif action='unlink' then delete from family_private.personal_kinship where owner_id=uid and member_id=(payload->>'member')::uuid;return 'true';
 else raise exception 'إجراء غير معروف';end if;
end$$;
create function public.family_action(action text,payload jsonb default '{}') returns jsonb language sql set search_path='' as $$select family_private.family_action(action,payload)$$;
revoke all on function family_private.phone_prefix(text),family_private.name_score(text,text),family_private.family_action(text,jsonb),public.family_action(text,jsonb) from public,anon,authenticated;
grant execute on function family_private.family_action(text,jsonb),public.family_action(text,jsonb) to authenticated;

create or replace function family_private.profile_save(data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare oldrow family_private.member_details; g text; n text;begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول';end if;
 select * into oldrow from family_private.member_details where id=auth.uid() for update;
 if oldrow.phone is not null and oldrow.phone is distinct from data->>'phone' then raise exception 'تغيير رقم الجوال يتطلب طلبًا للمدير';end if;
 g=data->>'gender';n=family_private.normalize_name(data->>'full_name');
 if cardinality(string_to_array(n,' '))<>4 or g not in ('male','female') or g is null then raise exception 'أدخل الاسم الرباعي والجنس';end if;
 if coalesce(data->>'phone','') !~ '^\+[1-9][0-9]{7,14}$' then raise exception 'أدخل رقم الجوال بصيغة دولية';end if;
 if oldrow.gender is not null and oldrow.gender<>g then raise exception 'تغيير الجنس يحتاج مراجعة المدير';end if;
 if g='female' and (coalesce(data->>'reference_name','')='' or (oldrow.relationship is distinct from data->>'relationship' and not exists(select 1 from public.kinship_options where code=data->>'relationship' and for_reference and enabled))) then raise exception 'أدخل اسم المعرّف وصلة القرابة';end if;
 update family_private.member_details set full_name=n,phone=nullif(data->>'phone',''),gender=g,reference_name=data->>'reference_name',relationship=nullif(data->>'relationship','') where id=auth.uid();
 update public.profiles set display_name=n where id=auth.uid();
 if (select auto_activate from public.family_settings where id) and family_private.registration_valid(auth.uid()) then update public.profiles set status='active' where id=auth.uid() and status='pending';end if;
 return family_private.profile_get();
exception when unique_violation then raise exception 'رقم الجوال مسجل لحساب آخر';end $$;

