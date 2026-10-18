begin;
alter table family_private.tenants add column trial_started_at timestamptz,add column trial_ends_at timestamptz,add column renewal_notice_sent_at timestamptz,add column deleting_at timestamptz;
alter table family_private.maintenance_requests add column requested_hours integer not null default 2 check(requested_hours between 1 and 72),add column approved_hours integer check(approved_hours between 1 and 72);
create table family_private.manual_members(id uuid primary key default gen_random_uuid(),tenant_id uuid not null references family_private.tenants(id),email text not null unique,phone text not null unique,full_name text not null,gender text not null check(gender in('male','female')),role text not null check(role in('admin','journalist','member')),created_by uuid not null,created_at timestamptz not null default now(),claimed_by uuid,claimed_at timestamptz);
create table family_private.admin_audit(id bigint generated always as identity primary key,tenant_id uuid not null references family_private.tenants(id),actor uuid,action text not null,maintenance_id uuid,created_at timestamptz not null default now());
create table family_private.lifecycle_mail(id uuid primary key default gen_random_uuid(),tenant_id uuid not null references family_private.tenants(id),expiry timestamptz not null,kind text not null check(kind in('trial_started','renewal')),recipient text not null,subject text not null,body text not null,sent_at timestamptz,provider_id text,last_error text,unique(tenant_id,kind,expiry));
create table family_private.tenant_deletions(tenant_id uuid primary key references family_private.tenants(id),members uuid[] not null,phase text not null default 'files',started_at timestamptz not null default now(),last_error text);
alter table family_private.manual_members enable row level security;alter table family_private.admin_audit enable row level security;alter table family_private.lifecycle_mail enable row level security;alter table family_private.tenant_deletions enable row level security;
revoke all on family_private.manual_members,family_private.admin_audit,family_private.lifecycle_mail,family_private.tenant_deletions from public,anon,authenticated,family_api_executor;
create index on family_private.admin_audit(tenant_id,created_at desc);
create or replace function family_private.tenant_available(tid uuid)returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from family_private.tenants t where t.id=tid and t.status='active'and t.deleting_at is null and(t.login_access='allowed'or(t.login_access='suspended'and t.login_suspended_until<=now())))$$;
create or replace function family_private.tenant_writable(tid uuid)returns boolean language sql stable security definer set search_path='' as $$select family_private.tenant_available(tid)and exists(select 1 from family_private.tenants t where t.id=tid and(case when t.payment_status='waived'then true when t.trial_ends_at is not null and t.payment_status<>'paid'then t.trial_ends_at>now()else t.subscription_ends_at is null or t.subscription_ends_at>now()end))$$;
create function family_private.lifecycle_state(tid uuid)returns jsonb language sql stable security definer set search_path='' as $$select jsonb_build_object('trial_ends_at',t.trial_ends_at,'subscription_ends_at',t.subscription_ends_at,'trial',t.trial_ends_at is not null and t.payment_status='unpaid','read_only',not family_private.tenant_writable(t.id),'renewal_notice_sent_at',t.renewal_notice_sent_at,'delete_after',case when t.payment_status='waived'then null when t.trial_ends_at is not null and t.payment_status<>'paid'then t.trial_ends_at+interval '30 days'when t.renewal_notice_sent_at is not null then t.renewal_notice_sent_at+interval '15 days'else null end,'renewal_notice_due',case when t.payment_status='paid'then t.subscription_ends_at+interval '6 months'else null end,'deleting',t.deleting_at is not null)from family_private.tenants t where t.id=tid$$;
revoke all on function family_private.lifecycle_state(uuid)from public,anon,authenticated;
create or replace function public.tenant_current()returns jsonb language sql stable security definer set search_path='' as $$select jsonb_build_object('id',t.id,'code',t.code,'name',t.name,'logo',t.logo,'status',case when family_private.tenant_available(t.id)then t.status else 'suspended'end)||family_private.lifecycle_state(t.id)from family_private.tenants t join public.profiles p on p.tenant_id=t.id where p.id=auth.uid()$$;
-- Existing paid and waived tenants are not enrolled in a trial.
create or replace function public.tenant_request(data jsonb)returns text language plpgsql security definer set search_path='' as $$declare email text:=lower(trim(data->>'email'));phone text:=trim(data->>'phone');label text:=trim(data->>'name');pic text:=nullif(data->>'logo','');tid uuid;code text;begin
 if label is null or length(label)not between 3 and 100 or email is null or email!~'^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'or length(email)>254 or phone is null or phone!~'^\+[1-9][0-9]{7,14}$'or pic is null then raise exception 'أدخل اسم العائلة وشعارها وبريد التواصل ورقم الجوال الدولي';end if;
 perform pg_advisory_xact_lock(hashtextextended('tenant-request-'||email,0));
 if(select count(*)from family_private.tenants where created_at>now()-interval '1 hour')>=100 then raise exception 'طلبات كثيرة الآن. حاول لاحقًا';end if;
 if exists(select 1 from family_private.tenants where lower(contact_email)=email)then raise exception 'يوجد كيان مسجل بهذا البريد';end if;
 code:='F-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
 insert into family_private.tenants(code,name,logo,status,contact_phone,contact_email,payment_status,trial_started_at,trial_ends_at)values(code,label,pic,'active',phone,email,'unpaid',now(),now()+interval '30 days')returning id into tid;
 insert into public.family_settings(tenant_id,id)values(tid,true);
 insert into family_private.storage_limits(tenant_id,id)values(tid,true);
 insert into public.kinship_options(tenant_id,code,label,generation,for_reference,enabled,allow_private_chat)select tid,o.code,o.label,o.generation,o.for_reference,o.enabled,o.allow_private_chat from public.kinship_options o where tenant_id=(select id from family_private.tenants where tenants.code='01');
 insert into family_private.lifecycle_mail(tenant_id,expiry,kind,recipient,subject,body)values(tid,now()+interval '30 days','trial_started',email,'بدء التجربة المجانية — '||label,'بدأت تجربة مجانية لمدة 30 يومًا. الكود: '||code||'. بعد انتهائها يتوقف الإضافة والدردشة، وبعد 30 يومًا إضافية يحذف الكيان وصوره وبياناته نهائيًا ما لم يتم الاشتراك.');
 return 'تم إنشاء عائلتك وتجربتها المجانية لمدة 30 يومًا. كود العائلة: '||code||'. اخترها وسجل بالبريد نفسه ثم أكد بريدك لتصبح مديرها. بعد انتهاء التجربة يتوقف الإضافة، ويحذف الكيان نهائيًا بعد 30 يومًا إضافية دون اشتراك.';
