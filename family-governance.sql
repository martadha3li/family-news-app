begin;
grant create on schema family_private to family_api_executor;
alter table family_private.tenants add column login_access text not null default 'allowed' check(login_access in('allowed','suspended','blocked')),add column login_suspended_until timestamptz;
alter table public.family_settings add column trusted_chat_enabled boolean not null default true,add column kinship_chat_enabled boolean not null default true;
alter table public.kinship_options add column allow_private_chat boolean not null default false;
alter table family_private.personal_kinship add column confirmed_by uuid references public.profiles(id),add column confirmed_at timestamptz;
insert into public.kinship_options(tenant_id,code,label,generation,allow_private_chat)select t.id,v.code,v.label,v.generation,true from family_private.tenants t cross join(values('maternal_aunt','خالة',-1),('paternal_aunt','عمة',-1),('granddaughter_son','بنت الابن',2),('granddaughter_daughter','بنت البنت',2))v(code,label,generation)on conflict do nothing;
update public.kinship_options set allow_private_chat=true where code in('father','mother','grandfather','grandmother','brother','sister','husband','wife','son','daughter','maternal_aunt','paternal_aunt','granddaughter_son','granddaughter_daughter');
create function family_private.tenant_available(tid uuid)returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from family_private.tenants t where t.id=tid and t.status='active' and(t.login_access='allowed'or(t.login_access='suspended'and t.login_suspended_until<=now())))$$;
create function family_private.tenant_writable(tid uuid)returns boolean language sql stable security definer set search_path='' as $$select family_private.tenant_available(tid)and exists(select 1 from family_private.tenants t where t.id=tid and(t.subscription_ends_at is null or t.subscription_ends_at>now()))$$;
revoke all on function family_private.tenant_available(uuid),family_private.tenant_writable(uuid)from public,anon;grant execute on function family_private.tenant_available(uuid),family_private.tenant_writable(uuid)to authenticated,family_api_executor;
create or replace function family_private.current_tenant()returns uuid language sql stable security definer set search_path='' as $$select p.tenant_id from public.profiles p where p.id=auth.uid()and family_private.tenant_available(p.tenant_id)$$;
create or replace function family_private.access_role()returns text language sql stable security definer set search_path='' as $$select p.role from public.profiles p join auth.users u on u.id=p.id where p.id=auth.uid()and p.status='active'and u.email_confirmed_at is not null and family_private.tenant_available(p.tenant_id)$$;
create or replace function public.tenant_current()returns jsonb language sql stable security definer set search_path='' as $$select to_jsonb(x)from(select t.id,t.code,t.name,t.logo,case when family_private.tenant_available(t.id)then t.status else 'suspended'end as status,t.subscription_ends_at,not family_private.tenant_writable(t.id)as read_only from family_private.tenants t join public.profiles p on p.tenant_id=t.id where p.id=auth.uid())x$$;
-- Restrictive write policies apply to REST, old app versions and scoped security-definer RPCs.
do $$declare r record;begin
 for r in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_attribute a on a.attrelid=c.oid and a.attname='tenant_id'and not a.attisdropped where n.nspname in('public','family_private')and c.relkind='r'loop
 execute format('create policy subscription_insert on %I.%I as restrictive for insert to authenticated,family_api_executor with check(family_private.tenant_writable(tenant_id))',r.nspname,r.relname);
 execute format('create policy subscription_update on %I.%I as restrictive for update to authenticated,family_api_executor using(family_private.tenant_writable(tenant_id))with check(family_private.tenant_writable(tenant_id))',r.nspname,r.relname);
 execute format('create policy subscription_delete on %I.%I as restrictive for delete to authenticated,family_api_executor using(family_private.tenant_writable(tenant_id))',r.nspname,r.relname);
 end loop;
