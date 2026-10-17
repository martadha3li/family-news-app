begin;
alter table public.announcements add column contact_member_id uuid references public.profiles(id) on delete set null;
create or replace function family_private.validate_ad_contact() returns trigger language plpgsql set search_path='' as $$begin
 if new.contact_member_id is null then return new;end if;
 if TG_OP='UPDATE' and new.contact_member_id is not distinct from old.contact_member_id then return new;end if;
 if not exists(select 1 from public.profiles where id=new.contact_member_id and status='active') then raise exception 'اختر عضوًا معتمدًا للتواصل';end if;
 return new;
end$$;
revoke all on function family_private.validate_ad_contact() from public,anon,authenticated;
create trigger validate_ad_contact before insert or update of contact_member_id on public.announcements for each row execute function family_private.validate_ad_contact();
notify pgrst,'reload schema';
commit;
