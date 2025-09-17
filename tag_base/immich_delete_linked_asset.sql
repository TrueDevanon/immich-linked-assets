---- drop triggers on delete

drop trigger if exists trigger_delete_linked_asset on asset;
drop trigger if exists trigger_delete_linked_tag on tag;
drop trigger if exists trigger_delete_shared_album on album;
drop trigger if exists trigger_delete_from_album on album_asset;
drop trigger if exists trigger_delete_asset_tag on tag_asset;

---- drop triggers on base table

drop trigger if exists trigger_update_linked_tag on tag;
drop trigger if exists trigger_update_linked_asset on asset;
drop trigger if exists trigger_update_linked_person on person;
drop trigger if exists trigger_update_linked_asset_exif on asset_exif;
drop trigger if exists trigger_link_new_album on album_asset;
drop trigger if exists trigger_link_new_asset on tag_asset;
drop trigger if exists trigger_tag_helper_func on tag_asset;


---- delete cloned asset 

delete from asset 
where id in (select id from linked.asset where base_owner is false);
delete from asset_file
where id in (select id from linked.asset_file where base_owner is false);
delete from asset_face  
where id in (select id from linked.asset_face where base_owner is false);
delete from asset_exif 
where "assetId" in (select id from linked.asset where base_owner is false);
delete from person
where id in (select id from linked.person where base_owner is false);
delete from smart_search 
where "assetId" in (select id from linked.asset where base_owner is false);
delete from face_search 
where "faceId" in (select id from linked.asset_face where base_owner is false);
delete from tag 
where id in (select id from linked.tag where base_owner is false);
delete from album
where id in (select id from linked.shared_album where base_owner is false);

---- drop schema

drop SCHEMA linked cascade;

