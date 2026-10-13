begin;
create table public.family_settings(id boolean primary key default true check(id),chat_enabled boolean not null default true,public_chat_enabled boolean not null default true,private_chat_enabled boolean not null default true,restrict_gender_chat boolean not null default false,journalist_approval boolean not null default true,auto_activate boolean not null default true);
insert into public.family_settings(id) values(true);
alter table public.family_settings enable row level security;
create policy settings_read on public.family_settings for select to authenticated using((select public.my_role()) is not null);
create policy settings_manage on public.family_settings for update to authenticated using((select public.my_role())='admin') with check((select public.my_role())='admin');
grant select,update on public.family_settings to authenticated;
create table public.allowed_families(name text primary key check(char_length(name) between 2 and 80));
alter table public.allowed_families enable row level security;
create policy families_read on public.allowed_families for select to authenticated using((select public.my_role()) is not null);
create policy families_manage on public.allowed_families for all to authenticated using((select public.my_role())='admin') with check((select public.my_role())='admin');
grant select,insert,delete on public.allowed_families to authenticated;
create table family_private.member_details(id uuid primary key references public.profiles(id) on delete cascade,full_name text not null default '',phone text unique,gender text check(gender in ('male','female')),reference_name text,relationship text check(relationship in ('father','husband','brother','uncle','maternal_uncle')),check(phone is null or phone ~ '^\+[1-9][0-9]{7,14}$'));
alter table family_private.member_details enable row level security;
create table family_private.chat_threads(id uuid primary key default gen_random_uuid(),member_a uuid not null references public.profiles(id),member_b uuid not null references public.profiles(id),created_at timestamptz not null default now(),check(member_a<member_b),unique(member_a,member_b));
create table family_private.chat_messages(id bigint generated always as identity primary key,thread_id uuid references family_private.chat_threads(id) on delete cascade,sender_id uuid not null references public.profiles(id),body text not null check(char_length(body) between 1 and 2000),created_at timestamptz not null default now());
alter table family_private.chat_threads enable row level security;
alter table family_private.chat_messages enable row level security;
create index chat_public_recent on family_private.chat_messages(created_at desc,id desc) where thread_id is null;
create index chat_thread_recent on family_private.chat_messages(thread_id,id desc);
create index chat_sender_recent on family_private.chat_messages(sender_id,created_at desc);
alter table public.posts add column moderation_status text not null default 'draft' check(moderation_status in ('draft','pending','published','rejected'));
update public.posts set moderation_status=case when published then 'published' else 'draft' end;
create function family_private.normalize_name(s text) returns text language sql immutable set search_path='' as $$select regexp_replace(translate(trim(s),'أإآى','اااي'),'[[:space:]]+',' ','g')$$;
create function family_private.registration_valid(member uuid) returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from family_private.member_details d join auth.users u on u.id=d.id where d.id=member and u.email_confirmed_at is not null and d.phone is not null and d.gender is not null and cardinality(string_to_array(family_private.normalize_name(d.full_name),' '))=4 and exists(select 1 from public.allowed_families f where family_private.normalize_name(f.name)=split_part(family_private.normalize_name(d.full_name),' ',4)) and (d.gender='male' or (d.relationship is not null and exists(select 1 from family_private.member_details r join public.profiles p on p.id=r.id where r.gender='male' and p.status='active' and family_private.normalize_name(r.full_name)=family_private.normalize_name(d.reference_name)))))
$$;
create or replace function family_private.enroll() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,display_name) values(new.id,left(coalesce(nullif(new.raw_user_meta_data->>'display_name',''),'عضو'),80)) on conflict(id) do nothing;
 if TG_OP='INSERT' then
  insert into family_private.member_details(id,full_name,phone,gender,reference_name,relationship) values(new.id,left(coalesce(new.raw_user_meta_data->>'full_name',''),250),nullif(new.raw_user_meta_data->>'phone',''),nullif(new.raw_user_meta_data->>'gender',''),left(new.raw_user_meta_data->>'reference_name',250),nullif(new.raw_user_meta_data->>'relationship',''));
 end if;
 if lower(new.email)='martadha3li@gmail.com' and new.email_confirmed_at is not null and not exists(select 1 from public.profiles where is_root and id<>new.id) then
  update public.profiles set role='admin',status='active',is_root=true where id=new.id;
 elsif new.email_confirmed_at is not null and (select auto_activate from public.family_settings where id) and family_private.registration_valid(new.id) then
  update public.profiles set status='active' where id=new.id and status='pending';
 end if;
 return new;
