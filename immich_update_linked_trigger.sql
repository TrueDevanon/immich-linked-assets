---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
----------------------------------------delete triggers--------------------------------------------------
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------


---- delete asset recursive

CREATE OR REPLACE FUNCTION linked.delete_linked_asset()
RETURNS TRIGGER AS $$
DECLARE
    a_cluster UUID;
BEGIN
    IF EXISTS (SELECT 1 FROM linked.asset WHERE id = old.id and base_owner is true) THEN
		SELECT asset_cluster INTO a_cluster FROM linked.asset WHERE id = old.id;
		delete from asset
		where id in (select id from linked.asset where asset_cluster = a_cluster);
	else
		delete from asset where id = old.id;
	END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- trigger for delete_asset_recursive

create OR REPLACE trigger trigger_delete_linked_asset before delete
on asset for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.delete_linked_asset();

-- delete asset from album

CREATE OR REPLACE FUNCTION linked.delete_from_album()
RETURNS TRIGGER AS $$
DECLARE
    a_asset_cluster UUID;
	a_album_cluster UUID;
BEGIN
	IF EXISTS (SELECT 1 FROM linked.asset WHERE id = old."assetsId" and base_owner is true) THEN
		select asset_cluster into a_asset_cluster from linked.asset where id = old."assetsId";
		select shared_album_cluster into a_album_cluster from linked.shared_album where id = old."albumsId";
		delete from album_asset
		where "assetsId" in (select id from linked.asset where asset_cluster = a_asset_cluster)
		and "albumsId" in (select id from linked.shared_album where shared_album_cluster = a_album_cluster);
	else
		delete from album_asset where "albumsId" = old."albumsId" and "assetsId" = old."assetsId";
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger for shared album asset

create OR REPLACE trigger trigger_delete_from_album before delete
on
album_asset for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.delete_from_album();

-- delete tag recursive

CREATE OR REPLACE FUNCTION linked.delete_linked_tag()
RETURNS TRIGGER AS $$
DECLARE
    t_cluster UUID;
BEGIN
    IF EXISTS (SELECT 1 FROM linked.tag WHERE id = old.id and base_owner is true) THEN
		SELECT tag_cluster INTO t_cluster FROM linked.tag WHERE id = old.id;
		delete from tag
		where id in (select id from linked.tag where tag_cluster = t_cluster);
	else
		delete from tag where id = old.id;
	END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- trigger for delete_tag_recursive

create OR REPLACE trigger trigger_delete_linked_tag before delete
on tag for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.delete_linked_tag();

---- delete asset tag

CREATE OR REPLACE FUNCTION linked.delete_asset_tag()
RETURNS TRIGGER AS $$
DECLARE
	a_asset_cluster UUID;
	a_tag_cluster UUID;
BEGIN
	IF new.type = 'DELETE' THEN
		select tag_cluster into a_tag_cluster from linked.tag where id = new.tag_id;
		select asset_cluster into a_asset_cluster from linked.asset where id = new.id;
		delete from tag_asset
		where "tagsId" in (select id from linked.tag where tag_cluster = a_tag_cluster)
		and "assetsId" in (select id from linked.asset where asset_cluster = a_asset_cluster);
		IF exists (select 1 from linked.album where tag_id = new.tag_id) THEN
			select asset_cluster into a_asset_cluster from linked.asset where id = new.id;
			delete from asset
			where id in (select id from linked.asset where asset_cluster = a_asset_cluster and base_owner is false);
			delete from linked.asset
			where id in (select id from linked.asset where asset_cluster = a_asset_cluster);
			delete from linked.tag_helper where id=new.id;
		END IF;
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_delete_asset_tag

create OR REPLACE trigger trigger_delete_asset_tag after update
on linked.tag_helper for each row
WHEN (pg_trigger_depth() = 1)
execute function linked.delete_asset_tag();

---- create tag_asset helper table

