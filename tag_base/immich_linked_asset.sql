---- create schema

CREATE SCHEMA linked AUTHORIZATION postgres;

----- create tables

CREATE TABLE linked.album (
	album_cluster uuid NOT NULL,
	owner_id uuid NOT NULL,
	base_owner bool DEFAULT false NOT NULL,
	description text NOT NULL,
	tag_id uuid,
	id uuid NOT NULL,
	CONSTRAINT linked_album_pk PRIMARY KEY (id)
);

CREATE TABLE linked.tag (
	tag_cluster uuid NOT NULL,
	owner_id uuid NOT NULL,
	base_owner bool DEFAULT false NOT NULL,
	parent_updated bool DEFAULT false NOT NULL,
	value text not null,
	id uuid NOT NULL,
	CONSTRAINT linked_tag_pk PRIMARY KEY (id)
);

CREATE TABLE linked.shared_album (
	album_name text NOT NULL,
	shared_album_cluster uuid NOT NULL,
	owner_id uuid not null,
	base_owner bool DEFAULT false NOT NULL,
	id uuid NOT NULL,
	CONSTRAINT linked_shared_album_pk PRIMARY KEY (id)
);

CREATE TABLE linked.asset (
	album_cluster uuid NOT NULL,
	asset_cluster uuid NOT NULL,
	owner_id uuid NOT NULL,
	base_owner bool DEFAULT false NOT NULL,
	id uuid NOT null,
	CONSTRAINT linked_asset_pk PRIMARY KEY (id)
);

CREATE TABLE linked.asset_file (
	asset_cluster uuid NOT NULL,
	files_cluster uuid NOT NULL,
	owner_id uuid NOT NULL,
	base_owner bool DEFAULT false NOT NULL,
	asset_id uuid NOT NULL,
	id uuid NOT NULL,
	CONSTRAINT linked_asset_file_pk PRIMARY KEY (id)
);

CREATE TABLE linked.asset_face (
	asset_cluster uuid NOT NULL,
	face_cluster uuid NOT NULL,
	owner_id uuid NOT NULL,
	base_owner bool DEFAULT false NOT NULL,
	asset_id uuid NOT NULL,
	person_id uuid NULL,
	id uuid NOT NULL,
	CONSTRAINT linked_asset_face_pk PRIMARY KEY (id)
);

CREATE TABLE linked.person (
	asset_cluster uuid NOT NULL,
	face_cluster uuid NOT NULL,
	face_asset_id uuid NOT NULL,
	owner_id uuid NOT NULL,
	base_owner bool DEFAULT false NOT NULL,
	asset_id uuid NOT NULL,
	id uuid NOT NULL,
	CONSTRAINT linked_person_pk PRIMARY KEY (id)
);

create table linked.tag_helper (
	id uuid not null, 
	updated timestamp default NOW() not null, 
	CONSTRAINT tag_helper_pk PRIMARY KEY (id));


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
----------------------------------------create base tables-----------------------------------------------
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------

---- create linked.album

insert into linked.album (album_cluster,owner_id,base_owner,description,id)          
with base as (
	select uuid_generate_v4() as album_cluster,"ownerId" as owner_id,true as base_owner,description,id from album
	WHERE album."albumName"::text ~~* '%%linked album%%'::text) 
select album_cluster,owner_id,base_owner,description,id from base 
union
select a.album_cluster,b."usersId",false,a.description,uuid_generate_v4() from base as a
LEFT JOIN album_user as b ON a.id = b."albumsId"
on conflict (id) do nothing;

---- update linked_tag_id

update linked.album as a
set tag_id = t.id
from (
	select  t.id, b.album_cluster, b.owner_id from linked.album as b
	left join tag as t on t.value ilike b.description::text || '%%' and t."userId"=b.owner_id) as t
where a.album_cluster = t.album_cluster and a.owner_id = t.owner_id;

---- create linked.asset

with asset_filter as (select b.album_cluster,a.asset_cluster, a."ownerId" as owner_id,true as base_owner,a.id from (select *, uuid_generate_v4() as asset_cluster from asset) as a
left join linked.album as b on b.owner_id = a."ownerId"
where exists (select 1 from tag_asset where "assetsId" = a.id and "tagsId" = b.tag_id)),
prepare_additional_faces as (select distinct p."faceAssetId", a.album_cluster, a.owner_id from asset_filter as a
	left join asset_file as af on a.id=af."assetId"
	left join asset_face as afa on afa."assetId"=a.id
	left join person as p on p.id=afa."personId"
	where afa."personId" is not null),
additional_faces as (select distinct on (af.album_cluster,a.id) af.album_cluster,FIRST_VALUE(a.asset_cluster) OVER (PARTITION BY a."ownerId",a.id) AS asset_cluster,a."ownerId" as owner_id,true as base_owner,a.id from (select *, uuid_generate_v4() as asset_cluster from asset) as a
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
	left join prepare_final_table as aa on b.owner_id = aa.owner_id and aa.asset_cluster = a.asset_cluster and a.album_cluster = aa.album_cluster)
