revoke execute on function public.media_send(jsonb),family_private.media_send(jsonb) from authenticated;
alter policy "chat media upload own" on storage.objects with check(false);