end$$;
create policy subscription_storage_insert on storage.objects as restrictive for insert to authenticated,family_api_executor with check(bucket_id not in('news-images','profile-images','chat-media','ad-images')or family_private.tenant_writable(family_private.current_tenant()));
create policy subscription_storage_update on storage.objects as restrictive for update to authenticated,family_api_executor using(bucket_id not in('news-images','profile-images','chat-media','ad-images')or family_private.tenant_writable(family_private.current_tenant()))with check(bucket_id not in('news-images','profile-images','chat-media','ad-images')or family_private.tenant_writable(family_private.current_tenant()));
create policy subscription_storage_delete on storage.objects as restrictive for delete to authenticated,family_api_executor using(bucket_id not in('news-images','profile-images','chat-media','ad-images')or family_private.tenant_writable(family_private.current_tenant()));
create function family_private.trusted_pair(other uuid)returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.profiles me join public.profiles them on them.id=other and them.tenant_id=me.tenant_id join public.family_settings s on s.tenant_id=me.tenant_id and s.id where me.id=auth.uid()and me.status='active'and them.status='active'and family_private.tenant_available(me.tenant_id)and(
(s.trusted_chat_enabled and exists(select 1 from family_private.endorsements e where e.tenant_id=me.tenant_id and e.status='approved'and((e.applicant_id=me.id and e.sponsor_id=other)or(e.sponsor_id=me.id and e.applicant_id=other))))or
(s.kinship_chat_enabled and exists(select 1 from family_private.personal_kinship k join public.kinship_options o on o.tenant_id=k.tenant_id and o.code=k.relation where k.tenant_id=me.tenant_id and k.confirmed_at is not null and k.confirmed_by is not null and o.enabled and o.allow_private_chat and((k.owner_id=me.id and k.member_id=other)or(k.member_id=me.id and k.owner_id=other))))))$$;
revoke all on function family_private.trusted_pair(uuid)from public,anon;grant execute on function family_private.trusted_pair(uuid)to authenticated,family_api_executor;
-- Keep public chat and groups separated by gender. Exceptions apply to private conversations only.
create function family_private.chat_group_pair_allowed(other uuid)returns boolean language sql stable security definer set search_path='' as $$select false$$;
do $$declare def text;begin
 select pg_get_functiondef('family_private.chat_pair_allowed(uuid)'::regprocedure)into def;
 execute replace(def,'FUNCTION family_private.chat_pair_allowed','FUNCTION family_private.chat_group_pair_allowed');
 def=replace(def,'not s.restrict_gender_chat or exists','not s.restrict_gender_chat or family_private.trusted_pair(other)or exists');execute def;
 select pg_get_functiondef('family_private.group_action(text,jsonb)'::regprocedure)into def;execute replace(def,'family_private.chat_pair_allowed(','family_private.chat_group_pair_allowed(');
 select pg_get_functiondef('family_private.chat_read(uuid,bigint)'::regprocedure)into def;execute replace(def,'and family_private.chat_pair_allowed(m.sender_id)','and(case when thread is null then family_private.chat_group_pair_allowed(m.sender_id)else family_private.chat_pair_allowed(m.sender_id)end)');
end$$;
alter function family_private.chat_group_pair_allowed(uuid)owner to family_api_executor;
revoke all on function family_private.chat_group_pair_allowed(uuid)from public,anon;grant execute on function family_private.chat_group_pair_allowed(uuid)to authenticated,family_api_executor;
-- Confirmed kinship cannot be forged by updating one's own personal tree.
create function family_private.kinship_confirmation_guard()returns trigger language plpgsql set search_path='' as $$begin
 if new.confirmed_at is not null and(new.confirmed_at is distinct from old.confirmed_at or new.confirmed_by is distinct from old.confirmed_by)then
 if not(new.confirmed_by=auth.uid()and(auth.uid()=new.member_id or exists(select 1 from public.profiles p where p.id=auth.uid()and p.role='admin'and p.status='active'and p.tenant_id=new.tenant_id)))then raise exception 'تأكيد القرابة للطرف الآخر أو مدير العائلة';end if;end if;return new;end$$;
