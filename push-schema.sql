create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;
create table family_private.push_config(id boolean primary key default true check(id),public_key text not null,private_key text not null,dispatch_secret text not null);
create table family_private.push_subscriptions(endpoint text primary key,user_id uuid not null references public.profiles(id) on delete cascade,subscription jsonb not null,news boolean not null default true,private_chat boolean not null default true,updated_at timestamptz not null default now());
create index push_subscriber on family_private.push_subscriptions(user_id);
create table family_private.push_jobs(id bigint generated always as identity primary key,user_id uuid not null references public.profiles(id) on delete cascade,kind text not null check(kind in('news','chat')),item text not null,created_at timestamptz not null default now(),attempts int not null default 0,leased_at timestamptz,sent_at timestamptz,unique(user_id,kind,item));
create index push_pending on family_private.push_jobs(created_at) where sent_at is null;
alter table family_private.push_config enable row level security;alter table family_private.push_subscriptions enable row level security;alter table family_private.push_jobs enable row level security;
create policy push_config_lock on family_private.push_config for all using(false) with check(false);create policy push_subscription_lock on family_private.push_subscriptions for all using(false) with check(false);create policy push_job_lock on family_private.push_jobs for all using(false) with check(false);
revoke all on family_private.push_config,family_private.push_subscriptions,family_private.push_jobs from public,anon,authenticated;
create function family_private.push_action(action text,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();s jsonb:=payload->'subscription';ep text:=s->>'endpoint';begin
 if family_private.access_role() is null then raise exception 'الإشعارات للأعضاء المعتمدين';end if;
 if action='key' then return jsonb_build_object('publicKey',(select public_key from family_private.push_config where id));
 elsif action='subscribe' then
 if ep !~ '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|web[.]push[.]apple[.]com|[a-z0-9-]+[.]notify[.]windows[.]com)/' or char_length(ep)>2048 or coalesce(s->'keys'->>'p256dh','') !~ '^[A-Za-z0-9_-]{80,100}$' or coalesce(s->'keys'->>'auth','') !~ '^[A-Za-z0-9_-]{20,30}$' then raise exception 'اشتراك إشعارات غير صالح';end if;
 if (select count(*) from family_private.push_subscriptions where user_id=uid and endpoint<>ep)>=5 then raise exception 'حد الإشعارات خمسة أجهزة للحساب';end if;
 insert into family_private.push_subscriptions(endpoint,user_id,subscription,news,private_chat) values(ep,uid,s,coalesce((payload->>'news')::boolean,true),coalesce((payload->>'private_chat')::boolean,true)) on conflict(endpoint) do update set user_id=uid,subscription=excluded.subscription,news=excluded.news,private_chat=excluded.private_chat,updated_at=now();return 'true';
 elsif action='unsubscribe' then delete from family_private.push_subscriptions where user_id=uid and endpoint=payload->>'endpoint';return 'true';
 else raise exception 'إجراء غير معروف';end if;
end$$;
create function public.push_action(action text,payload jsonb default '{}') returns jsonb language sql set search_path='' as $$select family_private.push_action(action,payload)$$;
revoke all on function family_private.push_action(text,jsonb),public.push_action(text,jsonb) from public,anon,authenticated;
grant execute on function family_private.push_action(text,jsonb),public.push_action(text,jsonb) to authenticated;
create function family_private.queue_news_push() returns trigger language plpgsql security definer set search_path='' as $$begin
 if not new.published or new.deleted_at is not null then return new;end if;
 if TG_OP='UPDATE' and old.published then return new;end if;
 insert into family_private.push_jobs(user_id,kind,item) select distinct s.user_id,'news',new.id::text from family_private.push_subscriptions s join public.profiles p on p.id=s.user_id join auth.users u on u.id=p.id where s.news and p.status='active' and u.email_confirmed_at is not null and p.id<>new.author_id on conflict do nothing;return new;
end$$;
create function family_private.queue_chat_push() returns trigger language plpgsql security definer set search_path='' as $$declare peer uuid;begin
 if new.thread_id is null or new.group_id is not null then return new;end if;
 select case when member_a=new.sender_id then member_b else member_a end into peer from family_private.chat_threads where id=new.thread_id;
 insert into family_private.push_jobs(user_id,kind,item) select distinct s.user_id,'chat',new.id::text from family_private.push_subscriptions s join public.profiles p on p.id=s.user_id join auth.users u on u.id=p.id where s.user_id=peer and s.private_chat and p.status='active' and u.email_confirmed_at is not null on conflict do nothing;return new;
end$$;
revoke all on function family_private.queue_news_push(),family_private.queue_chat_push() from public,anon,authenticated;
create trigger queue_news_push after insert or update on public.posts for each row execute function family_private.queue_news_push();
create trigger queue_chat_push after insert on family_private.chat_messages for each row execute function family_private.queue_chat_push();
create function family_private.push_backend(action text,payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$declare answer jsonb;begin
 if action='config' then return(select to_jsonb(c) from family_private.push_config c where id);
 elsif action='claim' then
 with claimed as(update family_private.push_jobs j set attempts=attempts+1,leased_at=now() where j.id in(select id from family_private.push_jobs where sent_at is null and attempts<5 and (leased_at is null or leased_at<now()-interval '3 minutes') and created_at>now()-interval '1 day' order by id limit 100 for update skip locked) returning j.*) select jsonb_agg(jsonb_build_object('id',j.id,'kind',j.kind,'subscriptions',(select coalesce(jsonb_agg(s.subscription),'[]') from family_private.push_subscriptions s join public.profiles p on p.id=s.user_id join auth.users u on u.id=p.id where s.user_id=j.user_id and p.status='active' and u.email_confirmed_at is not null and case when j.kind='news' then s.news and exists(select 1 from public.posts where id::text=j.item and published and deleted_at is null) else s.private_chat and (select chat_enabled and private_chat_enabled from public.family_settings where id) and exists(select 1 from family_private.chat_messages m join family_private.member_details sender on sender.id=m.sender_id join family_private.member_details receiver on receiver.id=j.user_id where m.id::text=j.item and m.deleted_at is null and (not(select restrict_gender_chat from public.family_settings where id) or sender.gender=receiver.gender)) end))) into answer from claimed j;return coalesce(answer,'[]');
 elsif action='done' then update family_private.push_jobs set sent_at=now() where id=(payload->>'id')::bigint;return 'true';
 elsif action='expired' then delete from family_private.push_subscriptions where endpoint=payload->>'endpoint';return 'true';
 elsif action='cleanup' then delete from family_private.push_jobs where created_at<now()-interval '7 days';return 'true';
 else raise exception 'إجراء غير معروف';end if;
end$$;
create function public.push_backend(action text,payload jsonb default '{}') returns jsonb language sql set search_path='' as $$select family_private.push_backend(action,payload)$$;
revoke all on function family_private.push_backend(text,jsonb),public.push_backend(text,jsonb) from public,anon,authenticated;
grant usage on schema family_private to service_role;
grant execute on function family_private.push_backend(text,jsonb),public.push_backend(text,jsonb) to service_role;
