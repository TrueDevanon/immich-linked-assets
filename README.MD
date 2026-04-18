# Immich Linked Assets

A robust SQL-based automation tool for **synchronizing and sharing assets** across multiple [Immich](https://immich.app/) users using a **tag-driven linking system**. It allows seamless cloning of photos, albums, tags, and people metadata directly within the Immich database (without duplicates on the hard drive). 

---

### ✅ Tested Immich version: **v2.7.5**

---

## 🚀 Overview

Immich Linked Assets enables collaborative synchronization based on a special `linked` tag. When this tag is applied to an asset, it is automatically **cloned and synchronized** across all connected users.

---

## 🧩 How It Works

The system operates in two main steps:

1. **Database Schema Extension** — Adds new structures to manage linked assets.
2. **Database Triggers** — Automatically handles cloning and syncing in real-time.

### On First Run

* All assets with the `linked` tag are cloned for all participating users.
* The following are included in the cloning process:

  * Asset with metadata
  * Asset tags
  * Albums containing those assets
  * People associated with those assets
  * Data used for context search/face similarity

### After Initial Setup

#### ⚠️ **Important Note:** Due to the script’s design, you can add the `linked` tag only to an existing asset in Immich. Do not add the `linked` tag to your photos before you upload it.

* **Tag Trigger** — When an asset receives the `linked` tag, it triggers a clone for all linked users.
* **Cloning Logic** — Each user gets a full, copy of the asset, including metadata, tags, and facial recognition data.
* **Real-Time Sync** — Any changes (metadata, tags) are instantly propagated to all linked copies.

> ⚠️ **Note:** If you add the `linked` tag *after* running the script, linked assets will still sync, but albums containing them will **not** be cloned.

---

## ⚙️ Setup Guide

### **The script is not compatible with "Storage Templates".**

0. **Verify Immich version compatibility.**

1. **Backup Your Database**

   ⚠️ The script modifies your Immich database directly. Backup your data before proceeding. Future Immich updates may affect compatibility.

2. **Create a Linked Album**

   * In Immich, create a new album named `linked album`.
   * In its description, specify the tag name that will act as the `linked` tag.
   * Share this album with users who should participate in synchronization.

3. **(Optional) Set a Display Name**

   * Update your display name in Immich settings. This name is used as part of the automatic tagging system. Each `linked` asset will have:

     1. A shared `linked` tag
     2. A tag with the owner’s name

4. **Prepare Shared Assets**

   * Create the `linked` tag for each participant.
   * Tag all assets you intend to share.
   * Doing this before the first run improves performance significantly.

> 💡 The linked album is only needed for the **initial setup**. After the script completes, it can be safely deleted.

5. **Install the Script**

   Run the following command (update with your database/container details):

   ```bash
   docker exec -i immich_postgres psql --dbname=immich --username=postgres < ./immich_linked_asset.sql
   ```

---

## ❌ Removing the Script

To completely remove linked assets and triggers:

```bash
docker exec -i immich_postgres psql --dbname=immich --username=postgres < ./immich_delete_linked_asset.sql
```

> ⚠️ **Note:** If you only want to remove triggers, comment out or delete all lines except those containing `DROP TRIGGER`.

---

## 🔁 Updating the Script

If Immich updates cause trigger issues, reinstall only the triggers without affecting existing linked assets:

```bash
docker exec -i immich_postgres psql --dbname=immich --username=postgres < ./immich_update_linked_trigger.sql
```

Always check the **tested version** listed at the top before applying updates.

---

## 🧭 Manual Linked Album Management

After the initial synchronization, new albums are **not** automatically cloned. You can manually link or unlink them using special commands inside the album description.

### 🔗 Create a Linked Album

Add this line to the album description and save:

```
create linked album
```

This will:

* Clone the album for all linked users.
* Clone all assets within it that have the `linked` tag.

### ❌ Remove a Linked Album

To unlink and delete an album from other users’ accounts, add this line to its description:

```
delete linked album
```

This will remove the album for all linked users except the owner.

---

## 🔄 Synchronization & Permissions

The system operates on an **owner/non-owner** model. The owner is the user who uploaded an asset, created an album, person, or tag. Any changes made by the owner will automatically be reflected in the system for others (except for asset metadata).

### Owner Permissions (Changes Are Synced)

* **Trash Item** — Trash for owner, but **archive** for other (All linked copies are connected to the same file, so anyone can delete it from the trash permanently).
* **Permanently delete Item** — Deleted for everyone.
* **Remove linked Tag** — Asset is unlinked and deleted for all others.
* **Edit person metadata** — Changes will propagate to others.
* **Edit album metadata** — Changes will propagate to others.
* **Edit tag metadata** — Changes will propagate to others.
* **Create stack** — Changes will propagate to others.

### Non-Owner Permissions

* **Trash linked Item** — **Linked** asset will be **archived**. (Local Only)
* **Add to albums** - Add or remove to linked and non-linked albums.
* **Unstack linked assets** - Unstack linked assets (Local Only).

### Owner and Non-Owner

* **Edit asset Metadata** — Synced to all users (instant).
* **Add or Remove Tags** — Synced to all users (instant).
* **Modify people** - Add, change, or delete people. (Local for non-owner)

### People/Face & Album Sync Details

* **People Metadata** — Synced when edited by the owner.
* **Linked Faces** — Not automatically synced; re-tag the asset to re-sync.
* **Albums** — Any linked user can add linked assets to any linked album. However, the asset’s owner can remove that asset from any album across accounts, while non-owners can only remove it locally within their own account.

### Summary Table

| Action                   | Owner | Non-Owner | Synced?                      |   
| ------------------------ | ----- | --------- | --------------------------   | 
| Edit Asset Metadata      | ✅     | ✅         | ✅                          |   
| Add or Remove Tags       | ✅     | ✅         | ✅                          |   
| Modify Person on Asset   | ✅     | ✅         | ❌ (Requires re-link)       |   
| Delete Asset             | ✅     | ✅         | ✅ (Owner deletes globally) |   
| Remove linked Tag        | ✅     | ✅         | ✅ (Owner unlink globally)  |   
| Edit Album Metadata      | ✅     | ❌         | ✅ (Owner overwrites)       |   
| Add or Remove Linked Asset | ✅     | ✅       | ✅ (Owner deletes globally) |   
| Delete Album             | ✅     | ✅         | ✅ (Owner deletes globally) |   
| Link or Unlink Album        | ✅     | ❌      | ✅                          |   
| Edit Tag or Person Metadata | ✅     | ✅      | ✅ (Owner overwrites)       |  
| Edit asset (crop/rotate/etc) | ✅     | ✅       | ❌ (Requires re-link)        |  

---

## 😎 Pro Tips

* To avoid duplicate people entries, merge your **base** to **linked** people across accounts. This ensures new linked assets reuse existing entities. (Note: owner metadata updates will propagate to everyone.)
* Linking assets is not instant — expect ~1–2 seconds per asset on slower disks.
* ~~The Immich *Memories* feature currently does not work correctly with linked assets.~~
* If you create a stack of assets, only **linked** assets will be cloned
* Sometimes, when you add, remove tags, or edit metadata of an asset, **Immich** can refresh the sidecar too often, which causes the auto-recreation of the **linked** asset.
* Be careful with deduplication feature in Immich.
* When you create a stack as an asset owner, the primary asset in the **linked** stack can differ (if the primary asset is not **linked**).

---
