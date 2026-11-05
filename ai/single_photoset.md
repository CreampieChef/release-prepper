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

Resolution is compared by pixel area, as for a pack, and a resolution value is written as
`WIDTHxHEIGHT`. `imageFormats` is the distinct extensions among the counted photos, lowercased and
sorted alphabetically, joined with `, ` — the same rule as `videoFormats` (`ai/video_pack.md` §4). A
photo whose header cannot be read is still counted, because the extension list is what decides what a
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

The same applies to the strings the Photosets section shows. "Photo packs", "There are no photosets" and
"Pick the folder with the photosets" read wrong for one set, so the section's strings are resolved per
type as well, by `_strings()` — one switch over the type, no table, the same shape as `_sourceLabel` in
the editor. The three keys that were named for the pack were given pack names, because they are no
longer the only ones. The Scan and Pick buttons, the count line and the report lines keep their existing
wording, because they say the same thing for one set as for many.

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

- `N = min(total, clamp(ceil(5% × total), 5, 50))`;
- the whole of N goes to the one set, because its share is the whole of N;
- the per-set floor cannot bind, because a set that has photos has a share of at least one;
- the positions inside the set are the interval centres, as the rule defines them.

So a set of 30 photos shows 5, and a set of 1200 shows 50. The picker is not changed for this type,
and its tests already cover the single-set case as a pack of one.

The picked photos are copied into the release, mirroring the structure the user picked, and recorded as
`kind: photo` with `item` set to the item path — the Upload section's progress bars count them
unchanged.

## 7. The section

The Photosets section is the same widget, not a new one and not a different layout: Scan and Pick, the
set with its count, the picked photos as a masonry, and what the scan or the pick could not take. With
one item the grid holds one card. The layout does not branch on the release type; only its strings do
(§4).

Re-picking writes the same names, so the section needs the cache eviction and a key that changes on
each run, as `AGENTS.md` §5 requires — the rule the section already follows.

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
   to the names the type has, and the section shows one card with the per-type strings.
6. l10n keys in both arb files: the type label, the source row label, the two field labels, and the
   section's strings for this type. The pack's own keys were renamed to say they are the pack's,
   because they are no longer the only ones.
7. `assets/templates/pornolab/singlePhotoset.txt`, and `TemplateStore` reading the title per type with
   the tracker's file as the fallback.
8. Tests: the form for the type, the scan with the source as the item, the formats field, the
   section's strings, and the title template of the type with the tracker's as the fallback.

The picking rule and the masonry are already written and tested; they do not change.

## 10. Open questions

- Whether a photoset may contain subfolders — the same open question as for packs, and this type is
  where it is most likely to appear.
- Whether the app copies the picked photos into the release or uploads them from the source — the same
  open question as for packs.
- Whether the picking numbers are constants or tracker config (`ai/picking.md` §4).
- Whether `imageFormats` is sorted alphabetically, as `videoFormats` is, or by how many photos of each
  format the set has. Alphabetical is assumed here because it is the rule that already exists.