end$$;
-- A verified email can claim only the administrator-prepared member in the same tenant.
create function family_private.claim_manual_member()returns trigger language plpgsql security definer set search_path='' as $$declare m family_private.manual_members;tid uuid;begin
 if new.email_confirmed_at is null then return new;end if;
 select tenant_id into tid from public.profiles where id=new.id;
 select * into m from family_private.manual_members where email=lower(new.email)and tenant_id=tid and claimed_by is null for update;
 if found and family_private.tenant_writable(tid)then
 update family_private.member_details set full_name=m.full_name,phone=m.phone,gender=m.gender where id=new.id and tenant_id=tid;
 update public.profiles set display_name=m.full_name,role=m.role,status='active'where id=new.id and tenant_id=tid and not is_root;
 update family_private.manual_members set claimed_by=new.id,claimed_at=now()where id=m.id;
 end if;return new;
end$$;
create trigger z_claim_manual_member after insert or update of email_confirmed_at on auth.users for each row execute function family_private.claim_manual_member();
-- Maintenance is validated on every operation, never by an unrestricted impersonation session.
create function family_private.admin_scope(payload jsonb)returns uuid language plpgsql stable security definer set search_path='' as $$declare tid uuid;begin
 if nullif(payload->>'maintenance','')is not null then
 if not family_private.platform_allowed()then raise exception 'إدارة المنصة فقط';end if;
 select r.tenant_id into tid from family_private.maintenance_requests r join public.profiles p on p.id=r.approved_by join auth.users u on u.id=p.id where r.id=(payload->>'maintenance')::uuid and r.requested_by=auth.uid()and r.status='approved'and r.expires_at>now()and p.tenant_id=r.tenant_id and p.role='admin'and p.status='active'and u.email_confirmed_at is not null and family_private.tenant_available(r.tenant_id);
 if tid is null then raise exception 'انتهى تصريح الصيانة أو ألغي';end if;
 else
 if family_private.access_role()is distinct from 'admin'then raise exception 'مدير العائلة فقط';end if;tid:=family_private.current_tenant();
 end if;return tid;
