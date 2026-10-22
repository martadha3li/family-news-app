begin;
alter table family_private.news_templates add column artwork_layout jsonb;
alter table family_private.news_requests add column artwork_layout jsonb;
alter table public.posts add column artwork_layout jsonb;
create function family_private.valid_artwork_layout(v jsonb)returns boolean language plpgsql immutable set search_path='' as $$declare key text;field text;r jsonb;x numeric;y numeric;w numeric;h numeric;begin
if v is null or v='null'then return true;end if;
if jsonb_typeof(v)<>'object'or not v ?& array['text','photo','align']or(select count(*)from jsonb_object_keys(v))<>3 or coalesce(v->>'align','')not in('left','center','right')then return false;end if;
foreach key in array array['text','photo']loop r:=v->key;if jsonb_typeof(r)<>'object'or not r ?& array['x','y','width','height']or(select count(*)from jsonb_object_keys(r))<>4 then return false;end if;foreach field in array array['x','y','width','height']loop if jsonb_typeof(r->field)<>'number'then return false;end if;end loop;x:=(r->>'x')::numeric;y:=(r->>'y')::numeric;w:=(r->>'width')::numeric;h:=(r->>'height')::numeric;if not coalesce(x>=0 and y>=0 and w>=60 and h>=60 and x+w<=1080 and y+h<=1080,false)then return false;end if;end loop;return true;exception when others then return false;end$$;
revoke all on function family_private.valid_artwork_layout(jsonb)from public,anon;grant execute on function family_private.valid_artwork_layout(jsonb)to authenticated;
alter table family_private.news_templates add constraint template_artwork_layout_valid check(family_private.valid_artwork_layout(artwork_layout));
alter table family_private.news_requests add constraint request_artwork_layout_valid check(family_private.valid_artwork_layout(artwork_layout));
alter table public.posts add constraint post_artwork_layout_valid check(family_private.valid_artwork_layout(artwork_layout));
alter function family_private.news_request_action(text,jsonb)rename to news_request_presentation_base;
revoke all on function family_private.news_request_presentation_base(text,jsonb)from public,anon,authenticated;
create function family_private.news_request_action(action text,payload jsonb default '{}')returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;tid uuid:=family_private.current_tenant();layout jsonb:=nullif(payload->'artwork_layout','null');begin
if action='template_save'and not family_private.valid_artwork_layout(layout)then raise exception 'مواضع النص والصورة يجب أن تكون داخل الخلفية والمحاذاة يمين أو وسط أو يسار';end if;
result:=family_private.news_request_presentation_base(action,payload);
if action='template_save'and payload?'artwork_layout'then update family_private.news_templates set artwork_layout=layout where id=(result#>>'{}')::uuid and tenant_id=tid;
elsif action='submit'then update family_private.news_requests r set artwork_layout=t.artwork_layout from family_private.news_templates t where r.id=(result#>>'{}')::uuid and r.tenant_id=tid and t.id=r.template_id and t.tenant_id=tid and r.requester_id=auth.uid()and r.status='pending';
elsif action='list'then select coalesce(jsonb_agg(v||jsonb_build_object('artwork_layout',r.artwork_layout)),'[]')into result from jsonb_array_elements(result)v join family_private.news_requests r on r.id=(v->>'id')::uuid and r.tenant_id=tid;end if;return result;end$$;
revoke all on function family_private.news_request_action(text,jsonb)from public,anon;grant execute on function family_private.news_request_action(text,jsonb)to authenticated;
create or replace function public.news_request_action(action text,payload jsonb default '{}')returns jsonb language sql security invoker set search_path='' as $$select family_private.news_request_action(action,payload)$$;
create function family_private.stamp_news_layout()returns trigger language plpgsql security definer set search_path='' as $$begin
if new.source_request_id is not null then select r.artwork_layout into new.artwork_layout from family_private.news_requests r where r.id=new.source_request_id and r.tenant_id=new.tenant_id;
elsif TG_OP='INSERT'then select t.artwork_layout into new.artwork_layout from family_private.news_templates t where t.tenant_id=new.tenant_id and t.artwork_key=new.news_artwork order by t.updated_at desc,t.id limit 1;
elsif new.news_artwork is distinct from old.news_artwork then select t.artwork_layout into new.artwork_layout from family_private.news_templates t where t.tenant_id=new.tenant_id and t.artwork_key=new.news_artwork order by t.updated_at desc,t.id limit 1;end if;return new;end$$;
revoke all on function family_private.stamp_news_layout()from public,anon,authenticated;
create trigger d_stamp_news_layout before insert or update on public.posts for each row execute function family_private.stamp_news_layout();
notify pgrst,'reload schema';commit;
