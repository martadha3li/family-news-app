create function family_private.account_action(action text,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();role text:=family_private.access_role();member uuid;request family_private.phone_requests;path text;begin
 if uid is null then raise exception 'سجل الدخول';end if;
 if action='avatar' then
  path=payload->>'path';
  if path not like uid::text||'/%' or not exists(select 1 from storage.objects where bucket_id='profile-images' and name=path) then raise exception 'صورة غير صالحة';end if;
  update public.profiles set avatar_path=path where id=uid;return 'true';
 elsif action='directory_profile' then
  member=(payload->>'member')::uuid;
  if role is null or not exists(select 1 from public.profiles p where p.id=member and status='active') then raise exception 'الملف غير متاح';end if;
  return(select jsonb_build_object('id',id,'display_name',display_name,'avatar_path',avatar_path,'role',p.role) from public.profiles p where p.id=member);
 elsif action='phone_request' then
  if coalesce(payload->>'phone','') !~ '^\+[1-9][0-9]{7,14}$' then raise exception 'رقم غير صالح';end if;
  if exists(select 1 from family_private.member_details where phone=payload->>'phone' and id<>uid) then raise exception 'رقم الجوال مستخدم';end if;
  if exists(select 1 from family_private.phone_requests where member_id=uid and created_at>now()-interval '1 minute') then raise exception 'انتظر دقيقة بين الطلبات';end if;
  insert into family_private.phone_requests(member_id,new_phone) values(uid,payload->>'phone') on conflict(member_id) where status='pending' do update set new_phone=excluded.new_phone,created_at=now();return 'true';
 elsif action='phone_list' then
  return coalesce((select jsonb_agg(to_jsonb(x)) from(select r.id,r.member_id,r.new_phone,r.status,r.created_at,p.display_name,d.phone as current_phone from family_private.phone_requests r join public.profiles p on p.id=r.member_id join family_private.member_details d on d.id=r.member_id where r.member_id=uid or family_private.access_role()='admin' order by r.created_at desc limit 100)x),'[]');
 elsif action in('phone_approve','phone_reject') then
  if role is distinct from 'admin' then raise exception 'للمدير فقط';end if;
  select * into request from family_private.phone_requests where id=(payload->>'id')::uuid and status='pending' for update;
  if request.id is null then raise exception 'الطلب غير متاح';end if;
  if action='phone_approve' then update family_private.member_details set phone=request.new_phone where id=request.member_id;end if;
  update family_private.phone_requests set status=case when action='phone_approve' then 'approved' else 'rejected' end where id=request.id;return 'true';
 elsif action='history' then
  if role is null then raise exception 'حساب غير معتمد';end if;
  return jsonb_build_object('posts',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,title,created_at,published,moderation_status from public.posts where author_id=uid and deleted_at is null order by created_at desc limit 100)x),'[]'),'comments',coalesce((select jsonb_agg(to_jsonb(x)) from(select c.id,c.body,c.created_at,p.id as post_id,p.title from public.comments c join public.posts p on p.id=c.post_id where c.author_id=uid and p.deleted_at is null and (p.published or p.author_id=uid or family_private.access_role()='admin') order by c.created_at desc limit 100)x),'[]'),'likes',coalesce((select jsonb_agg(to_jsonb(x)) from(select p.id,p.title,p.created_at from public.likes l join public.posts p on p.id=l.post_id where l.user_id=uid and p.published and p.deleted_at is null order by p.created_at desc limit 100)x),'[]'));
 end if;raise exception 'إجراء غير معروف';
exception when unique_violation then raise exception 'رقم الجوال مستخدم لحساب آخر';end $$;
revoke all on function family_private.account_action(text,jsonb) from public,anon;
grant execute on function family_private.account_action(text,jsonb) to authenticated;
create function public.account_action(action text,payload jsonb default '{}') returns jsonb language sql set search_path='' as $$select family_private.account_action(action,payload)$$;
revoke all on function public.account_action(text,jsonb) from public,anon;
grant execute on function public.account_action(text,jsonb) to authenticated;
