# Single photoset

The third release type, after Single video and the video pack. **Implemented.** It follows
`ai/release_structure.md`: the containers are one shape for every type, and a new type is a
field list, a template and a label. `ai/doc.md` §7 describes the shape as it now is.

## 1. What it is

One photoset, not a pack of sets. The source is a directory of photos, and that directory is the set.

It is the type `ai/release_structure.md` §6 describes as the catch-all, but with a field list, so it
is a type of its own and the catch-all stays the future fallback. They are not the same thing: the
catch-all has nothing required and emits the default block, while this type has the fields a photoset
post shows.

It is not a photoset pack with one item, for one reason: the field list. A pack's user fields are the
journal, the period and the counts across sets; a single set has a model, a title and a date, and no
period. A type that is a pack with one item would carry both lists and the post would show fields it
has no values for.

## 2. The source and the item

- `source` is the picked directory, as it is for every type.
- **The picked directory is treated as a container containing only itself** — the same rule as a
  picked file (`ai/release_structure.md` §2). So there is exactly one item, `type: photoset`, and its
  path is the directory's own name. `items` stays present, the path stays the ID, and the image
  records stay linked to an item.
- **The display name is the item path.** A directory name has no extension, so the derivation in
  `ai/photoset_pack.md` §2 returns it unchanged, and the mirror folder in the release carries the
  same name (`ai/release_structure.md` §4). No collision is possible with one item.
- One item means no aggregate across items: the release-level values are the values of that one item.
  `photosetCount` is not a field here, because it is always 1.

## 3. Field list

`singlePhotosetFieldList`, behind `FieldList`. Names are the names `release.json` writes, and a name
that means the same thing is the name another type already has (`ai/video_pack.md` §3). The labels
are per type, which is §4.

User-provided, at the release level:

| Field | Meaning |
| --- | --- |
| `cast` | the model, or the actress — the existing name, reused |
| `videoTitle` | the set name — the existing name, reused |
| `siteOrJournal` | the journal or the site — the existing name, reused |
| `productionDate` | the date — the existing name, reused, with the date picker |
| `genreTags` | the tags — the existing name, reused |
| `description` | the description — the existing name, reused |
| `additionalInfo` | the additional information — the existing name, reused |
| `sceneUrl` | the scene the set is from — the existing name, reused, and the name the Stash row writes (§9) |

`additionalInfo` is on the list because the template reads it as an optional line, so the type has
the field and the row the other types have (`ai/description_template.md` §Variables). A field with
no row and no value would be stored but never written, which is why it was not on this list while
no template read it.

`sceneUrl` is on the list because the row the field has is drawn for this type too (§9). It has no
row the form builds, as it has for a single video: its widget is the Stash row, and that is what
writes it through the editor's write path (`ai/release_structure.md` §3).

`additionalInfo` is on the list because the template reads it as an optional line, so the type has
the field and the row the other types have (`ai/description_template.md` §Variables). A field with
no row and no value would be stored but never written, which is why it was not on this list while
no template read it.

App-generated, at the release level:

| Field | Meaning |
| --- | --- |
| `totalPhotoCount` | the number of photos in the set |
| `pickedPhotoCount` | the number of photos the picking rule wrote |
| `totalSize` | the size the counted photos have in the source, summed |
| `minResolution` | the smallest photo by pixel area |
| `maxResolution` | the largest photo by pixel area |
| `imageFormats` | the distinct formats among the counted photos |

App-generated, at the item level:

| Field | Meaning |
| --- | --- |
| `photoCount` | the number of photos in this set |

`photoCount` and `totalPhotoCount` are the same number here, and both are kept on purpose: the scan
writes the item's value, and the aggregate is the name the pack already has. Nothing shows the item's
value for this type, because the block draws no list of sets, so a per-item count is written and read by
the model rather than by the form (`ai/picking.md` §7). `pickedPhotoCount` is not what the scan counts:
it is what the pick run wrote, so it is filled by the run rather than by the scan, and it is handed to
the editor's write path at the end of the run, as the scan's values are. It is the same name and the
same value as the pack's, because for this type the item is the folder the run wrote into, so the
release-level count and the item's are the same number.

