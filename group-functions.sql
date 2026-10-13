create function family_private.group_action(action text,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();role text:=family_private.access_role();g family_private.chat_groups;gid uuid;person uuid;mid bigint;answer jsonb;begin
 if role is null then raise exception 'حساب غير معتمد';end if;
 if not(select chat_enabled from public.family_settings where id) then raise exception 'الدردشة موقوفة';end if;
 gid=nullif(payload->>'id','')::uuid;
 if action='list' then
  return coalesce((select jsonb_agg(to_jsonb(x)) from(select cg.id,cg.title,cg.kind,cg.owner_id,cg.starts_at,cg.ends_at,(cg.kind='group' or now() between cg.starts_at and cg.ends_at) as open_now from family_private.chat_groups cg join family_private.group_members m on m.group_id=cg.id where m.member_id=uid order by cg.created_at desc limit 100)x),'[]');
 elsif action='create' then
  if payload->>'kind'='event' and role<>'admin' then raise exception 'إنشاء الأحداث للمدير';end if;
  if payload->>'kind'='group' and role<>'admin' and not(select allow_groups from public.family_settings where id) then raise exception 'إنشاء المجموعات موقوف من المدير';end if;
  if jsonb_array_length(coalesce(payload->'members','[]'))>200 then raise exception 'الحد الأقصى 200 عضو للمجموعة';end if;
  if not family_private.chat_pair_allowed(uid) then raise exception 'أكمل ملفك الشخصي';end if;
  insert into family_private.chat_groups(owner_id,title,kind,starts_at,ends_at) values(uid,trim(payload->>'title'),payload->>'kind',nullif(payload->>'starts_at','')::timestamptz,nullif(payload->>'ends_at','')::timestamptz) returning id into gid;
  insert into family_private.group_members values(gid,uid);
  for person in select jsonb_array_elements_text(coalesce(payload->'members','[]'))::uuid loop
   if person<>uid then
    if not family_private.chat_pair_allowed(person) then raise exception 'عضو غير متاح وفق ضوابط الدردشة';end if;
    insert into family_private.group_members values(gid,person) on conflict do nothing;
   end if;
  end loop;return to_jsonb(gid);
 end if;
 select * into g from family_private.chat_groups where id=gid;
 if g.id is null or not exists(select 1 from family_private.group_members where group_id=gid and member_id=uid) then raise exception 'المجموعة غير متاحة';end if;
 if action='members' then
  return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name,'avatar_path',p.avatar_path)) from family_private.group_members m join public.profiles p on p.id=m.member_id where m.group_id=gid and family_private.chat_pair_allowed(p.id)),'[]');
 elsif action='add' or action='remove' then
  if g.owner_id<>uid and role<>'admin' then raise exception 'إدارة الأعضاء لمنشئ المجموعة';end if;
  person=(payload->>'member')::uuid;
  if action='add' then
   if not family_private.chat_pair_allowed(person) then raise exception 'عضو غير متاح';end if;
   if(select count(*) from family_private.group_members where group_id=gid)>=200 then raise exception 'وصلت المجموعة حد الأعضاء';end if;
   insert into family_private.group_members values(gid,person) on conflict do nothing;
  else
   if person=g.owner_id then raise exception 'لا يمكن إزالة منشئ المجموعة';end if;
   delete from family_private.group_members where group_id=gid and member_id=person;
  end if;return 'true';
 elsif action='leave' then
  if uid=g.owner_id then raise exception 'منشئ المجموعة لا يغادر قبل نقل إدارتها';end if;
  delete from family_private.group_members where group_id=gid and member_id=uid;return 'true';
 end if;
 if g.kind='event' and not(now() between g.starts_at and g.ends_at) then raise exception 'الحدث خارج فترة الدردشة المحددة';end if;
 if action='read' then
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from(select m.id,m.sender_id,m.body,m.created_at,p.display_name,p.avatar_path from family_private.chat_messages m join public.profiles p on p.id=m.sender_id where m.group_id=gid and (nullif(payload->>'before_id','') is null or m.id<(payload->>'before_id')::bigint) and family_private.chat_pair_allowed(m.sender_id) order by m.id desc limit 50)x),'[]');
 elsif action='send' then
  if not family_private.chat_pair_allowed(uid) then raise exception 'أكمل ملفك';end if;
  if exists(select 1 from family_private.chat_messages where sender_id=uid and created_at>now()-interval '2 seconds') then raise exception 'انتظر لحظة بين الرسائل';end if;
  insert into family_private.chat_messages(group_id,sender_id,body) values(gid,uid,trim(payload->>'message')) returning id into mid;return to_jsonb(mid);
 end if;
 raise exception 'إجراء غير معروف';
end $$;
revoke all on function family_private.group_action(text,jsonb) from public,anon;
grant execute on function family_private.group_action(text,jsonb) to authenticated;
create function public.group_action(action text,payload jsonb default '{}') returns jsonb language sql set search_path='' as $$select family_private.group_action(action,payload)$$;
revoke all on function public.group_action(text,jsonb) from public,anon;
grant execute on function public.group_action(text,jsonb) to authenticated;
