-- Applied to the existing project; do not rerun automatically.
create table public.announcements (
 id bigint generated always as identity primary key,
 author_id uuid not null references public.profiles(id),
 title text not null check(char_length(title) between 3 and 250),
 body text not null check(char_length(body) between 1 and 5000),
 starts_at timestamptz not null default now(),
 ends_at timestamptz not null,
 enabled boolean not null default true,
 created_at timestamptz not null default now(),
 constraint announcement_period check(ends_at>starts_at)
);
alter table public.announcements enable row level security;
create index announcements_window on public.announcements(starts_at,ends_at) where enabled;
create index announcements_author on public.announcements(author_id);
create policy announcements_read on public.announcements for select to authenticated using((select public.my_role())='admin' or ((select public.my_role()) is not null and enabled and starts_at<=now() and ends_at>now()));
create policy announcements_insert on public.announcements for insert to authenticated with check((select public.my_role())='admin' and author_id=(select auth.uid()));
create policy announcements_update on public.announcements for update to authenticated using((select public.my_role())='admin') with check((select public.my_role())='admin');
create policy announcements_delete on public.announcements for delete to authenticated using((select public.my_role())='admin');
grant select,insert,update,delete on public.announcements to authenticated;
grant usage,select on sequence public.announcements_id_seq to authenticated;
create policy family_posts_delete on public.posts for delete to authenticated using((select public.my_role())='admin');
grant delete on public.posts to authenticated;
create policy "news images delete admin" on storage.objects for delete to authenticated using(bucket_id='news-images' and (select public.my_role())='admin');