end $$;
insert into family_private.member_details(id) select id from public.profiles on conflict do nothing;
create function family_private.profile_get() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول';end if;
 return (select to_jsonb(d)||jsonb_build_object('display_name',p.display_name,'status',p.status,'role',p.role) from family_private.member_details d join public.profiles p on p.id=d.id where d.id=auth.uid());
end $$;
create function family_private.profile_save(data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare oldrow family_private.member_details; g text; n text;begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول';end if;
 select * into oldrow from family_private.member_details where id=auth.uid() for update;
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
create function family_private.member_detail(member uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if family_private.access_role()<>'admin' or family_private.access_role() is null then raise exception 'للمدير فقط';end if;
 return (select to_jsonb(d)||jsonb_build_object('email',u.email,'email_confirmed',u.email_confirmed_at is not null) from family_private.member_details d join auth.users u on u.id=d.id where d.id=member);
end $$;
create function family_private.chat_pair_allowed(other uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and family_private.access_role() is not null and exists(select 1 from public.family_settings s join public.profiles p on p.id=other where s.id and s.chat_enabled and p.status='active' and exists(select 1 from auth.users u where u.id=p.id and u.email_confirmed_at is not null) and (not s.restrict_gender_chat or exists(select 1 from family_private.member_details me join family_private.member_details them on them.id=other and them.gender=me.gender where me.id=auth.uid() and me.gender is not null)))
$$;
create function family_private.chat_search(term text) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if family_private.access_role() is null then raise exception 'حساب غير معتمد';end if;
 if not (select chat_enabled and private_chat_enabled from public.family_settings where id) then return '[]'::jsonb;end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (select id,display_name from public.profiles where id<>auth.uid() and family_private.chat_pair_allowed(id) and display_name ilike '%'||left(term,80)||'%' order by display_name limit 30)x),'[]'::jsonb);
end $$;
create function family_private.chat_open(other uuid) returns uuid language plpgsql security definer set search_path='' as $$declare t uuid;begin
 if other=auth.uid() or not family_private.chat_pair_allowed(other) or not (select private_chat_enabled from public.family_settings where id) then raise exception 'المحادثة غير متاحة';end if;
 insert into family_private.chat_threads(member_a,member_b) values(least(auth.uid(),other),greatest(auth.uid(),other)) on conflict(member_a,member_b) do update set member_a=excluded.member_a returning id into t;return t;
end $$;
create function family_private.chat_list() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if family_private.access_role() is null then raise exception 'حساب غير معتمد';end if;
 if not (select chat_enabled and private_chat_enabled from public.family_settings where id) then return '[]'::jsonb;end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (select t.id,p.display_name,p.id as member_id from family_private.chat_threads t join public.profiles p on p.id=case when t.member_a=auth.uid() then t.member_b else t.member_a end where auth.uid() in(t.member_a,t.member_b) and family_private.chat_pair_allowed(p.id) order by t.created_at desc limit 100)x),'[]'::jsonb);
end $$;
create function family_private.chat_read(thread uuid,before_id bigint default null) returns jsonb language plpgsql stable security definer set search_path='' as $$declare peer uuid;begin
 if family_private.access_role() is null or not (select chat_enabled from public.family_settings where id) then raise exception 'الدردشة موقوفة';end if;
 if thread is null then
  if not (select public_chat_enabled from public.family_settings where id) then raise exception 'الدردشة العامة موقوفة';end if;
 else
  select case when member_a=auth.uid() then member_b else member_a end into peer from family_private.chat_threads where id=thread and auth.uid() in(member_a,member_b);
  if peer is null or not family_private.chat_pair_allowed(peer) or not (select private_chat_enabled from public.family_settings where id) then raise exception 'المحادثة غير متاحة';end if;
 end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from (select m.id,m.sender_id,m.body,m.created_at,p.display_name from family_private.chat_messages m join public.profiles p on p.id=m.sender_id where m.thread_id is not distinct from thread and (before_id is null or m.id<before_id) and family_private.chat_pair_allowed(m.sender_id) order by m.id desc limit 50)x),'[]'::jsonb);