revoke all on function family_private.kinship_confirmation_guard()from public,anon,authenticated;
create trigger kinship_confirmation_guard before update on family_private.personal_kinship for each row execute function family_private.kinship_confirmation_guard();
create function family_private.family_extensions(action text,payload jsonb)returns jsonb language plpgsql security definer set search_path='' as $$declare uid uuid:=auth.uid();target uuid;tid uuid:=family_private.current_tenant();begin
 if family_private.access_role()is null then raise exception 'للحسابات المعتمدة فقط';end if;
 if action='trusted' then return coalesce((select jsonb_agg(to_jsonb(x))from(select distinct p.id,p.display_name,p.avatar_path,family_private.chat_pair_allowed(p.id)as can_chat from public.profiles p join family_private.endorsements e on e.tenant_id=tid and e.status='approved'and((e.applicant_id=uid and e.sponsor_id=p.id)or(e.sponsor_id=uid and e.applicant_id=p.id))where p.tenant_id=tid and p.status='active')x),'[]');
 elsif action='kinship_requests' then return coalesce((select jsonb_agg(to_jsonb(x))from(select k.owner_id as id,p.display_name,p.avatar_path,k.relation,o.label from family_private.personal_kinship k join public.profiles p on p.id=k.owner_id join public.kinship_options o on o.tenant_id=k.tenant_id and o.code=k.relation where k.tenant_id=tid and k.member_id=uid and k.confirmed_at is null)x),'[]');
 elsif action in('confirm_link','reject_link')then
 target=(payload->>'owner')::uuid;
 if action='confirm_link'then update family_private.personal_kinship set confirmed_by=uid,confirmed_at=now()where tenant_id=tid and owner_id=target and member_id=uid;
 else delete from family_private.personal_kinship where tenant_id=tid and owner_id=target and member_id=uid;end if;return 'true';
 elsif action='find_relative'then return coalesce((select jsonb_agg(to_jsonb(x))from(select p.id,p.display_name,p.avatar_path from public.profiles p join family_private.member_details d on d.id=p.id where p.tenant_id=tid and p.id<>uid and p.status='active'and length(trim(payload->>'term'))>0 and(starts_with(family_private.normalize_name(p.display_name),family_private.normalize_name(payload->>'term'))or starts_with(d.phone,family_private.phone_prefix(payload->>'term')))order by p.display_name limit 30)x),'[]');
 end if;raise exception 'إجراء غير معروف';end$$;
alter function family_private.family_extensions(text,jsonb)owner to family_api_executor;
revoke all on function family_private.family_extensions(text,jsonb)from public,anon;grant execute on function family_private.family_extensions(text,jsonb)to authenticated,family_api_executor;
do $$declare def text;begin
 select pg_get_functiondef('family_private.family_action(text,jsonb)'::regprocedure)into def;
 def=replace(def,'if action=''similar'' then','if action in(''trusted'',''kinship_requests'',''confirm_link'',''reject_link'',''find_relative'')then return family_private.family_extensions(action,payload);'||chr(10)||' elsif action=''similar'' then');
 def=replace(def,'p.id,p.display_name,k.relation,o.label,o.generation','p.id,p.display_name,p.avatar_path,k.relation,o.label,o.generation,(k.confirmed_at is not null)as confirmed,family_private.chat_pair_allowed(p.id)as can_chat');
 def=replace(def,'on o.code=k.relation','on o.tenant_id=k.tenant_id and o.code=k.relation');
 def=replace(def,'do update set relation=excluded.relation','do update set relation=excluded.relation,confirmed_by=null,confirmed_at=null');execute def;
 select pg_get_functiondef('family_private.endorse_action(text,jsonb)'::regprocedure)into def;def=replace(def,'p.display_name,d.full_name','p.display_name,p.avatar_path,s.avatar_path as sponsor_avatar,d.full_name');execute def;
