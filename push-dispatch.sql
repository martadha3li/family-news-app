create function family_private.dispatch_push() returns void language plpgsql security definer set search_path='' as $$declare stamp text:=floor(extract(epoch from now()))::bigint::text;signature text;begin
 delete from family_private.push_jobs where created_at<now()-interval '7 days';
 if not exists(select 1 from family_private.push_jobs where sent_at is null and attempts<5 and created_at>now()-interval '1 day') then return;end if;
 select encode(extensions.hmac(stamp||':family-push',dispatch_secret,'sha256'),'hex') into signature from family_private.push_config where id;
 perform net.http_post(url:='https://dlkykiducjimwehfhxfq.supabase.co/functions/v1/family-push',headers:=jsonb_build_object('Content-Type','application/json','x-family-signature',signature,'x-family-time',stamp),body:='{}',timeout_milliseconds:=60000);
end$$;
revoke all on function family_private.dispatch_push() from public,anon,authenticated;
select cron.schedule('family-news-push','* * * * *','select family_private.dispatch_push()');

