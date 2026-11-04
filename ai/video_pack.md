# Video pack

**Partly implemented: the field list, the form, the scan and the section are, including the videos as a
table with expandable rows, the slider and the button that generate the images, and the table's flag
columns for the screenlist and the screenshots; the per-item form that edits those values, the images in
the expanded detail, the flag column for the additional data, and the message are not.** This is the
second release type, after Single video. It follows `ai/release_structure.md`: the containers are
one shape for every type, and a new type is a field list plus a template — plus a scan,
because this type's derived values come from files rather than from a form.

`ai/doc.md` describes what exists now (§2, §3, §5, §6, §7, §10). What is described here and not built
is the per-item form, the images in the detail, and the message; the order in §10 is the order they are
built in.

## 1. What this type is

The user picks one folder; the video files in it, including the ones in subfolders, are the
items.

It is not Single video with a longer item list, because two things differ:

- **The source is a directory**, so it yields many items rather than one.
- **The derived values are aggregates across the items** — a count, a set of resolutions, a set
  of formats — which Single video has no need for.

What stays the same is the per-item data: what ffprobe reports for one file. That is why the
item field list is the same set of names as Single video's, and why `MediaInfo` and `Ffprobe`
are reused rather than written again.

## 2. The source and the items

- `source` is the picked folder, as it is for every type. Item paths are relative to it.
- **An item is a video file.** A subfolder is a container, not an item: the scan walks the tree
  and every file the extension list accepts is an item. This answers the open question in
  `ai/release_structure.md` §9 for this type.
- **The item path is the real relative path**, `videos/first.mp4`, and it is the ID the image
  records link to (`ai/release_structure.md` §2). The structure the user picked is preserved in
  the ID, so `images/<item path>/` mirrors it.
- **Nothing is copied.** Videos are never copied into the release (`ai/release_structure.md` §4),
  so a video pack depends on the source staying where it is. A source that is gone or cannot be
  read is reported; the values already recorded stay. This is the cost the photoset pack's open
  question names, and for videos it is not optional: a video is too large to copy.
- **Order.** The scan walks each directory in name order, depth-first. Order only matters for
  what the scan reports, because the two aggregate lists are sorted (§4).
- A pack does not mix item types. Its items are all `type: video`.

## 3. Field list

`videoPackFieldList`, behind `FieldList`. Names are the names `release.json` writes.

User-provided, at the release level — all existing names, reused, so no new labels:

| Field | Meaning |
| --- | --- |
| `subsiteAndSite` | the site and subsite |
| `cast` | the actress name |
| `period` | the time period — the name the photoset pack introduced |
| `genreTags` | the tags |
| `description` | optional, as it is for Single video |
| `additionalInfo` | optional, as it is for Single video |

`cast` is the actress name rather than a new field: a credit is the same value, and reusing it
keeps the fill-from-items button working. `period` is reused for the same reason. `description`
and `additionalInfo` are in the list because the message reads them; a pack post has a
description.

App-generated, at the release level, in the order the field list writes them:

| Field | Meaning |
| --- | --- |
| `totalSize` | the size of the item files on disk, summed |
| `videoCount` | the number of items |
| `videoResolutions` | the distinct resolutions, sorted |
| `videoFormats` | the distinct formats, sorted |

The order above is the order the form's column shows them in, the total first, because the form
lists the aggregates in the order the field list writes them.

App-generated, at the item level — the same names Single video has:

| Field | Meaning |
| --- | --- |
| `fileSize` | the file size, as the byte count |
| `duration` | `hh:mm:ss` |
| `videoType` | the resolution, `2160p`, from the video height |
| `videoFormat` | the container ffprobe reports, `MP4` |
| `videoStream` | the video stream line |
| `audioStream` | the audio stream line |

Not in this field list yet: `siteNumber`, `videoTitle`, `sceneUrl`. They belong to the per-item form
that edits the values, which is not built (§8), and a field with no widget would be stored but never
written. The item list is expected to grow with the optional fields Single video has; that is the
next step, not an open question.

The two list aggregates are written as comma-separated strings, the same shape as `genreTags`.
`totalSize` is a byte count, the same shape as the item size field, so its row shows the human form
as well; which fields are byte counts is the `isByteCount` flag on the field spec, so the form reads
that rather than a list of names it knows.

## 4. The scan

