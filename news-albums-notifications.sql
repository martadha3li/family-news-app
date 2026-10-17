begin;
alter table public.posts add column if not exists image_paths text[] not null default '{}';
alter table public.posts add column if not exists published_at timestamptz;
update public.posts set image_paths=array[image_path] where image_path is not null and cardinality(image_paths)=0;
update public.posts set published_at=created_at where published and published_at is null;
create or replace function family_private.normalize_post_album() returns trigger language plpgsql set search_path='' as $$
declare path text;begin
 if TG_OP='INSERT' then
  if cardinality(new.image_paths)=0 and new.image_path is not null then new.image_paths=array[new.image_path];end if;
 elsif new.image_paths is not distinct from old.image_paths and new.image_path is distinct from old.image_path then
  -- An older client changes only the cover: preserve the rest of the album.
  new.image_paths=case when new.image_path is null then coalesce(old.image_paths[2:5],'{}') else array[new.image_path]||coalesce(old.image_paths[2:5],'{}') end;
 end if;
 if cardinality(new.image_paths)>5 or array_ndims(new.image_paths)>1 or array_position(new.image_paths,null) is not null then raise exception 'الخبر يدعم من صفر إلى خمس صور فقط';end if;
 foreach path in array new.image_paths loop
  if path !~ ('^'||new.author_id::text||'/[a-zA-Z0-9_.-]+$') then raise exception 'مسار الصورة لا يخص صاحب الخبر';end if;
 end loop;
 if cardinality(new.image_paths)<>(select count(distinct p) from unnest(new.image_paths) p) then raise exception 'لا يمكن تكرار الصورة في الخبر';end if;
 new.image_path=new.image_paths[1];return new;
end$$;
revoke all on function family_private.normalize_post_album() from public,anon,authenticated;
create trigger a_normalize_post_album before insert or update on public.posts for each row execute function family_private.normalize_post_album();
alter table public.posts add constraint posts_album_limit check (cardinality(image_paths)<=5);
create or replace function family_private.stamp_news_publication() returns trigger language plpgsql set search_path='' as $$begin
 if TG_OP='INSERT' then new.published_at=case when new.published then now() else null end;
 elsif new.published and not old.published then new.published_at=now();
 else new.published_at=old.published_at;end if;
 return new;
end$$;
revoke all on function family_private.stamp_news_publication() from public,anon,authenticated;
create trigger z_stamp_news_publication before insert or update on public.posts for each row execute function family_private.stamp_news_publication();
create index posts_image_paths_gin on public.posts using gin(image_paths);
alter policy "news images read approved" on storage.objects using(bucket_id='news-images' and (select family_private.access_role()) is not null and ((storage.foldername(name))[1]=(select auth.uid())::text or (select family_private.access_role())='admin' or exists(select 1 from public.posts p where name=any(p.image_paths) and p.published and p.deleted_at is null)));
-- Private read watermark: never expose recipient state or message tables.
create table family_private.notification_reads(user_id uuid primary key references public.profiles(id) on delete cascade,read_at timestamptz not null default now());
alter table family_private.notification_reads enable row level security;
revoke all on family_private.notification_reads from public,anon,authenticated;
create or replace function family_private.native_notifications(action text,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();watermark timestamptz;cutoff timestamptz:=clock_timestamp();items jsonb;begin
 if uid is null or family_private.access_role() is null then raise exception 'حساب غير معتمد';end if;
 insert into family_private.notification_reads(user_id) values(uid) on conflict do nothing;
 if action='read' then
  if nullif(payload->>'through','') is null then raise exception 'وقت القراءة مطلوب';end if;
  update family_private.notification_reads set read_at=greatest(read_at,least((payload->>'through')::timestamptz,cutoff)) where user_id=uid;
 elsif action<>'list' then raise exception 'إجراء غير معروف';end if;
 select read_at into watermark from family_private.notification_reads where user_id=uid;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id),'[]') into items from (
  (select 'news:'||p.id as id,'news'::text as kind,p.title,p.published_at as created_at,p.id::text as post_id,null::text as thread_id,null::text as member_id,null::text as avatar_path
   from public.posts p where p.published and p.deleted_at is null and p.published_at is not null and p.published_at<=cutoff and p.author_id<>uid order by p.published_at desc,p.id desc limit 100)
  union all
  (select 'message:'||m.id,'private'::text,p.display_name,m.created_at,null::text,m.thread_id::text,p.id::text,p.avatar_path
   from family_private.chat_messages m join family_private.chat_threads t on t.id=m.thread_id join public.profiles p on p.id=m.sender_id
   where uid in(t.member_a,t.member_b) and m.sender_id<>uid and m.group_id is null and m.deleted_at is null and m.created_at<=cutoff
    and (select chat_enabled and private_chat_enabled from public.family_settings where id)
    and family_private.chat_pair_allowed(m.sender_id)
   order by m.created_at desc,m.id desc limit 100)
  order by created_at desc,id limit 100
 ) x;
 return jsonb_build_object('items',items,'read_at',watermark,'server_at',cutoff);