CREATE OR REPLACE FUNCTION linked.tag_helper_func()
RETURNS TRIGGER AS $$
BEGIN
	IF EXISTS (SELECT 1 FROM linked.tag WHERE id = new."tagsId" or id = old."tagsId") THEN
		IF exists (select 1 from linked.asset where (id = new."assetsId" or id = old."assetsId") and base_owner is true) THEN
			if TG_OP = 'INSERT' THEN
				insert into linked.tag_helper (id, tag_id, type, updated)
				select new."assetsId", new."tagsId", TG_OP, now()
				on conflict (id) do update set updated = now(), tag_id = new."tagsId", type = TG_OP;
			ELSIF TG_OP = 'DELETE' THEN
				IF not exists (select 1 from linked.tag_helper where id = old."assetsId" and now() - interval '0.5 second' <= updated) THEN
					insert into linked.tag_helper (id, tag_id, type, updated)
					select old."assetsId", old."tagsId", TG_OP, now()
					on conflict (id) do update set updated = now(), tag_id = old."tagsId", type = TG_OP;
				END IF;
			END IF;
		END IF;
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_tag_helper_func

create OR REPLACE trigger trigger_tag_helper_func after insert or delete
on tag_asset for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.tag_helper_func();

---- delete shared album recursive

CREATE OR REPLACE FUNCTION linked.delete_shared_album()
RETURNS TRIGGER AS $$
DECLARE
    a_cluster UUID;
BEGIN
    IF EXISTS (SELECT 1 FROM linked.shared_album WHERE id = old.id and base_owner is true) THEN
		SELECT shared_album_cluster INTO a_cluster FROM linked.shared_album WHERE id = old.id;
		delete from album
		where id in (select id from linked.shared_album where shared_album_cluster = a_cluster);
	else
		delete from album where id = old.id;
	END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- trigger for delete shared album recursive

create OR REPLACE trigger trigger_delete_shared_album before delete
on album for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.delete_shared_album();


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
----------------------------------------update triggers--------------------------------------------------
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------


---- create update tag recursive

CREATE OR REPLACE FUNCTION linked.update_linked_tag()
RETURNS trigger
AS $$
DECLARE
    t_cluster UUID;
BEGIN
    IF EXISTS (SELECT 1 FROM linked.tag WHERE id = new.id and base_owner is true) THEN
		SELECT tag_cluster INTO t_cluster FROM linked.tag WHERE id = new.id;
		update tag
		set color = new.color
		where id in (select id from linked.tag WHERE tag_cluster = t_cluster and id != new.id);
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- trigger for update tag recursive

create OR REPLACE trigger trigger_update_linked_tag after update
on tag for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.update_linked_tag();

---- create update albums

CREATE OR REPLACE FUNCTION linked.update_linked_album()
RETURNS trigger
AS $$
DECLARE
    a_cluster UUID;
BEGIN
	IF NOT EXISTS (SELECT 1 FROM linked.shared_album WHERE id = new.id) THEN
		IF new.description = 'create linked album' THEN
			--- new linked album
			with base as (select a."albumName" as album_name,uuid_generate_v4() as shared_album_cluster,la.album_cluster,la.owner_id,true as base_owner,a.id from album as a
				left join linked.album as la on a."ownerId"=la.owner_id
				where a.id=new.id),
			final_album as (
				select album_name,shared_album_cluster,owner_id,base_owner,id from base
				union all
				select b.album_name,b.shared_album_cluster,ls.owner_id,false,uuid_generate_v4() from base as b
				left join linked.album as ls using(album_cluster)
				where ls.owner_id!=b.owner_id),
			--- into album
			joined AS (SELECT 
				n.id as new_id,
				n.owner_id,
				to_jsonb(t) AS data
				FROM final_album as m
				left JOIN album as t ON t.id = m.id
				inner JOIN final_album as n ON m.shared_album_cluster = n.shared_album_cluster
				where m.id=new.id and n.id!=new.id),
			patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id), 
										'description', to_jsonb(''::text),
										'ownerId', to_jsonb(owner_id)) AS new_data FROM joined),
			insert_album as (
				INSERT INTO album
				SELECT (jsonb_populate_record(NULL::album, new_data)).*
				FROM patched
				ON CONFLICT (id) DO NOTHING
				RETURNING 1)
			--- into linked.shared_album
			insert into linked.shared_album (album_name,shared_album_cluster,owner_id,base_owner,id)
			select album_name,shared_album_cluster,owner_id,base_owner,id from final_album
			on conflict (id) do nothing;
			INSERT INTO album_asset ("albumsId","assetsId")
			with base as (select a.id,a.asset_cluster,sa.shared_album_cluster from album_asset as ta
				left join linked.asset as a on a.id = ta."assetsId"
				left join linked.shared_album as sa on sa.id = ta."albumsId"
				where ta."albumsId" = new.id)
			select lt.id,a.id from base as b
			inner join linked.asset as a using(asset_cluster)
			inner join linked.shared_album as lt using(shared_album_cluster,owner_id)
			where lt.id != new.id 
			on conflict ("albumsId","assetsId") do nothing;
			update album set description = '' where id = new.id;
		END IF;
	ELSIF EXISTS (SELECT 1 FROM linked.shared_album WHERE id = new.id and base_owner is true) THEN
		IF new.description = 'delete linked album' THEN
			--- delete linked album
			SELECT shared_album_cluster INTO a_cluster FROM linked.shared_album WHERE id = new.id;
			delete from album
			where id in (select id from linked.shared_album where shared_album_cluster = a_cluster and id != new.id);
			delete from linked.shared_album where id = new.id;
			update album set description = '' where id = new.id;
	    ELSE
			SELECT shared_album_cluster INTO a_cluster FROM linked.shared_album WHERE id = new.id;
			update album
			set "albumName" = new."albumName",
			description = new.description,
			"order" = new."order",
			"isActivityEnabled" = new."isActivityEnabled"
			where id in (select id from linked.shared_album WHERE shared_album_cluster = a_cluster and id != new.id);
		END IF;
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- trigger for update albums