A service under `lib/service/`, called only when the user asks: opening a release is a read and
changes nothing (`ai/release_structure.md` §4).

It walks the picked folder, decides which files are items, probes each one, and writes the items
with `type: video`, the per-item values, and the four aggregates at the release level.

The rules it is written to:

- **What counts as a video.** The extension list `mp4`, `mkv`, `webm`, `avi`, `mov`, `wmv`,
  matched case-insensitively. A file outside it is not an item and is reported by name, so an
  accidental file in the picked folder is visible rather than silently included.
- **The probe.** One `ffprobe` call per item, run one at a time with the existing per-call
  timeout. A real pack is tens of processes, which is why the scan is only run when the user
  asks and why it reports progress rather than pretending to be instant. Running the calls
  concurrently is an open question (§9).
- **A file that cannot be probed** is still an item — the extension list is what decides what a
  video is — with its fields left empty, and it is reported by name. One file does not fail the
  whole scan.
- **A folder inside the source that cannot be read** is reported by name and the walk continues, as
  an unreadable set is in `ai/photoset_pack.md` §4. It is not counted as an empty one, because the
  scan cannot say whether it had a video in it, so the aggregates are known to be incomplete when
  that list is not empty. Only the picked folder itself is a failure, because there is nothing to
  report when it cannot be read. A file that cannot be probed is reported too, and does not fail the
  scan.
- **An empty subfolder** is reported, as a set with no photos is.
- **Total size.** The byte counts the files have on disk, summed over the items. This is
  deliberately not the sum of the `fileSize` item fields: what the probe reports is what a container
  says its size is, which is not the same number as the file on disk, and a file the probe cannot
  read has no field value but does have a size. A file the walk cannot stat is not counted, so the
  total is known to be incomplete in that case, as the aggregates are when a folder could not be
  read. A file that cannot be stat'ed does not fail the scan, the same rule as a file that cannot
  be probed.
- **Resolutions.** The distinct `videoType` values across the items, sorted numerically by
  height (`720p, 1080p, 2160p`) — not as text, which would put `720p` after `2160p`. A video
  whose height ffprobe does not report is not in the list.
- **Formats.** The distinct extensions, lowercased, sorted alphabetically. This is deliberately
  not derived from the item fields: the post shows the format as the file name says, while the
  item line shows what the container actually is. A `.wmv` that is really an AVI container makes
  the two disagree, and that is accepted.
- **The aggregates are the scan's output.** They are recomputed on every scan, and editing an
  item value does not change them until the scan runs again.

The values the scan counts go through the editor's single write path; the items it records are
the scan's own output, because an item is what the scan produces.

## 5. The section

`VideoPackSection` is the section for this type, in place of the Screenshots section: a Scan
button, the slider and the button that generate the images, the videos as a table with one row
each, and what the two runs could not do, listed by name. Nothing is shown before a scan,
because opening a release is a read and changes nothing — but a release opened from a manifest
shows the items its file records, because those are what the file holds. The form itself shows
only the four aggregates.

- **The section is one form column wide**, which is what lets it be one of the form's columns
  for this type, as the Single video section is for its type (`ai/doc.md` §2); when there is no
  room for it as a column it is below the form instead, at the same width. A table is read at
  the whole width by the types whose section is a masonry, so this is the one table read at a
  column width, and the cost is that its value columns are about 48 px each there and a number
  such as a size wraps inside its cell. That is accepted, because the page is the same shape for
  the two video types.
- **The generate button's label is the short word**, because the title row is the title and the
  two buttons, and at one column width it cannot hold a title such as "Videos and screenshots"
  and a long label at the same time. The row is shared UI, so the fix is the label and not the
  row.

The table has a header row and one row per video. A row shows the name, the size, the duration, whether
the item has a screenlist and how many screenshots it has; clicking it shows the values the row does not.
Which values are in the row and which in the detail is the widget's layout, not the field list's order.

- **The name is the path relative to the source**, not a bare file name. The path is the record ID
  (§2), and two files in different subfolders can share a file name. For a flat folder the two are
  the same text.
- **The columns are named by the labels the fields have**, so the table and the form above it use the
  same words for the same values. The name column is not a field, so its header is its own key.
- **The size in a cell is the short form**, `9.5 GiB`, because a fixed-width cell cannot hold the byte
  count as well; the full form the size field uses is what the detail shows.
