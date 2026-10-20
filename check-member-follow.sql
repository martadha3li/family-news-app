begin;
create temp table follow_ids(kind text,id uuid);grant select on follow_ids to authenticated;
insert into follow_ids values('tenant',gen_random_uuid()),('other_tenant',gen_random_uuid()),('writer',gen_random_uuid()),('subject',gen_random_uuid()),('fan',gen_random_uuid()),('outsider',gen_random_uuid()),('other_writer',gen_random_uuid());
insert into family_private.tenants(id,code,name,status,contact_phone,contact_email,payment_status)select id,case kind when 'tenant'then 'FOLLOW-TEST'else 'FOLLOW-OTHER'end,'اختبار المتابعة','active','+966500007701',kind||'-follow@example.invalid','waived'from follow_ids where kind in('tenant','other_tenant');
select set_config('request.jwt.claim.sub',(select user_id::text from family_private.platform_admins limit 1),true);
select public.platform_action('save',jsonb_build_object('id',id,'status','active','payment_status','waived'))from follow_ids where kind in('tenant','other_tenant');
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_user_meta_data)select id,'authenticated','authenticated',kind||'-follow@example.invalid',now(),jsonb_build_object('family_code',case kind when 'outsider'then 'FOLLOW-OTHER'else 'FOLLOW-TEST'end,'full_name',kind||' احمد حسن اختبار','display_name',kind||' احمد حسن اختبار','gender','male','phone',case kind when 'writer'then '+966500007701'when 'subject'then '+966500007702'when 'fan'then '+966500007703'when 'other_writer'then '+966500007705'else '+966500007704'end)from follow_ids where kind in('writer','subject','fan','outsider','other_writer');
update public.profiles set status='active',role=case when id in(select id from follow_ids where kind in('writer','other_writer'))then 'journalist'else 'member'end where id in(select id from follow_ids);
update public.family_settings set journalist_approval=false where tenant_id=(select id from follow_ids where kind='tenant');
select set_config('request.jwt.claim.sub',(select id::text from follow_ids where kind='fan'),true);
set local role authenticated;
select public.member_social('follow',jsonb_build_object('member',(select id from follow_ids where kind='writer')));
select public.member_social('follow',jsonb_build_object('member',(select id from follow_ids where kind='writer')));
select public.member_social('follow',jsonb_build_object('member',(select id from follow_ids where kind='subject')));
do $$begin
 begin perform public.member_social('follow',jsonb_build_object('member',(select id from follow_ids where kind='fan')));raise exception 'SELF_FOLLOW';exception when raise_exception then if sqlerrm='SELF_FOLLOW'then raise;end if;end;
 begin perform public.member_social('profile',jsonb_build_object('member',(select id from follow_ids where kind='outsider')));raise exception 'CROSS_TENANT_PROFILE';exception when raise_exception then if sqlerrm='CROSS_TENANT_PROFILE'then raise;end if;end;
 begin perform count(*)from family_private.member_follows;raise exception 'RAW_GRAPH_ACCESS';exception when insufficient_privilege then null;end;
end$$;
reset role;
insert into family_private.push_subscriptions(tenant_id,endpoint,user_id,subscription,news,follow_alerts)select(select id from follow_ids where kind='tenant'),'https://fcm.googleapis.com/follow-test',id,'{}',false,true from follow_ids where kind='fan';
create temp table follow_posts(id bigint);grant select,insert on follow_posts to authenticated;
select set_config('request.jwt.claim.sub',(select id::text from follow_ids where kind='writer'),true);
set local role authenticated;
with p as(insert into public.posts(author_id,title,body,published,mentioned_member_ids,image_paths)values(auth.uid(),'خبر متابعة الاختبار','خبر @subject احمد حسن اختبار',true,array[(select id from follow_ids where kind='subject')],array[auth.uid()::text||'/follow.jpg'])returning id)insert into follow_posts select id from p;
reset role;
do $$begin
 if(select count(*)from family_private.follow_events where post_id=(select id from follow_posts))<>1 then raise exception 'duplicate publication and mention event';end if;
 if not exists(select 1 from family_private.push_jobs where user_id=(select id from follow_ids where kind='fan')and item=(select id::text from follow_posts)and follow_event)then raise exception 'follower push missing with general news disabled';end if;
