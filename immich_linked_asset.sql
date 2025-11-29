---- asserts

DO $$ DECLARE val bool; BEGIN select (value -> 'storageTemplate' -> 'enabled')::bool into val from public.system_metadata where key = 'system-config'; ASSERT val is false or val is null, 'Storage Template is not compatible'; END $$;
DO $$ DECLARE val bool; BEGIN select true into val from public.album where "albumName" = 'linked album'; ASSERT val is true, 'linked album do not exists'; END $$;
DO $$ DECLARE val bool; BEGIN select true into val from public.album where "albumName" = 'linked album' and description is not null; ASSERT val is true, 'linked album has no description'; END $$;
DO $$ DECLARE val bool; BEGIN select true into val from public.album inner join tag on album.description = tag.value where "albumName" = 'linked album'; ASSERT val is true, 'linked tag not match in linked album description or not exists'; END $$;
DO $$ DECLARE val bool; BEGIN
with base as (
	select "ownerId" as owner_id,description,id from public.album
	WHERE "albumName"::text = 'linked album'::text),
final as (select owner_id,description from base
	union
	select b."userId",a.description from base as a
	LEFT JOIN public.album_user as b ON a.id = b."albumId")
select true into val from final as b
left join public.tag as t on t.value = b.description::text and t."userId" = b.owner_id
where t.id is null;
ASSERT val is null, 'you must create a linked tag for each participant with the name mentioned in the linked album description'; END $$;

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

CREATE TABLE linked.stack (
	stack_cluster uuid NOT NULL,
	owner_id uuid NOT NULL,
	base_owner bool DEFAULT false NOT NULL,
	id uuid NOT NULL,
	CONSTRAINT linked_stack_pk PRIMARY KEY (id)
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

create table linked.tag_helper (
	asset_cluster uuid not null,
	lp_asset_cluster uuid,
	tag_cluster uuid not null,
	base_owner bool not null,
	tag_id uuid not null,
	status bool not null,
	CONSTRAINT tag_helper_pk PRIMARY KEY (asset_cluster));


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
----------------------------------------create base tables-----------------------------------------------
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------


---- create linked.album

insert into linked.album (album_cluster,owner_id,base_owner,description,id)
with base as (
	select uuid_generate_v4() as album_cluster, "ownerId" as owner_id, true as base_owner, description, id from public.album
	WHERE "albumName"::text = 'linked album'::text)
select album_cluster, owner_id, base_owner, description, id from base
union
select a.album_cluster, b."userId", false, a.description, uuid_generate_v4() from base as a
LEFT JOIN public.album_user as b ON a.id = b."albumId"
on CONFLICT (id) do nothing;

---- update linked_tag_id

update linked.album as a
set tag_id = t.id
from (select  t.id, b.album_cluster, b.owner_id from linked.album as b
	left join public.tag as t on t.value = b.description::text and t."userId" = b.owner_id) as t
where a.album_cluster = t.album_cluster and a.owner_id = t.owner_id;

---- create linked.asset

with asset_filter as (select b.album_cluster, a.asset_cluster, a."ownerId" as owner_id, true as base_owner, a.id from (select *, uuid_generate_v4() as asset_cluster from public.asset) as a
	left join linked.album as b on b.owner_id = a."ownerId"
	where exists (select 1 from public.tag_asset where "assetId" = a.id and "tagId" = b.tag_id)),
final_table as (select b.album_cluster, a.asset_cluster, b.owner_id, coalesce(aa.base_owner,false) as base_owner, coalesce(aa.id,uuid_generate_v4()) as id from asset_filter as a
	left join linked.album as b on b.album_cluster = a.album_cluster
	left join asset_filter as aa on b.owner_id = aa.owner_id and aa.asset_cluster = a.asset_cluster and a.album_cluster = aa.album_cluster)
insert into linked.asset (album_cluster,asset_cluster,owner_id,base_owner,id)
select distinct on (id) album_cluster, asset_cluster, owner_id, base_owner, id from final_table as a
on CONFLICT (id) do nothing;

---- create linked.stack

with asset_filter as (select distinct on ("stackId") b.album_cluster, b.asset_cluster as stack_cluster, b.owner_id, true as base_owner, a."stackId" as id from public.asset as a
	inner join linked.asset as b using (id)
	where "stackId" is not null),
final_table as (select a.stack_cluster, b.owner_id, coalesce(aa.base_owner,false) as base_owner, coalesce(aa.id,uuid_generate_v4()) as id from asset_filter as a
	left join linked.album as b on b.album_cluster = a.album_cluster
	left join asset_filter as aa on b.owner_id = aa.owner_id and aa.stack_cluster = a.stack_cluster and a.album_cluster = aa.album_cluster)
insert into linked.stack (stack_cluster,owner_id,base_owner,id)
select distinct on (id) stack_cluster, owner_id, base_owner, id from final_table as a
on CONFLICT (id) do nothing;

---- create linked_asset_file

with base as (select la.asset_cluster, af.files_cluster, la.owner_id, la.base_owner, la.id as asset_id, af.id from (select *,uuid_generate_v4() as files_cluster from public.asset_file) as af
	inner join linked.asset as la on af."assetId" = la.id where la.base_owner is true)
insert into linked.asset_file (asset_cluster,files_cluster,owner_id,base_owner,asset_id,id)
select asset_cluster, files_cluster, owner_id, base_owner, asset_id, id from base
union
select b.asset_cluster, b.files_cluster, ls.owner_id, false, ls.id, uuid_generate_v4() from base as b
left join linked.asset as ls using (asset_cluster)
where ls.base_owner is false
on CONFLICT (id) do nothing;

---- linked_asset_face
insert into linked.asset_face (asset_cluster,face_cluster,owner_id,base_owner,asset_id,person_id,id)
with base as (select la.asset_cluster, af.face_cluster, la.owner_id, la.base_owner, la.id as asset_id, af."personId" as person_id, af.id from (select *, uuid_generate_v4() as face_cluster from public.asset_face) as af
	inner join linked.asset as la on la.id = af."assetId" where la.base_owner is true),
person_base as (select distinct on (b.person_id,la.owner_id) b.person_id, la.owner_id, uuid_generate_v4() as person from base as b
	left join linked.asset as la using (asset_cluster)
	where b.person_id is not null)
select b.asset_cluster, b.face_cluster, ls.owner_id, false, ls.id, pb.person as person_id, uuid_generate_v4() from base as b
left join linked.asset as ls using (asset_cluster)
left join person_base as pb on b.person_id = pb.person_id and ls.owner_id = pb.owner_id
where ls.base_owner is false
union all
select asset_cluster, face_cluster, owner_id, base_owner, asset_id, person_id, id from base
on CONFLICT (id) do nothing;

---- create linked.shared_album

with base as (select distinct on (aaa."albumId") a."albumName", a.shared_album_cluster, la.asset_cluster, la.owner_id, la.base_owner, aaa."albumId" from public.album_asset as aaa
	inner join linked.asset as la on aaa."assetId" = la.id
	left join (select *, uuid_generate_v4() as shared_album_cluster from public.album) as a on aaa."albumId" = a.id
	where la.base_owner is true)
insert into linked.shared_album (album_name,shared_album_cluster,owner_id,base_owner,id)
select "albumName", shared_album_cluster, owner_id, base_owner, "albumId" from base
union
select b."albumName", b.shared_album_cluster, ls.owner_id, false, uuid_generate_v4() from base as b
left join linked.asset as ls using (asset_cluster)
where ls.base_owner is false
on CONFLICT (id) do nothing;

---- generate tags

insert into public.tag ("userId",value)
select id, name from public.user
on CONFLICT ("userId",value) do nothing;

---- insert generated tags

insert into public.tag_asset ("assetId","tagId")
select a.id, t.id from linked.asset as a
left join public.tag as t on t."userId" = a.owner_id
left join public.user as u on u.id = a.owner_id
where a.base_owner is true and u.name = t.value
on CONFLICT ("assetId","tagId") do nothing;

---- create linked.tag

with base as (select distinct on (ta."tagId") (first_value(tag_cluster) OVER (PARTITION BY t.value)) as tag_cluster, la.asset_cluster, la.owner_id, la.base_owner, true as parent_updated, t.value, ta."tagId" as id from public.tag_asset as ta
	inner join linked.asset as la on ta."assetId" = la.id
	left join (select *, uuid_generate_v4() as tag_cluster from public.tag) as t on ta."tagId" = t.id
	where la.base_owner is true)
insert into linked.tag (tag_cluster,owner_id,base_owner,parent_updated,value,id)
select tag_cluster, owner_id, base_owner, parent_updated, value, id from base
union
select b.tag_cluster, ls.owner_id, false, false, b.value, coalesce(t.id,uuid_generate_v4()) from base as b
left join linked.asset as ls using (asset_cluster)
left join public.tag as t on ls.owner_id = t."userId" and t.value = b.value
where ls.base_owner is false and not exists (select 1 from base where id = t.id)
on CONFLICT (id) do nothing;

---- insert account name in linked.tag

with base as (select uuid_generate_v4() as tag_cluster, la.album_cluster, la.owner_id, true as base_owner, true as parent_updated, t.value, t.id from public.tag as t
	left join public.user as u on u.id = t."userId"
	left join linked.album as la on u.id = la.owner_id
	where u.name = t.value and not exists (select 1 from linked.tag where id = t.id))
insert into linked.tag (tag_cluster,owner_id,base_owner,parent_updated,value,id)
select tag_cluster, owner_id, base_owner, parent_updated, value, id from base
union
select b.tag_cluster, ls.owner_id, false, false, b.value, coalesce(t.id,uuid_generate_v4()) from base as b
left join linked.album as ls using (album_cluster)
left join public.tag as t on ls.owner_id = t."userId" and t.value = b.value
where ls.base_owner is false --and not exists (select 1 from base where id = t.id)
on CONFLICT (id) do nothing;


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
----------------------------------------update real tables-----------------------------------------------
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------


---- insert asset

WITH joined AS (SELECT
	n.id as new_id,
    n.owner_id,
    lpa.id as livephoto_id,
    to_jsonb(t) AS data
  	FROM linked.asset m
  	left JOIN asset t ON t.id = m.id
  	left JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
	left join linked.asset lp on lp.id = t."livePhotoVideoId"
	left join linked.asset lpa on lp.asset_cluster = lpa.asset_cluster and lpa.owner_id = n.owner_id
  	where m.base_owner is true and n.base_owner is false),
patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
						'stackId', null, 'duplicateId', null, 'livePhotoVideoId', to_jsonb(livephoto_id),
						'ownerId', to_jsonb(owner_id)) AS new_data FROM joined)