- **The value columns are right-aligned** so the numbers line up, and a header follows its own column;
  the name is not a number, so it is not aligned as one.
- **Every other row is tinted**, because a table read as bands of text is followed with the eye, and the
  rows have the padding that makes a band read as a band rather than as a line of text with a colour
  behind it. The tint belongs to the row, so it covers the detail as well: an open row that is half
  tinted reads as two rows. The parity is the position in the order the items are stored, so a re-scan of
  the same folder does not change a row's colour. The header is not a row, so it is not tinted.
  The tint is on the row's own `Material` and not on a plain container, because the hover highlight is
  painted on the canvas of the nearest `Material` ancestor and a container paints its colour over that;
  an untinted row is a transparent `Material` for the same reason, so every row is the same shape
  rather than two kinds of row.
- **A flag column shows a checkmark or a count**, and a count of 0 is shown as nothing, because a flag
  column that says 0 reads as an error rather than as an absence. The two flag columns read the same
  records the Single video section shows, so a column and a tile cannot disagree: the source of truth is
  `images.json`, and only a record whose file is on disk is shown.
- **The detail shows what the row does not show**, each value with the label its field has: the
  resolution, the format and the two stream lines. The stream lines are long, so they cannot be
  columns, and each needs a label to be read at all. The values that are in the row are not repeated in
  the detail.
- **The detail also shows the images the run wrote for that item**, in the same block: the screenlist at
  the detail's full width, because it is the summary of the video and a grid is as tall as its rows, and
  the screenshots as small tiles in a wrap, because an expanded row of a table that lists many items has
  to stay a row. Only the open row builds them, so a closed row costs nothing, and the names are not
  repeated under the tiles, because the row already names the item. Only a record whose file is on disk is
  shown, the same rule the flag columns follow.
- **A value the model does not have is shown as nothing**, because a file the probe could not read has
  none, and the report line says which files those are.
- **Which rows are open is widget state**, keyed by the item path, because the path is the record ID and
  stays the same across a re-scan of the same folder. Nothing is open by default, and a re-scan that
  removes a file leaves no stale entry. There is no animation, because the app has none anywhere.

The flag column for the additional data is not built, because it belongs to the feature that fills it
(§8); the table does not show a column that is always empty.

The tile is shared UI (`lib/feature/image_tile.dart`), because the Single video section, the photoset
section and this one show the same files the same way. Showing it here needs the image rule in full —
evict the cache entry for the path the app writes and give the `Image` a key that changes on each rewrite
(`AGENTS.md` rule 5) — which is what that file implements, so a row that shows a regenerated screenlist
shows the file as it is now rather than as it was decoded the first time.

The section shows the values without editing them: the per-item form that edits them is not built
(§8).

### Generating

The slider and the button below Scan generate the images for every item. The rules that write the files
are the service's (`lib/service/videos/image_generator.dart`, `ai/doc.md` §2); the
controller runs it per item and records what it wrote, because a record is a file plus the item it
belongs to, which is the feature's, not the tools'.

- **The slider here allows 0 to 20 and starts at 0.** The minimum is the section's, not the
  generation's: the Single video section keeps 3, because there the number is the set of frames a post
  shows. A run over many files can be asked to write only the screenlist, because mtn reads the video
  itself.
- **The button is disabled while the release has no items**, and there is no "Regenerate" variant,
  because the run replaces what it writes either way.
- **The run writes `images.json` once for the whole run**, in the order the scan recorded the items,
  because a pack is tens of items and one write per item would be tens of writes for one action the user
  asked for once.
- **A tool that is not available stops the run**, because it does not become installed while the app is
  open. A file that failed does not stop the next one, as one file does not fail the scan.
- **What the run could not do to individual files is a report line**, with the scan's lines, because a
  run that did most of them is not an error. What it could not do as a whole — a tool not installed, a
  manifest that could not be written — is a message, the same text the Single video section shows. A
  re-scan replaces the items, so the lines naming files that are no longer items are cleared with it, as
  the open rows are.

What the scan could not take is shown as lines in the section rather than as a message, because a
scan that ran and excluded files is not an error: the files outside the extension list, the files the
probe could not read, the subfolders with no video in them, and the folders the walk could not read.
Only the cases where nothing can happen at all — no source, a source that is not there, a source that
cannot be read — are messages, and those are the same three the photoset section uses.

