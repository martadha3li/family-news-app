alter table family_private.chat_messages add column attachment_path text,add column attachment_type text,add column attachment_name text;
create index chat_attachment_path on family_private.chat_messages(attachment_path) where attachment_path is not null;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('chat-media','chat-media',false,2097152,array['image/jpeg','image/png','image/webp','audio/webm','audio/mp4','audio/ogg','audio/mpeg','application/pdf']);
create function family_private.message_visible(mid bigint) returns boolean language plpgsql stable security definer set search_path='' as $$declare m family_private.chat_messages;a jsonb;begin
 if family_private.access_role() is null then return false;end if;
 select * into m from family_private.chat_messages where id=mid;
 if m.id is null or m.deleted_at is not null then return false;end if;
 if m.group_id is not null then a:=family_private.group_action('read',jsonb_build_object('id',m.group_id,'before_id',m.id+1));else a:=family_private.chat_read(m.thread_id,m.id+1);end if;
 return exists(select 1 from jsonb_array_elements(a)x where (x->>'id')::bigint=mid);
exception when others then return false;end$$;
revoke all on function family_private.message_visible(bigint) from public,anon,authenticated;
grant execute on function family_private.message_visible(bigint) to authenticated;
create function family_private.media_path_allowed(path text) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from family_private.chat_messages m where m.attachment_path=path and family_private.message_visible(m.id))$$;
revoke all on function family_private.media_path_allowed(text) from public,anon,authenticated;
grant execute on function family_private.media_path_allowed(text) to authenticated;
create policy "chat media upload own" on storage.objects for insert to authenticated with check(bucket_id='chat-media' and (storage.foldername(name))[1]=auth.uid()::text and family_private.access_role() is not null and (select chat_enabled from public.family_settings where id));
create policy "chat media read room" on storage.objects for select to authenticated using(bucket_id='chat-media' and family_private.access_role() is not null and (select chat_enabled from public.family_settings where id) and ((storage.foldername(name))[1]=auth.uid()::text or family_private.media_path_allowed(name)));
create policy "chat media delete own" on storage.objects for delete to authenticated using(bucket_id='chat-media' and (storage.foldername(name))[1]=auth.uid()::text and family_private.access_role() is not null);
create function family_private.media_send(payload jsonb) returns bigint language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();mid bigint;gid uuid:=nullif(payload->>'group','')::uuid;tid uuid:=nullif(payload->>'thread','')::uuid;path text:=payload->>'path';mime text;begin
 if family_private.access_role() is null then raise exception 'حساب غير معتمد';end if;
 select metadata->>'mimetype' into mime from storage.objects where bucket_id='chat-media' and name=path and (storage.foldername(name))[1]=uid::text;
 if mime is null then raise exception 'المرفق غير محفوظ في حسابك';end if;
 if gid is not null then mid:=(family_private.group_action('send',jsonb_build_object('id',gid,'message','[مرفق]'))#>>'{}')::bigint;else mid:=family_private.chat_send(tid,'[مرفق]');end if;
 update family_private.chat_messages set attachment_path=path,attachment_type=mime,attachment_name=left(coalesce(payload->>'name','مرفق'),150) where id=mid;return mid;
end$$;
create function public.media_send(payload jsonb) returns bigint language sql set search_path='' as $$select family_private.media_send(payload)$$;
revoke all on function family_private.media_send(jsonb),public.media_send(jsonb) from public,anon,authenticated;
grant execute on function family_private.media_send(jsonb),public.media_send(jsonb) to authenticated;
do $$declare def text;begin
 def:=pg_get_functiondef('family_private.chat_read(uuid,bigint)'::regprocedure);def:=replace(def,'m.body,m.created_at','m.body,m.created_at,m.attachment_path,m.attachment_type,m.attachment_name');execute def;
 def:=pg_get_functiondef('family_private.group_action(text,jsonb)'::regprocedure);def:=replace(def,'m.body,m.created_at','m.body,m.created_at,m.attachment_path,m.attachment_type,m.attachment_name');execute def;
end$$;
