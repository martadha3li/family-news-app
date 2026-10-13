begin;
create schema if not exists family_private;
revoke all on schema family_private from public;
grant usage on schema family_private to authenticated;
alter table public.profiles add column if not exists status text not null default 'pending' check(status in ('pending','active','suspended'));
alter table public.profiles add column if not exists is_root boolean not null default false;
create unique index if not exists one_family_root on public.profiles(is_root) where is_root;
alter table public.posts add column if not exists deleted_at timestamptz;
alter table public.posts add constraint news_body_size check (char_length(body) between 1 and 20000);
create index if not exists posts_feed on public.posts(created_at desc,id desc) where published and deleted_at is null;
create index if not exists comments_post_created on public.comments(post_id,created_at,id);
create index if not exists posts_author on public.posts(author_id);
create index if not exists comments_author on public.comments(author_id);
create index if not exists likes_user on public.likes(user_id);
create or replace function family_private.access_role() returns text language sql stable security definer set search_path='' as $$
 select p.role from public.profiles p join auth.users u on u.id=p.id
 where (select auth.uid()) is not null and p.id=(select auth.uid()) and p.status='active' and u.email_confirmed_at is not null
$$;
revoke all on function family_private.access_role() from public,anon;
grant execute on function family_private.access_role() to authenticated;
create or replace function public.my_role() returns text language sql stable set search_path='' as $$select family_private.access_role()$$;
revoke all on function public.my_role() from public,anon;
grant execute on function public.my_role() to authenticated;
create or replace function family_private.enroll() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,display_name) values(new.id,left(coalesce(nullif(new.raw_user_meta_data->>'display_name',''),'عضو'),80)) on conflict(id) do nothing;
 if lower(new.email)='martadha3li@gmail.com' and new.email_confirmed_at is not null and not exists(select 1 from public.profiles where is_root and id<>new.id) then
  update public.profiles set role='admin',status='active',is_root=true where id=new.id;
 end if;
 return new;
end $$;
revoke all on function family_private.enroll() from public,anon,authenticated;
create trigger family_enroll after insert or update of email,email_confirmed_at on auth.users for each row execute function family_private.enroll();
create or replace function family_private.protect_root() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('authenticated','anon') and (new.id<>old.id or new.is_root<>old.is_root or (old.is_root and (new.role<>old.role or new.status<>old.status))) then raise exception 'الحساب الرئيسي محمي'; end if;
 return new;
end $$;
revoke all on function family_private.protect_root() from public,anon,authenticated;
create trigger family_protect_root before update on public.profiles for each row execute function family_private.protect_root();
do $$declare p record;begin
 for p in select * from pg_policies where (schemaname='public' and tablename in ('profiles','posts','comments','likes')) or (schemaname='storage' and tablename='objects' and policyname like 'news images%') loop
 execute format('alter policy %I on %I.%I %s',p.policyname,p.schemaname,p.tablename,case when p.cmd='INSERT' then 'with check(false)' when p.cmd='UPDATE' then 'using(false) with check(false)' else 'using(false)' end);
 end loop;
end $$;
create policy family_profiles_read on public.profiles for select to authenticated using(id=(select auth.uid()) or (select family_private.access_role()) is not null);
create policy family_profiles_manage on public.profiles for update to authenticated using((select family_private.access_role())='admin') with check((select family_private.access_role())='admin');
create policy family_posts_read on public.posts for select to authenticated using((select family_private.access_role()) is not null and ((published and deleted_at is null) or author_id=(select auth.uid()) or (select family_private.access_role())='admin'));
create policy family_posts_insert on public.posts for insert to authenticated with check(author_id=(select auth.uid()) and (select family_private.access_role()) in ('admin','journalist') and deleted_at is null);
create policy family_posts_update on public.posts for update to authenticated using((select family_private.access_role())='admin' or ((select family_private.access_role())='journalist' and author_id=(select auth.uid()))) with check((select family_private.access_role())='admin' or ((select family_private.access_role())='journalist' and author_id=(select auth.uid())));
create policy family_comments_read on public.comments for select to authenticated using((select family_private.access_role()) is not null and exists(select 1 from public.posts p where p.id=post_id and p.published and p.deleted_at is null));
create policy family_comments_insert on public.comments for insert to authenticated with check((select family_private.access_role()) is not null and author_id=(select auth.uid()) and parent_id is null and exists(select 1 from public.posts p where p.id=post_id and p.published and p.deleted_at is null));
create policy family_comments_delete on public.comments for delete to authenticated using((select family_private.access_role()) is not null and (author_id=(select auth.uid()) or (select family_private.access_role())='admin'));
create policy family_likes_read on public.likes for select to authenticated using((select family_private.access_role()) is not null and exists(select 1 from public.posts p where p.id=post_id and p.published and p.deleted_at is null));
create policy family_likes_insert on public.likes for insert to authenticated with check((select family_private.access_role()) is not null and user_id=(select auth.uid()) and exists(select 1 from public.posts p where p.id=post_id and p.published and p.deleted_at is null));
create policy family_likes_delete on public.likes for delete to authenticated using(user_id=(select auth.uid()) and (select family_private.access_role()) is not null);
create policy "news images read approved" on storage.objects for select to authenticated using(bucket_id='news-images' and (select family_private.access_role()) is not null and ((storage.foldername(name))[1]=(select auth.uid())::text or (select family_private.access_role())='admin' or exists(select 1 from public.posts p where p.image_path=name and p.published and p.deleted_at is null)));
create policy "news images upload editors" on storage.objects for insert to authenticated with check(bucket_id='news-images' and (select family_private.access_role()) in ('admin','journalist') and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "news images delete own" on storage.objects for delete to authenticated using(bucket_id='news-images' and (select family_private.access_role()) in ('admin','journalist') and (storage.foldername(name))[1]=(select auth.uid())::text);
update storage.buckets set public=false,file_size_limit=409600,allowed_mime_types=array['image/jpeg','image/webp','image/png'] where id='news-images';
revoke insert,delete on public.profiles from authenticated;
revoke delete on public.posts from authenticated;
grant select,update on public.profiles to authenticated;
grant select,insert,update on public.posts to authenticated;
grant select,insert,delete on public.comments,public.likes to authenticated;
alter table public.posts add constraint own_news_image check (image_path is null or image_path like author_id::text || '/%');
commit;
