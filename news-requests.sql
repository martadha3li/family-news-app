begin;
create table family_private.news_templates(id uuid primary key default gen_random_uuid(),tenant_id uuid not null references family_private.tenants(id),name text not null check(length(name)between 3 and 100),kind text not null check(kind in('general','newborn','marriage')),body text not null check(length(body)between 3 and 6000),enabled boolean not null default true,updated_at timestamptz not null default now());
create index news_templates_family on family_private.news_templates(tenant_id,enabled,name);
create table family_private.news_requests(id uuid primary key default gen_random_uuid(),tenant_id uuid not null references family_private.tenants(id),requester_id uuid not null references public.profiles(id)on delete cascade,template_id uuid references family_private.news_templates(id)on delete set null,title text not null,template_snapshot text not null,fields jsonb not null,rendered_body text not null,status text not null default 'pending'check(status in('pending','approved','rejected','cancelled')),reviewer_id uuid references public.profiles(id)on delete set null,reviewed_at timestamptz,review_note text,post_id bigint references public.posts(id)on delete set null,created_at timestamptz not null default now());
create index news_requests_family on family_private.news_requests(tenant_id,status,created_at desc);
create index news_requests_owner on family_private.news_requests(tenant_id,requester_id,created_at desc);
alter table family_private.news_templates enable row level security;alter table family_private.news_requests enable row level security;
revoke all on family_private.news_templates,family_private.news_requests from public,anon,authenticated;
alter table public.posts add column from_request boolean not null default false;
create function family_private.render_news_template(pattern text,fields jsonb)returns text language plpgsql immutable set search_path='' as $$declare result text:='';part text;remaining text:=pattern;key text;pos integer;begin
 -- Substitute exactly once; values are literal text and cannot introduce more placeholders.
 while position('{'in remaining)>0 loop
 pos:=position('{'in remaining);result:=result||left(remaining,pos-1);remaining:=substr(remaining,pos+1);pos:=position('}'in remaining);if pos=0 then raise exception 'أغلق الحقل بالقوس }';end if;key:=left(remaining,pos-1);if key not in('subject','newborn','bride_father','details','requester')then raise exception 'حقل غير معروف في الصيغة: %',key;end if;result:=result||coalesce(fields->>key,'');remaining:=substr(remaining,pos+1);
 end loop;
 if position('}'in remaining)>0 then raise exception 'صيغة الأقواس غير صحيحة';end if;return result||remaining;end$$;