Resolution is compared by pixel area, as for a pack, including the tie that decides which of two
equal photos is reported (`ai/photoset_pack.md` §3), and a resolution value is written as
`WIDTHxHEIGHT`. `totalSize` is the same name and the same rule as the pack's (`ai/photoset_pack.md`
§3): the sizes the counted photos have in the source, summed — with one item that is the set's own
total. `imageFormats` is the distinct extensions among the counted photos, lowercased and sorted
alphabetically, joined with `, ` — the same rule as `videoFormats` (`ai/video_pack.md` §4). A photo
whose header cannot be read is still counted, because the extension list is what decides what a
photo is, and it is reported.

The field's value is what the scan counted, so an all-jpg set is a `jpg` value and its row says so.
The post lists no formats for such a set, because the site does not write a line for a post whose
images are all jpg (`ai/description_template.md` §Variables): the value a render reads is the empty
one, which is what drops the line, while the field, its row and `release.json` keep the value. The
rule is the site's rather than this type's, so it applies to the other two types the same way, and a
mixed set still lists jpg with the others.

The two resolutions are two fields, and the title shows them on one line, so the value the title
reads is not a field: it is built when the message is rendered, as the image variables are
(`ai/description_template.md` §Variables). Nothing can edit it, so it is not stored and not in this
list.

The derived values describe **the source as scanned**, not the photos the picking rule chose: the post
reports the set's stats, and the sample is what the post shows, not what it measures.

The poster is not a field. It is the poster box every type has (`ai/doc.md` §5).

The form has the first column the other types have: the user fields with the poster box above them, and
the scene link row as its first row, as it is for a single video (§9). The derived values are not a
second column of rows: they are the rows the Photosets block draws, as they are for the pack, so the
form's second column is the block and what the row has left is the photo area
(`ai/picking.md` §7). They are drawn in the order the field list gives them, so the count the pick wrote
is the row after the count the scan took. Because the block is this type's second column, the Torrent
section is at the end of it, below the block (`ai/torrents.md`). There is no second image box, because
there is no video to take a frame from, and the form titles only its first column, because the block
titles itself and the area titles itself.

## 4. Labels become per type

`fieldLabel(name, l10n)` is one function for every type, so a reused name has one label. For this
type the words are *Model* and *Set name*, not *Cast* and *Video title*, so `fieldLabel` takes the
release type and resolves those two per type. It is called by the editor's form, the Stash section and
the Video pack section, so its signature took the type; what it returns for the other types does not
change. The Stash section has no release to ask, so the type is passed to it; it is rendered for the two
types whose field list names the scene link, a single video and a single photoset (§9).

The same applies to the strings the Photosets block shows. "Photo packs" and "Pick the folder with the
photosets" read wrong for one set, so the strings are resolved per type as
well, by `photosetStrings()` in `photoset_group.dart` — one switch over the type, no table, the same
shape as `_sourceLabel` in the editor. The three keys that were named for the pack were given pack names, because they are no
longer the only ones. The Scan and Pick buttons, the count line and the report lines keep their existing
wording, because they say the same thing for one set as for many. The words a run's progress is said with
are part of the same switch: the pick counts photos, which is the same measure for one set as for many,
so it is one set of words; the scan counts the sets it found, and that reads wrong for one item, so it is
null for this type and the block draws nothing (`ai/picking.md` §7). The title of the photo area is not
one of these: what the area shows is the pictures, so it says the word the other area that shows the same
pictures says, for both types. And there is no title for the block's column, because the block titles
itself rather than being titled by the form, so the key that named that column is gone (`ai/picking.md`
§7).

The source row needs its own key: *Folder with the photos*, distinct from *Folder with the
photosets* — the row label is per type today (`ai/doc.md` §2), and this is one more arm of it.