INSERT INTO asset
SELECT (jsonb_populate_record(NULL::asset, new_data)).* FROM patched
ON CONFLICT (id) DO NOTHING;

---- insert stack

WITH joined AS (SELECT
    n.id as new_id,
    n.owner_id,
	la.id as primary_asset_id,
    to_jsonb(t) AS data
  	FROM linked.stack m
  	left JOIN public.stack t ON t.id = m.id
  	left JOIN linked.stack n ON m.stack_cluster = n.stack_cluster
	left join linked.asset as la on la.asset_cluster = n.stack_cluster and n.owner_id = la.owner_id 
  	where m.base_owner is true and n.base_owner is false),
patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
							'primaryAssetId', to_jsonb(primary_asset_id),
  							'ownerId', to_jsonb(owner_id)) AS new_data FROM joined)
INSERT INTO public.stack
SELECT (jsonb_populate_record(NULL::public.stack, new_data)).* FROM patched
on CONFLICT (id) do nothing;

---- update stack in asset

with base as (select la.asset_cluster, a."stackId" from public.asset as a 
	inner join linked.asset as la using (id) 
	where a."stackId" is not null)
update public.asset as a
set "stackId" = lss.id
from base as b
left join linked.asset as la using (asset_cluster)
inner join linked.stack as ls on b."stackId" = ls.id
inner join linked.stack as lss on ls.stack_cluster = lss.stack_cluster and la.owner_id = lss.owner_id
where la.base_owner is false and a.id = la.id;

---- insert shared_album

WITH joined AS (SELECT
    n.id as new_id,
    n.owner_id,
    to_jsonb(t) AS data
  	FROM linked.shared_album m
  	left JOIN public.album t ON t.id = m.id
  	left JOIN linked.shared_album n ON m.shared_album_cluster = n.shared_album_cluster
  	where m.base_owner is true and n.base_owner is false),
patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
  							'ownerId', to_jsonb(owner_id)) AS new_data FROM joined)
INSERT INTO public.album
SELECT (jsonb_populate_record(NULL::public.album, new_data)).* FROM patched
on CONFLICT (id) do nothing;

---- inset shared_album_asset

INSERT INTO public.album_asset ("albumId","assetId")
select al.id,a.id from (
	select a.id as asset_id, a.asset_cluster, al.id as album_id, al.shared_album_cluster from public.album_asset as aaa
	inner join linked.asset as a on a.id = aaa."assetId"
	inner join linked.shared_album as al on aaa."albumId" = al.id) as b
left join linked.asset as a using (asset_cluster)
left join linked.shared_album as al using (shared_album_cluster,owner_id)
where a.base_owner is false
on CONFLICT ("albumId","assetId") do nothing;

---- insert tag

with link as (select m.id as base_id, n.id, n.tag_cluster,n.owner_id from linked.tag as m 
	left JOIN linked.tag as n ON m.tag_cluster = n.tag_cluster
	where m.base_owner is true and n.base_owner is false),
joined AS (SELECT
    n.id as new_id,
    n.owner_id,
    l.id as parent_id,
    to_jsonb(t) AS data
  	from link as n
  	left JOIN public.tag as t ON t.id = n.base_id
  	left JOIN (select base_id, id, owner_id from link) as l ON t."parentId" = l.base_id and n.owner_id = l.owner_id),
patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
  							'parentId', to_jsonb(parent_id),
  							'userId', to_jsonb(owner_id)) AS new_data FROM joined),
parent_updated as (update linked.tag set parent_updated = true where id in (select id from link) RETURNING 1)
INSERT INTO public.tag
SELECT (jsonb_populate_record(NULL::public.tag, new_data)).* FROM patched
on CONFLICT (id) do nothing;

---- inset into tag asset

INSERT INTO public.tag_asset ("assetId","tagId")
select a.id,lt.id  from (
	select a.id as asset_id, a.asset_cluster, lt.id as tag_id, lt.tag_cluster from public.tag_asset as ta
	inner join linked.asset as a on a.id = ta."assetId"
	inner join linked.tag as lt on ta."tagId" = lt.id) as b