insert into linked.asset (album_cluster, asset_cluster, owner_id, base_owner, id) 
select distinct on (id) album_cluster,asset_cluster,owner_id,base_owner,id from final_table as a
on conflict (id) do nothing;

---- create linked_asset_file

with base as (select la.asset_cluster,af.files_cluster,la.owner_id,la.base_owner,la.id as asset_id,af.id from (select *,uuid_generate_v4() as files_cluster from asset_file) as af
	inner join linked.asset as la on af."assetId"=la.id
	where la.base_owner is true)
--
insert into linked.asset_file (asset_cluster,files_cluster,owner_id,base_owner,asset_id,id) 
select asset_cluster,files_cluster,owner_id,base_owner,asset_id,id from base
union
select b.asset_cluster,b.files_cluster,ls.owner_id,false,ls.id,uuid_generate_v4() from base as b
left join linked.asset as ls using(asset_cluster)
where ls.base_owner is false
on conflict (id) do nothing;

---- linked_asset_face

with base as (select la.asset_cluster,af.face_cluster,la.owner_id,la.base_owner,la.id as asset_id,af."personId" as person_id,af.id from (select *,uuid_generate_v4() as face_cluster from asset_face) as af
	inner join linked.asset as la on la.id=af."assetId"
	where la.base_owner is true)
---
insert into linked.asset_face (asset_cluster,face_cluster,owner_id,base_owner,asset_id,person_id,id) 
select asset_cluster,face_cluster,owner_id,base_owner,asset_id,person_id,id from base
union
select b.asset_cluster,b.face_cluster,ls.owner_id,false,ls.id,person_id,uuid_generate_v4() from base as b
left join linked.asset as ls using(asset_cluster)
where ls.base_owner is false
on conflict (id) do nothing;

---- create linked_person

with base as (select distinct on (p.id) la.asset_cluster,la.face_cluster,la.id as face_asset_id,la.owner_id,la.base_owner,la.asset_id,p.id from person as p
	inner join linked.asset_face as la on la.id=p."faceAssetId"
	where la.base_owner is true)
--
insert into linked.person (asset_cluster,face_cluster,face_asset_id,owner_id,base_owner,asset_id,id) 
select asset_cluster,face_cluster,face_asset_id,owner_id,base_owner,asset_id,id from base
union
select  b.asset_cluster,b.face_cluster,ls.id,ls.owner_id,false,ls.asset_id,uuid_generate_v4() from base as b
left join linked.asset_face as ls using(asset_cluster,face_cluster)
where ls.base_owner is false
on conflict (id) do nothing;

---- link face to preson

update linked.asset_face as a
set person_id = b.person_id
from (select m.id as idi, n.owner_id, n.id as person_id from linked.person as m 
    inner join linked.person as n using(asset_cluster,face_cluster)
    where m.base_owner is true and n.base_owner is false) as b
where a.person_id=b.idi and a.owner_id=b.owner_id;

---- create linked.shared_album

with base as (select distinct on (aaa."albumsId") a."albumName",a.shared_album_cluster,la.asset_cluster,la.owner_id,la.base_owner,aaa."albumsId" from album_asset as aaa
	inner join linked.asset as la on aaa."assetsId"=la.id
	left join (select *,uuid_generate_v4() as shared_album_cluster from album) as a on aaa."albumsId"=a.id
	where la.base_owner is true)
insert into linked.shared_album (album_name,shared_album_cluster,owner_id,base_owner,id) 
select "albumName",shared_album_cluster,owner_id,base_owner,"albumsId" from base
union 
select b."albumName",b.shared_album_cluster,ls.owner_id,false,uuid_generate_v4() from base as b
left join linked.asset as ls using(asset_cluster)
where ls.base_owner is false;

---- create linked.tag

with base as (select distinct on (ta."tagsId") t.tag_cluster,la.asset_cluster,la.owner_id,la.base_owner,true as parent_updated,t.value,ta."tagsId" as id from tag_asset as ta
	inner join linked.asset as la on ta."assetsId"=la.id
	left join (select *,uuid_generate_v4() as tag_cluster from tag) as t on ta."tagsId"=t.id
	where la.base_owner is true)
insert into linked.tag (tag_cluster,owner_id,base_owner,parent_updated,value,id) 
select tag_cluster,owner_id,base_owner,parent_updated,value,id from base
union
select b.tag_cluster,ls.owner_id,false,false,b.value,coalesce(t.id,uuid_generate_v4()) from base as b
left join linked.asset as ls using(asset_cluster)
left join tag as t on ls.owner_id=t."userId" and t.value=b.value
where ls.base_owner is false and not exists (select 1 from base where id=t.id);


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
----------------------------------------update real tables-----------------------------------------------
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------

