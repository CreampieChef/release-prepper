# Photoset pack

**Design. The field list, the form, the scan, the header reader, the two readers and the photosets
section are implemented; the picker and the template are not.** This is the fourth release type,
after Single video, the video pack and the single photoset. It follows `ai/release_structure.md`:
the containers are one shape for every type, and a new type is a field list plus a template. When
the rest is implemented, `ai/doc.md` §7 is rewritten in the same change, as the project rule
requires.

## 1. One release type, not two

A photoset may be a folder or an archive. That is not two release types, for two reasons.

**The distinction is per item, not per release.** The user picks one folder that contains
photosets, and within it some photosets are folders and some are archives. A release type
describes the release, so it cannot describe each item: a mixed pack would need two types at
once.

**The data is the same either way.** Item list, image records, field list — one shape. Only the
reader that produces the files differs, and `ai/release_structure.md` §1 says a difference that
exists only in the code that produces the files must not be encoded in the format. Two types
would duplicate the field list, the template, the l10n labels and the dropdown entry for a
distinction the post never shows.

So: one release type, `Photoset pack`, one item type `photoset`. The container kind is something
the scan observes while it reads the source; nothing after the scan depends on it, and a re-scan
can re-derive it from the filesystem. This is the same reasoning as "provenance is not data"
(`ai/release_structure.md` §4).

## 2. The source and the items

- `source` is the picked folder, as it is for every type. Item paths are relative to it.
- **An item is a photoset**: a directory or an archive directly under the source. Its `type` is
  `photoset`, recorded at scan time.
- **The item path is the real relative path** — `set01` for a folder, `set01.zip` for an archive.
  It is the ID the image records link to (`ai/release_structure.md` §2), so it keeps the extension.
- **The name without the extension is derived for display, not stored.** Storing it would make
  `set01.zip` and `set01/` collide on one ID. The list of photosets the app shows is the item
  list with the display name derived from each path.
- The two namespaces stay as they are: item paths are paths in the source, image record paths are
  paths inside the release. A mirrored folder in the release carries the display name; that is not
  a conflict, it is the two namespaces working as designed.

## 3. Field list

`photosetPackFieldList`, behind `FieldList`. Names are the names `release.json` writes.

User-provided, at the release level:

| Field | Meaning |
| --- | --- |
| `siteOrJournal` | the site or journal name |
| `period` | the period the set covers |
| `genreTags` | the tags — the existing name, reused |

`genreTags` is reused rather than renamed so the tags and the fill-from-items button work
unchanged. `siteOrJournal` and `period` are new: a journal is not a subsite, and a period is not
a production date.

App-generated, at the release level:

| Field | Meaning |
| --- | --- |
| `photosetCount` | the number of items |
| `totalPhotoCount` | the number of photos across all items |
| `minResolution` | the smallest photo by pixel area, across all photos |
| `maxResolution` | the largest photo by pixel area, across all photos |

App-generated, at the item level:

| Field | Meaning |
| --- | --- |
| `photoCount` | the number of photos in this set |

Resolution is compared by pixel area, not by a side, and it is aggregated at the release level
only — there is no per-set min/max. A resolution value is written as `WIDTHxHEIGHT`.

The scan also counts the distinct extensions among the photos it counted, lowercased and sorted.
That is the value the single photoset has (`ai/single_photoset.md` §6); this type's field list does
not have the name, so the controller keeps the values it returns to the names its type has.

The field list carries a marker for "the app fills this, the user cannot edit it" — `filledByApp`,
the general form of what was a set of video-only names. This is the first type that needed the
per-type field lists `ai/release_structure.md` §7 item 2 asks for, because the editor, the store,
the Stash section and the message all hardcoded one type's names before it existed.

Two things follow from the editor becoming type-driven:

- The Stash section is a video feature — a photoset is not a StashDB scene — so it is not shown
  for this type.
- The Screenshots section is replaced by the picked-photos section, so the editor's section list
  and its image boxes are per release type. The thumbnail box is a video box, so a pack form has
  the poster box and no second box.

## 4. The scan

A service under `lib/service/`, called only when the user asks: opening a release is a read and
changes nothing (`ai/release_structure.md` §4).

It reads the picked folder, decides which entries are items — the rule is given to it per type
as `ItemBoundary`, and for this type it is the entries under the source (`ai/single_photoset.md`
§5) — and for each item enumerates its photos, counts them and reads their dimensions. It writes
the items with `type: photoset` and the generated fields, and the aggregate values at the
release level.

The rules it is written to:

- **What counts as a photoset.** A directory or an archive directly under the source. A loose
  image at the top level is not an item — reported, not guessed at. A subfolder inside a set is not
  read: whether a photoset may contain subfolders is still open, so the reader does not decide it by
  accident.
- **What counts as a photo.** The extension list `jpg`, `jpeg`, `png`, `webp` — the same set as the
  formats the header reader understands, so a file is never counted as a photo and then left
  unmeasured. Files outside it are ignored, not counted.
- **Order.** The order the source gives, as §4 already defines it: for an archive the order of its
  entries, for a directory the order a file manager shows, which is by name.
- **Display names can collide.** `set01.zip` and `set01/` both read as `set01`. The scan reports
  it; it does not rename anything. With directories only this cannot happen, so the report comes
  with the archive reader.
- **A photo whose header cannot be read** is still counted, because the extension list is what
  decides what a photo is, and it is reported. A set with nothing measurable has no minimum or
  maximum, so no value is written for it.

Reading dimensions without a package: a small header reader for JPEG, PNG and WebP. It reads only
the header — JPEG's start-of-frame marker, PNG's IHDR, WebP's three chunk types — and does not
decode the image. The alternative is one `ffprobe` call per photo, which is a few lines but
hundreds of processes for a real pack. The header reader is the choice.

