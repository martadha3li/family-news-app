begin;
create temp table contact_fixture(label text,id uuid);insert into contact_fixture values('male',gen_random_uuid()),('female',gen_random_uuid()),('pending',gen_random_uuid());grant select on contact_fixture to authenticated;
insert into public.allowed_families(name) values('اختبارتواصل');
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) select id,id::text||'@example.invalid',now(),jsonb_build_object('full_name',label||' علي حسن اختبارتواصل','display_name',label||' علي حسن اختبارتواصل','gender',case when label='female' then 'female' else 'male' end,'reference_name','male علي حسن اختبارتواصل','relationship','father','phone',case label when 'male' then '+966500008831' when 'female' then '+966500008832' else '+966500008833' end) from contact_fixture order by case label when 'male' then 1 when 'female' then 2 else 3 end;
update public.profiles set status=case when id=(select id from contact_fixture where label='pending') then 'pending' else 'active' end where id in(select id from contact_fixture);

create temp table promo_fixture(id bigint);grant select,insert on promo_fixture to authenticated;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where is_root),true);
set local role authenticated;
with a as(insert into public.announcements(author_id,title,body,starts_at,ends_at,enabled,is_popup,image_path,display_seconds,repeat_days) values(auth.uid(),'فحص الإعلان الدعائي','لا يبقى',now()-interval '1 day',now()+interval '10 days',true,true,auth.uid()::text||'/11111111-1111-4111-8111-111111111111.jpg',3,2) returning id)insert into promo_fixture select id from a;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from contact_fixture where label='male'),true);
set local role authenticated;
do $$begin
 if not exists(select 1 from public.promo_due() where id=(select id from promo_fixture)) then raise exception 'due missing before claim';end if;
 if not public.promo_claim((select id from promo_fixture)) then raise exception 'first claim failed';end if;
 if exists(select 1 from public.promo_due() where id=(select id from promo_fixture)) then raise exception 'already viewed still due';end if;
 if public.promo_claim((select id from promo_fixture)) then raise exception 'repeat too soon';end if;
end$$;
reset role;
update public.ad_preferences set last_shown_at=now()-interval '25 hours' where ad_id=(select id from promo_fixture);
set local role authenticated;
do $$begin if public.promo_claim((select id from promo_fixture)) then raise exception '2 day interval ignored';end if;end$$;
reset role;
update public.ad_preferences set last_shown_at=now()-interval '49 hours' where ad_id=(select id from promo_fixture);
set local role authenticated;
do $$begin
 if not public.promo_claim((select id from promo_fixture)) then raise exception 'due not shown';end if;
 perform public.promo_hide((select id from promo_fixture),true);
end$$;
reset role;
update public.ad_preferences set last_shown_at=now()-interval '400 days' where ad_id=(select id from promo_fixture);
set local role authenticated;
do $$begin if public.promo_claim((select id from promo_fixture)) then raise exception 'opt out ignored';end if;if exists(select 1 from public.promo_due() where id=(select id from promo_fixture)) then raise exception 'hidden ad still due';end if;end$$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from contact_fixture where label='female'),true);
set local role authenticated;
do $$declare changed int;begin
 if exists(select 1 from public.ad_preferences) then raise exception 'other member preferences leaked';end if;
 if not public.promo_claim((select id from promo_fixture)) then raise exception 'member preference not independent';end if;
 update public.announcements set display_seconds=9 where id=(select id from promo_fixture);get diagnostics changed=row_count;if changed<>0 then raise exception 'member edited campaign';end if;
 begin insert into public.ad_preferences(user_id,ad_id) values((select id from contact_fixture where label='male'),(select id from promo_fixture));raise exception 'FOREIGN_PREFERENCE_ALLOWED';exception when insufficient_privilege then null;end;
end$$;
reset role;
update public.announcements set enabled=false where id=(select id from promo_fixture);
set local role authenticated;
do $$begin if public.promo_claim((select id from promo_fixture)) then raise exception 'disabled shown';end if;end$$;
reset role;
select set_config('request.jwt.claim.sub',(select id::text from contact_fixture where label='pending'),true);
set local role authenticated;
do $$begin if public.promo_claim((select id from promo_fixture)) then raise exception 'pending claim allowed';end if;end$$;
reset role;
do $$begin
 begin update public.announcements set display_seconds=0 where id=(select id from promo_fixture);raise exception 'INVALID_DURATION';exception when check_violation then null;end;
 begin update public.announcements set image_path=null where id=(select id from promo_fixture);raise exception 'NO_IMAGE';exception when check_violation then null;end;
 if has_function_privilege('anon','public.promo_claim(bigint)','EXECUTE') then raise exception 'anonymous execution';end if;
end$$;
select 'PASS: first display, exact repeat interval, independent accounts, permanent opt-out, RLS, disabled campaign, pending account, duration/image constraints and anonymous denial' as result;
rollback;