---- insert asset

WITH joined AS (
	SELECT 
	n.id as new_id,
    n.owner_id,
    to_jsonb(t) AS data
  	FROM linked.asset m
  	left JOIN asset t ON t.id = m.id
  	left JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
  	where m.base_owner is true and n.base_owner is false),
patched AS (
	SELECT data || jsonb_build_object('id', to_jsonb(new_id), 
  							'ownerId', to_jsonb(owner_id)) AS new_data FROM joined)
INSERT INTO asset
SELECT (jsonb_populate_record(NULL::asset, new_data)).*
FROM patched
ON CONFLICT (id) DO NOTHING;

---- insert shared_album

WITH joined AS (
	SELECT 
    n.id as new_id,
    n.owner_id,
    to_jsonb(t) AS data
  	FROM linked.shared_album m
  	left JOIN album t ON t.id = m.id
  	left JOIN linked.shared_album n ON m.shared_album_cluster = n.shared_album_cluster
  	where m.base_owner is true and n.base_owner is false),
patched AS (
	SELECT data || jsonb_build_object('id', to_jsonb(new_id), 
  							'ownerId', to_jsonb(owner_id)) AS new_data FROM joined)
INSERT INTO album
SELECT (jsonb_populate_record(NULL::album, new_data)).*
FROM patched
ON CONFLICT (id) DO NOTHING;

---- inset shared_album_asset

INSERT INTO album_asset ("albumsId","assetsId")
select al.id,a.id from (
	select a.id as asset_id, a.asset_cluster, al.id as album_id, al.shared_album_cluster from album_asset as aaa
	inner join linked.asset as a on a.id = aaa."assetsId"
	inner join linked.shared_album as al on aaa."albumsId" = al.id) as b
left join linked.asset as a using(asset_cluster)
left join linked.shared_album as al using(shared_album_cluster,owner_id)
where a.base_owner is false;
  
---- insert tag

with link as (select m.id as base_id, n.id, n.tag_cluster,n.owner_id 
	from linked.tag as m left JOIN linked.tag as n ON m.tag_cluster = n.tag_cluster 
	where m.base_owner is true and n.base_owner is false),
joined AS (
	SELECT 
    n.id as new_id,
    n.owner_id,
    l.id as parent_id,
    to_jsonb(t) AS data
  	from link as n
  	left JOIN tag as t ON t.id = n.base_id
  	left JOIN (select base_id, id, owner_id from link) as l ON t."parentId" = l.base_id and n.owner_id=l.owner_id),
patched AS (
	SELECT data || jsonb_build_object('id', to_jsonb(new_id), 
  							'parentId', to_jsonb(parent_id),
  							'userId', to_jsonb(owner_id)) AS new_data FROM joined),
parent_updated as (update linked.tag set parent_updated = true where id in (select id from link) RETURNING 1)
INSERT INTO tag
SELECT (jsonb_populate_record(NULL::tag, new_data)).*
FROM patched
ON CONFLICT (id) DO NOTHING;

---- inset into tag asset

INSERT INTO tag_asset ("assetsId","tagsId")
select a.id,lt.id  from (
	select a.id as asset_id, a.asset_cluster, lt.id as tag_id, lt.tag_cluster from tag_asset as ta
	inner join linked.asset as a on a.id = ta."assetsId"
	inner join linked.tag as lt on ta."tagsId" = lt.id) as b
left join linked.tag as lt using(tag_cluster)
left join linked.asset as a using(asset_cluster,owner_id)
where lt.base_owner is false and a.id is not null
on conflict ("assetsId","tagsId") do nothing;

---- insert into tag_closure

INSERT INTO tag_closure (id_ancestor,id_descendant)
select id, case when "parentId" is null then id else "parentId" end from tag
on conflict (id_ancestor,id_descendant) do nothing;

---- insert asset_file

WITH joined AS (
	SELECT 
    n.id as new_id,
    n.owner_id,
    n.asset_id,
    to_jsonb(t) AS data
  	FROM (select  n.*, m.id as id_base from linked.asset_file as m 
    inner join linked.asset_file as n using(asset_cluster,files_cluster)
    where m.base_owner is true and n.base_owner is false) as n
  	left JOIN asset_file t ON t.id = n.id_base),
patched AS (
	SELECT data || jsonb_build_object('id', to_jsonb(new_id), 
  								'ownerId', to_jsonb(owner_id), 
  								'assetId', to_jsonb(asset_id)) AS new_data FROM joined)
INSERT INTO asset_file
SELECT (jsonb_populate_record(NULL::asset_file, new_data)).*
FROM patched
ON CONFLICT (id) DO NOTHING;

---- insert asset_face