When a folder could not be read the aggregates above the section are known to be incomplete, because
the scan cannot say what that folder contained. It says which folders it could not read rather than
presenting a count as a fact, so the form is not corrected to say so.

The report lines come after the videos, because they say what is not among them.

## 6. The form

Four columns when the window has room for them, as the Single video type's form is, and two when it
does not (`ai/doc.md` §2). The poster box, and no second box: a pack has no single video, so there
is no thumbnail. The Stash section is not shown — a pack is not one scene.

The four aggregate rows carry `filledByApp`, so they read as text the app wrote. Which fields are
in which column is the widget's layout, and the column lists them in the order the field list
writes them, the total first. The second column is the source row, the four aggregates and the
Torrent section at its end, and it is titled "Source folder" because it is the folder the user
picked and the values taken from it, not one value inside it; a single video's column in the same
position is named Video, because there the row is one video. The section is the third column when
there is room for it as one, and below the form at the same width when there is not.

## 7. The message

The post is the release block and the image block: the poster, the fields the user writes, the three
values the scan counted, and the image block. The items appear in the post only inside the image
block, which is built in code, so the template needs nothing the renderer does not already do, and
the values it reads are the release's own.

The template is `assets/templates/pornolab/videoPack.txt` and the title template is
`assets/templates/pornolab/videoPack.title.txt`. The words in them are the Russian words the app's
labels use for the same fields, so the two read as the rest of the tracker's templates do.

The image block is the part that names an item, so this type chooses its shape. The two shapes are
the ones in `ai/description_template.md` §Screenshot section: the default groups by hoster with one
group per item inside it, the other groups by item with the hosters inside. An item's group is
titled with the file name, the duration, the resolution and the size, and holds the two stream
lines before its images; the words for those lines are constants in `message_controller.dart`, not
l10n keys, for the same reason the block titles are.

The choice is made with a row of radio buttons at the top of the Message section, below its title,
and it is stored on the release as `screenshotLayout` in `release.json`. A file without the key
reads as the default, so a release written before the choice existed is not an error. The row is
drawn only for this type, because the two shapes name a video and the other types have no video to
name, so they keep the flat block. Choosing a shape is written through the editor's single write
path, which marks the tab
dirty and sends the notice that clears the box: the choice is part of what a render would produce.

Listing the items individually in the template itself is still open, with the photoset pack's: it
needs iteration over a list in `TemplateRenderer` (`ai/description_template.md` §5). The grouping
rule is decided for this type only, and stays open for the others.

Per-item screenshots and screenlists are the open item in `ai/release_structure.md` §7, and the
screenlist placement question in `ai/release_structure.md` §9 is still open for this type. The
per-item description and poster lines the second shape could show are the same open item: they
are what a per-video `stash_url` import would fill.

## 8. What changes in code

Done:

1. `release_type.dart` — `ReleaseType.videoPack`, and its arm in `releaseTypeLabel`.
2. `release_fields.dart` — `videoPackFieldList`, and the arms for the four aggregate names in
   `fieldLabel`. The reused names need no arms; they already have them. `fieldLabel` is also what the
   section uses for the two stream lines, so it is not only the form's function. The byte-count flag
   on `FieldSpec` is what the form's display rule reads, so the form does not switch on names.
3. `lib/service/videos/video_scanner.dart` — the walk, the extension list, the probe per file, the
   size each file has on disk as the walk reads it, and the aggregates. No reader interface: there
   is no container format to abstract here, only the filesystem, so an interface would be a
   speculative abstraction.
4. `lib/feature/video_pack/` — the controller and the section: the scan button, the table with
   expandable rows, and the reports. The controller reads the items back for the section, because the
   section shows what the release stores rather than what the last scan produced.
5. `release_editor.dart` — the column layout arm for the type, the column title for it, and the
   section list.
