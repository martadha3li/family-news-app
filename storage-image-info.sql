create function family_private.storage_image_info(bucket text,path text) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if family_private.access_role()<>'admin' or family_private.access_role() is null then raise exception 'للمدير فقط';end if;
 return(select jsonb_build_object('bytes',(o.metadata->>'size')::bigint) from storage.objects o where o.bucket_id=bucket and o.name=path and o.bucket_id in('news-images','profile-images') and ((o.bucket_id='news-images' and exists(select 1 from public.posts where image_path=o.name)) or (o.bucket_id='profile-images' and exists(select 1 from public.profiles where avatar_path=o.name))));
end$$;
create function public.storage_image_info(bucket text,path text) returns jsonb language sql set search_path='' as $$select family_private.storage_image_info(bucket,path)$$;
revoke all on function family_private.storage_image_info(text,text),public.storage_image_info(text,text) from public,anon,authenticated;
grant execute on function family_private.storage_image_info(text,text),public.storage_image_info(text,text) to authenticated;