WITH joined AS (
	SELECT 
    n.id as new_id,
    n.asset_id,
    to_jsonb(t) AS data
	FROM (select  n.*, m.id as idi from linked.asset_face as m 
    inner join linked.asset_face as n using(asset_cluster,face_cluster)
    where m.base_owner is true and n.base_owner is false) as n
  	left JOIN asset_face t ON t.id = n.idi),
patched AS (
	SELECT data || jsonb_build_object('id', to_jsonb(new_id), 
  								'assetId', to_jsonb(asset_id)) AS new_data FROM joined)
INSERT INTO asset_face
SELECT (jsonb_populate_record(NULL::asset_face, new_data)).*
FROM patched
ON CONFLICT (id) DO NOTHING;

---- insert person

WITH joined AS (
	SELECT 
    n.id as new_id,
    n.owner_id,
    n.face_asset_id,
    to_jsonb(t) AS data
  	FROM (select  n.*, m.id as idi from linked.person as m 
    inner join linked.person as n using(asset_cluster,face_cluster)
    where m.base_owner is true and n.base_owner is false) as n
  	left JOIN person t ON t.id = n.idi),
patched AS (
	SELECT data || jsonb_build_object('id', to_jsonb(new_id), 
  								'ownerId', to_jsonb(owner_id), 
  								'faceAssetId', to_jsonb(face_asset_id)) AS new_data FROM joined)
INSERT INTO person
SELECT (jsonb_populate_record(NULL::person, new_data)).*
FROM patched
ON CONFLICT (id) DO NOTHING;

---- update person_id in asset_face

update asset_face as a
set "personId" = b.person_id
from (select id, person_id from linked.asset_face where base_owner is false) as b
where a.id=b.id;

---- insert asset_exif

WITH joined AS (
	SELECT 
    n.id as new_id,
    to_jsonb(t) AS data
  	FROM linked.asset m
  	left JOIN asset_exif t ON t."assetId" = m.id
  	left JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
  	where m.base_owner is true and n.base_owner is false),
patched AS (
	SELECT data || jsonb_build_object('assetId', to_jsonb(new_id) ) AS new_data FROM joined)
INSERT INTO asset_exif
SELECT (jsonb_populate_record(NULL::asset_exif, new_data)).*
FROM patched
ON CONFLICT ("assetId") DO NOTHING;

---- insert smart_search

WITH joined AS (
	SELECT 
    n.id as new_id,
    to_jsonb(t) AS data
	FROM linked.asset m
	inner JOIN smart_search t ON t."assetId" = m.id
	inner JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
	where m.base_owner is true and n.base_owner is false),
patched AS (
	SELECT data || jsonb_build_object('assetId', to_jsonb(new_id) ) AS new_data FROM joined)
INSERT INTO smart_search
SELECT (jsonb_populate_record(NULL::smart_search, new_data)).*
FROM patched
ON CONFLICT ("assetId") DO NOTHING;

---- insert face_search

WITH joined AS (
  	SELECT 
    n.id as new_id,
    to_jsonb(t) AS data
	FROM linked.asset_face m
	inner JOIN face_search t ON t."faceId" = m.id
	inner JOIN linked.asset_face n ON m.face_cluster = n.face_cluster
	where m.base_owner is true and n.base_owner is false),
patched AS (
	SELECT data || jsonb_build_object('faceId', to_jsonb(new_id) ) AS new_data FROM joined)
INSERT INTO face_search
SELECT (jsonb_populate_record(NULL::face_search, new_data)).*
FROM patched
ON CONFLICT ("faceId") DO NOTHING;

---- update linked_tag_id one more time

update linked.album as a
set tag_id = t.id
from (
select t.id, b.album_cluster, b.owner_id from linked.album as b
	left join tag as t on t.value ilike b.description::text || '%%' and owner_id = t."userId") as t
where a.album_cluster = t.album_cluster and a.owner_id = t.owner_id;


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
----------------------------------------dependences------------------------------------------------------
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------


ALTER TABLE linked.asset ADD CONSTRAINT asset_asset_fk FOREIGN KEY (id) REFERENCES public.asset(id) ON DELETE CASCADE;
ALTER TABLE linked.asset_file ADD CONSTRAINT asset_file_asset_fk FOREIGN KEY (asset_id) REFERENCES linked.asset(id) ON DELETE CASCADE;
ALTER TABLE linked.asset_face ADD CONSTRAINT asset_face_asset_fk FOREIGN KEY (asset_id) REFERENCES linked.asset(id) ON DELETE CASCADE;
ALTER TABLE linked.person ADD CONSTRAINT person_asset_face_fk FOREIGN KEY (face_asset_id) REFERENCES linked.asset_face(id) ON DELETE CASCADE;
ALTER TABLE linked.shared_album ADD CONSTRAINT album_shared_album_fk FOREIGN KEY (id) REFERENCES public.album(id) ON DELETE CASCADE;
ALTER TABLE linked.tag ADD CONSTRAINT tag_tag_fk FOREIGN KEY (id) REFERENCES public.tag(id) ON DELETE CASCADE;


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
----------------------------------------indexes----------------------------------------------------------
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------


