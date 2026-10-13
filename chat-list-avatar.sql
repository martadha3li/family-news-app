create or replace function family_private.chat_list() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if family_private.access_role() is null then raise exception 'حساب غير معتمد';end if;
 if not (select chat_enabled and private_chat_enabled from public.family_settings where id) then return '[]'::jsonb;end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (select t.id,p.display_name,p.avatar_path,p.id as member_id from family_private.chat_threads t join public.profiles p on p.id=case when t.member_a=auth.uid() then t.member_b else t.member_a end where auth.uid() in(t.member_a,t.member_b) and family_private.chat_pair_allowed(p.id) order by t.created_at desc limit 100)x),'[]'::jsonb);
end $$;