6. l10n keys in both arb files: `releaseTypeVideoPack`, `videoFolderLabel`, `videoPackSectionTitle`,
   `fileNameLabel` for the table's name column, `scanVideos`, `noVideos`, `totalSizeLabel`,
   `videoCountLabel`, `videoResolutionsLabel`, `videoFormatsLabel`, the four report keys for what the
   scan could not take, the three source messages, `columnTitleSourceFolder` for the column title, and
   `uploadNeedsScreenlistsFirst` for the placeholder. The last two are keys of their own rather than
   the shared ones, because a single video's column of the same position is called Video and its
   placeholder names the screenshots. `totalSizeLabel` is a key of its own rather than
   `fileSizeLabel`, because the total is the size of the whole folder rather than of one file. Every
   other field label is an existing key, and the table's other two column headers are those same keys.
   The source row label cannot come from `sourceKind` alone, because a folder with videos is a
   different thing to pick than a folder with photosets, so it is resolved per release type.
7. Tests: the field list, the walk, the extension list, the two sorts, the size the walk sums, the
   reports, the form, the rows the table shows, opening one, the column title, the order the
   aggregate rows are shown in, the size shown in the human form, and the upload gate for the type.
   The folder the walk could not read is not tested, as the photoset spec's unreadable entry is not:
   it depends on file permissions, which a test process may ignore. A file the walk could not stat
   is not tested either, for the same reason: it depends on the file being there when the walk
   reaches it.
8. `lib/service/videos/image_generator.dart` — the rules that turn one video file into the images the app
   writes: the key-frame times, the file names, the screenlist rows, the ffmpeg and mtn calls. It writes
   the files and reports what it wrote as paths relative to the release directory; it does not record
   them, because a record is a file plus the item it belongs to, which is the feature's. No service may
   import feature code, so each controller maps the files to records itself. `maxCount` is the shared
   rule; the minimum is each section's.
9. The controller runs the service for every item and records what it wrote in `images.json` once for the
   whole run; `imagesFor(item)` is what both the pack's flag columns and the Single video section show.
   The per-item result and the failure vocabulary are one shape both widgets map to text, with the
   `stopsRun` rule on the enum so the controller's loop and the widget's mapping read the same rule.
10. The section's slider (0-20), the generate button, the two flag columns, the right alignment, and the
    report line for the files the run could not do.
11. l10n keys for the generation: `generatePackImages`, `screenlistLabel`, `screenshotsLabel`,
    `imagesFailedFiles`.
12. `lib/feature/image_tile.dart` — the tile the three sections show the same way: the bordered box with
    the picture, the `Image` with the key that changes on each rewrite, and the cache eviction. Those are
    one rule (`AGENTS.md` rule 5), so they live in one file; the generation counter stays each widget's
    own state, because each widget owns its own re-resolve. The box height is a parameter because the
    photoset packing sizes the box, not the picture inside it.
13. The images in the expanded detail: the screenlist at the detail's full width, the screenshots as
    small tiles in a wrap, built only for the row that is open.
14. The message templates for the type: `assets/templates/pornolab/videoPack.txt` and
    `videoPack.title.txt`. The post is the release block and the image block, so it needs nothing
    the renderer does not already do.
15. `upload_controller.dart` — the gate as a per-type rule, because a run over a pack can be asked
    to write only the screenlist, and the words the placeholder says for it. The two photoset types
    and the image folder are read as the types they are, because their run has a photo rather than a
    screenshot.

Left:

16. The per-item form that edits the values, with the optional fields Single video has.
17. The flag column for the additional data.
18. The message listing the items individually: iteration in `TemplateRenderer` and the grouping
    rule.

The wizard's dropdown, the store, `images.json` and the tool layer need nothing: the type is a value
in the file, and the shape is already the one they read.

## 9. Open questions

- The first version runs the probe calls one at a time, as §4 says. Whether they should run
  concurrently is still open: sequential keeps the log in order and is simpler, and a large pack is
  slow.
- Whether a pack post lists a title per item, or only the file name (`ai/release_structure.md`
  §9).
- Screenlists for a pack: generated or accepted from the user, and where they are stored.
- Whether the aggregates should be left alone once the user has corrected one, as the block on
  regenerating an uploaded image works.
- Locking the source field once records exist (`lib/TODO.MD`), which matters more here than for
  a photoset pack because the items are the paths themselves.

## 10. Order

1. The field list and the form arm. Done.
2. The scan, and the section that reports what it could not take. Done.
3. The section listing the videos as a table with expandable rows. Done.
4. The generation and the table's flag columns. Done.
5. The images in the expanded detail. Done.
6. The per-item form that edits those values, with the optional fields Single video has.
7. The message: iteration and the grouping rule.
