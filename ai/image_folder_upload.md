# Image folder upload

**Implemented.** This is the fifth release type, after Single video, the video pack, the single
photoset and the photoset pack, and it is the catch-all type `ai/release_structure.md` §6
describes. It is also the evidence that page was right: it needed no change to the format, no new
field name, no new reader and no new grid — an enum value, a field list of derived values, a
template with only the image block, a label, and a section that shows the folder.

## 1. What it is

The user picks one folder of images and presses Scan. The app reads every image in it, copies them into
the release, and they are uploaded through the Upload section like any other image. The message is the
image block and nothing else.

It is the fallback for niche, unusual and future types, so it is the thinnest type the app has on
purpose: no field the user writes, no title, no picking rule. A type that needs a field, a title or a
message shape of its own is a type of its own (`ai/single_photoset.md`), not this one.

## 2. The source, the item and the copy

- `source` is the picked folder, as it is for every type.
- **The picked folder is the item** — `ItemBoundary.source`, the rule the single photoset established
  (`ai/single_photoset.md` §5). There is exactly one item, `type: imageFolder`, and its path is the
  folder's own name. `items` stays present, the path stays the ID, and the image records stay linked to
  an item.
- **The images are copied into the release**, into a folder named by the picked folder, and recorded as
  `kind: photo` with `item` set to the item path — the release folder mirrors the structure the user
  picked (`ai/release_structure.md` §4).
- **The reason to copy rather than upload from where they were picked** is the record path: a record path
  is relative to the release directory and the Upload section resolves it there (`ai/upload_images.md`),
  so a record pointing at the picked folder could not be uploaded. The picked folder is left as it is.
- **The order is filename order**, because the reader reads the files directly inside the folder in name
  order and order is data (`ai/release_structure.md` §4). The records are written in that order, and the
  Upload section works through them in the order `images.json` lists them.
- Only the files directly inside the picked folder are read; a subfolder is not read, as for a set
  (`ai/photoset_pack.md` §9). The question of whether a folder may contain subfolders is the same open
  question `ai/release_structure.md` §9 names, and this type is where one is most likely to appear.

There is no picking rule here. `ai/picking.md` decides how many photos a pack shows; this type shows all
of them, so the rule does not apply — the number is what the folder contains, not a choice.

A re-scan replaces the item and the photo records this run writes, and keeps the poster, which is not this
run's to replace (`ai/release_structure.md` §4). A run that copied files stamps the last edit, because it
changed the release; the values the user has not saved are not the run's to write.

## 3. Files that are not images

A file that is not one of the photo extensions is not counted, and it is reported rather than guessed at.

The report is the feature's, not the scan's. `PhotosetReader.read()` counts the images it is given and
reports nothing it skipped, and changing it would change what the two photoset types report. So the feature
lists the files directly inside the picked folder that are not images, in filename order, using the shared
extension rule (`isPhotoExtension`) rather than a rule of its own. `PhotosetScanner` and the readers are
unchanged, and the scan is reused as it is, with `ItemBoundary.source`.

An image whose header cannot be read is still counted — the extension list is what decides what an image
is — and reported, as for a photoset. An image that could not be copied is reported. A run that did not
finish still records and returns what it wrote, so one file that failed does not hide the ones that
succeeded.

## 4. Field list, labels and the form

`imageFolderUploadFieldList`, behind `FieldList`. Nothing here is a field the user writes: the type is a
folder, and what a post shows is the image block, so the only values are the ones the scan counts. The
names are the names the photoset types already have — a count of images is the same value as a count of
photos, a resolution is the same value, a format list is the same value — so no new name is introduced.

App-generated, at the release level:

| Field | Meaning |
| --- | --- |
| `totalPhotoCount` | the number of images in the folder |
| `minResolution` | the smallest image by pixel area |
| `maxResolution` | the largest image by pixel area |
| `imageFormats` | the distinct formats among the counted images |

There are no item fields: the item is the picked folder and the counts describe it as a whole, so an
item-level count would be the release-level count under another name.

The values go through the editor's single write path, so the controller returns them rather than writes
them, and keeps them to the names its field list has. A run that counted nothing returns none, so the
widget writes nothing.

The three photo names are the same values whatever the type, but a folder of images is not a set of
photos, so the words differ for this type: *Images (total)*, *Minimum image resolution*, *Maximum image
resolution*. That is one more arm of `fieldLabel`, which already takes the release type for the two names
the single photoset words differently (`ai/single_photoset.md` §4). The source row is not a field and its
label is per type, so this type has its own key: *Folder with the images*, distinct from *Folder with the
photosets*.

The form is the two columns the other types have, with the right column only: the left column is empty,
because there is no field the user writes. The poster box is still there, because the poster belongs to the
release rather than to an item (`ai/doc.md` §5).

