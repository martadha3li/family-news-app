begin;
create table family_private.member_follows(tenant_id uuid not null references family_private.tenants(id),follower_id uuid not null references public.profiles(id)on delete cascade,followed_id uuid not null references public.profiles(id)on delete cascade,created_at timestamptz not null default now(),primary key(tenant_id,follower_id,followed_id),check(follower_id<>followed_id));
create index member_follows_followed on family_private.member_follows(tenant_id,followed_id,follower_id);
create table family_private.follow_events(id bigint generated always as identity primary key,tenant_id uuid not null references family_private.tenants(id),recipient_id uuid not null references public.profiles(id)on delete cascade,subject_id uuid not null references public.profiles(id)on delete cascade,post_id bigint not null references public.posts(id)on delete cascade,reason text not null check(reason in('publication','mention')),created_at timestamptz not null default now(),unique(tenant_id,recipient_id,post_id));
create index follow_events_recipient on family_private.follow_events(tenant_id,recipient_id,created_at desc);
alter table family_private.member_follows enable row level security;alter table family_private.follow_events enable row level security;
revoke all on family_private.member_follows,family_private.follow_events from public,anon,authenticated;
grant select on family_private.member_follows,family_private.follow_events to family_api_executor;
create policy follows_scoped_read on family_private.member_follows for select to family_api_executor using(tenant_id=family_private.current_tenant());
create policy follow_events_scoped_read on family_private.follow_events for select to family_api_executor using(tenant_id=family_private.current_tenant()and recipient_id=auth.uid());
alter table family_private.push_subscriptions add column follow_alerts boolean not null default true;
alter table family_private.push_jobs add column follow_event boolean not null default false;
-- Checked APIs expose only public family-profile fields. Raw follow edges stay private.
create function family_private.member_social(action text,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();tid uuid:=family_private.current_tenant();target uuid:=(payload->>'member')::uuid;page integer:=greatest(0,least(coalesce((payload->>'offset')::integer,0),100000));mode text:=coalesce(payload->>'scope','mentions');begin
 if uid is null or family_private.access_role()is null then raise exception 'حساب غير معتمد';end if;
 if not exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=target and p.tenant_id=tid and p.status='active'and u.email_confirmed_at is not null)then raise exception 'الملف غير متاح داخل عائلتك';end if;
 if action in('follow','unfollow')then
 if not family_private.tenant_writable(tid)then raise exception 'الكيان للاطلاع فقط؛ يلزم تجديد الاشتراك';end if;
 if uid=target then raise exception 'لا يمكنك متابعة نفسك';end if;
 if action='follow'then insert into family_private.member_follows(tenant_id,follower_id,followed_id)values(tid,uid,target)on conflict do nothing;
 else delete from family_private.member_follows where tenant_id=tid and follower_id=uid and followed_id=target;end if;
 elsif action='grid'then
 if mode not in('mentions','posts')then raise exception 'تبويب غير صحيح';end if;
 return coalesce((select jsonb_agg(to_jsonb(x))from(select p.id,p.title,p.image_path,p.image_paths,p.created_at from public.posts p where p.tenant_id=tid and p.published and p.deleted_at is null and(case when mode='posts'then p.author_id=target else target=any(p.mentioned_member_ids)end)order by p.created_at desc,p.id desc limit 30 offset page)x),'[]');
 elsif action<>'profile'then raise exception 'إجراء غير معروف';end if;
 return(select jsonb_build_object('id',p.id,'display_name',p.display_name,'avatar_path',p.avatar_path,'bio',p.bio,'role',p.role,'following',exists(select 1 from family_private.member_follows f where f.tenant_id=tid and f.follower_id=uid and f.followed_id=target),'followers',(select count(*)from family_private.member_follows f join public.profiles m on m.id=f.follower_id where f.tenant_id=tid and f.followed_id=target and m.status='active'),'following_count',(select count(*)from family_private.member_follows f join public.profiles m on m.id=f.followed_id where f.tenant_id=tid and f.follower_id=target and m.status='active'),'posts',(select count(*)from public.posts n where n.tenant_id=tid and n.author_id=target and n.published and n.deleted_at is null),'mentions',(select count(*)from public.posts n where n.tenant_id=tid and target=any(n.mentioned_member_ids)and n.published and n.deleted_at is null))from public.profiles p where p.id=target and p.tenant_id=tid);
