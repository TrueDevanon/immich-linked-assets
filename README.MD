# Immich Shared Asset Sync Addon

Current tested Immich version: **v1.138.0**

**Goal:**
This addon is designed to solve the shared asset problem in [Immich](https://immich.app/) when used as a family gallery with separate accounts for each family member. Normally, you must upload shared family photos to each account separately, which results in:

* Duplicate files and wasted disk space.
* Unmanageable Synchronization of shared assets.

## Approach

Instead of uploading the same files multiple times, this addon allows you to:

* Maintain a single **"Family"** account with all shared media.
* Automatically clone/synchronize that media with all other linked user accounts without storing duplicate files.

**Benefits:**

1. Eliminates duplicate files, saving disk space.
2. Synchronizes changes to shared assets between users.

## Important Warning

* **This addon modifies your database** directly.
* You risk losing data if something goes wrong.
* Immich is under active development — database structures may change.
* Always check for addon compatibility before upgrading Immich.
* Installing the addon will create new person entries for linked media, which may appear as duplicates.

## How It Works

* The addon creates a **new schema** in the database.
* It adds triggers to Immich's asset tables.
* All assets in the specified "linked album" are made visible to all linked users.
* Changes in linked assets (deletions, metadata updates, people tagging, albums, tags) are synced across all linked users.

**Limitations:**

* Starred/favorites are not synced.
* New persons must be linked to existing linked assets; otherwise, the addon will try to add all assets containing that person.

## Installation Steps

1. **Backup your database**

   * Administration → Jobs → Create Job → Create Database Dump.

2. **Create the linked album**

   * Name must start with `linked album`.
   * In the description, place the absolute path to your shared media location. exp: `/data/upload/1e24bb2e-e9a2-424c-a9c7-8bdc24715f9e/`

3. **Share the album**

   * Share with all target users.

4. **Install the addon**

   ```
   docker exec -i immich_postgres psql --dbname=immich --username=postgres < ./immich_linked_asset.sql
   ```
5. **Manage job concurrency**

Set the following parameters to 1 (Synchronization requirement):
```
External Libraries concurrency
Smart Search concurrency
Face detection concurrency
```
6. **To remove the addon**

   ```
   docker exec -i immich_postgres psql --dbname=immich --username=postgres < ./immich_delete_linked_asset.sql
   ```

## Synchronization Behavior

* **Add new media**: Adding files to the linked album's path will create linked assets for all linked users.
* **Delete media**: Deleting a linked asset from one account removes it from all linked accounts.
* **Edit metadata**: Changes (except stars/favorites) are synced.
* **People tagging**: Manual person tags are synced if the person is already linked to another shared asset.
* **Albums**: Creating albums with linked assets, or adding/removing linked assets from albums, is synced. (album cover is not synced)
* **Tags**: Creating or removing tags on linked assets is synced.
