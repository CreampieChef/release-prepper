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

`additionalInfo` is not in this list: the type's fields are the ones above, and a field with no row
and no value would be stored but never written.

App-generated, at the release level:

| Field | Meaning |
| --- | --- |
| `totalPhotoCount` | the number of photos in the set |
| `totalSize` | the size the counted photos have in the source, summed |
| `minResolution` | the smallest photo by pixel area |
| `maxResolution` | the largest photo by pixel area |
| `imageFormats` | the distinct formats among the counted photos |

App-generated, at the item level:

| Field | Meaning |
| --- | --- |
| `photoCount` | the number of photos in this set |

`photoCount` and `totalPhotoCount` are the same number here, and both are kept on purpose: the scan
writes the item's value, the section shows the count per set, and the aggregate is the name the pack
already has. Dropping either would make one of the two read the other.

Resolution is compared by pixel area, as for a pack, including the tie that decides which of two
equal photos is reported (`ai/photoset_pack.md` §3), and a resolution value is written as
`WIDTHxHEIGHT`. `totalSize` is the same name and the same rule as the pack's (`ai/photoset_pack.md`
§3): the sizes the counted photos have in the source, summed — with one item that is the set's own
total. `imageFormats` is the distinct extensions among the counted photos, lowercased and sorted
alphabetically, joined with `, ` — the same rule as `videoFormats` (`ai/video_pack.md` §4). A photo
whose header cannot be read is still counted, because the extension list is what decides what a
photo is, and it is reported.

The derived values describe **the source as scanned**, not the photos the picking rule chose: the post
reports the set's stats, and the sample is what the post shows, not what it measures.

The poster is not a field. It is the poster box every type has (`ai/doc.md` §5).

The form is the two columns the other types have: the user fields on the left with the poster box
above them, the derived values on the right. There is no second image box, because there is no video
to take a frame from.

## 4. Labels become per type

`fieldLabel(name, l10n)` is one function for every type, so a reused name has one label. For this
type the words are *Model* and *Set name*, not *Cast* and *Video title*, so `fieldLabel` takes the
release type and resolves those two per type. It is called by the editor's form, the Stash section and
the Video pack section, so its signature took the type; what it returns for the other types does not
change. The Stash section has no release to ask, so the type is passed to it — it is only ever rendered
for a single video.

The same applies to the strings the Photosets block shows. "Photo packs", "There are no photosets" and
"Pick the folder with the photosets" read wrong for one set, so the strings are resolved per type as
well, by `photosetStrings()` in `photoset_group.dart` — one switch over the type, no table, the same
shape as `_sourceLabel` in the editor. The three keys that were named for the pack were given pack names, because they are no
longer the only ones. The Scan and Pick buttons, the count line and the report lines keep their existing
wording, because they say the same thing for one set as for many. The words a run's progress is said with
are part of the same switch: the pick counts photos, which is the same measure for one set as for many,
so it is one set of words; the scan counts the sets it found, and that reads wrong for one item, so it is
null for this type and the block draws nothing (`ai/picking.md` §7).

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
unchanged. No preview thumbnail is written for this type, so the tile that draws one shows the photo
itself: the fallback of `ai/picking.md` §8, which is what this type did before the pack's run started
writing them.

## 7. The block

For a single photoset the block is the whole feature, because there is no space beside it for its
  pictures: Scan and Pick in its heading row, the set with its count, and the picked photos with the
  same grid drawing the pack uses, at the whole width, at the same two widths the feature gives it
  (`ai/picking.md` §7). There is no header naming a list above the line, and no row naming its
  columns, because one item is not a list (`ai/picking.md` §7). It is not split by kind, because
  with one item the grid holds one set and there is nothing to group, so its photos are in the order
  the source gives them, and a tile there labels itself with its file name only: the block names the
  set above the photos, so there is nothing for a tile to say about which set it is from. The band
  rule for the lines (`ai/picking.md` §7) shows nothing here: there is one line, and the first is
  not tinted.

Re-picking writes the same names, so the block needs the cache eviction and a key that changes on each
run, as `AGENTS.md` §5 requires — the rule the feature already follows. Here that key can be the
block's own counter, because the block is the widget that shows the pictures; for a pack it cannot be,
because the pictures are in another widget (`ai/picking.md` §7). The block is one implementation, so both
types use the state the editor holds, and the key moves on each photo the run writes rather than once per
run, as `ai/picking.md` §7 says.

A row for a run going now is drawn here only for the pick, for the reason §4 gives: the scan counts the
items, and here the item is the folder the user picked, so a row counting items says nothing. The pick
row is the shared one, and the photos shown are the ones the run has copied so far, so a tile appears when
its file is written rather than when the run ends, and the count on the line is the count of what is
shown (`ai/picking.md` §7).

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
[{{siteOrJournal}}] {{cast}} - {{videoTitle}} [{{productionDate}}, {{genreTags}}]
```

The block titles stay as they are: the code writes *Скриншоты*, and a photoset post uses the same
word. That is the decision `ai/description_template.md` §Open items names, and it is taken here as "no
change".

## 9. What changed in code

1. `release_type.dart` — the enum value, and the `releaseTypeLabel` arm.
2. `release_fields.dart` — `singlePhotosetFieldList`, the `imageFormats` label, `hasField`, and
   `fieldLabel` taking the release type (§4).
3. `release_editor.dart` — the column layout, the source row label and the section arm. All three are
   exhaustive switches over `ReleaseType`, so the compiler named the places a new type had to be
   handled.
4. `lib/service/photosets/photoset_scanner.dart` — the item-boundary rule per type (§5), carried on the
   field list as `itemBoundary`, and `SourceEntry.readPath`, so a picked file is not joined to the
   source twice. The readers and the header reader do not change.
5. `lib/feature/photosets/` — the controller writes the formats field and keeps the values it returns
   to the names the type has, and the block shows the set with the per-type strings.
6. l10n keys in both arb files: the type label, the source row label, the two field labels, and the
   block's strings for this type. The pack's own keys were renamed to say they are the pack's,
   because they are no longer the only ones.
7. `assets/templates/pornolab/singlePhotoset.txt`, and `TemplateStore` reading the title per type with
   the tracker's file as the fallback.
8. Tests: the form for the type, the scan with the source as the item, the formats field, the
   block's strings, and the title template of the type with the tracker's as the fallback.

The picking rule does not change for this type, and its tests already cover a single set as a pack of
one. The grid the block draws with does change — the two widths, and the split by kind — but one set is
never split, so the grid here is the one zone that is the whole space (`ai/picking.md` §7).

## 10. Open questions

- Whether a photoset may contain subfolders — the same open question as for packs, and this type is
  where it is most likely to appear.
- Whether the app copies the picked photos into the release or uploads them from the source — the same
  open question as for packs.
- Whether the picking numbers are constants or tracker config (`ai/picking.md` §4).
- Whether `imageFormats` is sorted alphabetically, as `videoFormats` is, or by how many photos of each
  format the set has. Alphabetical is assumed here because it is the rule that already exists.
