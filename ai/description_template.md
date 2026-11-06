# Description message

The app builds the post text for a release from a **template** and a **style**, shows it
in a new **Message** section below Upload, and stores it as `message.txt` in the release
directory.

The template is the structure. The style is the appearance. Nothing about the shape of
the post is written in code, except the screenshot block, which the renderer builds (see
Open items).

## Files

```
assets/templates/<tracker>/<releaseType>.txt    the template
assets/templates/<tracker>/<releaseType>.title.txt  the title template (see Title)
assets/templates/<tracker>/title.txt             the tracker default title template
assets/templates/<tracker>/appSignature.txt      the app signature text (see App signature)
assets/templates/<tracker>/<style>.style         the style
<release dir>/message.txt                        the generated text
<release dir>/title.txt                          the generated title (a type with no title has no such file)
```

One folder per tracker holds the files, named by the technical names — the enum values of `Tracker`
and `ReleaseType` (`ai/release_structure.md` §3) — so the value `release.json` writes, the enum
value and the asset path are the same string. The description template is chosen by tracker and
release type, the way `trackerIconAssets` chooses an icon. The title format is a rule of the
tracker, with a per-release-type override when that tracker publishes one (see Title).

Templates are not editable by users. They are the rules a tracker publishes for its
releases. User styles come later, after user settings exist.

## Template grammar

Six constructs, and no others:

* `{{name}}` — a variable.
* `{{#name}}…{{/name}}` — a section. It renders when the value is not empty.
* `{{^name}}…{{/name}}` — an inverted section. It renders when the value is empty.
* `{{#style.slot}}…{{/style.slot}}` — a style slot. Its content is wrapped by the rule
  of that name in the style file.
* `{{blank}}` — an empty line in the output.
* A block variable (`{{screenshotSection}}`, `{{appSignature}}`) — the app builds the
  whole block itself, the image block from the release's image records as a spoiler block
  with one item per line and the app signature from its file, and passes the
  finished block to the template as a string. The template does not describe its shape, so
  no style slot applies to it. `MessageController` builds it.

### Lines

The template is read line by line, and each line produces one output line.

* A line that is only a control tag produces nothing when its section is skipped, so a
  skipped field does not leave a blank line behind.
* An empty line in the template produces nothing in the output. It is breathing room in
  the source for whoever reads the template. An empty line in the output comes only from
  `{{blank}}`.
* `{{blank}}` inside a skipped section produces nothing.
* A `{{blank}}` written outside a section is always emitted, so two of them become
  adjacent when the section between them is skipped. That is the case the collapse rule in
  Output rules handles.
* A block variable expands to as many lines as the block has and is inserted as it is.

## Style grammar

`key = value`, one rule per line.

* `#` at the start of a line is a comment. Inside a value `#` is part of the value, so a
  comment must start at the line start.
* `{content}` is the slot body. A value with no `{content}` is emitted as it is, which is
  how a standalone tag such as `[hr]` is written. An empty value means no wrapper.
* `{token}` substitutes another key from the same file, so a colour is written once.
* Keys are lowercase identifiers. Values are single lines. No nesting.
* There is no inheritance. A style defines every slot the template uses.

The style is appearance only. It is not a config: which hoster an image link comes from is not
an appearance rule, so it is not a style key.

## Variables

Field names are the names `release.json` writes.

| Variable | Source |
| --- | --- |
| `cast`, `videoTitle`, `siteNumber`, `subsiteAndSite`, `productionDate`, `genreTags`, `fileSize`, `duration`, `videoType`, `videoQuality`, `videoFormat`, `videoStream`, `audioStream`, `description`, `additionalInfo` | the release fields |
| `name`, `tracker`, `releaseType` | the release record |
| `posterUrl`, `screenshotSection` | `images.json` |
| `appVersion` | the app's own version, from `lib/app/app_info.dart` |
| `appSignature` | the app signature file, when the checkbox is on (see App signature) |

`tracker` and `releaseType` are the technical names, not the display names. A template is written
in the language the tracker publishes in and writes its own words, so the app can only provide the
ID; a template that needs the words a post shows writes them itself.

`movieFilePath` is not available: a local path is not something a post shows.

