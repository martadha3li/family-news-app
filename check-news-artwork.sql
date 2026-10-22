begin;
create temp table follow_ids(kind text,id uuid);grant select on follow_ids to authenticated;
insert into follow_ids values('tenant',gen_random_uuid()),('other_tenant',gen_random_uuid()),('writer',gen_random_uuid()),('subject',gen_random_uuid()),('fan',gen_random_uuid()),('outsider',gen_random_uuid()),('other_writer',gen_random_uuid());
insert into family_private.tenants(id,code,name,status,contact_phone,contact_email,payment_status)select id,case kind when 'tenant'then 'FOLLOW-TEST'else 'FOLLOW-OTHER'end,'اختبار المتابعة','active','+966500007701',kind||'-follow@example.invalid','waived'from follow_ids where kind in('tenant','other_tenant');
select set_config('request.jwt.claim.sub',(select user_id::text from family_private.platform_admins limit 1),true);
select public.platform_action('save',jsonb_build_object('id',id,'status','active','payment_status','waived'))from follow_ids where kind in('tenant','other_tenant');
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_user_meta_data)select id,'authenticated','authenticated',kind||'-follow@example.invalid',now(),jsonb_build_object('family_code',case kind when 'outsider'then 'FOLLOW-OTHER'else 'FOLLOW-TEST'end,'full_name',kind||' احمد حسن اختبار','display_name',kind||' احمد حسن اختبار','gender','male','phone',case kind when 'writer'then '+966500007701'when 'subject'then '+966500007702'when 'fan'then '+966500007703'when 'other_writer'then '+966500007705'else '+966500007704'end)from follow_ids where kind in('writer','subject','fan','outsider','other_writer');
update public.profiles set status='active',role=case when id in(select id from follow_ids where kind in('writer','other_writer'))then 'admin'else 'member'end where id in(select id from follow_ids);
update public.family_settings set journalist_approval=false where tenant_id=(select id from follow_ids where kind='tenant');




update family_private.tenants set code='ARTWORK-ORIGINAL'where code='01';
update family_private.tenants set code='01'where id=(select id from follow_ids where kind='tenant');
create temp table artwork_test(k text,v text);grant all on artwork_test to authenticated;
select set_config('request.jwt.claim.sub',(select id::text from follow_ids where kind='writer'),true);
set local role authenticated;
insert into artwork_test select 'template',public.news_request_action('template_save','{"name":"اختبار مولود","kind":"newborn","artwork_key":"newborn","body":"نبارك {subject} بالمولود {newborn}. {details}"}')#>>'{}';
do $$declare key text;begin foreach key in array array['family','mansoura','marriage','icu','honor','ramadan','wedding','job','funeral']loop perform public.news_request_action('template_save',jsonb_build_object('name','اختبار '||key,'kind','general','artwork_key',key,'body','خبر {subject} {details}'));end loop;end$$;
reset role;
insert into storage.objects(bucket_id,name,metadata)select 'news-images',id::text||'/artwork-photo.jpg','{"size":1234,"mimetype":"image/jpeg"}'::jsonb from follow_ids where kind='fan';
select set_config('request.jwt.claim.sub',(select id::text from follow_ids where kind='fan'),true);
set local role authenticated;
insert into artwork_test select 'request',public.news_request_action('submit',jsonb_build_object('template',(select v from artwork_test where k='template'),'subject','أحمد علي','newborn','علي','details','تفاصيل','smart_crop_enabled',true,'artwork_only',true,'artwork_face',jsonb_build_object('x',0.5,'y',0.1,'width',0.15,'height',0.2),'image_paths',jsonb_build_array(auth.uid()::text||'/artwork-photo.jpg')))#>>'{}';
do $$begin if public.news_request_action('list')->0->>'artwork_key'<>'newborn'then raise exception 'SNAPSHOT_MISSING';end if;end$$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from follow_ids where kind='writer'),true);
set local role authenticated;
select public.news_request_action('claim',jsonb_build_object('id',(select v from artwork_test where k='request')));
insert into artwork_test select 'post',public.news_request_action('approve',jsonb_build_object('id',(select v from artwork_test where k='request')))->>'post_id';
do $$begin if not exists(select 1 from public.posts where id=(select v::bigint from artwork_test where k='post')and news_artwork='newborn'and artwork_smart_crop and artwork_only and artwork_face @> '{"x":0.5,"width":0.15}'::jsonb and image_paths=array[(select id::text||'/artwork-photo.jpg'from follow_ids where kind='fan')])then raise exception 'ARTWORK_ORIGINAL_OPT_OUT_LOST';end if;end$$;
insert into public.posts(author_id,title,body,published)values(auth.uid(),'ترقية أحمد','تفاصيل الترقية',true);
do $$begin if not exists(select 1 from public.posts where author_id=auth.uid()and title='ترقية أحمد'and news_artwork='promotion')then raise exception 'TITLE_MAP_FAILED';end if;end$$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from follow_ids where kind='outsider'),true);
reset role;update public.profiles set role='admin'where id=auth.uid();set local role authenticated;
do $$begin begin perform public.news_request_action('template_save','{"name":"خاص بعائلة أخرى","kind":"general","artwork_key":"newborn","body":"نبارك {subject}"}');raise exception 'CROSS_BRAND';exception when raise_exception then if sqlerrm='CROSS_BRAND'then raise;end if;end;end$$;
insert into public.posts(author_id,title,body,published,news_artwork)values(auth.uid(),'ترقية خارجية','بدون شعار عائلة أخرى',true,'promotion');
do $$begin if exists(select 1 from public.posts where author_id=auth.uid()and news_artwork is not null)then raise exception 'CROSS_BRAND_POST';end if;end$$;
reset role;do $$begin if family_private.valid_artwork_face('{"x":0.9,"y":0.1,"width":0.5,"height":0.2}')or family_private.valid_artwork_face('{"x":"bad","y":0,"width":1,"height":1}')then raise exception 'INVALID_FACE';end if;end$$;select 'PASS template snapshot, title mapping, original photo retained, crop opt-out, branded family isolation and review authorization' result;rollback;