## 5. The scan

The same scan, called only when the user asks: opening a release is a read and changes nothing.

The only thing that differs is the item-boundary rule, which is the open question
`ai/release_structure.md` §9 names. This is the first type that forces an answer:

- **pack**: the entries directly under the source are the items;
- **single photoset**: the source itself is the item.

So the scan is given the rule per type rather than holding one. It decides both what the items are and
where a reader reads from: for this type the reader is called on the source, not on an entry inside
it. Everything else is unchanged — the reader interface, the extension list, the header reader, the
order the source gives, and the reports for what it could not take.

A subfolder inside the set is not read, as for a pack (`ai/photoset_pack.md` §9): the question of
whether a photoset may contain subfolders is still open, so the reader does not decide it by accident.
With the source as the set, this is the first case where a set is likely to have one. It is left out
rather than reported, because the report is for entries the scan looked at and could not take, and a
subfolder inside a set is not an entry the scan looks at.

The values it counts go through the editor's single write path; the item it records is the scan's own
output, as for a pack.

## 6. The picking

`ai/picking.md`, unchanged. With one set the rule degenerates at every point, and the degenerate case
is the same rule:

- the popup is the same for this type as for a pack for the two things it can decide here — the count
  and the extremes — but not for the strategy: with one set the two answers are the same, so there is
  nothing to choose and the row is not drawn for this type (`ai/picking.md` §7). The answer carries the
  strategy the popup opens with, which is what both answers give for one set;
- the count row is the same here, with `total` meaning this set's own size: it opens at the curve's
  value and can be raised to the smaller of 100 and what the set has, and for a set of 5 or fewer the
  two are the same number, so there is nothing to choose and the row is not drawn (`ai/picking.md` §1);
- the whole of the count goes to the one set, because its share is the whole of the count, and the
  choice of strategy cannot change that: the second strategy places the count over the whole array,
  and with one set the whole array is that set. So the two answers are the same here, and the choice
  is not shown — a type is not shown a part of the popup it has nothing to decide in;
- the positions inside the set are the interval centres, as the rule defines them;
- the extremes are the same two photos the rule looks for in a pack, and with one set both are inside
  it, so the swap that keeps the count is the same swap.

So a set of 30 photos shows 5 when the popup is answered with what it opened at, and a set of 1200
shows 50. There is no floor per set, so a set is not guaranteed a place in the post — with one set the
count is what the user asked for, and a count below what the set has is what it shows. The picker is
not changed for this type, and its tests already cover the single-set case as a pack of one.

The picked photos are copied into the release, mirroring the structure the user picked, and recorded as
`kind: photo` with `item` set to the item path — the Upload section's progress bars count them
unchanged. The run writes the preview thumbnails here as it does for a pack, because nothing in that rule
branches on the type (`ai/picking.md` §8): a tile shows the thumbnail when the file is there, and the
photo itself when the run skipped the photo, could not write the thumbnail, or the tool is not installed.

## 7. The block

For a single photoset the block is the page's second column, at the most the width this feature
gives it, and the picked photos are the photo area beside it — the same two widgets the pack has,
with the same drawing (`ai/picking.md` §7). The block is its heading with the Scan and Pick buttons
at its right, the rows the editor gives it, and nothing below them, as it is for the pack: there is
no header naming a list and no row naming its columns, because no type draws a list, so the words a
list would need are not in the strings for either type (`ai/picking.md` §7). Its tiles keep one
label line: the line naming the set is drawn only where the grid mixes sets, and here there is one
set, so a tile has nothing to say about which set its photo is from. The grid is split by kind, as
it is for the pack, and the columns are capped at the same width, because the drawing is one
implementation for both types (`ai/picking.md` §7). Nothing here is tinted, because nothing in this
feature is a table (`ai/picking.md` §7).

