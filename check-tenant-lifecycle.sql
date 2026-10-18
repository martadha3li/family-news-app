begin;
create temp table lifecycle_ids(id uuid);
insert into lifecycle_ids values(gen_random_uuid());
insert into family_private.tenants(id,code,name,status,contact_phone,contact_email,payment_status,subscription_starts_at,subscription_ends_at)select id,'LIFE-TEST','اختبار تجديد الاشتراك','active','+966500009977','renewal@example.invalid','paid',now()-interval '1 year',now()-interval '6 months 1 day'from lifecycle_ids;
select public.lifecycle_backend('tick');
do $$begin
 if not exists(select 1 from family_private.lifecycle_mail where tenant_id=(select id from lifecycle_ids)and kind='renewal'and sent_at is null)then raise exception 'renewal not queued';end if;
 if exists(select 1 from family_private.tenant_deletions where tenant_id=(select id from lifecycle_ids))then raise exception 'deleted before successful mail';end if;
end$$;
select public.lifecycle_backend('mail_sent',jsonb_build_object('id',(select id from family_private.lifecycle_mail where tenant_id=(select id from lifecycle_ids)),'provider_id','rollback-test-receipt'));
select public.lifecycle_backend('tick');
do $$begin if exists(select 1 from family_private.tenant_deletions where tenant_id=(select id from lifecycle_ids))then raise exception 'deleted before 15 day notice';end if;end$$;
update family_private.tenants set renewal_notice_sent_at=now()-interval '16 days'where id=(select id from lifecycle_ids);
-- Renew before deletion cancels the old notice and queued expiry.
update family_private.tenants set subscription_starts_at=now(),subscription_ends_at=now()+interval '1 year'where id=(select id from lifecycle_ids);
select public.lifecycle_backend('tick');
do $$begin if exists(select 1 from family_private.tenant_deletions where tenant_id=(select id from lifecycle_ids))or exists(select 1 from family_private.tenants where id=(select id from lifecycle_ids)and renewal_notice_sent_at is not null)then raise exception 'renewal did not cancel countdown';end if;end$$;
set local role authenticated;
do $$begin begin perform public.lifecycle_backend('tick');raise exception 'PUBLIC_WORKER_BYPASS';exception when insufficient_privilege then null;end;end$$;
reset role;
select 'PASS: paid six-month reminder queue, no deletion before actual email acknowledgement plus 15 days, renewal cancels countdown, worker service-only' result;
rollback;