left join linked.tag as lt using (tag_cluster)
left join linked.asset as a using (asset_cluster,owner_id)
where a.id is not null
on CONFLICT ("assetId","tagId") do nothing;

---- insert into tag_closure

INSERT INTO public.tag_closure (id_ancestor,id_descendant)
select id, case when "parentId" is null then id else "parentId" end from public.tag
on CONFLICT (id_ancestor,id_descendant) do nothing;

---- insert asset_file

WITH joined AS (SELECT
    n.id as new_id,
    n.owner_id,
    n.asset_id,
    to_jsonb(t) AS data
  	FROM (select  n.*, m.id as id_base from linked.asset_file as m
    inner join linked.asset_file as n using (asset_cluster,files_cluster)
    where m.base_owner is true and n.base_owner is false) as n
  	left JOIN public.asset_file t ON t.id = n.id_base),
patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
  								'ownerId', to_jsonb(owner_id),
  								'assetId', to_jsonb(asset_id)) AS new_data FROM joined)
INSERT INTO public.asset_file
SELECT (jsonb_populate_record(NULL::public.asset_file, new_data)).* FROM patched
on CONFLICT (id) do nothing;

---- insert asset_face

WITH joined AS (SELECT
    n.id as new_id,
    n.asset_id,
    to_jsonb(t) AS data
	FROM (select  n.*, m.id as idi from linked.asset_face as m
    inner join linked.asset_face as n using (asset_cluster,face_cluster)
    where m.base_owner is true and n.base_owner is false) as n
  	left JOIN public.asset_face t ON t.id = n.idi),
patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
  								'assetId', to_jsonb(asset_id)) AS new_data FROM joined)
INSERT INTO public.asset_face
SELECT (jsonb_populate_record(NULL::public.asset_face, new_data)).* FROM patched
on CONFLICT (id) do nothing;

---- insert person

WITH joined AS (SELECT
    n.person_id as new_id,
    n.owner_id,
    n.id,
    n.idi,
    to_jsonb(t) AS data
  	FROM (select distinct on (n.person_id) n.*, m.person_id as idi from linked.asset_face as m
		inner join linked.asset_face as n using (asset_cluster,face_cluster)
		where m.base_owner is true and n.base_owner is false and m.person_id is not null) as n
		left JOIN public.person t ON t.id = n.idi),
patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
  								'ownerId', to_jsonb(owner_id),
  								'faceAssetId', to_jsonb(id)) AS new_data FROM joined)
INSERT INTO public.person
SELECT (jsonb_populate_record(NULL::public.person, new_data)).* FROM patched
on CONFLICT (id) do nothing;

---- update person_id in asset_face

update public.asset_face as a
set "personId" = b.person_id
from (select id, person_id from linked.asset_face where base_owner is false and person_id is not null) as b
where a.id = b.id;

---- insert asset_exif

WITH joined AS (SELECT
    n.id as new_id,
    to_jsonb(t) AS data
  	FROM linked.asset m
  	inner JOIN public.asset_exif t ON t."assetId" = m.id
  	left JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
  	where m.base_owner is true and n.base_owner is false),
patched AS (SELECT data || jsonb_build_object('assetId', to_jsonb(new_id)) AS new_data FROM joined)
INSERT INTO public.asset_exif
SELECT (jsonb_populate_record(NULL::public.asset_exif, new_data)).* FROM patched
on CONFLICT ("assetId") do nothing;

---- insert smart_search

INSERT INTO public.smart_search
SELECT n.id, t.embedding
FROM linked.asset m
inner JOIN public.smart_search t ON t."assetId" = m.id
inner JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
where m.base_owner is true and n.base_owner is false
on CONFLICT ("assetId") do nothing;

---- insert asset_ocr

WITH joined AS (SELECT
    n.id as new_id,
	uuid_generate_v4() as generated_id,
    to_jsonb(t) AS data
  	FROM linked.asset m
  	inner JOIN public.asset_ocr t ON t."assetId" = m.id
  	inner JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
  	where m.base_owner is true and n.base_owner is false),
patched AS (SELECT data || jsonb_build_object('assetId', to_jsonb(new_id), 'id', to_jsonb(generated_id)) AS new_data FROM joined)
INSERT INTO public.asset_ocr
SELECT (jsonb_populate_record(NULL::public.asset_ocr, new_data)).* FROM patched
on CONFLICT (id) do nothing;

---- insert ocr_search

INSERT INTO public.ocr_search
SELECT n.id, t."text"
FROM linked.asset m
inner JOIN public.ocr_search t ON t."assetId" = m.id
inner JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
where m.base_owner is true and n.base_owner is false
on CONFLICT ("assetId") do nothing;

---- insert face_search

INSERT INTO public.face_search
SELECT n.id, t.embedding
FROM linked.asset_face m
inner JOIN public.face_search t ON t."faceId" = m.id
inner JOIN linked.asset_face n ON m.face_cluster = n.face_cluster
where m.base_owner is true and n.base_owner is false
on CONFLICT ("faceId") do nothing;

---- update linked_tag_id one more time

update linked.album as a
set tag_id = t.id
from (select t.id, b.album_cluster, b.owner_id from linked.album as b
	left join public.tag as t on t.value = b.description::text and owner_id = t."userId") as t
where a.album_cluster = t.album_cluster and a.owner_id = t.owner_id;

---- tag main assets

INSERT INTO public.tag_asset
select a.id,al.tag_id from linked.asset as a
left join linked.album al using (album_cluster,owner_id)
where not exists (select 1 from public.tag_asset where "assetId" = a.id and al.tag_id = "tagId")
on CONFLICT ("assetId","tagId") do nothing;


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
----------------------------------------dependences------------------------------------------------------
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------


ALTER TABLE linked.asset_file ADD CONSTRAINT asset_file_asset_fk FOREIGN KEY (asset_id) REFERENCES linked.asset(id) ON DELETE CASCADE;
ALTER TABLE linked.asset_face ADD CONSTRAINT asset_face_asset_fk FOREIGN KEY (asset_id) REFERENCES linked.asset(id) ON DELETE CASCADE;
ALTER TABLE linked.shared_album ADD CONSTRAINT album_shared_album_fk FOREIGN KEY (id) REFERENCES public.album(id) ON DELETE CASCADE;
ALTER TABLE linked.tag ADD CONSTRAINT tag_tag_fk FOREIGN KEY (id) REFERENCES public.tag(id) ON DELETE CASCADE;
ALTER TABLE linked.stack ADD CONSTRAINT stack_stack_fk FOREIGN KEY (id) REFERENCES public.stack(id) ON DELETE CASCADE;


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
----------------------------------------indexes----------------------------------------------------------
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------