end$$;
-- Maintenance consent is isolated from ordinary family data privileges.
create table family_private.maintenance_requests(id uuid primary key default gen_random_uuid(),tenant_id uuid not null references family_private.tenants(id),requested_by uuid not null references auth.users(id),reason text not null check(length(reason)between 5 and 1000),status text not null default 'pending'check(status in('pending','approved','rejected','revoked')),approved_by uuid references auth.users(id),created_at timestamptz not null default now(),expires_at timestamptz,last_opened_at timestamptz);
alter table family_private.maintenance_requests enable row level security;
revoke all on family_private.maintenance_requests from public,anon,authenticated,family_api_executor;
create index maintenance_tenant_status on family_private.maintenance_requests(tenant_id,status,created_at desc);
create function public.maintenance_action(action text,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$declare t uuid:=family_private.current_tenant();begin
 if family_private.access_role()is distinct from 'admin'then raise exception 'موافقة مدير الكيان مطلوبة';end if;
 if action='list'then return coalesce((select jsonb_agg(to_jsonb(r))from family_private.maintenance_requests r where tenant_id=t),'[]');
 elsif action in('approve','reject','revoke')then
 update family_private.maintenance_requests set status=case action when 'approve'then 'approved'when 'reject'then 'rejected'else 'revoked'end,approved_by=auth.uid(),expires_at=case when action='approve'then now()+interval '2 hours'else now()end where tenant_id=t and id=(payload->>'id')::uuid and((action in('approve','reject')and status='pending')or(action='revoke'and status='approved'));
 if not found then raise exception 'طلب غير متاح';end if;return 'true';end if;raise exception 'إجراء غير معروف';end$$;
revoke all on function public.maintenance_action(text,jsonb)from public,anon;grant execute on function public.maintenance_action(text,jsonb)to authenticated;
create function family_private.platform_operations(action text,data jsonb)returns jsonb language plpgsql security definer set search_path='' as $$declare t family_private.tenants;r record;bytes bigint:=0;n bigint:=0;rows bigint;files bigint;request family_private.maintenance_requests;begin
 if not family_private.platform_allowed()then raise exception 'إدارة المنصة فقط';end if;
 select * into t from family_private.tenants where id=(data->>'id')::uuid;if not found then raise exception 'الكيان غير موجود';end if;
 if action='login_access'then
 if data->>'mode'not in('allowed','suspended','blocked')or data->>'mode'is null then raise exception 'حالة غير صحيحة';end if;
 if data->>'mode'='suspended'and(nullif(data->>'until','')is null or(data->>'until')::timestamptz<=now())then raise exception 'اختر نهاية تعليق مستقبلية';end if;
 update family_private.tenants set login_access=data->>'mode',login_suspended_until=case when data->>'mode'='suspended'then(data->>'until')::timestamptz else null end,updated_at=now()where id=t.id;return 'true';
 elsif action='chat_policy'then
 update public.family_settings set trusted_chat_enabled=(data->>'trusted')::boolean,kinship_chat_enabled=(data->>'kinship')::boolean where tenant_id=t.id and id;
 if data?'relations'then update public.kinship_options set allow_private_chat=code in(select jsonb_array_elements_text(data->'relations'))where tenant_id=t.id;end if;return 'true';
 elsif action='operations'then
 return jsonb_build_object('trusted',(select trusted_chat_enabled from public.family_settings where tenant_id=t.id and id),'kinship',(select kinship_chat_enabled from public.family_settings where tenant_id=t.id and id),'relations',(select coalesce(jsonb_agg(jsonb_build_object('code',code,'label',label,'allowed',allow_private_chat)),'[]')from public.kinship_options where tenant_id=t.id),'maintenance',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select * from family_private.maintenance_requests where tenant_id=t.id order by created_at desc limit 20)x));
 elsif action='usage'then
 for r in select ns.nspname,c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace join pg_attribute a on a.attrelid=c.oid and a.attname='tenant_id'and not a.attisdropped where ns.nspname in('public','family_private')and c.relkind='r'loop
 execute format('select coalesce(sum(pg_column_size(x)),0),count(*)from %I.%I x where tenant_id=$1',r.nspname,r.relname)into n,rows using t.id;bytes:=bytes+n;end loop;
 select coalesce(sum(case when o.metadata->>'size'~'^[0-9]+$'then(o.metadata->>'size')::bigint else 0 end),0),count(*)into n,files from storage.objects o join public.profiles p on split_part(o.name,'/',1)=p.id::text where p.tenant_id=t.id and o.bucket_id in('news-images','profile-images','chat-media','ad-images');
 return jsonb_build_object('row_bytes_estimate',bytes,'file_bytes',n,'files',files,'users',(select count(*)from public.profiles where tenant_id=t.id),'news',(select count(*)from public.posts where tenant_id=t.id),'messages',(select count(*)from family_private.chat_messages where tenant_id=t.id),'groups',(select count(*)from family_private.chat_groups where tenant_id=t.id));
 elsif action='maintenance_request'then
 if length(trim(data->>'reason'))not between 5 and 1000 or data->>'reason'is null then raise exception 'اكتب سبب الصيانة';end if;
 if exists(select 1 from family_private.maintenance_requests where tenant_id=t.id and requested_by=auth.uid()and(status='pending'or(status='approved'and expires_at>now())))then raise exception 'يوجد طلب صيانة قيد الانتظار أو تصريح ساري';end if;
 insert into family_private.maintenance_requests(tenant_id,requested_by,reason)values(t.id,auth.uid(),trim(data->>'reason'))returning * into request;return to_jsonb(request);
 elsif action='maintenance_open'then
 select * into request from family_private.maintenance_requests where id=(data->>'request')::uuid and tenant_id=t.id and requested_by=auth.uid()and status='approved'and expires_at>now()and exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=approved_by and p.tenant_id=t.id and p.role='admin'and p.status='active'and u.email_confirmed_at is not null);
 if not found then raise exception 'يلزم تصريح صيانة ساري بموافقة مدير الكيان';end if;
 update family_private.maintenance_requests set last_opened_at=now()where id=request.id;
 return jsonb_build_object('expires_at',request.expires_at,'scope','قراءة الأخبار والإعدادات والتشخيص فقط؛ دون الرسائل الخاصة أو تعديل البيانات','settings',(select to_jsonb(s)from public.family_settings s where tenant_id=t.id and id),'news',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select id,title,body,created_at,published from public.posts where tenant_id=t.id and deleted_at is null order by created_at desc limit 30)x));
 end if;raise exception 'إجراء غير معروف';end$$;
