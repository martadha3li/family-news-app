begin;
create temp table migration_counts as select (select count(*)from public.profiles) profiles,(select count(*)from public.posts) posts,(select count(*)from public.comments) comments,(select count(*)from public.likes) likes,(select count(*)from public.announcements) ads,(select count(*)from family_private.chat_messages) messages;
create role family_api_executor nologin nosuperuser nobypassrls inherit;
grant authenticated to family_api_executor;
grant family_api_executor to postgres;
create table family_private.tenants(
 id uuid primary key default gen_random_uuid(),code text not null unique check(code ~ '^[0-9A-Za-z-]{2,20}$'),
 name text not null check(length(name) between 3 and 100),logo text,
 status text not null default 'pending' check(status in ('pending','active','suspended','rejected')),
 contact_phone text not null,contact_email text not null,
 fee_sar numeric(10,2) not null default 0 check(fee_sar>=0),payment_status text not null default 'unpaid' check(payment_status in ('unpaid','paid','waived')),
 notes text not null default '',created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(logo is null or (length(logo)<=280000 and logo ~ '^data:image/jpeg;base64,[A-Za-z0-9+/=]+$'))
);
insert into family_private.tenants(code,name,status,contact_phone,contact_email,payment_status)values('01','أخبار العائلة','active','غير محدد','martadha3li@gmail.com','waived');
create table family_private.platform_admins(user_id uuid primary key references auth.users(id));
insert into family_private.platform_admins select p.id from public.profiles p join auth.users u on u.id=p.id where p.is_root and lower(u.email)='martadha3li@gmail.com' and u.email_confirmed_at is not null;
alter table family_private.tenants enable row level security;alter table family_private.platform_admins enable row level security;
revoke all on family_private.tenants,family_private.platform_admins from public,anon,authenticated;
create temp table tenant_relations as
select c.conrelid,c.confrelid,c.conname,
 (select string_agg(quote_ident(a.attname),',' order by k.ord) from unnest(c.conkey) with ordinality k(num,ord) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num) local_cols,
 (select string_agg(quote_ident(a.attname),',' order by k.ord) from unnest(c.confkey) with ordinality k(num,ord) join pg_attribute a on a.attrelid=c.confrelid and a.attnum=k.num) ref_cols
