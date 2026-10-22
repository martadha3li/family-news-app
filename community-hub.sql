begin;
alter table family_private.member_details add column extra_roles text[] not null default '{}',add column birth_date date,add column birth_visible boolean not null default false;
alter table public.family_settings add column free_square_enabled boolean not null default true;
create table family_private.square_posts(id bigint generated always as identity primary key,tenant_id uuid not null references family_private.tenants(id),author_id uuid not null references public.profiles(id)on delete cascade,body text not null check(length(body)between 1 and 5000),created_at timestamptz not null default now());
create table family_private.square_comments(id bigint generated always as identity primary key,tenant_id uuid not null references family_private.tenants(id),post_id bigint not null references family_private.square_posts(id)on delete cascade,author_id uuid not null references public.profiles(id)on delete cascade,body text not null check(length(body)between 1 and 2000),created_at timestamptz not null default now());
create table family_private.square_reactions(tenant_id uuid not null references family_private.tenants(id),post_id bigint not null references family_private.square_posts(id)on delete cascade,user_id uuid not null references public.profiles(id)on delete cascade,emoji text not null check(emoji in('👍','❤️','😂','😮','😢','🙏')),primary key(tenant_id,post_id,user_id));
create index square_posts_family on family_private.square_posts(tenant_id,id desc);
create index square_comments_post on family_private.square_comments(tenant_id,post_id,id);
alter table family_private.square_posts enable row level security;alter table family_private.square_comments enable row level security;alter table family_private.square_reactions enable row level security;
revoke all on family_private.square_posts,family_private.square_comments,family_private.square_reactions from public,anon,authenticated;
create function family_private.member_roles(member uuid)returns text[] language sql stable security definer set search_path='' as $$select array(select distinct r from unnest(array[p.role]||coalesce(d.extra_roles,'{}'))r where r in('member','admin','journalist','auditor')and(r<>'admin'or p.role='admin')and(r<>'journalist'or p.role in('admin','journalist')))from public.profiles p left join family_private.member_details d on d.id=p.id where p.id=member$$;
revoke all on function family_private.member_roles(uuid)from public,anon,authenticated;
create function family_private.community_hub(action text,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();tid uuid:=family_private.current_tenant();ar text:=family_private.access_role();manager boolean:=ar='admin';reviewer boolean;target uuid;pid bigint;term text:=left(trim(coalesce(payload->>'term','')),100);txt text:=trim(payload->>'body');result jsonb;roles text[];enabled boolean;begin
 if uid is null or tid is null then raise exception 'سجل الدخول أولًا';end if;
 reviewer:=coalesce(manager,false)or(ar is not null and 'auditor'=any(family_private.member_roles(uid)));
 if action='self'then return(select jsonb_build_object('birth_date',d.birth_date,'birth_visible',d.birth_visible,'roles',family_private.member_roles(uid),'reviewer',reviewer,'enabled',s.free_square_enabled,'pending',case when reviewer then(select count(*)from public.profiles where tenant_id=tid and status='pending')else 0 end)from family_private.member_details d join public.family_settings s on s.tenant_id=tid and s.id where d.id=uid);end if;
 if action='birth_save'then
 if not family_private.tenant_writable(tid)then raise exception 'الكيان للاطلاع فقط';end if;
 if nullif(payload->>'birth_date','')is not null and ((payload->>'birth_date')::date>current_date or (payload->>'birth_date')::date<date '1900-01-01')then raise exception 'تاريخ ميلاد غير صحيح';end if;
 update family_private.member_details set birth_date=nullif(payload->>'birth_date','')::date,birth_visible=coalesce((payload->>'visible')::boolean,false)where id=uid;return '{}'::jsonb;end if;
 if ar is null then raise exception 'يلزم حساب معتمد';end if;
 if action='search'or action='team'then
 return coalesce((select jsonb_agg(to_jsonb(x))from(select p.id,p.display_name,p.avatar_path,family_private.member_roles(p.id)roles,exists(select 1 from family_private.member_follows f where f.tenant_id=tid and f.follower_id=uid and f.followed_id=p.id)following from public.profiles p join auth.users u on u.id=p.id where p.tenant_id=tid and p.status='active'and u.email_confirmed_at is not null and(case when action='team'then family_private.member_roles(p.id)&&array['admin','journalist','auditor']else term<>''and family_private.normalize_name(p.display_name)like '%'||replace(replace(family_private.normalize_name(term),'%','\%'),'_','\_')||'%'end)order by p.display_name limit 100)x),'[]');
 elsif action='profile'then
 target:=(payload->>'member')::uuid;
 return(select jsonb_build_object('roles',family_private.member_roles(p.id),'birth_date',case when uid=p.id or manager or d.birth_visible then d.birth_date else null end,'birth_visible',d.birth_visible)from public.profiles p join family_private.member_details d on d.id=p.id where p.id=target and p.tenant_id=tid and(p.status='active'or manager));
 elsif action='pending'then
 if not reviewer then raise exception 'للمدير والمدقق فقط';end if;
 return coalesce((select jsonb_agg(to_jsonb(x))from(select p.id,p.display_name,p.status,d.full_name,d.gender,d.reference_name,d.relationship,u.email,u.email_confirmed_at is not null email_confirmed from public.profiles p join family_private.member_details d on d.id=p.id join auth.users u on u.id=p.id where p.tenant_id=tid and p.status='pending'order by p.created_at limit 2000)x),'[]');
 elsif action='details'then
 if not manager then raise exception 'للمدير فقط';end if;
 return(select to_jsonb(d)||jsonb_build_object('display_name',p.display_name,'status',p.status,'role',p.role,'roles',family_private.member_roles(p.id),'email',u.email,'email_confirmed',u.email_confirmed_at is not null)from public.profiles p join family_private.member_details d on d.id=p.id join auth.users u on u.id=p.id where p.id=(payload->>'member')::uuid and p.tenant_id=tid);
 end if;
 if action in('activate','roles','enable','publish','comment','react','delete','comment_delete')and not family_private.tenant_writable(tid)then raise exception 'الكيان للاطلاع فقط؛ جدد الاشتراك';end if;
 if action='activate'then
 if not reviewer then raise exception 'للمدير والمدقق فقط';end if;
 target:=(payload->>'member')::uuid;
 perform pg_advisory_xact_lock(hashtextextended(target::text,7));
 if not exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=target and p.tenant_id=tid and p.status='pending'and u.email_confirmed_at is not null)then raise exception 'الطلب غير متاح أو البريد لم يؤكد بعد';end if;
 update public.profiles set status='active'where id=target and tenant_id=tid and status='pending';
 insert into family_private.admin_audit(tenant_id,actor,action)values(tid,uid,'activation:'||target::text);return '{}'::jsonb;
 elsif action='roles'then
 if not manager then raise exception 'للمدير فقط';end if;
 target:=(payload->>'member')::uuid;
 select array_agg(distinct r)into roles from jsonb_array_elements_text(payload->'roles')r;
 if roles is null or cardinality(roles)>4 or not roles<@array['admin','journalist','auditor','member']then raise exception 'صلاحيات غير صحيحة';end if;
 if not exists(select 1 from public.profiles where id=target and tenant_id=tid and not is_root and id<>uid)then raise exception 'الحساب محمي أو غير متاح';end if;
 update family_private.member_details set extra_roles=roles where id=target;
 update public.profiles set role=case when 'admin'=any(roles)then 'admin'when 'journalist'=any(roles)then 'journalist'else 'member'end where id=target and tenant_id=tid;
 insert into family_private.admin_audit(tenant_id,actor,action)values(tid,uid,'roles:'||target::text);return '{}'::jsonb;
 elsif action='enable'then
 if not manager then raise exception 'للمدير فقط';end if;
 update public.family_settings set free_square_enabled=(payload->>'enabled')::boolean where tenant_id=tid and id;return '{}'::jsonb;
 end if;
 select free_square_enabled into enabled from public.family_settings where tenant_id=tid and id;
 if not coalesce(enabled,false)then raise exception 'الساحة الحرة معطلة من مدير العائلة';end if;
 if action='feed'then
 return coalesce((select jsonb_agg(to_jsonb(x))from(select p.id,p.body,p.author_id,a.display_name,a.avatar_path,p.created_at,(select count(*)from family_private.square_comments c where c.tenant_id=tid and c.post_id=p.id)comments,(select coalesce(jsonb_object_agg(v.emoji,v.n),'{}')from(select r.emoji,count(*)n from family_private.square_reactions r where r.tenant_id=tid and r.post_id=p.id group by r.emoji)v)reactions,(select r.emoji from family_private.square_reactions r where r.tenant_id=tid and r.post_id=p.id and r.user_id=uid)my_reaction from family_private.square_posts p join public.profiles a on a.id=p.author_id and a.tenant_id=tid where p.tenant_id=tid and (nullif(payload->>'before','')is null or p.id<(payload->>'before')::bigint)order by p.id desc limit 30)x),'[]');
 elsif action='publish'then
 if txt is null or length(txt)not between 1 and 5000 then raise exception 'اكتب منشورًا من 1 إلى 5000 حرف';end if;
 if(select count(*)from family_private.square_posts where author_id=uid and created_at>now()-interval '1 minute')>=5 then raise exception 'انتظر قليلًا قبل نشر المزيد';end if;
 insert into family_private.square_posts(tenant_id,author_id,body)values(tid,uid,txt)returning id into pid;return to_jsonb(pid);
 end if;
 pid:=(payload->>'post')::bigint;
 if not exists(select 1 from family_private.square_posts where id=pid and tenant_id=tid)then raise exception 'المنشور غير موجود';end if;
 if action='comments'then return coalesce((select jsonb_agg(to_jsonb(x))from(select c.id,c.body,c.author_id,p.display_name,p.avatar_path,c.created_at from family_private.square_comments c join public.profiles p on p.id=c.author_id and p.tenant_id=tid where c.tenant_id=tid and c.post_id=pid and c.id>coalesce((payload->>'after')::bigint,0)order by c.id limit 100)x),'[]');
 elsif action='comment'then
 if txt is null or length(txt)not between 1 and 2000 then raise exception 'اكتب تعليقًا من 1 إلى 2000 حرف';end if;
 if(select count(*)from family_private.square_comments where author_id=uid and created_at>now()-interval '1 minute')>=20 then raise exception 'انتظر قليلًا قبل التعليق';end if;
 insert into family_private.square_comments(tenant_id,post_id,author_id,body)values(tid,pid,uid,txt);
 elsif action='react'then
 if nullif(payload->>'emoji','')is null then delete from family_private.square_reactions where tenant_id=tid and post_id=pid and user_id=uid;
 else insert into family_private.square_reactions(tenant_id,post_id,user_id,emoji)values(tid,pid,uid,payload->>'emoji')on conflict(tenant_id,post_id,user_id)do update set emoji=excluded.emoji;end if;
 elsif action='delete'then delete from family_private.square_posts where tenant_id=tid and id=pid and(author_id=uid or manager);if not found then raise exception 'لا تملك صلاحية الحذف';end if;
 elsif action='comment_delete'then delete from family_private.square_comments where tenant_id=tid and post_id=pid and id=(payload->>'comment')::bigint and(author_id=uid or manager);if not found then raise exception 'لا تملك صلاحية الحذف';end if;
 else raise exception 'إجراء غير معروف';end if;
 return '{}'::jsonb;