end $$;
create function family_private.chat_send(thread uuid,message text) returns bigint language plpgsql security definer set search_path='' as $$declare mid bigint;begin
 perform family_private.chat_read(thread,null);
 if not family_private.chat_pair_allowed(auth.uid()) then raise exception 'أكمل الجنس في ملفك أولًا';end if;
 if exists(select 1 from family_private.chat_messages where sender_id=auth.uid() and created_at>now()-interval '2 seconds') then raise exception 'انتظر لحظة بين الرسائل';end if;
 insert into family_private.chat_messages(thread_id,sender_id,body) values(thread,auth.uid(),trim(message)) returning id into mid;return mid;
end $$;
create function family_private.moderate_post() returns trigger language plpgsql security definer set search_path='' as $$declare r text;begin
 if auth.uid() is null then return new;end if;
 r=family_private.access_role();
 if TG_OP='UPDATE' and new.author_id<>old.author_id then raise exception 'لا يمكن تغيير صاحب الخبر';end if;
 if r='journalist' then
  if new.author_id<>auth.uid() then raise exception 'الخبر ليس لك';end if;
  if new.published then
   if (select journalist_approval from public.family_settings where id) then new.published=false;new.moderation_status='pending';else new.moderation_status='published';end if;
  elsif TG_OP='INSERT' or new.title is distinct from old.title or new.body is distinct from old.body or new.image_path is distinct from old.image_path then new.moderation_status='draft';end if;
 elsif r='admin' then
  if new.published then new.moderation_status='published';elsif new.moderation_status='published' then new.moderation_status='draft';end if;
 else raise exception 'النشر للمدير والصحفي فقط';end if;
 return new;
end $$;
create trigger family_moderate before insert or update on public.posts for each row execute function family_private.moderate_post();
create function public.profile_get() returns jsonb language sql set search_path='' as $$select family_private.profile_get()$$;
create function public.profile_save(data jsonb) returns jsonb language sql set search_path='' as $$select family_private.profile_save(data)$$;
create function public.member_detail(member uuid) returns jsonb language sql set search_path='' as $$select family_private.member_detail(member)$$;
create function public.chat_search(term text) returns jsonb language sql set search_path='' as $$select family_private.chat_search(term)$$;
create function public.chat_open(other uuid) returns uuid language sql set search_path='' as $$select family_private.chat_open(other)$$;
create function public.chat_list() returns jsonb language sql set search_path='' as $$select family_private.chat_list()$$;
create function public.chat_read(thread uuid,before_id bigint default null) returns jsonb language sql set search_path='' as $$select family_private.chat_read(thread,before_id)$$;
create function public.chat_send(thread uuid,message text) returns bigint language sql set search_path='' as $$select family_private.chat_send(thread,message)$$;
revoke all on function family_private.normalize_name(text),family_private.registration_valid(uuid),family_private.profile_get(),family_private.profile_save(jsonb),family_private.member_detail(uuid),family_private.chat_pair_allowed(uuid),family_private.chat_search(text),family_private.chat_open(uuid),family_private.chat_list(),family_private.chat_read(uuid,bigint),family_private.chat_send(uuid,text),family_private.moderate_post() from public,anon,authenticated;
grant execute on function family_private.access_role(),family_private.profile_get(),family_private.profile_save(jsonb),family_private.member_detail(uuid),family_private.chat_search(text),family_private.chat_open(uuid),family_private.chat_list(),family_private.chat_read(uuid,bigint),family_private.chat_send(uuid,text) to authenticated;
revoke all on function public.profile_get(),public.profile_save(jsonb),public.member_detail(uuid),public.chat_search(text),public.chat_open(uuid),public.chat_list(),public.chat_read(uuid,bigint),public.chat_send(uuid,text) from public,anon;
grant execute on function public.profile_get(),public.profile_save(jsonb),public.member_detail(uuid),public.chat_search(text),public.chat_open(uuid),public.chat_list(),public.chat_read(uuid,bigint),public.chat_send(uuid,text) to authenticated;
create policy private_details_no_direct_access on family_private.member_details for all to authenticated using(false) with check(false);
create policy private_threads_no_direct_access on family_private.chat_threads for all to authenticated using(false) with check(false);
create policy private_messages_no_direct_access on family_private.chat_messages for all to authenticated using(false) with check(false);
commit;