end$$;
create function public.family_admin(action text,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$#variable_conflict use_column
declare tid uuid:=family_private.admin_scope(payload);t family_private.tenants;m family_private.manual_members;v record;settings jsonb;v_email text;v_mobile text;v_full_name text;begin
 select * into t from family_private.tenants where id=tid;
 if action='overview'then return jsonb_build_object('family',jsonb_build_object('id',t.id,'code',t.code,'name',t.name,'logo',t.logo),'lifecycle',family_private.lifecycle_state(tid),'members',(select count(*)from public.profiles where tenant_id=tid),'pending',(select count(*)from public.profiles where tenant_id=tid and status='pending'),'news',(select count(*)from public.posts where tenant_id=tid),'messages',(select count(*)from family_private.chat_messages where tenant_id=tid),'settings',(select to_jsonb(s)-'tenant_id'from public.family_settings s where tenant_id=tid and id),'maintenance',(select count(*)from family_private.maintenance_requests where tenant_id=tid and status='pending'),'invoices',(select coalesce(jsonb_agg(to_jsonb(i)-'created_by'-'settled_by'),'[]')from family_private.billing_invoices i where tenant_id=tid),'audit',(select coalesce(jsonb_agg(to_jsonb(a)),'[]')from(select action,created_at,maintenance_id from family_private.admin_audit where tenant_id=tid order by created_at desc limit 30)a));
 elsif action='members'then return jsonb_build_object('members',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select p.id,p.display_name,p.role,p.status,p.is_root,p.avatar_path,d.full_name,d.phone,u.email from public.profiles p join auth.users u on u.id=p.id left join family_private.member_details d on d.id=p.id where p.tenant_id=tid order by p.created_at desc limit 2000)x),'prepared',(select coalesce(jsonb_agg(to_jsonb(m)-'created_by'),'[]')from family_private.manual_members m where tenant_id=tid and claimed_by is null));
 end if;
 if not family_private.tenant_writable(tid)then raise exception 'انتهت المدة: الكيان للاطلاع فقط. جدد الاشتراك لإجراء تغييرات';end if;
 if action='member_add'then
 v_email:=lower(trim(payload->>'email'));v_mobile:=family_private.phone_prefix(payload->>'phone');v_full_name:=trim(payload->>'full_name');
 if v_email is null or v_email!~'^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'or length(v_email)>254 or v_mobile is null or v_mobile!~'^\+[1-9][0-9]{7,14}$'or v_full_name is null or cardinality(string_to_array(family_private.normalize_name(v_full_name),' '))<>4 or length(v_full_name)>250 or coalesce(payload->>'gender','')not in('male','female')or coalesce(payload->>'role','')not in('member','journalist','admin')then raise exception 'أدخل الاسم الرباعي والبريد والجوال والجنس والصلاحية بشكل صحيح';end if;
 if exists(select 1 from auth.users u where lower(u.email)=v_email)or exists(select 1 from family_private.member_details d where d.phone=v_mobile)then raise exception 'البريد أو الجوال مسجل بالفعل';end if;
 insert into family_private.manual_members(tenant_id,email,phone,full_name,gender,role,created_by)values(tid,v_email,v_mobile,v_full_name,payload->>'gender',payload->>'role',auth.uid())returning * into m;
 elsif action='member_cancel'then delete from family_private.manual_members where tenant_id=tid and id=(payload->>'id')::uuid and claimed_by is null;
 elsif action='member_update'then
 if coalesce(payload->>'role','')not in('admin','journalist','member')or coalesce(payload->>'status','')not in('active','pending','suspended')then raise exception 'حالة أو صلاحية غير صحيحة';end if;
 update public.profiles set role=payload->>'role',status=payload->>'status'where tenant_id=tid and id=(payload->>'id')::uuid and not is_root and id<>auth.uid();if not found then raise exception 'الحساب محمي أو غير موجود';end if;
 elsif action='settings'then
 settings:=payload->'settings';if settings is null then raise exception 'إعدادات ناقصة';end if;
 update public.family_settings set chat_enabled=coalesce((settings->>'chat_enabled')::boolean,chat_enabled),public_chat_enabled=coalesce((settings->>'public_chat_enabled')::boolean,public_chat_enabled),private_chat_enabled=coalesce((settings->>'private_chat_enabled')::boolean,private_chat_enabled),restrict_gender_chat=coalesce((settings->>'restrict_gender_chat')::boolean,restrict_gender_chat),journalist_approval=coalesce((settings->>'journalist_approval')::boolean,journalist_approval),allow_groups=coalesce((settings->>'allow_groups')::boolean,allow_groups),auto_activate=coalesce((settings->>'auto_activate')::boolean,auto_activate),endorsements_enabled=coalesce((settings->>'endorsements_enabled')::boolean,endorsements_enabled)where tenant_id=tid and id;
 elsif action='branding'then
 update family_private.tenants set name=coalesce(nullif(trim(payload->>'name'),''),name),logo=coalesce(nullif(payload->>'logo',''),logo),updated_at=now()where id=tid;
 elsif action='news'then return coalesce((select jsonb_agg(to_jsonb(x))from(select id,title,body,published,moderation_status,created_at from public.posts where tenant_id=tid order by created_at desc limit 100)x),'[]');
 elsif action='news_update'then update public.posts set published=(payload->>'published')::boolean,moderation_status=case when(payload->>'published')::boolean then 'published'else 'rejected'end where tenant_id=tid and id=(payload->>'id')::uuid;
 else raise exception 'إجراء غير معروف';end if;
 insert into family_private.admin_audit(tenant_id,actor,action,maintenance_id)values(tid,auth.uid(),action,nullif(payload->>'maintenance','')::uuid);
 return jsonb_build_object('ok',true,'member',case when m.id is not null then to_jsonb(m)-'created_by'else null end);
