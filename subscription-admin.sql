begin;
alter table family_private.tenants add column subscription_starts_at timestamptz,add column subscription_ends_at timestamptz,add column renewal_prices jsonb not null default '{}';
alter table family_private.tenants add constraint subscription_period_valid check((subscription_starts_at is null and subscription_ends_at is null)or(subscription_starts_at is not null and subscription_ends_at is not null and isfinite(subscription_starts_at) and isfinite(subscription_ends_at) and subscription_ends_at>subscription_starts_at));
create table family_private.subscription_renewals(
 request_id uuid primary key,tenant_id uuid not null references family_private.tenants(id),months integer not null check(months in(6,12,24,36)),amount_sar numeric(10,2) not null check(amount_sar>=0),payment_status text not null check(payment_status in('paid','waived')),previous_end timestamptz,starts_at timestamptz not null,ends_at timestamptz not null,performed_by uuid not null references auth.users(id),created_at timestamptz not null default now()
);
create index subscription_renewals_tenant_date on family_private.subscription_renewals(tenant_id,created_at desc);
alter table family_private.subscription_renewals enable row level security;
revoke all on family_private.subscription_renewals from public,anon,authenticated,family_api_executor;
-- Private extension: the existing public dispatcher verifies the platform administrator first.
create function family_private.subscription_action(action text,data jsonb)returns jsonb language plpgsql security definer set search_path='' set timezone='Asia/Riyadh' as $$
declare t family_private.tenants;start_time timestamptz;end_time timestamptz;prices jsonb;key text;price numeric;months_count integer;request uuid;settlement text;entry family_private.subscription_renewals;begin
 if not family_private.platform_allowed()then raise exception 'إدارة المنصة فقط';end if;
 select * into t from family_private.tenants where id=(data->>'id')::uuid for update;if not found then raise exception 'الكيان غير موجود';end if;
 if action='subscription_save' then
 start_time=nullif(data->>'subscription_starts_at','')::timestamptz;end_time=nullif(data->>'subscription_ends_at','')::timestamptz;
 if (start_time is null)<>(end_time is null)or(start_time is not null and(not isfinite(start_time)or not isfinite(end_time)or end_time<=start_time))then raise exception 'حدد البداية والنهاية، ويجب أن تكون النهاية بعد البداية';end if;
 prices=coalesce(data->'renewal_prices','{}');
 if jsonb_typeof(prices)<>'object' then raise exception 'تحقق من أسعار الباقات';end if;
 for key in select jsonb_object_keys(prices)loop
 if key not in('6','12','24','36')then raise exception 'باقة غير معروفة';end if;
 if jsonb_typeof(prices->key)not in('number','null')then raise exception 'السعر رقم موجب أو صفر';end if;
 if prices->key<>'null'::jsonb then price=(prices->>key)::numeric;if price<0 or price>99999999.99 or price<>round(price,2)then raise exception 'تحقق من السعر (منزلتان عشريتان كحد أقصى)';end if;end if;
 end loop;
 update family_private.tenants set subscription_starts_at=start_time,subscription_ends_at=end_time,renewal_prices=prices,updated_at=now()where id=t.id;
 return jsonb_build_object('saved',true);
 elsif action='renew' then
 months_count=(data->>'months')::integer;request=(data->>'request_id')::uuid;settlement=data->>'payment_status';
 if months_count is null or months_count not in(6,12,24,36)or request is null or settlement is null or settlement not in('paid','waived')then raise exception 'اختر الباقة وحالة السداد وأكد التجديد';end if;
 select * into entry from family_private.subscription_renewals where request_id=request;
 if found then if entry.tenant_id<>t.id or entry.months<>months_count or entry.payment_status<>settlement then raise exception 'معرف العملية مستخدم';end if;return to_jsonb(entry);end if;
 if t.renewal_prices->>months_count::text is null then raise exception 'حدد سعر هذه الباقة واحفظه أولًا';end if;
 price=(t.renewal_prices->>months_count::text)::numeric;
 start_time=case when t.subscription_ends_at>now()then t.subscription_ends_at else date_trunc('minute',now())end;
 end_time=start_time+make_interval(months=>months_count);
 insert into family_private.subscription_renewals(request_id,tenant_id,months,amount_sar,payment_status,previous_end,starts_at,ends_at,performed_by)values(request,t.id,months_count,case when settlement='waived'then 0 else price end,settlement,t.subscription_ends_at,start_time,end_time,auth.uid())returning * into entry;
 update family_private.tenants set subscription_starts_at=case when subscription_ends_at>now()then subscription_starts_at else start_time end,subscription_ends_at=end_time,payment_status=settlement,fee_sar=entry.amount_sar,updated_at=now()where id=t.id;
 return to_jsonb(entry);
 end if;raise exception 'إجراء غير معروف';end$$;
revoke all on function family_private.subscription_action(text,jsonb)from public,anon,authenticated,family_api_executor;
do $$declare definition text;begin
 select pg_get_functiondef('public.platform_action(text,jsonb)'::regprocedure)into definition;
 definition=replace(definition,'elsif action=''save'' then','elsif action in(''subscription_save'',''renew'')then return family_private.subscription_action(action,data);'||chr(10)||' elsif action=''save'' then');execute definition;
end$$;
notify pgrst,'reload schema';
commit;