Image variables read the hoster and the URL type from constants in `message_controller.dart`
(`realPosterHoster`, `mockPosterHoster`, `posterUrlType`, `imageUrlType`, `thumbUrlType`). For the
first version they are hardcoded: the poster comes from fastpic with `direct_url`, as PornoLab
requires, and its links on the other hosters are the backup poster. The poster hoster is named per
run, because `--dev` replaces the real hosters with the mock ones (`ai/upload_images.md`): a
development run reads the poster from `rptest-a`, the first test hoster, so it produces the same
shape of message, and the backup block then names `rptest-b`. `posterHoster` is the getter that
picks which name applies. The screenshot block names the hoster on each line, so it needs no rule
for choosing one; a record appears under every hoster it was uploaded to. A poster with no entry for
the poster hoster has no value, so its line is dropped.

Both are empty when nothing has been uploaded: a variable with no value produces nothing, and the
blank line before it collapses.

These are per-tracker rules, not appearance rules, so they do not belong in the style file. They
belong in a config of their own. Hardcoding them is the first-version choice, not the design.

Only `siteNumber`, `description` and `additionalInfo` are optional as template
variables, and the template wraps those in conditional sections. `sceneUrl` is
not a template variable, and it is optional too: it is only there to help fill
the other fields. The other fields are required or are filled by the app
from the movie file. What a generation does with an empty one is §Validation.

## Validation

A generation checks the fields before it reads the templates, so a post is never
written from a release that cannot say what the template reads. The check runs
when the user asks for a message, and a generation that fails writes nothing:
the box and the files stay as they were.

* A required field with no value is a problem. A field the app fills is required
  as well: the post shows its value, so a value the probe has not written is a
  missing value like one the user did not type. The optional ones are the three
  the template wraps as conditional sections, and `sceneUrl`, which is not a
  template variable and is only there to help fill the other fields.
* `productionDate` is a problem when its value is not one of the three shapes
  the field accepts: `YYYY`, `YYYY-MM`, `YYYY-MM-DD`. The shape only — a date
  the calendar does not have is not reported, because the app does not decide
  what a production date can be: a release may show a year, or a month, when the
  site does not know the day.
* Only the single video type states its rules. The required set of the other
  types is an item in `lib/TODO.MD`, so a field list that has not stated its
  rules is not checked, and nothing is reported for it.
* The problems are shown as a message, one line per problem, in the order the
  field list lists the fields, which is the order the form shows them in, and
  the same line is shown under the row of the field it is about. Only a row the
  user can type into shows it: the rows the app fills are not something they can
  fix here, so those are said in the message only. The button is not disabled:
  the user is told what is wrong when they ask for a message, not before. After
  the first refusal the form shows the rule as it stands, so an error goes away
  when the field is filled — that is why a row is read through the rule rather
  than through what was reported once.

The rules are the field list's (`FieldSpec.isRequired`,
`FieldList.validatesFields`), so the field list stays the one place the rule
lives. `field_validation.dart` is the pure rule over them and answers with field
names, because a field list is data and a user-visible string comes from
`AppLocalizations`; `fieldProblemText` is the words for a problem, built from
the words `fieldLabel` gives the name (rule 13). Both widgets that report a
problem use it — the Message section joins the lines into the message, the
editor puts one under the row it marks — so the same problem cannot be said
two ways.

## Output rules

* No trailing newline. `message.txt` holds exactly the text the section shows and the
  text the user pastes, so the file, the box and the post are the same bytes. This
  differs from `release.json`, which ends with a newline.
* Leading and trailing blank lines are trimmed.
* Consecutive blank lines collapse to one. This is not a nicety, it is what makes the
  optional fields work: `description` and `additionalInfo` can be empty, and the template
  writes `{{blank}}` before each of them, so two blanks become adjacent whenever one of
  those sections is skipped. Two blanks produce one empty line in the output.
* If a site needs double spacing, that belongs in the style, not in the template.
* UTF-8, LF.

## Title

The title is a second template in the same folder, rendered with the same values. It is plain
text, not bbcode, so no style slot applies to it.

Per release type when the tracker publishes one, falling back to the tracker's `title.txt`
when it does not:

```
assets/templates/<tracker>/<releaseType>.title.txt
assets/templates/<tracker>/title.txt
```

`TemplateStore` reads the type's file first and the tracker's when it is not there. A single
photoset has no video quality to put in a title, so its rule is not the tracker's; see
`ai/single_photoset.md` §8.

The single video type's file, `assets/templates/pornolab/singleVideo.title.txt`:

```
[{{subsiteAndSite}}] {{cast}} - {{videoTitle}}{{#siteNumber}} ({{siteNumber}}){{/siteNumber}} [{{productionDate}}, {{genreTags}}, {{videoType}}, {{videoQuality}}]
```

