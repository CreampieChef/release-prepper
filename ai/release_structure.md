# Release structure — one shape for all release types

**Implemented.** This is the shape the code writes, and `ai/doc.md` §7 documents it as it is.
What is still open is at the end of §7.

## 1. Why one shape

The app is not released, so there is no data to migrate. That makes the criterion for the
format: **a new release type must be addable as data, not as a format change.**

- A structure with one key per release type fails that test: every new type adds a key,
  which is a format change.
- A structure with an item list and a `type` field passes it: the format stores the technical
  name, so a new type is a value in the file, and what the app adds is its knowledge of that
  name — a field list, a template, a label. The enum is that knowledge, not the format.
- The image → item link requires an item identity for every type, including Single video.
  So Single video is an item list of length one, and its data lives in `items[0]`.
- Photosets differ from videos in **processing** (copying files instead of generating
  frames), not in data shape. A difference that exists only in the code that produces the
  files must not be encoded in the format.
- The catch-all release type in §6 is the test of the design: it needs no new structure,
  only a field list with nothing required and a template that emits the default block.

One shape for the containers. Field lists stay per release type — that is where the shapes
genuinely differ, and it is what `ai/release_editor.md` already says.

## 2. The source and item identity

`source` is **what the user picked**, and item paths are relative to it. A picked file is
treated as a directory containing only itself — the same rule as an archive name being a
directory segment. So a single video's item path is its filename, and a pack item's path is
its path under the picked directory. One rule, no branch.

This is what removes the ambiguity of storing a parent directory: the source records what was
picked, so the app never has to decide what belongs to the release. A file root yields exactly
one item; a directory root yields the items the scan wrote. Membership is never inferred from
the release type at read time.

A type can also say that the source itself is the item, which is what a single photoset does
(`ai/single_photoset.md` §5). Then the source is a container containing only itself, and the item
path is the source's own name — the same rule a picked file already follows, so no second rule is
needed. `Release.absolutePath(item)` answers with the source for such an item, so the path is not
joined to the source twice.

Rules:

- **The relative path is the ID**, for items and for image records. There is no generated id
  field.
- Item paths are relative to `source`. Image record paths are relative to the release
  directory. These are two namespaces, and that is deliberate: videos are never copied, so an
  item path is a path in the source, while an image path is a path inside the release.
- `source` is the only absolute path in the format, and it is knowingly not portable. Every
  path inside the release stays relative, so the manifest remains valid if the release folder
  is moved.
- IDs do not depend on where images are placed inside the release: the ID is the
  path whatever the placement gives, so the format does not encode the policy.
  Moving a file that is already recorded changes its ID, which is the rename rule
  in §4.
- Items reflect real files on disk — videos, directories, archives. The user cannot add or
  remove an item that is not on disk. The app never alters the user's videos or directories.
- A pack does not mix item types. A video pack holds videos; a photo pack holds photosets. A
  structure that mixes them is invalid and is rejected by validation.
- `type` is **recorded at scan time**, not derived on read. What counts as an item depends on
  the release type: in a photo pack a subdirectory is an item, in a video pack a subdirectory
  is a container of images belonging to an item. That is a rule, not a fact about the
  filesystem, so the decision the app made must be recorded rather than re-derived — otherwise
  re-reading an old release can produce a different item list than the one the scan wrote.

Single video:

```json
{
  "source": "/home/user/videos/movie.mp4",
  "items": [ { "path": "movie.mp4", "type": "video", "fields": {} } ]
}
```

Pack, same rule:

```json
{
  "source": "/home/user/packs/my_pack",
  "items": [
    { "path": "videos/first.mp4",  "type": "video",   "fields": {} },
    { "path": "videos/second.mp4", "type": "video",   "fields": {} }
  ]
}
```

The filename appears twice for a single video — once inside `source`, once as the item path.
That is accepted: `source` is an absolute location outside the release, `items[0].path` is an
ID. They serve different purposes, and a pack has no duplication because the root is stored
once. Storing the parent directory instead would remove the repetition but would make the app
decide membership from the release type, which is the branch the whole design exists to avoid.

## 3. `release.json`

