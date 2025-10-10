# Immich Linked Assets

This script enables **automatic synchronization and sharing of assets** between multiple [Immich](https://immich.app/) users through a **tag-based linking system**.
It allows users to share photos, albums, people, and metadata seamlessly across connected accounts.

---

### Current tested Immich version: **v2.0.1**

---

## 🚀 Overview

The synchronization system is based on the **`linked` tag**.
When an asset is tagged as `linked`, it will be **cloned** and synchronized among all users connected through a **linked album**.

---

## ⚙️ Initial Setup

0. **Check supported version of Immich**

1. **Create backup**

   * Immich is in active development, and any new update can possibly break a script.

2. **Create a “linked album”**

   * In Immich, create a new album that will act as your *linked album*. Title must be **linked album**.
   * In the album’s description, specify the name of the tag that will be used as the `linked` tag.
   * Share this album with other participants who will exchange assets with you.

3. **(Optional but recommended) Set your display name**

   * In your Immich user settings, change your display name to your real name or nickname.
   * When assets are cloned, two tags will appear automatically:

     1. The shared `linked` tag
     2. The tag containing the *owner’s name* (from system settings)

4. **Prepare your shared assets**

   * Before executing the script, create the `linked` tag for each participant.
   * Assign this tag to all assets you want to share.
   * Doing this **before** the script runs will greatly improve performance, since assets will be processed instantly rather than scanned dynamically.

> 💡 **Note:**
> The linked album is **only required for the initial run** of the script.
> Once the script finishes, you can safely delete this album — it’s no longer used in later operations.

5. **Install the script**

   * Copy project files to any folder on your server.

   > The following command works with the default Immich settings, replace dbname/username/container_name according to your settings.

   ```
   docker exec -i immich_postgres psql --dbname=immich --username=postgres < ./immich_linked_asset.sql
   ```


## ❌ To remove script

   * Execute the following command on your server. It will remove all *linked* assets and triggers.
   
   > If you need to delete only triggers, then comment/remove all lines except ones that contain `drop trigger`

    > The following command works with the default Immich settings, replace dbname/username/container_name according to your settings.

   ```
   docker exec -i immich_postgres psql --dbname=immich --username=postgres < ./immich_delete_linked_asset.sql
   ```

## 🔁 To update script

   Basically needed only if a new version of Immich changes something in the database, and the triggers won't work anymore. I would try to fix the issue as soon as possible. Before updating, check the latest tested version at the top of this readme.

   As a quick solution, you can delete triggers from the database, and when I fix the script, reinstall it.

   * Execute the following command on your server. By this action you recreate only triggers, it won't change any of your *linked* assets.

    > The following command works with the default Immich settings, replace dbname/username/container_name according to your settings.

   ```
   docker exec -i immich_postgres psql --dbname=immich --username=postgres < ./immich_update_linked_trigger.sql
   ```

---

## 🧩 How It Works 

The script consists of two parts:

1. Create a new scheme in the database and create **linked** assets.
2. Create triggers on tables in the database to dynamically create new **linked** assets.

When you first run the script:

* All assets with the `linked` tag are **cloned** for all participants.
* The following are also cloned:

  * All tags on those assets
  * Albums containing those assets
  * People associated with those assets
  * Assets that are used as a base for face to those people

When you add the `linked` tag **after applying the script**, new linked assets (with tag/people) will be cloned, but albums that contain the asset **will not**.

---

## 🧭 Manual Linked Album Management

After the initial synchronization, new albums will not be automatically cloned between users.
To manually link or unlink albums, use the following commands in the **album description**:

### 🔗 To Create a Linked Album

If the album owner wants to share an existing album with all connected users:

1. Edit the album description and add the line:

   ```
   create linked album
   ```
2. Save the changes.

After that:

* The album will appear for all other linked users.
* All assets in it that have the `linked` tag will be cloned for everyone.

### ❌ To Remove a Linked Album

If the owner wants to unlink and delete the album from other users’ accounts:

1. Edit the album description and add:

   ```
   delete linked album
   ```
2. Save the changes.

After that:

* The album will be removed from all linked users (except the owner).

---

## 🔁 Synchronization Rules

### 🟢 Asset Owners Can:

* Edit metadata — updates are instantly synced to all participants.
* Add or remove tags — changes propagate to everyone.
* Removing the `linked` tag from the asset will lead to deleting the asset from all linked users.

### 🟡 Non-owners Can:

* Edit metadata (local only — not synced).
* Add or remove tags (local only — not synced).

### 🔵 Both Owners and Non-owners Can:

* Add assets to the linked album.
* Modify people associated with an asset (not synced automatically).

### 🟢 Album/Tag/People Owners Can:

* Edit all metadata — updates are instantly synced to all participants.

### 🟡 Album/Tag/People Non-owners Can:

* Edit all metadata, but only locally, and when the **owner** changes album/tag/people metadata, it overwrites non-owner changes.

---

## 🧹 Deletion Rules

* When the **owner** deletes an asset, album, or tag — it is deleted for **everyone**.
* When a **non-owner** deletes an album — only their access is revoked (tags remain).

---

## 🔄 Updating People Synchronization

If the owner wants to change people on an asset and synchronize these updates:

* Simply **remove** the `linked` tag, then **add it again**.
* The script will detect the change and resynchronize the asset.

---

## 😎 Pro tip

   * When someone is creating a **linked** asset that contains people who already exist in your account, you get duplicates. To prevent it, merge your **base** to **linked** people on every account. By this action, any new **linked** asset with these people wouldn't create a duplicate. But the method has a disadvantage: when the true owner of people changes metadata (name/birthday), it will propagate to everyone else.

   * When you create **linked** asset with new people, the script would clone 2+ asset:
      1. Original asset.
      2. Assets that are linked to the people on the original asset (assets that contain face).
   To avoid sharing assets that you won't share, go to those people and choose another "featured photo".

   * Creating a **linked** asset is not an immediate action; if you try to put **linked** tag on a couple of assets at once, it will take some time to finish. (on my old slow hdd ~1.2 second per asset with total asset count ~230k)

---

## 💡 Synchronization Rules summary

| Action                                       | Owner | Non-Owner | Synced?                |
| -------------------------------------------- | ----- | --------- | ---------------------- |
| Edit metadata                                | ✅     | ✅         | ✅ (owner to others)         |
| Add/remove/edit tags                              | ✅     | ✅         | ✅ (owner to others)         |
| Delete asset                                 | ✅     | ✅         | ✅ (owner to others)         |
| Remove `linked` tag                          | ✅     | ✅         | ✅ (owner to others) |
| Modify people                                | ✅     | ✅         | ✅ (owner to others (only metadata))    |
| Modify album metadata                        | ✅     | ✅         | ✅ (owner to others)          |
| Add to linked album                          | ✅     | ✅         | ✅ (only linked assets)  |
| Delete album                                 | ✅     | ✅         | ✅ (owner to others)         |
| Create/delete linked album (via description) | ✅     | ❌         | ✅ (owner only)         |

---