create OR REPLACE trigger trigger_update_linked_album after update
on album for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.update_linked_album();

---- create update asset

CREATE OR REPLACE FUNCTION linked.update_linked_asset()
RETURNS trigger
AS $$
DECLARE
    a_cluster UUID;
BEGIN
    IF EXISTS (SELECT 1 FROM linked.asset WHERE id = new.id and base_owner is true) THEN
		SELECT asset_cluster INTO a_cluster FROM linked.asset WHERE id = new.id;
		update asset
		set "fileModifiedAt" = NEW."fileModifiedAt",
		"createdAt" = NEW."createdAt",
		"isOffline" = NEW."isOffline",
		"deletedAt" = NEW."deletedAt",
		"localDateTime" = NEW."localDateTime",
		visibility = NEW.visibility,
		status = NEW.status
		where id in (select id from linked.asset WHERE asset_cluster = a_cluster and id != new.id);
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- trigger for update asset

create OR REPLACE trigger trigger_update_linked_asset after update
on asset for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.update_linked_asset();

---- create update person metadata

CREATE OR REPLACE FUNCTION linked.update_linked_person()
 RETURNS trigger
AS $$
DECLARE
    f_cluster UUID;
BEGIN
	IF EXISTS (SELECT 1 FROM linked.asset_face WHERE person_id = new.id and base_owner is true) THEN
		SELECT face_cluster INTO f_cluster FROM linked.asset_face WHERE person_id = new.id limit 1;
		update person
		set "name"=new."name",
		"isHidden"=new."isHidden",
		"birthDate"=new."birthDate",
		color=new.color
		where id in (select person_id from linked.asset_face where face_cluster = f_cluster and person_id != new.id);
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_update_linked_person

create OR REPLACE trigger trigger_update_linked_person after update
on person for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.update_linked_person();

---- create update asset_face

CREATE OR REPLACE FUNCTION linked.sync_asset_face()
 RETURNS trigger
AS $$
BEGIN
	IF EXISTS (SELECT 1 FROM linked.asset_face WHERE person_id = old."personId") and old."personId" != new."personId" THEN
		update linked.asset_face
		set person_id = new."personId"
		where person_id = old."personId";
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_update_linked_person

create OR REPLACE trigger trigger_sync_asset_face after update
on asset_face for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.sync_asset_face();

---- create update asset metadata

CREATE OR REPLACE FUNCTION linked.update_linked_asset_exif()
 RETURNS trigger
AS $$
DECLARE
    a_cluster UUID;
