begin;
alter table family_private.tenants add column family_paused boolean not null default false;
create or replace function family_private.tenant_available(tid uuid)returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from family_private.tenants t where t.id=tid and t.status='active'and not t.family_paused and t.deleting_at is null and(t.login_access='allowed'or(t.login_access='suspended'and t.login_suspended_until<=now())))$$;
create or replace function public.tenant_directory(term text default '')returns jsonb language sql stable security definer set search_path='' as $$select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select id,code,name,logo from family_private.tenants where status='active'and deleting_at is null and trim(term)<>''and upper(code)=upper(trim(term))limit 1)x$$;
create or replace function public.tenant_current()returns jsonb language sql stable security definer set search_path='' as $$select jsonb_build_object('id',t.id,'code',t.code,'name',t.name,'logo',t.logo,'family_paused',t.family_paused,'can_resume',p.role='admin'and p.status='active'and exists(select 1 from auth.users u where u.id=auth.uid()and u.email_confirmed_at is not null),'status',case when family_private.tenant_available(t.id)then t.status when t.family_paused and t.status='active'and t.deleting_at is null then 'family_paused'else 'suspended'end)||family_private.lifecycle_state(t.id)from family_private.tenants t join public.profiles p on p.tenant_id=t.id where p.id=auth.uid()$$;
create function family_private.family_manager()returns uuid language sql stable security definer set search_path='' as $$select p.tenant_id from public.profiles p join auth.users u on u.id=p.id where p.id=auth.uid()and p.role='admin'and p.status='active'and u.email_confirmed_at is not null$$;
revoke all on function family_private.family_manager()from public,anon,authenticated;
create function public.family_pause(paused boolean)returns jsonb language plpgsql security definer set search_path='' as $$declare tid uuid:=family_private.family_manager();begin
if tid is null then raise exception 'مدير العائلة فقط';end if;
update family_private.tenants set family_paused=paused where id=tid and status='active'and deleting_at is null and(login_access='allowed'or(login_access='suspended'and login_suspended_until<=now()));
if not found then raise exception 'الكيان موقوف من إدارة المنصة؛ تواصل مع الدعم';end if;
insert into family_private.admin_audit(tenant_id,actor,action)values(tid,auth.uid(),case when paused then 'family_paused'else 'family_resumed'end);return jsonb_build_object('paused',paused);end$$;
revoke all on function public.family_pause(boolean)from public,anon;grant execute on function public.family_pause(boolean)to authenticated;
alter table family_private.square_posts add column mentioned_member_ids uuid[] not null default '{}';
alter function family_private.community_hub(text,jsonb)rename to community_hub_core;
revoke all on function family_private.community_hub_core(text,jsonb)from public,anon,authenticated;
create function family_private.community_hub(action text,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;ids uuid[];tid uuid:=family_private.current_tenant();begin
if action='publish'then
 select coalesce(array_agg(distinct x::uuid),'{}')into ids from jsonb_array_elements_text(coalesce(payload->'mentions','[]'))x;
 if cardinality(ids)>30 or exists(select 1 from unnest(ids)m where not exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=m and p.tenant_id=tid and p.status='active'and u.email_confirmed_at is not null))then raise exception 'المنشن لأعضاء العائلة المعتمدين فقط، بحد أقصى 30';end if;