revoke all on function family_private.platform_operations(text,jsonb)from public,anon,authenticated,family_api_executor;
do $$declare def text;begin
 select pg_get_functiondef('public.platform_action(text,jsonb)'::regprocedure)into def;def=replace(def,'elsif action in(''subscription_save''','elsif action in(''login_access'',''chat_policy'',''operations'',''usage'',''maintenance_request'',''maintenance_open'')then return family_private.platform_operations(action,data);'||chr(10)||' elsif action in(''subscription_save''');execute def;
end$$;
revoke create on schema family_private from family_api_executor;
notify pgrst,'reload schema';
commit;
begin;
do $$declare def text;begin
 select pg_get_functiondef('family_private.chat_open(uuid)'::regprocedure)into def;
 def=replace(def,'insert into family_private.chat_threads(member_a,member_b)',E'select id into t from family_private.chat_threads where member_a=least(auth.uid(),other)and member_b=greatest(auth.uid(),other);if t is not null then return t;end if;\n if not family_private.tenant_writable(family_private.current_tenant())then raise exception ''انتهى الاشتراك: الكيان للاطلاع فقط'';end if;\n insert into family_private.chat_threads(member_a,member_b)');execute def;
end$$;
commit;
begin;
do $$declare def text;begin select pg_get_functiondef('public.platform_action(text,jsonb)'::regprocedure)into def;def=replace(def,'insert into public.kinship_options(tenant_id,code,label,generation,for_reference,enabled)select tid,code,label,generation,for_reference,enabled','insert into public.kinship_options(tenant_id,code,label,generation,for_reference,enabled,allow_private_chat)select tid,code,label,generation,for_reference,enabled,allow_private_chat');execute def;end$$;
commit;
begin;
do $$declare def text;begin
 select pg_get_functiondef('family_private.family_extensions(text,jsonb)'::regprocedure)into def;
 def=replace(def,'if action=''trusted'' then',E'if action in(''admin_kinship_list'',''admin_kinship_confirm'',''admin_kinship_reject'')then\n if family_private.access_role()<>''admin''then raise exception ''لمدير العائلة فقط'';end if;\n if action=''admin_kinship_list''then return coalesce((select jsonb_agg(to_jsonb(x))from(select k.owner_id::text||''_''||k.member_id::text as id,k.owner_id,k.member_id,p.display_name,o.label,m.display_name as member_name from family_private.personal_kinship k join public.profiles p on p.id=k.owner_id join public.profiles m on m.id=k.member_id join public.kinship_options o on o.tenant_id=k.tenant_id and o.code=k.relation where k.tenant_id=tid and k.confirmed_at is null)x),''[]'');end if;\n if action=''admin_kinship_confirm''then update family_private.personal_kinship set confirmed_at=now(),confirmed_by=uid where tenant_id=tid and owner_id=(payload->>''owner'')::uuid and member_id=(payload->>''member'')::uuid;else delete from family_private.personal_kinship where tenant_id=tid and owner_id=(payload->>''owner'')::uuid and member_id=(payload->>''member'')::uuid;end if;return ''true'';\n elsif action=''trusted'' then');execute def;
 select pg_get_functiondef('family_private.family_action(text,jsonb)'::regprocedure)into def;def=replace(def,'if action in(''trusted''','if action in(''admin_kinship_list'',''admin_kinship_confirm'',''admin_kinship_reject'',''trusted''');execute def;
end$$;
commit;