BEGIN
    IF EXISTS (SELECT 1 FROM linked.asset WHERE id = new."assetId" and base_owner is true) THEN
		SELECT asset_cluster INTO a_cluster FROM linked.asset WHERE id = new."assetId";
		update asset_exif
		set orientation = NEW.orientation,
		"dateTimeOriginal"=new."dateTimeOriginal",
		"modifyDate" = NEW."modifyDate",
		latitude = NEW.latitude,
		longitude = NEW.longitude,
		city = NEW.city,
		state = NEW.state,
		country = NEW.country,
		description = NEW.description,
		"timeZone" = NEW."timeZone",
		rating = NEW.rating
		where "assetId" in (select id from linked.asset WHERE asset_cluster = a_cluster and base_owner is false);
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_update_linked_asset_exif

create OR REPLACE trigger trigger_update_linked_asset_exif after update
on asset_exif for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.update_linked_asset_exif();

---- create update/create person

CREATE OR REPLACE FUNCTION linked.insert_linked_person()
RETURNS trigger
AS $$
DECLARE
    a_face_cluster UUID;
BEGIN
	if new.base_owner is true THEN
		--- person already in linked database
		select face_cluster into a_face_cluster from linked.asset_face where face_cluster != new.face_cluster and person_id = new.person_id limit 1;
		IF a_face_cluster is not null THEN
			--- with the person already seen
			with base as (select af.asset_cluster,af.face_cluster,af.owner_id,af.base_owner,af.asset_id,af.person_id,af.id from linked.asset_face as af
				where af.id=new.id),
			final_asset_face as (
				select asset_cluster,face_cluster,owner_id,base_owner,asset_id,person_id,id from base
				union all
				select b.asset_cluster,b.face_cluster,ls.owner_id,ls.base_owner,ls.id as asset_id,lsl.person_id as person_id,ls.id from base as b
				left join linked.asset_face as ls using(asset_cluster,face_cluster)
				left join linked.asset_face as lsl on lsl.owner_id = ls.owner_id and lsl.face_cluster = a_face_cluster
				where ls.base_owner is false),
			update_asset_face as (
				update asset_face as af
				set "personId" = n.person_id,
				"deletedAt" = t."deletedAt"
				FROM final_asset_face m
				inner JOIN asset_face t ON t.id = m.id
				inner JOIN final_asset_face n ON m.asset_cluster = n.asset_cluster and m.face_cluster = n.face_cluster
				where m.base_owner is true and n.base_owner is false and n.id = af.id
				RETURNING 1)
			update linked.asset_face as af
			set person_id = faf.person_id
			from final_asset_face as faf
			where af.id = faf.id;
		ELSIF EXISTS (SELECT 1 FROM linked.asset WHERE id = (select "assetId" from asset_face where id = (select "faceAssetId" from person where id = new.person_id))) and new.base_owner is true THEN
			--- create person
			with base as (select af.asset_cluster,af.face_cluster,af.id as face_asset_id,af.owner_id,af.base_owner,af.asset_id,af.person_id as id from linked.asset_face as af
				where af.id=new.id),
			final_person as (
				select asset_cluster,face_cluster,face_asset_id,owner_id,base_owner,asset_id,id from base
				union all
				select b.asset_cluster,b.face_cluster,af.id,af.owner_id,af.base_owner,af.asset_id,uuid_generate_v4() from base as b
				left join linked.asset_face as af using(asset_cluster,face_cluster)
				where af.base_owner is false),
			--- insert into person;
			joined AS (SELECT
			    n.id as new_id,
			    n.owner_id,
			    n.face_asset_id,
			    to_jsonb(t) AS data
			  FROM final_person m
				inner JOIN person t ON t.id = m.id
				inner JOIN final_person n ON m.asset_cluster = n.asset_cluster and m.face_cluster = n.face_cluster
				where m.base_owner is true and n.base_owner is false),
			patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
			  								'ownerId', to_jsonb(owner_id),
			  								'faceAssetId', to_jsonb(face_asset_id)) AS new_data FROM joined),
			insert_into_person as (
				INSERT INTO person
				SELECT (jsonb_populate_record(NULL::person, new_data)).* FROM patched
				ON CONFLICT (id) DO NOTHING
				RETURNING 1),
			--- link face to preson
			update_face_to_person as (update linked.asset_face as a
				set person_id = fp.id
				from final_person as fp
				where a.id = fp.face_asset_id
				RETURNING 1)
			--- update person_id in asset_face
			update asset_face as a
			set "personId" = fp.id
			from final_person as fp
			where a.id = fp.face_asset_id;
		END IF;
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_insert_linked_person