It was the tracker default until it moved to the per-type path, because it writes `videoType`
and `videoQuality`, which the photoset types have no values for, so it was never a rule for
them. With no tracker default, a type that has no title file of its own gets an empty title,
which is what a tracker without a title file always produced.

The optional field is a conditional section, so its parentheses are not written at all when
`siteNumber` is empty.

A tracker without a title file still generates the message: the title is empty rather than a
failure, because the post text does not depend on it.

A type with no title at all is a rule of the type, `hasTitle` in `lib/feature/release/release_type.dart`:
the image folder has no field the user writes, so there is nothing a title could say. For such a
type no title file is read, nothing is written to `title.txt`, and the section draws no title row
(`ai/image_folder_upload.md` §6). The controller and the section read the same rule, so they cannot
disagree about whether a type has a title.

The result is written to `title.txt` with the same no-trailing-newline rule as `message.txt`.
The title is read-only in the section: it has no edit path, only a copy button.

## Section

The Message section sits below Upload: a **Generate** button, the app signature
checkbox, the title line, and a large text box.

* The text is generated when the user clicks the button.
* The app signature checkbox is the first row after the section's title, above
  the row of radio buttons where the type has one. Both rows are drawn only while
  the Generate button is drawn (rule 14): before any image the message reads is
  uploaded there is no render, so a signature has nothing to be part of and a shape
  nothing to shape, and a row that sets a value nothing can use is noise. Not
  drawing a row is not changing the value it would show — what the record holds
  stays as it is, and the rows show the same values again when an upload run opens
  the gate. It is on by default, and its
  state is the release's (`includeAppSignature` in `release.json`), so a release
  shows the same answer wherever the app is reopened. Changing it goes through
  the editor's single write path, so it marks the tab dirty and clears the box
  with the two files, the same as a field, because the text shown is no longer
  what a render would produce with the signature off.
* The fields are validated first (§Validation), so a release with a required
  field is told which field it is rather than rendered as a post with a label
  and nothing after it. The controller answers with field names, because a field
  list is data, and the words for a problem come from `fieldProblemText`
  (rule 13); the problems are shown as a message, one line per problem, and the
  same problems are given to the editor, which is the widget that builds the
  rows and marks the ones the user can type into. A plain callback, not a
  listener (rule 3): this section cannot mark a row it does not build.
* The **Generate** button is drawn only once every image the message reads has
  been uploaded to the poster hoster: the message is made of those URLs, so
  before any upload there is nothing it could say. While it is not drawn the
  section shows the placeholder line saying what has to happen first, and the
  title row has nothing on its right, which is the same row as one with an
  action. The check is per record — a record with no entry for the poster
  hoster is an upload that did not happen — and an empty manifest is nothing
  uploaded rather than all uploaded. It is a synchronous method on the
  controller, because the widget asks while it builds, like the Upload section's
  `hasUploadableImages()`.
* The run that writes `images.json` is the Upload section, so this one cannot
  see the change; it registers its rebuild with the editor, the widget that
  places both, and the editor calls it when a run ends. A plain callback, not
  a listener (rule 3).
* What the box shows is a render of the values the template reads, so when those
  values change it is no longer what a render would produce, and the section goes
  back to its placeholder: the title line and the box are cleared, and the two
  files go with them, because the files always match what the section shows. The
  reset is silent — it is not an error, and the section is already the thing that
  shows the message. Hand-typed text in the box is lost with it.
  A field is any field, including the ones the app fills, because the message
  reads the values and not the rows; the notice goes out from the editor's single
  write path. An image is a change only when the run added a URL the message
  reads: a run that wrote nothing, and a generation run that wrote files without
  URLs, change what the render would produce by nothing, so neither clears the
  box. Nothing is cleared when there is nothing to clear.
  This applies to every release type: the rule is about the values a template
  reads, not about a form.
* The title line is drawn only for a type that has a title (`hasTitle`). A type with no title has
  no title file, so there is nothing to show and nothing to copy, and a row that holds nothing is
  noise rather than part of the section.
* The results are written to `title.txt` and `message.txt` and shown in the section.
* An edit in the box writes `message.txt` immediately, like the poster writes its file.
  It is not part of the save and does not take part in the dirty flag.
* The title and the text each have a copy button. Writing to the clipboard is a UI action, like
  reading it for the poster's paste-from-URL, so it stays in the widget rather than in the
  controller.

## Implementation shape