from pg_constraint c where c.contype='f' and c.connamespace in ('public'::regnamespace,'family_private'::regnamespace) and c.confrelid in(select c.oid from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','family_private'));
-- Per-row scope, including existing records. Every existing row stays with 01.
do $$declare r record;old_tenant uuid:=(select id from family_private.tenants where code='01');begin
 for r in select schemaname,tablename from pg_tables where schemaname in('public','family_private') and tablename not in('tenants','platform_admins','push_config') loop
 execute format('alter table %I.%I add column tenant_id uuid not null default %L references family_private.tenants(id)',r.schemaname,r.tablename,old_tenant);
 end loop;
 for r in select * from tenant_relations where confrelid='public.kinship_options'::regclass loop execute format('alter table %s drop constraint %I',r.conrelid::regclass,r.conname);end loop;
end$$;
alter table public.family_settings drop constraint family_settings_pkey,add primary key(tenant_id,id);
alter table public.allowed_families drop constraint allowed_families_pkey,add primary key(tenant_id,name);
alter table public.kinship_options drop constraint kinship_options_pkey,add primary key(tenant_id,code);
alter table family_private.storage_limits drop constraint storage_limits_pkey,add primary key(tenant_id,id);
drop index public.one_family_root;
create unique index one_root_per_tenant on public.profiles(tenant_id) where is_root;
create function family_private.current_tenant() returns uuid language sql stable security definer set search_path='' as $$select p.tenant_id from public.profiles p join family_private.tenants t on t.id=p.tenant_id where p.id=auth.uid() and t.status='active'$$;
revoke all on function family_private.current_tenant() from public,anon;grant execute on function family_private.current_tenant() to authenticated,family_api_executor;
create function family_private.keep_tenant() returns trigger language plpgsql set search_path='' as $$begin if new.tenant_id is distinct from old.tenant_id and current_user<>'postgres' then raise exception 'لا يمكن نقل بيانات بين الكيانات';end if;return new;end$$;
revoke all on function family_private.keep_tenant() from public,anon,authenticated;
create function family_private.check_tenant_ref() returns trigger language plpgsql security definer set search_path='' as $$declare target uuid;value text:=to_jsonb(new)->>TG_ARGV[1];begin
 if value is not null then execute format('select tenant_id from %s where %I::text=$1',TG_ARGV[0]::oid::regclass,TG_ARGV[2])into target using value;
 if target is not null and target<>new.tenant_id then raise exception 'لا يمكن الربط بين كيانات مختلفة';end if;end if;return new;end$$;
revoke all on function family_private.check_tenant_ref() from public,anon,authenticated;
do $$declare r record;begin
 for r in select schemaname,tablename from pg_tables where schemaname in('public','family_private') and tablename not in('tenants','platform_admins','push_config') loop
 execute format('alter table %I.%I alter column tenant_id set default family_private.current_tenant()',r.schemaname,r.tablename);
 execute format('create index on %I.%I(tenant_id)',r.schemaname,r.tablename);
 execute format('alter table %I.%I enable row level security',r.schemaname,r.tablename);
 execute format('create policy tenant_boundary on %I.%I as restrictive for all to authenticated,family_api_executor using(tenant_id=(select family_private.current_tenant())) with check(tenant_id=(select family_private.current_tenant()))',r.schemaname,r.tablename);
 execute format('create policy tenant_rpc_access on %I.%I for all to family_api_executor using(true) with check(true)',r.schemaname,r.tablename);
 execute format('grant select,insert,update,delete on %I.%I to family_api_executor',r.schemaname,r.tablename);
 execute format('create trigger tenant_immutable before update on %I.%I for each row execute function family_private.keep_tenant()',r.schemaname,r.tablename);
 end loop;
 for r in select * from tenant_relations loop
 execute format('create unique index if not exists %I on %s(tenant_id,%s)','tenant_ref_'||left(md5(r.confrelid::text||r.ref_cols),24),r.confrelid::regclass,r.ref_cols);
 if r.confrelid='public.kinship_options'::regclass then
 execute format('alter table %s add constraint %I foreign key(tenant_id,%s) references %s(tenant_id,%s) deferrable initially deferred',r.conrelid::regclass,r.conname,r.local_cols,r.confrelid::regclass,r.ref_cols);
 else
 execute format('create trigger %I before insert or update on %s for each row execute function family_private.check_tenant_ref(%L,%L,%L)','tenant_'||r.conname,r.conrelid::regclass,r.confrelid::text,r.local_cols,r.ref_cols);
 end if;
 end loop;
end$$;
-- This role cannot log in, own tables, or bypass RLS. Existing checked RPCs run as it.
grant usage,create on schema public,family_private to family_api_executor;
grant usage on schema auth,storage to family_api_executor;
grant select(id,email,email_confirmed_at) on auth.users to family_api_executor;
create policy tenant_rpc_verified_users on auth.users for select to family_api_executor using(id=auth.uid() or exists(select 1 from public.profiles p where p.id=users.id and p.tenant_id=family_private.current_tenant()));
grant select,insert,update,delete on storage.objects to family_api_executor;
grant usage,select on all sequences in schema public,family_private to family_api_executor;
do $$declare r record;begin
 for r in select p.oid::regprocedure sig from pg_proc p where p.pronamespace='family_private'::regnamespace and p.prosecdef and p.proname not in('access_role','enroll','signup_sponsor','registration_valid','dispatch_push','push_backend','current_tenant','check_tenant_ref') loop
 execute format('alter function %s owner to family_api_executor',r.sig);
 end loop;
end$$;
grant execute on function family_private.normalize_name(text),family_private.phone_prefix(text),family_private.name_score(text,text),family_private.registration_valid(uuid) to family_api_executor;
-- The push client may read the public VAPID key only; secrets remain inaccessible.
grant select(id,public_key) on family_private.push_config to family_api_executor;
create policy rpc_push_public_key on family_private.push_config for select to family_api_executor using(true);
revoke create on schema public,family_private from family_api_executor;
-- Restrictive storage boundary applies even to administrator storage policies.
create policy tenant_storage_boundary on storage.objects as restrictive for all to authenticated,family_api_executor using(
 bucket_id not in('news-images','profile-images','chat-media','ad-images') or exists(select 1 from public.profiles p where p.id::text=(storage.foldername(name))[1] and p.tenant_id=family_private.current_tenant())
)with check(bucket_id not in('news-images','profile-images','chat-media','ad-images') or exists(select 1 from public.profiles p where p.id::text=(storage.foldername(name))[1] and p.tenant_id=family_private.current_tenant()));
create or replace function family_private.access_role() returns text language sql stable security definer set search_path='' as $$select p.role from public.profiles p join auth.users u on u.id=p.id join family_private.tenants t on t.id=p.tenant_id where p.id=auth.uid() and p.status='active' and u.email_confirmed_at is not null and t.status='active'$$;
-- Explicit scoping in registration triggers, where there is no signed-in user yet.
create or replace function family_private.registration_valid(member uuid) returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from family_private.member_details d join auth.users u on u.id=d.id join public.family_settings s on s.tenant_id=d.tenant_id where s.id and not s.endorsements_enabled and d.id=member and u.email_confirmed_at is not null and d.phone is not null and d.gender is not null and cardinality(string_to_array(family_private.normalize_name(d.full_name),' '))=4 and exists(select 1 from public.allowed_families f where f.tenant_id=d.tenant_id and family_private.normalize_name(f.name)=split_part(family_private.normalize_name(d.full_name),' ',4)) and(d.gender='male' or(d.relationship is not null and exists(select 1 from family_private.member_details r join public.profiles p on p.id=r.id where r.tenant_id=d.tenant_id and r.gender='male' and p.status='active' and family_private.normalize_name(r.full_name)=family_private.normalize_name(d.reference_name)))))$$;
create or replace function family_private.enroll() returns trigger language plpgsql security definer set search_path='' as $$declare tid uuid;begin
 select tenant_id into tid from public.profiles where id=new.id;
 if tid is null then
  select id into tid from family_private.tenants where code=coalesce(nullif(new.raw_user_meta_data->>'family_code',''),'01') and status='active';
  if tid is null then raise exception 'الكيان غير متاح للتسجيل';end if;
 end if;
 insert into public.profiles(id,display_name,tenant_id)values(new.id,left(coalesce(nullif(new.raw_user_meta_data->>'display_name',''),'عضو'),80),tid)on conflict(id)do nothing;
 if TG_OP='INSERT' then insert into family_private.member_details(id,tenant_id,full_name,phone,gender,reference_name,relationship)values(new.id,tid,left(coalesce(new.raw_user_meta_data->>'full_name',''),250),nullif(new.raw_user_meta_data->>'phone',''),nullif(new.raw_user_meta_data->>'gender',''),left(new.raw_user_meta_data->>'reference_name',250),nullif(new.raw_user_meta_data->>'relationship',''));end if;
 if new.email_confirmed_at is not null and exists(select 1 from family_private.tenants where id=tid and lower(contact_email)=lower(new.email)) and not exists(select 1 from public.profiles where tenant_id=tid and is_root and id<>new.id) then
 update public.profiles set role='admin',status='active',is_root=true where id=new.id;
 elsif new.email_confirmed_at is not null and (select auto_activate from public.family_settings where tenant_id=tid and id) and family_private.registration_valid(new.id) then update public.profiles set status='active' where id=new.id and status='pending';end if;
 return new;
