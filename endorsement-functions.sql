create function family_private.endorse_action(action text,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();role text:=family_private.access_role();term text:=trim(payload->>'term');applicant uuid; sponsor uuid;rid uuid;row family_private.endorsements;begin
 if uid is null then raise exception 'سجل الدخول';end if;
 if not(select endorsements_enabled from public.family_settings where id) then raise exception 'التعريف بالأعضاء غير مفعّل من المدير';end if;
 if action='sponsors' then
  if char_length(coalesce(term,''))<3 then return '[]';end if;
  return coalesce((select jsonb_agg(to_jsonb(x)) from(select p.id,p.display_name,p.avatar_path from public.profiles p join family_private.member_details d on d.id=p.id join auth.users u on u.id=p.id where p.id<>uid and p.status='active' and u.email_confirmed_at is not null and (family_private.normalize_name(p.display_name) ilike '%'||family_private.normalize_name(term)||'%' or d.phone=term) order by p.display_name limit 10)x),'[]');
 elsif action='search' then
  if role is null then raise exception 'التعريف للعضو المعتمد';end if;
  if char_length(coalesce(term,''))<3 then return '[]';end if;
  return coalesce((select jsonb_agg(to_jsonb(x)) from(select p.id,p.display_name from public.profiles p join family_private.member_details d on d.id=p.id join auth.users u on u.id=p.id where p.status='pending' and p.id<>uid and (family_private.normalize_name(p.display_name) ilike '%'||family_private.normalize_name(term)||'%' or d.phone=term or lower(u.email)=lower(term)) order by p.created_at desc limit 10)x),'[]');
 elsif action='request' then
  applicant=uid;sponsor=(payload->>'member')::uuid;
 elsif action='offer' then
  if role is null then raise exception 'التعريف للعضو المعتمد';end if;
  applicant=(payload->>'member')::uuid;sponsor=uid;
 elsif action='list' then
  return coalesce((select jsonb_agg(to_jsonb(x)) from(select e.id,e.applicant_id,e.sponsor_id,e.status,e.created_at,p.display_name,d.full_name,d.phone,d.gender,d.reference_name,d.relationship,u.email,u.email_confirmed_at is not null as email_confirmed,s.display_name as sponsor_name from family_private.endorsements e join public.profiles p on p.id=e.applicant_id join public.profiles s on s.id=e.sponsor_id join family_private.member_details d on d.id=p.id join auth.users u on u.id=p.id where e.applicant_id=uid or e.sponsor_id=uid order by e.created_at desc limit 100)x),'[]');
 elsif action in('approve','reject') then
  rid=(payload->>'id')::uuid;
  select * into row from family_private.endorsements where id=rid for update;
  if role is null or row.id is null or row.sponsor_id<>uid or row.status<>'pending' then raise exception 'طلب غير متاح لك';end if;
  if action='approve' and not coalesce((payload->>'confirm')::boolean,false) then raise exception 'يجب تأكيد معرفتك الشخصية بهذا العضو';end if;
  if action='approve' then
   if not exists(select 1 from family_private.member_details d join auth.users u on u.id=d.id join public.profiles p on p.id=d.id where d.id=row.applicant_id and u.email_confirmed_at is not null and p.status='pending' and d.phone is not null and d.gender is not null and cardinality(string_to_array(family_private.normalize_name(d.full_name),' '))=4 and (d.gender='male' or (d.reference_name is not null and d.relationship is not null))) then raise exception 'يجب إكمال بيانات العضو وتأكيد بريده أولًا';end if;
   update public.profiles set status='active' where id=row.applicant_id and status='pending';
  end if;
  update family_private.endorsements set status=case when action='approve' then 'approved' else 'rejected' end,decided_at=now() where id=rid;
  return 'true';
 else raise exception 'إجراء غير معروف';end if;
 if applicant=sponsor or not exists(select 1 from public.profiles where id=applicant and status='pending') or not exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=sponsor and p.status='active' and u.email_confirmed_at is not null) then raise exception 'طالب التعريف أو المعرّف غير متاح';end if;
 if(select count(*) from family_private.endorsements where applicant_id=applicant and created_at>now()-interval '1 day')>=3 then raise exception 'الحد ثلاثة طلبات تعريف يوميًا';end if;
 insert into family_private.endorsements(applicant_id,sponsor_id) values(applicant,sponsor) on conflict(applicant_id,sponsor_id) do update set status='pending',created_at=now(),decided_at=null where family_private.endorsements.status='rejected' returning id into rid;
 return to_jsonb(rid);
end $$;
revoke all on function family_private.endorse_action(text,jsonb) from public,anon;
grant execute on function family_private.endorse_action(text,jsonb) to authenticated;
create function public.endorse_action(action text,payload jsonb default '{}') returns jsonb language sql set search_path='' as $$select family_private.endorse_action(action,payload)$$;
revoke all on function public.endorse_action(text,jsonb) from public,anon;
grant execute on function public.endorse_action(text,jsonb) to authenticated;