CREATE INDEX asset_file_asset_cluster_idx ON linked.asset_file (asset_cluster);
CREATE INDEX asset_file_files_cluster_idx ON linked.asset_file (files_cluster);
CREATE INDEX asset_album_cluster_idx ON linked.asset (album_cluster);
CREATE INDEX asset_asset_cluster_idx ON linked.asset USING btree (asset_cluster);
CREATE INDEX asset_face_asset_cluster_idx ON linked.asset_face (asset_cluster);
CREATE INDEX asset_face_face_cluster_idx ON linked.asset_face (face_cluster);
CREATE INDEX person_asset_cluster_idx ON linked.person (asset_cluster);
CREATE INDEX person_face_cluster_idx ON linked.person (face_cluster);
CREATE INDEX shared_album_shared_album_cluster_idx ON linked.shared_album (shared_album_cluster);
CREATE INDEX tag_tag_cluster_idx ON linked.tag (tag_cluster);


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
    a_tag_cluster UUID;
	a_asset_cluster UUID;
BEGIN
	IF EXISTS (SELECT 1 FROM linked.tag WHERE id = old."tagsId") THEN
		IF not exists (select 1 from linked.tag_helper where id=old."assetsId" and now() - interval '1 second' <= updated) THEN
			IF exists (select 1 from linked.asset where id=old."assetsId" and base_owner is true) THEN
				delete from linked.tag_helper where id=old."assetsId";
				select tag_cluster into a_tag_cluster from linked.tag where id = old."tagsId";
				select asset_cluster into a_asset_cluster from linked.asset where id = old."assetsId";
				delete from tag_asset 
				where "tagsId" in (select id from linked.tag where tag_cluster = a_tag_cluster)
				and "assetsId" in (select id from linked.asset where asset_cluster = a_asset_cluster);
				--
				IF EXISTS (SELECT 1 FROM linked.album WHERE tag_id = old."tagsId") THEN
					delete from asset
					where id in (select id from linked.asset where asset_cluster = a_asset_cluster and base_owner is false);
					delete from linked.asset
					where id in (select id from linked.asset where asset_cluster = a_asset_cluster);
				END IF;
			END IF;
		else
			delete from linked.tag_helper where id=old."assetsId";
		END IF;
	else
		delete from tag_asset where "tagsId" = old."tagsId" and "assetsId" = old."assetsId";
	END IF;	    
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_delete_asset_tag

create OR REPLACE trigger trigger_delete_asset_tag after delete
on tag_asset for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.delete_asset_tag();

---- create tag_asset helper table

CREATE OR REPLACE FUNCTION linked.tag_helper_func()
RETURNS TRIGGER AS $$
BEGIN
	if TG_OP = 'INSERT' THEN
		insert into linked.tag_helper (id, updated)
		select new."assetsId", now()
		on conflict (id) do update set updated = now();
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
		set color=new.color
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
    IF EXISTS (SELECT 1 FROM linked.shared_album WHERE id = new.id and base_owner is true) THEN
		SELECT shared_album_cluster INTO a_cluster FROM linked.shared_album WHERE id = new.id;
		update album
		set "albumName"=new."albumName",
		description=new.description,
		"order"=new."order",
		"isActivityEnabled"=new."isActivityEnabled" 
		where id in (select id from linked.shared_album WHERE shared_album_cluster = a_cluster and id != new.id);
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
	IF EXISTS (SELECT 1 FROM linked.person WHERE id = new.id and base_owner is true) THEN
		SELECT face_cluster INTO f_cluster FROM linked.person WHERE id = new.id;
		update person
		set "name"=new."name", 
		"isHidden"=new."isHidden", 
		"birthDate"=new."birthDate",
		color=new.color
		where id in (select id from linked.person where face_cluster = f_cluster and id != new.id);
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_update_linked_person

create OR REPLACE trigger trigger_update_linked_person after update
on person for each row 
WHEN (pg_trigger_depth() = 0)
execute function linked.update_linked_person();

---- create update asset metadata

CREATE OR REPLACE FUNCTION linked.update_linked_asset_exif()
 RETURNS trigger
AS $$
DECLARE
    a_cluster UUID; 