The block titles itself with the word for one folder of photos, while the area titles itself with the word
the picture area has for both types, so the only title the form has is the first column's
(`ai/picking.md` §7, `ai/single_photoset.md` §4).

Re-picking writes the same names, so the cache has to be evicted and the tiles keyed with a key that
changes on each run, as `AGENTS.md` §5 requires. The key cannot be a widget's counter here, because the
pictures are in another widget, so the generation is the state the editor holds and it moves on each photo
the run writes rather than once per run, as `ai/picking.md` §7 says — the same rule the poster follows.

A row for a run going now is drawn here only for the pick, for the reason §4 gives: the scan counts
the items, and here the item is the folder the user picked, so a row counting items says nothing.
The pick row is the shared one, and the photos shown are the ones the run has copied so far, so a
tile appears when its file is written rather than when the run ends. The count the run answers with
is what it copied, and it is handed to the editor's write path at the end of the run, where the
field's row reads it (`ai/picking.md` §7).

## 8. The message

This is the first pack type the current renderer can render, because there is nothing to iterate over:
one set, so the post is the field block plus the image block, and the image block is already built in
`MessageController` — a photo is an image in the post like a screenshot is (`ai/picking.md` §7).

The template is `assets/templates/pornolab/singlePhotoset.txt`, named by the enum value as every
template is.

The title is the part that changes. `ai/description_template.md` had one title file per tracker, and
that file writes `videoType` and `videoQuality`, which this type has no values for — it would render
empty parts. So the title becomes per type: `assets/templates/<tracker>/<releaseType>.title.txt`, with
the tracker's `title.txt` as the fallback for a type that has none. That is a change to
`TemplateStore` and to `ai/description_template.md`.

```
[{{siteOrJournal}}] {{productionDate}} {{cast}} - {{videoTitle}} [{{genreTags}}] [{{resolutionMinMax}}, {{totalPhotoCount}} фото]
```

The count in the title reads `totalPhotoCount` rather than the item's `photoCount`, because a
per-item value is not one a template can read (`ai/release_structure.md` §3); for this type the two
are the same number. `{{resolutionMinMax}}` is the value the render builds from the two resolution
fields (§3), and `{{additionalInfo}}` is the optional line §3 lists. A template with a variable the
render does not provide produces nothing, which is what the title would have done for both.

The block titles stay as they are: the code writes *Скриншоты*, and a photoset post uses the same
word. That is the decision `ai/description_template.md` §Open items names, and it is taken here as "no
change".

## 9. The Stash row

The row is drawn for this type as it is for a single video: the first row of the form's first
column, under the poster box (`ai/release_editor.md`). It is the widget the `sceneUrl` field has, and
the editor draws it for the types whose field list names that field, so the field list is what decides
this rather than a check on the type. A pack has no row, because a pack is not one scene, and the video
pack has the name in its per-item list, not in the form's.

The values the popup offers are the names this type's field list has. `StashController` states which
values a scene can answer for, and the field list says which of them this type has, so the same rule
writes the value and the name it is written into is the type's:

| What the popup offers | What it writes |
| --- | --- |
| the model | `cast` |
| the set name | `videoTitle` |
| the site | `siteOrJournal` |
| the date | `productionDate` |
| the tags | `genreTags` |
| the description | `description` |

The site is the value the single video's `subsiteAndSite` gets — the studio's domain, and the parent's
after it when it has one, the two separated by " / " — written into this type's one site field. A value
the type has no field for is not offered: there is no site number here, so nothing is written for it.
The fields the app fills, and `additionalInfo`, are not values a scene answers for, as they are for the
other type, and the poster goes through the poster path rather than the field path.

The number is still cut from the title. For a single video the reason is that the number is a field of
its own, so a title that contains it says the same thing twice; this type has no field for the number,
and the number is still cut, because the set name is the title without it — so a title that contains the
scene's code is a value the import changed, and the popup lists it under "Import notes". A note names
the field the value is written into, so for this type it names `siteOrJournal` and the set name rather
than the single video's names: the message is the same key, with the label this type's words resolve to
(§4).

