begin;
create function public.platform_lifecycle(action text,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$declare t family_private.tenants;begin
 if not family_private.platform_allowed()then raise exception 'إدارة المنصة فقط';end if;
 if action='status'then return jsonb_build_object('pending_mail',(select count(*)from family_private.lifecycle_mail where sent_at is null),'mail_errors',(select coalesce(jsonb_agg(jsonb_build_object('family',x.name,'error',x.last_error)),'[]')from(select t.name,m.last_error from family_private.lifecycle_mail m join family_private.tenants t on t.id=m.tenant_id where m.sent_at is null and m.last_error is not null limit 20)x),'deletions',(select coalesce(jsonb_agg(jsonb_build_object('family',t.name,'phase',d.phase,'last_error',d.last_error)),'[]')from family_private.tenant_deletions d join family_private.tenants t on t.id=d.tenant_id),'schedule_active',exists(select 1 from cron.job where jobname='family-tenant-lifecycle'and active));
 elsif action='trial_start'then
 select * into t from family_private.tenants where id=(payload->>'id')::uuid for update;
 if not found or t.trial_started_at is not null or t.payment_status<>'unpaid'or t.subscription_ends_at is not null or t.deleting_at is not null then raise exception 'التجربة متاحة مرة واحدة لكيان جديد غير مشترك';end if;
 update family_private.tenants set trial_started_at=now(),trial_ends_at=now()+interval '30 days',status='active'where id=t.id;
 insert into public.family_settings(tenant_id,id)values(t.id,true)on conflict do nothing;insert into family_private.storage_limits(tenant_id,id)values(t.id,true)on conflict do nothing;
 insert into public.kinship_options(tenant_id,code,label,generation,for_reference,enabled,allow_private_chat)select t.id,o.code,o.label,o.generation,o.for_reference,o.enabled,o.allow_private_chat from public.kinship_options o where tenant_id=(select id from family_private.tenants where code='01')on conflict do nothing;
 return 'true';end if;raise exception 'إجراء غير معروف';end$$;
revoke all on function public.platform_lifecycle(text,jsonb)from public,anon;grant execute on function public.platform_lifecycle(text,jsonb)to authenticated;
-- New account creation must not bypass an expired tenant's write lock.
do $$declare def text;begin select pg_get_functiondef('family_private.enroll()'::regprocedure)into def;def:=replace(def,'insert into public.profiles(id,display_name,tenant_id)','if TG_OP=''INSERT''and not family_private.tenant_writable(tid)then raise exception ''انتهت مدة الكيان؛ يلزم تجديد الاشتراك قبل إضافة أعضاء'';end if;'||chr(10)||' insert into public.profiles(id,display_name,tenant_id)');execute def;end$$;
commit;