BEGIN
    IF EXISTS (SELECT 1 FROM linked.asset WHERE id = new."assetId" and base_owner is true) THEN
		SELECT asset_cluster INTO a_cluster FROM linked.asset WHERE id = new."assetId";
		---
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
		"timeZone" = NEW."timeZone"
		where "assetId" in (select id from linked.asset WHERE asset_cluster = a_cluster and "assetId" != new."assetId");
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
BEGIN
	--- with the person already seen
	IF EXISTS (SELECT 1 FROM linked.person WHERE id = new.person_id) and new.base_owner is true THEN
		--- person already in linked database
		with base as (select af.asset_cluster,af.face_cluster,af.owner_id,af.base_owner,af.asset_id,af.person_id,af.id from linked.asset_face as af
			where af.id=new.id),
		final_asset_face as (
			select asset_cluster,face_cluster,owner_id,base_owner,asset_id,person_id,id from base
			union all
			select b.asset_cluster,b.face_cluster,ls.owner_id,ls.base_owner,ls.id as asset_id,p.id as person_id,ls.id from base as b
			left join linked.asset_face as ls using(asset_cluster,face_cluster)
			left join linked.person as pp on pp.id=b.person_id
			left join linked.person as p on p.owner_id=ls.owner_id and p.face_cluster = pp.face_cluster
			where ls.id != new.id),
		update_linked_asset_face as (
			update linked.asset_face as af
			set person_id = faf.person_id
			from final_asset_face as faf
			where af.id = faf.id
			RETURNING 1)
		update asset_face as af
		set "personId" = n.person_id,
		"deletedAt" = t."deletedAt"
		FROM final_asset_face m
		inner JOIN asset_face t ON t.id = m.id
		inner JOIN final_asset_face n ON m.asset_cluster = n.asset_cluster and m.face_cluster = n.face_cluster
		where m.id = new.id and n.id = af.id;
	ELSIF EXISTS (SELECT 1 FROM linked.asset WHERE id = (select "assetId" from asset_face where id = (select "faceAssetId" from person where id = new.person_id))) THEN
		--- create person
		with base as (select af.asset_cluster,af.face_cluster,af.id as face_asset_id,af.owner_id,af.base_owner,af.asset_id,af.person_id as id from linked.asset_face as af
			where af.id=new.id),
		final_person as (
			select asset_cluster,face_cluster,face_asset_id,owner_id,base_owner,asset_id,id from base
			union all
			select b.asset_cluster,b.face_cluster,af.id,af.owner_id,af.base_owner,af.asset_id,uuid_generate_v4() from base as b
			left join linked.asset_face as af using(asset_cluster,face_cluster)
			where af.id!=new.id),
		--- insert into linked.person
		insert_linked_person as (
			insert into linked.person (asset_cluster,face_cluster,face_asset_id,owner_id,base_owner,asset_id,id) 
			select asset_cluster,face_cluster,face_asset_id,owner_id,base_owner,asset_id,id from final_person
			on conflict (id) do nothing
			RETURNING 1),
		--- insert into person;
		joined AS (
		  SELECT 
		    n.id as new_id,
		    n.owner_id,
		    n.face_asset_id,
		    to_jsonb(t) AS data
		  FROM final_person m
			inner JOIN person t ON t.id = m.id
			inner JOIN final_person n ON m.asset_cluster = n.asset_cluster and m.face_cluster = n.face_cluster
			where m.base_owner is true and n.base_owner is false),
		patched AS (
		  SELECT data || jsonb_build_object('id', to_jsonb(new_id), 
		  								'ownerId', to_jsonb(owner_id), 
		  								'faceAssetId', to_jsonb(face_asset_id)) AS new_data FROM joined),
		insert_into_person as (
			INSERT INTO person
			SELECT (jsonb_populate_record(NULL::person, new_data)).*
			FROM patched
			ON CONFLICT (id) DO NOTHING
			RETURNING 1),
		--- link face to preson
		update_face_to_person as (update linked.asset_face as a
			set person_id = fp.id
			from final_person as fp
			where a.id=fp.face_asset_id
			RETURNING 1)
		--- update person_id in asset_face
		update asset_face as a
			set "personId" = fp.id
			from final_person as fp
			where a.id=fp.face_asset_id;
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


-- create new albums
--
--CREATE OR REPLACE FUNCTION linked.link_new_album()
--RETURNS TRIGGER AS $$
--BEGIN
--	IF EXISTS (SELECT 1 FROM linked.asset WHERE id = new."assetsId" and base_owner is true) THEN
--		IF EXISTS (SELECT 1 FROM linked.shared_album WHERE id = new."albumsId" and base_owner is true) THEN
--			- insert new asset
--			INSERT INTO album_asset ("albumsId","assetsId")
--			with base as (select * from album_asset as ta
--				left join linked.asset as a on a.id = ta."assetsId"
--				left join linked.shared_album as lt on ta."albumsId" = lt.id
--				where "albumsId" = new."albumsId" and "assetsId" = new."assetsId")
--			select lt.id,a.id from base as b
--			inner join linked.asset as a using(asset_cluster)
--			inner join linked.shared_album as lt using(shared_album_cluster)
--			where a.id != "assetsId" and lt.id != new."albumsId"
--			on conflict ("albumsId","assetsId") do nothing;
--		END IF;
--	END IF;
--	RETURN NULL;
--END;
--$$ LANGUAGE plpgsql;
--
-- create trigger_link_new_album
--
--create OR REPLACE trigger trigger_link_new_album after insert
--on album_asset for each row
--WHEN (pg_trigger_depth() = 0)
--execute function linked.link_new_album();