The count appears twice on purpose: as the read-only field the post reads, and as the section's count line,
which comes from the records that exist rather than from what the scan counted (`ai/picking.md` §7). Those
are two different things — the field is what the scan measured, the line is what is on disk — and a run that
did not finish shows the difference.

## 5. The section

The Image folder section takes the place of the Screenshots section and the Photosets feature for this
type: the Scan button, the images as a masonry, the count line, and what the run could not take reported as
a message.

- **No Pick button**, because for this type the scan and the copy are the same action: what the rule copies
  is every image in the folder, so there is nothing left to choose after the scan.
- **No slider**, for the same reason the Photoset section has none: the number is what the folder contains,
  not a choice.
- Nothing is shown before a scan, because opening a release is a read and changes nothing; a release opened
  from a manifest shows the records its file holds.
- The folder it reads is the source row above the form, so the section does not repeat it. The row shows the
  item path, which is the folder's name, and the images under it.
- The tiles are the shared `ImageTile` and the positions come from the pure `masonryPositions`
  (`ai/picking.md` §7). Nothing is cropped: each image keeps its own ratio, and an image clearly wider than
  it is tall spans two columns. An image whose header cannot be read takes a square tile.
- Re-scanning writes the same names, so the section evicts the cache for the paths it wrote and gives each
  tile a key that changes on each run, as `AGENTS.md` §5 requires — the case the poster does not have.
- The strings that say the same thing are the ones the Photoset section already has: the Scan button, the
  unread-images and not-copied report lines, and the two source failures. New keys are added only where the
  wording differs: the section title, the count line, the not-images line, and the message for a folder that
  has not been picked.

The widget owns the layout and the widget state — the busy flag and the generation counter — and builds its
own controller in `initState` from the provider scope, as the other sections do. The controller owns the side
effects: the scan, the copies, the records, the manifest write, the stamp, and the values it returns to the
editor's write path. Typed result, no listener, no context (rules 3 and 13). No new entry in
`app_providers.dart`, because the feature adds no dependency of its own; it uses the ones already in the
scope.

## 6. The message

The template is `assets/templates/pornolab/imageFolderUpload.txt`, named by the enum value as every
template is, and it is the image block on its own:

```
{{screenshotSection}}
```

There is no field block, because the type has no fields the user writes.

There is no title. A type with no title is a rule of the type, `hasTitle` in `release_type.dart`: no title
file is read, nothing is written to `title.txt`, and the Message section draws no title row for it
(`ai/description_template.md`). This is not the same as a tracker without a title file, which produces an
empty title rather than a failure: here the type has no title at all, so there is nothing to show and no row
to show it in.

The block itself is not written again: a photo is an image in the post like a screenshot is, so the block
`MessageController` already builds covers this type unchanged — one spoiler per hoster holding the images
uploaded to it, then the backup poster for the poster's hoster.

The block's titles are the ones every type has: *Скриншоты* and *Резервный постер*. The images of a folder
are not screenshots, but the block is one shape for every type and its titles are part of it, so this type
does not get a word of its own.

## 7. What changed in code

1. `release_type.dart` — the enum value, the `releaseTypeLabel` arm, and the `hasTitle` arm (§6).
2. `release_fields.dart` — `imageFolderUploadFieldList`, `itemTypeImageFolder`, the `fieldListFor` arm,
   and the three per-type label arms (§4).
3. `release_editor.dart` — the column layout, the source row label and the section arm. All three are
   exhaustive switches over `ReleaseType`, so the compiler named the places the new type had to be handled.
4. `lib/feature/image_folder/` — the controller (scan, copy, records, stamp, values) and the section (Scan
   button, masonry, count line, report lines).
5. l10n keys in both arb files: the type label, the source row label, the three field labels, the section
   title, the count line, the not-images line and the source-empty message. The keys that say the same thing
   as the photoset section's are reused rather than duplicated.
6. `assets/templates/pornolab/imageFolderUpload.txt`.
7. Tests: the scan (the item, the copies in filename order, the values, the non-image report, a re-scan
   keeping the poster), the section (the images it copied, what it could not take, the message for no folder),
   the editor (its own fields and labels, its own section, its source row label), and the message (no title
   file read or written for this type, and no title row in the Message section).

`PhotosetScanner`, the readers, the header reader, the extension list, `masonryPositions`, `ImageTile`, the
Upload section and the message renderer are unchanged.

## 8. Open questions

- Whether a folder may contain subfolders — the same open question as for sets
  (`ai/release_structure.md` §9), and this type is where a folder is most likely to have one. Today a
  subfolder is not read and not reported.
- Whether the app copies the images into the release or uploads them from the source. This type copies,
  because the Upload section resolves a record path against the release directory (§2); the same question is
  open for packs (`ai/picking.md` §Open items), and the answer there is the same as here.
- Whether the count line should show what the scan counted rather than what is on disk. It shows what is on
  disk, as the photoset section does, which is why it can disagree with the read-only field after a run that
  did not finish (§4).