create OR REPLACE trigger trigger_insert_linked_person after update or insert
on linked.asset_face for each row
WHEN (pg_trigger_depth() = 2)
execute function linked.insert_linked_person();


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
----------------------------------------insert triggers--------------------------------------------------
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------


---- create new albums

CREATE OR REPLACE FUNCTION linked.link_new_album()
RETURNS TRIGGER AS $$
BEGIN
	IF EXISTS (SELECT 1 FROM linked.shared_album WHERE id = new."albumsId") THEN
		IF EXISTS (SELECT 1 FROM linked.asset WHERE id = new."assetsId") THEN
			--- insert new asset
			INSERT INTO album_asset ("albumsId","assetsId")
			with base as (select ta."assetsId",a.asset_cluster,lt.shared_album_cluster from album_asset as ta
				left join linked.asset as a on a.id = ta."assetsId"
				left join linked.shared_album as lt on ta."albumsId" = lt.id
				where "albumsId" = new."albumsId" and "assetsId" = new."assetsId")
			select lt.id,a.id from base as b
			inner join linked.asset as a using(asset_cluster)
			inner join linked.shared_album as lt using(shared_album_cluster,owner_id)
			where a.id != "assetsId" and lt.id != new."albumsId"
			on conflict ("albumsId","assetsId") do nothing;
		END IF;	
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_link_new_album

create OR REPLACE trigger trigger_link_new_album after insert
    on album_asset for each row
    WHEN (pg_trigger_depth() = 0)
    execute function linked.link_new_album();

---- create new tag

CREATE OR REPLACE FUNCTION linked.link_new_tag()
RETURNS TRIGGER AS $$
BEGIN
	IF NOT EXISTS (SELECT 1 FROM linked.album WHERE tag_id = new."tagsId") THEN
		IF EXISTS (SELECT 1 FROM linked.asset WHERE id = new."assetsId" and base_owner is true) THEN
			IF NOT EXISTS (SELECT 1 FROM linked.tag WHERE id = new."tagsId") THEN
				--- new linked tag
				with base as (select uuid_generate_v4() as tag_cluster,la.asset_cluster,la.owner_id,la.base_owner,false as parent_updated,t.value,ta."tagsId" as id from tag_asset as ta
					left join linked.asset as la on ta."assetsId"=la.id
					left join tag as t on ta."tagsId"=t.id
					where ta."tagsId"=new."tagsId" and ta."assetsId"=new."assetsId"),
				final_tag as (
					select tag_cluster,owner_id,base_owner,parent_updated,value,id from base
					union all
					select b.tag_cluster,ls.owner_id,(case when t.id is not null then true else false end),false,b.value,coalesce(t.id,uuid_generate_v4()) from base as b
					left join linked.asset as ls using(asset_cluster)
					left join tag as t on b.value = t.value and ls.owner_id = t."userId"
					where ls.owner_id != b.owner_id),
				joined AS (SELECT
				    n.id as new_id,
				    n.owner_id,
				    null as parent_id,
				    to_jsonb(t) AS data
					FROM final_tag as m
				  	left JOIN tag as t ON t.id = m.id
				  	inner JOIN final_tag as n ON m.tag_cluster = n.tag_cluster
					where m.id=new."tagsId" and n.id!=new."tagsId"),
				patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
				  							'parentId', to_jsonb(parent_id),
				  							'userId', to_jsonb(owner_id)) AS new_data FROM joined),
				insert_tag as (
					INSERT INTO tag
					SELECT (jsonb_populate_record(NULL::tag, new_data)).* FROM patched
					ON CONFLICT (id) DO NOTHING
					RETURNING 1),
				--- into linked.tag
				insert_linked_tag as (
					insert into linked.tag (tag_cluster,owner_id,base_owner,parent_updated,value,id)
					select tag_cluster,owner_id,base_owner,parent_updated,value,id from final_tag
					on conflict (id) do nothing
					RETURNING 1)
				--- insert into tag_closure
				INSERT INTO tag_closure (id_ancestor,id_descendant)
				select id, id from final_tag
				on conflict (id_ancestor,id_descendant) do nothing;
			END IF;
			--- insert new asset
			INSERT INTO tag_asset ("assetsId","tagsId")
			with base as (select * from tag_asset as ta
				left join linked.asset as a on a.id = ta."assetsId"
				left join linked.tag as lt on ta."tagsId" = lt.id
				where "tagsId" = new."tagsId" and "assetsId" = new."assetsId")
			select a.id, lt.id from base as b
			inner join linked.asset as a using(asset_cluster)
			inner join linked.tag as lt on lt.tag_cluster=b.tag_cluster and a.owner_id=lt.owner_id
			where a.id != new."assetsId" and lt.id != new."tagsId"
			on conflict ("assetsId","tagsId") do nothing;
			IF exists (select 1 from linked.tag where id = new."tagsId" and parent_updated is false) then
				WITH RECURSIVE parents AS (
					SELECT id, "parentId" FROM tag WHERE id = new."tagsId"
					UNION ALL
					SELECT t.id, t."parentId" FROM tag t
					JOIN parents d ON t.id = d."parentId"
					where t."parentId" is not null),
				base as (SELECT ltc.id, ltpc.id as parent_id FROM parents as p
					left join linked.tag as lt on p.id = lt.id
					left join linked.tag as ltc on lt.tag_cluster = ltc.tag_cluster
					left join linked.tag as ltp on p."parentId" = ltp.id
					left join linked.tag as ltpc on ltp.tag_cluster = ltpc.tag_cluster and ltc.owner_id = ltpc.owner_id
					where p."parentId" is not null and ltc.id is not null and not exists (select 1 from parents where ltc.id=id)),
				insert_closure as (INSERT INTO tag_closure (id_ancestor,id_descendant)
					select id, case when parent_id is null then id else parent_id end from base
					on conflict (id_ancestor,id_descendant) do nothing
					RETURNING 1),
				parent_updated as (update linked.tag set parent_updated = true where id in (select id from base) RETURNING 1)
				update tag as t
				set "parentId" = parent_id
				from base as b
				where t.id = b.id;
			END IF;
		END IF;
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_link_new_tag