---- create new tag
--
--CREATE OR REPLACE FUNCTION linked.link_new_tag()
--RETURNS TRIGGER AS $$
--begin
--	IF NOT EXISTS (SELECT 1 FROM linked.album WHERE tag_id = new."tagsId") THEN
--		IF EXISTS (SELECT 1 FROM linked.tag WHERE id = new."tagsId") THEN
--			IF EXISTS (SELECT 1 FROM linked.asset WHERE id = new."assetsId" and base_owner is true) THEN
--				--- insert new asset
--				INSERT INTO tag_asset ("assetsId","tagsId")
--				with base as (select * from tag_asset as ta
--					left join linked.asset as a on a.id = ta."assetsId"
--					left join linked.tag as lt on ta."tagsId" = lt.id
--					where "tagsId" = new."tagsId" and "assetsId" = new."assetsId")
--				select a.id, lt.id from base as b
--				inner join linked.asset as a using(asset_cluster)
--				inner join linked.tag as lt using(tag_cluster)
--				where a.id != new."assetsId" and lt.id != new."tagsId" 
--				on conflict ("assetsId","tagsId") do nothing;
--				IF exists (select 1 from linked.tag where id = new."tagsId" and parent_updated is false) then
--					WITH RECURSIVE parents AS (
--						SELECT id, "parentId" FROM tag WHERE id = new."tagsId" 
--						UNION ALL
--						SELECT t.id, t."parentId" FROM tag t
--						JOIN parents d ON t.id = d."parentId"
--						where t."parentId" is not null),
--					base as (SELECT ltc.id, ltpc.id as parent_id FROM parents as p
--						left join linked.tag as lt on p.id = lt.id
--						left join linked.tag as ltc on lt.tag_cluster = ltc.tag_cluster
--						left join linked.tag as ltp on p."parentId" = ltp.id
--						left join linked.tag as ltpc on ltp.tag_cluster = ltpc.tag_cluster and ltc.owner_id = ltpc.owner_id
--						where p."parentId" is not null and ltc.id is not null and not exists (select 1 from parents where ltc.id=id)),
--					insert_closure as (INSERT INTO tag_closure (id_ancestor,id_descendant)
--						select id, parent_id from base 
--						on conflict (id_ancestor,id_descendant) do nothing
--						RETURNING 1),
--					parent_updated as (update linked.tag set parent_updated = true where id in (select id from base) RETURNING 1)
--					update tag as t
--					set "parentId" = parent_id
--					from base as b
--					where t.id = b.id;
--				END IF;
--			END IF;
--		END IF;
--	END IF;
--	RETURN NULL;
--END;
--$$ LANGUAGE plpgsql;
--
------ create trigger_link_new_tag
--
--create OR REPLACE trigger trigger_link_new_tag after insert
--on tag_asset for each row
--WHEN (pg_trigger_depth() = 0)
--execute function linked.link_new_tag();

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
	        WHERE a.tag_id = new."tagsId" limit 1;
			---
			with asset_filter as (select a_album_cluster as album_cluster, a_asset_cluster as asset_cluster, a."ownerId" as owner_id, true as base_owner, a.id from asset as a where a.id=NEW."assetsId"),
			prepare_additional_faces as (select distinct p."faceAssetId", a.album_cluster, a.owner_id from asset_filter as a
				left join asset_file as af on a.id=af."assetId"
				left join asset_face as afa on afa."assetId"=a.id
				left join person as p on p.id=afa."personId"
				where afa."personId" is not null and not exists (select 1 from linked.person where id=afa."personId")),
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
			joined AS (
				SELECT n.id as new_id,
				n.owner_id,
			    to_jsonb(t) AS data
			    FROM final_table m
			    left JOIN asset t ON t.id = m.id
			    left JOIN final_table n ON m.asset_cluster = n.asset_cluster
			    where m.base_owner is true and n.base_owner is false),
			patched AS (
				SELECT data || jsonb_build_object('id', to_jsonb(new_id), 
			  							'ownerId', to_jsonb(owner_id)) AS new_data FROM joined),
			insert_asset as (INSERT INTO asset
				SELECT (jsonb_populate_record(NULL::asset, new_data)).*
				FROM patched
				ON CONFLICT (id) DO NOTHING
				RETURNING 1)
			--- insert into linked
			insert into linked.asset (album_cluster, asset_cluster, owner_id, base_owner, id) 
			select album_cluster, asset_cluster, owner_id, base_owner, id from final_table
			on conflict (id) do nothing;
			--- insert new tag_asset
			INSERT INTO tag_asset ("assetsId","tagsId")
			with base as (select * from tag_asset as ta
				left join linked.asset as a on a.id = ta."assetsId"
				left join linked.tag as lt on ta."tagsId" = lt.id
				where "tagsId" = new."tagsId" and "assetsId" = new."assetsId")
			select a.id, lt.id from base as b
			inner join linked.asset as a using(asset_cluster)
			inner join linked.tag as lt using(tag_cluster)
			where a.id != new."assetsId" and lt.id != new."tagsId"
			on conflict ("assetsId","tagsId") do nothing;
		END IF;
	END IF;
    RETURN NULL; 