## 5. Archives

ZIP only, for PornoLab, through the `archive` package. This is the one place where rule 12 is set
aside, and the reason is not convenience: the parts a hand-written reader gets wrong are the ones
real archives have — zip64 when the plain end-of-central-directory record holds placeholders, data
descriptors from a streaming writer, encrypted entries. A hand-written reader was tried against
real archives first and works for the plain cases, so this is a considered exception rather than a
default. Rule 12 in `ai/doc.md` lists `archive` as the package used for reading archives and for
nothing else.

What the scan needs from it:

- the entry names, in the order the archive lists them, for the count and for the order the
  records are written in;
- the first bytes of each entry, for the dimensions;
- the entry itself, for the photo that is copied into the release.

The reader reads the central directory through the package and then only the bytes the header needs:
a stored entry is read as it is, a deflated one is decoded lazily. Reading a whole entry is what
reading headers exists to avoid. It is called more than once for one entry — a fixed prefix, then
more, because a JPEG's frame marker can be preceded by metadata — so each call starts from the
beginning of that entry again rather than from where the previous read ended. The package's lazy path
does decrypt, so an encrypted entry is read
as well, but only with a password, which the app does not have, and entries stored with another
method are not decoded — a ZIP of photos is stored or deflated, because JPEG, PNG and WebP are
already compressed. Both give the header reader bytes it cannot read, and the photo is counted and
reported, as §4 says.

The reader is behind an interface so a format can be added without changing the scan. RAR and 7z
are not in scope: they need a real decoder, not a container parser, so they would mean an external
tool as a new required native tool.

## 6. The picker

Implemented. The rule is `ai/picking.md`; the seam defined here is what the code follows:

- A selector takes the scanned items and a rule and returns the photos it picks.
- The picked photos are copied into the release, mirroring the structure the user picked
  (`ai/release_structure.md` §4), and recorded as `kind: photo`.
- The section shows them in place of the screenshots, grouped per set (`ai/picking.md` §7).
- The scan runs before the picker, because the picking reads the counts. The resolutions are not
  part of the rule (`ai/picking.md` §4).

The rule, the distribution and the section are decided in `ai/picking.md`. Copying is what the code
does, as `ai/release_structure.md` §4 says; whether it should upload from the source instead is §9.

## 7. The message

A pack post lists items individually, which needs iteration over a list in `TemplateRenderer` —
the one genuinely new capability `ai/description_template.md` §5 names. It is also the first case
where building the block in code is no longer acceptable, because the block is grouped per
photoset rather than flat.

So this type is where the tracker config stops being a future idea: the grouping rule, the block
titles, the hoster and the URL types. Either the config is built now, or the pack block is
hardcoded as the first version is today. That is a decision, not an implementation detail.

The template is `assets/templates/pornolab/photoset_pack.txt`. The pack has no title file of
its own, and the tracker default no longer exists — it was the single video type's template,
moved to the per-type path (`ai/description_template.md` §Title) — so the pack's title is
empty.

## 8. What changes in code

Done:

1. `release_fields.dart` — `FieldSpec` and `FieldList`, the "filled by the app" marker, the two
   field lists, the registry the wizard's option list reads, and `fieldLabel` for the names the
   widgets show. The item-level field list is part of `FieldList`, because the field list decides
   which level a value lives at.
2. `release.dart` — the item types moved to the field lists that produce them.
3. `release_editor.dart` — the form renders a field list; the sections and the image boxes are per
   type; the Stash section is not shown for a pack.
4. `release_store.dart` — a new release gets the defaults of its type's field list.
5. `lib/service/images/image_dimensions.dart` — the header reader, and the extension list. The
   header bytes come through a function rather than a path, so a file and an archive entry read
   through the same format dispatch.
6. `lib/service/photosets/` — the scan behind the reader interface, and one file per reader:
   `directory_reader.dart` and `zip_reader.dart`.
7. `lib/feature/photosets/` — the controller, the block that lists the photosets with their counts,
   the area that draws the picked photos in the page's columns, and the state and the drawing helpers
   the two share.
8. l10n keys in both arb files, and the tests for the pack form, the header reader, the scan and
   the block and the area.
9. `zip_reader.dart` — the ZIP reader through the `archive` package, and `pubspec.yaml` with it;
   rule 12 in `ai/doc.md` now lists `archive` as the package used for reading archives and for
   nothing else. The display-name collision report comes with it, since with directories only it
   cannot happen.

Left:

10. `message_controller.dart` — iteration and the grouping rule.
11. `template_renderer.dart` — iteration over a list.
12. The per-item forms in the editor (`ai/release_structure.md` §7 item 11).

## 9. Open questions

- Whether a photoset may contain subfolders. The reader does not read them, so a set is the files
  directly inside it until this is decided.
- Whether the app copies the picked photos into the release or uploads them from the source. The
  structure spec says copy; the cost is disk space and a source that may be gone later.
- Whether the item record needs the container kind. It does not, unless a re-scan has to work
  after the source is gone.
- The picking rule is decided in `ai/picking.md`, including that the per-set minimum applies to every
  pack. What is not: whether the numbers are constants in the code or values the tracker config holds.
- The tracker config, or the block hardcoded for this type.
- Display-name collisions: report or reject. The scan reports what it cannot take, so reporting is
  the pattern; the case itself only appears with the archive reader.

## 10. Order

1. The field-list interface and `PhotosetPackField`; the editor renders a field list generically.
2. The scan for directories, and the photosets section.
3. The ZIP reader.
4. The picker.
5. The message: iteration and the grouping rule.