end if;
result:=family_private.community_hub_core(action,payload);
if action='publish'then update family_private.square_posts set mentioned_member_ids=ids where id=(result#>>'{}')::bigint and tenant_id=tid;
elsif action='feed'then select coalesce(jsonb_agg(v||jsonb_build_object('mentions',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name)),'[]')from public.profiles p join family_private.square_posts s on p.id=any(s.mentioned_member_ids)where s.id=(v->>'id')::bigint and s.tenant_id=tid and p.tenant_id=tid and p.status='active'))),'[]')into result from jsonb_array_elements(result)v;
end if;return result;end$$;
revoke all on function family_private.community_hub(text,jsonb)from public,anon;grant execute on function family_private.community_hub(text,jsonb)to authenticated;
create or replace function public.community_hub(action text,payload jsonb default '{}')returns jsonb language sql security invoker set search_path='' as $$select family_private.community_hub(action,payload)$$;
create table family_private.news_comment_alerts(id bigint generated always as identity primary key,tenant_id uuid not null references family_private.tenants(id),recipient_id uuid not null references public.profiles(id)on delete cascade,post_id bigint not null references public.posts(id)on delete cascade,comment_id bigint not null references public.comments(id)on delete cascade,created_at timestamptz not null default now(),unique(recipient_id,comment_id));
alter table family_private.news_comment_alerts enable row level security;revoke all on family_private.news_comment_alerts from public,anon,authenticated;
create index on family_private.news_comment_alerts(tenant_id,recipient_id,created_at desc);
create function family_private.alert_news_comment()returns trigger language plpgsql security definer set search_path='' as $$begin
insert into family_private.news_comment_alerts(tenant_id,recipient_id,post_id,comment_id)
select p.tenant_id,r.id,p.id,new.id from public.posts p join public.profiles r on r.tenant_id=p.tenant_id join auth.users u on u.id=r.id where p.id=new.post_id and p.published and p.deleted_at is null and r.status='active'and u.email_confirmed_at is not null and r.id<>new.author_id and(r.id=p.author_id or r.id=any(p.mentioned_member_ids)or exists(select 1 from public.likes l where l.post_id=p.id and l.user_id=r.id)or exists(select 1 from public.comments c where c.post_id=p.id and c.author_id=r.id));
insert into family_private.push_jobs(tenant_id,user_id,kind,item)
select distinct a.tenant_id,a.recipient_id,'news',a.post_id::text from family_private.news_comment_alerts a join family_private.push_subscriptions s on s.user_id=a.recipient_id and s.tenant_id=a.tenant_id and s.news where a.comment_id=new.id
on conflict(user_id,kind,item)do update set sent_at=null,attempts=0,leased_at=null,created_at=now();return new;end$$;
revoke all on function family_private.alert_news_comment()from public,anon,authenticated;
create trigger alert_news_comment after insert on public.comments for each row execute function family_private.alert_news_comment();
alter function family_private.native_notifications(text,jsonb)rename to native_notifications_core;
revoke all on function family_private.native_notifications_core(text,jsonb)from public,anon,authenticated;
create function family_private.native_notifications(action text,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;extra jsonb;begin
result:=family_private.native_notifications_core(action,payload);
select coalesce(jsonb_agg(jsonb_build_object('id','comment:'||a.id,'kind','news','title','تعليق جديد على: '||p.title,'post_id',p.id::text,'created_at',a.created_at)),'[]')into extra from(select * from family_private.news_comment_alerts where tenant_id=family_private.current_tenant()and recipient_id=auth.uid()order by created_at desc limit 100)a join public.posts p on p.id=a.post_id and p.tenant_id=a.tenant_id and p.published and p.deleted_at is null;
return jsonb_set(result,'{items}',(select coalesce(jsonb_agg(v order by(v->>'created_at')::timestamptz desc),'[]')from(select v from jsonb_array_elements((result->'items')||extra)v order by(v->>'created_at')::timestamptz desc limit 100)x));end$$;
revoke all on function family_private.native_notifications(text,jsonb)from public,anon;grant execute on function family_private.native_notifications(text,jsonb)to authenticated;
create or replace function public.native_notifications(action text default 'list',payload jsonb default '{}')returns jsonb language sql security invoker set search_path='' as $$select family_private.native_notifications(action,payload)$$;
create table family_private.support_tickets(id uuid primary key default gen_random_uuid(),tenant_id uuid not null references family_private.tenants(id),subject text not null check(length(subject)between 3 and 200),status text not null default 'open'check(status in('open','closed')),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table family_private.support_messages(id bigint generated always as identity primary key,tenant_id uuid not null references family_private.tenants(id),ticket_id uuid not null references family_private.support_tickets(id)on delete cascade,author_id uuid references auth.users(id)on delete set null,from_platform boolean not null,body text not null check(length(body)between 1 and 5000),created_at timestamptz not null default now());
alter table family_private.support_tickets enable row level security;alter table family_private.support_messages enable row level security;revoke all on family_private.support_tickets,family_private.support_messages from public,anon,authenticated;
create index on family_private.support_tickets(tenant_id,updated_at desc);create index on family_private.support_messages(ticket_id,id);
create function public.support_action(action text,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$declare manager uuid:=family_private.family_manager();is_platform boolean:=coalesce((payload->>'platform')::boolean,false)and family_private.platform_allowed();ticket family_private.support_tickets;txt text:=trim(payload->>'body');begin
if auth.uid()is null or(manager is null and not is_platform)then raise exception 'الدعم لمدير العائلة وإدارة المنصة فقط';end if;
if action='list'then return coalesce((select jsonb_agg(to_jsonb(x))from(select t.*,f.name family_name,f.code family_code,(select from_platform from family_private.support_messages m where m.ticket_id=t.id order by m.id desc limit 1)last_from_platform from family_private.support_tickets t join family_private.tenants f on f.id=t.tenant_id where is_platform or t.tenant_id=manager order by t.updated_at desc limit 200)x),'[]');end if;
if action='create'then
if manager is null then raise exception 'مدير العائلة فقط';end if;
if length(coalesce(txt,''))not between 1 and 5000 or length(trim(coalesce(payload->>'subject','')))not between 3 and 200 then raise exception 'أدخل عنوان الطلب وتفاصيله';end if;
if(select count(*)from family_private.support_tickets where tenant_id=manager and created_at>now()-interval '1 hour')>=10 then raise exception 'طلبات كثيرة؛ انتظر قليلًا';end if;
insert into family_private.support_tickets(tenant_id,subject)values(manager,trim(payload->>'subject'))returning * into ticket;
insert into family_private.support_messages(tenant_id,ticket_id,author_id,from_platform,body)values(manager,ticket.id,auth.uid(),false,txt);return to_jsonb(ticket);
end if;
select * into ticket from family_private.support_tickets where id=(payload->>'ticket')::uuid and(is_platform or tenant_id=manager)for update;
if ticket.id is null then raise exception 'الطلب غير متاح';end if;
if action='messages'then return coalesce((select jsonb_agg(to_jsonb(x))from(select id,from_platform,body,created_at from family_private.support_messages where ticket_id=ticket.id and tenant_id=ticket.tenant_id and id>coalesce((payload->>'after')::bigint,0)order by id limit 100)x),'[]');
elsif action='reply'then
if length(coalesce(txt,''))not between 1 and 5000 then raise exception 'الرسالة من 1 إلى 5000 حرف';end if;
if(select count(*)from family_private.support_messages where author_id=auth.uid()and created_at>now()-interval '1 minute')>=20 then raise exception 'انتظر قليلًا';end if;
insert into family_private.support_messages(tenant_id,ticket_id,author_id,from_platform,body)values(ticket.tenant_id,ticket.id,auth.uid(),is_platform,txt);
update family_private.support_tickets set updated_at=now(),status='open'where id=ticket.id;
elsif action='close'then update family_private.support_tickets set status='closed',updated_at=now()where id=ticket.id;
else raise exception 'إجراء غير معروف';end if;return '{}'::jsonb;end$$;
revoke all on function public.support_action(text,jsonb)from public,anon;grant execute on function public.support_action(text,jsonb)to authenticated;
do $$declare def text;begin select pg_get_functiondef('public.lifecycle_backend(text,jsonb)'::regprocedure)into def;if position('<>36'in def)=0 then raise exception 'Lifecycle registry changed';end if;def:=replace(def,'<>36','<>39');def:=replace(def,'array[''family_private.news_request_events''','array[''family_private.support_messages'',''family_private.support_tickets'',''family_private.news_comment_alerts'',''family_private.news_request_events''');execute def;end$$;
notify pgrst,'reload schema';commit;