END;
$$ LANGUAGE plpgsql;

---- create trigger_link_new_asset

create OR REPLACE trigger trigger_link_new_asset after insert
on public.tag_asset for each row 
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
			where ls.id != new.id),
		--- insert into main
		joined AS (
			SELECT 
			n.id as new_id,
			n.owner_id,
			n.asset_id,
			to_jsonb(t) AS data
			FROM final_asset_file m
			left JOIN asset_file t ON t.id = m.id
			left JOIN final_asset_file n ON m.asset_cluster = n.asset_cluster and m.files_cluster = n.files_cluster
			where m.asset_id = new.id and n.asset_id != new.id),
		patched AS (
			SELECT data || jsonb_build_object('id', to_jsonb(new_id), 
		  								'ownerId', to_jsonb(owner_id), 
		  								'assetId', to_jsonb(asset_id)) AS new_data
			FROM joined),
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

---- create triger_link_new_asset_file

create OR REPLACE trigger triger_link_new_asset_file after insert
on linked.asset for each row 
WHEN (pg_trigger_depth() = 1)
execute function linked.link_new_asset_file();

---- create new face to asset

CREATE OR REPLACE FUNCTION linked.insert_linked_asset_face()
 RETURNS trigger
AS $$
BEGIN
	IF new.base_owner is true THEN 
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
		joined AS (
			SELECT 
			n.id as new_id,
			n.asset_id,
			n.person_id,
			to_jsonb(t) AS data
			FROM final_asset_face m
			inner JOIN asset_face t ON t.id = m.id
			inner JOIN final_asset_face n ON m.asset_cluster = n.asset_cluster and m.face_cluster = n.face_cluster
			where m.base_owner is true and n.base_owner is false),
		patched AS (
			SELECT data || jsonb_build_object('id', to_jsonb(new_id), 
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
			RETURNING 1),
		--- face search
		joined_2 AS (
			SELECT 
			    n.id as new_id,
			    to_jsonb(t) AS data
			FROM final_asset_face m
			inner JOIN face_search t ON t."faceId" = m.id
			inner JOIN final_asset_face n ON m.asset_cluster = n.asset_cluster and m.face_cluster = n.face_cluster
			where m.base_owner is true
			),
		patched_2 AS (
			SELECT data || jsonb_build_object('faceId', to_jsonb(new_id) ) AS new_data
			FROM joined_2)
			INSERT INTO face_search
			SELECT (jsonb_populate_record(NULL::face_search, new_data)).*
			FROM patched_2
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
		WITH joined AS (
			SELECT 
		    n.id as new_id,
		    to_jsonb(t) AS data
		  	FROM linked.asset m
		  	left JOIN asset_exif t ON t."assetId" = m.id
		  	left JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
		  	where m.base_owner is true and n.base_owner is false and m.id = new.id
		),
		patched AS (
			SELECT data || jsonb_build_object('assetId', to_jsonb(new_id) ) AS new_data
		    FROM joined)
		INSERT INTO asset_exif
		SELECT (jsonb_populate_record(NULL::asset_exif, new_data)).*
		FROM patched
		ON CONFLICT ("assetId") DO NOTHING;
	END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create triger_link_new_asset_exif

create OR REPLACE trigger triger_link_new_asset_exif after insert
on linked.asset for each row 
WHEN (pg_trigger_depth() = 1)
execute function linked.link_new_asset_exif();

---- create new smart search 

CREATE OR REPLACE FUNCTION linked.link_new_smart_search()
RETURNS TRIGGER AS $$
BEGIN
    IF new.base_owner is true THEN
		WITH joined AS (
			SELECT 
		    n.id as new_id,
		    to_jsonb(t) AS data
			FROM linked.asset m
			inner JOIN smart_search t ON t."assetId" = m.id
			inner JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
			where m.base_owner is true and n.base_owner is false and m.id = new.id
		),
		patched AS (
			SELECT data || jsonb_build_object('assetId', to_jsonb(new_id) ) AS new_data
		  	FROM joined)
		INSERT INTO smart_search
		SELECT (jsonb_populate_record(NULL::smart_search, new_data)).*
		FROM patched
		ON CONFLICT ("assetId") DO NOTHING;
	END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create triger_link_new_smart_search

create OR REPLACE trigger triger_link_new_smart_search after insert
on linked.asset for each row 
WHEN (pg_trigger_depth() = 1)
execute function linked.link_new_smart_search();