```json
{
  "schema": 1,
  "createdDate": "2026-03-11T10:00:00.000Z",
  "lastEditDate": "2026-03-14T18:22:31.000Z",
  "tracker": "pornolab",
  "releaseType": "singleVideo",
  "source": "/home/user/videos/movie.mp4",
  "fields": {
    "subsiteAndSite": "XXX / Main",
    "productionDate": "2026-03-11",
    "genreTags": "solo, anal",
    "description": "",
    "additionalInfo": ""
  },
  "items": [
    {
      "path": "movie.mp4",
      "type": "video",
      "fields": {
        "videoTitle": "Example title",
        "cast": "",
        "videoFormat": "MP4",
        "videoStream": "AVC, 3840x2160, 29.970 (30000/1001) FPS, 15.0 Mb/s",
        "audioStream": "AAC LC, 48.0 kHz, 2 channels, 128 kb/s",
        "fileSize": "10737418240",
        "duration": "00:12:34"
      }
    }
  ],
  "includeAppSignature": true,
  "torrentPrivate": true
}
```

Rules:

- `tracker` and `releaseType` are the technical names — the enum values of `Tracker`
  (`tracker.dart`) and `ReleaseType` (`release_type.dart`) — and they are the IDs: the same names
  the template folder and file are built from and the field lists are looked up by. The display
  name is not stored, because it is resolved when it is shown: for a release type it is an
  `AppLocalizations` key, and for a tracker it is the same in every language, so it is a field on
  the enum. A value that is not one of the names this version knows is reported rather than
  guessed at: there is no field list, template, label or icon for it, and saving would write a
  name the file did not contain.
- `createdDate` and `lastEditDate` are the record of the release changing: the first is written
  once when the release is created and never changes, the second is stamped by every write,
  including the operations that write files inside a release rather than the manifest. Both are
  UTC ISO 8601. A manifest that does not have them is read as having none and written back
  without them, because the app writes what the file contains rather than a date it invented.
