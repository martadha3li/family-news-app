begin;
create function public.lifecycle_backend(action text,data jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$#variable_conflict use_column
declare t family_private.tenants;j family_private.tenant_deletions;r record;tid uuid;stamp text;sig text;begin
 if action='verify'then
 stamp:=data->>'stamp';if stamp is null or stamp!~'^[0-9]{10}$'or abs(extract(epoch from now())-stamp::bigint)>120 then return 'false';end if;
 select encode(extensions.hmac(stamp||':family-lifecycle',dispatch_secret,'sha256'),'hex')into sig from family_private.push_config where id;return to_jsonb(sig is not null and sig=data->>'signature');
 elsif action='tick'then
 -- An active subscription or waiver always takes precedence over a historical trial.
 for t in select * from family_private.tenants where deleting_at is null and payment_status='paid'and subscription_ends_at+interval '6 months'<=now()and renewal_notice_sent_at is null for update skip locked loop
 insert into family_private.lifecycle_mail(tenant_id,expiry,kind,recipient,subject,body)values(t.id,t.subscription_ends_at,'renewal',t.contact_email,'تجديد اشتراك '||t.name||' قبل الحذف النهائي','انتهت مهلة الاطلاع البالغة ستة أشهر بعد انتهاء الاشتراك. يرجى التجديد. بعد 15 يومًا من إرسال هذه الرسالة سيحذف الكيان وكل صوره وبياناته نهائيًا. الكود: '||t.code||'. رابط الإدارة: https://family-news-app.nimbletide.chatgpt.site')on conflict do nothing;
 end loop;
 for t in select * from family_private.tenants where deleting_at is null and payment_status<>'waived'and((payment_status<>'paid'and trial_ends_at+interval '30 days'<=now())or(payment_status='paid'and subscription_ends_at<=now()and renewal_notice_sent_at+interval '15 days'<=now()))for update skip locked loop
 update family_private.tenants set deleting_at=now(),login_access='blocked'where id=t.id;
 insert into family_private.tenant_deletions(tenant_id,members)select t.id,coalesce(array_agg(p.id),'{}'::uuid[])from public.profiles p where tenant_id=t.id;
 end loop;
 return jsonb_build_object('mail',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select m.* from family_private.lifecycle_mail m join family_private.tenants t on t.id=m.tenant_id where m.sent_at is null and t.deleting_at is null and((m.kind='trial_started'and t.payment_status='unpaid'and t.trial_ends_at=m.expiry)or(m.kind='renewal'and t.payment_status='paid'and t.subscription_ends_at=m.expiry and t.subscription_ends_at+interval '6 months'<=now()))order by m.id limit 10)x),'jobs',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select * from family_private.tenant_deletions order by started_at limit 3)x));
 elsif action='mail_sent'then
 select * into r from family_private.lifecycle_mail where id=(data->>'id')::uuid for update;if not found then raise exception 'Unknown message';end if;
 update family_private.lifecycle_mail set sent_at=coalesce(sent_at,now()),provider_id=data->>'provider_id',last_error=null where id=r.id;
 if r.kind='renewal'then update family_private.tenants set renewal_notice_sent_at=coalesce(renewal_notice_sent_at,now())where id=r.tenant_id and payment_status='paid'and subscription_ends_at=r.expiry;end if;return 'true';
 elsif action='mail_error'then update family_private.lifecycle_mail set last_error=left(data->>'error',200)where id=(data->>'id')::uuid and sent_at is null;return 'true';
 end if;
 tid:=(data->>'tenant')::uuid;
 select * into t from family_private.tenants where id=tid for update;
 select * into j from family_private.tenant_deletions where tenant_id=tid for update;
 if t.deleting_at is null or j.tenant_id is null or t.payment_status='waived'then raise exception 'Deletion not authorized';end if;
 if action='files'then return coalesce((select jsonb_agg(to_jsonb(x))from(select o.bucket_id,o.name from storage.objects o where split_part(o.name,'/',1)=any(select unnest(j.members)::text)order by o.bucket_id,o.name limit 500)x),'[]');
 elsif action='auth_members'then return to_jsonb(array(select member from unnest(j.members)member where not exists(select 1 from family_private.platform_admins a where a.user_id=member)));
 elsif action='purge_data'then
 if(select count(*)from information_schema.columns where column_name='tenant_id'and table_schema in('public','family_private'))<>28 then raise exception 'Tenant table registry changed; update cleanup before deletion';end if;
 if exists(select 1 from storage.objects o where split_part(o.name,'/',1)=any(select unnest(j.members)::text))then raise exception 'Files remain';end if;
 -- Dependency order is explicit; a new tenant table stops cleanup instead of leaking data.
 for r in select unnest(array['family_private.push_jobs','family_private.notification_reads','family_private.push_subscriptions','public.ad_preferences','public.likes','public.comments','family_private.chat_messages','family_private.group_members','family_private.chat_groups','family_private.chat_threads','family_private.endorsements','family_private.personal_kinship','family_private.phone_requests','public.announcements','public.posts','family_private.member_details','family_private.manual_members','family_private.maintenance_requests','family_private.subscription_renewals','family_private.billing_invoices','family_private.admin_audit','public.profiles','public.allowed_families','public.kinship_options','public.family_settings','family_private.storage_limits','family_private.lifecycle_mail'])as tbl loop
 execute format('delete from %s where tenant_id=$1',r.tbl::regclass)using tid;end loop;
 update family_private.tenant_deletions set phase='auth'where tenant_id=tid;return to_jsonb(j.members);
 elsif action='finish'then
 if j.phase<>'auth'then raise exception 'Invalid phase';end if;
 if exists(select 1 from auth.users where id=any(j.members)and not exists(select 1 from family_private.platform_admins a where a.user_id=auth.users.id))then raise exception 'Auth users remain';end if;
 delete from family_private.tenant_deletions where tenant_id=tid;delete from family_private.tenants where id=tid;return 'true';
 elsif action='error'then update family_private.tenant_deletions set last_error=left(data->>'error',200)where tenant_id=tid;return 'true';
 end if;raise exception 'Unknown action';
end$$;
revoke all on function public.lifecycle_backend(text,jsonb)from public,anon,authenticated,family_api_executor;grant execute on function public.lifecycle_backend(text,jsonb)to service_role;
create function family_private.dispatch_lifecycle()returns void language plpgsql security definer set search_path='' as $$declare stamp text:=floor(extract(epoch from now()))::bigint::text;sig text;begin
 select encode(extensions.hmac(stamp||':family-lifecycle',dispatch_secret,'sha256'),'hex')into sig from family_private.push_config where id;
 perform net.http_post(url:='https://dlkykiducjimwehfhxfq.supabase.co/functions/v1/family-lifecycle',headers:=jsonb_build_object('Content-Type','application/json','x-family-time',stamp,'x-family-signature',sig),body:='{}',timeout_milliseconds:=60000);
end$$;
revoke all on function family_private.dispatch_lifecycle()from public,anon,authenticated;
select cron.schedule('family-tenant-lifecycle','17 * * * *','select family_private.dispatch_lifecycle()');
commit;