CREATE INDEX asset_file_asset_cluster_file_fluster_idx ON linked.asset_file (asset_cluster,files_cluster);
CREATE INDEX asset_asset_cluster_idx ON linked.asset (asset_cluster);
CREATE INDEX asset_asset_cluster_owner_id_idx ON linked.asset (asset_cluster,owner_id);
CREATE INDEX stack_stack_cluster_owner_id_idx ON linked.stack (stack_cluster,owner_id);
CREATE INDEX asset_face_asset_cluster_face_cluster_idx ON linked.asset_face (asset_cluster,face_cluster);
CREATE INDEX asset_face_face_cluster_person_idx ON linked.asset_face (face_cluster,person_id);
CREATE INDEX asset_face_owner_id_face_cluster_idx ON linked.asset_face (owner_id,face_cluster);
CREATE INDEX asset_face_person_idx ON linked.asset_face (person_id);
CREATE INDEX shared_album_shared_album_cluster_idx ON linked.shared_album (shared_album_cluster);
CREATE INDEX shared_album_shared_album_cluster_owner_id_idx ON linked.shared_album (shared_album_cluster,owner_id);
CREATE INDEX tag_tag_cluster_idx ON linked.tag (tag_cluster);
CREATE INDEX tag_tag_cluster_owner_id_idx ON linked.tag (tag_cluster,owner_id);
CREATE INDEX tag_owner_id_idx ON linked.tag (owner_id);
CREATE INDEX tag_owner_id_value_idx ON linked.tag (owner_id,value);
CREATE INDEX album_tag_id_idx ON linked.album (tag_id);
CREATE INDEX album_album_cluster_idx ON linked.album (album_cluster);
CREATE INDEX album_album_cluster_owner_id_idx ON linked.album (album_cluster,owner_id);
CREATE INDEX album_owner_id_idx ON linked.album (owner_id);
CREATE INDEX tag_helper_asset_cluster_idx ON linked.tag_helper (asset_cluster,tag_cluster);


---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------
----------------------------------------delete triggers--------------------------------------------------
---------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------


---- delete asset recursive

CREATE OR REPLACE FUNCTION linked.delete_linked_asset()
RETURNS TRIGGER AS $$
DECLARE
    a_cluster UUID[];
BEGIN
    IF EXISTS (SELECT 1 FROM linked.asset WHERE id = old.id and base_owner is true) THEN
		SELECT array_agg(asset_cluster) INTO a_cluster FROM linked.asset WHERE id in (old.id, old."livePhotoVideoId");
		delete from public.asset
		where id in (select id from linked.asset where asset_cluster = ANY(a_cluster));
		delete from linked.asset where asset_cluster = ANY(a_cluster);
	END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- trigger for delete_asset_recursive

create OR REPLACE trigger trigger_delete_linked_asset after delete
on public.asset for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.delete_linked_asset();

-- delete asset from album

CREATE OR REPLACE FUNCTION linked.delete_from_album()
RETURNS TRIGGER AS $$
DECLARE
    a_asset_cluster UUID;
	a_album_cluster UUID;
BEGIN
	IF EXISTS (SELECT 1 FROM linked.asset WHERE id = old."assetId" and base_owner is true) THEN
		select asset_cluster into a_asset_cluster from linked.asset where id = old."assetId";
		select shared_album_cluster into a_album_cluster from linked.shared_album where id = old."albumId";
		delete from public.album_asset
		where "assetId" in (select id from linked.asset where asset_cluster = a_asset_cluster)
		and "albumId" in (select id from linked.shared_album where shared_album_cluster = a_album_cluster);
	else
		delete from public.album_asset where "albumId" = old."albumId" and "assetId" = old."assetId";
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger for shared album asset

create OR REPLACE trigger trigger_delete_from_album before delete
on public.album_asset for each row
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
		delete from public.tag
		where id in (select id from linked.tag where tag_cluster = t_cluster);
	ELSIF EXISTS (select 1 from linked.album where tag_id = old.id) THEN
		RETURN NULL;
	else
		delete from public.tag where id = old.id;
	END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- trigger for delete_tag_recursive

create OR REPLACE trigger trigger_delete_linked_tag before delete
on public.tag for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.delete_linked_tag();

---- delete asset tag

CREATE OR REPLACE FUNCTION linked.delete_asset_tag()
RETURNS TRIGGER AS $$
BEGIN
	IF new.status = true THEN
		IF exists (select 1 from linked.album as a where a.tag_id = new.tag_id) THEN
			IF new.base_owner is true THEN
				delete from public.asset
				where id in (select id from linked.asset where asset_cluster in (new.asset_cluster,new.lp_asset_cluster) and base_owner is false);
				delete from linked.asset
				where id in (select id from linked.asset where asset_cluster in (new.asset_cluster,new.lp_asset_cluster));
				delete from linked.tag_helper where asset_cluster = new.asset_cluster and tag_cluster = new.tag_cluster;
			END IF;
			RETURN NULL;
		END IF;
		delete from public.tag_asset
		where "tagId" in (select id from linked.tag where tag_cluster = new.tag_cluster)
		and "assetId" in (select id from linked.asset where asset_cluster = new.asset_cluster);
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
DECLARE
	a_asset_cluster UUID;
	lp_asset_cluster UUID;
	a_tag_cluster UUID;
	a_base_owner bool;
BEGIN
	IF TG_OP = 'INSERT' THEN
		delete from linked.tag_helper where asset_cluster = (select asset_cluster from linked.asset where id = new."assetId");
		RETURN NULL;
	END IF;
	IF EXISTS (SELECT 1 FROM linked.tag WHERE id = old."tagId") THEN
		select base_owner into a_base_owner from linked.asset where id = old."assetId";
		IF a_base_owner is not null THEN
			select tag_cluster into a_tag_cluster from linked.tag where id = old."tagId";
			select asset_cluster into a_asset_cluster from linked.asset where id = old."assetId";
			select asset_cluster into lp_asset_cluster from linked.asset where id = (select "livePhotoVideoId" from public.asset where id = old."assetId");
			IF exists (select 1 from linked.tag_helper where asset_cluster = a_asset_cluster) THEN
				update linked.tag_helper as th
				set status = true
				where th.status is false and th.asset_cluster = a_asset_cluster and th.tag_cluster = a_tag_cluster;
			ELSE
				insert into linked.tag_helper (asset_cluster, lp_asset_cluster, tag_cluster, base_owner, tag_id, status)
				select a_asset_cluster, lp_asset_cluster, a_tag_cluster, a_base_owner, old."tagId", false;
				update linked.tag_helper as th
				set status = true
				where th.status is false and th.asset_cluster = a_asset_cluster and th.tag_cluster = a_tag_cluster;
			END IF;
		END IF;
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_tag_helper_func

create OR REPLACE trigger trigger_tag_helper_func after insert or delete
on public.tag_asset for each row
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
		delete from public.album
		where id in (select id from linked.shared_album where shared_album_cluster = a_cluster);
	else
		delete from public.album where id = old.id;
	END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- trigger for delete shared album recursive

create OR REPLACE trigger trigger_delete_shared_album before delete
on public.album for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.delete_shared_album();

---- delete linked stack

CREATE OR REPLACE FUNCTION linked.delete_linked_stack()
RETURNS TRIGGER AS $$
DECLARE
    s_cluster UUID;
BEGIN
    IF EXISTS (SELECT 1 FROM linked.stack WHERE id = old.id and base_owner is true) THEN
		SELECT stack_cluster INTO s_cluster FROM linked.stack WHERE id = old.id;
		delete from public.stack
		where id in (select id from linked.stack where stack_cluster = s_cluster);
	else
		delete from public.stack where id = old.id;
	END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- trigger for delete linked stack

create OR REPLACE trigger trigger_delete_linked_stack before delete
on public.stack for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.delete_linked_stack();


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
		update public.tag
		set color = new.color
		where id in (select id from linked.tag WHERE tag_cluster = t_cluster and id != new.id);
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- trigger for update tag recursive

