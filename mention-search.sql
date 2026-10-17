begin;
create or replace function family_private.mention_search(term text default '') returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=auth.uid();prefix text:=family_private.normalize_name(left(trim(coalesce(term,'')),80));begin
 if uid is null or family_private.access_role() is null then raise exception 'المنشن للأعضاء المعتمدين';end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.proximity,x.display_name,x.id) from (
 select p.id,p.display_name,p.avatar_path,o.label as relation_label,
 case when k.relation in('father','mother','son','daughter','husband','wife') then 1
 when k.relation in('brother','sister','grandfather','grandmother','grandchild') then 2
 when k.relation in('uncle','maternal_uncle') then 3 when k.relation='cousin' then 4
 when k.member_id is not null then 5 else 9 end as proximity
 from public.profiles p left join family_private.personal_kinship k on k.owner_id=uid and k.member_id=p.id left join public.kinship_options o on o.code=k.relation
 where p.status='active' and p.id<>uid and starts_with(family_private.normalize_name(p.display_name),prefix)
 order by proximity,p.display_name,p.id limit 20
 )x),'[]'::jsonb);
end$$;
create function public.mention_search(term text default '') returns jsonb language sql security invoker set search_path='' as $$select family_private.mention_search(term)$$;
revoke all on function family_private.mention_search(text),public.mention_search(text) from public,anon,authenticated;
grant execute on function family_private.mention_search(text),public.mention_search(text) to authenticated;
notify pgrst,'reload schema';
commit;
