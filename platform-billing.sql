begin;
create table family_private.billing_plans(id uuid primary key default gen_random_uuid(),name text not null check(length(name)between 2 and 100),duration_count int not null check(duration_count between 1 and 3650),duration_unit text not null check(duration_unit in('month','year','week','day')),price_sar numeric(10,2)check(price_sar>=0),enabled boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),check(not enabled or price_sar is not null));
alter table family_private.billing_plans enable row level security;
revoke all on family_private.billing_plans from public,anon,authenticated,family_api_executor;
insert into family_private.billing_plans(name,duration_count,duration_unit)values('سنة',1,'year'),('سنتان',2,'year'),('ثلاث سنوات',3,'year'),('ستة أشهر',6,'month');
alter table family_private.tenants add column billing_plan_id uuid references family_private.billing_plans(id);
create table family_private.billing_invoices(id uuid primary key default gen_random_uuid(),request_id uuid not null unique,number bigint generated always as identity unique,tenant_id uuid not null references family_private.tenants(id),plan_id uuid not null references family_private.billing_plans(id),plan_name text not null,duration_count int not null,duration_unit text not null,amount_sar numeric(10,2)not null check(amount_sar>=0),currency text not null default 'SAR'check(currency='SAR'),status text not null default 'issued'check(status in('issued','paid','void')),issued_at timestamptz not null default now(),paid_at timestamptz,starts_at timestamptz,ends_at timestamptz,created_by uuid not null references auth.users(id),settled_by uuid references auth.users(id),payment_method text);
create index billing_invoice_tenant on family_private.billing_invoices(tenant_id,issued_at desc);
alter table family_private.billing_invoices enable row level security;
revoke all on family_private.billing_invoices from public,anon,authenticated,family_api_executor;
create function family_private.billing_action(action text,data jsonb)returns jsonb language plpgsql security definer set search_path='' set timezone='Asia/Riyadh' as $$
#variable_conflict use_column
declare p family_private.billing_plans;t family_private.tenants;i family_private.billing_invoices;rid uuid;start_time timestamptz;end_time timestamptz;begin
 if not family_private.platform_allowed()then raise exception 'إدارة المنصة فقط';end if;
 if action='plans'then return coalesce((select jsonb_agg(to_jsonb(x))from(select * from family_private.billing_plans order by created_at,id)x),'[]');
 elsif action='plan_save'then
 if (data->>'enabled')::boolean and nullif(data->>'price_sar','')is null then raise exception 'حدد سعر الباقة قبل تفعيلها';end if;
 if nullif(data->>'price_sar','')is not null and (data->>'price_sar')::numeric<>round((data->>'price_sar')::numeric,2)then raise exception 'السعر بمنزلتين عشريتين كحد أقصى';end if;
 if nullif(data->>'id','')is null then insert into family_private.billing_plans(name,duration_count,duration_unit,price_sar,enabled)values(trim(data->>'name'),(data->>'duration_count')::int,data->>'duration_unit',nullif(data->>'price_sar','')::numeric,coalesce((data->>'enabled')::boolean,false))returning * into p;
 else update family_private.billing_plans set name=trim(data->>'name'),duration_count=(data->>'duration_count')::int,duration_unit=data->>'duration_unit',price_sar=nullif(data->>'price_sar','')::numeric,enabled=coalesce((data->>'enabled')::boolean,false),updated_at=now()where id=(data->>'id')::uuid returning * into p;if not found then raise exception 'الباقة غير موجودة';end if;end if;return to_jsonb(p);
 elsif action='invoices'then return coalesce((select jsonb_agg(to_jsonb(x))from(select i.*,t.name as tenant_name,t.code as tenant_code,t.contact_email,t.contact_phone from family_private.billing_invoices i join family_private.tenants t on t.id=i.tenant_id where nullif(data->>'id','')is null or i.tenant_id=(data->>'id')::uuid order by i.issued_at desc limit 500)x),'[]');
 elsif action='assign_plan'then
 rid=(data->>'request_id')::uuid;if rid is null then raise exception 'معرف العملية مطلوب';end if;
 select * into t from family_private.tenants where id=(data->>'id')::uuid for update;if not found then raise exception 'الكيان غير موجود';end if;
 select * into i from family_private.billing_invoices where request_id=rid;if found then if i.tenant_id<>t.id or i.plan_id<>(data->>'plan_id')::uuid then raise exception 'معرف عملية مستخدم';end if;return to_jsonb(i);end if;
 select * into p from family_private.billing_plans where id=(data->>'plan_id')::uuid and enabled and price_sar is not null for share;if not found then raise exception 'اختر باقة مفعلة لها سعر';end if;
 update family_private.billing_invoices set status='void'where tenant_id=t.id and status='issued';
 update family_private.tenants set billing_plan_id=p.id,updated_at=now()where id=t.id;
 insert into family_private.billing_invoices(request_id,tenant_id,plan_id,plan_name,duration_count,duration_unit,amount_sar,created_by)values(rid,t.id,p.id,p.name,p.duration_count,p.duration_unit,p.price_sar,auth.uid())returning * into i;return to_jsonb(i);
 elsif action in('invoice_paid','invoice_void')then
 -- Lock tenant before invoice, consistently with invoice creation.
 select * into t from family_private.tenants where id=(select tenant_id from family_private.billing_invoices where id=(data->>'invoice')::uuid)for update;if not found then raise exception 'الفاتورة غير موجودة';end if;
 select * into i from family_private.billing_invoices where id=(data->>'invoice')::uuid for update;
 if action='invoice_void'then if i.status='paid'then raise exception 'لا يمكن إلغاء مطالبة مسددة';end if;update family_private.billing_invoices set status='void'where id=i.id;return 'true';end if;
 if i.status='paid'then return to_jsonb(i);end if;
 if i.status<>'issued'then raise exception 'الفاتورة ملغاة';end if;
 if data->>'confirm'is distinct from 'MANUAL_PAYMENT_RECEIVED'then raise exception 'أكد استلام السداد فعليًا';end if;
 start_time=case when t.subscription_ends_at>now()then t.subscription_ends_at else date_trunc('minute',now())end;
 end_time=start_time+case i.duration_unit when 'year'then make_interval(years=>i.duration_count)when 'month'then make_interval(months=>i.duration_count)when 'week'then make_interval(weeks=>i.duration_count)else make_interval(days=>i.duration_count)end;
 update family_private.tenants set subscription_starts_at=case when subscription_ends_at>now()then subscription_starts_at else start_time end,subscription_ends_at=end_time,payment_status='paid',fee_sar=i.amount_sar,updated_at=now()where id=t.id;
 update family_private.billing_invoices set status='paid',paid_at=now(),starts_at=start_time,ends_at=end_time,settled_by=auth.uid(),payment_method='admin_manual'where id=i.id returning * into i;return to_jsonb(i);
 end if;raise exception 'إجراء غير معروف';end$$;