Following the rules in `ai/doc.md`:

* `lib/feature/message/message_section.dart` and `message_controller.dart`. The widget owns the
  layout, the box and the title line; the controller owns the render and the write, and returns a
  typed result the widget maps to localized text.
* The validation is a pure rule in `lib/feature/release/field_validation.dart`:
  it reads a field list and the values and answers with the problems, writes
  nothing and shows no messages. The controller calls it before it reads
  anything and returns `MessageInvalid` with the field names, which the widget
  maps to localized text like it maps the other results. The editor keeps the
  problems as widget state, because a row is the editor's and the section
  cannot mark one, and a change to a field is read through the same rule, so
  an error goes away when the field is filled.
* `MessageStore` reads and writes `message.txt` and `title.txt`, and removes them.
  A file that is not there is not an error, because a reset removes files that may
  already be gone.
* The controller owns the snapshot the reset compares against: the values the last
  render read. A generation records them only when the write succeeded — a failed
  write leaves the box and the files as they were, so the snapshot stays what the
  earlier content came from. Opening a section takes the values as they are then,
  because nothing says what generated the text it read from the files. A reset takes
  the current values as the snapshot, so the next change is a change to what comes
  after the reset rather than to content already cleared. The widget owns the box and
  the title line, and calls the controller for the removal (rule 13); the result is
  `MessageCleared`, which reports nothing back because there is nothing to show.
* The renderer is a service under `lib/service/template/`: a plain class with required
  constructor parameters, no listener, no messages.
* The templates and the style are read from the app bundle. A file the bundle does not have is read
  as absent rather than as a crash: the bundle reports a key it does not have with `FlutterError`,
  which is an `Error` and not an `Exception`, so `on Exception` alone lets a missing file escape as
  an unhandled exception in the running app. `TemplateStore._read` is the one place that answers a
  missing key, and the test fakes throw the same shape the real bundle throws.

The renderer is written by hand rather than taken from a package, because rule 12 allows
no third-party packages and the subset needed is small. The part that needs care is the
line rule above: it is what keeps a skipped field from leaving a blank line, and it is
the most likely source of stray blank lines in the output.

## Screenshot section

The block is one spoiler holding the groups, then the backup poster. For the types that cannot
choose a shape, the groups are one per hoster:

```
[spoiler="Скриншоты"]
[spoiler="Скриншоты fastpic.org"]
[url=https://fastpic.org/view/123.jpg][img]<thumb>[/img][/url][url=https://fastpic.org/view/124.jpg][img]<thumb>[/img][/url]
[/spoiler]
[spoiler="Скриншоты turboimagehost.com"]
[url=...][img]...[/img][/url]
[/spoiler]
[spoiler="Резервный постер"]
[url=...][img]...[/img][/url]
[/spoiler]
[/spoiler]
```

* Each hoster's spoiler holds the screenshots **and the screenlist** uploaded to that hoster. A
  record appears in every hoster's spoiler it was uploaded to, since the hoster is named on the
  line.
* Within a hoster's spoiler the screenshots come in the order `images.json` lists them, and the
  screenlist is the last item.
* The last item is the backup poster: the poster records uploaded to hosters other than
  `posterHoster`, which is fastpic for a normal run and `rptest-a` for a `--dev` run (see
  Variables). The poster itself is not in the block — it is the `posterUrl` variable at the top of
  the message.
* Each image is `[url=<view URL>][img]<thumb URL>[/img][/url]`. The link is the view URL, the
  picture shown is the thumb URL.
* The images of one hoster are on one line, with nothing between them, so the site renders them
  as one block. The spoiler opening and closing tags stay on their own lines. No indentation.
* A hoster with nothing uploaded produces no spoiler. An image with no `thumb_url` is skipped;
  it should not happen, and showing the user an error for it is in `lib/TODO.MD`.
* The titles are written in code, as the block is. They are the language the site's rules
  require, so a second tracker needs its own strings. This is the second part of the message
  that is not data — the first is the block shape.

### The two shapes for the type that names items

The video pack is the only type that can choose how the block groups, because the two shapes name
a video: a file name, a duration, a resolution and a size. The other types keep the flat block. The
choice is stored on the release, as `screenshotLayout` in `release.json`,
and a file without the key reads as the first shape, which is the one the block has always had.
The row of radio buttons is the first thing after the section's title; choosing one goes through the
editor's single write path, so it marks the tab dirty and clears the box with the two files, the
same as a field, because the text shown is no longer what a render would produce with the other
shape. The backup poster is the end of the outer block in both shapes, and the rules above about
what is drawn apply to both.

