begin;
alter table public.family_settings add column whole_tree_enabled boolean not null default false;
create function family_private.whole_tree(action text,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$declare tid uuid:=family_private.current_tenant();manager boolean:=family_private.access_role()='admin';a uuid;b uuid;r text;begin
 if family_private.access_role()is null then raise exception 'حساب غير معتمد';end if;
 if action='settings'then return jsonb_build_object('enabled',manager or coalesce((select whole_tree_enabled from public.family_settings where tenant_id=tid and id),false),'public_enabled',(select whole_tree_enabled from public.family_settings where tenant_id=tid and id),'admin',manager);end if;
 if action in('enable','link','unlink')then
 if not manager then raise exception 'مدير العائلة فقط';end if;if not family_private.tenant_writable(tid)then raise exception 'الكيان للاطلاع فقط';end if;
 if action='enable'then update public.family_settings set whole_tree_enabled=(payload->>'enabled')::boolean where tenant_id=tid and id;return 'true';end if;
 a:=(payload->>'owner')::uuid;b:=(payload->>'member')::uuid;r:=payload->>'relation';
 if a=b or a is null or b is null or(select count(*)from public.profiles where tenant_id=tid and id in(a,b))<>2 then raise exception 'اختر عضوين مختلفين من عائلتك';end if;
 if action='unlink'then delete from family_private.personal_kinship where tenant_id=tid and owner_id=a and member_id=b;return 'true';end if;
 if not exists(select 1 from public.kinship_options where tenant_id=tid and code=r and enabled)then raise exception 'اختر صلة قرابة مفعّلة';end if;
 insert into family_private.personal_kinship(tenant_id,owner_id,member_id,relation,confirmed_by,confirmed_at)values(tid,a,b,r,auth.uid(),now())on conflict(owner_id,member_id)do update set relation=excluded.relation,confirmed_by=excluded.confirmed_by,confirmed_at=excluded.confirmed_at;return 'true';
 elsif action<>'get'then raise exception 'إجراء غير معروف';end if;
 if not manager and not coalesce((select whole_tree_enabled from public.family_settings where tenant_id=tid and id),false)then raise exception 'عرض الشجرة العامة غير مفعّل من المدير';end if;
 return jsonb_build_object('name',(select name from family_private.tenants where id=tid),'logo',(select logo from family_private.tenants where id=tid),'admin',manager,'public_enabled',(select whole_tree_enabled from public.family_settings where tenant_id=tid and id),'nodes',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name,'avatar_path',p.avatar_path,'status',p.status)order by p.display_name),'[]')from public.profiles p where p.tenant_id=tid and(manager or p.status='active')),'edges',(select coalesce(jsonb_agg(jsonb_build_object('owner',k.owner_id,'member',k.member_id,'relation',k.relation,'label',o.label,'generation',o.generation)),'[]')from family_private.personal_kinship k join public.kinship_options o on o.tenant_id=k.tenant_id and o.code=k.relation join public.profiles p on p.id=k.owner_id and p.tenant_id=tid join public.profiles q on q.id=k.member_id and q.tenant_id=tid where k.tenant_id=tid and k.confirmed_at is not null and(manager or(p.status='active'and q.status='active'))),'options',case when manager then(select coalesce(jsonb_agg(jsonb_build_object('code',code,'label',label)),'[]')from public.kinship_options where tenant_id=tid and enabled)else '[]'::jsonb end);
end$$;
create function public.whole_tree(action text default 'get',payload jsonb default '{}')returns jsonb language sql security invoker set search_path='' as $$select family_private.whole_tree(action,payload)$$;
revoke all on function family_private.whole_tree(text,jsonb),public.whole_tree(text,jsonb)from public,anon;grant execute on function family_private.whole_tree(text,jsonb),public.whole_tree(text,jsonb)to authenticated;
-- Logo uploads are optional for new tenants. The original 01 keeps its existing identity.
alter function public.tenant_request(jsonb)rename to tenant_request_with_logo;
revoke all on function public.tenant_request_with_logo(jsonb)from public,anon,authenticated;
do $$declare def text;begin select pg_get_functiondef('public.tenant_request_with_logo(jsonb)'::regprocedure)into def;def:=replace(def,'or pic is null','');execute def;end$$;
create function public.tenant_request(data jsonb)returns text language sql security definer set search_path=''as $$select public.tenant_request_with_logo(data)$$;
revoke all on function public.tenant_request(jsonb)from public;grant execute on function public.tenant_request(jsonb)to anon,authenticated;
notify pgrst,'reload schema';
commit;