create OR REPLACE trigger trigger_update_linked_tag after update
on public.tag for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.update_linked_tag();

---- create update stack primary asset

CREATE OR REPLACE FUNCTION linked.update_stack_primary_asset()
RETURNS trigger
AS $$
DECLARE
    s_cluster UUID;
	a_cluster UUID;
BEGIN
    IF EXISTS (SELECT 1 FROM linked.stack WHERE id = new.id and base_owner is true) THEN
		SELECT asset_cluster INTO a_cluster FROM linked.asset WHERE id = new."primaryAssetId";
		IF a_cluster is not null then
			SELECT stack_cluster INTO s_cluster FROM linked.stack WHERE id = new.id;
			update public.stack as s
			set "primaryAssetId" = a.id
			from linked.asset as a
			where a.asset_cluster = a_cluster and a.owner_id = s."ownerId"
			and s.id in (select id from linked.stack WHERE stack_cluster = s_cluster and id != new.id);
		END IF;
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- trigger for update tag recursive

create OR REPLACE trigger trigger_update_stack_primary_asset after update
on public.stack for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.update_stack_primary_asset();

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
			with base as (select a."albumName" as album_name, uuid_generate_v4() as shared_album_cluster, la.album_cluster, a."ownerId" as owner_id, true as base_owner, a.id from public.album as a
				left join linked.album as la on a."ownerId" = la.owner_id
				where a.id = new.id),
			final_album as (
				select album_name, shared_album_cluster, owner_id, base_owner, id from base
				union all
				select b.album_name, b.shared_album_cluster, ls.owner_id, false, uuid_generate_v4() from base as b
				left join linked.album as ls using (album_cluster)
				where ls.owner_id != b.owner_id),
			--- into album
			joined AS (SELECT 
				n.id as new_id,
				n.owner_id,
				to_jsonb(t) AS data
				FROM final_album as m
				left JOIN public.album as t ON t.id = m.id
				inner JOIN final_album as n ON m.shared_album_cluster = n.shared_album_cluster
				where m.id = new.id and n.id != new.id),
			patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id), 
										'description', to_jsonb(''::text),
										'ownerId', to_jsonb(owner_id)) AS new_data FROM joined),
			insert_album as (
				INSERT INTO public.album
				SELECT (jsonb_populate_record(NULL::public.album, new_data)).*
				FROM patched
				ON CONFLICT (id) DO NOTHING
				RETURNING 1)
			--- into linked.shared_album
			insert into linked.shared_album (album_name,shared_album_cluster,owner_id,base_owner,id)
			select album_name, shared_album_cluster, owner_id, base_owner, id from final_album
			on conflict (id) do nothing;
			INSERT INTO public.album_asset ("albumId","assetId")
			with base as (select a.id, a.asset_cluster, sa.shared_album_cluster from public.album_asset as ta
				left join linked.asset as a on a.id = ta."assetId"
				left join linked.shared_album as sa on sa.id = ta."albumId"
				where ta."albumId" = new.id)
			select lt.id, a.id from base as b
			inner join linked.asset as a using (asset_cluster)
			inner join linked.shared_album as lt using (shared_album_cluster,owner_id)
			where lt.id != new.id 
			on conflict ("albumId","assetId") do nothing;
			update public.album set description = '' where id = new.id;
		END IF;
	ELSIF EXISTS (SELECT 1 FROM linked.shared_album WHERE id = new.id and base_owner is true) THEN
		IF new.description = 'delete linked album' THEN
			--- delete linked album
			SELECT shared_album_cluster INTO a_cluster FROM linked.shared_album WHERE id = new.id;
			delete from public.album
			where id in (select id from linked.shared_album where shared_album_cluster = a_cluster and id != new.id);
			delete from linked.shared_album where id = new.id;
			update public.album set description = '' where id = new.id;
	    ELSE
			SELECT shared_album_cluster INTO a_cluster FROM linked.shared_album WHERE id = new.id;
			update public.album
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
on public.album for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.update_linked_album();

---- create update asset

CREATE OR REPLACE FUNCTION linked.update_linked_asset()
RETURNS trigger
AS $$
DECLARE
    a_cluster UUID;
	s_cluster UUID;
BEGIN
    IF EXISTS (SELECT 1 FROM linked.asset WHERE id = new.id and base_owner is true) THEN
		IF new.visibility = 'locked' THEN
			SELECT asset_cluster INTO a_cluster FROM linked.asset WHERE id = new.id;
			delete from public.asset
			where id in (select id from linked.asset where asset_cluster = a_cluster and id != new.id);
		ELSIF new.status = 'trashed' THEN
			SELECT asset_cluster INTO a_cluster FROM linked.asset WHERE id = new.id;
			update public.asset as a
			set visibility = 'archive', status = 'active', "deletedAt" = null
			where id in (select id from linked.asset where asset_cluster = a_cluster and id != new.id);
		ELSIF old.status = 'trashed' and new.status = 'active' THEN
			SELECT asset_cluster INTO a_cluster FROM linked.asset WHERE id = new.id;
			update public.asset as a
			set visibility = 'timeline', status = 'active', "deletedAt" = null
			where id in (select id from linked.asset where asset_cluster = a_cluster and id != new.id);
		ELSE
			SELECT asset_cluster INTO a_cluster FROM linked.asset WHERE id = new.id;
			IF new."stackId" is not null THEN
				SELECT stack_cluster INTO s_cluster FROM linked.stack WHERE id = new."stackId";
			END IF;
			IF old."stackId" is null and new."stackId" is not null and s_cluster is null THEN
				with base as (select coalesce(a.asset_cluster,b.asset_cluster) as asset_cluster from public.stack as s
					left join linked.asset as a on a.id = s."primaryAssetId"
					left join linked.asset as b on b.id = new.id
					where s.id = new."stackId"),
				final_table as (select a.asset_cluster as stack_cluster, a.id as asset_id, a.owner_id, a.base_owner, coalesce(s.id,uuid_generate_v4()) as id from linked.album as la
					left join public.stack as s on la.owner_id = s."ownerId" and s.id = new."stackId"
					left join linked.asset as a on a.asset_cluster = (select asset_cluster from base) and a.owner_id = la.owner_id),
				insert_stack as (INSERT INTO public.stack (id, "primaryAssetId", "ownerId")
					select id,asset_id,owner_id from final_table where base_owner is false
					ON CONFLICT (id) DO NOTHING
					RETURNING 1)
				insert into linked.stack (stack_cluster,owner_id,base_owner,id)
				select stack_cluster, owner_id, base_owner, id from final_table
				ON CONFLICT (id) DO NOTHING;
				SELECT stack_cluster INTO s_cluster FROM linked.stack WHERE id = new."stackId";
			END IF;
			update public.asset as a
			set "fileModifiedAt" = NEW."fileModifiedAt",
			"createdAt" = NEW."createdAt",
			"isOffline" = NEW."isOffline",
			"localDateTime" = NEW."localDateTime",
			"stackId" = (CASE WHEN s_cluster IS NULL THEN NULL ELSE ls.id end)
			from linked.stack as ls
			where (s_cluster IS NULL OR (ls.stack_cluster = s_cluster and ls.owner_id = a."ownerId"))
 				and a.id in (select id from linked.asset WHERE asset_cluster = a_cluster and id != new.id);
		END IF;
	ELSIF EXISTS (SELECT 1 FROM linked.asset WHERE id = new.id and base_owner is false and new.status = 'trashed') THEN
		update public.asset as a
		set visibility = 'archive', status = 'active', "deletedAt" = null
		where id = new.id;
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- trigger for update asset