create OR REPLACE trigger trigger_link_new_tag after insert
on tag_asset for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.link_new_tag();

---- create new asset

CREATE OR REPLACE FUNCTION linked.link_new_asset()
RETURNS TRIGGER AS $$
DECLARE
    a_asset_cluster uuid;
	a_album_cluster uuid;
BEGIN
    IF EXISTS (SELECT 1 FROM linked.album WHERE tag_id = new."tagsId") THEN
		IF NOT EXISTS (SELECT 1 FROM linked.asset WHERE id = new."assetsId") THEN
		--- if asset should be linked
			SELECT uuid_generate_v4(), a.album_cluster
	        INTO a_asset_cluster, a_album_cluster
	        FROM linked.album a
	        WHERE a.tag_id = new."tagsId";
			---
			with asset_filter as (select a_album_cluster as album_cluster, a_asset_cluster as asset_cluster, a."ownerId" as owner_id, true as base_owner, a.id from asset as a where a.id=NEW."assetsId"),
			prepare_additional_faces as (select distinct p."faceAssetId", a.album_cluster, a.owner_id from asset_filter as a
				left join asset_file as af on a.id=af."assetId"
				left join asset_face as afa on afa."assetId"=a.id
				left join person as p on p.id=afa."personId"
				where afa."personId" is not null and not exists (select 1 from linked.asset_face where person_id=afa."personId")),
			additional_faces as (select distinct on (a.id) af.album_cluster,uuid_generate_v4() as asset_cluster,a."ownerId" as owner_id,true as base_owner,a.id from asset as a
				inner join (select distinct "assetId",album_cluster from asset_face as af
					inner join prepare_additional_faces as aaf on af.id=aaf."faceAssetId") as af
				on af."assetId"=a.id
				left join linked.album as b on b.album_cluster=af.album_cluster
				where not exists (select 1 from linked.asset where id = af."assetId")
				and not exists (select 1 from asset_filter where id=a.id)),
			prepare_final_table as (select * from asset_filter
				union all
				select * from additional_faces),
			final_table as (select b.album_cluster,a.asset_cluster,b.owner_id,coalesce(aa.base_owner,false) as base_owner,coalesce(aa.id,uuid_generate_v4()) as id from prepare_final_table as a
				left join linked.album as b on b.album_cluster = a.album_cluster
				left join prepare_final_table as aa on b.owner_id = aa.owner_id and aa.asset_cluster = a.asset_cluster),
			joined AS (SELECT 
				n.id as new_id,
				n.owner_id,
			    to_jsonb(t) AS data
			    FROM final_table m
			    left JOIN asset t ON t.id = m.id
			    left JOIN final_table n ON m.asset_cluster = n.asset_cluster
			    where m.base_owner is true and n.base_owner is false),
			patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
			  							'ownerId', to_jsonb(owner_id)) AS new_data FROM joined),
			insert_asset as (INSERT INTO asset
				SELECT (jsonb_populate_record(NULL::asset, new_data)).* FROM patched
				ON CONFLICT (id) DO NOTHING
				RETURNING 1),
			--- insert into linked
			insert_linked_asset as (insert into linked.asset (album_cluster, asset_cluster, owner_id, base_owner, id)
			select album_cluster, asset_cluster, owner_id, base_owner, id from final_table
			on conflict (id) do nothing
			RETURNING 1)
			--- insert new tag_asset
			INSERT INTO tag_asset ("assetsId","tagsId")
			with base as (select lt.tag_cluster from final_table as ft
				left join public.user as u on ft.owner_id = u.id
				left join linked.tag as lt on ft.owner_id = lt.owner_id and u.name = lt.value
				where ft.base_owner is true )
			select ft.id, t.id from final_table as ft
			left join linked.tag as t on t.tag_cluster in (select tag_cluster from base) and ft.owner_id=t.owner_id
			where t.id is not null
			union all
			select ft.id,al.tag_id from final_table as ft
			left join linked.album al using(album_cluster,owner_id)
			on conflict ("assetsId","tagsId") do nothing;
		END IF;
	END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_link_new_asset

