alter table public.posts add column if not exists mentioned_member_ids uuid[] not null default '{}';
alter table public.posts add constraint posts_mentions_limit check (cardinality(mentioned_member_ids)<=20);
create index if not exists posts_mentions on public.posts using gin(mentioned_member_ids) where published and deleted_at is null;
create or replace function family_private.validate_post_mentions() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='UPDATE' and new.mentioned_member_ids is not distinct from old.mentioned_member_ids then return new; end if;
 if cardinality(new.mentioned_member_ids)>0 then
   if family_private.access_role() not in ('admin','journalist') or family_private.access_role() is null then raise exception 'لا يسمح حسابك بوضع منشن في الخبر'; end if;
   if exists(select 1 from unnest(new.mentioned_member_ids) m(id) left join public.profiles p on p.id=m.id where p.id is null or p.status<>'active') then raise exception 'اختر أعضاء معتمدين فقط للمنشن'; end if;
   if cardinality(new.mentioned_member_ids)<>(select count(distinct id) from unnest(new.mentioned_member_ids) m(id)) then raise exception 'لا تكرر العضو في المنشن'; end if;
 end if;
 return new;
end $$;
revoke all on function family_private.validate_post_mentions() from public,anon,authenticated;
create trigger validate_post_mentions before insert or update of mentioned_member_ids on public.posts for each row execute function family_private.validate_post_mentions();
