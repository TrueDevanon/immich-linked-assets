---- drop triggers on delete

drop trigger if exists trigger_delete_linked_asset on asset;
drop trigger if exists trigger_delete_linked_tag on tag;
drop trigger if exists trigger_delete_shared_album on album;
drop trigger if exists trigger_delete_from_album on album_asset;

---- drop triggers on linked base

drop trigger if exists trigger_link_new_asset_file on linked.asset;
drop trigger if exists trigger_insert_linked_asset_face on linked.asset;
drop trigger if exists trigger_link_new_asset_exif on linked.asset;
drop trigger if exists trigger_link_new_smart_search on linked.asset;
drop trigger if exists trigger_insert_linked_person on linked.asset_face;
drop trigger if exists trigger_delete_asset_tag on linked.tag_helper;

---- drop triggers on base table

drop trigger if exists trigger_link_new_tag on tag_asset;
drop trigger if exists trigger_link_new_asset on tag_asset;
drop trigger if exists trigger_tag_helper_func on tag_asset;
drop trigger if exists trigger_update_linked_asset on asset;
drop trigger if exists trigger_sync_asset_face on asset_face;
drop trigger if exists trigger_update_linked_asset_exif on asset_exif;
drop trigger if exists trigger_update_linked_album on album;
drop trigger if exists trigger_link_new_album on album_asset;
drop trigger if exists trigger_update_linked_tag on tag;
drop trigger if exists trigger_update_linked_person on person;

---- delete cloned asset 

DELETE FROM asset a
USING linked.asset la
WHERE a.id = la.id AND la.base_owner is false;
delete from asset_file as a
    where exists (select 1 from linked.asset_file where id = a.id and base_owner is false);
delete from asset_face as a
    where exists (select 1 from linked.asset_face where id = a.id and base_owner is false);
delete from asset_exif as a
    where exists (select 1 from linked.asset where id = a."assetId" and base_owner is false);
delete from smart_search as a
    where exists (select 1 from linked.asset where id = a."assetId" and base_owner is false);
delete from face_search as a
    where exists (select 1 from linked.asset_face where id = a."faceId" and base_owner is false);
delete from tag as a
    where exists (select 1 from linked.tag where id = a.id and base_owner is false);
delete from album as a
    where exists (select 1 from linked.shared_album where id = a.id and base_owner is false);

---- drop schema

drop SCHEMA linked cascade;