end$$;
create function public.member_social(action text,payload jsonb default '{}')returns jsonb language sql security invoker set search_path='' as $$select family_private.member_social(action,payload)$$;
revoke all on function family_private.member_social(text,jsonb),public.member_social(text,jsonb)from public,anon;grant execute on function family_private.member_social(text,jsonb),public.member_social(text,jsonb)to authenticated;
-- New publication and newly added mentions only; one event and one news push per recipient/post.
create function family_private.queue_follow_news()returns trigger language plpgsql security definer set search_path='' as $$declare old_mentions uuid[]:='{}';publication boolean:=true;begin
 if not new.published or new.deleted_at is not null or not family_private.tenant_available(new.tenant_id)then return new;end if;
 if TG_OP='UPDATE'then
 publication:=not old.published;
 if old.published then old_mentions:=old.mentioned_member_ids;if new.mentioned_member_ids is not distinct from old.mentioned_member_ids then return new;end if;end if;
 end if;
 with candidates as(
 select f.follower_id,f.followed_id,'publication'::text as reason,0 as priority from family_private.member_follows f where f.tenant_id=new.tenant_id and f.followed_id=new.author_id and publication
 union all
 select f.follower_id,f.followed_id,'mention',1 from family_private.member_follows f where f.tenant_id=new.tenant_id and f.followed_id=any(new.mentioned_member_ids)and not(f.followed_id=any(coalesce(old_mentions,'{}')))
 ),inserted as(
 insert into family_private.follow_events(tenant_id,recipient_id,subject_id,post_id,reason)
 select distinct on(c.follower_id)new.tenant_id,c.follower_id,c.followed_id,new.id,c.reason from candidates c join public.profiles p on p.id=c.follower_id and p.tenant_id=new.tenant_id join public.profiles subject on subject.id=c.followed_id and subject.tenant_id=new.tenant_id join auth.users u on u.id=p.id where p.status='active'and subject.status='active'and u.email_confirmed_at is not null and p.id<>new.author_id order by c.follower_id,c.priority,c.followed_id on conflict do nothing returning recipient_id
 )
 insert into family_private.push_jobs(tenant_id,user_id,kind,item,follow_event)select distinct new.tenant_id,e.recipient_id,'news',new.id::text,true from inserted e join family_private.push_subscriptions s on s.user_id=e.recipient_id and s.tenant_id=new.tenant_id and s.follow_alerts on conflict(user_id,kind,item)do update set follow_event=true;
 return new;
end$$;
revoke all on function family_private.queue_follow_news()from public,anon,authenticated;
create trigger queue_follow_news after insert or update on public.posts for each row execute function family_private.queue_follow_news();
-- Preserve existing news/message notification API and add follower context without duplicate rows.
do $$declare def text;begin
 select pg_get_functiondef('family_private.native_notifications(text,jsonb)'::regprocedure)into def;
 def:=replace(def,'''news''::text as kind,p.title,p.published_at as created_at','''news''::text as kind,case when e.reason=''publication''then ''نشر ''||subject.display_name||'' خبرًا: ''||p.title when e.reason=''mention''then ''ذُكر ''||subject.display_name||'' في خبر: ''||p.title else p.title end as title,coalesce(e.created_at,p.published_at)as created_at');
 def:=replace(def,'from public.posts p where p.published','from public.posts p left join family_private.follow_events e on e.post_id=p.id and e.recipient_id=uid and e.tenant_id=p.tenant_id and exists(select 1 from family_private.member_follows f where f.tenant_id=e.tenant_id and f.follower_id=uid and f.followed_id=e.subject_id)left join public.profiles subject on subject.id=e.subject_id and subject.status=''active'' where p.published');
 def:=replace(def,'p.published_at<=cutoff','coalesce(e.created_at,p.published_at)<=cutoff');
 def:=replace(def,'order by p.published_at desc,p.id desc','order by coalesce(e.created_at,p.published_at)desc,p.id desc');execute def;
 select pg_get_functiondef('family_private.push_backend(text,jsonb)'::regprocedure)into def;
 def:=replace(def,'''kind'',j.kind,','''kind'',j.kind,''post_id'',case when j.kind=''news''then j.item else null end,''is_follow'',j.follow_event,');
 def:=replace(def,'when j.kind=''news'' then s.news and exists','when j.kind=''news'' then(s.news or(j.follow_event and s.follow_alerts and exists(select 1 from family_private.follow_events e join family_private.member_follows f on f.tenant_id=e.tenant_id and f.follower_id=e.recipient_id and f.followed_id=e.subject_id join public.profiles subject on subject.id=e.subject_id and subject.status=''active'' where e.tenant_id=j.tenant_id and e.recipient_id=j.user_id and e.post_id::text=j.item)))and exists');
 def:=replace(def,'t.status=''active''' ,'t.status=''active''and family_private.tenant_available(t.id)');execute def;
 -- Store the new preference on subscribe; older clients opt in by default.
 select pg_get_functiondef('family_private.push_action(text,jsonb)'::regprocedure)into def;
 def:=replace(def,'subscription,news,private_chat)','subscription,news,private_chat,follow_alerts)');
 def:=replace(def,'coalesce((payload->>''private_chat'')::boolean,true))','coalesce((payload->>''private_chat'')::boolean,true),coalesce((payload->>''follow_alerts'')::boolean,true))');
 def:=replace(def,'private_chat=excluded.private_chat,','private_chat=excluded.private_chat,follow_alerts=excluded.follow_alerts,');execute def;
 -- Cleanup is fail-closed for new tables; add both to the explicit tenant purge registry.
 select pg_get_functiondef('public.lifecycle_backend(text,jsonb)'::regprocedure)into def;
 def:=replace(def,'<>28','<>30');
 def:=replace(def,'array[''family_private.push_jobs''','array[''family_private.follow_events'',''family_private.member_follows'',''family_private.push_jobs''');execute def;
end$$;
notify pgrst,'reload schema';
commit;