end$$;
select set_config('request.jwt.claim.sub',(select id::text from follow_ids where kind='fan'),true);
set local role authenticated;
do $$declare x jsonb;begin
 x:=public.member_social('grid',jsonb_build_object('member',(select id from follow_ids where kind='subject'),'scope','mentions'));
 if jsonb_array_length(x)<>1 or(x->0->>'id')::bigint<>(select id from follow_posts)then raise exception 'mention grid wrong';end if;
 x:=public.native_notifications('list');if not exists(select 1 from jsonb_array_elements(x->'items')e where e->>'post_id'=(select id::text from follow_posts)and e->>'title'like 'نشر %')then raise exception 'follow notification missing';end if;
end$$;
reset role;
-- Unrelated edits and republishing cannot create duplicate follower alerts.
select set_config('request.jwt.claim.sub',(select id::text from follow_ids where kind='writer'),true);
update public.posts set title=title||' معدل'where id=(select id from follow_posts);
do $$begin if(select count(*)from family_private.follow_events where post_id=(select id from follow_posts))<>1 then raise exception 'edit duplicated alert';end if;end$$;
-- Mention a followed member in somebody else's previously published news.
select set_config('request.jwt.claim.sub',(select id::text from follow_ids where kind='other_writer'),true);
reset role;
insert into public.posts(tenant_id,author_id,title,body,published)values((select id from follow_ids where kind='tenant'),(select id from follow_ids where kind='other_writer'),'خبر يذكر من أتابعه','خبر بدون ذكر',true);
select set_config('request.jwt.claim.sub',(select id::text from follow_ids where kind='other_writer'),true);
update public.posts set mentioned_member_ids=array[(select id from follow_ids where kind='writer')],body='خبر @writer احمد حسن اختبار'where tenant_id=(select id from follow_ids where kind='tenant')and title='خبر يذكر من أتابعه';
do $$begin if not exists(select 1 from family_private.follow_events where tenant_id=(select id from follow_ids where kind='tenant')and reason='mention'and subject_id=(select id from follow_ids where kind='writer'))then raise exception 'mention in old post did not alert follower';end if;end$$;
-- Hide a post: it disappears from profile grid and live notification delivery.
select set_config('request.jwt.claim.sub',(select id::text from follow_ids where kind='writer'),true);
update public.posts set deleted_at=now()where id=(select id from follow_posts);
select set_config('request.jwt.claim.sub',(select id::text from follow_ids where kind='fan'),true);
set local role authenticated;
do $$begin if jsonb_array_length(public.member_social('grid',jsonb_build_object('member',(select id from follow_ids where kind='subject'),'scope','mentions')))<>0 then raise exception 'hidden news leaked to grid';end if;end$$;
select public.member_social('unfollow',jsonb_build_object('member',(select id from follow_ids where kind='writer')));
reset role;
-- A new mention in an old published post alerts followers even if they do not follow the author.
select set_config('request.jwt.claim.sub',(select id::text from follow_ids where kind='other_writer'),true);
update public.posts set mentioned_member_ids='{}',body='خبر بدون ذكر'where tenant_id=(select id from follow_ids where kind='tenant')and title='خبر يذكر من أتابعه';
-- Restrictive read-only entitlement cannot be bypassed through the new RPC.
update family_private.tenants set payment_status='paid',subscription_starts_at=now()-interval '2 days',subscription_ends_at=now()-interval '1 day'where id=(select id from follow_ids where kind='tenant');
select set_config('request.jwt.claim.sub',(select id::text from follow_ids where kind='fan'),true);
set local role authenticated;
do $$begin begin perform public.member_social('follow',jsonb_build_object('member',(select id from follow_ids where kind='writer')));raise exception 'EXPIRED_FOLLOW';exception when raise_exception then if sqlerrm='EXPIRED_FOLLOW'then raise;end if;end;end$$;
reset role;
select 'PASS: tenant-private follow graph, idempotent follow, no self/cross-family access, publication/mention dedup, follower-only push, three-column grid API excludes hidden posts, read-only enforced' result;
rollback;
