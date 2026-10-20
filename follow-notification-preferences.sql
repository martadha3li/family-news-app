begin;
do $$declare def text;begin
 select pg_get_functiondef('family_private.native_notifications(text,jsonb)'::regprocedure)into def;
 def:=replace(def,'when e.reason=''publication''then','when e.reason=''publication''and subject.id is not null then');
 def:=replace(def,'when e.reason=''mention''then','when e.reason=''mention''and subject.id is not null then');
 def:=replace(def,'null::text as avatar_path','null::text as avatar_path,case when subject.id is not null then e.reason else null end as follow_reason');
 def:=replace(def,'p.id::text,p.avatar_path','p.id::text,p.avatar_path,null::text');execute def;
 select pg_get_functiondef('family_private.push_backend(text,jsonb)'::regprocedure)into def;
 def:=replace(def,'''is_follow'',j.follow_event,','''is_follow'',j.follow_event and exists(select 1 from family_private.follow_events e join family_private.member_follows f on f.tenant_id=e.tenant_id and f.follower_id=e.recipient_id and f.followed_id=e.subject_id join public.profiles subject on subject.id=e.subject_id and subject.status=''active'' where e.tenant_id=j.tenant_id and e.recipient_id=j.user_id and e.post_id::text=j.item),');execute def;
end$$;
commit;