create OR REPLACE trigger trigger_update_linked_asset after update
on public.asset for each row
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
		update public.person
		set "name" = new."name",
		"isHidden" = new."isHidden",
		"birthDate" = new."birthDate",
		color = new.color
		where id in (select person_id from linked.asset_face where face_cluster = f_cluster and person_id != new.id);
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_update_linked_person

create OR REPLACE trigger trigger_update_linked_person after update
on public.person for each row
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
on public.asset_face for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.sync_asset_face();

---- create update asset metadata

CREATE OR REPLACE FUNCTION linked.update_linked_asset_exif()
RETURNS trigger
AS $$
DECLARE
    a_cluster UUID;
BEGIN
    IF EXISTS (SELECT 1 FROM linked.asset WHERE id = new."assetId") THEN
		SELECT asset_cluster INTO a_cluster FROM linked.asset WHERE id = new."assetId";
		update public.asset_exif
		set orientation = NEW.orientation,
		"dateTimeOriginal" = new."dateTimeOriginal",
		"modifyDate" = NEW."modifyDate",
		latitude = NEW.latitude,
		longitude = NEW.longitude,
		city = NEW.city,
		state = NEW.state,
		country = NEW.country,
		description = NEW.description,
		"timeZone" = NEW."timeZone",
		rating = NEW.rating
		where "assetId" in (select id from linked.asset WHERE asset_cluster = a_cluster and id != new."assetId");
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_update_linked_asset_exif

create OR REPLACE trigger trigger_update_linked_asset_exif after update
on public.asset_exif for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.update_linked_asset_exif();

---- create update/create person

CREATE OR REPLACE FUNCTION linked.insert_linked_person()
RETURNS trigger
AS $$
DECLARE
    a_face_cluster UUID;
BEGIN
	if new.base_owner is true and new.person_id is not null THEN
		--- person already in linked database
		select face_cluster into a_face_cluster from linked.asset_face where face_cluster != new.face_cluster and person_id = new.person_id limit 1;
		IF a_face_cluster is not null THEN
			--- with the person already seen
			with base as (select af.asset_cluster, af.face_cluster, af.owner_id, af.base_owner, af.asset_id, af.person_id, af.id from linked.asset_face as af
				where af.id = new.id),
			final_asset_face as (
				select asset_cluster, face_cluster, owner_id, base_owner, asset_id, person_id, id from base
				union all
				select b.asset_cluster, b.face_cluster, ls.owner_id, ls.base_owner, ls.id as asset_id, lsl.person_id as person_id, ls.id from base as b
				left join linked.asset_face as ls using (asset_cluster,face_cluster)
				left join linked.asset_face as lsl on lsl.owner_id = ls.owner_id and lsl.face_cluster = a_face_cluster
				where ls.base_owner is false),
			update_asset_face as (
				update public.asset_face as af
				set "personId" = n.person_id,
				"deletedAt" = t."deletedAt"
				FROM final_asset_face m
				inner JOIN public.asset_face t ON t.id = m.id
				inner JOIN final_asset_face n ON m.asset_cluster = n.asset_cluster and m.face_cluster = n.face_cluster
				where m.base_owner is true and n.base_owner is false and n.id = af.id
				RETURNING 1)
			update linked.asset_face as af
			set person_id = faf.person_id
			from final_asset_face as faf
			where af.id = faf.id;
		ELSE
			--- create person
			with base as (select af.asset_cluster, af.face_cluster, af.id as face_asset_id, af.owner_id, af.base_owner, af.asset_id, af.person_id as id from linked.asset_face as af
				where af.id = new.id),
			final_person as (
				select asset_cluster, face_cluster, face_asset_id, owner_id, base_owner, asset_id, id from base
				union all
				select b.asset_cluster, b.face_cluster, af.id, af.owner_id, af.base_owner, af.asset_id, uuid_generate_v4() from base as b
				left join linked.asset_face as af using (asset_cluster,face_cluster)
				where af.base_owner is false),
			--- insert into person;
			joined AS (SELECT
			    n.id as new_id,
			    n.owner_id,
			    coalesce(n.face_asset_id,n.id) as face_asset_id,
			    to_jsonb(t) AS data
			  FROM final_person m
				inner JOIN public.person t ON t.id = m.id
				inner JOIN final_person n ON m.asset_cluster = n.asset_cluster and m.face_cluster = n.face_cluster
				where m.base_owner is true and n.base_owner is false),
			patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
			  								'ownerId', to_jsonb(owner_id),
			  								'faceAssetId', to_jsonb(face_asset_id)) AS new_data FROM joined),
			insert_into_person as (
				INSERT INTO public.person
				SELECT (jsonb_populate_record(NULL::public.person, new_data)).* FROM patched
				ON CONFLICT (id) DO NOTHING
				RETURNING 1),
			--- link face to preson
			update_face_to_person as (update linked.asset_face as a
				set person_id = fp.id
				from final_person as fp
				where a.id = fp.face_asset_id
				RETURNING 1)
			--- update person_id in asset_face
			update public.asset_face as a
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
	IF EXISTS (SELECT 1 FROM linked.shared_album WHERE id = new."albumId") THEN
		IF EXISTS (SELECT 1 FROM linked.asset WHERE id = new."assetId") THEN
			--- insert new asset
			INSERT INTO public.album_asset ("albumId","assetId")
			with base as (select ta."assetId", a.asset_cluster, lt.shared_album_cluster from public.album_asset as ta
				left join linked.asset as a on a.id = ta."assetId"
				left join linked.shared_album as lt on ta."albumId" = lt.id
				where "albumId" = new."albumId" and "assetId" = new."assetId")
			select lt.id, a.id from base as b
			inner join linked.asset as a using (asset_cluster)
			inner join linked.shared_album as lt using (shared_album_cluster,owner_id)
			where a.id != "assetId" and lt.id != new."albumId"
			on conflict ("albumId","assetId") do nothing;
		END IF;	
	END IF;
	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_link_new_album

create OR REPLACE trigger trigger_link_new_album after insert
on public.album_asset for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.link_new_album();

---- create new tag

