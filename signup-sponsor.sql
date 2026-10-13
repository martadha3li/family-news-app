create function family_private.signup_sponsor() returns trigger language plpgsql security definer set search_path='' as $$declare hint text:=trim(new.raw_user_meta_data->>'sponsor_hint');person uuid;matches integer;begin
 if not(select endorsements_enabled from public.family_settings where id) or coalesce(hint,'')='' then return new;end if;
 if hint ~ '^05[0-9]{8}$' then hint='+966'||substr(hint,2);end if;
 select count(*),min(p.id::text)::uuid into matches,person from public.profiles p join family_private.member_details d on d.id=p.id join auth.users u on u.id=p.id where p.id<>new.id and p.status='active' and u.email_confirmed_at is not null and (family_private.normalize_name(p.display_name)=family_private.normalize_name(hint) or d.phone=hint);
 if matches=1 then insert into family_private.endorsements(applicant_id,sponsor_id) values(new.id,person) on conflict do nothing;end if;
 return new;
end $$;
revoke all on function family_private.signup_sponsor() from public,anon,authenticated;
create trigger request_sponsor_on_signup after insert on auth.users for each row execute function family_private.signup_sponsor();
