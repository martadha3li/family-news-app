alter table family_private.chat_messages add column edited_at timestamptz,add column deleted_at timestamptz,add column reply_to bigint references family_private.chat_messages(id),add column reply_excerpt text;
do $$declare def text;begin
 def:=pg_get_functiondef('family_private.chat_read(uuid,bigint)'::regprocedure);def:=replace(def,'m.body,m.created_at','m.body,m.created_at,m.edited_at,m.deleted_at,m.reply_to,m.reply_excerpt');execute def;
 def:=pg_get_functiondef('family_private.group_action(text,jsonb)'::regprocedure);def:=replace(def,'m.body,m.created_at','m.body,m.created_at,m.edited_at,m.deleted_at,m.reply_to,m.reply_excerpt');execute def;
end$$;
create function family_private.message_action(action text,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();m family_private.chat_messages;allowed jsonb;mid bigint;tid uuid;gid uuid;q text;begin
 if family_private.access_role() is null then raise exception 'حساب غير معتمد';end if;
 if action='search' then
 tid=nullif(payload->>'thread','')::uuid;gid=nullif(payload->>'group','')::uuid;q=trim(left(payload->>'term',80));
 if gid is not null then perform family_private.group_action('read',jsonb_build_object('id',gid));else perform family_private.chat_read(tid,null);end if;
 if coalesce(q,'')='' then return '[]';end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from(select m.id,m.body,m.created_at,p.display_name from family_private.chat_messages m join public.profiles p on p.id=m.sender_id where ((gid is not null and m.group_id=gid) or (gid is null and m.group_id is null and m.thread_id is not distinct from tid)) and m.deleted_at is null and strpos(m.body,q)>0 and family_private.chat_pair_allowed(m.sender_id) order by m.id desc limit 50)x),'[]');
 end if;
 select * into m from family_private.chat_messages where id=(payload->>'id')::bigint for update;
 if m.id is null then raise exception 'الرسالة غير متاحة';end if;
 if m.group_id is not null then allowed:=family_private.group_action('read',jsonb_build_object('id',m.group_id,'before_id',m.id+1));else allowed:=family_private.chat_read(m.thread_id,m.id+1);end if;
 if not exists(select 1 from jsonb_array_elements(allowed) x where (x->>'id')::bigint=m.id) then raise exception 'الرسالة غير متاحة لك';end if;
 if action='reply_send' then
 if m.deleted_at is not null then raise exception 'تم حذف الرسالة الأصلية';end if;
 if m.group_id is not null then mid:=(family_private.group_action('send',jsonb_build_object('id',m.group_id,'message',payload->>'message'))#>>'{}')::bigint;else mid:=family_private.chat_send(m.thread_id,payload->>'message');end if;
 update family_private.chat_messages set reply_to=m.id,reply_excerpt=left(m.body,250) where id=mid;return to_jsonb(mid);
 elsif action in ('edit','delete') then
 if m.sender_id<>uid or m.deleted_at is not null then raise exception 'يمكنك تعديل أو حذف رسائلك فقط';end if;
 if action='edit' then
 if m.created_at<now()-interval '15 minutes' then raise exception 'مدة تعديل الرسالة 15 دقيقة';end if;
 update family_private.chat_messages set body=trim(payload->>'message'),edited_at=now() where id=m.id;
 else
 if m.created_at<now()-interval '2 days' then raise exception 'انتهت مدة حذف الرسالة للجميع';end if;
 update family_private.chat_messages set body='تم حذف هذه الرسالة',deleted_at=now() where id=m.id;
 update family_private.chat_messages set reply_excerpt='تم حذف الرسالة الأصلية' where reply_to=m.id;
 end if;return 'true';
 else raise exception 'إجراء غير معروف';end if;
end$$;
create function public.message_action(action text,payload jsonb default '{}') returns jsonb language sql set search_path='' as $$select family_private.message_action(action,payload)$$;
revoke all on function family_private.message_action(text,jsonb),public.message_action(text,jsonb) from public,anon,authenticated;
grant execute on function family_private.message_action(text,jsonb),public.message_action(text,jsonb) to authenticated;