The values are listed in the order the type's field list lists them, and that is the order the popup
shows them in and the order its notes are in. For this type that is the site first, then the model, the
set name, the date, the tags, the description — the same order the field list writes the values in,
which is what the block's rows follow (§3). What a single video shows does not change, because its field
list already listed the values in the order the popup showed them.

The section takes the type for its labels and the field list for its names: the widget builds the field
list for the type it is given and passes it to the controller, as the photoset controller is given one
(`ai/release_structure.md` §3).

## 10. What changed in code

1. `release_type.dart` — the enum value, and the `releaseTypeLabel` arm.
2. `release_fields.dart` — `singlePhotosetFieldList`, the `imageFormats` label, `hasField`, and
   `fieldLabel` taking the release type (§4).
3. `release_editor.dart` — the source row label, and the arms of the switches for the field list, the
   column titles and the section list. The placement is one arm for both photoset types: the block is the
   page's second column and the pictures are the space after it (`ai/picking.md` §7), so there is nothing
   here that says which of the two it is drawing. All of these are exhaustive switches over `ReleaseType`,
   so the compiler named the places a new type had to be handled.
4. `lib/service/photosets/photoset_scanner.dart` — the item-boundary rule per type (§5), carried on the
   field list as `itemBoundary`, and `SourceEntry.readPath`, so a picked file is not joined to the
   source twice. The readers and the header reader do not change.
5. `lib/feature/photosets/` — the controller writes the formats field, keeps the values it returns to
   the names the type has, and writes the preview thumbnails with the same rule the pack's run has; the
   block shows the set with the per-type strings, and the pictures are drawn by the same area the pack
   uses (`ai/picking.md` §7, §8).
6. l10n keys in both arb files: the type label, the source row label, the two field labels, and the
   block's strings for this type. The pack's own keys were renamed to say they are the pack's,
   because they are no longer the only ones. The key that named the block's column was taken out,
   because the block is not a column the form titles (§4).
7. `assets/templates/pornolab/singlePhotoset.txt`, and `TemplateStore` reading the title per type with
   the tracker's file as the fallback.
8. Tests: the form for the type, the scan with the source as the item, the formats field, the
   block's strings, the drawing that is the same as the pack's, the placement of the block and the photo
   area, and the title template of the type with the tracker's as the fallback.
9. `release_fields.dart` — `sceneUrl` on this type's field list, with no row the form builds, because its
   row is the Stash row's (§3, §9).
10. `lib/feature/stashdb/` — `StashController` is given the field list, so the names it offers are the
   ones this type has and an import note names the field a value is written into; the rules that write the
   values are the same for both types, including the number being cut from the title (§9). The widget
   builds the field list for the type it is given and passes it to the controller.
11. `release_editor.dart` — the scene link row is drawn for the types whose field list names the field, so
   the field list is what decides it here rather than a check on the type (§9).
12. Tests for §9: the names offered per type, the values written under the names this type has, a note
   naming the field this type has, the popup showing this type's words, and the row as the first row of
   the form's first column.

The picking rule does not change for this type, and its tests already cover a single set as a pack of
one. The drawing is one implementation for both types, so nothing in it knows which type it is drawing:
the two widths, the split by kind and the cap on the share are the same here as for a pack
(`ai/picking.md` §7). What differs is what a tile says, because a grid with one set does not name the set
on its tiles (§7).

## 11. Open questions

- Whether a photoset may contain subfolders — the same open question as for packs, and this type is
  where it is most likely to appear.
- Whether the app copies the picked photos into the release or uploads them from the source — the same
  open question as for packs.
- Whether the picking numbers are constants or tracker config (`ai/picking.md` §4).
- Whether `imageFormats` is sorted alphabetically, as `videoFormats` is, or by how many photos of each
  format the set has. Alphabetical is assumed here because it is the rule that already exists.
