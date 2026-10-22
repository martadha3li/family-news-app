begin;
alter table family_private.news_templates add column artwork_key text;
alter table family_private.news_requests add column artwork_key text;
alter table public.posts add column news_artwork text,add column artwork_smart_crop boolean not null default true;
create function family_private.artwork_key(label text)returns text language sql immutable set search_path='' as $$select case when family_private.normalize_name(label)like 'عاجل%'then 'urgent'when family_private.normalize_name(label)like 'ترقي%'then 'promotion'when family_private.normalize_name(label)like 'انجاز عائل%'then 'achievement'when family_private.normalize_name(label)like 'البقاء لله%'or family_private.normalize_name(label)like 'وفاة%'or family_private.normalize_name(label)like 'الي رحمة الله%'then 'death'when family_private.normalize_name(label)like 'تخرج%'then 'graduation'when family_private.normalize_name(label)like 'مولود%'or family_private.normalize_name(label)like 'رزق بمولود%'then 'newborn'when family_private.normalize_name(label)like 'ختم%قر%'then 'quran'when family_private.normalize_name(label)like 'علي السرير الابيض%'then 'hospital'when family_private.normalize_name(label)like 'خروج من المشف%'then 'recovery'else null end$$;
revoke all on function family_private.artwork_key(text)from public,anon,authenticated;
alter table family_private.news_templates add constraint news_template_artwork check(artwork_key is null or artwork_key in('urgent','promotion','achievement','death','graduation','newborn','quran','quran-qr','hospital','recovery'));
alter table public.posts add constraint news_artwork_valid check(news_artwork is null or news_artwork in('urgent','promotion','achievement','death','graduation','newborn','quran','quran-qr','hospital','recovery'));
create function family_private.stamp_news_artwork()returns trigger language plpgsql security definer set search_path='' as $$declare allowed boolean;key text;begin
select code='01'into allowed from family_private.tenants where id=new.tenant_id;
if not coalesce(allowed,false)then new.news_artwork:=null;return new;end if;
if new.source_request_id is not null then
 select r.artwork_key,r.smart_crop_enabled into key,new.artwork_smart_crop from family_private.news_requests r where r.id=new.source_request_id and r.tenant_id=new.tenant_id;
 new.news_artwork:=coalesce(key,family_private.artwork_key(new.title));
elsif TG_OP='INSERT'or new.title is distinct from old.title then new.news_artwork:=coalesce(new.news_artwork,family_private.artwork_key(new.title));end if;
new.artwork_smart_crop:=coalesce(new.artwork_smart_crop,true);return new;end$$;
revoke all on function family_private.stamp_news_artwork()from public,anon,authenticated;
create trigger b_stamp_news_artwork before insert or update on public.posts for each row execute function family_private.stamp_news_artwork();
-- Keep original authorization, exclusive review lease and publication rules intact.
alter function family_private.news_request_action(text,jsonb)rename to news_request_guarded;
revoke all on function family_private.news_request_guarded(text,jsonb)from public,anon,authenticated;
create function family_private.news_request_action(action text,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;key text;tid uuid:=family_private.current_tenant();begin
if action='template_save'then
key:=nullif(payload->>'artwork_key','');if key is not null and(not exists(select 1 from family_private.tenants where id=tid and code='01')or key not in('urgent','promotion','achievement','death','graduation','newborn','quran','quran-qr','hospital','recovery'))then raise exception 'خلفية غير متاحة لهذا الكيان';end if;
end if;
result:=family_private.news_request_guarded(action,payload);
if action='template_save'and payload?'artwork_key'then update family_private.news_templates set artwork_key=key where id=(result#>>'{}')::uuid and tenant_id=tid;
elsif action='submit'then update family_private.news_requests r set artwork_key=t.artwork_key from family_private.news_templates t where r.id=(result#>>'{}')::uuid and r.tenant_id=tid and t.tenant_id=tid and t.id=r.template_id and r.requester_id=auth.uid();
elsif action='list'then select coalesce(jsonb_agg(v||jsonb_build_object('artwork_key',r.artwork_key)),'[]')into result from jsonb_array_elements(result)v join family_private.news_requests r on r.id=(v->>'id')::uuid and r.tenant_id=tid;
end if;return result;end$$;
revoke all on function family_private.news_request_action(text,jsonb)from public,anon;grant execute on function family_private.news_request_action(text,jsonb)to authenticated;
create or replace function public.news_request_action(action text,payload jsonb default '{}')returns jsonb language sql security invoker set search_path='' as $$select family_private.news_request_action(action,payload)$$;
-- Only the supplied family's templates: preserve any existing wording or disabled state.
do $$declare tid uuid;v record;existing uuid;begin select id into tid from family_private.tenants where code='01';if tid is null then return;end if;
for v in select * from(values('عاجل','urgent','general','{subject}\n{details}'),('ترقية','promotion','general','نبارك إلى {subject} بمناسبة الترقية.\n{details}'),('إنجاز عائلي','achievement','general','نبارك إلى {subject} هذا الإنجاز.\n{details}'),('البقاء لله','death','general','إنا لله وإنا إليه راجعون.\n{subject}\n{details}'),('تخرج','graduation','general','نبارك إلى {subject} بمناسبة التخرج.\n{details}'),('مولود جديد','newborn','newborn','نبارك إلى {subject} بالمولود {newborn}.\n{details}'),('ختمة قرآن','quran','general','نبارك إلى {subject} إتمام ختم القرآن الكريم.\n{details}'),('ختمة قرآن · مع رموز التواصل','quran-qr','general','نبارك إلى {subject} إتمام ختم القرآن الكريم.\n{details}'),('على السرير الأبيض','hospital','general','يرقد {subject} على السرير الأبيض.\n{details}\nنسأل الله له الشفاء والعافية.'),('خروج من المشفى','recovery','general','نحمد الله على سلامة {subject} وخروجه من المشفى.\n{details}'))as seeds(name,key,kind,body)loop
select id into existing from family_private.news_templates t where t.tenant_id=tid and(family_private.normalize_name(t.name)=family_private.normalize_name(v.name)or(t.artwork_key=v.key))order by updated_at desc limit 1;
if existing is null then insert into family_private.news_templates(tenant_id,name,kind,body,artwork_key)values(tid,v.name,v.kind,replace(v.body,'\n',chr(10)),v.key);else update family_private.news_templates set artwork_key=v.key where id=existing;end if;
end loop;end$$;
update family_private.news_templates t set artwork_key=family_private.artwork_key(t.name)from family_private.tenants f where f.id=t.tenant_id and f.code='01'and t.artwork_key is null and family_private.artwork_key(t.name)is not null;
notify pgrst,'reload schema';commit;
