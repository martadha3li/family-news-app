create table family_private.storage_limits(id boolean primary key default true check(id),plan text not null default 'free' check(plan in('free','pro','custom')),database_limit bigint not null default 524288000 check(database_limit>0),file_limit bigint not null default 1073741824 check(file_limit>0),updated_at timestamptz not null default now());
insert into family_private.storage_limits(id) values(true);
alter table family_private.storage_limits enable row level security;
create policy storage_limits_lock on family_private.storage_limits for all using(false) with check(false);
revoke all on family_private.storage_limits from public,anon,authenticated;
create function family_private.stale_chat_rooms() returns table(kind text,room uuid,last_at timestamptz,messages bigint,estimated_bytes bigint) language sql stable security definer set search_path='' as $$
select case when group_id is not null then 'group' when thread_id is not null then 'private' else 'public' end,coalesce(group_id,thread_id),max(created_at),count(*),sum(pg_column_size(m))::bigint from family_private.chat_messages m group by group_id,thread_id having max(created_at)<now()-interval '10 months'
$$;
revoke all on function family_private.stale_chat_rooms() from public,anon,authenticated;
create function family_private.storage_maintenance(action text,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare cutoff timestamptz:=now()-interval '10 months';r record;latest timestamptz;n bigint;removed bigint:=0;rooms int:=0;paths text[]:='{}';part text[];begin
 if family_private.access_role()<>'admin' or family_private.access_role() is null then raise exception 'إدارة المساحة للمدير فقط';end if;
 if action='usage' then
 return jsonb_build_object('measured_at',now(),'database_bytes',pg_database_size(current_database()),'storage_bytes',(select coalesce(sum(case when metadata->>'size' ~ '^[0-9]+$' then (metadata->>'size')::bigint else 0 end),0) from storage.objects),'limits',(select to_jsonb(l) from family_private.storage_limits l where id),'buckets',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select bucket_id,count(*) as files,sum(case when metadata->>'size' ~ '^[0-9]+$' then (metadata->>'size')::bigint else 0 end) as bytes from storage.objects group by bucket_id)x),'records',jsonb_build_object('users',(select count(*) from public.profiles),'news',(select count(*) from public.posts),'comments',(select count(*) from public.comments),'messages',(select count(*) from family_private.chat_messages)),'tables',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select n.nspname as schema,c.relname as name,pg_total_relation_size(c.oid) as bytes from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','family_private','auth','storage') and c.relkind='r' order by pg_total_relation_size(c.oid) desc limit 30)x));
 elsif action='limits' then
 update family_private.storage_limits set plan=payload->>'plan',database_limit=(payload->>'database_limit')::bigint,file_limit=(payload->>'file_limit')::bigint,updated_at=now() where id;return 'true';
 elsif action='preview' then
 return jsonb_build_object('cutoff',cutoff,'rooms',(select count(*) from family_private.stale_chat_rooms()),'messages',(select coalesce(sum(messages),0) from family_private.stale_chat_rooms()),'estimated_bytes',(select coalesce(sum(estimated_bytes),0) from family_private.stale_chat_rooms()),'breakdown',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select kind,count(*) as rooms,sum(messages) as messages from family_private.stale_chat_rooms() group by kind)x));
 elsif action='images' then
 return coalesce((select jsonb_agg(to_jsonb(x)) from(select o.bucket_id as bucket,o.name as path,(o.metadata->>'size')::bigint as bytes from storage.objects o where o.bucket_id in('news-images','profile-images') and o.metadata->>'size' ~ '^[0-9]+$' and ((o.bucket_id='news-images' and exists(select 1 from public.posts where image_path=o.name)) or (o.bucket_id='profile-images' and exists(select 1 from public.profiles where avatar_path=o.name))) order by (o.metadata->>'size')::bigint desc limit 2000)x),'[]');
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
end$$;
create function public.storage_maintenance(action text,payload jsonb default '{}') returns jsonb language sql set search_path='' as $$select family_private.storage_maintenance(action,payload)$$;
revoke all on function family_private.storage_maintenance(text,jsonb),public.storage_maintenance(text,jsonb) from public,anon,authenticated;
grant execute on function family_private.storage_maintenance(text,jsonb),public.storage_maintenance(text,jsonb) to authenticated;
do $$declare def text;begin def:=pg_get_functiondef('family_private.chat_send(uuid,text)'::regprocedure);def:=replace(def,'declare mid bigint;begin','declare mid bigint;begin if thread is null then perform pg_advisory_xact_lock(hashtextextended(''family-public-retention'',0));end if;');execute def;end$$;