end$$;
create or replace function family_private.signup_sponsor() returns trigger language plpgsql security definer set search_path='' as $$declare hint text:=trim(new.raw_user_meta_data->>'sponsor_hint');person uuid;matches integer;tid uuid;begin
 select tenant_id into tid from public.profiles where id=new.id;
 if not(select endorsements_enabled from public.family_settings where tenant_id=tid and id) or coalesce(hint,'')='' then return new;end if;
 if hint ~ '^05[0-9]{8}$' then hint='+966'||substr(hint,2);end if;
 select count(*),min(p.id::text)::uuid into matches,person from public.profiles p join family_private.member_details d on d.id=p.id join auth.users u on u.id=p.id where p.tenant_id=tid and p.id<>new.id and p.status='active' and u.email_confirmed_at is not null and(family_private.normalize_name(p.display_name)=family_private.normalize_name(hint)or d.phone=hint);
 if matches=1 then insert into family_private.endorsements(tenant_id,applicant_id,sponsor_id)values(tid,new.id,person)on conflict do nothing;end if;return new;
end$$;
-- Scope the lookup upsert to its new composite key.
do $$declare definition text;begin select pg_get_functiondef('family_private.family_action(text,jsonb)'::regprocedure) into definition;definition:=replace(definition,'on conflict(code)','on conflict(tenant_id,code)');execute definition;end$$;
-- Public directory exposes branding only, never contacts, fees or membership.
create function public.tenant_directory(term text default '') returns jsonb language sql stable security definer set search_path='' as $$select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select id,code,name,logo from family_private.tenants where status='active' and (code=trim(term) or name ilike '%'||left(trim(term),80)||'%') order by(code=trim(term))desc,code limit 30)x$$;
create function public.tenant_current() returns jsonb language sql stable security definer set search_path='' as $$select to_jsonb(x) from(select t.id,t.code,t.name,t.logo,t.status from family_private.tenants t join public.profiles p on p.tenant_id=t.id where p.id=auth.uid())x$$;
create function public.tenant_kinship(code text) returns jsonb language sql stable security definer set search_path='' as $$select coalesce(jsonb_agg(jsonb_build_object('code',k.code,'label',k.label,'generation',k.generation)),'[]') from public.kinship_options k join family_private.tenants t on t.id=k.tenant_id where t.code=tenant_kinship.code and t.status='active' and k.enabled and k.for_reference$$;
create function public.tenant_request(data jsonb) returns text language plpgsql security definer set search_path='' as $$declare email text:=lower(trim(data->>'email'));phone text:=trim(data->>'phone');label text:=trim(data->>'name');pic text:=nullif(data->>'logo','');begin
 if length(label)not between 3 and 100 or email!~'^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' or length(email)>254 or phone!~'^\+[1-9][0-9]{7,14}$' or pic is null then raise exception 'أدخل اسم العائلة وشعارها وبريد التواصل ورقم الجوال الدولي';end if;
 perform pg_advisory_xact_lock(hashtextextended('tenant-request-'||email,0));
 if (select count(*) from family_private.tenants where created_at>now()-interval '1 hour')>=100 then raise exception 'طلبات كثيرة الآن. حاول لاحقًا';end if;
 if exists(select 1 from family_private.tenants where lower(contact_email)=email and status in('pending','active')) then raise exception 'يوجد طلب قيد المراجعة أو كيان مسجل بهذا البريد';end if;
 insert into family_private.tenants(code,name,logo,contact_phone,contact_email)values('R-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),label,pic,phone,email);
 return 'تم استلام طلبك. ينتظر مراجعة إدارة المنصة والتواصل معك بشأن الرسوم والتفعيل.';
end$$;
create function family_private.platform_allowed() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from family_private.platform_admins a join auth.users u on u.id=a.user_id where a.user_id=auth.uid() and u.email_confirmed_at is not null)$$;
create function public.platform_action(action text,data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$declare tid uuid;v record;begin
 if not family_private.platform_allowed() then raise exception 'إدارة المنصة فقط';end if;
 if action='check' then return 'true';
 elsif action='list' then return coalesce((select jsonb_agg(to_jsonb(x)-'logo')from(select t.*,(select count(*)from public.profiles p where p.tenant_id=t.id) members,(select count(*)from public.posts p where p.tenant_id=t.id) posts from family_private.tenants t order by t.created_at desc limit 500)x),'[]');
 elsif action='save' then
 tid=(data->>'id')::uuid;
 select * into v from family_private.tenants where id=tid for update;if not found then raise exception 'الكيان غير موجود';end if;
 if data->>'status'='active' and coalesce(data->>'payment_status',v.payment_status)not in('paid','waived') then raise exception 'سجل سداد الرسوم أو الإعفاء قبل التفعيل';end if;
 if (data->>'code'='01' and v.code<>'01')or(v.code='01' and coalesce(data->>'code','01')<>'01') then raise exception 'الكود 01 محجوز';end if;
 update family_private.tenants set code=coalesce(nullif(trim(data->>'code'),''),code),name=coalesce(nullif(trim(data->>'name'),''),name),status=coalesce(data->>'status',status),fee_sar=coalesce((data->>'fee_sar')::numeric,fee_sar),payment_status=coalesce(data->>'payment_status',payment_status),notes=left(coalesce(data->>'notes',notes),2000),updated_at=now() where id=tid;
 insert into public.family_settings(tenant_id,id)values(tid,true)on conflict do nothing;
 insert into family_private.storage_limits(tenant_id,id)values(tid,true)on conflict do nothing;
 insert into public.kinship_options(tenant_id,code,label,generation,for_reference,enabled)select tid,code,label,generation,for_reference,enabled from public.kinship_options where tenant_id=(select id from family_private.tenants where code='01')on conflict do nothing;
 return 'true';
 else raise exception 'إجراء غير معروف';end if;
end$$;
revoke all on function public.tenant_directory(text),public.tenant_current(),public.tenant_kinship(text),public.tenant_request(jsonb),public.platform_action(text,jsonb),family_private.platform_allowed() from public,anon,authenticated;
grant execute on function public.tenant_directory(text),public.tenant_kinship(text),public.tenant_request(jsonb) to anon,authenticated;
grant execute on function public.tenant_current(),public.platform_action(text,jsonb) to authenticated;
notify pgrst,'reload schema';
-- Compatibility for older single-family signup clients: public relation labels from 01 only.
do $$begin execute format('create policy legacy_public_kinship on public.kinship_options as restrictive for select to anon using(tenant_id=%L)',(select id from family_private.tenants where code='01'));end$$;
-- Background delivery remains service-only, scoped per job rather than a logged-in member.
do $$declare definition text;begin
 select pg_get_functiondef('family_private.push_backend(text,jsonb)'::regprocedure)into definition;
 definition:=replace(definition,'from public.family_settings where id)','from public.family_settings where id and tenant_id=j.tenant_id)');
 definition:=replace(definition,'p.status=''active''','p.status=''active'' and p.tenant_id=j.tenant_id and exists(select 1 from family_private.tenants t where t.id=j.tenant_id and t.status=''active'')');
 definition:=replace(definition,'from public.posts where id::text=j.item','from public.posts where tenant_id=j.tenant_id and id::text=j.item');
 definition:=replace(definition,'m.id::text=j.item','m.tenant_id=j.tenant_id and m.id::text=j.item');
 execute definition;
end$$;

do $$begin
 if exists(select 1 from migration_counts c where c.profiles<>(select count(*)from public.profiles) or c.posts<>(select count(*)from public.posts) or c.comments<>(select count(*)from public.comments) or c.likes<>(select count(*)from public.likes) or c.ads<>(select count(*)from public.announcements) or c.messages<>(select count(*)from family_private.chat_messages))then raise exception 'Migration changed record counts';end if;
end$$;

commit;