end$$;
revoke all on function family_private.admin_scope(jsonb),family_private.claim_manual_member()from public,anon,authenticated;
revoke all on function public.family_admin(text,jsonb)from public,anon;grant execute on function public.family_admin(text,jsonb)to authenticated;
-- Parameterized approval, maximum 72 hours. Old clients retain two-hour default.
DO $$declare def text;begin
 select pg_get_functiondef('public.maintenance_action(text,jsonb)'::regprocedure)into def;
 def:=replace(def,'elsif action in(''approve'',''reject'',''revoke'')then','elsif action in(''approve'',''reject'',''revoke'')then if action=''approve''and(coalesce((payload->>''hours'')::integer,2)<1 or coalesce((payload->>''hours'')::integer,2)>72)then raise exception ''المدة من ساعة إلى 72 ساعة'';end if;');
 def:=replace(def,'now()+interval ''2 hours''','now()+make_interval(hours=>coalesce((payload->>''hours'')::integer,2))');
 def:=replace(def,'approved_by=auth.uid(),','approved_by=auth.uid(),approved_hours=case when action=''approve''then coalesce((payload->>''hours'')::integer,2)else approved_hours end,');execute def;
 select pg_get_functiondef('family_private.platform_operations(text,jsonb)'::regprocedure)into def;
 def:=replace(def,'insert into family_private.maintenance_requests(tenant_id,requested_by,reason)values(t.id,auth.uid(),trim(data->>''reason''))','insert into family_private.maintenance_requests(tenant_id,requested_by,reason,requested_hours)values(t.id,auth.uid(),trim(data->>''reason''),coalesce((data->>''hours'')::integer,2))');execute def;
 -- Allow trial tenants to remain active without recording a fictitious payment.
 select pg_get_functiondef('public.platform_action(text,jsonb)'::regprocedure)into def;
 def:=replace(def,'not in(''paid'',''waived'') then','not in(''paid'',''waived'') and not(v.trial_ends_at>now())then');execute def;
end$$;
-- Renewal clears old notices; deletion already in progress cannot be reversed mid-file purge.
create function family_private.guard_lifecycle()returns trigger language plpgsql set search_path='' as $$begin
 if old.deleting_at is not null and(new.subscription_ends_at is distinct from old.subscription_ends_at or new.payment_status is distinct from old.payment_status or new.deleting_at is null)then raise exception 'بدأ الحذف النهائي؛ لا يمكن تجديد هذا الكيان';end if;
 if new.subscription_ends_at is distinct from old.subscription_ends_at or new.payment_status is distinct from old.payment_status then new.renewal_notice_sent_at:=null;end if;return new;
end$$;
create trigger guard_lifecycle before update on family_private.tenants for each row execute function family_private.guard_lifecycle();
revoke all on function family_private.guard_lifecycle()from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