end$$;
create function public.native_notifications(action text default 'list',payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select family_private.native_notifications(action,payload) $$;
revoke all on function family_private.native_notifications(text,jsonb),public.native_notifications(text,jsonb) from public,anon,authenticated;
grant execute on function family_private.native_notifications(text,jsonb),public.native_notifications(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
CREATE OR REPLACE FUNCTION family_private.storage_image_info(bucket text, path text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 if family_private.access_role()<>'admin' or family_private.access_role() is null then raise exception 'للمدير فقط';end if;
 return(select jsonb_build_object('bytes',(o.metadata->>'size')::bigint) from storage.objects o where o.bucket_id=bucket and o.name=path and o.bucket_id in('news-images','profile-images') and ((o.bucket_id='news-images' and exists(select 1 from public.posts where o.name=any(image_paths))) or (o.bucket_id='profile-images' and exists(select 1 from public.profiles where avatar_path=o.name))));
end$function$
;
CREATE OR REPLACE FUNCTION family_private.storage_maintenance(action text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cutoff timestamptz:=now()-interval '10 months';r record;latest timestamptz;n bigint;removed bigint:=0;rooms int:=0;paths text[]:='{}';part text[];begin
 if family_private.access_role()<>'admin' or family_private.access_role() is null then raise exception 'إدارة المساحة للمدير فقط';end if;
 if action='usage' then
 return jsonb_build_object('measured_at',now(),'database_bytes',pg_database_size(current_database()),'storage_bytes',(select coalesce(sum(case when metadata->>'size' ~ '^[0-9]+$' then (metadata->>'size')::bigint else 0 end),0) from storage.objects),'limits',(select to_jsonb(l) from family_private.storage_limits l where id),'buckets',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select bucket_id,count(*) as files,sum(case when metadata->>'size' ~ '^[0-9]+$' then (metadata->>'size')::bigint else 0 end) as bytes from storage.objects group by bucket_id)x),'records',jsonb_build_object('users',(select count(*) from public.profiles),'news',(select count(*) from public.posts),'comments',(select count(*) from public.comments),'messages',(select count(*) from family_private.chat_messages)),'tables',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select n.nspname as schema,c.relname as name,pg_total_relation_size(c.oid) as bytes from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','family_private','auth','storage') and c.relkind='r' order by pg_total_relation_size(c.oid) desc limit 30)x));
 elsif action='limits' then
 update family_private.storage_limits set plan=payload->>'plan',database_limit=(payload->>'database_limit')::bigint,file_limit=(payload->>'file_limit')::bigint,updated_at=now() where id;return 'true';
 elsif action='preview' then
 return jsonb_build_object('cutoff',cutoff,'rooms',(select count(*) from family_private.stale_chat_rooms()),'messages',(select coalesce(sum(messages),0) from family_private.stale_chat_rooms()),'estimated_bytes',(select coalesce(sum(estimated_bytes),0) from family_private.stale_chat_rooms()),'breakdown',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select kind,count(*) as rooms,sum(messages) as messages from family_private.stale_chat_rooms() group by kind)x));
 elsif action='images' then
 return coalesce((select jsonb_agg(to_jsonb(x)) from(select o.bucket_id as bucket,o.name as path,(o.metadata->>'size')::bigint as bytes from storage.objects o where o.bucket_id in('news-images','profile-images') and o.metadata->>'size' ~ '^[0-9]+$' and ((o.bucket_id='news-images' and exists(select 1 from public.posts where o.name=any(image_paths))) or (o.bucket_id='profile-images' and exists(select 1 from public.profiles where avatar_path=o.name))) order by (o.metadata->>'size')::bigint desc limit 2000)x),'[]');
 elsif action='orphan_media' then
 return coalesce((select jsonb_agg(o.name) from storage.objects o where o.bucket_id='chat-media' and o.name in(select jsonb_array_elements_text(payload->'paths')) and not exists(select 1 from family_private.chat_messages where attachment_path=o.name)),'[]');
 elsif action='clean_chats' then
 if payload->>'confirm' is distinct from 'DELETE_OLD_CHATS' then raise exception 'يجب تأكيد حذف الدردشات الخاملة';end if;
 -- Lock parent rooms so concurrent sends cannot be deleted from an active room.
 for r in select t.id from family_private.chat_threads t where (select max(created_at) from family_private.chat_messages where thread_id=t.id and group_id is null)<cutoff order by t.id for update loop
 select max(created_at) into latest from family_private.chat_messages where thread_id=r.id and group_id is null;
 if latest<cutoff then
 select array_agg(attachment_path) filter(where attachment_path is not null) into part from family_private.chat_messages where thread_id=r.id and group_id is null;paths:=paths||coalesce(part,'{}');
 update family_private.chat_messages set reply_to=null where reply_to in(select id from family_private.chat_messages where thread_id=r.id and group_id is null);
 delete from family_private.chat_messages where thread_id=r.id and group_id is null;get diagnostics n=row_count;removed:=removed+n;rooms:=rooms+1;
 end if;end loop;
 for r in select g.id from family_private.chat_groups g where (select max(created_at) from family_private.chat_messages where group_id=g.id)<cutoff order by g.id for update loop
 select max(created_at) into latest from family_private.chat_messages where group_id=r.id;
 if latest<cutoff then
 select array_agg(attachment_path) filter(where attachment_path is not null) into part from family_private.chat_messages where group_id=r.id;paths:=paths||coalesce(part,'{}');
 update family_private.chat_messages set reply_to=null where reply_to in(select id from family_private.chat_messages where group_id=r.id);
 delete from family_private.chat_messages where group_id=r.id;get diagnostics n=row_count;removed:=removed+n;rooms:=rooms+1;
 end if;end loop;
 perform pg_advisory_xact_lock(hashtextextended('family-public-retention',0));
 select max(created_at) into latest from family_private.chat_messages where thread_id is null and group_id is null;
 if latest<cutoff then
 select array_agg(attachment_path) filter(where attachment_path is not null) into part from family_private.chat_messages where thread_id is null and group_id is null;paths:=paths||coalesce(part,'{}');
 update family_private.chat_messages set reply_to=null where reply_to in(select id from family_private.chat_messages where thread_id is null and group_id is null);
 delete from family_private.chat_messages where thread_id is null and group_id is null;get diagnostics n=row_count;removed:=removed+n;rooms:=rooms+1;
 end if;
 return jsonb_build_object('rooms',rooms,'messages',removed,'media_paths',to_jsonb(paths));
 else raise exception 'إجراء غير معروف';end if;
end$function$
;
create policy notification_reads_private_only on family_private.notification_reads for all to authenticated using(false) with check(false);
create or replace function family_private.moderate_post() returns trigger language plpgsql security definer set search_path='' as $$declare r text;begin
 if auth.uid() is null then return new;end if;r=family_private.access_role();
 if TG_OP='UPDATE' and new.author_id<>old.author_id then raise exception 'لا يمكن تغيير صاحب الخبر';end if;
 if r='journalist' then
  if new.author_id<>auth.uid() then raise exception 'الخبر ليس لك';end if;
  if new.published then if (select journalist_approval from public.family_settings where id) then new.published=false;new.moderation_status='pending';else new.moderation_status='published';end if;
  elsif TG_OP='INSERT' or new.title is distinct from old.title or new.body is distinct from old.body or new.image_paths is distinct from old.image_paths then new.moderation_status='draft';end if;
 elsif r='admin' then if new.published then new.moderation_status='published';elsif new.moderation_status='published' then new.moderation_status='draft';end if;
 else raise exception 'النشر للمدير والصحفي فقط';end if;return new;
end $$;