end$$;
create function public.community_hub(action text,payload jsonb default '{}')returns jsonb language sql security invoker set search_path='' as $$select family_private.community_hub(action,payload)$$;
revoke all on function family_private.community_hub(text,jsonb),public.community_hub(text,jsonb)from public,anon;grant execute on function family_private.community_hub(text,jsonb),public.community_hub(text,jsonb)to authenticated;
-- Preserve existing profile/follow APIs and append only permitted birth/role fields.
alter function family_private.member_social(text,jsonb)rename to member_social_base;
revoke all on function family_private.member_social_base(text,jsonb)from public,anon,authenticated;
create function family_private.member_social(action text,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$declare data jsonb;begin data:=family_private.member_social_base(action,payload);if action<>'grid'then data:=data||family_private.community_hub('profile',payload);end if;return data;end$$;
revoke all on function family_private.member_social(text,jsonb)from public,anon;grant execute on function family_private.member_social(text,jsonb)to authenticated;
-- Recreate the SQL wrapper so it points to the enriched function, not its renamed OID.
create or replace function public.member_social(action text,payload jsonb default '{}')returns jsonb language sql security invoker set search_path='' as $$select family_private.member_social(action,payload)$$;
create or replace function family_private.member_detail(member uuid)returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if family_private.access_role()is distinct from 'admin'then raise exception 'للمدير فقط';end if;
 return(select to_jsonb(d)||jsonb_build_object('email',u.email,'email_confirmed',u.email_confirmed_at is not null)from family_private.member_details d join public.profiles p on p.id=d.id join auth.users u on u.id=d.id where d.id=member and p.tenant_id=family_private.current_tenant());end$$;
-- Register every new tenant-owned table for the existing permanent-purge pipeline.
do $$declare def text;begin select pg_get_functiondef('public.lifecycle_backend(text,jsonb)'::regprocedure)into def;
 if position('<>30'in def)=0 or position('array[''family_private.follow_events'''in def)=0 then raise exception 'Lifecycle registry format changed';end if;
 def:=replace(def,'<>30','<>33');def:=replace(def,'array[''family_private.follow_events''','array[''family_private.square_reactions'',''family_private.square_comments'',''family_private.square_posts'',''family_private.follow_events''');execute def;end$$;
notify pgrst,'reload schema';
commit;