CREATE OR REPLACE FUNCTION linked.link_new_tag()
RETURNS TRIGGER AS $$
BEGIN
	IF NOT EXISTS (SELECT 1 FROM linked.album WHERE tag_id = new."tagId") THEN
		IF EXISTS (SELECT 1 FROM linked.asset WHERE id = new."assetId") THEN
			IF NOT EXISTS (SELECT 1 FROM linked.tag WHERE id = new."tagId") THEN
				--- new linked tag
				with base as (select uuid_generate_v4() as tag_cluster, la.asset_cluster, la.owner_id, la.base_owner, false as parent_updated, t.value, ta."tagId" as id from public.tag_asset as ta
					left join linked.asset as la on ta."assetId" = la.id
					left join public.tag as t on ta."tagId" = t.id
					where ta."tagId" = new."tagId" and ta."assetId" = new."assetId"),
				final_tag as (
					select tag_cluster, owner_id, base_owner, parent_updated, value, id from base
					union all
					select b.tag_cluster, ls.owner_id, (case when t.id is not null then true else false end), false, b.value, coalesce(t.id,uuid_generate_v4()) from base as b
					left join linked.asset as ls using (asset_cluster)
					left join public.tag as t on b.value = t.value and ls.owner_id = t."userId"
					where ls.owner_id != b.owner_id),
				joined AS (SELECT
				    n.id as new_id,
				    n.owner_id,
				    null as parent_id,
				    to_jsonb(t) AS data
					FROM final_tag as m
				  	left JOIN public.tag as t ON t.id = m.id
				  	inner JOIN final_tag as n ON m.tag_cluster = n.tag_cluster
					where m.id = new."tagId" and n.id != new."tagId"),
				patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
				  							'parentId', to_jsonb(parent_id),
				  							'userId', to_jsonb(owner_id)) AS new_data FROM joined),
				insert_tag as (
					INSERT INTO public.tag
					SELECT (jsonb_populate_record(NULL::public.tag, new_data)).* FROM patched
					ON CONFLICT (id) DO NOTHING
					RETURNING 1),
				--- into linked.tag
				insert_linked_tag as (
					insert into linked.tag (tag_cluster,owner_id,base_owner,parent_updated,value,id)
					select tag_cluster, owner_id, base_owner, parent_updated, value, id from final_tag
					on conflict (id) do nothing
					RETURNING 1)
				--- insert into tag_closure
				INSERT INTO public.tag_closure (id_ancestor,id_descendant)
				select id, id from final_tag
				on conflict (id_ancestor,id_descendant) do nothing;
			END IF;
			--- insert new asset
			INSERT INTO public.tag_asset ("assetId","tagId")
			with base as (select a.asset_cluster, lt.tag_cluster from public.tag_asset as ta
				left join linked.asset as a on a.id = ta."assetId"
				left join linked.tag as lt on ta."tagId" = lt.id
				where "tagId" = new."tagId" and "assetId" = new."assetId")
			select a.id, lt.id from base as b
			inner join linked.asset as a using (asset_cluster)
			inner join linked.tag as lt on lt.tag_cluster = b.tag_cluster and a.owner_id = lt.owner_id
			where a.id != new."assetId" and lt.id != new."tagId"
			on conflict ("assetId","tagId") do nothing;
			IF exists (select 1 from linked.tag where id = new."tagId" and parent_updated is false) then
				WITH RECURSIVE parents AS (
					SELECT id, "parentId" FROM public.tag WHERE id = new."tagId"
					UNION ALL
					SELECT t.id, t."parentId" FROM public.tag t
					JOIN parents d ON t.id = d."parentId"
					where t."parentId" is not null),
				base as (SELECT ltc.id, ltpc.id as parent_id FROM parents as p
					left join linked.tag as lt on p.id = lt.id
					left join linked.tag as ltc on lt.tag_cluster = ltc.tag_cluster
					left join linked.tag as ltp on p."parentId" = ltp.id
					left join linked.tag as ltpc on ltp.tag_cluster = ltpc.tag_cluster and ltc.owner_id = ltpc.owner_id
					where p."parentId" is not null and ltc.id is not null and not exists (select 1 from parents where ltc.id = id)),
				insert_closure as (INSERT INTO public.tag_closure (id_ancestor,id_descendant)
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
on public.tag_asset for each row
WHEN (pg_trigger_depth() = 0)
execute function linked.link_new_tag();

---- create new asset

CREATE OR REPLACE FUNCTION linked.link_new_asset()
RETURNS TRIGGER AS $$
DECLARE
    a_asset_cluster uuid;
	a_album_cluster uuid;
	a_stack_cluster uuid;
	a_livephoto_id uuid;
BEGIN
    IF EXISTS (SELECT 1 FROM linked.album WHERE tag_id = new."tagId") THEN
		IF NOT EXISTS (SELECT 1 FROM linked.asset WHERE id = new."assetId") THEN
		--- if asset should be linked
			SELECT a.album_cluster
	        INTO a_album_cluster
	        FROM linked.album a
	        WHERE a.tag_id = new."tagId";
			select ls.stack_cluster into a_stack_cluster from public.asset as a
			inner join linked.stack as ls on ls.id = a."stackId"
			where a.id = new."assetId";
			select "livePhotoVideoId" into a_livephoto_id from public.asset as a where a.id = new."assetId";
			---
			with asset_filter as (select a_album_cluster as album_cluster, uuid_generate_v4() as asset_cluster, a."ownerId" as owner_id, true as base_owner, "stackId", a.id, (case when id = a_livephoto_id then true else false end) as livephoto from public.asset as a where a.id in (NEW."assetId", a_livephoto_id)),
			final_table as (select b.album_cluster, a.asset_cluster, b.owner_id, coalesce(aa.base_owner,false) as base_owner, (case when a."stackId" is null then null else coalesce(aa."stackId",ls.id,uuid_generate_v4()) end) as stack_id, coalesce(aa.id,uuid_generate_v4()) as id, a.livephoto from asset_filter as a
				left join linked.album as b on b.album_cluster = a.album_cluster
				left join linked.stack as ls on ls.stack_cluster = a_stack_cluster and ls.owner_id = b.owner_id
				left join asset_filter as aa on b.owner_id = aa.owner_id and aa.asset_cluster = a.asset_cluster),
			joined AS (SELECT 
				n.id as new_id,
				n.owner_id,
				lp.id as livephoto_id,
			    to_jsonb(t) AS data
			    FROM final_table m
			    left JOIN public.asset t ON t.id = m.id
			    left JOIN final_table n ON m.asset_cluster = n.asset_cluster
				left join final_table lp on lp.owner_id = n.owner_id and lp.livephoto is true and n.livephoto is false
			    where m.base_owner is true and n.base_owner is false),
			patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
			  							'stackId', null,
										'livePhotoVideoId', to_jsonb(livephoto_id),
										'duplicateId', null,
			  							'ownerId', to_jsonb(owner_id)) AS new_data FROM joined),
			insert_asset as (INSERT INTO public.asset
				SELECT (jsonb_populate_record(NULL::public.asset, new_data)).* FROM patched
				ON CONFLICT (id) DO NOTHING
				RETURNING 1),
			--- insert into linked
			insert_linked_asset as (insert into linked.asset (album_cluster,asset_cluster,owner_id,base_owner,id)
				select album_cluster, asset_cluster, owner_id, base_owner, id from final_table
				on conflict (id) do nothing
				RETURNING 1),
			insert_stack as (insert into public.stack (id,"primaryAssetId","ownerId")
				with aaa as (select la.asset_cluster from final_table as ft
					inner join public.stack as s on ft.stack_id = s.id
					inner join linked.asset as la on s."primaryAssetId" = la.id
					where ft.base_owner is true)
				select ft.stack_id, coalesce(a.id,ft.id), ft.owner_id from final_table as ft
				left join linked.asset as a on a.asset_cluster = (select asset_cluster from aaa) and ft.owner_id = a.owner_id
				where ft.base_owner is false and ft.stack_id is not null
				on conflict (id) do nothing
				RETURNING 1),
			insert_linked_stack as (insert into linked.stack (stack_cluster,owner_id,base_owner,id)
				select asset_cluster, owner_id, base_owner, stack_id from final_table
				where stack_id is not null
				on conflict (id) do nothing
				RETURNING 1),
			update_stack_asset as (update public.asset as a 
				set "stackId" = ft.stack_id
				from final_table as ft
				where a.id = ft.id and ft.base_owner is false
				RETURNING 1)
			--- insert new tag_asset
			INSERT INTO public.tag_asset ("assetId","tagId")
			with base as (select lt.tag_cluster from final_table as ft
				left join public.user as u on ft.owner_id = u.id
				left join linked.tag as lt on ft.owner_id = lt.owner_id and u.name = lt.value
				where ft.base_owner is true )
			select ft.id, t.id from final_table as ft
			left join linked.tag as t on t.tag_cluster in (select tag_cluster from base) and ft.owner_id = t.owner_id
			where t.id is not null
			union all
			select ft.id,al.tag_id from final_table as ft
			left join linked.album al using (album_cluster,owner_id)
			on conflict ("assetId","tagId") do nothing;
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
		with base as (select la.asset_cluster, uuid_generate_v4() as files_cluster, la.owner_id, la.base_owner, la.id as asset_id, af.id from public.asset_file as af
			inner join linked.asset as la on af."assetId" = la.id
			where af."assetId" = new.id),
		final_asset_file as (
			select asset_cluster, files_cluster, owner_id, base_owner, asset_id, id from base
			union all
			select b.asset_cluster, b.files_cluster, ls.owner_id, false, ls.id, uuid_generate_v4() from base as b
			left join linked.asset as ls using (asset_cluster)
			where ls.base_owner is false),
		--- insert into main
		joined AS (SELECT
			n.id as new_id,
			n.owner_id,
			n.asset_id,
			to_jsonb(t) AS data
			FROM final_asset_file m
			left JOIN public.asset_file t ON t.id = m.id
			left JOIN final_asset_file n ON m.asset_cluster = n.asset_cluster and m.files_cluster = n.files_cluster
			where m.base_owner is true and n.base_owner is false),
		patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
		  								'ownerId', to_jsonb(owner_id),
		  								'assetId', to_jsonb(asset_id)) AS new_data FROM joined),
		insert_asset_file as (
			INSERT INTO public.asset_file
			SELECT (jsonb_populate_record(NULL::public.asset_file, new_data)).*
			FROM patched
			ON CONFLICT (id) DO NOTHING
			RETURNING 1)
		--- insert into linked.asset_file
		insert into linked.asset_file (asset_cluster,files_cluster,owner_id,base_owner,asset_id,id)
		select asset_cluster, files_cluster, owner_id, base_owner, asset_id, id from final_asset_file
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
	IF exists (select 1 from public.asset_face where "assetId" = new.id) and new.base_owner is true THEN
		with base as (select la.asset_cluster, uuid_generate_v4() as face_cluster, la.owner_id, la.base_owner, la.id as asset_id, af."personId" as person_id, af.id
			from linked.asset as la
			left join public.asset_face as af on la.id = af."assetId"
			where la.id = new.id),
		final_asset_face as (
			select asset_cluster, face_cluster, owner_id, base_owner, asset_id, person_id, id from base
			union all
			select b.asset_cluster, b.face_cluster, ls.owner_id, ls.base_owner, ls.id as asset_id, null as person_id, uuid_generate_v4() as id from base as b
			left join linked.asset as ls using (asset_cluster)
			where ls.base_owner is false),
		--- insert to linked.asset_face
		insert_linked_asset_face as (
			insert into linked.asset_face (asset_cluster,face_cluster,owner_id,base_owner,asset_id,person_id,id)
			select asset_cluster, face_cluster, owner_id, base_owner, asset_id, person_id, id from final_asset_face
			on conflict (id) do nothing
			RETURNING 1),
		--- insert new rows to asset_face
		joined AS (SELECT
			n.id as new_id,
			n.asset_id,
			n.person_id,
			to_jsonb(t) AS data
			FROM final_asset_face m
			inner JOIN public.asset_face t ON t.id = m.id
			inner JOIN final_asset_face n ON m.asset_cluster = n.asset_cluster and m.face_cluster = n.face_cluster
			where m.base_owner is true and n.base_owner is false),
		patched AS (SELECT data || jsonb_build_object('id', to_jsonb(new_id),
											'personId', to_jsonb(person_id),
			  								'assetId', to_jsonb(asset_id)) AS new_data FROM joined),
		insert_asset_face as (INSERT INTO public.asset_face
			SELECT (jsonb_populate_record(NULL::public.asset_face, new_data)).*
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
		INSERT INTO public.face_search ("faceId", embedding)
		SELECT n.id, t.embedding
		FROM final_asset_face as m
		inner JOIN public.face_search as t ON t."faceId" = m.id
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
		  	left JOIN public.asset_exif t ON t."assetId" = m.id
		  	left JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
		  	where m.base_owner is true and n.base_owner is false and m.id = new.id),
		patched AS (SELECT data || jsonb_build_object('assetId', to_jsonb(new_id)) AS new_data FROM joined)
		INSERT INTO public.asset_exif
		SELECT (jsonb_populate_record(NULL::public.asset_exif, new_data)).* FROM patched
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
		INSERT INTO public.smart_search ("assetId",embedding)
		SELECT n.id, t.embedding
		FROM linked.asset m
		inner JOIN public.smart_search t ON t."assetId" = m.id
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