Shape 1, the default: the hoster is the group and the item is inside it.

```
[spoiler="Скриншоты"]
[spoiler="Скриншоты fastpic.org"]
[spoiler="movie.mp4 | 00:12:30 | 1080p | 10.0 GiB"]
[b]Видео[/b]: HEVC
[b]Аудио[/b]: AAC
[url=...][img]...[/img][/url][url=...][img]...[/img][/url]
[/spoiler]
[/spoiler]
[/spoiler]
```

Shape 2: the same block with the two levels swapped — the item is the group and the hosters are
inside it.

```
[spoiler="Скриншоты"]
[spoiler="movie.mp4 | 00:12:30 | 1080p | 10.0 GiB"]
[b]Видео[/b]: HEVC
[b]Аудио[/b]: AAC
[spoiler="Скриншоты fastpic.org"]
[url=...][img]...[/img][/url]
[/spoiler]
[spoiler="Скриншоты turboimagehost.com"]
[url=...][img]...[/img][/url]
[/spoiler]
[/spoiler]
[/spoiler]
```

* An item's group is titled with the line the post shows for a video: the file name, the duration,
  the resolution and the size in the human form. A value the item does not have is left out rather
  than shown as an empty part, the same rule as the rest of the section. The values are the item's
  own fields, the ones the scan writes.
* Inside the group, before the images, are the two lines for the streams: `[b]Видео[/b]: <video
  stream>` and `[b]Аудио[/b]: <audio stream>`, and only the one with a value. The label is bold,
  and the tags are part of the shape written in code, like the spoiler tags are, so the style file
  cannot change them. The words are constants in `message_controller.dart` next to the block
  titles, not l10n keys, because the post is in the language the site publishes in rather than the
  language the app's UI is in — the same reason the block titles are not l10n keys. They are the
  same words the app's labels use for those fields.
* Items come in the order `release.json` lists them, and the kinds inside an item are photo,
  screenshot, screenlist. An item with nothing uploaded to a hoster is not drawn in that hoster's
  group, and an item with nothing uploaded anywhere is not drawn at all. Every record the block
  shows names the item it was generated for, so the grouping covers all of them; the poster is the
  one record that does not, and the backup half shows it.
* The per-item description line and the per-item poster line are not written yet. They are what a
  per-video `stash_url` import would fill, so they wait for it.

## App signature

`appSignature.txt` is the app signature: the app's own credit line, the text a post
ends with. It is a template like the other two, so it reads the same variables,
and `appVersion` is the one it usually reads. It is one file per tracker rather
than one per release type, because a tracker publishes its own wording for it, so
every description template ends with `{{appSignature}}`.

The Message section's checkbox decides whether a release's message ends with it,
and the release's answer is what the checkbox shows (§Section). When it is off the
block is not built at all, so the variable renders as an empty string; the
`{{blank}}` that introduces it is still emitted, because a template line that is
only a control tag is always emitted, and the trailing-blank-line rule then trims
it — so a message without a signature ends at its last content line rather than
at an empty one.

The file is read as text, not as a line list: it is not split, its lines are not
re-joined, and its trailing newline is kept, so a signature written with a final
newline renders with one. A tracker without the file produces an empty block, the
same as a tracker without a title file produces an empty title. It is not
validated (§Validation), so a variable it reads that is not in the table renders
as an empty string, as it does anywhere in a template.

## Open items

* The block is implemented. The hoster and the URL types it reads are constants in
  `message_controller.dart`, hardcoded for the first version; they are per-tracker rules, so the
  right place for them is a config of its own, not the style file, which is appearance only. The
  poster hoster is the one of them that depends on the run, because the mock hosters have no rule
  of their own and the first test hoster stands in for fastpic.
* The block is the one part of the message whose shape is not data: the spoiler wrapper
  and the item tags are written in code, so the style file cannot change them. That is
  the cost of keeping the template simple. If the block ever needs to be styled, a small
  sub-template is the way back.
* `[img=right]` and other dialect-specific tags: the app emits what the style says. There
  is no tag whitelist yet, so an unknown tag produces broken output rather than an error.
* Validation of templates and style files is in `lib/TODO.MD`.
* User styles need a writable location. That is the app's first app-level state, so it
  changes the persistence story in `ai/doc.md` §7.
* Whether regenerating overwrites text the user edited by hand.