revoke all on function family_private.render_news_template(text,jsonb)from public,anon,authenticated;
create function family_private.news_request_action(action text,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$#variable_conflict use_column
declare uid uuid:=auth.uid();tid uuid:=family_private.current_tenant();role text:=family_private.access_role();writer boolean:=coalesce(role in('admin','journalist'),false);manager boolean:=coalesce(role='admin',false);r family_private.news_requests;t family_private.news_templates;target uuid;data jsonb;body_text text;subject text;newborn text;bride text;detail text;mentions uuid[]:='{}';pid bigint;posted boolean;page integer:=greatest(0,least(coalesce((payload->>'offset')::integer,0),100000));begin
 if uid is null or role is null then raise exception 'للأعضاء المعتمدين فقط';end if;
 if action='meta'then return jsonb_build_object('writer',writer,'admin',manager,'pending',case when writer then(select count(*)from family_private.news_requests where tenant_id=tid and status='pending')else 0 end);end if;
 if action='templates'then return coalesce((select jsonb_agg(to_jsonb(t)-'tenant_id')from family_private.news_templates t where t.tenant_id=tid and(t.enabled or manager)order by t.name),'[]');
 elsif action='list'then return coalesce((select jsonb_agg(to_jsonb(x))from(select r.id,r.requester_id,p.display_name requester_name,r.title,r.fields,r.rendered_body,r.template_snapshot,r.status,r.review_note,r.post_id,r.created_at,case when n.published and n.deleted_at is null then 'published'when r.status='approved'and n.moderation_status='pending'then 'pending_manager'when r.status='approved'and n.moderation_status='rejected'then 'post_rejected'else r.status end display_status from family_private.news_requests r join public.profiles p on p.id=r.requester_id left join public.posts n on n.id=r.post_id and n.tenant_id=tid where r.tenant_id=tid and(case when coalesce((payload->>'review')::boolean,false)then writer else r.requester_id=uid end)order by r.created_at desc,r.id limit 30 offset page)x),'[]');
 elsif action='mention_search'then
 if not writer then raise exception 'للصحفي والمدير فقط';end if;
 detail:=left(trim(coalesce(payload->>'term','')),100);if detail=''then return '[]';end if;
 return coalesce((select jsonb_agg(to_jsonb(x))from(select p.id,p.display_name from public.profiles p join auth.users u on u.id=p.id left join family_private.member_details d on d.id=p.id where p.tenant_id=tid and p.status='active'and u.email_confirmed_at is not null and(starts_with(family_private.normalize_name(p.display_name),family_private.normalize_name(detail))or starts_with(d.phone,family_private.phone_prefix(detail)))order by p.display_name limit 30)x),'[]');end if;
 if not family_private.tenant_writable(tid)then raise exception 'الكيان للاطلاع فقط؛ يلزم تجديد الاشتراك';end if;
 if action='template_save'then
 if not manager then raise exception 'للمدير فقط';end if;
 target:=coalesce(nullif(payload->>'id','')::uuid,gen_random_uuid());body_text:=payload->>'body';perform family_private.render_news_template(body_text,'{}');
 if payload->>'kind'='newborn'and position('{newborn}'in body_text)=0 then raise exception 'أضف حقل {newborn} للصيغة';end if;
 if payload->>'kind'='marriage'and position('{bride_father}'in body_text)=0 then raise exception 'أضف حقل {bride_father} للصيغة';end if;
 if position('{subject}'in body_text)=0 then raise exception 'أضف حقل {subject} لصاحب الخبر';end if;
 if exists(select 1 from family_private.news_templates where id=target and tenant_id<>tid)then raise exception 'القالب غير متاح';end if;
 insert into family_private.news_templates(id,tenant_id,name,kind,body,enabled)values(target,tid,trim(payload->>'name'),payload->>'kind',body_text,coalesce((payload->>'enabled')::boolean,true))on conflict(id)do update set name=excluded.name,kind=excluded.kind,body=excluded.body,enabled=excluded.enabled,updated_at=now()where news_templates.tenant_id=tid;
 return to_jsonb(target);
 elsif action='submit'then
 select * into t from family_private.news_templates where id=(payload->>'template')::uuid and tenant_id=tid and enabled;if not found then raise exception 'اختر نوع خبر متاحًا';end if;
 subject:=trim(payload->>'subject');newborn:=trim(coalesce(payload->>'newborn',''));bride:=trim(coalesce(payload->>'bride_father',''));detail:=trim(coalesce(payload->>'details',''));
 if subject is null or length(subject)not between 2 and 250 or length(newborn)>250 or length(bride)>250 or length(detail)>2000 or(t.kind='newborn'and newborn='')or(t.kind='marriage'and bride='')then raise exception 'أكمل بيانات النموذج؛ اسم المولود لمولود جديد واسم كريمة من لعقد القران';end if;
 if(select count(*)from family_private.news_requests where requester_id=uid and created_at>now()-interval '1 hour')>=10 then raise exception 'وصلت للحد المؤقت للطلبات؛ حاول لاحقًا';end if;
 data:=jsonb_build_object('subject',subject,'newborn',newborn,'bride_father',bride,'details',detail,'requester',(select display_name from public.profiles where id=uid));body_text:=family_private.render_news_template(t.body,data);if length(body_text)>10000 then raise exception 'نص الخبر طويل جدًا';end if;
 target:=coalesce(nullif(payload->>'request_id','')::uuid,gen_random_uuid());
 insert into family_private.news_requests(id,tenant_id,requester_id,template_id,title,template_snapshot,fields,rendered_body)values(target,tid,uid,t.id,t.name,t.body,data,body_text)on conflict(id)do nothing;
 if not exists(select 1 from family_private.news_requests where id=target and tenant_id=tid and requester_id=uid)then raise exception 'رقم الطلب غير متاح';end if;return to_jsonb(target);
 end if;
 select * into r from family_private.news_requests where id=(payload->>'id')::uuid and tenant_id=tid for update;if not found then raise exception 'الطلب غير متاح';end if;
 if action='cancel'then
 if r.requester_id<>uid or r.status<>'pending'then raise exception 'لا يمكن إلغاء هذا الطلب';end if;update family_private.news_requests set status='cancelled'where id=r.id;return '{}';end if;
 if not writer then raise exception 'للصحفي والمدير فقط';end if;
 if r.status<>'pending'then raise exception 'تمت معالجة الطلب مسبقًا';end if;
 if action='reject'then update family_private.news_requests set status='rejected',reviewer_id=uid,reviewed_at=now(),review_note=left(payload->>'note',500)where id=r.id;return '{}';
 elsif action='approve'then
 select coalesce(array_agg(distinct x::uuid),'{}')into mentions from jsonb_array_elements_text(coalesce(payload->'mentions','[]'))x;
 if coalesce((payload->>'mention_requester')::boolean,false)then mentions:=array(select distinct x from unnest(mentions||r.requester_id)x);end if;
 if cardinality(mentions)>20 or exists(select 1 from unnest(mentions)m left join public.profiles p on p.id=m and p.tenant_id=tid left join auth.users u on u.id=p.id where p.id is null or p.status<>'active'or u.email_confirmed_at is null)then raise exception 'اختر حتى 20 عضوًا معتمدًا من العائلة للمنشن';end if;
 body_text:=coalesce(nullif(trim(payload->>'body'),''),r.rendered_body);detail:=coalesce(nullif(trim(payload->>'title'),''),r.title);
 if length(body_text)>10000 or length(detail)not between 3 and 250 then raise exception 'عنوان أو نص الخبر غير صحيح';end if;
 insert into public.posts(tenant_id,author_id,title,body,published,mentioned_member_ids,from_request)values(tid,uid,detail,body_text,true,mentions,true)returning id,published into pid,posted;
 update family_private.news_requests set status='approved',reviewer_id=uid,reviewed_at=now(),post_id=pid where id=r.id;
 return jsonb_build_object('post_id',pid,'published',posted);
 end if;
 raise exception 'إجراء غير معروف';end$$;
create function public.news_request_action(action text,payload jsonb default '{}')returns jsonb language sql security invoker set search_path='' as $$select family_private.news_request_action(action,payload)$$;
revoke all on function family_private.news_request_action(text,jsonb),public.news_request_action(text,jsonb)from public,anon;grant execute on function family_private.news_request_action(text,jsonb),public.news_request_action(text,jsonb)to authenticated;
-- Every journalist approval lookup must use the post's own family.
do $$declare def text;begin select pg_get_functiondef('family_private.moderate_post()'::regprocedure)into def;def:=replace(def,'from public.family_settings where id)','from public.family_settings where id and tenant_id=new.tenant_id)');execute def;
select pg_get_functiondef('public.lifecycle_backend(text,jsonb)'::regprocedure)into def;if position('<>33'in def)=0 then raise exception 'Lifecycle registry changed';end if;def:=replace(def,'<>33','<>35');def:=replace(def,'array[''family_private.square_reactions''','array[''family_private.news_requests'',''family_private.news_templates'',''family_private.square_reactions''');execute def;end$$;
notify pgrst,'reload schema';
commit;
