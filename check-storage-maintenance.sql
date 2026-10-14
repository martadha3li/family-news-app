begin;
select set_config('request.jwt.claim.sub',(select id::text from public.profiles where is_root),true);
create temp table cleanup_fixture as select gen_random_uuid() as old_room,gen_random_uuid() as active_room,gen_random_uuid() as boundary_room;
insert into family_private.chat_groups(id,owner_id,title,kind) select old_room,auth.uid(),'TEST_OLD','group' from cleanup_fixture union all select active_room,auth.uid(),'TEST_ACTIVE','group' from cleanup_fixture union all select boundary_room,auth.uid(),'TEST_BOUNDARY','group' from cleanup_fixture;
insert into family_private.chat_messages(group_id,sender_id,body,created_at) select old_room,auth.uid(),'OLD_TEST',now()-interval '11 months' from cleanup_fixture union all select active_room,auth.uid(),'ACTIVE_OLD_TEST',now()-interval '11 months' from cleanup_fixture union all select active_room,auth.uid(),'ACTIVE_RECENT_TEST',now()-interval '9 months' from cleanup_fixture union all select boundary_room,auth.uid(),'BOUNDARY_TEST',now()-interval '10 months' from cleanup_fixture;
select public.storage_maintenance('clean_chats','{"confirm":"DELETE_OLD_CHATS"}');
select not exists(select 1 from family_private.chat_messages where group_id=(select old_room from cleanup_fixture)) as old_room_cleaned,(select count(*)=2 from family_private.chat_messages where group_id=(select active_room from cleanup_fixture)) as active_room_preserved,exists(select 1 from family_private.chat_messages where group_id=(select boundary_room from cleanup_fixture)) as exact_boundary_preserved;
rollback;