create OR REPLACE trigger trigger_link_new_asset after insert
on 	tag_asset for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.link_new_asset();

---- create new link to files

CREATE OR REPLACE FUNCTION linked.link_new_asset_file()
RETURNS TRIGGER AS $$
BEGIN
    IF new.base_owner is true THEN
		with base as (select la.asset_cluster,uuid_generate_v4() as files_cluster,la.owner_id,la.base_owner,la.id as asset_id,af.id from asset_file as af
			inner join linked.asset as la on af."assetId"=la.id
			where af."assetId" = new.id),
		final_asset_file as (
			select asset_cluster,files_cluster,owner_id,base_owner,asset_id,id from base
			union all
			select b.asset_cluster,b.files_cluster,ls.owner_id,false,ls.id,uuid_generate_v4() from base as b
			left join linked.asset as ls using(asset_cluster)
			where ls.base_owner is false),
		--- insert into main
		joined AS (SELECT
			n.id as new_id,
			n.owner_id,
			n.asset_id,
			to_jsonb(t) AS data
			FROM final_asset_file m
			left JOIN asset_file t ON t.id = m.id
			left JOIN final_asset_file n ON m.asset_cluster = n.asset_cluster and m.files_cluster = n.files_cluster
			where m.base_owner is true and n.base_owner is false),
		patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
		  								'ownerId', to_jsonb(owner_id),
		  								'assetId', to_jsonb(asset_id)) AS new_data FROM joined),
		insert_asset_file as (
			INSERT INTO asset_file
			SELECT (jsonb_populate_record(NULL::asset_file, new_data)).*
			FROM patched
			ON CONFLICT (id) DO NOTHING
			RETURNING 1)
		--- insert into linked.asset_file
		insert into linked.asset_file (asset_cluster,files_cluster,owner_id,base_owner,asset_id,id)
		select asset_cluster,files_cluster,owner_id,base_owner,asset_id,id from final_asset_file
		on conflict (id) do nothing;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_link_new_asset_file

create OR REPLACE trigger trigger_link_new_asset_file after insert
on linked.asset for each row
WHEN (pg_trigger_depth() = 1)
execute function linked.link_new_asset_file();

---- create new face to asset