revoke all on function family_private.billing_action(text,jsonb)from public,anon,authenticated,family_api_executor;
do $$declare def text;begin select pg_get_functiondef('public.platform_action(text,jsonb)'::regprocedure)into def;def=replace(def,'elsif action=''save'' then',E'elsif action in(''plans'',''plan_save'',''invoices'',''assign_plan'',''invoice_paid'',''invoice_void'')then return family_private.billing_action(action,data);\n elsif action=''save'' then');execute def;end$$;
notify pgrst,'reload schema';
commit;
begin;
do $$declare def text;begin
 select pg_get_functiondef('public.platform_action(text,jsonb)'::regprocedure)into def;
 def=replace(def,'update family_private.tenants set code=',E'if data?''contact_email''and data->>''contact_email''is distinct from v.contact_email and(data->>''contact_email''!~''^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$''or length(data->>''contact_email'')>254)then raise exception ''تحقق من بريد مدير الكيان'';end if;\n if data?''contact_phone''and data->>''contact_phone''is distinct from v.contact_phone then data=jsonb_set(data,''{contact_phone}'',to_jsonb(family_private.phone_prefix(data->>''contact_phone'')));if data->>''contact_phone''!~''^\\+[1-9][0-9]{7,14}$''then raise exception ''تحقق من جوال مدير الكيان'';end if;end if;\n update family_private.tenants set contact_email=coalesce(nullif(lower(trim(data->>''contact_email'')),''''),contact_email),contact_phone=coalesce(nullif(trim(data->>''contact_phone''),''''),contact_phone),code=');execute def;
end$$;
commit;
