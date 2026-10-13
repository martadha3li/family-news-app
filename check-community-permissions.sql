begin;
create temp table fixture_ids(label text,id uuid,phone text);insert into fixture_ids values('male',gen_random_uuid(),'+966500001011'),('journalist',gen_random_uuid(),'+966500001012'),('female',gen_random_uuid(),'+966500001013'),('unknown',gen_random_uuid(),null);
grant select on fixture_ids to authenticated;
insert into public.allowed_families(name) values('اختبارنظام');
update public.family_settings set restrict_gender_chat=true,journalist_approval=true;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) select id,id::text||'@example.invalid',now(),jsonb_build_object('full_name',label||' ابن جد اختبارنظام','display_name',label||' ابن جد اختبارنظام','phone',phone,'gender',case when label='female' then 'female' when label='unknown' then null else 'male' end,'reference_name','male ابن جد اختبارنظام','relationship',case when label='female' then 'father' else null end) from fixture_ids order by case label when 'male' then 1 when 'journalist' then 2 when 'female' then 3 else 4 end;
update public.profiles set status='active' where id in(select id from fixture_ids);
update public.profiles set role='journalist' where id=(select id from fixture_ids where label='journalist');
select set_config('request.jwt.claim.sub',(select id::text from fixture_ids where label='male'),true);
set local role authenticated;
do $$declare hits jsonb;t uuid;begin
 hits=public.chat_search('ابن');if hits::text like '%female%' or hits::text like '%unknown%' then raise exception 'Opposite or unknown gender leaked';end if;
 t=public.chat_open((select id from fixture_ids where label='journalist'));perform public.chat_send(t,'رسالة اختبار خاصة');
 begin perform public.chat_open((select id from fixture_ids where label='female'));raise exception 'BLOCK_FAILED';exception when others then if SQLERRM='BLOCK_FAILED' then raise;end if;end;
 perform public.profile_get();
 begin perform public.member_detail((select id from fixture_ids where label='female'));raise exception 'BLOCK_FAILED';exception when others then if SQLERRM='BLOCK_FAILED' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from fixture_ids where label='female'),true);
set local role authenticated;
do $$begin
 begin perform public.chat_read((select (public.chat_list()->0->>'id')::uuid),null);exception when others then null;end;
 if public.chat_search('male')<>'[]'::jsonb then raise exception 'Male search visible to female';end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from fixture_ids where label='journalist'),true);
set local role authenticated;
do $$declare pid bigint;v record;begin
 insert into public.posts(author_id,title,body,published) values(auth.uid(),'اختبار مراجعة','اختبار آمن لا يبقى بعد التراجع',true) returning id into pid;
 select published,moderation_status into v from public.posts where id=pid;
 if v.published or v.moderation_status<>'pending' then raise exception 'Moderation bypass';end if;
end $$;
reset role;
update public.family_settings set journalist_approval=false;
set local role authenticated;
do $$declare v record;begin
 insert into public.posts(author_id,title,body,published) values(auth.uid(),'اختبار مباشر','اختبار آمن لا يبقى بعد التراجع',true) returning published,moderation_status into v;
 if not v.published or v.moderation_status<>'published' then raise exception 'Direct publication failed';end if;
end $$;
reset role;
update public.family_settings set chat_enabled=false;
set local role authenticated;
do $$begin
 if public.chat_search('male')<>'[]'::jsonb then raise exception 'Search when disabled';end if;
 begin perform public.chat_send(null,'رسالة مرفوضة');raise exception 'BLOCK_FAILED';exception when others then if SQLERRM='BLOCK_FAILED' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$begin
 begin perform public.profile_get();raise exception 'BLOCK_FAILED';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: private chat isolation, gender search, chat shutdown, publication approval, direct publication, admin private details and anonymous blocking' as result;
rollback;