CREATE OR REPLACE FUNCTION linked.insert_linked_asset_face()
RETURNS trigger
AS $$
BEGIN
	IF exists (select 1 from asset_face where "assetId" = new.id) and new.base_owner is true THEN
		with base as (select la.asset_cluster,uuid_generate_v4() as face_cluster,la.owner_id,la.base_owner,la.id as asset_id,af."personId" as person_id,af.id
			from linked.asset as la
			left join asset_face as af on la.id=af."assetId"
			where la.id=new.id),
		final_asset_face as (
			select asset_cluster,face_cluster,owner_id,base_owner,asset_id,person_id,id from base
			union all
			select b.asset_cluster,b.face_cluster,ls.owner_id,ls.base_owner,ls.id as asset_id,null as person_id,uuid_generate_v4() as id from base as b
			left join linked.asset as ls using(asset_cluster)
			where ls.base_owner is false),
		--- insert to linked.asset_face
		insert_linked_asset_face as (
			insert into linked.asset_face (asset_cluster,face_cluster,owner_id,base_owner,asset_id,person_id,id)
			select asset_cluster,face_cluster,owner_id,base_owner,asset_id,person_id,id from final_asset_face
			on conflict (id) do nothing
			RETURNING 1),
		--- insert new rows to asset_face
		joined AS (SELECT
			n.id as new_id,
			n.asset_id,
			n.person_id,
			to_jsonb(t) AS data
			FROM final_asset_face m
			inner JOIN asset_face t ON t.id = m.id
			inner JOIN final_asset_face n ON m.asset_cluster = n.asset_cluster and m.face_cluster = n.face_cluster
			where m.base_owner is true and n.base_owner is false),
		patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
											'personId', to_jsonb(person_id),
			  								'assetId', to_jsonb(asset_id)) AS new_data FROM joined),
		insert_asset_face as (INSERT INTO asset_face
			SELECT (jsonb_populate_record(NULL::asset_face, new_data)).*
			FROM patched
			ON CONFLICT (id) DO NOTHING
			RETURNING 1),
		--- update faces
		update_asset_face as (update linked.asset_face as af
			set id = af.id
			FROM final_asset_face as faf
			where af.id = faf.id
			RETURNING 1)
		--- face search
		INSERT INTO face_search ("faceId", embedding)
		SELECT n.id, t.embedding
		FROM final_asset_face as m
		inner JOIN face_search as t ON t."faceId" = m.id
		inner JOIN final_asset_face as n ON m.asset_cluster = n.asset_cluster and m.face_cluster = n.face_cluster
		where m.base_owner is true and n.base_owner is false
		ON CONFLICT ("faceId") DO NOTHING;
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_insert_linked_asset_face

create OR REPLACE trigger trigger_insert_linked_asset_face after insert
on linked.asset for each row
WHEN (pg_trigger_depth() = 1)
execute function linked.insert_linked_asset_face();

---- create new asset metadata

CREATE OR REPLACE FUNCTION linked.link_new_asset_exif()
RETURNS TRIGGER AS $$
BEGIN
    IF new.base_owner is true THEN
		WITH joined AS (SELECT
		    n.id as new_id,
		    to_jsonb(t) AS data
		  	FROM linked.asset m
		  	left JOIN asset_exif t ON t."assetId" = m.id
		  	left JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
		  	where m.base_owner is true and n.base_owner is false and m.id = new.id),
		patched AS (SELECT data || jsonb_build_object('assetId', to_jsonb(new_id) ) AS new_data FROM joined)
		INSERT INTO asset_exif
		SELECT (jsonb_populate_record(NULL::asset_exif, new_data)).* FROM patched
		ON CONFLICT ("assetId") DO NOTHING;
	END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_link_new_asset_exif

create OR REPLACE trigger trigger_link_new_asset_exif after insert
on linked.asset for each row
WHEN (pg_trigger_depth() = 1)
execute function linked.link_new_asset_exif();

---- create new smart search

CREATE OR REPLACE FUNCTION linked.link_new_smart_search()
RETURNS TRIGGER AS $$
BEGIN
    IF new.base_owner is true THEN
		INSERT INTO smart_search ("assetId",embedding)
		SELECT n.id, t.embedding
		FROM linked.asset m
		inner JOIN smart_search t ON t."assetId" = m.id
		inner JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
		where m.base_owner is true and n.base_owner is false and m.id = new.id
		ON CONFLICT ("assetId") DO NOTHING;
	END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_link_new_smart_search

create OR REPLACE trigger trigger_link_new_smart_search after insert
on linked.asset for each row
WHEN (pg_trigger_depth() = 1)
execute function linked.link_new_smart_search();