- `fields` is always a `name → string` map, at both levels. That is what makes this one shape.
- `items` is always present. Single video has exactly one item, and its data is `items[0]`.
- Three keys are not fields, dates or IDs: `screenshotLayout`,
  `includeAppSignature` and `torrentPrivate`. All three say how the release is
  prepared rather than what it contains, and all three belong to the record
  rather than to the app's settings, because the files generated from them were
  written with them: a release opened again has to show the shape and the
  signature its post was written with, and the flag its next torrent would be
  made with. None is a field, so none is in a field list; the checkboxes that
  show the flags are rows of the Message and Torrent sections rather than of the
  form.
  `screenshotLayout` is the shape the message's image block has
  (`ai/description_template.md` §Screenshot section). It is written only for the
  type that can choose one, so a release of another type does not carry a shape
  it could never use. `includeAppSignature` is whether the message ends with
  the app signature (`ai/description_template.md` §App signature), and it is
  written for every type. `torrentPrivate` is the flag a torrent run is asked
  for (`ai/torrents.md`), and it is written for every type, because the tool
  takes a file or a folder whatever the release is. It is the flag the app would
  write, not the flag a file on disk has: the file is the thing the flag
  describes, so a release opened again shows what its file states, and the
  record is what the row shows only when there is no file. A confirmed
  change to a file that is already there is written here at once, because
  the record has to agree with the file, and it does not make the tab
  dirty: the file is already changed, so there is nothing left to save.
  Where the values a new release is written with come from is a settings choice
  (the Settings page's Releases section); a clone is written with the source's,
  because a clone is the same scene at another resolution. A default is what a
  release is built with at the moment it is created, so changing it does not
  rewrite a record that exists: the record keeps what it was written with, and
  the flags on a release stay its own. The store is given the values rather than
  deciding them, so the same write serves both paths.
  A manifest without any of the three, or with a value this version does not
  know, reads as the default — the shape those files were written with, a
  message with the signature, and a private torrent — because a shape and a flag
  are not IDs, so they are not reported as an error the way an unknown tracker
  or release type is.
- The shared fields — subsite and site, production date, genre tags, description, additional
  information — exist at **both** levels. **Templates read the release fields**, so the message
  has one variable scope. 99% of releases work with the release-level values; the per-item
  values exist because the post lists items individually and because the tags are combined from
  them.
- The combination is one-directional: the items are the source, the release fields are the
  result. The editor has a button that fills the release tags from the items. It is not an
  automatic sync, because editing a release field must not silently overwrite the items it was
  built from.
- In the post a video is identified by its file name. A per-item title is optional additional
  information, the same as for a single video; it is below-average priority and may need its
  own template or an adaptation of the single-video one.
- Field lists are per release type. Required and optional are per tracker, not per type: for a
  pack PornoLab requires only the screenlist and the video tech data. So the required/optional
  marker belongs to the tracker config, not to the field list.
- `sceneUrl` is a field name in both lists: the StashDB scene the release is being prepared for,
  stored as the canonical URL built from the scene id, not as the text the user pasted. For a
  single video it is the item's URL; for a pack each item has its own, which is why it belongs to
  the item field list rather than being a key on the item record. It is the one field name with no
  form row — its widget is the Stash section's scene input, and the Stash section writes it through
  the editor's write path. It is stored for a pack once the per-item form exists; until then the
  editor writes it at the release level.
- The fields filled from the media are a property of the video field list only. A photoset has
  no probe-derived fields; its fields are the image count, the minimum and maximum resolution,
  and the formats.

## 4. `images.json`

```json
{
  "schema": 1,
  "images": [
    { "item": null, "kind": "poster", "file": "_rp_poster.jpg", "urls": {} },
    { "item": "movie.mp4", "kind": "screenshot", "file": "images/movie.mp4/_rp_screenshot01.jpg", "urls": {} },
    { "item": "movie.mp4", "kind": "screenlist", "file": "images/movie.mp4/_rp_screenlist.jpg", "urls": {} }
  ]
]
```

Rules:

- One flat list. No key per kind, so a new kind is a value rather than a format change.
- `item` is the item path from `release.json`, or `null` for an image that belongs to the
  release. Posters belong to the release by default; a pack post and a single video post both
  use the release poster. Per-item posters exist as an option in packs and appear only inside
  the spoiler.
- `kind` is the role the image has in the post: `poster`, `photo`, `screenshot`, `screenlist`,
  `thumbnail`.
- **Order is data, and it is scoped per item and kind.** For copied images it is the order the
  source gives — for an archive, the order of its entries, which is the order they were packed
  in; for a directory, the order a file manager shows. For generated images it is the generation
  order. For posters it is the priority, and the first poster record is the primary one. The UI
  can reorder posters, which rewrites the file. There is no `role` field.
- `urls` is unchanged: hoster → URL type → URL, only successful uploads stored, so the skip
  rule is unaffected.
- **Records are the source of truth for image paths.** Nothing is derived from the release
  directory, because two posters cannot share one derived name.
- The release folder mirrors the structure the user picked for the images that are copied into
  it. Only the images that are uploaded are kept; the archive itself is not. Generated images
  stay in the `images/` folder at the release root as they do today.
- **Provenance is not data.** A record does not say whether the app generated it or the user
  copied it. `kind` decides what can be regenerated: a screenshot can, a copied photo cannot.
- **An image that has been uploaded is not regenerated.** Once a record has any URL, it is
  fixed. Since a generation run rewrites the whole set, in practice the run is blocked once
  anything in it has been uploaded. This is what keeps records, their URLs, and the files on
  disk from drifting apart.
- Records are added and removed only by a generation run or a manual re-scan. **Opening a
  release is a read and changes nothing.** Changing the content of a release mid-work is
  uncommon, and re-scanning is a manual operation the user chooses.
- **Renaming is accepted as a loss.** The app cannot prevent the user from renaming their
  files, and with the path as the ID there is nothing to match a renamed record against. The
  data is gone. Ideally the app offers a way to move it to the new name (`lib/TODO.MD`).

## 5. What this means for the message

- Variables read the **release fields** (§3), so the message has one variable scope. Item
  variables are only needed where the post lists items individually, which is where iteration
  is needed.
- `TemplateRenderer` has truthiness sections only, so it needs iteration over a list. This is
  the one genuinely new capability in the renderer.
- Grouping by item or flattening, and the block titles, differ per tracker and per release
  type. They are rules, so they belong in the tracker config. Building the block in code is no
  longer acceptable once more than one type exists.
- For the video pack the grouping is decided, because it is the type the post names item by
  item: the two shapes are the ones written in `ai/description_template.md` §Screenshot section,
  and the one a release uses is stored in its `release.json` as `screenshotLayout`. That is a
  per-release choice, not a per-tracker rule, so it is not part of the config the next bullet
  describes. The other types keep the flat block, and the rule for them is still open.
- **The grammar of that config is not decided.** It stays in code until enough of PornoLab's
  release types are covered to know what it has to express.
- Photos are rendered the same way screenshots are: the link is the view URL, the picture is
  the thumb URL.

## 6. The catch-all release type

A release type that accepts a directory of images, copies it into the release, uploads it to
the photo hosters, and produces the default screenshot spoiler text. It exists to cover niche,
unusual and future types without inventing a new shape for each. It is implemented as the **Image
folder upload** type (`ai/image_folder_upload.md`).

It needs nothing new in the format: the type is a value in the file, so the app adds its knowledge
of the name — an enum value, a field list with nothing required, a template that emits the default
block, and a label. Its item is the picked directory; its records are `kind: photo` linked to that
item.

The single photoset (`ai/single_photoset.md`) is the first type with this item rule in live code, and it
is not the catch-all: it has a field list of its own and a template of its own, while the catch-all has
nothing required and emits the default block. They are two different things that happen to share the item
rule, and the image folder type keeps them separate: it has no field the user writes and no title, so it
is the shape, not a type with content of its own.

## 7. What changes in code

Done:

1. `release.dart` — `fields` is release-level; `source` and `List<ReleaseItem>`; the two dates.
2. `release_fields.dart` — per-type field lists behind one model the editor and the message read
   through, and the per-item field lists.
3. `release_store.dart` — reads and writes the item shape.
4. `images.dart` — one flat record list with a nullable `item` and `kind`; the path is the ID.
5. `release_type.dart` and `tracker.dart` — the technical names are the IDs, so the manifest value,
   the enum value and the asset path are one name; the display names are resolved when shown.
6. `release_editor_controller.dart` — poster paths come from records, and the first poster record is
   the primary one.
7. The photoset feature that copies files from a directory or an archive into the release and
   records them, and the scan that creates the items.
8. The catch-all type as the Image folder upload (`ai/image_folder_upload.md`): the enum value, the field
   list of derived values with no field the user writes, the section that shows the folder, the template
   with only the image block, and the per-type labels for the three photo names.
9. Tests, and `ai/doc.md` §7.

Still open:

1. `screenshots_controller.dart` works per item for the one item a Single video has; a pack's
   screenshots are not built.
2. Multiple posters in the UI, and reordering them by priority.
3. The button that fills the release tags from the items, and the block on regenerating an image
   that has been uploaded.
4. `message_controller.dart` — iteration where the post lists items, and the block rules read from
   the tracker config; the required/optional marker still lives in the field list, because there is
   no tracker config yet.
5. `template_renderer.dart` — iteration over a list.
6. The editor renders per-item forms.

## 8. What does not change

The hoster registry, `Uptooda`, the native-tool layer, `ToolLog`, the l10n mechanism, the provider
graph, the `urls` structure, and one-file-per-release persistence.

Two things this page said would not change did change, and the change is the point: `releaseType`
stopped being a display string and became the enum value that is the ID, and `TemplateStore`'s slug
mapping was deleted because the folder and the template file are named by that ID directly. One name
for the ID in the file, the enum and the asset path is what the design wanted; the display string
was the second name.

## 9. Open questions

- What decides item boundaries per release type is answered for the types the app has: the rule is
  carried on the field list as `itemBoundary`, because it is a rule of the type rather than of the
  scan — a pack's items are the entries under the source, and for the two single types the source
  itself is the item (`ai/single_photoset.md` §5). What is still open is whether a subdirectory
  inside a set is another item or part of the set; today the reader reads the files directly inside
  a set and leaves a subfolder out.
- Whether a pack post lists a title per item, or only the file name.
- The grammar of the tracker config: required and optional fields, the poster hoster, the URL
  types, the block titles, the grouping rule, and how many posters a release may have.
- Screenlists: the app generates them and stores them in the app's own image
  folder, which is what the code does. For a large pack it is worth deciding
  whether the file belongs inside the video's own folder instead, where the user's
  files are. Locking the source field once records exist and moving a record's
  data when the user renames a file are in `lib/TODO.MD`.
