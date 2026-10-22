begin;
alter table family_private.news_requests add column image_paths text[] not null default '{}',add column smart_crop_enabled boolean not null default true,add column locked_by uuid references public.profiles(id)on delete set null,add column lock_expires_at timestamptz,add column review_draft jsonb;
alter table public.posts add column source_request_id uuid;
alter table public.posts drop constraint own_news_image;
alter table public.posts add constraint own_news_image check(image_path is null or image_path like author_id::text||'/%'or source_request_id is not null);
create unique index one_post_per_news_request on public.posts(source_request_id)where source_request_id is not null;
create table family_private.news_request_events(id bigint generated always as identity primary key,tenant_id uuid not null references family_private.tenants(id),request_id uuid not null references family_private.news_requests(id)on delete cascade,actor uuid references public.profiles(id)on delete set null,actor_name text not null,event text not null,created_at timestamptz not null default now());
create index news_request_events_family on family_private.news_request_events(tenant_id,created_at desc,id desc);
alter table family_private.news_request_events enable row level security;revoke all on family_private.news_request_events from public,anon,authenticated;
create function family_private.request_event(rid uuid,kind text)returns void language sql security definer set search_path='' as $$insert into family_private.news_request_events(tenant_id,request_id,actor,actor_name,event)select r.tenant_id,r.id,auth.uid(),coalesce((select display_name from public.profiles where id=auth.uid()),'النظام'),kind from family_private.news_requests r where r.id=rid and r.tenant_id=family_private.current_tenant()$$;
revoke all on function family_private.request_event(uuid,text)from public,anon,authenticated;
create function family_private.request_photo_access(path text,operation text default 'read')returns boolean language sql stable security definer set search_path='' as $$select auth.uid()is not null and family_private.access_role()is not null and case when operation='delete'then starts_with(path,auth.uid()::text||'/')and not exists(select 1 from family_private.news_requests where path=any(image_paths))and not exists(select 1 from public.posts where path=any(image_paths))else exists(select 1 from family_private.news_requests r where r.tenant_id=family_private.current_tenant()and path=any(r.image_paths)and(r.requester_id=auth.uid()or family_private.access_role()in('admin','journalist')))end$$;
create function family_private.request_photo_link(rid uuid,path text,tid uuid,author uuid)returns boolean language sql stable security definer set search_path='' as $$select auth.uid()is not null and family_private.access_role()in('admin','journalist')and tid=family_private.current_tenant()and exists(select 1 from family_private.news_requests r where r.id=rid and r.tenant_id=tid and path=any(r.image_paths)and(r.status='approved'or(r.status='pending'and(family_private.access_role()='admin'or(r.locked_by=auth.uid()and r.lock_expires_at>now())))))$$;
revoke all on function family_private.request_photo_access(text,text),family_private.request_photo_link(uuid,text,uuid,uuid)from public,anon;grant execute on function family_private.request_photo_access(text,text),family_private.request_photo_link(uuid,text,uuid,uuid)to authenticated;
create policy request_news_image_upload on storage.objects for insert to authenticated with check(bucket_id='news-images'and (select family_private.access_role())='member'and family_private.tenant_writable(family_private.current_tenant())and name~('^'||auth.uid()::text||'/[a-zA-Z0-9_.-]+[.]jpg$'));
create policy request_news_image_read on storage.objects for select to authenticated using(bucket_id='news-images'and family_private.request_photo_access(name,'read'));
create policy request_news_image_delete on storage.objects for delete to authenticated using(bucket_id='news-images'and (select family_private.access_role())='member'and family_private.request_photo_access(name,'delete'));
-- Extend album validation only for attached, same-family request photos; preserve existing validated albums on text-only edits.
do $$declare def text;begin select pg_get_functiondef('family_private.normalize_post_album()'::regprocedure)into def;
def:=replace(def,'foreach path in array new.image_paths loop','if TG_OP=''UPDATE''and new.image_paths is not distinct from old.image_paths and new.source_request_id is not distinct from old.source_request_id then new.image_path=new.image_paths[1];return new;end if;'||chr(10)||' foreach path in array new.image_paths loop');
def:=replace(def,'if path !~ (''^''||new.author_id::text||''/[a-zA-Z0-9_.-]+$'') then','if path !~ (''^''||new.author_id::text||''/[a-zA-Z0-9_.-]+$'')and not family_private.request_photo_link(new.source_request_id,path,new.tenant_id,new.author_id)then');execute def;
end$$;
-- Extend the verified core API, retaining all existing template, validation and approval rules.
do $$declare def text;begin select pg_get_functiondef('family_private.news_request_action(text,jsonb)'::regprocedure)into def;
def:=replace(def,'mentions uuid[]:=''{}'';','photos text[]:=''{}'';photo text;mentions uuid[]:=''{}'';');
def:=replace(def,'r.template_snapshot,r.status,r.review_note,r.post_id,r.created_at,','r.template_snapshot,r.image_paths,r.smart_crop_enabled,r.locked_by,r.lock_expires_at,r.review_draft,(select display_name from public.profiles where id=r.locked_by)locked_name,(select display_name from public.profiles where id=r.reviewer_id)reviewer_name,r.reviewed_at,r.status,r.review_note,r.post_id,r.created_at,');
def:=replace(def,'target:=coalesce(nullif(payload->>''request_id'','''')::uuid,gen_random_uuid());','select coalesce(array_agg(x),''{}'')into photos from jsonb_array_elements_text(coalesce(payload->''image_paths'',''[]''))x;if cardinality(photos)>5 or cardinality(photos)<>(select count(distinct p)from unnest(photos)p)then raise exception ''حتى خمس صور مختلفة'';end if;foreach photo in array photos loop if photo!~(''^''||uid::text||''/[a-zA-Z0-9_.-]+[.]jpg$'')or not exists(select 1 from storage.objects o where o.bucket_id=''news-images''and o.name=photo)then raise exception ''صورة غير متاحة أو لا تخصك'';end if;end loop;target:=coalesce(nullif(payload->>''request_id'','''')::uuid,gen_random_uuid());');
def:=replace(def,'title,template_snapshot,fields,rendered_body)values(target,tid,uid,t.id,t.name,t.body,data,body_text)','title,template_snapshot,fields,rendered_body,image_paths,smart_crop_enabled)values(target,tid,uid,t.id,t.name,t.body,data,body_text,photos,coalesce((payload->>''smart_crop_enabled'')::boolean,true))');
def:=replace(def,'published,mentioned_member_ids,from_request)values(tid,uid,detail,body_text,true,mentions,true)','published,mentioned_member_ids,from_request,image_paths,image_path,source_request_id)values(tid,uid,detail,body_text,true,mentions,true,r.image_paths,r.image_paths[1],r.id)');
execute def;
end$$;
alter function family_private.news_request_action(text,jsonb)rename to news_request_core;
revoke all on function family_private.news_request_core(text,jsonb)from public,anon,authenticated;
create function family_private.news_request_action(action text,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$#variable_conflict use_column
declare uid uuid:=auth.uid();tid uuid:=family_private.current_tenant();role text:=family_private.access_role();r family_private.news_requests;data jsonb;rid uuid;begin
 if uid is null or role is null then raise exception 'للأعضاء المعتمدين فقط';end if;
 if action='history'then
 if role not in('admin','journalist')then raise exception 'للصحفي والمدير فقط';end if;
 return coalesce((select jsonb_agg(to_jsonb(x))from(select e.id,e.request_id,r.title,e.actor_name,e.event,e.created_at,r.post_id from family_private.news_request_events e join family_private.news_requests r on r.id=e.request_id where e.tenant_id=tid and(nullif(payload->>'id','')is null or e.request_id=(payload->>'id')::uuid)order by e.created_at desc,e.id desc limit 50 offset greatest(0,coalesce((payload->>'offset')::integer,0)))x),'[]');end if;
 if action in('claim','renew','release','draft','approve','reject')then
 if role not in('admin','journalist')then raise exception 'للصحفي والمدير فقط';end if;
 if not family_private.tenant_writable(tid)then raise exception 'الكيان للاطلاع فقط';end if;
 select * into r from family_private.news_requests where id=(payload->>'id')::uuid and tenant_id=tid for update;
 if not found or r.status<>'pending'then raise exception 'الطلب غير متاح أو تمت معالجته';end if;
 if role<>'admin'and r.locked_by is not null and r.locked_by<>uid and r.lock_expires_at>now()then raise exception 'الخبر تحت مراجعة العضو %',(select display_name from public.profiles where id=r.locked_by);end if;
 if action='claim'then
 update family_private.news_requests set locked_by=uid,lock_expires_at=now()+interval '15 minutes'where id=r.id;perform family_private.request_event(r.id,case when role='admin'and r.locked_by is not null and r.locked_by<>uid and r.lock_expires_at>now()then 'manager_takeover'else 'claimed'end);
 return jsonb_build_object('locked_by',uid,'lock_expires_at',now()+interval '15 minutes','review_draft',r.review_draft);
 elsif action='release'then
 if role<>'admin'and r.locked_by<>uid then raise exception 'الحجز ليس لك';end if;update family_private.news_requests set locked_by=null,lock_expires_at=null where id=r.id;perform family_private.request_event(r.id,'released');return '{}';end if;
 if role<>'admin'and(r.locked_by is distinct from uid or r.lock_expires_at is null or r.lock_expires_at<=now())then raise exception 'احجز مراجعة الطلب أولًا';end if;
 if action='renew'then update family_private.news_requests set lock_expires_at=now()+interval '15 minutes'where id=r.id and locked_by=uid;return '{}';
 elsif action='draft'then
 if length(coalesce(payload->>'body',''))not between 1 and 10000 or length(coalesce(payload->>'title',''))not between 3 and 250 or jsonb_array_length(coalesce(payload->'mentions','[]'))>20 then raise exception 'بيانات المسودة غير صحيحة';end if;
 update family_private.news_requests set review_draft=jsonb_build_object('title',payload->>'title','body',payload->>'body','mentions',coalesce(payload->'mentions','[]'),'mention_requester',coalesce((payload->>'mention_requester')::boolean,false)),lock_expires_at=now()+interval '15 minutes'where id=r.id;perform family_private.request_event(r.id,'draft_saved');return '{}';end if;
 end if;
 data:=family_private.news_request_core(action,payload);
 if action='submit'then rid:=(data#>>'{}')::uuid;perform family_private.request_event(rid,'submitted');
 elsif action in('approve','reject','cancel')then rid:=(payload->>'id')::uuid;perform family_private.request_event(rid,case action when 'approve'then 'approved'when 'reject'then 'rejected'else 'cancelled'end);if action='approve'and(data->>'published')::boolean then perform family_private.request_event(rid,'published');end if;update family_private.news_requests set locked_by=null,lock_expires_at=null where id=rid;
 end if;return data;
end$$;
revoke all on function family_private.news_request_action(text,jsonb)from public,anon;grant execute on function family_private.news_request_action(text,jsonb)to authenticated;
create or replace function public.news_request_action(action text,payload jsonb default '{}')returns jsonb language sql security invoker set search_path='' as $$select family_private.news_request_action(action,payload)$$;
create function family_private.request_published_event()returns trigger language plpgsql security definer set search_path='' as $$begin if new.source_request_id is not null and new.published and not old.published then perform family_private.request_event(new.source_request_id,'published');end if;return new;end$$;
revoke all on function family_private.request_published_event()from public,anon,authenticated;
create trigger request_published_audit after update of published on public.posts for each row execute function family_private.request_published_event();
do $$declare def text;begin select pg_get_functiondef('public.lifecycle_backend(text,jsonb)'::regprocedure)into def;if position('<>35'in def)=0 then raise exception 'Lifecycle registry changed';end if;def:=replace(def,'<>35','<>36');def:=replace(def,'array[''family_private.news_requests''','array[''family_private.news_request_events'',''family_private.news_requests''');execute def;end$$;
notify pgrst,'reload schema';
commit;
