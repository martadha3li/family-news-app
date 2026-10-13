begin;
insert into auth.users(id,email,raw_user_meta_data,raw_app_meta_data) values
 ('00000000-0000-4000-8000-000000000001','Martadha3li@gmail.com','{}','{}'),
 ('00000000-0000-4000-8000-000000000002','journalist@example.invalid','{}','{}'),
 ('00000000-0000-4000-8000-000000000003','member@example.invalid','{}','{}'),
 ('00000000-0000-4000-8000-000000000004','pending@example.invalid','{}','{}');
do $$begin if exists(select 1 from public.profiles where is_root) then raise exception 'Unverified owner gained root'; end if; end $$;
update auth.users set email_confirmed_at=now() where id::text like '00000000-0000-4000-8000-00000000000%';
update public.profiles set status='active',role='journalist' where id='00000000-0000-4000-8000-000000000002';
update public.profiles set status='active' where id='00000000-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
insert into public.posts(author_id,title,body,published,image_path) values('00000000-0000-4000-8000-000000000002','خبر اختبار','نص اختبار للتخزين والاسترجاع',true,'00000000-0000-4000-8000-000000000002/test.jpg');
do $$begin if (select count(*) from public.posts where title='خبر اختبار')<>1 then raise exception 'Journalist publish failed'; end if; end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
insert into public.comments(post_id,author_id,body) select id,'00000000-0000-4000-8000-000000000003','تعليق اختبار' from public.posts where title='خبر اختبار';
insert into public.likes(post_id,user_id) select id,'00000000-0000-4000-8000-000000000003' from public.posts where title='خبر اختبار';
do $$declare n int;begin
 if (select count(*) from public.comments)<>1 or (select count(*) from public.likes)<>1 then raise exception 'Member interactions failed'; end if;
 begin
  insert into public.posts(author_id,title,body,published) values('00000000-0000-4000-8000-000000000003','خبر ممنوع','محاولة عضو',true);
  raise exception 'Member could publish';
 exception when insufficient_privilege then null; end;
 update public.profiles set role='admin' where id='00000000-0000-4000-8000-000000000003'; get diagnostics n=row_count;
 if n<>0 then raise exception 'Member promoted self'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
do $$begin
 if (select count(*) from public.posts)<>0 or (select count(*) from public.comments)<>0 or (select count(*) from public.likes)<>0 then raise exception 'Pending account sees private data'; end if;
 if (select count(*) from public.profiles)<>1 then raise exception 'Pending account sees other profiles'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$begin
 if public.my_role()<>'admin' then raise exception 'Verified owner not admin'; end if;
 begin
  update public.profiles set role='member' where is_root;
  raise exception 'Root demotion permitted';
 exception when raise_exception then if sqlerrm<>'الحساب الرئيسي محمي' then raise; end if; end;
end $$;
update public.posts set deleted_at=now() where title='خبر اختبار';
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
do $$begin if (select count(*) from public.posts)<>0 then raise exception 'Member sees hidden post'; end if; end $$;
set local role anon;
do $$begin if (select count(*) from public.posts)<>0 or (select count(*) from public.profiles)<>0 then raise exception 'Anonymous data exposure'; end if; end $$;
select 'PASS: verified root, journalist publication, member comments and likes, pending/anonymous isolation, no self promotion, hidden post protection' as result;
rollback;
