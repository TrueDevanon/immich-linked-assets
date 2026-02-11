---- drop triggers on delete

drop trigger if exists trigger_delete_linked_asset on public.asset;
drop trigger if exists trigger_delete_linked_tag on public.tag;
drop trigger if exists trigger_delete_shared_album on public.album;
drop trigger if exists trigger_delete_from_album on public.album_asset;
drop trigger if exists trigger_delete_linked_stack on public.stack;

---- drop triggers on linked base

drop trigger if exists trigger_link_new_asset_file on linked.asset;
drop trigger if exists trigger_insert_linked_asset_face on linked.asset;
drop trigger if exists trigger_link_new_asset_exif on linked.asset;
drop trigger if exists trigger_link_new_smart_search on linked.asset;
drop trigger if exists trigger_link_new_asset_ocr on linked.asset;
drop trigger if exists trigger_link_new_ocr_search on linked.asset;
drop trigger if exists trigger_insert_linked_person on linked.asset_face;
drop trigger if exists trigger_delete_asset_tag on linked.tag_helper;

---- drop triggers on base table

drop trigger if exists trigger_link_new_tag on public.tag_asset;
drop trigger if exists trigger_link_new_asset on public.tag_asset;
drop trigger if exists trigger_tag_helper_func on public.tag_asset;
drop trigger if exists trigger_update_linked_asset on public.asset;
drop trigger if exists trigger_sync_asset_face on public.asset_face;
drop trigger if exists trigger_update_linked_asset_exif on public.asset_exif;
drop trigger if exists trigger_update_linked_album on public.album;
drop trigger if exists trigger_link_new_album on public.album_asset;
drop trigger if exists trigger_update_linked_tag on public.tag;
drop trigger if exists trigger_update_linked_person on public.person;
drop trigger if exists trigger_update_stack_primary_asset on public.stack;
drop trigger if exists trigger_check_storage_template on public.system_metadata;

---- delete cloned asset 
delete from public.stack s
using linked.stack ls
where s.id = ls.id and ls.base_owner is false;
DELETE FROM public.asset a
USING linked.asset la
WHERE a.id = la.id AND la.base_owner is false;
delete from public.asset_file as a
    where exists (select 1 from linked.asset_file where id = a.id and base_owner is false);
delete from public.asset_face as a
    where exists (select 1 from linked.asset_face where id = a.id and base_owner is false);
delete from public.asset_exif as a
    where exists (select 1 from linked.asset where id = a."assetId" and base_owner is false);
delete from public.smart_search as a
    where exists (select 1 from linked.asset where id = a."assetId" and base_owner is false);
delete from public.face_search as a
    where exists (select 1 from linked.asset_face where id = a."faceId" and base_owner is false);
delete from public.tag as a
    where exists (select 1 from linked.tag where id = a.id and base_owner is false);
delete from public.album as a
    where exists (select 1 from linked.shared_album where id = a.id and base_owner is false);

---- drop schema

drop SCHEMA linked cascade;