---- create new asset ocr

CREATE OR REPLACE FUNCTION linked.link_new_asset_ocr()
RETURNS TRIGGER AS $$
BEGIN
    IF new.base_owner is true THEN
		WITH joined AS (SELECT
		    n.id as new_id,
			uuid_generate_v4() as generated_id,
		    to_jsonb(t) AS data
		  	FROM linked.asset m
		  	inner JOIN public.asset_ocr t ON t."assetId" = m.id
		  	inner JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
		  	where m.base_owner is true and n.base_owner is false and m.id = new.id),
		patched AS (SELECT data || jsonb_build_object('assetId', to_jsonb(new_id), 'id', to_jsonb(generated_id)) AS new_data FROM joined)
		INSERT INTO public.asset_ocr
		SELECT (jsonb_populate_record(NULL::public.asset_ocr, new_data)).* FROM patched
		ON CONFLICT (id) DO NOTHING;
	END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_link_new_asset_ocr

create OR REPLACE trigger trigger_link_new_asset_ocr after insert
on linked.asset for each row
WHEN (pg_trigger_depth() = 1)
execute function linked.link_new_asset_ocr();

---- create new ocr search

CREATE OR REPLACE FUNCTION linked.link_new_ocr_search()
RETURNS TRIGGER AS $$
BEGIN
    IF new.base_owner is true THEN
		INSERT INTO public.ocr_search ("assetId","text")
		SELECT n.id, t."text"
		FROM linked.asset m
		inner JOIN public.ocr_search t ON t."assetId" = m.id
		inner JOIN linked.asset n ON m.asset_cluster = n.asset_cluster
		where m.base_owner is true and n.base_owner is false and m.id = new.id
		ON CONFLICT ("assetId") DO NOTHING;
	END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

---- create trigger_link_new_ocr_search

create OR REPLACE trigger trigger_link_new_ocr_search after insert
on linked.asset for each row
WHEN (pg_trigger_depth() = 1)
execute function linked.link_new_ocr_search();