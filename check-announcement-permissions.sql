begin;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data,raw_app_meta_data) values('00000000-0000-4000-8000-000000000009','announcement-test@example.invalid',now(),'{}','{}');
update public.profiles set status='active' where id='00000000-0000-4000-8000-000000000009';
select set_config('request.jwt.claims',json_build_object('sub',(select id from public.profiles where is_root),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 insert into public.announcements(author_id,title,body,starts_at,ends_at,enabled) values
 (auth.uid(),'__ad_active_fixture__','Disposable test',now()-interval '1 hour',now()+interval '1 hour',true),
 (auth.uid(),'__ad_future_fixture__','Disposable test',now()+interval '1 hour',now()+interval '2 hour',true),
 (auth.uid(),'__ad_expired_fixture__','Disposable test',now()-interval '2 hour',now()-interval '1 hour',true),
 (auth.uid(),'__ad_disabled_fixture__','Disposable test',now()-interval '1 hour',now()+interval '1 hour',false);
 if (select count(*) from public.announcements where title like '__ad_%_fixture__')<>4 then raise exception 'Admin cannot manage scheduled ads'; end if;
 begin
  insert into public.announcements(author_id,title,body,starts_at,ends_at) values(auth.uid(),'Invalid duration fixture','Disposable test',now(),now()-interval '1 second');
  raise exception 'Invalid duration accepted';
 exception when check_violation then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000009","role":"authenticated"}',true);
do $$begin
 if (select count(*) from public.announcements where title like '__ad_%_fixture__')<>1 then raise exception 'Member sees future, expired or disabled ads'; end if;
 begin
  insert into public.announcements(author_id,title,body,ends_at) values(auth.uid(),'Forbidden announcement','Disposable test',now()+interval '1 hour');
  raise exception 'Member created advertisement';
 exception when insufficient_privilege then null; end;
end $$;
set local role anon;
do $$begin if exists(select 1 from public.announcements) then raise exception 'Anonymous announcement exposure'; end if; end $$;
select 'PASS: active-only member visibility; future/expired/disabled ads hidden; admin-only management; invalid periods rejected; anonymous isolation' as result;
rollback;
