begin;
alter table public.announcements add column is_popup boolean not null default false,
 add column image_path text,
 add column display_seconds integer not null default 8 check(display_seconds between 1 and 300),
 add column repeat_days integer not null default 1 check(repeat_days between 1 and 3650),
 add constraint popup_image_required check(not is_popup or (image_path is not null and image_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$'));
create table public.ad_preferences(
 user_id uuid not null references public.profiles(id) on delete cascade,
 ad_id bigint not null references public.announcements(id) on delete cascade,
 last_shown_at timestamptz not null default now(),
 hidden boolean not null default false,
 primary key(user_id,ad_id)
);
alter table public.ad_preferences enable row level security;
grant select,insert,update on public.ad_preferences to authenticated;
create policy own_ad_preferences on public.ad_preferences for all to authenticated
 using(user_id=(select auth.uid()) and (select public.my_role()) is not null)
 with check(user_id=(select auth.uid()) and (select public.my_role()) is not null);
create function public.promo_claim(ad_id bigint) returns boolean language plpgsql security invoker set search_path='' as $$
declare days integer; claimed boolean;
begin
 select a.repeat_days into days from public.announcements a where a.id=promo_claim.ad_id and a.is_popup and a.enabled and a.starts_at<=now() and a.ends_at>now();
 if days is null or auth.uid() is null or public.my_role() is null then return false;end if;
 insert into public.ad_preferences(user_id,ad_id,last_shown_at) values(auth.uid(),promo_claim.ad_id,now())
 on conflict on constraint ad_preferences_pkey do update set last_shown_at=excluded.last_shown_at
 where not ad_preferences.hidden and ad_preferences.last_shown_at<=now()-make_interval(days=>days)
 returning true into claimed;
 return coalesce(claimed,false);
end$$;
create function public.promo_hide(ad_id bigint,hide boolean) returns void language plpgsql security invoker set search_path='' as $$
begin
 update public.ad_preferences p set hidden=hide where p.user_id=auth.uid() and p.ad_id=promo_hide.ad_id;
end$$;
revoke all on function public.promo_claim(bigint),public.promo_hide(bigint,boolean) from public,anon;
grant execute on function public.promo_claim(bigint),public.promo_hide(bigint,boolean) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('ad-images','ad-images',false,409600,array['image/jpeg']);
create policy ad_image_upload on storage.objects for insert to authenticated with check(bucket_id='ad-images' and (select public.my_role())='admin' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy ad_image_read on storage.objects for select to authenticated using(bucket_id='ad-images' and (select public.my_role()) is not null and ((select public.my_role())='admin' or exists(select 1 from public.announcements a where a.image_path=name and a.is_popup and a.enabled and a.starts_at<=now() and a.ends_at>now())));
create policy ad_image_delete on storage.objects for delete to authenticated using(bucket_id='ad-images' and (select public.my_role())='admin');
notify pgrst,'reload schema';
commit;
