# Release Prepper — Project Reference

Reference for agents working on this repository. Read this before changing code.
It describes what the project is, how it is structured, the rules the current
architecture follows, and which parts of the tree are **not live code**.

---

## 1. What the project is

**Release Prepper** is a Flutter **desktop** application (Linux is the primary
target; `linux/`, `windows/`, `macos/` runner directories exist) for preparing
media releases.

The user creates a release folder through a wizard, the app writes a
`release.json` manifest inside that folder, and the release is then shown in a
per-release editor tab. Releases are opened later by picking the folder through
**File → Open Release**, or through **File → Recent releases**, which lists the
folders the app has already opened and the folders inside the default release
directory (`ai/recent_releases.md`).

UI is localized (English + Russian) and uses a browser-style tab strip plus a
menu bar.

- Package name: `release_prepper`
- Version: `0.0.1` — the `appVersion` const in `app/app_info.dart`, kept equal to
  `pubspec.yaml`. Both are written by the release workflow from the version it
  is given, the name of a file under `changelog/` (§9).
- SDK: `sdk: ^3.13.5`
- Dependencies: `file_picker`, `path`, `path_provider`, `intl`,
  `flutter_localizations`, `provider`, `flutter_svg`, `window_manager`,
  `flutter_secure_storage`, `archive`, `url_launcher`, `enough_convert`; dev:
  `flutter_lints`
- `provider` is the third-party package used for dependency injection only (see
  §4). `flutter_svg` is the only other one and is used solely to render the
  tracker icon assets, because Flutter has no built-in SVG renderer.
  `window_manager` is the first exception to rule 12: it is used to receive the
  native window-close event, which Flutter cannot intercept on its own, so the
  app can run the per-tab unsaved-changes popup before closing, to set the
  native window title in `main.dart`, which `MaterialApp.title` does not set on
  the desktop runners, and to read the size the window has at the point the app
  closes. It is not used to ask the window for a size: the runners apply the
  recorded one before the window exists (§7). `flutter_secure_storage` is the
  second: it is used only to reach the OS credential store, which Flutter cannot
  reach on its own, and only for the values the Integration section stores (see
  §7). `archive` is the third: it is used only to read ZIP archives in the
  photoset scan, because the parts a hand-written reader gets wrong are the ones
  real archives have (see §5 and rule 12). `url_launcher` is the fourth: it is
  used only to open a folder in the file manager the OS uses, which Flutter
  cannot do on its own, and only for the link the Torrent section shows next to
  the path it wrote, and for the draft link the Upload draft section shows,
  which opens the browser the OS uses for it (see §5 and rule 12).
  `enough_convert` is the fifth: it is used only to read a response in the
  charset the site declares, because `dart:convert` has UTF-8 and Latin-1 and
  the pages of this site are in neither (see §5 and rule 12). No routing,
  logging, networking, analytics, or testing packages. Everything else is plain
  Flutter + `dart:io`.

---

## 2. Current state — read this first

The toolchain installed on this machine, and what it can build, are recorded in
`ai/environment.md`, which is not published with the sources.

The earlier non-compiling version of `app.dart` (state members written at top
level) is on branch `borked` (commit `93550ca`); it was removed from `main`.

What is left unfinished is not a compile error but missing behaviour:

- The main menu is File (`New Release`, `Open Release`, `Clone Release`, `Save`, `Close tab`,
  `Settings`, `Recent releases`) and Help (`About`, `System Check`). The four
  that have a keybinding show hotkey
  hints (Ctrl+N, Ctrl+O, Ctrl+S, Ctrl+W), drawn by `MainMenu` itself — gray,
  right-aligned with a minimum gap — because
  `MenuItemButton` renders its own shortcut label with the item's text style and
  a fixed spacing that cannot be styled from outside, and it only shows a hint:
  the keys are handled by `AppShortcuts`, and the items and the keys call the
  same callbacks. `Settings`, `Recent releases` and `System Check` show no hint,
  because there is no key for any of them, and `Clone Release` shows none for the same reason.
  Save writes the selected tab through
  the same path the close
  popup uses; it is disabled when the selected tab is not an editor tab, because
  a wizard has no release to save. Close tab closes the selected tab through the
  shared close flow, so a dirty tab gets the popup first; it is disabled when no
  tab is open. Clone Release acts on the selected tab and is enabled only when
  that tab is a single-video editor tab, because that is the only type the clone
  feature covers.
- The Ctrl keys are answered at the app level, by `AppShortcuts` placed in
  `MaterialApp.builder`, so it is an ancestor of every focus scope in the app, a
  popup route's included, and a key reaches it from wherever the focus is — one
  map for the whole app, where the same behaviour used to be patched one widget
  at a time. A handler nearer in the focus chain is asked first, so the editor's
  own Ctrl+S keeps its fields and this map is the fallback for the rest. PageUp,
  PageDown, Home and End move the page the content area shows: one page height,
  or its top and its bottom, with the move a browser's smooth scrolling makes —
  a fraction of a second, stopping gently rather than all at once. A press that
  arrives during a move starts from where the page is, so pressing the key
  several times reads as one continuous move. They belong to the content area
  rather than to a page, because a page has no controller of its own —
  `TabNavigation` owns the one the pages resolve to, and asks for the
  inheritance on every platform, which a desktop app needs since that is on by
  default only for the mobile ones. A focused text input keeps these keys for
  its caret, and a key with a modifier is the field's too. A focus on the menu
  bar or the tab strip is outside the content area, so nothing moves, as it is
  today. A key reaches a handler only through the focus chain, so
  `TabNavigation` is the default focus of its subtree — a page with nothing
  focusable in it, such as the recent list, has no node below it to be asked
  from — and it is not a stop for traversal, so Tab still reaches the first
  field.
- Open Release covers the happy path and the invalid-folder error (error popup with
  `Close` / `Choose another folder`, which repeats the pick). Cancel is not treated
  as an error. There is no busy/disabled state on the menu item, and the folder is
  not validated beyond `ReleaseStore.load()` finding `release.json` — a missing or
  unreadable folder currently reports `releaseManifestNotFound`.
- Clone Release (`Icons.content_copy` in the tab strip) is the wizard for making a second
  release out of one that is already open, for the case where the user publishes the same scene
  at another resolution: the same description and tags, a different video. It is a tab of its
  own kind, and several of them may be open at once, two of them for the same source, because
  one release per resolution means cloning the same source more than once. The form asks for
  the name the clone is created under and the folder it goes in, prefilled with the source's
  name and the folder the source is in, so the clone is its neighbour unless the user picks
  another one. The name must differ from the source's, because two releases with the same name
  are two rows of the recent list that cannot be told apart; the folder-name rules are the
  new-release wizard's. The tracker and the type are the source's and are not chosen here,
  because a clone is the same release with a different video; the same is true
  of the two flags, so the clone is created with the source's Private flag and
  the source's signature line rather than with the settings' defaults, because
  the post it writes and the torrent it builds are expected to be like the
  source's. On Create the app makes the release as the new-release wizard does
  and then copies what the user wrote — every field the user fills, including
  the scene link — and the poster: the primary poster record with its URLs, and
  its file when it is on disk. The six fields the app fills from the movie file
  are not copied, because they describe a different video, and no other record
  is copied, because the clone generates and uploads its own images. A copy that
  cannot be written is a failed create, and the folder the create made is
  removed, so a half-copied release is not left behind. The create is given the
  source's two flags, not the settings' defaults, so the clone starts as the
  source is. The form warns when the source has no poster, and warns separately
  when it has one that has not been uploaded, because the point of uploading the
  poster first is that the same poster is not uploaded twice for two releases.
- The editor is the Single video field form (`ai/release_editor.md`). The
  release name is the heading, with a tracker badge (its icon and name) and a
  release-type badge after it at a gap, because they say what the name is for.
  The heading has 12 px below it before the form: the gap a section title has
  before its content, because the heading titles the page and not a column. The
  form is as many columns of at least 430 px as the window has room for — the form's own columns plus the sections' columns for the
  types that can be one of them, so four columns appear at about 1792 px. The page uses the whole window width with the margins it
  has always had, so a wide window can really be four columns; there is no maximum width, because a form capped at 1000 px could not
  be. The minimum column width and the gap between columns are constants in `lib/service/images/masonry.dart`, so that a section
  drawn as the page's columns draws exactly those columns rather than its own — the photoset grid is the exception, because it lays
  its own columns out from the two widths `photoset_group.dart` gives it (§7). The columns after the form's are only ever the
  sections' columns, and only for the types `release_editor.dart` says can be one of them — the two video types, because the page is
  the same shape for them, and the photoset pack, whose page is the fields' column, then the Photosets block's column at the most
  the width this feature gives it, then the photo area for what the row has left; the Upload section, the Message section and the
  draft are stacked below the fields in the fields' column, because the block's column is too narrow for their rows. A masonry
  cannot be read at one column width, so the single photoset and the image folder keep the whole width below the form, and a single
  photoset draws its photos in its own block because there is no space beside it for them. Any type's section goes below the form
  too, left-aligned at one column width, when there is no room for it as a column; for a pack the photo area goes below the row at
  the whole width when what the row has left cannot hold one column of its grid, and the space beside the capped block is left empty
  (§7). The Message
  section is the whole width below everything unless it is one of those columns, which for a pack it is never, being part of the
  form's column. Each column is titled by what it holds, with the same title style the sections use: "Release Info" for the column
  of fields the user writes, and for the column of values the scan or the probe read the name of what that type holds — Video for a
  single video, Photosets for the two photoset types, Images for the image folder. A photoset pack is the exception: the only column
  the editor titles is the one with its fields, because its Photosets block titles itself as a section does, in its own column, and
  so does the photo area. So for a pack the word Photosets
  is said twice — as the block's heading and as the label of the count row inside it — and the word Screenshots once, as the title
  of the area, because what the area shows is the pictures rather than the list of sets (`ai/picking.md` §7). A video pack's second
  column is the folder the user picked and the values the scan took from it, so it is titled by the folder rather than by one value
  inside it. The image folder type has no column of fields, so the column that is the poster box and nothing else has no title. A
  section titles itself with `lib/feature/section_title.dart`: the title at the left and the button that runs in that section at the
  right, because the button is the action of the whole section and not of one row inside it. The action is drawn at least
  `SectionTitle.actionMinWidth` wide, so a short label is the same shape as a longer one; that is the width of the action, not of
  each button inside it. A form column has no such button, so it draws its title without that row. The gap a title has to the first
  row of its column is 4 px, not the 12 px a section uses, because the first row of a form column is an image box whose label row
  has its own space above its label, so the same gap reads as a bigger one here than in a section whose first content is plain text.
  The poster box shows the image the user chose; the video thumbnail shows the frame ffmpeg writes for the video, and clicking that
  box picks the video, as clicking the poster box picks an image. Neither is recorded in `release.json`. The poster is a record in
  `images.json`, so its path comes from that record; the video thumbnail is not recorded at all, and its path is derived from the
  release directory and the item path. Both boxes show the file itself rather than a separate smaller copy of it, and the frame is
  written at the source resolution. The path the user picked is its own row, not a field, because the item is the file
  (`ai/release_structure.md` §2). release directory. The poster box also takes a link from the clipboard and processes the image it
  points at the same way as a picked file; pasting the image itself is not implemented (see §10). Fields are editable text boxes
  except the six the app fills from the movie file (items 8, 9, 11, 12, 13, 16), which are read-only, and except `sceneUrl`, whose
  row is the Stash row at the top of the form's left column, under the poster box, and `parentForum`, whose row is the Upload draft
  section's, because a field is where the action that uses it is. Field state lives in `ReleaseEditorController`; the form is filled
  from `release.json` on open, Ctrl+S saves it back — a handler nearer in the focus chain is asked first, so this one wins while
  focus is inside the editor and the app-level `AppShortcuts` is the fallback for the rest — and a change marks the tab with an
  unsaved-changes dot in the tab strip. The form does not validate a field before the user asks for a message; the fields a message
  reads are checked when they ask, for the type whose rules are known, and after a generation is refused the rows the user can fill
  show the rule as it stands, so an error goes away when the field is filled (`ai/description_template.md` §Validation).
- The StashDB row is the first row of the form's left column, under the poster box: the field for
  the scene URL or ID, with a Fetch button, as the other rows that have one have theirs. What a
  fetch gives is not shown in the form but in a popup: each value with a checkbox — checked when
  there is something to apply — and Cancel and Apply. Applying writes through the editor's single
  write path, so the tab becomes dirty and Ctrl+S saves it; the row has no write path of its own.
  The popup owns the selection while it is open, so closing it without applying — by Cancel or by
  any other means — discards what it offered, and fetching again is what shows it again. Its title
  is "Import from Stash DB" and it is capped at 1000 px. The poster row shows its link and the
  image below it, at the width the row has and 240 px tall, fitted and kept at the left rather
  than centred, so a landscape poster fills the box and a portrait one does not sit in the middle
  of it: the app shows no image it has not read from a file, so the popup asks the controller to
  fetch the poster into a temporary file named after the scene, which is what makes an `Image`
  resolve it again (`AGENTS.md` rule 5), and removes the file when the popup closes. A poster
  that cannot be fetched shows its link only. Below the poster the popup has its "Import notes"
  subsection: the values the import changed rather than copied, each one the message that says
  what was done to it followed by the value as the scene reported it, with the part it cut
  struck through. A value it copied as it came is not listed, and a note has no checkbox,
  because it is not something to apply. The subsection titles itself with `SectionTitle`, the
  row every section uses. There are two kinds: the title rule, whose message says the title
  contained the site number so it was stripped from it, and a domain read from a URL outside the
  Primary sources category, whose message says the domain was read from another link and is
  followed by that link. The second kind can appear twice for the one field, once for each of
  the two studios, so a note's key includes its place in the list rather than the field alone.
  The row owns the focus of its input and takes it back when the popup closes,
  because the popup is a route and its focus scope is outside the row's: what
  the framework gives back is whatever had focus before the popup, not the row's
  input. The save key reaches the editor from wherever the focus is, so this is
  not what the key depends on; it is what owning the input's focus means here.
  The fields it can
  fill are cast, video title, site number, subsite and site, production date, tags and
  description, and the poster. The six fields the app reads from the movie file are not StashDB's
  to fill, and additional information has no StashDB value at all. Cast is the credit as the scene
  shows it, the alias when the scene uses one; subsite and site is the domain of the studio, and
  the parent's after it when it has one, the two separated by " / ". The domain is the host of the
  URL the app reads the studio as being on, without `www.`: the URL recorded under a site in the
  "Primary sources" category, because a studio's URL list is not only its own site and the links
  to other databases are often listed first; then the URL recorded under the site named "Studio",
  which is what a studio URL is put under when it does not match a site StashDB knows; and when
  there is neither, the first URL with a host. A URL with no host is not a domain, so it is not a
  candidate at any step. A host is lowercase, so the brand part keeps the studio name's
  capitalization when the name is the same word as the host, and otherwise the host is written as
  the URL gives it. A domain that `assets/stashdb/domain_map.json` has is what the field gets
  before any of this, because the file is the list of the domains the app writes in a form the
  rule cannot give — a host is lowercase, so the capitals a studio uses for its own domain are not
  something it can recover — and the value is used exactly as the file writes it. The file is read
  from the bundle when the values are built, which is why building them is the one async part of
  the feature. A studio with no URL with a host has no domain to read, so the name as StashDB
  reports it is what the field gets — nothing is invented; a domain read from a URL outside the
  Primary sources category is what the popup lists as an import note, with the URL it was read
  from; tags are the names as StashDB holds them, which are always in English; the date field is
  the scene's release date, because StashDB has a production date only when someone entered one,
  so the production date is the fallback; the poster is the first image the scene has, the same
  rule as `images.json`. The scene itself is stored as field `sceneUrl`, the canonical URL built
  from the scene id — never the text the user pasted — and the input shows that stored URL when
  the scene was not fetched in this session. `sceneUrl` is one of the two field names whose row is
  another widget's — the other is `parentForum`, the Upload draft section's — and neither is a
  value a template reads. It is applied on its own without a checkbox, so Apply works for any
  scene the popup is showing even when none of its values are selected.
  The poster
  is not a field, so it does not go through the field write path: it goes through the editor's
  poster path, the same one a pasted link uses. The app asks for one scene by ID over
  `https://stashdb.org/graphql` with the key from the Integration section. There is no GraphQL
  package: a GraphQL call is one POST with a JSON body, and the `HttpClient` the image downloader
  already uses is the client. The key is not a dependency of the client — the widget reads it from
  `SettingsController` and passes it to the call, so the client does not hold a value that can
  change while the app is open.
- The Screenshots section is the width of one form column,
  which is what lets it be one of the form's columns; when there is no room for it as a
  column it is below the form instead (§2). Its title row is the title with the Generate button at the
  right. The row below it is the label, the slider and the count on one line, the same shape the Video
  pack section has: with the button in the title row, they fit in one column width. The count
  text has a fixed width so the row does not move while a run goes. On click the app runs
  ffmpeg once per screenshot, each at a key frame, at the
  original resolution, as a JPEG, evenly spread along the duration (the centre of
  each equal segment), then one `mtn` call for the screenlist: 4 columns, one frame
  per minute of video, at least 16 and at most 96 frames, so the row count is that
  frame count rounded up to a whole row, and with blank skipping off so every cell of
  the grid is a frame rather than an empty space. Files are named `_rp_screenshotNN.jpg`
  and `_rp_screenlist.jpg` in `images/<item path>/`, the same folder the thumbnail
  uses, and the section shows them in two equal columns of its own, packed as a masonry
  (§7), with the screenlist first so it is the top of the left column. Nothing spans in that
  grid: every frame is above the span ratio, so spans would make every tile as wide as the
  grid and the grid would be one column. With no video picked the section shows the
  placeholder saying what has to happen first, rather than controls that cannot run, and its title row
  has no button for the same reason. It shows
  them as the run writes them,
  not only when it ends: the service reports each file as it writes it, the controller turns each
  report into a record, and the widget adds that record to what it shows while the run is going.
  A run that does not finish still records what it wrote, so a screenlist that failed does not
  hide the screenshots that succeeded. The generated images are tracked in `images.json`
  at the release directory root, for their photo-hosting links later.
  The rules that write the files — the key-frame times, the names, the rows, the tool calls — are the
  service's (`lib/service/videos/image_generator.dart`), and it reports the files it wrote, as it
  writes them, rather than records, because a record is a file plus the item it belongs to, which is
  the feature's. What the
  controller keeps is the record, the manifest write and the stamp. The slider minimum is the section's,
  not the generation's: 3 here, because the number is the set of frames a post shows, and 0 for the
  Video pack section, because a run there can write only the screenlist. Both sections read the images
  through `imagesFor(item)`, so one rule decides what a section shows: the records of one item whose
  files are on disk. When a run ends the section calls the function the editor passed it, because the
  count the Upload section shows is the count the release has and the two sections cannot see each
  other; the editor is the widget that places them, so it is where they meet (rule 3: a plain
  callback, not a listener). The editor keeps the rebuilds the sections register with it and calls
  them when something one of them shows changes: a run that writes images.json, or the source the
  Torrent section runs on. Writing or removing a poster is such a change, because the poster is a
  record in that file, so the poster path calls the same notice: without it a poster added after a
  generation is not an image the Upload section counts, and one removed is still counted. A section
  that is itself what changes such a state calls the same notice at the end of its run, so there is
  one path for the notice and one place where the rebuilds happen.
- For a photoset pack the feature is the Photosets block and the photo area, two widgets because
  they are in two grid cells (`ai/photoset_pack.md`, `ai/picking.md` §7). The block is the page's
  second column, at the most the width this feature gives it: its heading with the Scan and Pick
  buttons at the right, the rows the editor gives it — the path the user picked and the counts the
  scan took, which every other type has as rows of the form — and the line naming each set with the
  number of photos in it. The area is what the row has left after the fields' column and the block's
  column, and it draws the grid this feature fits from the two widths it gives: the photos of every
  set together, grouped by kind — the portraits in the columns of the portrait width and the
  landscapes in the columns of the landscape width, never mixed, with the counts deciding how many
  columns each kind gets (`ai/picking.md` §7) — so within a kind the order is the order the source
  gives and across the grid it is not. Each tile says which set its photo is from as well as its file
  name. Nothing is shown before the scan, because opening a release is a read and changes nothing, and
  nothing is drawn for a set before a pick, because the feature shows what is on disk. A set the scan
  found is named by its line in the block even when nothing was picked for it, because that is what
  says the set will not be in the post; with nothing grouping the photos there is no column in the
  grid for such a set. The scan decides which entries under the picked folder are items, counts the
  photos in each, and reads their dimensions from the file headers rather than by decoding the image;
  the minimum and the maximum are decided by pixel area across all photos, and what the scan could not
  take is reported rather than guessed at. The values it counts go through the editor's single write
  path; the items it records are the scan's own output, because an item is what the scan produces.
- A single photoset (`ai/single_photoset.md`) is that same block with one item: the picked folder
  is the set itself, so the scan reads the photos directly inside it and records one item named by
  the folder. It is the same feature with no area beside it, because a single set has no columns to
  put its pictures in, so its block draws them itself (`ai/single_photoset.md` §7). Only the
  strings are branched on the type, because "photosets" and "the folder with the photosets" read
  wrong for one set. Its fields are names the other types already have — a model is the same value
  as a cast, a set name the same value as a title — so only the words differ, and `fieldLabel`
  resolves those two per type. The one name it has of its own is the list of image formats, built
  by the same rule as the video formats. A value for a name the type does not have is not written,
  so the controller keeps the values it returns to the names its field list has.
- For an image folder upload the section below the form is the Image folder section
  (`ai/image_folder_upload.md`): its title row with the Scan button at the right, the images as a
  masonry, the count line, and what the run could not take. The picked folder is the item, and the
  images are copied into the release rather than
  uploaded from where they were picked, because a record path is relative to the release directory and the
  Upload section resolves it there. There is no Pick button and no slider, because for this type the scan and
  the copy are the same action and the number is what the folder contains, not a choice. The field list has no
  field the user writes, so the form is the poster box and the four values the scan counted, in the right
  column only; the three photo names are worded as image names for this type, and the source row says
  *Folder with the images*. A file that is not an image is not counted and is reported by the feature rather
  than by the scan, because the reader reports nothing it skipped and changing it would change what the
  photoset types report. The message is the image block alone.
- For a video pack the Video pack section (`ai/video_pack.md`) is one form column wide, which is
  what lets it be one of the form's columns for that type; when there is no room for it as a
  column it is below the form instead (§2). Its title row with the Scan and Generate buttons at
  the right, the slider, the videos as a table with one row each, and what the two runs could not
  do, listed by name. Nothing is shown before a scan, for the same reason, but a release opened
  from a manifest shows the items its file records, because those are what the file holds. The
  title row fits at one column width only because the generate button's label is the short word,
  and the value columns are about 48 px each at that width, so a number such as a size wraps
  inside its cell. The table has a header row and one row per video; a row shows the name, the size,
  the duration, whether the item has a screenlist and how many screenshots it has, and clicking it shows
  the values the row does not. The name is the path relative to the source rather than a bare file name,
  because two files in different subfolders can share a file name and the path is the record ID. The
  columns are named by the labels their fields have, so the table and the form above it use the same
  words, and the size in a cell is the human form alone, because a fixed-width cell cannot hold the
  byte count as well. The value columns are right-aligned so the numbers line up, and a header follows
  its own column; the name is not a number, so it is not aligned as one. A flag column shows a checkmark
  or a count, and a count of 0 is shown as nothing, because a flag column that says 0 reads as an error
  rather than as an absence; the two flag columns read the same records the Single video section shows,
  so a column and a tile cannot disagree. The detail shows the values the row does not — the resolution,
  the format and the two stream lines, each with the label its field has, because the stream lines are
  long and cannot be columns — and does not repeat the ones the row already shows. The images themselves
  are not shown in the detail yet; when they are, they need the image rule in full. The values are shown
  as the model holds them, so a value the user corrected shows as corrected, and a value the model does
  not have is shown as nothing, because a file the probe could not read has none and the report line says
  which files those are. Which rows are open is widget state, keyed by the item path, because the path is
  the record ID and stays the same across a re-scan of the same folder. The column for the additional
  data is not built, because it belongs to the feature that fills it. The section shows these values
  without editing them: the per-item form that edits them is not implemented yet.
  The slider here allows 0 to 20 and starts at 0, because a run over many files can be asked to write
  only the screenlist; the button is disabled while the release has no items, and there is no
  "Regenerate" variant, because the run replaces what it writes either way.
  A run generates for every item, in the order the scan recorded them, and records what it wrote in
  `images.json` once for the whole run, because a pack is tens of items and one write per item would be
  tens of writes for one action the user asked for once. A tool that is not available stops the run,
  because it does not become installed while the app is open; a file that failed does not stop the next
  one, as one file does not fail the scan. What the run could not do to individual files is a report
  line, with the scan's lines, because a run that did most of them is not an error; what it could not do
  as a whole — a tool not installed, a manifest that could not be written — is a message, the same text
  the Single video section shows. A re-scan replaces the items, so the lines naming files that are no
  longer items are cleared with it.
  The scan walks the picked folder and takes every file with one of the video
  extensions as an item wherever it is, including the ones in subfolders, and probes each one with
  the existing `Ffprobe`, one call per item; a file it cannot probe is still an item with its fields
  empty. The files outside the extension list, the files it could not probe, the subfolders with no
  video in them and the folders the walk could not read are reported rather than guessed at, and the
  walk continues past a folder it could not read — as the photoset scan does with an unreadable set.
  Such a folder is not counted as an empty one, because the scan cannot say whether it had a video in
  it, so the values it counts are known to be incomplete when that list is not empty; only the picked
  folder itself is a failure, because there is nothing to report when it cannot be read. The three
  values it counts — the count, the distinct resolutions sorted by height, the distinct extensions —
  go through the editor's single write path, and the items it records are the scan's own output, as
  with a photoset pack. Videos are never copied into the release, so a video pack depends on the
  picked folder staying where it is. The per-item form that edits these values and the message for this
  type are not implemented yet (`ai/video_pack.md` §8).
- In the same column, below the Screenshots section, is the Upload images section
  (`ai/upload_images.md`): the two sections are the width of one form column for a single
  video, and the whole width below the form for every other type. With room for four
  columns the Upload section is the fourth, and without room for it as a column it is below
  the Screenshots section (§2). The hoster list with
  a checkbox each, every hoster the app has checked at first — the real
  ones, or the mock ones when the app was started with `--dev` — and the Upload button, in its title
  row at the right. A
  hoster whose script reads a credential is not
  selectable while that value is empty: its checkbox is inactive and says where to set it.
  It uploads the poster, the screenlist, and every
  screenshot — not the video thumbnail — through the bundled `uptooda`, one image per call,
  one image at a time per hoster, several hosters at the same time, no retry. A credential
  goes to the tool through the environment variable `UPTOODA_HOSTER_API_KEY`, never as an
  argument, and only for the hosters whose script reads one (`ai/bundled_native_tools.md`).
  An image already uploaded to a hoster is skipped; one that failed is tried again, and an
  unselected hoster is never attempted. The work list is in the order `images.json` lists the
  records, because order is
data (`ai/release_structure.md` §4). The URLs are stored per image and per hoster in
`images.json`, under the
  field names the tool reports. A progress bar is drawn for every hoster in the list,
  whether or not it can run, and shows the images uploaded to that hoster over the images
  in the release: the bar is the share of the release's images that hoster has, so a hoster
  with none of them shows an empty bar while the count next to it reads 0 / 0. Until the
  release has the poster and an image of the kind its type produces there is nothing it could
  upload, so the section shows the placeholder saying what has to happen first instead of the list,
  and its title row has no button for the same reason. The kind is a per-type rule: a screenshot
  for a single video, a screenlist for a video pack, since a run over a pack can be asked to write
  only that, and a photo for the two photoset types and the image folder, which record photos rather
  than screenshots. The words name the kind for a pack; the other types keep the wording that names
  screenshots, which for the photoset types and the image folder is not what the gate requires.
  The state is read
  from `images.json` when the release is opened, so a release with everything uploaded
  shows full bars before anything runs. A run continues from that
  state rather than starting a new count. The count is the count the release has, so a generation run
  that adds images changes it, and the counters are read again when such a run ends: the section
  registers its rebuild with the editor, which calls it, because the two sections cannot see each
  other (rule 3). A run here is itself such a change, because it writes images.json, so it calls the
  editor's notice at the end of one too, and that notice rebuilds every registered section, this one
  included. A bar below full is the only error display: a
  per-image failure is what the bar shows and the log records, so it is not shown as a
  message. Only the cases where nothing can happen at all — the tool is not in the bundle,
  or `images.json` could not be written — get a message.
- The tool the Upload section calls is the one the app ships
  (`native/uptooda/`), because its upload scripts are the modified ones;
  `ToolLocator` reads a bundled tool from the bundle and never from PATH.
  ffmpeg, ffprobe and mtn are read from the bundle first and fall back to PATH
  when nothing is there. Only Linux and Windows binaries are committed rather
  than built from source; macOS is not provided. The three media tools are
  committed for Windows in one directory they share, because they load one set
  of DLLs; on the other platforms nothing is committed for them, so there a copy
  is put in the bundle by hand (`ai/bundled_native_tools.md`). The font the
  screenlist draws with is the app's own, and it is the same one the app's UI
  text uses: the theme asks for it by name, because `Typography` picks the
  family by platform. fontconfig cannot be pointed at the asset bundle, so the
  font is written into the app data directory on first use and the tool is given
  the path of the file (`lib/service/fonts/font_store.dart`,
  `ai/bundled_native_tools.md`).
- The Torrent section (`ai/torrents.md`) is the last thing in the form's second
  column, under its fields, in every layout branch, rather than one of the
  columns after the form, except for a photoset pack: for that type the form's
  second column is its data block, so the section is drawn in the column that
  stacks the sections below the fields, directly above the Upload section
  (`ai/torrents.md`). It calls `mkbrr`, the other tool the app ships. It
  runs the tool on whatever the user picked — a file or a folder, which is what
  the tool accepts — and writes `<release_dir>/<release_name>.torrent`. The
  output is passed as `--output`, because the tool's default is the source
  basename written in the working directory, which `ToolRunner` does not set.
  The file is an output, not a record: nothing is written to `release.json` or
  `images.json`, and a run writes over what is there, so when a release is
  opened again the file on disk is the only thing that says a run happened, and
  the section reports what it finds. The Private flag is the one thing the app
  does record for this feature, as `torrentPrivate`, because it is a choice the
  user makes rather than a result of a run, and its row is the first thing under
  the section title, because the flag is what the run is asked for. The file is
  the thing the flag describes, so when one is on disk the row shows what it
  states rather than what the record says; the record is what a run would write,
  so it is what the row shows when there is no file. The row is drawn only when the
  flag applies to something (rule 14): a source a run would hash, or a file whose
  flag it is. With neither the value belongs to no run and no file, so the row is
  not drawn at all rather than shown inactive. Reading the flag is the
  bencode read in `lib/service/torrent/torrent_file.dart`, and it is a read, not
  a change, so opening a release writes nothing. Changing the flag while a file is
  there is a run — `mkbrr modify` on that file — so the section asks first with a
  popup and runs only on the answer; a dismissed popup is not an agreement, the
  same rule as the close popup. The row is inactive while a run is going and when
  the file cannot be read, because a row cannot show a flag it has not read. The
  flag is part of the record, so the write is the editor's and the section
  reports the change to it, as the Message section does with the two flags it
  owns. With no file the value is only what a run would be asked for, so the
  write is a change and marks the tab dirty like a field does; with a file the run
  has already changed the thing the flag describes, so the record is written at
  once and the tab does not become dirty, because there is nothing left to save.
  With no source picked there is nothing to hash, so the title row has no action
  and the section says what has to happen first instead — "Pick a file first" or
  "Pick a folder first", which of the two is the release type's rule
  (`FieldList.sourceKind`), not something the section can know on its own. What a
  file that is already there says is still shown, because picking a source would
  not change it, so the placeholder is only what the section says when it has
  nothing else to say. The source is not state this section holds, and typing in
  the source row does not rebuild the editor, so the section registers its rebuild
  with the editor, which calls it when that row is written to (rule 3).
  The section shows what the tool reports while it works: the percentage, the
  rate in the bracket before it, and the time left in the pair after it, so
  `ToolRunner` has an optional `onOutput` callback; the wrapper reads those
  fields from the carriage-return-separated segments, because that is the tool's
  format, and the widget shows the bar and the two lines. The tool hashes pieces
  from every file at once, so it never names a current file and there is no name
  to show. Only a Linux binary is provided, so on the other systems the tool is
  reported as not present.
  Next to the path the section shows a link whose text is the release directory
  and which opens it in the file manager, through `FolderOpener`, the app's only
  use of `url_launcher`; a failure is shown as a message rather than swallowed.
- Below the Upload section is the Message section
  (`ai/description_template.md`) — the
  fourth column when there is room for four, otherwise the whole width below everything
  (§2): its title row with the Generate button at the right, the app signature
  checkbox, the title line, and a large text box; the last two each have a copy
  button. The checkbox is on by default and decides whether the message ends with
  the app signature (`ai/description_template.md` §App signature). Its
  state is the release's, as `includeAppSignature` in `release.json`, so a
  release shows the same answer wherever the app is reopened, and changing it
  marks the record dirty like a field does. Only what
  there is to show is drawn: an empty title draws no row, and while nothing has been generated the
  section is its title row and the placeholder — the same shape the Screenshots section
  has when it has no images. The two flag rows are not drawn in that state
  (rule 14): before any image the message reads is uploaded there is no render,
  so the signature has nothing to be part of and a shape nothing to shape. They
  appear with the gate, and the values they show are unchanged by the rows not
  being drawn. The Generate button is drawn only once every image
  the message reads has been uploaded to the poster hoster: the message is made of
  those URLs, so before any upload there is nothing it could say, and the
  placeholder says what has to happen first instead. The title row with nothing on
  its right is the same row as one with an action. The check is per record — a
  record with no entry for the poster hoster is an upload that did not happen —
  and an empty manifest is nothing uploaded rather than all uploaded. It is a
  synchronous method on the controller, like the Upload section's
  `hasUploadableImages()`, because the widget asks while it builds. The run
  that writes images.json is the Upload section, so this one is updated only
  through the rebuild it registers with the editor (rule 3). The consequence is that a message can only be
  typed after something has been generated, because while the box is not drawn there is nowhere to type.
  The copy button for the box is at its top, level with the first line, not in its middle:
  `InputDecorator` centres a suffix icon in the input area whatever the decoration takes, so the field
  uses the suffix slot with its text aligned to the top instead. Clicking it
  reads the templates and the style for the tracker from the app bundle, builds the values they
  read (the fields as `release.json` writes them, the release record, and the image variables),
  renders the post text and the title, and writes them to `message.txt` and `title.txt` at the
  release directory root with no trailing newline. The section shows what the files contain when
  the release is opened. An edit in the box writes the file immediately, so the message is not
  part of the save and does not take part in the dirty flag. Regenerating replaces what is in the
  box: the render is the source of truth. The title is read-only, and a tracker without a title
  template produces an empty title rather than a failure. A type that has no title at all
  (`hasTitle` in `release_type.dart`) reads no title file, writes no `title.txt`, and the section
  draws no title line for it, because a row that holds nothing is noise — the same is true for a type
  that has a title while there is none, so the title line appears only when a title exists; the image folder
  is such a type (`ai/image_folder_upload.md` §6). A file the bundle does not have is read as absent rather
  than as a crash: the bundle reports a key it does not have with `FlutterError`, which is an
  `Error` and not an `Exception`, so `on Exception` alone lets a missing file escape as an
  unhandled exception in the running app.
  What the box shows is a render of the values the template reads, so a change to
  those values makes it no longer what a render would produce, and the section goes
  back to its placeholder: the title line and the box are cleared, and the two files
  go with them, because the files always match what the section shows. The two things
  that change the values are outside this widget — the form and the Upload section —
  so the editor tells it through a second plain callback the section registers, called
  from the single write path and from the end of an upload run (rule 3). A field is
  any field, including the ones the app fills, because the message reads the values
  and not the rows. The choice of the shape the block has goes through the same notice,
  because it is part of what a render would produce, the same as a field. An image is a
  change only when the run added a URL the message
  reads: a run that wrote nothing, and a generation run that wrote files without URLs,
  change what the render would produce by nothing, so neither clears the box. Nothing
  is cleared when there is nothing to clear, and the reset is silent — it is not an
  error, and the section is already the thing that shows the message; hand-typed text
  is lost with it. The rule is about the values a template reads rather than about a
  form, so it applies to every release type.
  The controller holds the values the last render read and says whether the current
  ones are still those: a generation records them only when the write succeeded, since
  a failed write leaves the box and the files as they were, and opening a section takes
  the values as they are then, because nothing says what generated the text it read
  from the files. `MessageStore.delete` removes one of the two files, and a file that
  is not there is not an error, because a reset removes files that may already be gone.
  A reset answers with `MessageCleared`, which reports nothing back because the widget
  has already cleared the box.
  The screenshot block is the one part of the message whose shape is not data — the
  spoiler wrapper, the item tags and the titles are written in `MessageController`: one spoiler
  per hoster holding the photos, screenshots and screenlist uploaded to it — a photo is an image in
  the post like a screenshot is — then the backup poster for
  the poster links on the other hosters. The images of a hoster are on one line with nothing
  between them, so the site renders them as one block.
  For the video pack the block groups per item as well, in one of the two shapes the release
  chooses with a row of radio buttons at the top of the Message section: the hoster's group with
  one group per item inside it, or the item's group with the hosters inside it. An item's group is
  titled with the file name, the duration, the resolution and the size, and holds the two stream
  lines before its images. The shape is stored on the release as `screenshotLayout`, and a file
  without the key reads as the first shape, so a release written before the choice existed is not
  an error. The row is drawn only for that type; the other types keep the flat block,
  because the two shapes name a video and they have no video to name. Choosing a shape is written
  through the editor's single write path,
  so it marks the tab dirty and sends the notice that clears the box with the two files: the choice
  is part of what a render would produce.
- Below the Message section is the Upload draft section (`ai/uploading_draft.md`),
  in whichever place that one is: the fourth column when there is room for four, the
  whole width otherwise (§2). It is the section that sends what the Message section
  shows, so it is drawn only for the four types whose field list has the parent forum
  — the single video, the two photoset types and the video pack — and not for the image
  folder, which has no title to send. Its row is the section's own, as the Stash row is
  the Stash section's (`ai/release_editor.md`), because the field is where the action is
  and the row and the button are read together. `parentForum` and `draftUrl` are the two
  names with no row of the form besides the scene link, and the only two no template
  reads, so writing one does not make a rendered message stale.
  What is drawn is what there is: with nothing generated the section says what has to
  happen first, and the row and the Upload button appear only when a message exists — the
  subject and the message a run sends are the two files the Message section owns, read with
  `MessageStore.loadSync`, not the text in the box. Whether a message exists is state that
  section changes, so this one registers its rebuild with the editor (rule 3). A link the
  release already holds is shown even when the row is not: it is the result a run wrote, not
  something a reset takes away.
  The button is disabled while a run cannot be made, and its tooltip says which of the
  three is missing in the order a run needs them: the message first, then the two
  credentials, then the parent forum. The gate is the credentials rather than the cookie,
  because a run can obtain the cookie from them (`ai/pornolab_login.md` §1). The value is
  accepted only as a full URL on the site with an `f` parameter, because the request is
  built from the id in it; it is stored as the user wrote it, because a forum URL is not
  one shape — a subsite forum, a mirror, a URL with parameters — and the app cannot know
  which one was meant. The row shows the shape rule with the same words the form's rows
  use, and the words for a result are one set shared with the settings row, which is the
  exception to rule 13 recorded in §4, so the gate and the message cannot disagree.
  A run is not retried for a failure it cannot act on, and the app does not make
  a login from one: a run with nothing stored says where to make the login, and a
  cookie the site did not accept says what it was and where to log in again
  (`ai/pornolab_login.md` §7). The reason is the captcha: the site asks for one
  after a few login attempts from the same address, a login the app made on its
  own would use up the limit the user needs, and a run has no user to read an
  image. The one case a run acts on is a stored draft the site says is gone: the
  answer names what to do, so the run asks for a new draft once and the link it
  stores is the new one's (`ai/uploading_draft.md` §6).
  A run writes the link it gets back through the editor's single write path, so the tab
  becomes dirty and Ctrl+S saves it; the link is the result of the run, so there is no
  "draft saved" string, except the line for the run that had to make a new draft, which
  says why the link changed. A link the release already has is shown whenever it has one, even
  after the Message box was reset, following the Torrent section's precedent: a stored link
  is not something a reset takes away. Its text is the link and it opens the browser
  through `UrlOpener`; a failure is shown as a message rather than swallowed (rule 13).
  The copy button next to it copies the text: the same call the Message section's copy
  buttons make, and nothing is said when it works, as they do. The label above the link
  says what it is, because the link's text is the link itself. Both labels of this
  section are the words of the fields it owns, resolved through `fieldLabel` as the
  form's rows are, and the title names the tracker the draft goes to, because the app
  can talk to more than one.
- The Settings tab (`File` → `Settings`, `Icons.settings` in the tab strip) is a two-pane page:
  the section list on the left, the selected section on the right, with every field capped at
  400 px. General has the app language selector (System language / English /
  Русский). Releases is what the app does with a release it has not made yet:
  the default release directory, which is what the new-release wizard prefills
  its save path with, and the two flags a new release is built with — the
  torrent Private flag and the app signature line, both on by default, because
  that is the state the app has always created a release with. The folder button
  is on the same line as the field, to its right. The field is capped at the
  same 400 px as every other field on the page, so the row does not make it
  wider than the rest of the page; what the row does is put the two controls on
  one line when they fit and one control per line when they do not, because a
  field cannot show its label at a width the label does not fit in. The point
  where they stop fitting is what the two controls need, with the button's part
  measured from the label the app shows, so it moves with the language, as the
  login row's does. What this section holds are defaults, not rules: they are
  what a release the app has not made yet is built with, and a release that
  exists keeps what its own manifest holds, so changing a default here does not
  rewrite a release, and the editor, the Message section and the Torrent section
  still change the flags per release. Integration holds the credentials for
  external services, with one field each for StashDB, Postimages and the two
  PornoLab credentials. Which field is obscured is a flag on the field entry
  rather than a rule of the section: every entry here is stored in the
  credential store the same way, and the username is the one shown plainly. The
  two credential fields and the button that runs the login are one row. The
  row's fields are capped at the same 400 px as every other field on the page,
  so the row does not make a field wider than the rest of the page; what it does
  is put the three controls on one line when they fit and one control per line
  when they do not, because a field cannot show its label at a width the label
  does not fit in. The width where it stops is what the three controls need,
  with the button's part measured from the label the app shows, so it moves with
  the language. The fields are disabled while a session exists, because a
  credential cannot change during one. The button is Log in when no cookie is
  stored and Log out when one is, the second in the error colour the page
  already uses for a failed write. When an answer asks for a code the section
  shows the image the code is read from and a field for it, capped at the same
  400 px, and the same button sends what is typed; the code is not a stored
  value and is not committed as the fields are, because it belongs to the page
  that asked for it (`ai/pornolab_login.md` §3). The cookie a login gives is
  stored under the key `pornolabCookie`, and it is not a field the page draws:
  the value the user used to paste is not read any more, and nothing was
  migrated. Those values are not in `settings.json` — they live in the OS
  credential store (Keychain, Credential Manager, the Secret Service), which is
  per machine, so a fresh machine has no keys. When that store cannot be reached
  the section says what to enable and offers storing the values plainly in
  `settings.json`, marked as not recommended; a value is stored plainly only
  when the user allows it, and the field then says where the value is — once for
  the row rather than once for each field in it, because the note describes the
  row as a whole. The StashDB field is read by the Stash section and the
  Postimages field by the Upload section, which is what makes them real: the
  Upload section passes the Postimages value to the tool through the environment
  variable `UPTOODA_HOSTER_API_KEY`, only for the hosters whose script reads one
  (`ai/bundled_native_tools.md`), and the two credentials are what the login the
  app makes itself is built from. Settings are written as they change, so the
  settings tab has no dirty flag, is not part of Ctrl+S, and closes without the
  unsaved-changes popup. A text field commits on submit, when it loses focus,
  and when the tab closes: with no save step there is nothing that could hold
  unsaved text, so a field that still has text when the tab closes writes it.
  The language applies live, which is why `SettingsController` is a
  `ChangeNotifier` (see §4). The tab is opened once: the menu item selects the
  one already open, because settings are app-level and a second tab would show
  the same thing twice. Which section the settings tab shows is remembered
  while that tab is open, so coming back to it from another tab shows the
  section the user was on: the selection is the tab's state, not the page's,
  because the content area builds only the active tab and the page is thrown
  away on a switch. It is not stored in settings.json, because it is what the
  user was looking at and not a setting, and a settings tab that was closed
  shows the first section again, because the record the choice was on is gone.
- The app remembers the size the window had at the end of the run (`ai/doc.md`
  §7). It is the app's second app-level record and the only one with no page:
  nothing on the Settings page writes it, because the value is not something the
  app takes from a form — the window is what writes it. It is recorded at the
  point the app closes for real, which is the only moment the app knows what the
  window was for a whole run, and the same size as the one already recorded is
  not written again. What is remembered is the size the window reported at that
  point: the maximized state is not part of the record, so a window closed
  maximized is remembered at the size it was maximized to. Position is not
  recorded, because a size is what the user chose by dragging and the app has
  one window. A write that fails is not reported: there is no widget left that
  could say it, so it shows up on the next run, as the file the runners read and
  as the record this feature compares against. The app never asks the window for
  a size; the runners read the record before they create the window, so the
  window is created at the size the last run had rather than resized to it after
  it appeared. That is the only way to get that: the size a window is created
  with is what its toolkit says at creation, and a size asked for afterwards is
  a request the desktop may ignore, which is the difference between a window
  that opens at the remembered size and one that jumps to it. A record that is
  not there is nothing, so a first run takes the size a runner starts with. The
  macOS runner does not read it (`lib/TODO.MD`).
- The Recent releases tab (`File` → `Recent releases`, `Icons.schedule` in the tab strip) is a table of
  the releases the app has opened, so the user can go back to one without picking the folder again
  (`ai/recent_releases.md`). It is opened at startup, as the first tab, and opened once like the
  settings tab, because the list is app-level and a second tab would show the same table twice. It
  holds nothing the user edits, so it has no dirty flag, is not part of Ctrl+S, and closes without the
  unsaved-changes popup. One entry per release directory, keyed by the path; the entry opened least
  recently leaves when the list reaches 50, and there is no per-row remove, because the cap is what
  decides what leaves. An entry is recorded by the open, create and save paths, and only when one of
  them succeeds. The dates are what the app read the last time it touched the release rather than a
  live read of `release.json`, because a row whose folder is gone still has to show something and the
  table would otherwise be fifty file reads for one screen. Which column the table is ordered by is
  widget state, as the Video pack table's open rows are; the order the file lists is data and a sort
  does not rewrite it. A row whose `release.json` is not there any more is drawn dimmed with the values
  the index holds and marked, not dropped. Clicking a row opens the release through the shared open
  flow, or focuses the editor tab already open for that directory: the single-instance rule the settings
  tab uses, applied per release, which is a change to the open flow — before it the same release could
  be in two tabs. The popup a failed row click shows has only Close, because the row names a folder the
  app has already read and there is nothing to choose again. The table also lists the immediate
  subdirectories of the default release directory that hold a `release.json` (`ai/recent_releases.md` §5).
  Those are not entries: nothing was read about them, so a row shows the name and the path and nothing
  else and nothing is written from them, and a folder that is in both is one row with the values the
  index holds, because the index is the record and the scan only says the folder is there. A directory
  that is not there reads as nothing found, as a store that cannot be reached, and the scan has no cap,
  because the 50 is a rule about the stored list rather than about what a folder holds.
- The System Check tab (`Help` → `System Check`, `Icons.monitor_heart` in the
  tab strip) is one row per native tool the app calls — ffmpeg, ffprobe, mtn,
  uptooda-cli, mkbrr — showing the version the tool reported, or the reason it
  could not be run. It is opened once, like the settings tab, because the check
  is app-level and a second tab would show the same list twice. The check runs
  when the tab opens and not again after that, because a tool does not become
  installed while the app is open; reopening the tab runs it again. The calls
  run at the same time and each result is reported through a callback as it
  arrives, so a tool that hangs does not hold up the rows of the tools that
  answered; a row shows a spinner until its own result arrives. That is the rule
  3 pattern for a controller that reports while it works, as the screenshot and
  upload controllers do, and the page keeps the results by tool name rather than
  by position, because they do not arrive in the order of the list. The version
  is the first line of the tool's output as the tool wrote it, so nothing is
  parsed per tool, and the arguments are the ones each wrapper names: `-version`
  for ffmpeg and ffprobe, `-v -P` for mtn (`--version` is not an option mtn
  accepts, and `-P` is on every call to mtn, because without it mtn pauses at
  the end of a run and does not exit on Windows), `--version` for uptooda-cli,
  `version` for mkbrr, because the bare command prints its banner and its usage
  without a version. mtn is the one tool
  whose version call does not exit 0: `-v` is verbose mode and a run with no
  input file is an error to it, so it prints the version to stderr and exits
  255; for that tool the line it printed is the result, since the exit code
  says nothing about the check, and a run that printed nothing is still reported
  as no output. A tool that cannot be started is shown as not found, and a run
  that failed, timed out or printed nothing is its own message, so the page
  reports what happened rather than guessing at a version.
  Tool names are proper nouns shown from `NativeTool.name`, as tracker names
  are, so they are not l10n keys. The results are widget state; the controller
  owns the tool list and the calls (rule 13), and the widget maps a result to
  localized text and to a status icon. The page is a two-column list with a
  header, drawn with the shapes the recent table already uses — the odd rows
  take the container colour — so it reads as a report rather than as a stack of
  lines. Its block is capped at 1200 px and centred in the tab, and the title
  is the page title style the release name uses, centred with the block; the
  text inside the table stays at the start. The page holds nothing the user
  edits, so it has no dirty flag, is not part of Ctrl+S, and closes without the
  unsaved-changes popup. Its calls are
  logged in the app data directory, because `ToolRunner` needs a directory per
  call and outside a release there is no release directory.
- The two dropdowns' options are the enum values, `ReleaseType` and `Tracker`, so an option cannot
  exist without the field list and label behind it. A template is not required to create a release, so
  a type whose message is not implemented can still be chosen; a video pack is one, and generating its
  message is what fails, not opening it. The labels are the display names:
  `releaseTypeLabel` for a type, `Tracker.displayName` for a tracker.

---

## 3. Layout

```
lib/
  main.dart                     entry point: reads `--dev`, which is what makes the app use
                              the mock hosters instead of the real ones
                              (`ai/upload_images.md`), then runApp(const App())
  app/app.dart                  App + AppRoot (MaterialApp, the theme, the l10n delegates,
                              the app locale) + TabsPage. Composition only: installs the
                              provider scope and places MainMenu + TabStrip + TabView.
                              AppRoot is the one place app.dart reads from the provider
                              scope, for the locale (see §4).
  app/app_providers.dart        Composition root: the whole object graph, one
                                provider entry per feature.
  app/app_info.dart             appName and appVersion, the single source of truth
                                 for both, used by main.dart, app.dart and
                                 about.dart. The name is a proper noun and the
                                 version a number, so neither is an l10n key.
  feature/
    tab/
      tab_manager.dart          AppTab, AppTabKind, TabManager (ChangeNotifier).
                                addSettings(), addRecentReleases() and
                                addSystemCheck() open the app-level tabs, or
                                select the one already open; addReleaseEditor()
                                does the same per release directory, because one
                                release is one row of the recent list and one
                                tab. addCloneWizard(source) always adds a tab:
                                the clone feature is one release per resolution,
                                so the same source is cloned more than once and
                                two of its tabs are not the same thing.
      tab_strip.dart            TabStrip + _TabCard: the browser tab strip (no
                                press ripple; the hover tint is painted from the
                                card's own state so it follows the selection,
                                and only unselected cards get it; the middle
                                button closes a tab; the card icon is a
                                TrackerIcon for an editor tab, an IconData for a
                                wizard, which has no release yet — the clone
                                wizard has a source, but the release it will make
                                does not exist — so `Icons.new_releases` for the
                                new-release wizard and `Icons.content_copy` for
                                the clone wizard, `Icons.settings`
                                for the settings tab, Icons.schedule for the
                                recent releases tab, and Icons.monitor_heart for
                                the system check tab)
      tab_view.dart             TabView: content area for the active tab + empty
                                state. The page for the active tab is resolved
                                by switching on `AppTabKind`, including
                                `SystemCheckPage`. The clone wizard is given the
                                source its tab carries, which is the only thing a
                                clone tab holds. Keying the content by tab id is
                                why state that has to survive a switch is on the
                                tab record and not in the page: the page for a
                                tab is built only while that tab is active.
      tab_close_controller.dart TabCloseController: the side effects of closing a
                                  tab (select it, save its release, or close it);
                                  typed result, no listener, no context. A save that wrote the
                                  manifest also refreshes the recent entry with the date it
                                  stamped, because that date is what the recent table orders by
      tab_close.dart            the shared close flow: the three-option popup
                                for a dirty tab (Close without saving / Save and
                                close / Cancel), used by the strip, Ctrl-W, and
                                closing the app; the popup stays open and shows
                                the error when the write fails; tabTitle is
                                shared with the strip, and the system check tab
                                is named by the `systemCheck` key, as the other
                                app-level tabs are, and the two wizards by their
                                menu keys, because a wizard has no release to name
                                it
      app_shortcuts.dart        AppShortcuts: the app's Ctrl keys — Ctrl+N
                                creates a new release, Ctrl-O opens a release
                                through the shared open flow, Ctrl+S saves the
                                current tab through the shared save flow, Ctrl-W
                                closes the current tab through the shared close
                                flow. Placed by `AppRoot` in
                                `MaterialApp.builder`, so it is an ancestor of
                                every focus scope in the app and the keys reach
                                it from a popup route too; a widget that handles
                                a key itself is nearer in the focus chain, so it
                                keeps what it does.
      tab_navigation.dart TabNavigation: PageUp, PageDown, Home and End
                                move the page the content area shows — one page
                                height, or its top and its bottom, with the move
                                a browser's smooth scrolling makes, and a press
                                during a move starting from where the page is.
                                It owns the `ScrollController` the pages resolve
                                to (a deviation from rule 2 and rule 7, recorded
                                below) and asks for the inheritance on every
                                platform, which a desktop app needs. It is the
                                default focus of its subtree, because a key
                                reaches a handler only through the focus chain
                                and a page with nothing focusable has nothing
                                below it; it is not a stop for traversal. It
                                declines a key when a text input is focused or
                                when the key has a modifier, and it is not asked
                                at all when the focus is outside the content
                                area.
      app_close.dart            AppCloseHandler: keeps the window open when the
                                close button is pressed (prevent-close), runs
                                the popup once per dirty tab, and closes the app
                                only if none is cancelled (window_manager). On
                                the answer that closes, it records the window
                                size through `WindowController` before the
                                window is destroyed, because that is the only
                                point at which the app knows what the window was
                                for a whole run (`ai/doc.md` §7)
    main_menu.dart              MenuBar: File (New Release, Open Release, Clone
                                Release, Save, Close tab, Settings, Recent
                                releases), Help
                                (System Check, About), with gray right-aligned
                                hotkey hints (Ctrl+N, Ctrl+O, Ctrl+S, Ctrl+W, 60
                                px minimum gap) drawn by `_itemLabel`. Settings,
                                Recent releases and System Check show no hint,
                                because there is no key for any of them. Save
                                acts on the selected tab and is disabled when it
                                is not an editor tab; Close tab is disabled when
                                no tab is open; Clone Release is enabled only
                                for a single-video editor tab, the only type the
                                feature covers. `saveCurrentTab` is the shared
                                save flow, used by the menu item and by Ctrl+S.
    main_menu_controller.dart   MainMenuController: dispatches menu commands,
                                including Save, which delegates the write to
                                `TabCloseController.saveTab`, Settings, Recent
                                releases and the System Check, which ask
                                TabManager to open or focus the app-level tab,
                                and the open commands, which record the release
                                they read before opening its tab. Recording is
                                the recent feature's side effect, so this only
                                puts it and the tab in the order the user sees:
                                the list first, then the tab. `onCloneRelease()`
                                asks `TabManager` for a clone tab for the release
                                the selected editor tab shows, and does nothing
                                for a tab the feature does not cover, so a call
                                from anywhere cannot open a wizard for a release
                                it has no rules for.
    about.dart                AboutPopup (AlertDialog shown with showDialog)
    tracker_icon.dart         trackerIconAssets (Tracker -> asset path) and
                              TrackerIcon, the widget that draws one at a given
                              size; shared by the wizard, the tab strip and the
                              editor. Renders `.svg` with flutter_svg and any
                              other extension with Image.asset, so PNG icons work
                              without changing call sites. Presentational only:
                              no state, so no controller.
    image_tile.dart           ImageTile, the bordered box with a picture and its file name
                              centered under it, and the line naming the group the file is
                              from above that when the caller gives one. Shared by the
                              Screenshots, Photosets and Video pack sections, because they
                              show the same files the same way. With it `imageFromFile` and
                              `evictCachedImages`, the two halves of the rule in
                              AGENTS.md §5: the key that changes on each rewrite, and the
                              cache entry dropped for the path the app writes. The
                              generation counter stays each widget's own state, so it is
                              passed in rather than held here; the box height is a
                              parameter because the photoset packing sizes the box, not the
                              picture inside it. `fit` and `alignment` are the caller's,
                              because nothing is known about the picture before it is
                              decoded: the box is the caller's and the picture is fitted
                              into it. Presentational only: no state, so no controller.
    section_title.dart        SectionTitle, the title row a section begins with: the title at the left
                              and the action that runs in that section at the right. Shared by the six
                              sections, because every section titles itself the same way and the button
                              that belongs to a section is the same shape in all of them. The row is as
                              tall as the action and the title is centred against it, because a button is
                              taller than the title text and the two read as one line only when their
                              centres align. The action is drawn at least `actionMinWidth` wide, so a
                              short label is the same shape as a longer one; it is the width of the
                              action, not each button inside it. Presentational only: no state, so no
                              controller; the gap below the row is the caller's, because the widget is
                              the row and not the section.
    pornolab_results.dart     pornolabResultText, the words for a result the site gave. It is the
                              one mapping the settings row and the Upload draft section share, so
                              the same result cannot be said two ways; this is the exception to
                              rule 13, with `field_validation.dart` as the precedent for a shared
                              mapping. It is total over the result kinds, including the two a
                              field's own rule gives, which are unreachable from the settings page
                              because a login has no field to fail. The word for a login that
                              worked is not in this mapping, because only the settings page shows
                              it — a run has nothing to show for one, its success is the link it
                              was given — so that word is the page's own string
    release/
      release.dart              Release (name, directoryPath, tracker,
                                releaseType, source, fields, items, createdDate,
                                lastEditDate, includeAppSignature,
                                torrentPrivate) + ReleaseItem (path, type,
                                fields) + markEdited() + toJson() +
                                schemaVersion
      release_store.dart        ReleaseStore (create/load/save/touchLastEdit) +
                                the two exceptions. create() takes the two flags
                                as parameters rather than deciding them: the
                                store writes what it is given, which is the
                                settings' defaults for a release made through
                                the wizard and the source's own flags for a
                                clone
      release_open_controller.dart   sealed ReleaseOpenResult + openRelease(), which opens the
                                picker at the default release directory the widget gives it,
                                and openPath(), the same load for a folder the recent list
                                names with no picker, so a row click reports a failure the
                                same way the menu item does
      release_open_flow.dart       The shared Open Release flow: pick -> load ->
                                error popup (Close / Choose another folder),
                                used by the menu item and by Ctrl-O. For a recent row the
                                popup has only Close, because the row names a folder the
                                app has already read and there is nothing to choose again.
      release_wizard_controller.dart   wizard state, name validation, create().
                                       The default save path and the two flags a
                                       new release is built with are passed in
                                       from the settings by the widget rather
                                       than looked up here, so a release is
                                       created with the values it was given. A
                                       create that succeeded is recorded in the
                                       recent list, as an open is.
      release_wizard.dart       wizard form UI (selects use DropdownMenuFormField)
      clone_wizard_controller.dart   clone state: the fields the copy takes, the
                                     poster state, the default save path, and
                                     create(). The name rules are the new-release
                                     wizard's plus one: the name must differ from
                                     the source's, because two releases with the
                                     same name are two rows of the recent list that
                                     cannot be told apart. A create that succeeded
                                     is recorded in the recent list, as an open is;
                                     a copy that failed removes the folder the
                                     create made, so a half-copied release is not
                                     left behind.
      clone_wizard.dart           clone form UI: the source it names, the name and
                                     the folder it prefills, and the warning the
                                     poster state decides
      release_fields.dart       FieldValues, the field value model keyed by field name, + FieldSpec
                                 and FieldList, the per-type field lists behind one model + the
                                 values a new release starts with + the marker for the fields the
                                 app fills + the item types + the field names with no form row
                                 (`sceneUrl`, `parentForum`, and a video pack's item fields until
                                 the per-item form exists) + the marker for a field no template
                                 reads, which is what decides whether writing one sends the notice
                                 that clears the Message box + the marker for a field a clone does
                                 not copy, because a run wrote it + the item boundary the scan is
                                 given per type + whether a name is in a list, so a value for a
                                 type that does not have it is not written + whether a field may be
                                 empty when a message is generated, and which type states its rules
                                 at all + the labels the widgets resolve through AppLocalizations,
                                 per type where a name is worded differently
      field_validation.dart     the value rules a field list states, as a pure function over the
                                 list and the values: a required field with no value, and the shape
                                 a value must have — the date, and the parent forum URL the request
                                 is built from. Answers with field names rather than text,
                                 writes nothing and shows nothing. fieldProblemText is the words for
                                 a problem, from the words fieldLabel gives the name, and both
                                 widgets that report one use it, so a problem cannot be said two
                                 ways. fieldProblem is the rule for one field, which is what a
                                 section that owns its row asks for: the shape is its gate, and the
                                 required set of its type is not known
      release_type.dart         ReleaseType, the release types the app knows: the enum value is the
                                technical name, so the manifest value, the template file name and
                                the field list key are the same string + releaseTypeLabel, the one
                                place a type becomes an AppLocalizations key, as fieldLabel is for
                                a field name, + hasTitle, the per-type rule for whether a type has
                                a post title at all + the order, which is the order the wizard
                                lists the types, because its option list is ReleaseType.values
      tracker.dart              Tracker, the trackers the app knows: the enum value is the technical
                                name, so the manifest value and the template folder are the same
                                string + displayName, what the app shows in every language, so it
                                is not an AppLocalizations key
      file_size.dart            the size field's display: the stored byte count
                                as `9.5 GiB (10737418240 bytes)`, and the human form alone
                                for a fixed-width cell, as the Video pack table's size
                                column shows it
      release_editor_controller.dart   editor state: the field values, the shape of the
                                screenshot block, the source and the item it
                                is, the dirty flag, save(), the flag write paths: the
                                change path for a value with no file, and the write path for a
                                flag whose file a run changed, which writes the manifest and does
                                not mark the tab dirty, probeMovieFile(), the thumbnail
                                path and writing it, the poster record and its path, the
                                format check, writing and removing a poster, and a poster
                                from a pasted link
      release_editor.dart      editor UI: the title with the tracker and release-type badges
                               after it, the field form built from the release type's field list,
                               in as many columns of at least 430 px as the window has room for,
                               each column titled by what its rows are — one column for a
                               photoset pack, because the only column it titles is the one with
                               the fields: its Photosets block is stacked below them, and the
                               columns after it are the photo area, which titles itself too —
                               with the scene row at the top of the left column, the source row
                               and the poster box, Ctrl+S saves, the sections the type has — one
                               form column wide for the two video types, all the columns after
                               the form for the photoset pack, the whole width for the other
                               types, and the columns after the form when they fit — the Stash
                               row and the Screenshots section are single-video only, the
                               Photosets feature is the two photoset types', the Video pack
                               section is the video pack's and the Image folder section is the
                               image folder type's, and the Upload draft section is the four
                               types whose field list has the parent forum, because it is the
                               section that sends what the Message section shows — the single
                               write path the sections use for the values they do not write
                               themselves, which is how the two draft names are written, the
                               notice it passes to the section that gates on whether a message
                               exists, the function the Screenshots and Video pack sections call
                               when a generation run ends, and the same notice the poster path
                               calls when a poster is written or removed, because the poster is a
                               record in images.json and the Upload section shows what that file
                               holds: without it a poster added after a generation is not
                               counted, and one removed is still counted. Those sections cannot
                               see each other and the widget that places both is where they meet,
                               and the source row label, which is per type because a folder with
                               videos is a different thing to pick than a folder with photosets.
                               A row shows the words for a problem the last generation refused,
                               and only a row the user can type into shows it: the rows the app
                               fills are not something the user can fix here. The problems reach
                               this widget from the Message section through a plain callback,
                               because the section cannot mark a row it does not build (rule 3).
                               A column is empty for a type with no field the user writes, so the
                               image folder form is the poster box and the right column.
    screenshots/
      images.dart               ImageKind + ImageRecord (the item it belongs to, the kind, the
                                file path relative to the release directory, the
                                photo-hosting urls per hoster and per URL type) +
                                ImagesManifest, the contents of images.json as one flat
                                record list, in the order the file lists them +
                                generatedImageKinds, the kinds a generation run writes, so a run that
                                regenerates replaces only those and never a poster or a copied photo,
                                and primaryPoster(), the first poster record, which is the one with
                                no item — the rule is the manifest's, because order is data, so the
                                editor and the clone feature read it through this rather than each
                                keeping its own copy
      images_store.dart         ImagesStore (load/loadSync/save) for images.json at
                                the release directory root; a missing or unreadable
                                file reads as an empty manifest
      screenshots_controller.dart  ScreenshotsController: the item it works on, the records its run's
                                files become as it writes them — reported through a
                                callback the widget passes in, so a frame can be shown
                                before the run ends — writing images.json for that item,
                                and the stamp. The generation rules are the service's,
                                so this is the thin half: a service reports files, and a
                                record is a file plus the item it belongs to.
                                `imagesFor(item)` is what the section shows: the records
                                of this item whose files are on disk. `aspectRatio(path)` is the
                                ratio a tile is laid out at, read from the header of the file the
                                section shows, or null for one whose header cannot be read. Typed
                                result, no
                                listener, no context
      screenshots_section.dart   ScreenshotsSection: the title row with the Generate button at the right,
                                the slider (3-20; the minimum is the section's, not
                                the generation's — the Video pack section allows 0) with the label and the
                                count on the same row, the shape the Video pack section has, and the
                                generated images as a masonry in two equal columns, packed by the shared
                                `masonryPositions` with the screenlist first, so it is the top of the left
                                column, and with the span capped at 1 because every frame is above the span
                                ratio and spans would make the grid one column. With no item it shows the
                                placeholder saying to select a video first and shows no controls. It shows the
                                records of the item plus the ones the run in progress has reported, so a frame
                                appears as it is written rather than when the run ends, and it calls the
                                function the editor passed it when a run ends, because the count the Upload
                                section shows reads the records. The tiles are the shared `ImageTile`, each at
                                the shape its file reports, so nothing is cropped, and the gap is
                                between the columns as well as between the rows.
    photosets/
      photosets_controller.dart  PhotosetController: runs the scan with the item boundary its
                                 type has, records the items it found and the per-item counts,
                                 and returns the values the scan counted for the editor's single
                                 write path, kept to the names the type's field list has; typed
                                 result, no listener, no context. Copies the photos the rule
                                 picked into the release and records them as `kind: photo`,
                                 replacing the records this run writes (`ai/picking.md` §7). The
                                 display name is derived from the item path here, because the
                                 stored path is the record ID and is also the folder the copied
                                 photos go in. `aspectRatio()` is the ratio a tile is laid out at,
                                 from the header of the file shown
      photoset_group.dart      PhotosetState: the controller and the generation the two widgets
                               that show a photoset read. For a pack the run and the pictures are
                               two grid cells, so neither widget can own them and the generation
                               cannot be one widget's counter (`AGENTS.md` §5); the editor, which
                               places both, holds it. What a run wrote is recorded here, so the
                               cache is emptied for those paths and the generation moves only
                               when the run wrote something. Also the strings resolved per type,
                               one set as the feature lays it out, the line naming it, the tile,
                               the one grid shape, and the four numbers the grid is built from:
                               the width a portrait's column is, the width a landscape's is —
                               which is the number of columns a landscape spans — the widest the
                               block's column is, and the widest a column of the pack's grid may
                               be stretched to, twice the portrait width, because a zone capped
                               at the columns its photos need cannot always use the space it is
                               given. Also the zones the pack's grid is drawn as: the photos of
                               one kind with the columns that kind gets and the column the zone
                               starts at, so each kind is packed inside its own columns and the
                               drawing places the zones side by side (`ai/picking.md` §7). The
                               numbers are here because a private helper in one file cannot be
                               read from the other.
      photoset_block.dart      PhotosetBlock: the data block as the page's second column, at the
                               most the width this feature gives it — its
                               heading with the Scan and Pick buttons at the right, the rows the
                               editor gives it, and the line naming each set the scan found. Pick
                               is disabled until a scan has run, because the rule reads the
                               counts. No slider: the number is decided by the rule, and the
                               block shows what it decided (`ai/picking.md` §7). Its rows are the
                               path the user picked and the counts the scan took, which the
                               editor builds because they are form rows; every other type keeps
                               those as rows of the form. For a single photoset it is the whole
                               feature, because there is no space beside it for the pictures, and
                               it draws them with the same grid this feature uses
                               (`ai/single_photoset.md` §7). What the scan
                               or the pick could not take is reported as a message. The lines are
                               keyed `groupHeader` by the item's path rather than the name it is
                               shown under — two items that would share a display name are still
                               two sets.
      photoset_gallery.dart    PhotosetGallery: the area a pack shows its picked photos in — the
                               title row, and the grid this feature fits from the two widths it
                               gives, split by kind for a pack, at the space the page has left
                               after the two columns. No state: a run happens in the block, and
                               the page builds again afterwards, so the pictures here are
                               resolved against the cache the run emptied. A tile labels itself
                               with its file name and with the set it is from, because nothing
                               groups the photos. The area is keyed `photosetGallery`, the lines
                               in the block `groupHeader`, and the tiles `photoTile` by the path
                               each is shown from (`ai/picking.md` §7). The tiles are the shared
                               `ImageTile`, at the box height the packing worked out for each
                               photo, with a key that changes on each run because a re-pick
                               writes the same names (`AGENTS.md` §5).
      video_pack_controller.dart  VideoPackController: runs the scan, records the items it
                                  found and the values the probe reported for each,
                                  returns the values the scan counted for the editor's
                                  write path, and reads the items back for the section.
                                  Runs the generation service for every item, reports
                                  each record as its file is written so the section can
                                  show a frame before the run ends, and writes
                                  images.json once for the whole run; `imagesFor(item)`
                                  is what the table's two flag columns read. Typed
                                  result, no listener, no context. Copies nothing,
                                  because a video pack copies nothing into the release
                                  (`ai/video_pack.md` §2); what it writes is the
                                  manifest and the stamp for the files the run wrote
      video_pack_section.dart     VideoPackSection: the title row with the Scan and Generate buttons at
                                  the right, the slider (0-20), the videos as a table
                                  with one row each, and what the two runs could not do,
                                  listed by name. Nothing is shown before a scan,
                                  because opening a release is a read and changes
                                  nothing; a release opened from a manifest shows the
                                  items it recorded. A row shows the name, the size, the
                                  duration, and the two flags the generation writes, and
                                  clicking it shows the values the row does not, and the
                                  images the run wrote for that item: the screenlist at
                                  the detail's width, the screenshots as small tiles in
                                  a wrap, built only for the row that is open. It shows
                                  the records of the item plus the ones the run in
                                  progress has reported, so a frame appears as it is
                                  written, and it calls the function the editor passed
                                  it when a run ends, because the count the Upload
                                  section shows reads the records. The value columns are
                                  right-aligned and a header follows its own column, and
                                  every other row is tinted so the table reads as bands,
                                  with the padding that makes a band read as a band; the
                                  tint is the row's, so it covers the detail as well,
                                  and it is on the row's own `Material` because the
                                  hover highlight is painted on the canvas of the
                                  nearest `Material` ancestor (`ai/video_pack.md` §5)
    image_folder/
      image_folder_controller.dart  ImageFolderController: runs the scan with the source as the item,
                                    copies every image it counted into the release in filename order and
                                    records them as `kind: photo` for that item, writes images.json, stamps the
                                    last edit for a run that copied, and returns the values the scan counted for
                                    the editor's single write path, kept to the names the type's field list has.
                                    Reports the files it did not count, because the reader reports nothing it
                                    skipped (`ai/image_folder_upload.md` §3). Typed result, no listener, no
                                    context. No provider entry: the widget builds its own controller from the
                                    scope, as the other sections do.
      image_folder_section.dart     ImageFolderSection: the title row with the Scan button at the right, the
                                    images as a masonry, the count line, and what the run could not take
                                    reported as a message. No Pick button
                                    and no slider, because for this type the scan and the copy are the same
                                    action and the number is what the folder contains. The tiles are the shared
                                    `ImageTile`, at the box height the packing worked out for each image, with a
                                    key that changes on each run because a re-scan writes the same names
                                    (`AGENTS.md` §5).
    upload/
      hosters.dart              the hoster registry: the names `--server` takes, in the
                                order the section lists them, each with its icon asset and
                                the settings service whose value its script reads. Two
                                lists, the real hosters and the mock ones that call
                                `test-hoster/rp_test_hoster.py`, chosen between by the
                                `--dev` flag `main()` sets. The mock hosters have no icon
                                asset, so they are drawn with the placeholder
      hoster_icon.dart          the icon for one hoster as `Image.asset`, with a neutral
                                placeholder when the asset is not there
      upload_controller.dart    UploadController: the skip rule, one image at a time per
                                hoster with the hosters running at the same time, the state
                                the bars show read from images.json, the progress reports
                                through a callback the widget passes in, writing images.json
                                after each upload, and the environment a call gets — only
                                for a hoster whose script reads a credential; typed result,
                                no listener, no context
      upload_section.dart       UploadSection: the title row with the Upload button at the right, the
                                hoster list with checkboxes (every
                                hoster checked at first, inactive for a hoster
                                whose credential is missing, with a tooltip saying
                                where to set it), and a
                                progress bar for every hoster, drawn from the
                                state read when the section is opened. Until the
                                release has both a poster and a screenshot there
                                is nothing it could upload, so the section shows
                                the placeholder saying what has to happen first
                                instead of the list, and that condition is read
                                again with the counters. The
                                counters are read again when a generation run
                                ends: the section registers its rebuild with the
                                editor, which calls it, because the count is the
                                count the release has and the two sections cannot
                                see each other; a run here ends by calling the
                                editor's notice, which rebuilds every registered
                                section, this one included
                                drawn from the state read when the section is opened
    torrent/
      torrent_controller.dart   TorrentController: the paths — the
                                source as the user picked it, and
                                `<release name>.torrent` in the release
                                directory — and the call, with the progress
                                reported through a callback the widget passes
                                in; typed result, no listener, no context.
                                The file is an output, not a record, so
                                nothing is written to images.json or
                                release.json and a run writes over what is
                                there. It also says whether the file is already
                                on disk — a synchronous check, because the
                                widget asks while it builds, the same way the
                                poster box asks for its file — and opens the
                                folder through FolderOpener for the link the
                                section shows. The flag is read through
                                service/torrent/torrent_file.dart, and the modify
                                call is given the file the app writes, so the one
                                the run changes is the one the section shows
      torrent_section.dart      TorrentSection: the title row with the Create
                                button at the right, the Private flag row under
                                it, the progress bar and the
                                percentage, the rate and the time left as the
                                tool reports them, then what the run ended
                                with. The bar is drawn only once a run has
                                started, because before a run there is nothing
                                to show; the percentage and the outcome are
                                widget state, because the app records nothing
                                for the file and the section is the only place
                                the run's outcome exists. A release opened
                                again can already have the file, so the section
                                says what it finds before any run. The path it
                                shows is a link that opens the release folder,
                                and a failure to open it is said rather than
                                swallowed. The outcome is said in the section
                                rather than in a snackbar, because the section
                                is already the thing that shows the run. With no
                                source picked the title row has no action and the
                                section says what has to be picked first, the
                                wording decided by the release type's sourceKind;
                                what a file already on disk says is still shown,
                                so the placeholder only stands for the case where
                                there is nothing else to say. The source is not
                                state this section holds, so it registers its
                                rebuild with the editor, which calls it when that
                                row is written to. The flag row shows what the
                                file states when one is on disk, and the value
                                in release.json only when there is none, as the
                                file is what the flag describes. The row is not
                                drawn when there is neither a source nor a file
                                (rule 14), because with neither nothing can use
                                the value. Changing it
                                while a file is there is a run, so the section
                                asks first and runs only on the answer, and a
                                dismissed popup is not an agreement. The row is
                                inactive while a run is going and when the file
                                cannot be read, as a row cannot show a flag it
                                has not read. The flag is in the record, so the
                                write is the editor's: the section reports the
                                change path for a value with no file, and the
                                write path for a flag whose file a run changed
                                there: then there is nothing left to save.
                                No dirty flag of its own, not part of Ctrl+S
    message/
      message_store.dart        MessageStore (load/loadSync/save/delete) for the two
                                text files the section owns — message.txt and
                                title.txt — at the release directory root, with no
                                trailing newline. A file that is not there is not an
                                error, because a reset removes files that may already
                                be gone
      screenshot_layout.dart    ScreenshotLayout: the two shapes the block can have, by
                                hoster or by item. It is stored on the release, in
                                `release.json`, because `message.txt` holds a block built
                                with one of the two, so a release opened again shows the
                                shape its post was written with. Only the type with more
                                than one item can choose, and a file without the key reads
                                as the shape the block has always had
      message_controller.dart   MessageController: builds the values the template reads, the
                                screenshot block, in the shape the release chose or the flat block
                                for the types that cannot group, and the app signature block when
                                the release asks for it, calls the renderer, writes both
                                files; typed result, no listener, no context. Says whether every
                                image the message reads has been uploaded to the
                                poster hoster — a synchronous check, because the
                                widget asks while it builds. Validates the fields
                                before it reads anything, so a release that cannot
                                say what the template reads is a typed result with
                                the field names rather than a render. Holds the values
                                the last render read and says whether the current ones
                                are still those, which is what a reset is decided from:
                                a generation records them only when the write succeeded,
                                and opening a section takes the values as they are then,
                                because nothing says what generated the text it read from
                                the files. Removes the two files for a reset and answers
                                with `MessageCleared`, which reports nothing back
      message_section.dart      MessageSection: the title row with the Generate button at the right, the
                                app signature checkbox, the title line, and the large text box showing
                                the post text, each with a copy button. The checkbox row is drawn first,
                                and the row of radio buttons that chooses the shape of the block is drawn
                                before the title line, for the type that can choose, and only while
                                 the generation gate is open (rule 14): before an upload there is no
                                 render for either flag to affect, and both show what the
                                release holds and both are part of `release.json`, so the section reports
                                them to the editor, which is the widget with the write path. The radio
                                row is a `RadioGroup` with `Radio` children, because `Radio`'s own `groupValue`
                                and `onChanged` are deprecated in the Flutter version this project uses.
                                The
                                button for the box is at its top rather than in its middle, through
                                the decoration's suffix slot with the text aligned to the top, because
                                a suffix icon is centred by `InputDecorator`. Only what there is to show
                                is drawn: no title line while there is no title, and the placeholder
                                instead of the box while nothing has been generated; the button in the
                                title row is drawn only when every image the message
                                reads is uploaded to the poster hoster, and the
                                placeholder says what has to happen first while it is
                                not. That is state the Upload section changes, so
                                this one registers its rebuild with the editor. The
                                title line is drawn only for a type that has a title
                                (`hasTitle`). A generation refused by validation is
                                shown as one line per problem, in the order the field
                                list lists the fields, with the words the name has,
                                because the controller answers with names rather than
                                text. The same problems are given to the editor,
                                which is the widget that builds the rows and
                                marks the ones the user can type into, because
                                a section cannot mark a row it does not build
                                (rule 3). What the box shows is a render of the values
                                the template reads, so a change to them makes it stale
                                and the section goes back to its placeholder, taking the
                                two files with it, because the files always match what the
                                section shows. The form and the Upload section are outside
                                this widget, so the notices reach it, and the Upload draft
                                section that gates on whether a message exists, through plain
                                callbacks it registers with the editor: the single field
                                write path and the end of an upload run, and the notice this
                                widget itself calls when the box changes — a generation, a
                                reset, or an edit the user typed. A field is any
                                field, including the ones the app fills; an image is a
                                change only when the run added a URL the message reads.
                                The reset is silent, and nothing is cleared when there is
                                nothing to clear
    draft/
      draft_controller.dart     DraftController: the two text files the Message section owns are
                                what a run sends, so the box is not read; the shape rule for the one
                                field this feature owns, asked for that field rather than for the
                                whole list, because the required set of its type is not known and
                                the URL shape is the gate whatever the type is; and the run, with
                                the same checks the widget gates the button on, so a run is not
                                reached with a value they refuse. Typed result, no listener, no
                                context. It holds nothing that can change while the app is running
                                except the settings feature it is given: the cookie is read from it
                                per call, and a run does not log in — the login is the settings
                                page's action, because the site asks for a captcha after a few
                                logins and the app cannot read one (`ai/pornolab_login.md` §7)
      draft_section.dart        DraftSection: the title row with the Upload button at the right, the
                                parent forum row, and the link the release holds as a link that
                                opens the browser. Only what there is to show is drawn: the row and
                                the button only when a message exists, and the placeholder in place
                                of the row while nothing has been generated; a link the release
                                already holds is still shown, because it is what a run wrote. The
                                button is disabled while a run cannot be made and its tooltip says
                                which of the three is missing, in the order a run needs them: the
                                message, a stored cookie, the forum. The row shows the shape rule
                                with the words the form's rows use, and the words for a result are
                                the mapping the settings page reads them from too (§4), so the gate
                                and the message cannot disagree. What a run said is shown as text,
                                including the line for the run that had to make a new draft, because
                                the link the release holds changed and the user cannot see why
                                otherwise; a run that updated the stored draft says nothing. The link
                                the site answered with is written through the editor's
                                single write path, because this section has the field and the editor
                                is the widget with the write path (rule 3). The link is also copied:
                                the copy button next to it is the same call the Message section's
                                copy buttons make, and nothing is said when it works, as they do.
                                The label above the link says what it is, because the link's text is
                                the link itself, and both labels of this section are resolved
                                through `fieldLabel` as the form's rows are. It reads the settings
                                feature through the provider, because the gate is the credentials
                                rather than the cookie
    settings/
      settings.dart               AppLanguage + SettingsField + Settings (the
                                  app language, the default release directory,
                                  the two release defaults, the plain-storage
                                  flag, the values stored plainly) + toJson() —
                                  the app's first app-level state — plus
                                  resolveUserPath, for a stored path that starts
                                  with ~; it takes the path context as a
                                  parameter, because the context is what decides
                                  the separator and a rule that reads the
                                  platform can only be tested on the platform it
                                  reads
                                  SettingsSection is the sections the page has, in
                                  the order its left side lists them. It is not
                                  private to the page, because the section a
                                  settings tab shows is the tab's state, held on
                                  the `AppTab` record, so the selection is still
                                  there when the user comes back to the tab from
                                  another one.
                                  SettingsField is the fields the Integration
                                  section has, named by the key the credential
                                  store uses, with the flag that says which of
                                  them the page obscures: a display rule, not a
                                  storage rule, because every entry is stored
                                  the same way and the username is the one shown
                                  plainly. `pornolabCookieKey` is the key the
                                  cookie a login gives is written under; it is
                                  not a field, so nothing on the page writes it
      settings_store.dart         SettingsStore (load/save) for settings.json in the app data
                                  directory; a missing or unreadable file reads as the defaults.
                                  The directory is a constructor parameter as a function, because
                                  path_provider is async and a store builds no dependency of its
                                  own
      secret_store.dart           SecretStore (readAll/write/delete) for the OS credential store,
                                  plus PluginSecretStore over the plugin. It is an interface because
                                  the plugin is a method channel and cannot be exercised in a test,
                                  so the settings feature is tested against a fake
      settings_controller.dart    SettingsController (ChangeNotifier): the
                                  settings, the locale the app is given, the
                                  default directory with ~ expanded with the
                                  path context it is given, the values the
                                  Integration section shows, load() at startup,
                                  setLanguage(), setDefaultReleaseDirectory(),
                                  setDefaultTorrentPrivate(),
                                  setDefaultIncludeAppSignature(),
                                  setAllowPlainSecrets() and setSecret() writing
                                  immediately; typed result. setSecret() takes a
                                  key rather than a field, because a field is
                                  what the page draws and a key is what the
                                  store holds. It is the second Listenable in
                                  the app (see §4). It is also the feature that
                                  owns the login, because the login is a call
                                  and the value it obtains is a stored value: it
                                  takes the client and the app directory as
                                  constructor parameters, login() writes the
                                  cookie the answer gives under
                                  `pornolabCookieKey`, and `cookie` is what a
                                  run reads. login() takes the captcha and the
                                  code; a run calls it with neither, which is
                                  the shape the first login is, because a run
                                  has no user to read an image. It is the first
                                  controller another controller depends on (see
                                  §4)
      settings_page.dart          SettingsPage: the section list on the left and
                                  the selected section on the right, with every
                                  field capped at 400 px. Which section is
                                  shown is the tab's state, read from the
                                  `AppTab` record and written back through
                                  `TabManager`, the way the editor reports its
                                  dirty flag: the content area builds only the
                                  active tab, so the page is thrown away on a
                                  switch and a value it held itself would not
                                  be there when the user comes back; the page
                                  is given the tab id for that. The sections
                                  are private widgets of this page because they
                                  share its controller. The page owns the field
                                  controllers and their focus nodes, and commits
                                  a field on submit, on focus loss, and when it
                                  is disposed, which is what closing the tab
                                  does. Releases is the default release
                                  directory and the two release defaults as
                                  checkbox rows, and the checkbox row is one
                                  helper the page's three checkboxes share, so a
                                  checkbox is drawn the same way wherever it is
                                  on the page. The folder button is to the right
                                  of the field, and the two rows on the page
                                  treat width the same way: a field is capped at
                                  the same 400 px as every other field on the
                                  page, and a row puts its controls on one line
                                  when they fit and one control per line when
                                  they do not, because a field cannot show its
                                  label at a width the label does not fit in, so
                                  where a row stops fitting is what its controls
                                  need measured from the labels the app shows,
                                  which moves with the language. The Integration
                                  section obscures a field from the flag on its
                                  entry rather than masking every field in its
                                  loop, and the two credentials and the button
                                  that runs the login are one row. The row's
                                  fields are capped at the same 400 px as every
                                  other field on the page, so the row does not
                                  make a field wider than the rest of it; what
                                  the row does is put the three controls on one
                                  line when they fit and one control per line
                                  when they do not, because a field cannot show
                                  its label at a width the label does not fit
                                  in. The button's width is measured, so the
                                  point where the three stop fitting is that
                                  point in the language the app is in. The
                                  button is Log in when no cookie is stored and
                                  Log out when one is, in the error colour; it
                                  is disabled while a credential is empty or a
                                  call runs, and the fields are disabled while a
                                  session exists. The page rebuilds when a
                                  field's text changes, because whether the
                                  button can be pressed is read from the fields,
                                  and when the controller changes, because a
                                  login a run made is a change the row has to
                                  show. The note that says where a value lives
                                  is emitted once for the row rather than once
                                  per field. The outcome of the last login is
                                  said next to the row, in the colour that says
                                  which it was: the error colour the page
                                  already uses for a value that was not written,
                                  and a green for a login that worked. The green
                                  is the only colour in the app that is not the
                                  theme's, because `ColorScheme` has no success
                                  role. The words for a failure are the set the
                                  two features share; the word for a login that
                                  worked is this page's, because a run has
                                  nothing to show for one — its success is the
                                  link it was given. The space says the outcome
                                  of the last action, so a logout takes the word
                                  away. When the answer asks for a code the page
                                  shows it: the word, the image the code is read
                                  from, and a field for the code capped at the
                                  same 400 px as the other fields. The same
                                  button is the second half of the login, so it
                                  is gated on the code as well, because a login
                                  with an empty code is the same answer again
                                  and there is nothing to send. The code is not
                                  a stored value and is not committed as the
                                  fields are: it belongs to the page that asked
                                  for it, so a new captcha is a new code and the
                                  text typed for the previous one is cleared. A
                                  captcha is widget state, like the outcome the
                                  row shows is, and is kept only for the answer
                                  that asked for it — logging out cannot be
                                  showing one, because the button is Log out
                                  only when a cookie is stored and an answer
                                  that asks for a code stores none. The image is
                                  shown from its URL and not stored anywhere;
                                  each captcha is a different URL, so the
                                  widget's key changes on its own and the rule
                                  in §5 about an image rewritten under the same
                                  name does not apply here
    recent_releases/
      recent_releases.dart              RecentRelease (the directory path as the key, the technical
                                        names, the source, the three dates) + RecentReleases (the entry
                                        list, the record rule, the cap) + the date comparison and the
                                        sort, which stays pure because the comparator it is given is
                                        what the widget builds for a localized column + the display
                                        names for a stored tracker and type, or the string the file
                                        holds when the app does not know them + the row the scan found,
                                        which has nothing but the path because nothing was read about it
      recent_releases_store.dart        RecentReleasesStore (load/save) for recent_releases.json in the
                                        app data directory; a missing or unreadable file reads as an
                                        empty list. The directory is a constructor parameter as a
                                        function, for the same reason SettingsStore's is
      recent_releases_controller.dart   RecentReleasesController (ChangeNotifier): the list, the record
                                        rule, the availability check, the scan of the default release
                                        directory, the merged view the table draws, the startup read and
                                        the tab it opens as the first tab; the third Listenable in the
                                        app (see §4). Writes as the list changes, so the tab has no
                                        dirty flag, and a failed write is a flag the page shows as a line
      recent_releases_page.dart         RecentReleasesPage: the table, one row per entry or found
                                        folder, with the header that sorts. Which column and which
                                        direction are widget state, as the Video pack table's open rows
                                        are; a column that was not the sorted one starts in its natural
                                        direction. The rows are drawn in the sorted order and the order
                                        the file lists is not changed. The rows scroll inside the tab
                                        while the header stays fixed, because the header is the control
                                        the table is sorted through and the list can be longer than the
                                        tab (the scan has no cap); the write-failure line stays outside
                                        the scroll so it is always visible. A row whose manifest is gone
                                        is dimmed with an icon next to its name whose tooltip gives the
                                        reason; a row click goes through the shared open flow. It asks
                                        for the availability check and the scan when it opens, and
                                        passes the default directory to the scan
    window/
      window_size.dart          WindowSize (the whole pixels the window last
                                had), the app's record of what the window was
                                (`ai/doc.md` §7), + encode() and decode() for
                                the line the format is + the rule that a line no
                                reader can read is read as nothing
      window_size_store.dart    WindowSizeStore (load/save) for window_size.txt
                                in the app data directory; a missing or
                                unreadable file reads as nothing. The app is the
                                only writer: the Linux and Windows runners read
                                the same line, so the rules are the format's,
                                not the store's, and this class does the file
                                and not the interpretation. The directory is a
                                constructor parameter as a function, for the
                                same reason SettingsStore's is
      window_gateway.dart       WindowGateway (currentSize only) +
                                PluginWindowGateway over window_manager. It is
                                an interface because the plugin is a method
                                channel and cannot be exercised in a test, the
                                same reason SecretStore is one; the instance is
                                read at the composition root. It reads the
                                window and does not ask it for a size, because
                                the runners apply the recorded one before the
                                window exists (see §7)
      window_controller.dart    WindowController: recordSize() (read the size
                                the window has and write it when it is a size
                                the app can store and not the size already
                                recorded); typed result, no listener, no
                                context, no widget and no state (see §4). It is
                                called from the close flow, the only place that
                                knows the app is closing for real
    stashdb/
      stash_controller.dart       StashController: the scene ID from what the user pasted, the
                                  request, which form field each value goes into, the URL the domain
                                  is read from and the domain its host gives or the bundled mapping
                                  has, the title with the site number cut off every occurrence of
                                  it, the values the import changed rather than copied as what was
                                  done to them and as the parts the app keeps and the parts it cuts,
                                  the canonical scene URL from the scene ID, the poster, and the file
                                  the popup shows the poster from; typed result, no listener, no
                                  context. The values are read asynchronously because the mapping is
                                  an asset the app reads; the notes are not, because the mapping
                                  changes a value rather than which URL a value came from.
      stash_section.dart          StashSection: the row that is the scene link field — the URL or
                                  ID input with the Fetch button — and the popup a successful fetch
                                  shows, with each value and its checkbox and Cancel and Apply; the
                                  popup owns the selection while it is open, and the poster row
                                  shows its link with the image below it, at the width the row has
                                  and 240 px tall, from the file the controller writes. Below the
                                  poster it has the "Import notes" subsection, titled with
                                  `SectionTitle` like every section, where each value the import
                                  changed is the message that says what was done to it followed by
                                  the value with the parts it cut struck through; a note has no
                                  checkbox because it is not something to apply, and its key
                                  includes its place in the list because the same field can have one
                                  note per studio. The values are not there on the first frame,
                                  because the mapping is an asset the app reads, and the popup shows
                                  them when the read completes. The row owns the focus of its input and takes it
                                  back when the popup closes, so the save key reaches the editor
                                  again. Writes the fields through the editor's single write path,
                                  the poster through its poster path, and the scene URL field on its
                                  own
    system_check/
      system_check_controller.dart SystemCheckController: the tools the app
                                   calls, in the order the page lists them, each
                                   with the version call its wrapper names — the
                                   one place the tools are named, so a new
                                   wrapper is added here and the page needs no
                                   change, because it draws one row per entry;
                                   typed result, no listener, no context. It is
                                   a provider entry because the check is
                                   app-level. The app data directory is given as
                                   a function, for the same reason
                                   SettingsStore's is: ToolRunner needs a
                                   directory per call, and outside a release
                                   there is no release directory. mtn is the one
                                   exception in the mapping: its version call
                                   prints to stderr and exits 255, so for that
                                   tool the line it printed is the result, and
                                   the exit code is not a failure of the check.
                                   The calls run at the same time and each result
                                   is passed to a callback the page gives it, so
                                   a tool that hangs does not hold up the rows of
                                   the tools that answered
      system_check_page.dart    SystemCheckPage: its title, then a header and
                                one row per tool, showing the version the tool
                                reported or the reason it could not be run. The
                                title is the page title style the release name
                                uses, not `SectionTitle`, because that is the
                                row every section titles itself with. The block
                                is capped at 1200 px and centred in the tab, the
                                title with it; the text inside the table stays
                                at the start. The check runs when the page opens
                                and the results are its own widget state, kept by
                                tool name rather than by position, because the
                                results arrive in the order the tools answer, not
                                the order of the list. A row whose result has not
                                come back yet shows the tool name and a spinner
                                in the icon column, so the row keeps the shape it
                                has when the result arrives, and each row updates
                                as its own result arrives rather than waiting for
                                the others. An error row is drawn with
                                colorScheme.error. Tool names are shown from
                                NativeTool.name, not from l10n keys. The name
                                column is a fixed width, because the names are
                                short and the same in every row, and the odd
                                rows take surfaceContainerHigh as the recent
                                table does. A status icon is the state at a
                                glance: a check for a tool that reported a
                                version, the same mark for each reason
  service/
    fonts/
      font_store.dart           FontStore: the font the app ships, written into the app data
                                directory so the tool can open it by path
                                (`ai/bundled_native_tools.md`). libgd resolves a font name
                                only through fontconfig's own configuration, the one that
                                names the system font directories, so the tool is given a
                                path. The font is written once: a file whose length
                                already matches the asset is left alone, so a run that
                                generates screenlists does not rewrite 170 KB for every
                                video. Only the weight the tool draws with is written; the
                                app's own text gets the same font from the asset bundle.
                                `fontPath()` is what a tool call needs: the path of the
                                file. The asset bundle and the app data directory are
                                constructor parameters, so the service reads no static.
    images/
      image_dimensions.dart     ImageDimensions + readImageDimensions(): the dimensions a photo
                                reports, read from its header — JPEG's start-of-frame marker,
                                PNG's IHDR, WebP's chunks — without decoding the image, and the
                                photo extension list that is the same set of formats. The header
                                bytes come through a function rather than a path, so a file and an
                                archive entry read through the same format dispatch.
                                readImageDimensionsSync() is the same header read synchronously, so
                                a widget can lay a grid out while it builds — the same reason
                                ImagesStore.loadSync exists.
      masonry.dart              minColumnWidth and columnGap: the column width the page is built
                                from and the gap between its columns, shared because a section
                                drawn as the page's columns has to draw exactly those
                                (`ai/picking.md` §7). `photoColumnCount()` is as many columns as
                                fit at the width it is given, and `photoColumnWidth()` is the
                                share of the space, so the space is used up rather than leaving a
                                strip at the right narrower than a column; the share may be
                                bounded by a maximum the caller gives, which is what a zone
                                capped at its photos needs, and then the width past the bound is
                                left at the right. `photoSpanCount()` is the number of columns a
                                landscape takes, the number that makes it as wide as the
                                landscape width it is given, because a grid can only be a whole
                                number of columns wide. `isLandscape()` is the line the placement
                                and the counts of each kind share, so they agree on what a zone
                                is, and a photo whose header could not be read is the square the
                                drawing lays it out as. `photoZoneColumnCounts()` is the columns
                                each zone of the pack's grid gets from the two counts: a kind
                                with no photos has none, a kind with photos has at least one
                                column and never more than its photos need, and what the two
                                minimums do not take is shared in proportion to the counts, with
                                a zone already at its need giving its share to the other; it
                                returns nothing when the space cannot hold a column of both
                                kinds, which is the case where the grid is not split.
                                pictureHeight() and tileHeight() are what a tile takes in a
                                column of a given width, tileHeight with the gap that is its own
                                padding. `masonryPositions()`: the placement for a grid of
                                columns of equal width — each photo goes to the columns that are
                                highest at the point it is added, ties to the lower index, and
                                the order is the order the source gives. A photo at or above
                                `landscapeSpanRatio` spans as many columns as the caller allows,
                                and a span starts where all of its columns are free, so the
                                others keep a gap. The Screenshots grid asks for a span of one,
                                because every file there is a frame at the same ratio and spans
                                would make the grid one column. Heights are in pixels, because a
                                tile is its image plus the lines under it, so the placement does
                                depend on the column width. Pure, and tested on its own.
      tool_locator.dart         ToolLocator: where a tool's executable is — the
                                app bundle first, then PATH. A tool with a
                                bundle directory and no path fallback is
                                bundled-only, so a system install of it is not
                                used; one with the fallback is read from PATH
                                when the bundle has nothing there. A file in the
                                bundle is accepted on the same terms as one on
                                PATH: the execute bits. On Windows the name with
                                the `.exe` extension is tried first, because
                                that is what an executable there is named as.
                                `NativeTool` says which case a tool is: the
                                name, the optional bundle directory, and the
                                optional path fallback. The PATH and the
                                platform are constructor parameters, so the rule
                                can be tested on either platform.
      tool_runner.dart          ToolRunner: the only code that runs an external
                                process, + the typed ToolRunResult. It reads the output
                                as it arrives, writes every line to the tool log, stops a
                                call at the window it was given — 60s by default, or the
                                one the call asks for, which mkbrr does — and adds to the
                                child's environment the entries a call is given, which is
                                where a credential goes, because the log records the
                                arguments
      ffmpeg.dart               Ffmpeg: the commands the app uses (version(),
                                resizeImage() — an image resized to at most
                                maxSize px and written as a JPEG, screenshot() —
                                one key frame at the source resolution, written as
                                a JPEG, which is the call both the Screenshots
                                section and the video thumbnail use)
      ffprobe.dart              Ffprobe: probe() — one call for a file's
                                metadata, + the typed MediaProbeResult, and
                                version() — the version line the System Check
                                tab shows
      mtn.dart                  Mtn: screenlist() — one call that writes the
                                frame grid as `_rp_screenlist.jpg`, with blank
                                skipping off so no cell is left empty, and
                                version() — the version line the System Check
                                tab shows. `-v` is the option mtn accepts,
                                `--version` is not; `-v` prints the version to
                                stderr and exits 255, because a run with no
                                input file is an error to mtn. `-P` is on every
                                call, this one included, for the reason the
                                screenlist section gives
      media_info.dart           MediaInfo: the six values the editor shows,
                                formatted as ai/release_editor.md specifies, plus
                                the duration in seconds the thumbnail seeks to
      uptooda.dart              Uptooda: one image to one hoster, with the
                                arguments the spec fixes, + the typed upload
                                result. The result is decided by the `success`
                                field, not by the exit code, because a failed
                                upload and an unknown hoster both look like a
                                success to the exit code. version() is the
                                version line the System Check tab shows
      mkbrr.dart                Mkbrr: create() — one call that writes a torrent
                                for a file or a folder, + the typed result, and
                                version() — the version line the System Check tab
                                shows. The bare command prints its banner without
                                a version, so the check uses the `version`
                                subcommand. create() is given the progress
                                callback and reads the percentage, the rate and the
                                time left out of the carriage-return-separated
                                segments, because that is the tool's format, and it
                                asks for a 60 minute window rather than the
                                runner's default (`ai/torrents.md`). modify()
                                changes the flag of a file that is already there;
                                the reason a failed one prints is read from the
                                output, because a modify that cannot process the
                                file still exits 0 (`ai/bundled_native_tools.md`)
    photosets/
      photoset_scanner.dart     PhotosetScanner: reads the picked folder, decides which entries
                                are items — the rule is given to it per type as `ItemBoundary`,
                                because a pack is the entries under the source and a single
                                photoset is the source itself (`ai/single_photoset.md` §5) —
                                counts and measures the photos in each, and lists the formats
                                among them. The readers are behind an interface, so a format can
                                be added without changing the scan (`ai/photoset_pack.md` §5); the
                                interface also gives the whole photo, for the photo the picker
                                copies. + the typed scan result. Called only when the user
                                asks.
      directory_reader.dart     DirectoryPhotosetReader: a photoset that is a directory — the files
                                directly inside it, in name order.
      zip_reader.dart           ZipPhotosetReader: a photoset that is a ZIP archive — its entries,
                                in the order the archive lists them. Reads the central directory
                                through the `archive` package, the one place rule 12 is set aside,
                                because the parts a hand-written reader gets wrong are the ones real
                                archives have: zip64 sizes, data descriptors, encrypted entries.
                                Reads only the bytes a header is made of, not the entry; the whole
                                entry is read separately, for the photo the picker copies.
      photoset_picker.dart      PhotosetPicker: the picking rule (`ai/picking.md`) — the number,
                                the division across the sets by largest remainder, the positions
                                inside a set. Pure: takes the scanned sets, returns the picks,
                                writes nothing, and shows no messages.
    videos/
      image_generator.dart      ImageGenerator: the rules that turn one video file into the images the
                                 app writes — the key-frame times, the file names, the screenlist rows,
                                 the ffmpeg and mtn calls. It writes the files and reports each one as
                                 it writes it, as paths relative to the release directory, so the caller
                                 can show a frame before the run ends; it does not record them, because
                                 a record is a file plus the item it belongs to, which is the feature's.
                                 + the typed per-item result and the failure vocabulary both sections
                                 map to text, including the `stopsRun` rule. Called only when the user
                                 asks (`ai/doc.md` §2).
      video_scanner.dart        VideoScanner: walks the picked folder, decides which files are
                                items by the extension list, takes the size each has on disk, and
                                probes each one with the existing Ffprobe, one call per item; a file
                                it cannot probe is still an item, reported by name. + the typed scan
                                result. Called only when the user asks. No reader interface, because
                                there is no container format here (`ai/video_pack.md` §4).
    torrent/
      torrent_file.dart         readPrivateFlag(): the Private flag as a torrent
                                file states it — the two dictionaries it can be in
                                are walked, the file's top-level one and its
                                `info` entry, and the integer value there is the
                                flag. A value that is not the flag is skipped
                                rather than decoded, because the pieces are the
                                largest part of a real torrent and nothing here
                                needs them. A file whose `info` has no `private`
                                key is not private, which is what the format means
                                by the flag being absent; bytes that are not a
                                bencoded dictionary are reported as unreadable
                                rather than guessed at. A pure function over the
                                bytes, like `image_dimensions.dart` is over a file
                                header, so the rule can be tested without a file.
                                + the typed read result.
    template/
      style.dart                Style: a parsed style file — key = value, one rule per
                                line, `{content}` as the slot body, `{token}` as another
                                key, no inheritance. `ai/description_template.md`.
      template_renderer.dart    TemplateRenderer: the mustache subset the message uses —
                                variables, conditional and inverted sections, style slots,
                                `{{blank}}`, block variables. Line-based: one template line
                                produces one output line, a line that renders to nothing is
                                dropped, consecutive blanks collapse, leading and trailing
                                blanks are trimmed, no trailing newline. Written by hand
                                because rule 12 allows no third-party packages.
      template_store.dart       TemplateStore: reads the template and the style for a
                                tracker and release type from the app bundle. The title
                                is read per release type first, and the tracker's
                                `title.txt` is the fallback when that type has no file of
                                its own (`ai/single_photoset.md` §8); a type with no title
                                reads neither (`hasTitle`). The app signature is one
                                file per tracker, `appSignature.txt`, read as text with
                                its trailing newline kept (`ai/description_template.md`
                                §App signature). A key the bundle does not have
                                is read as absent, not as a crash, because the bundle throws
                                `FlutterError`, an `Error` and not an `Exception`. The asset
                                bundle is a constructor parameter, so the service reads no
                                static.
    logging/
      tool_log.dart             ToolLog: the JSON Lines log under
                                `<release_dir>/logs/`, one entry per output
                                line, named with the date of the first entry,
                                writes serialized with a lock. The directory is
                                the one the caller gives per call, so the System
                                Check writes to the app data directory, where
                                there is no release.
      tool_log_entry.dart       the shape of one entry: date, tool, the input repeated
                                on every entry, stream, line — and the exit entry that
                                closes a call with its exit code, and the three entries a
                                network call is recorded with: the request, the response, and
                                the failure that closes a call with no answer. A value that
                                does not belong in a log file is written as the redacted
                                marker, which is what the cookie is recorded as. The response
                                entry carries the headers too, as the rule that says which of
                                them belong in a log file left them
    network/
      image_downloader.dart     ImageDownloader: downloads one file, + the typed DownloadResult
                                that says what the response called the file. One of the two
                                Dart paths that make a network request; uptooda makes its own
                                requests, but it is a process the app runs, not Dart code
      stash_client.dart         StashClient: one GraphQL query to StashDB over the same client,
                                + the typed result and the scene as the schema describes it, and
                                the studio as the schema has it — the name and the URLs, because
                                the domain is read from those. No GraphQL package: a GraphQL
                                call is one POST with a JSON body, and the key goes in the
                                ApiKey header. parseResponse is the part the tests exercise,
                                because the transport cannot be
      pornolab_client.dart      PornolabClient: the three requests `ai/uploading_draft.md` and
                                `ai/pornolab_login.md` describe — the login, the page that gives the
                                form token, then the call that saves a draft — over the same client,
                                + the typed result. An interface, as StashClient is, so the feature
                                is tested against a fake; the rules it applies (a forum id read from
                                a URL, the form body, a token read from a page, a response read as
                                JSON, a `Cookie` value read from the `Set-Cookie` headers, and
                                whether an answer means a login was accepted) are functions on the
                                interface, so a test exercises them without a request. A `gone`
                                answer is read as the stored draft not being there, and the client
                                answers it by asking for a new draft once, because `draft_id` 0 is
                                the call that creates one (`ai/uploading_draft.md` §6). The login
                                form is encoded in Windows-1251 as the site's own form sends it,
                                which is the one request that does not use the app's UTF-8 rule.
                                Two of its fields are the form's own rather than data the app
                                chose: the hidden redirect field, and the submit button whose
                                value is the word the site uses, so both are constants rather
                                than translatable strings. A character the codepage cannot
                                represent is sent as its UTF-8 bytes, as a browser sends it, so
                                a password with one is a refused login rather than an exception.
                                A redirect means the
                                login was accepted, a 200 login page means it was not, and the
                                login page that asks for a code is a refused login the user can
                                still answer, so that is the one result that carries what the page
                                gave. A `Set-Cookie` alone is not proof, because the site sets one
                                for an anonymous visitor too. The three parts of a captcha are read
                                out of the page that asks for it, including the name of the code
                                field, which is a hash that changes with the page and so cannot be
                                a constant; a page with only some of the three is the refused login,
                                because a code the app cannot show is a code the user cannot type.
                                The token cache is the only state any service
                                holds, and it is dropped on a login and on a token the site does not
                                accept. A run is made once, and the app does not make a login from
                                one (`ai/pornolab_login.md` §7). A redirect on the page the token is
                                read from is read by where it would have gone: the login page is the
                                cookie the site did not accept, and any other answer is the request
                                failing. That rule is a function on the interface as the others are,
                                and the location the site sends is a full URL while a relative one
                                names the same page. The User-Agent is built from `app_info.dart`
                                rather than a generic client string, with the name as one word
                                because a product token is one word. The limit is the 60 s one
                                ToolRunner has, redirects are not followed, and the request and the
                                response are logged with the cookie redacted — no cookie is ever
                                recorded, and the first login request sends no `Cookie` header at
                                all, the one exception being the request with a code, which sends the
                                cookie the captcha page gave as a browser would —
                                and so is a request that got no answer, recorded as the failure
                                entry. A response is read as the charset its Content-Type declares,
                                since the site's pages are not UTF-8; a charset the app has no codec
                                for, or none declared, is read as Latin-1, which cannot fail, and
                                the response headers it logs are the ones that carry no credential.
                                The login's response body is read for the judgement, because the
                                judgement has a third shape, and is not recorded: what the entry
                                records as what was read is the cookie, which is never recorded as
                                its value
    stashdb/
      domain_map.dart           DomainMap: the domains the app writes in a form of its own,
                                read from `assets/stashdb/domain_map.json`. The domain rule
                                writes a host as the host gives it, and a host is lowercase,
                                so a studio that capitalizes its own domain cannot be
                                recovered from it; the file is the list of the domains the app
                                writes differently, and a value is used exactly as it is
                                written. A key is read as the app computes the domain —
                                lowercase, without `www.` — so the file can be written as a
                                person sees it rather than as the rule would produce it. A
                                file the bundle does not have, or that is not an object, is
                                read as an empty mapping rather than a crash, because the
                                mapping is optional data. The asset bundle is a constructor
                                parameter, so the service reads no static.
    launcher/
      folder_opener.dart        FolderOpener: opens a folder in the file manager
                                the OS uses, + the typed result. One of the two uses of
                                url_launcher, and one of the two services that call a
                                platform plugin rather than a process or the filesystem
                                (`ai/torrents.md`)
      url_opener.dart           UrlOpener: opens a link in the browser the OS uses, + the
                                typed result. The second use of url_launcher
                                (`ai/uploading_draft.md`); it shows no messages, so the widget
                                maps a failure to localized text (rule 13)
  l10n/
    app_en.arb                  template (arb-dir == output-dir == lib/l10n)
    app_ru.arb
    app_localizations.dart      generated
    app_localizations_en.dart   generated
    app_localizations_ru.dart   generated
  TODO.MD                       open items

test/                           tests (§10): widget tests + native tool tests
test-hoster/                    the test photo hoster, run by hand: `rp_test_hoster.py`,
                                an HTTP server the `rptest-a` and `rptest-b` hosters call,
                                with the upload latency and the success rate given to it on
                                the command line — serving is not simulated, so what it
                                stores is served back at once. It stores what it is given
                                under `test-hoster/photos/<tag>/` (gitignored), and
                                `README.md` says how to run it. The rules are in
                                `ai/bundled_native_tools.md`.
dart_test.yaml                  test timeout: 30s, concurrency: 4
assets/icons/                   tracker icon assets; declared under
                                `flutter: assets:` in pubspec.yaml, so they are
                                bundled. `assets/icons/pornolab.svg` is the one
                                entry `trackerIconAssets` maps to.
assets/icons/hosters/           the hoster icons, PNG, also declared under
                                `flutter: assets:`. `hosters.dart` maps each hoster to a
                                file here.

assets/stashdb/                   the domains the app writes in a form of its own, one entry
                                per domain, read by `DomainMap` (§2). Declared under
                                `flutter: assets:` in pubspec.yaml, so it is bundled.

assets/templates/pornolab/      the description template, the title template and the default
                                style, read by `TemplateStore` (`ai/description_template.md`).
                                The folder is the tracker's technical name and the template file is
                                the release type's, so `singleVideo.txt` is what
                                `ReleaseType.singleVideo` names. Declared under
                                `flutter: assets:` in pubspec.yaml, so they are
                                bundled.

assets/fonts/                   Roboto Regular and Bold, the font the app ships,
                                 declared under `flutter: fonts:` in pubspec.yaml and
                                 asked for by name in the theme, so the app's UI text
                                 resolves to them on every platform and the
                                 screenlist draws with the same font
                                 (`ai/bundled_native_tools.md`). `Roboto_LICENSE.txt`
                                 (Apache 2.0) is committed with them. Only Regular is
                                 written to the app data directory, because that is the
                                 weight the tool draws with; the store that writes it is
                                 `lib/service/fonts/font_store.dart`.

native/uptooda/                 the tool the app ships: `Data/` plus one binary per OS,
                                plus three files only the Windows build needs: its CA
                                bundle, the MIME database, and the WebView2 loader
                                (`ai/bundled_native_tools.md`). The install step copies
                                them next to the app, and the tool reads `Data/` from its
                                own directory, so the layout has to be preserved.
                                `native/uptooda/uptooda-cli` is a gitignored working copy
                                placed beside `Data/` so the tool can be run from the repo.
                                The rules are in `ai/bundled_native_tools.md`, including
                                that changing a script needs a full app restart: a running
                                app reads the copy the install step made at build time, so
                                hot reload and hot restart are not enough.
                                `Data/Scripts/rptest_a.nut` and `rptest_b.nut` are the test
                                hoster scripts, which call `test-hoster/rp_test_hoster.py`
                                — a server that is not part of the bundle and is run by
                                hand.

native/mkbrr/                   the other tool the app ships: one binary per OS, no data
                                files. It is committed with the executable bit and installed
                                with `install(PROGRAMS)` in its own directory next to the app
                                executable. A Linux and a Windows binary are committed; macOS
                                is not, so there the resolver reports the tool as not present
                                (`ai/bundled_native_tools.md`).

native/media/                   the Windows build of ffmpeg, ffprobe and mtn with
                                the DLLs the three load. One directory, because the
                                three share one set of DLLs and the loader looks in
                                the executable's own directory first, so the whole
                                closure has to be beside the binaries. Installed as
                                `<app directory>/media/`, which is the bundle
                                directory the three tools name
                                (`ai/bundled_native_tools.md`).

ai/doc.md                       this document
linux/ windows/ macos/          platform runner directories
linux/assets/                   the app icon, `app_icon_512.png`. It is not under
                                `assets/`, because that folder is the Flutter asset
                                bundle and the icon is read as a file, not as an asset
                                entry. The install step copies it into the icon theme
                                under the application id, which is the name the runner
                                and the .desktop file both use.
linux/desktop/                  `com.example.release_prepper.desktop`, the file a
                                desktop environment matches a running app to through
                                its application id. Its Icon line names the icon
                                through the theme rather than by a path, so the icon
                                has to be in a theme directory under that name.
linux/runner/                   the GTK runner. It sets the window icon by the
                                application id through the icon theme, the same
                                name the .desktop file uses. On Wayland a window
                                has no icon of its own, so the icon there comes
                                from the .desktop file; the runner's call is
                                what an X11 session reads. An application id
                                with no icon in the theme is reported with a
                                warning rather than left as the default icon. It
                                also reads `window_size.txt` before it creates
                                the window, so the window is created at the size
                                the last run had (`ai/doc.md` §7), and takes its
                                own default when the line is not one it can
                                read.
windows/runner/                 the Win32 runner. `window_size.cpp` reads the
                                same line as the Linux runner does, from the
                                directory `path_provider_windows` names, and
                                `main.cpp` creates the window at it; a recorded
                                size is in physical pixels, so it is not scaled
                                to the monitor, which is the `scale_size`
                                argument `Win32Window::Create` has for this
                                (`ai/doc.md` §7).
windows/runner/resources/       `app_icon.ico`, the icon the Windows runner shows in
                                the titlebar and the taskbar. It is the app's own
                                icon, the same artwork as
                                `linux/assets/app_icon_512.png`, at the sizes Windows
                                reads, 16 to 256 px. `Runner.rc` names
                                it as `IDI_APP_ICON`, and the runner loads that for the
                                window class, so a window with no icon there takes the
                                default Windows one.
changelog/                      one `<version>.md` per release, the notes a
                                release publishes. The file is the notes and
                                nothing else, so its contents go to the release
                                as they are; the version is the file name, which
                                the three-component form pub requires, which is
                                why the workflow takes the version rather than
                                the notes. It is committed before the run, so
                                the commit the workflow makes is the version
                                bump and nothing else (§9).
.github/workflows/              `windows-release.yml`, the Windows release. It
                                is where the Windows app is built, because
                                `flutter build windows` only runs on a Windows
                                host. It is run by hand from the Actions tab,
                                with the version to publish as its input: it
                                writes the version into `pubspec.yaml` and the
                                `appVersion` const in `app/app_info.dart`,
                                commits the bump with the version as the commit
                                header and the changelog file as the body,
                                pushes it, and publishes the install directory,
                                which is the app, as the asset of a GitHub
                                Release for the tag `v<version>`, at the commit
                                it made (§9).
.widget_preview/                generated `flutter widget-preview` scaffold (gitignored)
```

Naming conventions in use:
- Widgets: `snake_case.dart` (`release_wizard.dart`, `tab_strip.dart`).
- Controllers: `<widget>_controller.dart`, one per widget, co-located.
- Feature code lives under `lib/feature/<feature>/`; shared UI under
  `lib/feature/`.
- Services (no widgets, no controllers) live under `lib/service/<service>/`. They
  are plain classes with required constructor parameters and typed results, and
  they never show a message — the widget maps the result to localized text.
- Widgets used across module boundaries are public (`TabStrip`, `TabView`,
  `MainMenu`); widgets private to a module stay `_PascalCase` (`_TabCard`,
  `_ReleaseEditorState`).
- JSON keys are camelCase, the same shape as the Dart fields they come from
  (`releaseType`, `createdDate`, `lastEditDate`), not snake_case. The values of `tracker` and
  `releaseType` are the enum names, so the ID follows the same convention as the keys and is one
  name in the file, the enum and the asset path.

---

## 4. Architecture rules (the invariants)

Rules 1-3, 7, 8 and 13 come from the refactor spec that produced this layout;
rules 4-6, 12 and 14 are the project's own decisions about dependency injection and
about what a widget draws. Keep
them, except where the current code already deviates (listed after the rules — do
not treat those rules as describing the code as it is today).

1. **Feature-first layout.** Shared UI in `lib/feature/`; feature-specific code
   in `lib/feature/<feature>/`. Non-UI services live in `lib/service/<service>/`
   (added for the native-tool seam).
2. **One widget = one controller.** A widget gets a co-located
   `<widget>_controller.dart`. The widget owns layout; the controller owns
   state, validation, and side effects.
3. **Controllers do not own `Listenable` instances.** They expose plain
   callbacks; the widget subscribes to them. A controller may depend on
   `TabManager`, but it must not create its own listener.
4. **Controllers take required constructor parameters and never build their own
   dependencies.** No optional default that quietly creates a real object — that
   hides the dependency and makes substitution impossible.
5. **The object graph is built in one place: `lib/app/app_providers.dart`.**
   Adding a feature means adding one provider entry there plus the feature's own
   files. `app.dart` does not change.
6. **Widgets resolve dependencies from the provider scope** (`context.read` /
   `context.watch`), never from a static and never by constructing them.
7. **`TabManager` is the sole global tab-state owner and the only `Listenable`
   in the app.** Widgets observe it with `context.watch<TabManager>()`; nothing
   else holds tab state, and there is no second tab manager. Provider owns its
   disposal.
8. **`app.dart` composes, it does not implement.** It installs the provider
   scope and places `MainMenu`, `TabStrip`, `TabView`. It builds no object and
   renders no tab or menu UI itself.
9. **`AppTab` is a plain data record** (`id`, `kind`, `release`, `hasUnsavedChanges`,
   `settingsSection`). No `Listenable` inside it. The last two are what a feature
   reports to the tab rather than holds itself, because the tab outlives the widget that
   shows them: the content area builds only the active tab, so a page is thrown away
   when another tab is selected, and a value it kept would be gone before the user comes
   back.
10. **No static singletons.** Shared objects live only in the provider scope and
    are reached through `context`, never through a top-level variable. The hoster registry
    is the one exception, and it is a necessary one: it is data the tests read, so it stays
    a top-level list, and the `--dev` flag that chooses between the real and the mock
    hosters is a top-level bool set once by `main()` before the app is built — the message
    reads it too, to decide which poster hoster applies.
11. **All user-visible strings come from `AppLocalizations`.** No hardcoded
    English in widgets. A tracker name is the one exception, and it is a necessary one: it is
    the same in every language, so it is a field on `Tracker` rather than a key.
12. **No third-party packages** beyond the ones the project uses for one defined
    job each: `provider` for dependency injection only — not as a
    state-management framework, `flutter_svg`, which is only ever used by
    `lib/feature/tracker_icon.dart` to draw the tracker icons, `window_manager`,
    which is only used by `lib/feature/tab/app_close.dart` to receive the native
    window-close event so closing the app can run the per-tab unsaved-changes
    popup, by `main.dart` to set the native window title, and by
    `PluginWindowGateway` to read the size the window has and to ask for a size,
    which is the toolkit's decision and not the app's, `file_picker` only for
    the folder picker, `path` only for joining paths, `intl` only for the
    formatting the generated l10n code needs and for the dates the Recent
    releases table shows in local time, and `path_provider` only for the app
    data directory `settings.json`, `recent_releases.json`, `window_size.txt`
    and the font `FontStore` writes live in, and `flutter_secure_storage` only
    for the OS credential store the Integration values live in, and `archive`
    only for reading ZIP archives in the photoset scan and for nothing else, and
    `url_launcher` only for opening a folder in the file manager the OS uses,
    which Flutter cannot do on its own, and only for the link the Torrent
    section shows and the draft link the Upload draft section shows, which the
    OS opens in the browser, and `enough_convert` only to read a response in the
    charset the site declares, which `dart:convert` cannot do.
13. **Do not pass `BuildContext` into controllers.** Typed results come from
    controllers; localized messages stay in widgets.
14. **A control is not drawn when nothing can use what it sets.** A row that sets
    a value belongs to the feature that uses the value, so it is drawn only while
    that feature can act: no source picked means no run to be asked for a flag, no
    images uploaded means no render a signature or a shape could appear in. A row
    that shows what a file already states is drawn whenever that file is there — the
    file is what the value describes, whatever else the feature can do. Hiding a row
    is not changing the value: what is stored stays as it is and the row shows it
    again when the feature can act.

**Current deviations from these rules:**

- Rule 3: `ReleaseWizardController` is a `ChangeNotifier` and its widget listens
  to it with `AnimatedBuilder`. This is how the code works today; changing it
  back to plain callbacks is a separate decision, not an accident to fix
  silently. `MainMenuController`, `ReleaseOpenController`,
  `CloneWizardController` and
  `ReleaseEditorController` follow rule 3.
- Rule 5: these controllers (`ReleaseWizardController`, `CloneWizardController`,
  `ReleaseEditorController`,
  `ScreenshotsController`) are per-widget state, so they are created by their widget
  in `initState` and are not provider entries. They receive their dependencies from
  the provider scope, which keeps rule 4 intact.
- Rule 2: `WindowController` has no widget, because the feature shows nothing
  and there is no widget to pair it with. It is called from `app_close.dart`,
  the only place that knows the app is closing for real, and that is the only
  place the feature is used from, so the provider entry is the whole feature. It
  holds no state and nothing is read at startup, because the app does not apply
  a size — the runners read the record before they create a window (§5) — so the
  size it compares against is the file read at the point the record is written.
  It is not a `Listenable`, so rule 7 is intact. Its typed result is read by the
  tests, because there is no widget that could show it: the close flow cannot
  report a file that was not written, so it calls the write and does not look at
  the answer, and a failed write shows up on the next run.
- Rule 10: `window_manager` exposes a top-level `windowManager` instance, which
  `app_close.dart` uses. It is the one shared object reached outside the
  provider scope, and it is there to receive the window-close event and to be
  the window the app reads. The window feature does not reach it as a top-level:
  the composition root reads it once and gives it to `PluginWindowGateway`, the
  same kind of exception as `rootBundle` and the environment — a top-level the
  framework owns, read only at the composition root.
- Rule 13: the shared close flow in `tab_close.dart`, the open flow in
  `release_open_flow.dart`, and the save flow in `main_menu.dart` show the popup
  or the message, so their functions take a `BuildContext` and
  `AppLocalizations`. They are UI, not controllers: the controllers own the side
  effects and return typed results, and the flows decide the UI. The flows are
  shared so the menu items and the keyboard shortcuts use one path: the strip,
  Ctrl-W, and closing the app all use the close flow, the menu item and Ctrl-O
  the open flow, the menu item and Ctrl+S the save flow.
- Rule 13: `lib/feature/pornolab_results.dart` maps a result to localized text,
  which is what a widget does, because the settings row and the Upload draft
  section show the same set of results and the words must not be two sets
  (`ai/pornolab_login.md` §8). It takes `AppLocalizations` as a parameter and is
  called by both widgets, so the text is still resolved by the widget that shows
  it; `fieldProblemText` in `field_validation.dart` is the same kind of shared
  mapping and is the precedent for it.
- Rule 10: `TemplateStore` takes the asset bundle as a constructor parameter rather than
  reading `rootBundle` inside itself, so the service reads no static. The bundle is still a
  framework top-level, and `app_providers.dart` is the one place that reads it. It is the same
  kind of exception as `windowManager`: a shared object the framework owns.
- Rule 10: `app_providers.dart` reads the environment once for the user's home, because a stored
  path may start with `~` and `SettingsController` must not build that dependency itself. It is the
  same kind of exception as `rootBundle`: a top-level the OS owns, read only at the composition root.
  It is also the one place that takes the path package's platform context and gives it to
  `SettingsController`, so the rule that decides the separator is a parameter rather than a static.
- Rule 3 and rule 7: `SettingsController` is a `ChangeNotifier`, and it is the second Listenable
  in the app. The app language is app-level state, and what the app shows cannot change when it
  changes unless something notifies, so a plain callback controller cannot serve it. `AppRoot`
  watches it for the locale and `SettingsPage` watches it for the language selector. This is the
  agreed design for the settings feature, not an accident to fix silently.
- Rule 3: `DraftController` takes `SettingsController` as a required constructor
  parameter, which is the first controller that depends on another controller. It
  reads it and does not listen to it, so rule 3 is intact; the dependency is
  there because the cookie is a value the settings feature owns and a run needs
  one. A session feature between the two was the alternative, and for one read
  that is the abstraction rule 3 refuses.
- Rule 3 and rule 7: `RecentReleasesController` is a `ChangeNotifier`, and it is the third Listenable
  in the app, after `SettingsController`, for the same reason: the recent list is app-level state shown
  in a table, and a row appears when a release is opened while that table is open, so a plain callback
  controller cannot serve it. `RecentReleasesPage` watches it. This is the agreed design for the feature
  (`ai/recent_releases.md` §8), not an accident to fix silently.
- Rule 8: `AppRoot` in `app.dart` reads `SettingsController` for the locale, which is the one
  thing `app.dart` reads from the provider scope. It has to be its own widget rather than part of
  `App`, because `App.build` runs above the providers `App` installs.
- Rule 2 and rule 7: `TabNavigation` has no controller and it owns a
  `ScrollController`, which is a `Listenable`. There is nothing for a controller
  to own here: the widget holds the one object its subtree resolves to, as
  `SettingsPage` and `StashSection` hold the `FocusNode`s of the fields they own
  — a widget's own `Listenable`, disposed by the widget, which is not the shared
  state rule 7 is about. Rule 7 stays intact for tab state.
- Rule 10: `TabNavigation` reads `FocusManager.instance` to answer whether a
  text input is focused, because the focus chain gives the widget its own node
  and the focused one is elsewhere. It is the same kind of exception as
  `windowManager` and `rootBundle`: a top-level the framework owns, read only to
  answer one question, and the widget that reads it is the widget the question
  is about.

---

## 5. Runtime flow

**Startup:** `main.dart` → `runApp(const App())`. `App` installs the
`MultiProvider` built from `appProviders()`; its child `AppRoot` builds
`MaterialApp` with `AppLocalizations.delegate` +
`GlobalMaterialLocalizations.delegate` + `GlobalCupertinoLocalizations.delegate`
+ `GlobalWidgetsLocalizations.delegate`, `supportedLocales:
AppLocalizations.supportedLocales`, `locale:` from `SettingsController` — null
follows the system locale, which is what the settings' `system` option means —
and `home: const TabsPage()`. `SettingsController.load()` runs when the provider
creates it — settings.json first, then the credential store — so the first
frames use the defaults and the stored values apply when the reads complete. A
store that cannot be reached is not an error at startup: the page shows the
values it has and says what is missing. `RecentReleasesController.start()` runs
when the provider creates it, in the same shape: it reads `recent_releases.json`
and then opens the tab the app opens at startup as the first tab, so the first
frames show an empty table and the stored entries apply when the read completes.
Opening a tab is a side effect, so it is the controller's and not `app.dart`'s
(rule 8). Nothing in the app reads the window size at startup, because the app
does not apply a size. The Linux and Windows runners read `window_size.txt`
before they create the window (§7), which is the only point at which a size can
be settled: a window is created at the size its toolkit states at creation, and
a size asked for afterwards is a request the desktop may ignore, so an app that
asked would show the user a window that jumps. What the app does with the size
is record it, at the point `app_close.dart` decides the app is closing for real.

**Composition:** `appProviders()` is the whole object graph: `ToolLocator`,
`ToolLog`, `ToolRunner`, `Ffmpeg`, `Ffprobe`, `Mtn`, `Uptooda`, `HttpClient` and
`ImageDownloader` and `StashClient` — the two network users share one client,
and `Provider` closes it — `ReleaseStore`, `ImagesStore`, `TemplateStore`,
`TemplateRenderer`, `MessageStore`, `SettingsStore`, `RecentReleasesStore`,
`SecretStore` (the plugin instance is built here, not inside the store),
`SettingsController`, `TabManager` and `RecentReleasesController`
(`ChangeNotifierProvider`s, disposed by Provider), `TabCloseController`,
`ReleaseOpenController`, `MainMenuController`, `WindowSizeStore`,
`WindowGateway` (`PluginWindowGateway`: the plugin instance is read here for the
same reason the credential store's is) and `WindowController`.
`RecentReleasesController` is built after `TabManager`, because opening the
startup tab goes through it. `SystemCheckController` is a provider entry too,
because the check is app-level rather than per release; it is given the four
tool wrappers and the app data directory as a function, for the same reason
`TabsPage` is stateless: its `build` places `AppCloseHandler` around a
`Scaffold` whose body is a `Column` of `MainMenu`, `TabStrip`,
`Expanded(TabNavigation(TabView))`. It builds nothing and resolves nothing; the
two wrappers are feature widgets that own the window-close and the page-key
behaviour, and the default focus of the content area, which is what a page with
nothing focusable in it is reached from. The Ctrl keys are not placed here:
`AppShortcuts` is placed by `AppRoot` in `MaterialApp.builder`, which is the
only place that is an ancestor of every focus scope in the app, a popup route's
included — `home` is below the `Navigator`, so a key that comes from a route
cannot reach a map inside it. The save flow shows its message through
`ScaffoldMessenger`, and `MaterialApp` puts the one it provides above `builder`,
so a message shown by an app-level action resolves even when a popup is open.

**Resolution:** widgets read their dependencies from the provider scope —
`MainMenu` reads `MainMenuController` and watches `TabManager` for the Save item's
enabled state, `TabStrip` and `TabView` watch `TabManager`, `TabStrip`,
`AppShortcuts` and `AppCloseHandler` read `TabCloseController`, `AppShortcuts`
reads `MainMenuController` for its Ctrl-O and Ctrl+S bindings, `ReleaseWizard`
builds its own controller in `initState` with the
store from the scope. `AppRoot` watches `SettingsController` for the locale and `SettingsPage`
watches it for the fields it shows; which section the settings page shows is not its own state but
the tab's, read from the `AppTab` record: the content area builds only the active tab, so the page
is thrown away when another tab is selected, and a value it held itself would be gone by the time
the user comes back — the same reason the editor's dirty flag is on the record.
`StashSection` builds its own controller
in `initState` with `StashClient` from the scope, and reads `SettingsController` for the key it
passes to the call rather than holding it. `RecentReleasesPage` watches `RecentReleasesController` for
the rows and reads `MainMenuController` for the row click, and asks the controller to check which rows
are still there when it opens; which column the table is ordered by is its own widget state, like the
hoster selection in the Upload section.
`SystemCheckPage` reads `SystemCheckController` in `initState` and runs the
check when it opens; the results are its own widget state, like the column the
recent table is ordered by.

**Tabs:** `TabManager` holds `List<AppTab>` and `selectedIndex`;
`addNewReleaseWizard`, `addReleaseEditor`, `addSettings`, `addRecentReleases`, `selectTab`,
`closeTabAt`, and `replaceWizardWithEditor(tabId, release)` mutate the list and notify. `addSettings`
and `addRecentReleases` are the entries that do not always add one: the settings and the recent list
are app-level, so a second tab would show the same thing twice, and they select the tab that is already
open. `addReleaseEditor` does the same per release directory, because one release is one row of the
recent list and one tab, and a second tab for the same folder would show the same release twice.
`setUnsavedChanges(tabId, value)` is how the editor reports dirty state; the tab
record is the only place that state lives. `setSettingsSection(tabId, section)` is how the settings
page reports which section it shows, for the same reason: the content area builds only the active
tab, so the page is gone when another tab is selected, and the section it was showing would be
gone with it.
`replaceWizardWithEditor` takes either wizard kind, because both become the editor
of the release they made, and is a no-op if the wizard tab was closed while creation
was in progress.
`addCloneWizard` is the entry that always adds one, unlike the app-level tabs: the
clone feature is one release per resolution, so the same source is cloned more than
once and two of its tabs are not the same thing.
`addSystemCheck` is the third entry that does not always add one, for the same
reason: the check is app-level, so a second tab would show the same list twice.

`TabStrip` observes `TabManager` with `context.watch<TabManager>()` and renders the strip
from it (titles and icons resolved by switching on `AppTabKind`: `newRelease` for a wizard,
`cloneRelease` for the clone wizard, `tab.release!.name` for an editor, `settings` for the
settings tab and `recentReleases` for the recent tab; the icon is a `TrackerIcon` for an
editor tab at 16 px, `Icons.new_releases` for the new-release wizard, `Icons.content_copy`
for the clone wizard, `Icons.settings` for the settings tab and `Icons.schedule` for the
recent tab). A wizard has no release to name it, so both wizards are titled by their menu
key, and the clone wizard has a source but the release it will make does not exist, so there
is no tracker to draw either. It dispatches
`selectTab` and, for closing, the shared close flow (`closeTabWithConfirmation`)
rather than `closeTabAt` directly, so a dirty tab gets the popup first. It renders nothing when there are no tabs. Like a
browser tab, the primary button selects the card and the middle button closes it;
the middle click is read from a `Listener` pointer-down event, because gesture
callbacks never report which button was used (a tap recognizer routes the middle
button to its tertiary callbacks, which `InkWell` does not have). The tab
card has no press ripple (`splashColor` and `highlightColor` are transparent), and
the hover tint is painted from the card's own hover state rather than by `InkWell`, because
`InkWell` resolves `hoverColor` once — when the highlight is created on hover-enter — and keeps
that colour until the pointer leaves, so a card that is hovered and then clicked would keep the
tint it had before the click. Painting it from the current state is what makes it disappear on
the click, and it is only applied to unselected cards: the selected one is already highlighted.
A card whose tab has `hasUnsavedChanges` shows a dot after the title.
`TabView` does the same and renders the active tab through `KeyedSubtree(key: ValueKey(tab.id))`, so switching tabs rebuilds the
widget, and shows `allTabsClosed` when the list is empty. It passes `tab.id` to
the editor, which is how the editor reports dirty state back.

`AppTabKind` values: `releaseWizard`, `cloneWizard`, `releaseEditor`, `settings`, `recentReleases`,
`systemCheck`. A clone tab carries the source it clones, which is the only thing it holds; the
release it will make has no record yet.

**Closing a tab:** the close decision is one shared path, `closeTabWithConfirmation`
in `tab_close.dart`, used by the strip's close button and middle click, by Ctrl-W,
and by closing the app. A clean tab closes directly, and a settings tab is always clean: settings
are written as they change, so it has no dirty flag and nothing to save. A tab with `hasUnsavedChanges`
shows an `AlertDialog` with three options — **Close without saving** (the danger
one, `colorScheme.error`), **Save and close**, **Cancel** — and a dismissed dialog
counts as Cancel. Before the popup is shown the flow selects the tab it is about to
name, so the user decides about the tab they are looking at rather than another one.
The controller `TabCloseController` owns the side effects only: `selectTab` moves the
selection to the tab the popup names, `saveTab` writes the manifest through
`ReleaseStore` and clears the flag, returning a typed result, and `closeTab` removes
the tab through `TabManager`. The flow itself is UI (it shows the popup), so it takes
a context, as `MainMenu` does for the open flow.
A failed write does not close the popup: the tab is kept and the popup shows the
error inside itself, so the user can retry or pick another option rather than losing
the work. The popup therefore only returns a choice that really closed the tab, or
Cancel.

`AppShortcuts` is an ancestor of every focus scope, so it maps Ctrl-W to closing
the current tab through that flow regardless of which tab is focused, a popup
route's focus scope included.
`AppCloseHandler` registers the `window_manager` window-close listener and sets
`setPreventClose(true)` so the toolkit does not close the window on its own; on
the close event it runs the only if none is cancelled. A clean tab is skipped.
On the answer that closes it first records the size the window has, through
`WindowController.recordSize()`, because this is the only point at which the app
knows what the window was for a whole run; the answer is not shown, because
there is no widget left that could say a file was not written, and the close
does not depend on the write. `destroy()` fires the close event again, so the
handler guards against re-entering itself. `main.dart` calls
`windowManager.ensureInitialized()` before `runApp` so the listener can be
registered, then `windowManager.setTitle(appName)` — `MaterialApp.title` is not
the window title on the desktop runners, so the native title is set here.

**Creating a release:** `ReleaseWizard` (form) → `validateReleaseName()` →
`ReleaseWizardController.create()` → `ReleaseStore.create()` →
`widget.onCreated(release)` → `TabManager.replaceWizardWithEditor()`.
Failures are typed as `ReleaseCreationFailure.alreadyExists | failed` and the
widget maps them to localized snackbars.

`ReleaseStore.create()` checks the directory does not exist, creates it, writes
`release.json`, and returns the path. The two flags it writes are the ones it is
given: the settings' defaults for a release made through the wizard, and the
source's for a clone. The store decides nothing about them, so one call serves
both paths, and a release keeps the flags its manifest holds afterwards whatever
the settings say. `ReleaseAlreadyExistsException` is distinguished from generic
failures by the controller.

**Creating a clone:** `CloneWizard` (form) → `validateCloneName()` →
`CloneWizardController.create()` → `ReleaseStore.create()` → the copy →
`recentReleases.record()` → `widget.onCreated(release)` →
`TabManager.replaceWizardWithEditor()`. The create is the new-release one, so the
failure vocabulary is the same `ReleaseCreationFailure` and the widget maps it to
the same snackbars; the copy is what adds a failure the new-release create cannot
have, and a copy that cannot be written is a failed create that removes the folder
the create made, so a half-copied release is not left behind. The copy takes the
fields the user writes — every field the user fills, including `sceneUrl`, which has
no form row of its own, and the Upload draft's `parentForum` — and the poster: the
primary poster record with its URLs,
copied as a record of its own so the Upload section of either release cannot write
through the same map, and the poster file when it is on disk. The six fields the app
fills from the movie file stay at the defaults a new release starts with, because
they describe a different video, and no other record is copied, because the clone
generates and uploads its own images. A value a run wrote is not copied either:
`draftUrl` names the topic the source's draft was saved as, so a clone that kept it
would point at a draft it did not make; it starts without one and gets its own when
the feature is run there. The parent forum is what the user typed, so the next run
there is made in the same forum. The clone's save path defaults to the folder
the source is in rather than to the settings' default release directory, because the
user is making another release of the same scene and the neighbour is what they are
most likely to want; the folder button falls back to it when the field names a
folder that is not there. The warning the form shows is decided by `posterStatus()`,
a synchronous read of the source's manifest, the same way the Message section reads
the poster state; the controller answers with the state and the widget maps it to
one of the two warning strings, because a controller shows no text (rule 13).

The wizard's save path defaults to the default release directory from the settings, which is
`~/Documents/Releases` when nothing has been set; the folder button uses
`FilePicker.getDirectoryPath()` with the localized `dialogTitle`. The widget reads the value from
`SettingsController` and passes it to its controller, so the controller builds no dependency of its
own, and there is no loading state any more: the settings are already loaded when a wizard is
opened.

The tracker and release-type fields are `DropdownMenuFormField` (Material 3), which
opens its menu below the field. `DropdownButtonFormField` centres the menu on the
button and has no placement API, so it is not used. `selectOnly: true` keeps them
as selectors rather than editable text fields, and `expandedInsets: EdgeInsets.zero`
makes them take the parent's width — without it the field sizes itself to its
longest entry, which is narrower than the other form fields. The tracker entry's
`leadingIcon` is a `TrackerIcon`, so it is not `const`; the icon comes from the
asset registry rather than a Material glyph.

**Editor:** `ReleaseEditor` renders the `Release` the tab carries — name as a
heading with a tracker badge (`TrackerIcon` plus `Tracker.displayName`) and a
release-type badge (`releaseTypeLabel`) after it at a gap, because they say what the
name is for and not where the row ends, and 12 px below it before the form, the gap
a section title has before its content, as the heading titles the page. Then the
field form for the release type. The form
is as many columns of at least 430 px as the space the page has — one for a photoset pack, two for the other types, plus the sections'
columns for the types whose section can be one of them — each with an image box at the top. The page has no maximum width, so the columns
are the window's width less the padding it has always had; a form capped at 1000 px could not be four. The columns after the form's are
only ever the sections' columns, and only for the types `release_editor.dart` says can be one of them — the two video types, and the
photoset pack, whose grid takes all of them, one set per column it fits: its form is the first column, with the values the scan counted and
the Upload and Message sections stacked below its fields in that same column. A table and a masonry cannot be read at one column width, so
the single photoset and the image folder keep the whole width below the form; when a section that could be a column does not fit as one it
sits below the form, left-aligned at one column width, and for a pack that is the whole width, because its grid fits as many of its own
columns as fit in that width, between the two widths its rule gives it. A fixed width is only kept when the surrounding column does not
stretch it, so the sections below the form sit in a row that holds their width. The Message section is the fourth column when there is room
for four, the form's own column for a pack, and otherwise the whole width below everything, which is why the page is built inside the
LayoutBuilder that decides the columns. Both boxes are 16:9, the shape of the frames they show, so a video frame fills one without being
cropped; their height comes from the width the column gives them. The poster box shows the poster file the user chose, fitted inside the
box rather than cropped to it, because a poster is usually portrait; the thumbnail box shows the frame ffmpeg wrote for the video, cropped
to the box. Neither box shows a smaller copy of the file: the box is the size the widget draws at, and the file is what the tool wrote. An
empty box says what it is missing, and the message is the caller's rather than one string for both, because the two video cases read
differently: no video is picked, versus a video that is there with no frame. Both boxes are an `InkWell` with the same action as the button
that picks their file — the poster's choose button and the pick on the source row — because that is where the user is looking; the video
box is not clickable while the probe is in flight, and it has no button of its own because the source row already has the pick, and its
hint is only for the case where clicking it is what fills it. The poster box has a choose button and a paste-from-URL button at the end of
its label row, and a remove button only when a poster is there, and it is the focus a clipboard paste will be attached to later (§10). The
label row is the same height with or without buttons, so the two boxes in the two columns start at the same height: a row sizes itself to
its tallest child, and an icon button is taller than a label. The boxes render nothing but the file they are given: no state of their own
beyond the widget's poster busy flag, no separate controller, and nothing about them is recorded in `release.json`. Which fields are in
which column is the widget's layout, not the field model: the scene link field's row is the first row of the left column, under the poster
box, because the values a fetch gives are what the form is filled with, and that row is the Stash widget's own, so the editor builds no
text controller for it. Four field lists exist: the Single video one, the video pack one (`ai/video_pack.md`), the single photoset one
(`ai/single_photoset.md`), and the photoset pack one (`ai/photoset_pack.md`); the form is built from whichever one the release's type has.
The widget's column layout is a switch exhaustive over `ReleaseType`, so a type added to the enum has to be given a layout there; the
compiler says so, which is what a runtime fallback used to do silently. The same rule covers the switch in `MessageController` that decides
which shape the image block has for a type, the one in `MessageSection` that decides whether the row of shapes is drawn, and the one that
names the two shapes.

A field list is data. `FieldSpec` holds the name `release.json` writes, the value a new release
starts with, whether the app fills it, whether it has a form row, and whether its value is a
byte count; `FieldList` is the list of
them for one type, plus what the user picks for that type (a file or a directory), the item type
its items are recorded with, and the item boundary the scan is given: whether the items are the
entries under the source or the source itself, because that is a rule of the type rather than of
the scan (`ai/single_photoset.md` §5). `hasField(name)` is what a controller uses to keep the
values it emits to the names its type has, because a scan counts the same aggregates for every type
it can read. `fieldListFor(ReleaseType)` is a switch rather than a map, so a type added to the enum
has to be given a field list there, and the wizard's option list is `ReleaseType.values`, so a type
cannot be chosen without one behind it, and the order the dropdown lists them in is the order the
enum declares them. A field list cannot hold a localized string, so
`fieldLabel(name, l10n, releaseType)` is the one place the names are turned into `AppLocalizations`
keys, and the editor's form, the Stash section and the Video pack section all call it — the section
for its table's column headers and for the detail lines, which are text rather than form rows;
`releaseTypeLabel(type, l10n)` in `release_type.dart` is the same for a release type. The answer is
the same for every type except the two names a single photoset words differently, because a model
is the same value as a cast and a set name the same value as a title (`ai/single_photoset.md` §4).
Which shape a row has — a button, a multiline box, one that grows — is the widget's.

`FieldValues` holds the values as plain strings keyed by field name — the same model at both
levels, the release and an item (`ai/release_structure.md` §3). Which names exist is the field
list, not this class. A new release gets the defaults of its type's field list when the store
creates it — Video Quality `SiteRip` for a Single video, nothing for a photoset pack or a video pack,
which have no defaults of their own — and `SiteRip` is a value the user writes the same way in every language,
so it is not an `AppLocalizations` key. A manifest is read into `FieldValues.fromJson()`, so a
loaded release shows exactly what its file contains rather than the defaults of a new one, and a
key the field list does not know is kept because the file is what the user may have edited.

The path the user picked is not a field: for a type whose source is a file the item is the file, and
its path is the record ID (`ai/release_structure.md` §2). The editor shows it as its own row, keyed by
`sourceRowKey`, and writes it through `setSource()`, which records the source and the item it is when
the picked path is a file; for a pack the items are what the scan writes, so picking a directory
records the source without creating an item.

`ReleaseEditorController` reads the release's own `fields` — plus the source, the poster
record, the dirty flag and `save()`. The widget binds
one `TextEditingController` per field, seeded from the model, and every write goes
through one path: `setField()` on the controller, then the field showing the
value. The field is only written back when the value did not come from that field
itself: echoing what the user typed moves the caret to the end and clears the IME
composition, which is what stops typing after one character. Writes from outside a
field — the probe, the date picker, the file picker — do update it. The controller
marks the tab dirty through `TabManager`, which is the only
listener, so the widget does not listen to the controller at all.

Ctrl+S is handled by a `Focus` wrapper in the widget: key events reach it from
the focused text field through the focus chain, and this is the nearer handler,
so the key is answered here while a field inside the editor has focus. The
editor does not ask for focus itself — the content area is the default focus of
its subtree — so with nothing inside the editor focused the app-level map
answers the key. Saving writes the manifest and clears the flag; a failed write
shows a localized message. `AppShortcuts` is an ancestor of every focus scope,
so a popup route's focus scope reaches it too. The Stash row still takes focus
back to its input when its popup closes, because it owns that input's focus.

Every field is a text box except: the source row, which has a picker button at the end of the
row — `FilePicker.pickFile()` for a type whose source is a file, `FilePicker.getDirectoryPath()`
for one whose source is a directory — and the production date, which has a `showDatePicker()`
button. The date is stored as the ISO
`yyyy-MM-dd` text the field shows, so it round-trips without locale formatting.
Description and additional information are multiline fields that grow with the
text; genre stays on one line and grows below when the text does not fit.
Additional information is labelled optional. Every field carries a `ValueKey` of its field name,
which is how the tests find a field without depending on which column it is in. A row shows
the words for a problem the last generation refused, and only a row the user can type into
shows it: the rows the app fills are not something the user can fix here
(`ai/description_template.md` §Validation).

**Reading the movie file.** Six fields — file size, duration, video type, video
format, video stream, audio stream, items 8, 9, 11, 12, 13 and 16 of
`ai/release_editor.md`, which are the fields from file size down in the right
column — are not editable: the app fills them from the file. They are drawn without
a border and with a muted background, so they read as text the app wrote rather
than an input, but they are still text boxes with `readOnly: true`, so their values
can still be selected and copied. The marker is `filledByApp` on the field spec, so the knowledge
lives in the field model rather than in the widget. For a video these are the fields ffprobe
reports; for a photoset pack they are the ones the scan counts (`ai/photoset_pack.md`).

A byte-count field is the kind of field whose value and the text shown in it
differ: the model stores the byte count, as item 16 asks, and the field shows it
in a human-friendly form as well — `9.5 GiB (10737418240 bytes)`, binary units,
one decimal place, the byte count alone when it is too small to have a shorter
form. Which fields are byte counts is the `isByteCount` flag on the field spec,
so the form reads that rather than a list of names it knows; the two are a single
video's file size and a video pack's total. `file_size.dart` derives that text
from the stored value, so it works for a value read from a manifest as well as
for one the probe wrote, and the word "bytes" comes from the `fileSizeDisplay`
l10n template rather than being written in the code. The same file also gives the
human form alone, for a place that shows a size in a fixed-width cell rather than
as the field's text — the Video pack table's size column — and a value with no
shorter form is the byte count there as well, so a caller does not handle that
case separately. The single write path writes the model and then the derived
text; the text put into a field is `_displayValue`, which is the value itself
for every other field.
`AppLocalizations` cannot be read in `initState` — Flutter asserts on an
inherited-widget lookup there — so the derived text is put into the field in
`didChangeDependencies`, which also updates it when the app's language changes.

`ReleaseEditorController.probeMovieFile()` checks that the path in the field points
at an existing file and calls `Ffprobe.probe()`, which makes one call —
`ffprobe -hide_banner -of json -show_format -show_streams <file>` — and parses the
output into `MediaInfo`. The controller returns a typed result and does not write the
fields: the widget applies the values through its own single write path, so the tab
becomes dirty and Ctrl+S saves them. The probe runs when the file picker sets the
path and when the path field is submitted (Enter); while it is in flight the row
shows a progress indicator instead of the picker button. A failure is mapped to a
localized message: `fileNotFound` → `movieFileNotFound`, `toolNotAvailable` →
`probeToolNotAvailable`, `probeFailed` → `probeFailed`.

**Writing the thumbnail.** The same flow then writes one frame of the video.
`ReleaseEditorController.thumbnailPath()` is
`<release dir>/images/<item path>/_rp_thumbnail.jpg` — nothing about it is in
`release.json`, so the path comes from the release directory and the item path,
which is the structure a multi-video release will use too. `generateThumbnail()`
creates the folder and calls `Ffmpeg.screenshot()` at half the duration `MediaInfo`
reports; a file ffprobe did not report a duration for is read from the start. That is
the same call the Screenshots section uses, so the file is the full frame at the source
resolution rather than a scaled-down copy of it, and there is no second, smaller file
for the box to show. The controller returns a typed `ThumbnailResult` and shows no
messages: the widget shows the file in the box and maps a failure to localized text.

Both boxes show an image only for a file that is on disk, which
`ReleaseEditorController.thumbnailOnDisk()` and `posterOnDisk()` answer. Flutter
remembers a failed load for the same path, so an image built for a file that is not
there stays empty even after the tool writes it: a box would never show an image the
app wrote in the same session.

The other half of the same cache is the image itself, keyed by the file path: a file
the app rewrites would still be shown as the image decoded from it the first time, so
replacing a poster already on screen showed the old one. The widget drops the cached
image for a path it writes before it builds again (`_evictCachedImage()`), for both
boxes.

Evicting the entry is only half of it. `Image` resolves its provider once and
re-resolves only when the provider key changes, and the key is the file path. So a
path that is rewritten with the same name is not re-resolved: the already-mounted
image keeps the stream it resolved the first time. The poster file is always
`_rp_poster.jpg`, and the screenshots, the screenlist and the photos keep their
names on a regeneration, so all three are the case the rule is about. The editor keys
the poster image with a generation that changes on every write; the three sections that
show generated images key every tile through `lib/feature/image_tile.dart`, with a
generation counter that changes when files are written — once per run for the photosets and
the image folder section, and once per file for the two sections that show a run as it
writes, so a tile is rebuilt and resolves against the now-empty cache at the moment its
file is written. The two halves are `imageFromFile` and
`evictCachedImages` in that file, and the counter stays each widget's own state, so it
is passed in rather than held there. The Stash popup is the same case with a file it
downloads: its poster preview is written under a name the scene id gives, so a different
scene is a different path, and the popup evicts the entry and keys the image with its own
counter for the case where the same scene is fetched twice.

The captcha image on the Settings page is the only image the app shows from a
URL rather than from a file, and it is not the case this rule is about: each
captcha is a different URL, so the key changes on its own. It is not stored
anywhere, because a captcha is not a record the app keeps
(`ai/pornolab_login.md` §3).

**Choosing the poster.**
`ReleaseEditorController.posterPath()` is the path the poster's record gives, resolved against
the release directory, because two posters cannot share one derived name
(`ai/release_structure.md` §4); the first poster record is the primary one, which is what
`ImagesManifest.primaryPoster()` gives, and posters belong to the release, so their records
have no item. The clone feature reads the same function, so there is one rule for which
record is the poster rather than one per feature. That path is what the box shows: there is
no smaller copy of the poster beside it, and no second file to write or to remove. A poster
with no record yet gets one at the release directory root, where the first poster of a
release has always been. `setPoster(sourcePath, format)` checks the file is there and that
its format is one of `posterExtensions` (`jpg`, `jpeg`, `webp` — the same list the file
picker is filtered to; there is no format sniffing). The format is the extension the path
has, which is what a picked file gives, or what the caller passes when the path cannot say
it — a downloaded file whose link names no format. It then writes the poster with
`Ffmpeg.resizeImage()` at no more than `posterMaxSize` (1200 px on the bigger dimension).
`min(maxSize, iw)` never makes a dimension larger, so a poster that is already smaller is
not resized. `removePoster()` deletes the file and the record for the primary poster, and
returns false when a file or the manifest could not be written. Both return typed results
and show no messages; the widget maps a failure to localized text.

The widget picks with `FilePicker.pickFile()` filtered to those extensions, shows a
progress indicator in the label row while the write is in flight, and builds again so
the box shows the poster it wrote. A failure is mapped to `posterFileNotFound`,
`posterWrongFormat`, `ffmpegNotAvailable` or `posterWriteFailed`, and a failed removal
to `posterRemoveFailed`. The mapping is one function, `_posterMessage()`, because the
picked file and a pasted link share it.

**A poster from a link.** `setPosterFromUrl(url)` is the same path as a picked file, so
the same checks and the same two files apply. It checks the link is http or https, and then
its format. A link that names one is judged from the extension in its path — not from the
whole string, so a link with a query is still a jpg — before anything is downloaded, so a
link that will be rejected is never fetched. A link that names no format cannot be judged
from its path: a StashDB image is `stashdb.org/images/<uuid>`, so what its response calls
the file is what decides, and that is only known after the download. The download goes to a
temporary file, because ffmpeg reads files rather than bytes, and that file is handed to
`setPoster()` with the format the link named, or the one its response named when the link
named none. ffmpeg reads a file by looking at its bytes, so the temporary name needs no
extension in it. The temporary file is deleted afterwards: it is not part of the release. A
bad link is `PosterFailureKind.invalidUrl` and a failed download `downloadFailed`, mapped to
`posterUrlInvalid` and `posterDownloadFailed`.

The widget reads the link from the clipboard with `Clipboard.getData(Clipboard.kTextPlain)`
— the text format, which is what a link is and the only format Flutter's clipboard API
has — because reading the clipboard is a UI action, like the file picker; the download
itself is a side effect, so it belongs to the controller. Writing to the clipboard is the
same kind of UI action, so the copy buttons in the Message section are in the widget as
well. `ImageDownloader` and `StashClient` are the two Dart paths in the app that make a network
request, and they share one `HttpClient` provider entry that `Provider` closes. uptooda makes its
own requests, but it is a process the app runs rather than Dart code, so it does not go through the
client.

ffmpeg is used for this because `dart:ui` cannot encode a JPEG or WebP —
`ImageByteFormat` has no such format — so decoding and re-encoding an image needs an
external tool. It reads WebP natively and applies the orientation an EXIF tag gives a
JPEG, so a phone photo comes out the right way round.

The poster is written when it is chosen, not on save, and it does not take part in the
dirty flag: `release.json` stores no poster path, so there is nothing to save. Writing it
stamps `lastEditDate` in the manifest through `ReleaseStore.touchLastEdit()`, which records the
release changing rather than its fields changing, and only the timestamp is written so the values
the user has not saved stay unsaved. The
widget keeps a `_posterBusy` flag for its own progress indicator, which is widget state,
not controller state.

The formatting rules are in `MediaInfo`, not in the UI: codec ids are shown as the
names the document uses (`h264` → `AVC`, `aac` → `AAC` with its profile, which the
document writes for audio but not for video), the frame rate keeps its fraction
(`29.970 (30000/1001) FPS`), the container is the name the demuxer list is known for
(`mov,mp4,...` → `MP4`), and a part ffprobe does not report is left out rather than
guessed. The first stream of each type is the one shown.

**Generating screenshots.**
`ScreenshotsSection` is the section that is one form column wide for a single video (§2): its title
row with the Generate button at the right, and a `Slider` (3-20 here; the minimum is the section's, not
the generation's, and the Video pack section allows 0) for the count, with the label, the
slider and the count on one row, the same shape the Video pack section has: with the button
in the title row they fit in one column width. With no item the section shows the placeholder
saying to select a video first and shows no controls, and its title row has no button, because
nothing there can run without a video. That row is stable while generating: the count text
has a fixed width, and the button is a loading button — it stays in place and is disabled,
with the spinner overlaid on top, so its size is fixed by its label. The
button reads "Generate", or "Regenerate" once images exist; that label change changes the button's width,
and with it the width the title row gives the title, but the title itself stays at the left, so the row
does not visibly move. The count is widget state — the widget owns the slider value
and passes it to `ScreenshotsController.generate(item, count, onRecord)`, which does not
hold it. The rules that write the files are `ImageGenerator.generate()`: it checks the
file, probes it for the duration, computes the key-frame times as the centre of each of
`count` equal segments, creates `images/<item path>/`, calls `Ffmpeg.screenshot()` once
per screenshot — a key frame at the original resolution, written as a JPEG — and then
`Mtn.screenlist()` once, with the rows the duration gives: one frame per minute, at
least 16 and at most 96 frames, 4 per row, so a duration that is not a whole number of
rows is rounded up — that is `ImageGenerator.screenlistRows()`, tested on its own. It
reports each file as it writes it, as a path relative to the release directory, and what
stopped this item, if anything; it does not record them, because a record is a file plus
the item it belongs to, so the controller maps each report to a record and writes
`images.json` — the item the image belongs to, the kind, the path relative to the
release directory, with an empty `urls` map until the Upload section fills it —
replacing the records this run writes, so the poster, the copied photos and the records
of other items are kept, and returns a typed result. The widget maps a failure to
localized text and shows the images that are on disk in two equal columns of its own, one form
column wide (§2), packed as the masonry §7 describes with the screenlist first, so it is the top
of the left column and the frames fill the columns after it. Nothing spans in this grid: every
frame is above the span ratio, so spans would make every tile as wide as the grid and the grid
would be one column, so the packing is called with a maximum span of 1. A tile is the shape its
file reports rather than an assumed 16:9, because ffmpeg writes a frame at the source resolution;
a file whose header cannot be read is laid out as a square, the same rule the photoset grid uses.
The gap is between the columns as well as between the rows: the packing counts it in the height of
each tile, which is what keeps the rows apart, so the columns take the same — a column is what is
left after one gap is taken out of the section's width, and each one starts at its own offset. The
name under a tile is centred, which is the shared tile's rule and so the same in the other sections.
The grid can be taller than the window, which is why the editor puts the section in a scroll view.
What the section shows is the records of the item plus the records the run in progress has
reported, held as widget state and cleared when the run ends, so a frame appears as it
is written rather than at the end, and a regeneration does not blank the section while
it works. A run that does not finish still records and returns what it wrote, so a
screenlist that failed does not hide the screenshots that succeeded; the widget evicts
the cache for each file as it is reported and bumps the generation for that file, which
is what the rule above requires. When the run ends the section calls the function the
editor passed it, so the Upload counters are read again (rule 3). `ImagesStore` reads
and writes `images.json`; a missing or unreadable file reads as an empty manifest, so
the section shows nothing until the first generation.

**Reading the picked folder.** `ai/photoset_pack.md` is the spec, and `ai/single_photoset.md` the
one for a single set. `PhotosetBlock` is the data block: its heading with the Scan and Pick
buttons at the right, the rows the editor gives it for a pack — the path the user picked and the
counts the scan took from it — and the line naming each set with the number of photos in it.
Nothing is shown before the scan, because opening a release is a read and changes nothing. For a
pack the picked photos are drawn by another widget, `PhotosetGallery`, because the block is the
page's first column and the photos are the columns after it, and one widget cannot be two grid
cells; for a single photoset the block is the whole feature and draws the photos itself
(`ai/picking.md` §7). The strings are resolved per type, because "photosets" and "the folder with
the photosets" read wrong for one set. `PhotosetController.scan()` calls `PhotosetScanner` with
the item boundary its field list has — the entries under the source for a pack, the source itself
for a single set — records the items it found with `type: photoset` and the per-item count, and
returns the values it counted for the editor's single write path — the feature has no write path
of its own — kept to the names the type's field list has. The scanner decides which entries are
items and which are photos through a reader interface, so a format can be added without changing
the scan, and reports what it could not take rather than guessing at it: entries at the top level
that are not photosets, photos whose header could not be read, and display names two items would
share. Order is the order the source gives: for an archive the order of its entries, for a
directory name order, because a directory has no order of its own. An archive that cannot be read
is an empty set, as a directory that cannot be listed is — one entry does not fail the whole
source. The dimensions come from the file header, not by decoding the image, and the minimum and
the maximum are decided by pixel area across all photos; the formats are the distinct extensions
among the counted photos, lowercased and sorted, the same rule as the video formats. The name a
row shows is derived from the item path, because the stored path is the record ID.

**Reading the picked folder for a video pack.** `ai/video_pack.md` is the spec. `VideoPackSection` is
the section below the form for a video pack: its title row with the Scan and Generate buttons at the
right, the slider, the videos as a table with one row each, and what the two runs could not do,
listed by name;
nothing before a scan, but a release opened from a manifest shows the items its file records. A row shows
the name, the size, the duration, whether the item has a screenlist and how many screenshots it has, and
clicking it shows the values the row does not. The name is the path relative to the source, because that
is the record ID and two files in different subfolders can share a file name, and the columns are named
by the labels their fields have; the size in a cell is the human form alone, because a fixed-width cell
cannot hold the byte count as well, and the values are shown as the model holds them. The value columns
are right-aligned so the numbers line up and a header follows its own column; the name is not a number,
so it is not aligned as one. A flag column shows a checkmark or a count, and a count of 0 is shown as
nothing, because a flag column that says 0 reads as an error rather than as an absence. Which rows are
open is widget state, keyed by the item path. `VideoPackController.scan()` calls `VideoScanner`, records
the items it found with `type: video` and the values the probe reported for each, returns the values it
counted for the editor's single write path, and reads the items back for the section, as the photoset
controller does.

`VideoPackController.generateImages(count, onRecord)` runs `ImageGenerator` for every
item, in the order the scan recorded them, reports each record as its file is written,
and records what the run wrote in `images.json` once for the whole run, because a pack
is tens of items and one write per item would be tens of writes for one action the user
asked for once. The open row shows the records of its item plus the ones the run in
progress has reported, so a frame appears as it is written rather than at the end, and
the section calls the function the editor passed it when a run ends, so the Upload
counters are read again (rule 3). The slider here allows 0 to 20 and starts at 0,
because a run over many files can be asked to write only the screenlist; the button is
disabled while the release has no items, and there is no "Regenerate" variant, because
the run replaces what it writes either way. A tool that is not available stops the run,
because it does not become installed while the app is open; a file that failed does not
stop the next one, as one file does not fail the scan. What the run could not do to
individual files is a report line with the scan's lines, because a run that did most of
them is not an error; what it could not do as a whole — a tool not installed, a manifest
that could not be written — is a message, the same text the Single video section shows.
A re-scan replaces the items, so the lines naming files that are no longer items are
cleared with it, as the open rows are.

**Picking photos from a pack.** `ai/picking.md` is the spec. `PhotosetPicker` is the rule as a pure
function: the number is `min(total, clamp(ceil(5% × total), 5, 50))`, the division across the sets
is by largest remainder with each set capped at its own size, the per-set minimum applies to every
pack, and the photos inside a set are the centres of evenly spaced intervals. Ties are broken by the
order the source gives, so the same input gives the same output. The rule reads counts only: the
resolutions are fields the scan fills and the post shows, not part of the rule.

`PhotosetBlock` has its Pick button next to Scan in its heading row, disabled until a scan has run
because the rule reads the counts, and there is no slider: the number is decided by the rule, and the
block shows what it decided rather than letting the user change it. `PhotosetController.pick()` copies
the photos the rule picked into the release under the display name — the release folder mirrors the
structure the user picked for the images that are copied into it — and records them as `kind: photo`
with `item` set to the set's path, replacing the photo records this run writes while the poster and
the records of other kinds are kept. The picked photos are one grid, in the order the source gives the
sets and, within a set, the order it gives the photos; the message still groups them by set
(`ai/photoset_pack.md` §7), because that is a list rather than a grid, and a tile says which set its
photo is from because nothing else does. The grid is as many columns of `photosetColumnWidth` as fit
in the space it is given, and what those columns cannot use is shared out rather than left as a strip
at the right, so the space is used up; a photo at or above a ratio of 1.2 spans the number of columns
that makes it `photosetLandscapeWidth`, which is what makes a landscape read as a landscape rather
than as a small tile, and a span starts where all of its columns are free, so the others keep a gap —
filling it would put a photo out of the order the source gives. The columns have no gap of their own,
because a spanned column must be exactly as many of them as the two widths say: the space between two
tiles is the padding inside them. A single photoset has no space beside its block, so its block draws
the same grid at the whole width, and a tile there keeps its file name only, because its block names
the one set above the photos. The ratio comes from the header, read synchronously, because a grid
cannot be laid out before it knows the shape of each tile and a widget builds synchronously — the same
reason `ImagesStore.loadSync` exists. A photo whose header cannot be read takes a square tile. The
grid places by position rather than by nesting, because a tile can span columns. The picked number in
a row comes from the records that exist, so it appears only after a pick: the feature shows what is on
disk. A photo that could not be read or written, and a set with no photos, are reported rather than
left out, and a set with no photos is only its line in the block, because with nothing grouping the
photos there is no column for it. Re-picking writes the same names, so the block records what its run wrote and the
tiles are keyed with a generation that moves on each run, as the rule above requires; that generation
is the shared state's rather than the block's own counter, because for a pack the pictures are drawn
by `PhotosetGallery`, and the block reports the run to the editor so the page builds again and the
area resolves against the emptied cache (`AGENTS.md` §5).

mtn exits with a non-zero code when it prints a warning, including for a shot it skips,
even when it wrote the file, so the app decides by the file on disk rather than by the
exit code. Its flags turn blank skipping off (`-b 2`): with the default `-b 0.80` mtn
skips a frame it reads as blank and leaves that cell empty, so the grid can end with an
empty frame that is not a frame of the video, which the app does not want. `-P` is on
every call the app makes to mtn, not only the screenlist one, because without it mtn
pauses at the end of a run and does not exit on Windows; on Linux it changes nothing,
so the same arguments work on both.

The command the app builds for a screenlist, and what each flag is:

```
-w 1200                            # width in px
-c 4                               # columns
-r <rows>                          # the rows the rule above gives
-g 1                               # gap in px
-k 252525                          # background colour
-b 2                               # blank skipping off
-L 4:2                             # info text upper left, time lower right
-f <font path>                     # the font `FontStore` wrote, as a path
-F FFFFFF:12                       # font format
-q                                 # quiet: errors only
-P                                 # no pause at the end, on every call
-O <output directory>
-x _rp_screenlist                  # name without the extension
-o .jpg                            # the extension added to it
```

The `-F` value is mtn's font format string. The app passes it as one value and
does not read its fields, so the order inside it is the tool's. Its font field is
the timestamp font, and the fields are split on `:`, so a path with a drive colon
cannot be passed there and an empty field is not accepted; the timestamp takes the
tool's defaults.

The font is the one the app ships (`ai/bundled_native_tools.md`), and it reaches
the tool as the path of the file `FontStore` wrote, defined once as
`FontStore.fontFileName`, because libgd resolves a font name only through
fontconfig's own configuration and not through anything the app writes. A font it
cannot open is not a failure: the screenlist is still written, without the info
text.

**Upload images:** `UploadSection` owns the hoster selection and the layout,
`UploadController` owns the side effects. The selection is widget state, checked by
default for every hoster in `hosters.dart`, and is passed to `upload()` as the registry
records, because a call needs to know which hoster reads a credential; the controller does
not hold it. The controller reads `images.json`, builds the
work list per hoster from the records with no entry for that hoster — the skip rule: an
uploaded image is skipped, a failed one is tried again because nothing was recorded for
it, and an unselected hoster is never in the list — reports the state for each hoster
before it runs, and runs each hoster as a sequential loop, one image at a time, while the
hosters run at the same time through `Future.wait`. There is no retry: the tool's own
retries are used with their defaults, and a failed upload records nothing. Only successful
URLs are stored, so the presence of a hoster key in a record is what "uploaded to this
hoster" means. `images.json` is one file written by several hosters at once, so the writes
are serialized with a lock, and the file is written after each upload rather than at the
end, so a run that is stopped keeps what it already uploaded.

Progress counts against the images in the release, not against the items a run happens
to pick up, so the state read at open and the reports a run makes are the same measure
and a bar never moves backwards. The controller reads `images.json` and reports, per
hoster, the images uploaded to it over the images in the release; the widget reads that
in `initState`, as the other sections read what is on disk, keeps it as its own state,
and draws a bar for every hoster in the list — including one whose credential is
missing, because the bar shows what that hoster has regardless of whether it can run —
so a bar exists before anything runs and a release opened with everything uploaded shows
full bars. A run reports the state it starts from and then one report after each item. A
hoster with none of the release's images is 0/0 and shows an empty bar, because the bar is the
share of those images this hoster has and it has none; the count next to it is what says there is
nothing to do. A release that has neither a poster nor a screenshot has nothing this section could
upload, so it shows the placeholder saying what has to happen first instead of the list, and the
placeholder waits for the pair rather than for one of them, so a poster alone does not dismiss it.
The count is the count the release has, so a generation run that adds images changes it, and the
counters and the placeholder condition are read again when such a run ends, because a run can be
what makes the release have the images: the section registers its rebuild with the editor, which
calls it, because the two sections cannot see each other (rule 3). The entries are updated rather
than replaced, so a bar does not move backwards. A bar below full is the only display for a per-image failure;
the log is what the developer reads. Only `toolNotAvailable` and a failed `images.json`
write are shown as a message, because those are the cases where nothing can happen at
all.

The parser decides by the `success` field, not by the exit code: the tool exits 1 for a
failed upload and 0 for an unknown hoster, so the exit code cannot tell them apart, and
output with no JSON on stdout is `noResult`. The failure kinds are `toolNotAvailable`,
`timeout`, `noResult`, `uploadFailed`. `UploadSuccess` carries only the URLs, because the
caller already knows the hoster and the file.

**Generating the message:** `ai/description_template.md` is the spec. `MessageSection` owns the
title line and the text box, `MessageController` owns the render and the write. `generate()` reads
the two templates and the style through `TemplateStore` (the asset bundle is a constructor
parameter, so the service reads no static), builds the values — the fields as `release.json` writes
them, plus `name`, `tracker`, `releaseType`, `posterUrl`, `appVersion`, and the
two block variables, `screenshotSection` and `appSignature`; `tracker` and
`releaseType` are the technical names, because a template is written in the
language the tracker publishes in and writes its own words, so the app can only
provide the ID — only the
release's own field values, because the renderer has no iteration and no template lists items, so a
per-item value is not something a template can read — renders the post
text and the title through `TemplateRenderer`, and writes them to `message.txt` and `title.txt`.
The app signature is `appSignature.txt` rendered with the same
values, and it is empty when the Message section's checkbox is off; the flag is
one of the values the snapshot holds, so turning it off is a change to what a
render would produce and clears the box like a field does.
The files hold exactly the text the section shows, with no trailing newline, so the file, the box
and the pasted post are the same bytes; these are the only persisted files that do not end with a
newline. An edit in the box calls `saveText()`, which writes the file immediately, like the poster
writes its file, so the message is not part of the save and not part of the dirty flag. The title
has no write path, because it is read-only. A tracker with no title template renders an empty title
rather than failing, because the post text does not depend on it. A type with no title at all
(`hasTitle`) renders no title and writes no `title.txt`, so a release folder of such a type holds no
title file. What the section draws is what there is: no title line while there is no title, and the
placeholder rather than a box while nothing has been generated, the same shape the Screenshots section
has when it has no images. The Generate button in the title row is the part that stays, because it is
what can run —
that section hides its controls only when there is no item — so a message can only be typed after
something has been generated.

The renderer is a hand-written subset of the mustache grammar: variables, conditional and
inverted sections, style slots, `{{blank}}`, and block variables. It reads one line at a time,
so a section cannot span lines, and a line that renders to nothing produces no output line —
that is what keeps a skipped optional field from leaving a blank line. Consecutive blanks
collapse to one, because an optional field can be empty and two `{{blank}}` become adjacent
when it is. Leading and trailing blanks are trimmed.

Only `siteNumber`, `description` and `additionalInfo` are optional, and the template wraps
those in conditional sections. The image variables are empty when nothing has been uploaded.
Which hoster and which URL type a variable reads come from the constants at the top of
`message_controller.dart`: `realPosterHoster` and `mockPosterHoster` name the hoster the post's
poster comes from for the two runs, and `posterHoster` is the getter that picks which one applies —
fastpic for a normal run, `rptest-a` for a `--dev` run, where the first test hoster stands in for
fastpic so a development run produces the same shape of message and the backup block names the
second test hoster. `posterUrlType` is the type the poster uses. The screenshot block groups its
images by hoster, so it needs no rule for choosing one; a record appears under every hoster it was
uploaded to, with `imageUrlType` as the link and `thumbUrlType` as the picture. These are
per-tracker rules, so hardcoding them is the first-version choice rather than the design, and they
are not style keys: the style is appearance only. The path the user picked is not a value a
template can read, because a local path is not something a post shows. Only the release's own
field values are values; a per-item value is not one a template reads, because the renderer has no
iteration and no template lists items.

**Uploading a draft:** `ai/uploading_draft.md` is the spec. `DraftSection` owns the row, the
button and the link; `DraftController` owns the gates and the call, and reads the subject and
the message from `title.txt` and `message.txt` through `MessageStore.loadSync` — the two files,
not the text in the box, because the files are what the Message section owns and what a post
would be made of. A run is the two requests the spec describes: `GET
https://pornolab.net/forum/posting.php?mode=newtopic&f=<forum id>` for the page the form token
is read from, then `POST https://pornolab.net/forum/ajax.php` with the fields the form posts,
as `application/x-www-form-urlencoded; charset=UTF-8`. The forum id is the `f` parameter of the
URL the user wrote, which is the only part of it a request can be built from; the value itself
is stored as written. `draft_id` is 0 for a draft the app has not saved, and otherwise the
`draft` parameter of the link the release holds, so a second run updates the draft it made
instead of making another one; `is_tpl` is not read, because the app does not make a topic of
that kind. An answer that says the stored draft is gone is not a draft to link to, so the client
asks again with 0, which is the call that makes a new one, and the link the release keeps is the
new draft's; the new draft is asked for once, so a second such answer is what the run ends with.
The client is behind an interface, as `StashClient` is, so no test reaches the network, and the
rules it applies — a forum id read from a URL, the form body, a token read from a page, an
answer read as JSON — are functions on the interface, exercised directly. The token is cached in
the client, which is the only state any service holds, because the site ties it to the session
rather than to a release; an answer that says the token was not accepted drops the cache without
retrying, because the page would give the same one.
The request carries `User-Agent: ReleasePrepper/<version>`, built from `app_info.dart` rather than
a generic client string, so the site can identify the version it is talking to; the name is written
as one word because a product token is one word. No `Referer` is sent, because the app is not a
browser and has no page to be referred from.
Redirects are not followed, because a redirect to the login page is what a cookie the site does
not accept looks like, and following it would turn a clear answer into a page with no token. The
body is read as the charset the response declares rather than as what the app assumes, because the
site's pages are in windows-1251 and reading them as UTF-8 is what a run failed with; a charset the
app has no codec for, or none declared, is read as Latin-1, which cannot fail — the values the app
reads out of a response are ASCII, so an encoding it does not know is not a reason to lose a run,
and the text it produces is only what goes to the log. The limit is the 60 s one `ToolRunner` has.
The request and the answer are written to the tool log
with the cookie as the redacted marker, and the page is logged as the token read from it rather
than as its HTML, because a page is not an output line. The answer's headers are recorded with it,
except the ones that carry a credential, because a credential in a log file is a copy of something
the user keeps private — the same rule the cookie follows. A request that gets no answer is recorded
with the failure entry, so a call that failed before a response is not left as a request with
nothing after it; the reason is what the exception reported, and it goes to the log rather than to
the user.
The site's `error_msg` text is never shown to the user: only `error_code` 1 is known, so the
other codes are one result and the text goes to the log. What a run answered is shown as text,
and the link it is given is written through the editor's single write path, so the tab becomes
dirty; the link is the result, so there is no "draft saved" string, except for the run that had
to make a new draft, which says so because the link the release holds changed and the user cannot
see why otherwise. A link the release already has is shown even after the Message box was reset,
because a stored link is not something a reset takes away. The copy button next to the link is the
same call the Message section's copy buttons make, because the text is what a user takes to
another post, and it says nothing when it works, as they do.

**The tool log:** every call `ToolRunner` runs is written to
`<release_dir>/logs/log_<date of the first entry>.json`, one JSON object per line, as the
tool speaks. An entry carries the date (ISO 8601 UTC), the tool, the input, the stream,
and the line; the input is repeated on every entry so an entry stands on its own, and a
final entry records the exit code. Lines are split on newlines only, so the carriage
returns a tool uses to redraw a progress line stay inside the recorded text; the raw
output is accumulated separately for parsing. The first existing log file is appended to,
otherwise a new one is created named with today's date. Writes are serialized with a lock,
because several hosters write to the same file at the same time. Recording every tool call
rather than only uptooda is a deliberate broadening of the spec.

**Menu:** `MainMenu` is a `MenuBar` with `File` (`New Release`, `Open Release`,
`Save`, `Close tab`) and `Help` (`About`). `New Release` calls
`MainMenuController.onNewRelease()`, which asks `TabManager` for a wizard tab;
`About` opens `AboutPopup` through `showDialog`. All four File items carry
hotkey hints (Ctrl+N, Ctrl+O, Ctrl+S, Ctrl+W), drawn by `_itemLabel`: gray,
right-aligned with a 60 px minimum gap — the row fills the item because a
vertical menu wraps each item's child in an `Expanded`, so the hints line up at
the right edge. `MenuItemButton` cannot style its own shortcut label — it renders
it with the item's text style and a fixed spacing — and it does not handle the
key either: `MenuItemButton.shortcut` only shows a hint, so the hint is drawn by
the widget from `AppLocalizations` keys and the keys are handled by
`AppShortcuts`. The items and the keys call the same callbacks, so a menu action
and its shortcut do the same thing: `Close tab` calls the shared close flow, the
same path as Ctrl-W and the strip. `Save` is disabled when the selected tab is
not an editor tab and `Close tab` when no tab is open, which is why `MainMenu`
watches `TabManager` for that state.

**Opening a release:** the menu item and Ctrl-O both call the shared flow
`openReleaseWithErrors` in `release_open_flow.dart`, which calls
`MainMenuController.onOpenRelease(dialogTitle: l10n.chooseReleaseFolder, initialDirectory: ...)`,
which delegates to `ReleaseOpenController.openRelease()` — `FilePicker.getDirectoryPath()`
then `ReleaseStore.load()` — and returns a typed result. `initialDirectory` is the default
release directory from the settings, read by the widget from `SettingsController` and passed
down, the same way the wizard's folder button does it (rule 4: the controller builds no
dependency of its own); an empty value is passed as no directory, so the picker opens wherever
it would otherwise. `MainMenuController` does
not show messages; on `ReleaseOpenSuccess` it records the release in the recent list and asks
`TabManager` for the editor tab for that directory, and returns the result unchanged. The flow maps the
result to localized text:

| Result | Behaviour |
| --- | --- |
| `ReleaseOpenSuccess` | the entry is recorded, the editor tab for that directory is opened or focused, no message, flow ends |
| `ReleaseOpenCancelled` | nothing shown — cancelling is not an error, flow ends |
| `ReleaseOpenFailure` | error popup, then the flow repeats or ends |

The popup is an `AlertDialog` with `openReleaseError` as its title and the reason
as its content; `Close` ends the flow, `Choose another folder` repeats the pick.
A row of the recent list calls the same flow through `openReleaseFromPathWithErrors`, with the picker
skipped, so a failure reads the same from a row as from the menu item; that popup has only `Close`,
because the row names a folder the app has already read and there is nothing to choose again.
The reason comes from the failure kind:

| Kind | Reason key |
| --- | --- |
| `folderPicker` | `folderPickerFailed` |
| `manifestNotFound` | `releaseManifestNotFound` |
| `loadFailed` | `releaseMetadataInvalid` |

The retry loop lives in the shared flow, not in the controller: the controller
returns a typed result and the flow decides the UI. A dismissed dialog counts as
`Close`.

The error cannot be shown inside the folder picker itself: on Linux `file_picker`
calls `org.freedesktop.portal.FileChooser` over D-Bus, so the dialog is a separate
process and the app only receives the chosen path — there is no validation hook.
The same is true for the plugin's Windows and web implementations. Showing the
error inside a picker would require a Dart-implemented picker, which is a separate
component.

`ReleaseStore`, `TabManager`, `ReleaseOpenController`, `RecentReleasesController` and
`MainMenuController` are built by `appProviders()`; `MainMenu` reads the controller from the provider
scope.

**Saving:** `MainMenuController.onSave()` delegates the write to
`TabCloseController.saveTab` — the same path the close popup uses — and returns
whether it succeeded. The shared save flow `saveCurrentTab` in `main_menu.dart`
does nothing for a tab that cannot be saved (no tabs, or a wizard with no
release) and maps a failed write to `releaseSaveFailed`; it is used by the menu
item and by Ctrl+S. The editor's own Ctrl+S handler is nearer in the focus
chain, so it wins while a field inside the editor has focus, and the app-level
map answers the key otherwise — which is what the per-widget patches used to do
one case at a time. Both paths write the manifest through the same store, but
only the app-level one records the recent entry with the date the write stamped
(`ai/recent_releases.md` §3); the editor's own path does not.

**The recent list:** `RecentReleasesController.record(release)` is the entry rule — the entry for the
release's directory is updated or added, the entry opened least recently leaves when the list reaches 50,
and the file is written. It is called by the three paths that touch a release, and only when one of them
succeeds: `MainMenuController` after an open, `ReleaseWizardController` after a create,
`TabCloseController` after a save that wrote the manifest. The dates it stores are the values the release
object has at that moment, so a save refreshes the edit date with the stamp the write put in the file,
and a write that failed is not recorded. The table does not read `release.json`: the values are what the
last record left, and a row whose folder is gone still shows them. Which rows are gone is a stat per row
asked once when the tab opens, not a read of each manifest — that is the same fifty file reads the stored
values exist to avoid — so a file that is there but cannot be parsed is not marked and reports itself when
the row is clicked. The table also draws the immediate subdirectories of the default release directory that
hold a `release.json`, listed when the tab opens; those are not entries, so a row shows the name and the
path and nothing else and nothing is written from them, and a folder in both is one row with the values the
index holds. The page passes the directory it reads from `SettingsController`, as the open flow and the
wizard do, and asks for both checks in a microtask, because a controller that notifies while the frame that
created it is still building marks the provider scope as needing build while the framework is locked — which
is what happens when the list is empty and the check finishes without an await. The model is written first and the widget shows it, the same order as the editor's
write path; a write that fails does not change what the table shows, so the page says the file was not
written, as the settings page says the same for settings.json.

**Native tools:** `lib/service/native_tools/tool_locator.dart` decides where a
tool's executable is: the app bundle first, then PATH. A tool declared with a
bundle directory and no path fallback is bundled-only, so a system install of it
is never used — for uptooda that is the whole point, because the bundled copy
carries the modified upload scripts, and mkbrr is the other tool declared that
way. ffmpeg, ffprobe and mtn are declared with a bundle directory and the
fallback, because either copy is the same tool and their binaries are too heavy
to commit (`ai/bundled_native_tools.md`). `NativeTool({required name, optional
bundleDirectory, optional pathFallback})` is what says which case a tool is, and
`ToolLocation` is `ToolFound(path, ToolSource.bundled|system)` or
`ToolNotFound`. A file in the bundle is accepted on the same terms as one on
PATH: the execute bits, so a copy without them is not found and the fallback is
what the app uses instead. The check is made when a call starts, so a copy added
while the app is running is used by the next call. The PATH lookup is done in
Dart rather than with `which`, so `ToolRunner` stays the only code that runs a
process.

`ToolRunner.run(tool, arguments, releaseDirectory:, optional environment, optional
onOutput, optional timeout)` returns a typed result —
`ToolRunSuccess` (exit 0), `ToolRunFailure` (non-zero exit, with `exitCode`),
`ToolRunNotAvailable` (the tool is not where the locator resolves it, or the process
could not be started: not installed, not executable, or refused by the OS),
`ToolRunTimeout` (the call ran past the window it was given and the process was
killed) — each carrying `stdout` and `stderr`. It shows no messages, so a widget maps
them to localized text like every other controller does.

The runner reads the streams as the tool writes, because `Process.run` buffers everything
until the process exits and the log would record nothing until then. Every call the
runner runs is written to the tool log, one entry per output line, and a final entry
records the exit code. This is broader than the upload feature asked for: the log covers
every tool the app runs, not only uptooda. That is a deliberate choice — the log is the
record of what the app ran — and it is why the log writer is a parameter of the runner
rather than of uptooda.

The optional `onOutput` callback is given each chunk as the tool writes it, before the
process ends. That is what lets a caller show progress during a long run, since the
result is only known at the end. The runner does not interpret the chunks: the wrapper
that knows the tool's format reads them. It is a plain callback the caller passes, not a
listener (rule 3), and without it a call behaves exactly as it did before.

The window a call is stopped at is the one it was given. `callTimeout` is the default
for a call that does not ask for its own, and a wrapper whose call can legitimately run
longer asks for a bigger one — `Mkbrr.create()` asks for 60 minutes, because hashing a
whole release is not an upload with retries (`ai/torrents.md`). The window is the whole
call, from the process being started to it exiting, not a period of silence, so a call
that keeps writing progress is stopped when it runs past it. A call stopped this way has
no exit code on its log entry, because it was killed rather than finished.

A tool is a thin wrapper that names the executable and the commands the app uses and
takes the runner as a required constructor parameter: `Ffmpeg` with `version()` for
`ffmpeg -version`, `screenshot()` for one frame at the source resolution, and `resizeImage()` for an image resized
and written as a JPEG, `Ffprobe` with `probe()` for the single call that reads a file's
metadata, `Mtn` with `screenlist()`, `Uptooda` with `upload()` for one image to one
hoster, and `Mkbrr` with `create()` for one torrent — the 60 minute window it asks
the runner for, and the callback it reads the tool's progress segments with: the
percentage, the rate in the bracket before it, and the time left in the pair after
the bar (`ai/torrents.md`).
Every wrapper also has `version()`, the one call the System Check tab uses. Every call
takes `releaseDirectory`, because that is where the log is written.
Features call the wrapper, never the runner, and never through `Process` directly. All of
them are provider entries, so a test can substitute the runner; the editor reads
`Ffprobe` from the scope and passes it to its controller.

---

## 6. Localization workflow

- `l10n.yaml`: `arb-dir: lib/l10n`, `template-arb-file: app_en.arb`,
  `output-dir: lib/l10n`, `output-class: AppLocalizations`. Generated files are
  committed to the repo.
- `pubspec.yaml` sets `generate: true`.
- Add a key to **`app_en.arb` first** (it is the template), then add the same
  key to `app_ru.arb`, then run `flutter gen-l10n`. Keys present only in the
  Russian file produce no getters in `AppLocalizations`. The `openRelease` family
  (`openRelease`, `chooseReleaseFolder`, `releaseManifestNotFound`,
  `releaseMetadataInvalid`, `openReleaseError`, `chooseAnotherFolder`) is in both
  files and used by `main_menu.dart`. The `save` key, the `closeTabItem` menu
   label, and the four hotkey hint keys (`newReleaseShortcut`,
   `openReleaseShortcut`, `saveShortcut`, `closeTabShortcut`) are in both files
   and are used by `main_menu.dart`; the hint text is the same in both languages
   because the key names are not translated. The close-flow family
   (`closeUnsavedTitle`, `closeUnsavedMessage` with a `title` placeholder,
   `closeWithoutSaving`, `saveAndClose`, `cancel`) is in both files and used by
   `tab_close.dart`. The size field family (`fileSizeLabel`, `fileSizeDisplay`
   with `human` and `bytes` placeholders) is in both files and used by
   `file_size.dart`, which is why the word "bytes" is a template rather than text in the code.
   The StashDB family (`stashImportTitle`, `stashSceneInputLabel`, `stashFetchButton`,
   `stashApplyButton`, `stashInputInvalid`, `stashNoApiKey`, `stashRequestFailed`,
   `stashBadResponse`, `stashGraphqlError`, `stashSceneNotFound`, `stashImportNotesTitle`,
   `stashNoteSiteNumberStripped`, `stashNoteDomainFromOtherUrl`) is in both files and used by
   `stash_section.dart`, which is what maps a failure kind and an import-note kind to one of
   its messages (rule 13), and whose `stashImportTitle` is the title of the popup a successful
   fetch shows while `stashImportNotesTitle` is the title of its notes subsection. Both note
   messages take the field label as their `label` placeholder, so the note names the field with
   the same words the editor uses for it. The labels the widget shows for the values are the
   existing editor field labels, not new keys — including the scene URL row, whose label is
   `stashSceneInputLabel` itself. The Recent releases family
   (`recentReleases`, `noRecentReleases`, `recentPathLabel`, `recentSourceLabel`,
   `recentCreatedDateLabel`, `recentLastEditDateLabel`, `recentFolderUnavailable`,
   `recentWriteFailed`) is in both files and used by `recent_releases_page.dart`, which is also where the
   tab title comes from. The name, tracker and type headers are the existing keys (`releaseNameLabel`,
   `trackerLabel`, `releaseTypeLabel`), because the table shows the same labels the editor does; the path
   and the two dates have keys of their own, because the editor has no row that shows them as columns.
   The System Check family (`systemCheck`, `systemCheckToolLabel`,
   `systemCheckResultLabel`, `systemCheckToolNotFound`, `systemCheckRunFailed`,
   `systemCheckRunTimeout`, `systemCheckNoOutput`) is in both files and used by
   `system_check_page.dart`, which is also where the tab title comes from. The
   tool names are not keys, because a tool name is the same in every language,
   like a tracker name.
   The Clone Release family (`cloneRelease`, `cloneSourceLabel` with a `name`
   placeholder, `cloneNameMustDiffer`, `cloneNoPosterWarning`,
   `clonePosterNotUploadedWarning`) is in both files and used by
   `clone_wizard.dart`, which is also where the tab title comes from. The two
   warnings are separate keys because they say two different things: one is that
   the clone will have no poster at all, the other that a poster exists but its
   links cannot be copied. They end with the same sentence, because the advice is
   the same in both cases and the user should not meet it in two wordings. The
   name field reuses the wizard's `releaseNameRequired` and `releaseNameInvalid`,
   because the folder-name rules are the same, and only the rule the clone adds
   has a key of its own.
- Use placeholders as `'{title}'` and document them with
  `"@closeTab": { "placeholders": { "title": { "type": "String" } } }`.
- Regenerate after every arb change; do not hand-edit
  `app_localizations*.dart`.

**Keys present in arb but not used by any widget:** `releaseDetails` and
`releaseCreated` (both in both files). Every other key is used by
`main_menu.dart`, `about.dart`, `release_wizard.dart`, `clone_wizard.dart`,
`tab_strip.dart`,
`tab_view.dart`, `release_editor.dart`, or `stash_section.dart`.

The app name and version are not l10n keys: the name is a proper noun and the
version a number, so both are consts in `app/app_info.dart` and the About text
is built from them.

The editor field labels (`movieFilePathLabel`, `castLabel`, `videoTitleLabel`,
`siteNumberLabel`, `subsiteAndSiteLabel`, `productionDateLabel`,
`genreTagsLabel`, `durationLabel`, `videoTypeLabel`, `videoQualityLabel`,
`videoFormatLabel`, `videoStreamLabel`, `audioStreamLabel`, `descriptionLabel`,
`additionalInfoLabel`, plus `posterImageLabel`, `videoThumbnailLabel`,
`parentForumLabel`, `noImageSelected`, `noVideoSelected`, `chooseFile`, `chooseDate`, `filePickerFailed` and
`durationHint`) are in both files. The Russian values are the labels from
`ai/release_editor.md` as it states them, including the optional markers the
labels for items 4 and 15 carry. The English file holds their translations.
`movieFilePathLabel` is the label of the
source row for a type whose source is a file, `photosetFolderLabel` and `videoFolderLabel` are the
and `photosetPackFolderLabel`, `singlePhotosetFolderLabel` and `videoFolderLabel` are the ones for
the three types whose source is a directory; the label cannot come from `sourceKind` alone, because
a folder with videos is a different thing to pick than a folder with photosets, and a folder with
photos in it is not a folder with sets in it, so it is resolved per release type by `_sourceLabel`
in `release_editor.dart`. The source row is not a field, so it is keyed by `sourceRowKey` rather
than by a field name. The probe messages (`movieFileNotFound`, `probeToolNotAvailable`,
`probeFailed`), the thumbnail message (`thumbnailFailed`), the two box hints (`posterHint` and
`videoHint`, each shown only by the box it belongs to), the poster family (`chooseImage`,
`pasteFromUrl`, `nothingToPaste`, `removeImage`, `posterFileNotFound`,
`posterWrongFormat`, `posterUrlInvalid`, `posterDownloadFailed`, `posterWriteFailed`,
`posterRemoveFailed`) are in both files too and are used by `release_editor.dart`. The photoset
pack family (`photosetPackFolderLabel`, `chooseFolder`, `siteOrJournalLabel`, `periodLabel`,
`photosetCountLabel`, `totalPhotoCountLabel`, `totalSizeLabel`, `minResolutionLabel`,
`maxResolutionLabel`) is in both files and is used by `release_editor.dart`. `totalSizeLabel`
is the name the video pack has, and the two photoset field lists read it as well, because the
size they count is the same kind of value, so no label is added for them. The three names a
video pack has of its own (`videoCountLabel`, `videoResolutionsLabel`, `videoFormatsLabel`) are
in both files too; every other name its field list uses is one the other types already have,
because a credit is the same value as an actress name and a period is the same value, so no
label is duplicated. A single
photoset has three keys of its own: `imageFormatsLabel`, and the two words it uses for names the
other types already have, `modelLabel` and `setNameLabel`; those two are resolved per release type,
which is why the same field name reads as Cast in one form and Model in another. The release type
display names (`releaseTypeSingleVideo`, `releaseTypeVideoPack`, `releaseTypeSinglePhotoset`,
`releaseTypePhotosetPack` and `releaseTypeImageFolderUpload`) are in both files, in the order the
enum declares them, and are resolved by `releaseTypeLabel` in `release_type.dart`. Every one of
them carries a "(Beta)" marker except Single video. `genreTagsLabel` is reused rather than given a
pack name of its own, so the tags work for both types. `fieldLabel` in `release_fields.dart` is
the one function that turns a field name into a key, and `releaseTypeLabel` is the same for a
release type, which is why the editor's form, the wizard's dropdown, the editor's badge and the
Video pack section do not each carry their own table. `parentForumLabel` and `draftLinkLabel` are
two of those names, so the row the Upload draft section builds and the label above its link resolve
their words the same way rather than the widget carrying them. The five
column titles (`columnTitleReleaseInfo`, `columnTitleVideo`,
`columnTitleSourceFolder`, `columnTitlePhotosets`, `columnTitleImages`) are in both files and are
used by `release_editor.dart`, which resolves them per release type the same way, because a column
is named by what its rows are rather than by a field name. A photoset pack resolves only
`columnTitleReleaseInfo`, because the only column the editor titles is the one with its fields: what is
below it in that column is the Photosets block, which titles itself as a section does, and the columns after
the first are the photo area, which titles itself too (`ai/picking.md` §7). The word for the photoset column
is used only by a single photoset, because a pack titles no column. It is the same word as the heading a
pack's block titles itself with, and the word for the image folder column is the same as that section's
title, but these are separate keys, because a column title is not a section title. A tracker is not a key:
its name is the same in every language, so it is a field on `Tracker`. The Photosets family
(`scanPhotosets`, `pickPhotosets`, `photosetPickedOfTotal`, `photosetListSectionTitle`,
`photosetSkippedEntries`, `photosetUnreadPhotos`, `photosetNameCollisions`, `photosetNotCopied`,
`photosetEmptySets`, `photosetSourceNotFound`, `photosetSourceNotReadable`) is in both files and is
read through `photosetStrings()` in `photoset_group.dart`, which both widgets use; these are the
strings that read the same for one set. The ones that do not read the same for one set are keyed per
type — `photosetPackSectionTitle` against `singlePhotosetSectionTitle`, `photosetPackNoPhotosets`
against `singlePhotosetNoPhotosets`, `photosetPackSourceEmpty` against `singlePhotosetSourceEmpty` —
and are resolved by `photosetStrings()` in `photoset_group.dart`, the same shape as `_sourceLabel`
in the editor: one switch over the type, no table. It resolves three titles, because a pack shows
three things: the heading of the block, the header naming the list, and the title of the area that
shows the picked photos. The header is one key, `photosetListSectionTitle`, not a pair, because only
a pack has a list: the type with one set has null there and draws nothing (`ai/picking.md` §7). For
a pack the third title is `screenshotsSectionTitle`, the key the Screenshots section titles itself
with, so the two areas that show the same files the same way say the same word; for a single
photoset there is no area apart from the block, so both are `singlePhotosetSectionTitle`. The keys
are named for the pack because they were written when the pack was the only type that showed them.
`photosetPickedOfTotal`, `photosetSkippedEntries`, `photosetUnreadPhotos`, `photosetNameCollisions`,
`photosetNotCopied` and `photosetEmptySets` take placeholders and are documented with `@key` in both
files. The count key is the pair one line shows — the number the rule picked and the number the scan
counted — so its second placeholder is a String rather than an int: the value is the model's, and a
String placeholder is what lets a count a user edited in `release.json` be shown as it is. There is
no plural form anywhere, and none is needed: the pair is one format string, and the Russian value is
the same shape as the English one.
`videoSkippedFiles`, `videoUnprobedFiles`, `videoEmptyFolders`, `videoUnreadableFolders`,
`videoSourceEmpty`, `videoSourceNotFound`, `videoSourceNotReadable`) is in both files and is used by
`release_editor.dart` and `video_pack_section.dart`. The four report keys take a `{names}` placeholder and
are documented with `@key` in both files. What the scan could not take is listed by the section rather than
shown as a message, because a scan that ran and excluded files is not an error; only the cases where nothing
can happen at all are messages, and those are the same three as the photoset family's. The values the
section shows per video use the labels their fields already have, through `fieldLabel`, rather than keys of
their own, and the table's two value columns are those same labels. The name column is not a field, so its
header is `fileNameLabel`: the one key in the family that is neither a field label nor a message. The detail
lines are `label: value`, so the colon is punctuation in the widget, as the joins in the report lines are.
The Screenshots family (`screenshotsSectionTitle`, `screenshotCountLabel`, `generateScreenshots`,
`regenerateScreenshots`, `noScreenshots`, `selectVideoFirst`, `screenshotFailed`, `mtnNotAvailable`,
`screenlistFailed`) is in both files and is used by `screenshots_section.dart`; its failure mapping reuses
the probe and ffmpeg messages. The two button keys are the bare verbs, because the section's title already
says what the button acts on, and `selectVideoFirst` is the placeholder the section shows when there is no
item. The Upload family (`uploadSectionTitle`, `uploadNeedsImagesFirst`, `uploadNeedsScreenlistsFirst`,
`uploadButton`, `uploadProgress`, `uptoodaNotAvailable`, `imagesManifestFailed`) is in both files and is
used by `upload_section.dart`. `uploadProgress` is the bar's "{done} / {total}" text with two int
placeholders. The two placeholder strings are what the section shows instead of the list until the release
has the poster and an image of the kind its type produces; the widget picks between them per type, so a pack
names the screenlists and the other types name the screenshots. Only the cases where nothing can happen at
all get a message — the tool is not in the bundle, or `images.json` could not be written — because a
per-image upload failure is shown by the bar staying below full. `uptoodaNotAvailable` says the installation
is incomplete rather than "install it", because that tool is part of the app and is not something the user
installs. The Torrent family (`torrentSectionTitle`, `torrentButton`, `torrentProgress`, `torrentSpeed`,
`torrentEta`, `torrentCreated`, `torrentAlreadyCreated`, `mkbrrNotAvailable`, `mkbrrRunFailed`,
`mkbrrRunTimeout`, `mkbrrModifyFailed`, `folderOpenFailed`, `torrentPickFileFirst`,
`torrentPickFolderFirst`, `torrentPrivateLabel`, `torrentPrivateTitle`, `torrentPrivateMessage`,
`torrentPrivateValuePrivate`, `torrentPrivateValueNotPrivate`, `torrentPrivateConfirm`,
`torrentPrivateNotReadable`) is in both files and is used by `torrent_section.dart`. `torrentProgress` is
the bar's "{percent}%" text with one int placeholder; `torrentSpeed` and `torrentEta` are the `Label:
{value}` lines with one String placeholder each, because what the tool reports is text the app cannot format
as a number. The path the link shows is data, not a string, so it needs no key of its own, and
`folderOpenFailed` is the message for the link's failure, because the service itself shows nothing (rule
13). The tool name is inside the strings, as `uptoodaNotAvailable` has it, because a tool name is the same
in every language and has no key of its own, and `mkbrrNotAvailable` says the installation is incomplete for
the same reason. The outcome is shown in the section rather than as a snackbar, because the section is
already the thing that shows the run. `torrentPickFileFirst` and `torrentPickFolderFirst` are the
placeholder the section shows while no source is picked, and there are two of them because the
file-or-folder rule is the release type's: one key cannot say both. `torrentPrivateLabel` is the label of
the flag row. The popup has keys of its own because it is a question rather than a message:
`torrentPrivateTitle`, and `torrentPrivateMessage` with one String placeholder for the value it names, which
is why the two value strings exist — one key cannot say both "private" and "not private" — and
`torrentPrivateConfirm`, the verb the answer button uses, since `cancel` is the shared one.
`torrentPrivateNotReadable` is what the row says when the file cannot be read, and `mkbrrModifyFailed` is
the reason the tool printed, with one String placeholder, because a modify that cannot process the file
still exits 0 and the reason is the only thing it says. `ffmpegNotAvailable` is shared by both image flows:
it says "install it to work with images" rather than naming the thumbnail, so one key serves both. The
Message family (`messageSectionTitle`, `generateMessage`, `messageNeedsImagesFirst`, `noMessage`,
`screenshotLayoutLabel`, `screenshotLayoutByHoster`, `screenshotLayoutByItem`, `includeAppSignature`,
`templateNotFound`, `styleNotFound`, `templateInvalid`, `messageSaveFailed`, `fieldNotFilled`,
`productionDateInvalid`, `messageValidationFailed`, `copyToClipboard`) is in both files and is used by
`message_section.dart`. `includeAppSignature` is the label of the checkbox row, the row that decides whether
the message ends with the app signature. `noMessage` is the placeholder the section shows when nothing has
been generated, which is what its value already said: the box is not drawn when it holds nothing, so the key
is no longer a hint. `copyToClipboard` is the tooltip of every copy button — the Message section's two and
the one next to the draft link — so one key serves all three. The four failure keys are the cases where
nothing can happen at all: the template or the style is not in the bundle, a template line cannot be read as
it stands, or the file could not be written. The labels a template writes are not l10n keys — they are
literal text in the template file, in the language the site's rules require. The same is true of the two
words the post writes for a video's streams: they are constants in `message_controller.dart` next to the
block titles, because the post is in the language the site publishes in, not the language the app's UI is
in. The row that chooses the shape of the block is app UI, so its label and the two option names are keys in
both files. `messageNeedsImagesFirst` is the placeholder for the other case: the generation cannot run until
every image the message reads is uploaded to the poster hoster, so the key says what has to happen first
while the button is not drawn.

The three validation keys are the case where the fields are not complete.
`fieldNotFilled` and `productionDateInvalid` are one line each, with the
label as a String placeholder, because the rule answers with field names and
the words a name has come from `fieldLabel` (rule 13).
`messageValidationFailed` is the header the lines are joined under; a
placeholder is the only way a message can be built from a field list, which is
data. The sentence is written once, in `fieldProblemText`, because the same
problem is what the message shows and what the row of the field it is about
shows.

The Upload draft family (`draftSectionTitle`, `draftUploadButton`,
`parentForumInvalid`, `draftLinkLabel`, `draftNeedsMessageFirst`,
`draftNeedsLoginFirst`, `draftNeedsForumFirst`, `draftRecreated`,
`linkOpenFailed`) is in
both files and is used by `draft_section.dart`; the label of its row is
`parentForumLabel` and the label above its link is `draftLinkLabel`, both of
the field labels above, resolved through `fieldLabel` because the section owns
those two fields. `parentForumInvalid` is a problem line with the label as a
String placeholder, because the shape rule answers with a field name as the
other rules do, and the same sentence is what the row shows and what a run
reports. The three "…first" keys name the cases where a run cannot be made at
all, and one key serves both the line the section shows and the tooltip of the
button, because they say the same thing in the two places it can be asked.
`draftRecreated` is the one line a run that worked says, because the link the
release holds changes through it: a run that updated the draft the stored link
points at says nothing, and only the run that had to make a new one has a
change to explain.

The words for what a run answered are one family, `pornolab*`, because the
settings row and the Upload draft section show the same results:
`pornolabNeedsCredentials`, `pornolabLoginRefused`, `pornolabLoginNoCookie`,
`pornolabCookieRefused`, `pornolabNoToken`, `pornolabTokenRejected`,
`pornolabDraftGone`, `pornolabSiteError`, `pornolabBadResponse`,
`pornolabRequestFailed`,
`pornolabTimeout`. They were
`draft*` before the login, and the mapping that reads them is the shared one in
`lib/feature/pornolab_results.dart` (§4), so the same result cannot be said two
ways. The site's own error text is not among them, because it is not a key and
is not shown — it goes to the log. `pornolabDraftGone` is the word for the run
that could not make a new draft where the stored one was: the client makes the
new draft itself, so the run the widget sees is a saved one, and the line for
that run is `draftRecreated`, in the draft family above. `linkOpenFailed` is the
words for the
launcher failing, the same shape as `folderOpenFailed`, which is why a service
that shows no messages has a key in the widget that calls it (rule 13).
`pornolabUsernameLabel` and `pornolabPasswordLabel` are the two fields the
Integration section shows for the site, and `loginButton` and `logoutButton` are
the button on that row; the other settings keys are not listed here because the
page resolves them from its own section list. `pornolabCookieLabel` is gone with
the field it named.

---

## 7. Persistence format

The shape is the one `ai/release_structure.md` describes, and it is the same shape for every
release type: a Single video release is an item list of length one. The app has not been
released, so this is the first shape and there is nothing to migrate from. `schema` is 1, and
that is `schemaVersion` in `release.dart`, which both files write.

`release.json`, pretty-printed with 2-space indent and a trailing newline:

```json
{
  "schema": 1,
  "createdDate": "2026-03-11T10:00:00.000Z",
  "lastEditDate": "2026-03-14T18:22:31.000Z",
  "tracker": "pornolab",
  "releaseType": "singleVideo",
  "source": "/home/user/videos",
  "fields": { "videoTitle": "Example title" },
  "items": [
    { "path": "movie.mp4", "type": "video", "fields": {} }
  ]
}
```

- `tracker` and `releaseType` are the technical names — the enum values of `Tracker`
  (`tracker.dart`) and `ReleaseType` (`release_type.dart`) — not the strings the app shows. They
  are the IDs: the same names the template folder and file are built from and the field lists are
  looked up by. What the user sees is a display name, resolved when it is shown — `releaseTypeLabel`
  for a type, which is localized, and `Tracker.displayName` for a tracker, which is the same in
  every language. A value that is not one of the names this version knows is reported rather than
  guessed at, because there is no field list, template, label or icon for something the app does
  not have, and saving would write a name the file did not contain.
- `source` is what the user picked, a file or a directory, and it is the only absolute path
  in the format, because videos are never copied into the release. Item paths are relative to
  it, and a picked file is treated as a directory containing only itself, so a single video's
  item path is its filename. Which entries under the source are items is the field list's
  `itemBoundary`: for a pack they are the entries under the source, and for the two single
  types the source itself is the item, so its path is the source's own name.
  `Release.absolutePath(item)` is what turns an item path back into a file on disk, and it
  answers with the source for an item that is the source.
- `items` are the real files on disk the release is made of. Nothing is picked when a release is
  created, so a new manifest has no source and no item; the item appears when the user picks the
  file. An item path is the record ID the image records link to, so it is not generated from
  anything, and renaming the file changes it.
- `fields` is a plain map of field name to value, the same shape at both levels. Which names exist
  is the field list of the release type — `singleVideoFieldList`, `photosetPackFieldList`,
  `videoPackFieldList` or `singlePhotosetFieldList`. The path to the movie file is not a field,
  because the item is the file. For a Single video release the values are the release's own, so an
  item's `fields` is empty; for a photoset pack and a single photoset the scan writes the per-item
  photo count, and for a video pack the scan writes the values the probe reported for each file,
  which are empty for a file it could not read. The field list is what decides which level a value
  lives at (`ai/release_structure.md` §3).
- `type` is recorded when an item is created, not derived when a manifest is read, because what
  counts as an item depends on the release type.
- `screenshotLayout` is the shape the message's image block has. It is written only for the video
  pack, the only type that can choose, so a release of another type does not carry a shape it could
  never use. A manifest without the key, or with a value this version does not know, reads as
  `byHoster`, which is the shape every file was written with before the choice existed. It is stored
  on the record rather than in the app's settings because `message.txt` holds a block built with one
  of the two, so a release opened again has to show the shape its post was written with. The value
  is an enum name, as the two ID fields are, but a shape is not an ID: an unknown one is read as the
  default rather than reported, because there is nothing the app would have to look up for it.
- `name` is not persisted — on load it is derived from the directory basename
  (`p.basename(directory.path)`). There is no `notes` field yet.
- `createdDate` and `lastEditDate` are the record of the release changing. `createdDate` is
  written once by `create()` and never changes; `lastEditDate` is stamped by `save()` and by
  `touchLastEdit()`, which is what the operations that write files inside a release call — a
  generation run, a pick, an upload, a message, a poster. Both are UTC ISO 8601, the same as
  the tool log entries. A manifest that does not have them is read as having none and is
  written back without them: the app writes what the file contains rather than a date it
  invented, so a release it did not create stays without a creation date. A value that is not
  a date is read as none rather than reported, because a manifest is a file the user may have
  edited.

- `ReleaseStore.create({savePath, name, tracker, releaseType})` — creates
  `savePath` (recursive), then creates `savePath/name`. The fields it writes are
  the defaults of a new release, so the first manifest contains
  `"videoQuality": "SiteRip"`. If that directory
  already exists it throws `ReleaseAlreadyExistsException`. If writing the
  manifest fails, it deletes the created directory (best effort) and rethrows.
- `ReleaseStore.load(directoryPath)` — throws `ReleaseManifestNotFoundException`
  when `release.json` is absent, and `FormatException('Invalid release
  metadata.')` when the file is not a JSON object, or `tracker`/`releaseType`/`source`
  are not strings, or `tracker`/`releaseType` name something this version does not know. A
  missing or non-object `fields` or `items` is read as empty, so a
  manifest without them still loads, and the two dates are read as null when the file does
  not have them or cannot be read as a date. Called by `ReleaseOpenController.openRelease()`.
- `ReleaseStore.save(release)` — writes `release.toJson()`, so it writes the field values, the
  source and the items too, and stamps `lastEditDate` on the model before writing so the two
  agree; throws `FileSystemException` when the release directory does not exist. Called from
  `create()` and from `ReleaseEditorController.save()`.
- `ReleaseStore.touchLastEdit(release)` — stamps `lastEditDate` in the file on disk without
  writing the rest of the model, because the operations that write files inside a release are
  not part of a save and must not write the field values the user has not saved: a dirty tab
  keeps its values and stays dirty. It returns whether the file was written, and a run that
  cannot write it is not reported as a failure — the files it wrote are what the user asked
  for, and the next write stamps it again. Called by the Screenshots, Photoset, Upload and
  Message controllers and by `ReleaseEditorController._stamp()`, and only by a run that
  actually wrote something.
- Opening a release is a read and changes nothing; re-scanning is a manual action.
- `package:path` for joining, `dart:io` for file access. No database. The release files are the
  only data inside a release directory; the app's own settings and its record of the releases it has
  opened are the app-level files at the end of this section.

`images.json` at the release directory root is the tracking file for the images the app knows
about, pretty-printed the same way. It is one flat list of records, in the order the file lists
them, so a new kind is a value rather than a format change:

```json
{
  "schema": 1,
  "images": [
    {
      "item": "movie.mp4",
      "kind": "screenshot",
      "file": "images/movie.mp4/_rp_screenshot01.jpg",
      "urls": {
        "fastpic.org": {
          "delete_url": "",
          "direct_url": "https://example.com/images/test_image.jpg",
          "thumb_url": "https://example.com/thumb/test_image.jpg",
          "view_url": "https://example.com/images/test_image.jpg.html"
        }
      }
    }
  ]
}
```

- `item` is the item the image belongs to, as its path in `release.json`. Null means the image
  belongs to the release rather than to an item — the poster, which both a single video post and
  a pack post use.
- `kind` is the role the image has in the post: `poster`, `photo`, `screenshot`, `screenlist`.
  It is the role, not the provenance, and it is what decides whether an image can be
  regenerated. A record whose kind this version does not know is dropped on read rather than
  guessed at.
- `file` is relative to the release directory with `/` separators, so the manifest stays valid
  if the folder is moved. It is the record ID: there is no generated id field, so a rename loses
  the record.
- Order is data, scoped per item and kind. For copied images it is the order the source gives,
  for generated images the generation order, and for posters the priority: the first poster
  record is the primary one, and that is what `posterUrl` reads.
- `urls` is hoster → URL type → URL, under the field names the tool reports. Only successful
  uploads are stored, so a hoster with no entry is one the image has not been uploaded to — that
  is what the skip rule reads. An image that has been uploaded is never regenerated: records are
  added or removed only by a generation run or a manual re-scan.

`message.txt` and `title.txt` at the release directory root are the generated post text and
the generated title (`ai/description_template.md`). They are written as the rendered text with no
trailing newline, so the files, the Message section, and the text the user pastes are the same
bytes. These are the only persisted files that do not end with a newline, and it is deliberate: a
trailing newline would be part of the post.

`settings.json` in the app data directory is the app's own state — the first app-level file, and
the only one that is not inside a release directory. It is not part of a release and is not read
when a release is opened.

```json
{
  "schema": 1,
  "language": "ru",
  "defaultReleaseDirectory": "~/Documents/Releases",
  "defaultTorrentPrivate": true,
  "defaultIncludeAppSignature": true,
  "allowPlainSecrets": false,
  "plainSecrets": {}
}
```

- `language` is what the user chose, not what the app shows right now: `system` means the system
  locale. The values are the languages the app has translations for — `AppLanguage` in
  `settings.dart`, which is `AppLocalizations.supportedLocales` plus the `system` option, so adding
  a language means adding it there and to the arb files.
- `defaultReleaseDirectory` is stored as the user wrote it. A leading `~` means the user's home, so
  the default `~/Documents/Releases` is the same string on every machine and the app expands it when
  it uses the path, not when it stores it. It is what the new-release wizard prefills its save path
  with. A missing or empty value is read as the default.
  The expanded path is rebuilt from segments with the path context's separator, because the `~` form
  is written with `/` on every machine: appending it to the home as one string leaves a `/` inside a
  path whose other separators are `\` on Windows. What is stored is not rewritten, only the path the
  app uses.
- `defaultTorrentPrivate` and `defaultIncludeAppSignature` are what a release
  the app has not made yet is built with: the Private flag a new torrent is made
  with and the line the post ends with. They are defaults, not rules — the flags
  on a release are its own, in its manifest, so changing a default here does not
  rewrite a release that exists, and the editor, the Message section and the
  Torrent section still change the flags per release. A clone is built with the
  source's flags rather than these, because a clone is the same scene at another
  resolution. Both are on by default, which is the state the app has always
  created a release with, so a settings file written before the choice existed
  reads as that state. A missing key or a value that is not a flag is read as
  the default, the same rule `allowPlainSecrets` follows.
- `allowPlainSecrets` and `plainSecrets` are the fallback for a machine with no credential store.
  The values the Integration section stores normally live in the OS credential store, not here:
  `plainSecrets` holds only the values stored plainly, and only when the user allowed it. So an
  empty `plainSecrets` does not mean the app has no keys — it means the keys are in the store, or
  that nothing was stored because plain storage was not allowed.
- The credential store is per machine and per user, so the settings live in two places: this file
  and the store. A fresh machine has no keys, and a machine where the store cannot be reached has
  only the plainly stored ones. A value is never moved from the store to the file without asking,
  because a value the app moves on its own is a surprise.
- The plugin needs libsecret at build time and at runtime plus a running Secret Service on Linux,
  the C++ ATL build tools on Windows, and `keychain-access-groups` in both macOS entitlements —
  without that entitlement values look as if they were written but never come back. A value stored
  plainly is readable by anyone who can read the file, which is why the app marks it as not
  recommended.
- A file that does not exist or cannot be read is the same as a new one: the app follows the system
  locale, and there is nothing to report. A language this version does not know is read as `system`,
  because there is no translation to show for it. Other keys are not kept, because this is a file the
  app writes rather than one the user edits — unlike `release.json`, which preserves what it does not
  understand.
- It is written as the settings change, not at a save step, so the settings tab has no dirty flag and
  is not part of Ctrl+S. The model is written first and the widget shows it, the same order as the
  editor's write path; when the write fails the app still shows what was chosen and says the file was
  not written, so a failed write only shows up on the next start. A commit that happens while the page
  is being disposed cannot be reported, because there is no widget left to show the message, so it
  shows up on the next start too; it is deferred to a microtask, because notifying during unmount
  marks the provider scope as needing build while the framework is locked.
- The app data directory is resolved at the composition root and passed to the store as a function,
  because `path_provider` is async and a store builds no dependency of its own (rule 4), and because
  a test needs to point it at a temp directory.

`recent_releases.json` in the same directory is the app's record of the releases it has opened
(`ai/recent_releases.md`), pretty-printed the same way:

```json
{
  "schema": 1,
  "entries": [
    {
      "directoryPath": "/home/user/releases/example",
      "tracker": "pornolab",
      "releaseType": "singleVideo",
      "source": "/home/user/videos",
      "createdDate": "2026-03-11T10:00:00.000Z",
      "lastEditDate": "2026-03-14T18:22:31.000Z",
      "lastOpenedDate": "2026-03-15T09:12:04.000Z"
    }
  ]
}
```

- It is a file of its own rather than a field inside `settings.json`, because settings are the user's
  choices and this is a record of what happened; putting a history in settings would make it a setting.
- `directoryPath` is the key, and the only absolute path here, as `source` is the only one in
  `release.json`. `name` is not stored: it is the directory basename, as it is everywhere else, so a
  stored name could disagree with the folder it names.
- `tracker` and `releaseType` are the technical names, as in `release.json`, so a row agrees with the
  editor badges and the wizard dropdowns. This is the one place the app keeps them as strings rather than
  as enum values, because the file records what was read at the time, and a name this version does not
  know is shown as the string it holds — there is no label for something the app does not have.
- The dates are the values the app read the last time it touched the release, not a live read of
  `release.json`: `createdDate` and `lastEditDate` are what the release object held when the entry was
  recorded, and `lastOpenedDate` is the moment of the record. A date the release does not have is not
  written at all, as a manifest that has none writes none, and a value that is not a date is read as
  none rather than reported, because this is a file the user may have edited.
- `lastOpenedDate` is not a column; it is what the cap decides with, because the only thing a list of
  recents can order by is when it was opened.
- At most 50 entries, and the entry opened least recently is the one dropped when the 51st is added.
  There is no per-row remove and no Clear list, because the cap is what decides what leaves. A row whose
  folder is gone is not dropped from the file, because the folder may come back.
- A missing, unreadable, or non-object file reads as an empty list, as `SettingsStore` reads a missing
  file as the defaults, and an entry that is not an object is not kept.
- The folders the scan finds in the default release directory are not written here: the file holds what
  the app recorded, and the scan is only what the table draws (`ai/recent_releases.md` §5).
- It is written as the list changes, not at a save step, so the tab has no dirty flag and is not part of
  Ctrl+S. The model is written first and the widget shows it, the same order as the editor's write path;
  a failed write does not change what the table shows, so the page says the file was not written, as the
  settings page says the same for `settings.json`.

`window_size.txt` in the same directory is the app's record of the size the
window had at the end of the last run. It is one line of three whole numbers —
the format version, the width, the height — with a trailing newline:

```text
1 1440 900
```

- It is a file of its own rather than a field inside `settings.json`, for the
  same reason `recent_releases.json` is: settings are the user's choices, and
  this is a record of what the window was. Nothing on the Settings page reads or
  writes it, so nothing shows it.
- It is plain text rather than JSON because three readers read it: the app, and
  the Linux and Windows runners, which read it before they create the window so
  the window is created at the size the last run had rather than being resized
  to it after it appeared. A C or C++ runner has no reader for the app's JSON
  files, and a JSON library to parse two numbers would be a dependency for
  nothing.
- The app is the only writer; the runners only read. So what a line means is the
  format's rules, not a store's, and every reader must give the same answer for
  the same file: a line that is not three whole numbers, a version the app does
  not write, or a number that is not positive is read as nothing by all three.
  `1440.5` is not read as `1440`. A missing or unreadable file reads as nothing,
  as `SettingsStore` reads a missing file as the defaults, so a run with no
  record takes the size the runner starts with — the one
  `linux/runner/my_application.cc` and `windows/runner/main.cpp` define. Nothing
  is reported for any of it: a size that cannot be read is not something a
  runner can show, and a window that opens at the default size is not an error.
- The numbers are the size as the toolkit reported it, and a reader applies them
  in the units it read them in, which are the same units on a platform: logical
  pixels on Linux, where `gtk_window_get_size` reports and
  `gtk_window_set_default_size` takes; physical pixels on Windows, where
  `GetWindowRect` reports and `CreateWindow` takes — which is why the Windows
  runner does not scale a recorded size to the monitor, which is what
  `Win32Window::Create`'s `scale_size` is for. The macOS runner does not read
  the file (`lib/TODO.MD`).
- The directory has to be named the same way by both readers, so the runners
  reproduce what `path_provider` does. Linux: `XDG_DATA_HOME`, or
  `~/.local/share` when that is not set, plus the application id, which is what
  `g_get_user_data_dir` gives; path_provider's fallback to a directory named for
  the executable is not reproduced, so such a directory is not read. Windows:
  Roaming AppData plus `company-name\product-name` from the VERSIONINFO
  resource, with the executable name as the product when the resource has none
  and the names sanitised as `path_provider_windows` sanitises them, which is
  what `windows/runner/window_size.cpp` does.
- The version is written as `schemaVersion` (§4 rule 11) and read as a number
  that must equal it, the same field the other data files carry. In the runners
  it is a constant that must stay equal to the Dart const, because a C runner
  has no access to it.
- It is written at the point the app closes for real, not as the window is
  resized, because that is the only moment the app knows what the window was for
  a whole run. The same size as the one already recorded is not written again,
  the same rule as the settings feature's.
- Position is not stored, and the maximized state is not part of the record, so
  a window closed maximized is remembered at the size it was maximized to. §10
  keeps both as open work.
- A write that fails is reported to the caller rather than swallowed, but the
  caller is the close flow and there is no widget left that could say a file was
  not written, so it shows up on the next run as the size the runners read. The
  close does not depend on the write.
- What no test can check is the runners' own reading, which is these rules
  written in C and C++ with no test host for either. That is why the version
  constant, the rules about a line, and the directory are written the same way
  in every reader: they are one rule with three implementations, not three
  rules. What the three were seen to agree on is recorded in
  `ai/environment.md`.

---

## 8. Not live code — do not treat as working

- **`lib/TODO.MD`** — the open items, which §10 mirrors: tracker icons, what is
  left of Open Release, the subsite and site field shapes, a renamed file losing
  its record, the field rules for the release types that have none, bbcode in
  description and additional information, template and style validation, an image
  with no `thumb_url`, the source folder field, the editor button that fills the
  release tags from the items, and the macOS runner not reading the window-size
  record. What the list used to hold and no longer does
  is work the code already does: the native tools check is the System Check tab,
  the Screenshots slider has a fixed width, and the Settings credentials are read
  by the Stash and Upload sections.
- **`.widget_preview/`** — generated scaffold, gitignored.
  `lib/src/generated_preview.dart` returns an empty preview list, so it shows
  nothing until it is regenerated with `flutter widget-preview start`.
- **`ai/photoset_pack.md`** — the design for the fourth release type. The field list, the form,
  the scan, the header reader, the directory and ZIP readers, the picking rule and the photosets
  section are implemented; the pack template is not. So a pack release can be created, its folder
  scanned, and the photos the rule picks copied into the release and shown per set, but the message
  for a pack is not written yet.
- **`ai/video_pack.md`** — the design for the second release type. The field list, the form, the scan
  and the section are implemented as the first version, including the table with expandable rows, the
  slider and the button that generate the images for every item, and the table's flag columns; the
  per-item form, the images in the expanded detail, and the pack template are not. So a video pack can
  be created, its folder scanned, the items and the four aggregates recorded, the screenlists and
  screenshots generated for every item and reported by the table, and what either run could not do
  listed by the section, but a per-item value cannot be edited and the message for a pack is not
  written yet.
- **`ai/picking.md`** — the rule for how many photos a pack picks and which ones. Implemented as a
  pure function, tested on its own. What is still open there is whether the numbers are constants or
  tracker config.
- **`lib/l10n/app_localizations*.dart`** — generated. Never edit by hand.

---

## 9. Commands

```bash
flutter pub get
flutter gen-l10n          # regenerate AppLocalizations from lib/l10n/*.arb
flutter analyze
flutter test
dart format lib test      # the house style is the formatter's output (§11)
flutter run -d linux
flutter build linux
```

The formatter is the house style, so the tree is kept formatted. It does not
reflow comments, so comments are wrapped to the same 80 columns by hand; a
paragraph that already fits is left as it is. A line the formatter cannot break —
a single string literal, an import — stays as it is, and those are the only lines
over 80 in the tree. The generated `lib/l10n/app_localizations*.dart` come out of
`gen-l10n` already formatted, so they need no hand-wrapping.

`flutter build linux` runs `cmake --install`, which copies `native/uptooda/` into the
bundle next to the app executable; the app runs from that bundle, so the directory the app
runs from is the bundle, which is what `ToolLocator` uses as its bundle directory. The
binary is installed with `install(PROGRAMS)`, not `install(FILES)`: `install(FILES)` copies
with default permissions and does not keep the source's execute bit, so a binary installed
that way is found by the locator and then fails to start, which the app reports as the tool
not being available.

`flutter build windows` only runs on a Windows host, so the Windows build is
made on a Windows CI runner by `.github/workflows/windows-release.yml`; the
`windows/` runner is already in the tree. Its install step copies the tools the
app ships into the directory next to `release_prepper.exe`, which is the bundle
the app resolves from: `uptooda`, `mkbrr`, and the committed
`native/media/windows/` as `media/`, the one directory the three media tools
share (`ai/bundled_native_tools.md`). It also copies the three files only the
Windows build needs into `uptooda`: the CA bundle and the WebView2 loader beside
the tool, and the MIME database into its `Data/`. The workflow publishes that
directory as a GitHub Release asset, because the app is the directory and not
the executable: the tools are read from beside it. In the archive the directory
is named for the app rather than for the build configuration the toolchain wrote
it into, because the folder a user unzips is the app.

It is run by hand from the Actions tab, with the version to publish as its
input. The version is the name of a file under `changelog/`, because the form
cannot be where the notes come from: a dispatch input is one line. The run fails
before it installs anything if the version is not three numeric components, if
that file is not there or is empty, or if the tag `v<version>` already exists on
the remote, so a version that cannot be released costs nothing. The version is
then written into `pubspec.yaml` and the
`appVersion` const in `app/app_info.dart`, the two places the project keeps them
equal, and the commit that records it is the one the release is published for:
its header is the version, its body is the changelog file, and the release shows
the same text. The commit is made before the build, so the binary is built from
the version the release is published for, and pushed only after the build
succeeds, so a failed build leaves nothing on the branch; it is pushed to the
branch the run was started on, and the tag is made for that commit. The version
the executable reports in its own properties is not this one: `Runner.rc`
defines `FileVersion` from `FLUTTER_VERSION`, so it is the SDK the build used.
The publish step gives `gh` the run's token as `GH_TOKEN`, and
`permissions: contents: write` is what lets that token push the commit and
create the release.

The suite runs on both platforms, so a test that names a file by the folder it
came from reads that name with `p.basename`, not by splitting the path on `/`.
For the same reason a test builds a path with `p.join` rather than by
concatenating with `/`: the app builds it with the path context's separator, so
an expectation written with `/` matches only on Linux. A record path inside
`images.json` is still `/`, because that is how the manifest stores it, so a
test joins the release directory to it rather than rewriting it.

`flutter widget-preview start` regenerates `.widget_preview/`.

`test/release_editor_test.dart` covers the editor: a picked date reaches its
field, the form fills from a manifest, a change marks the tab dirty, Ctrl+S
writes the manifest and clears the flag, the fields the field model marks as
filled by the app are read-only, typing keeps the caret where the user put it
(the write path must not echo the value back), the size field shows the byte
count in a human-friendly form while the model keeps the bytes — for a value
read from a manifest and for one the probe wrote, since both go through the same
write path, `probeMovieFile()` passes the item's path to the tool and reports an
empty or missing path as `fileNotFound` (the tool is a fake there), a new
release starts with the default video quality while a loaded manifest shows what
it contains, a new release has no source and no item because an item is a real
file on disk, `setSource()` records the source and the item it is and marks the
tab dirty, the flags the record holds mark it the same way and the same value
again does not, and the flag a run changed is written to the manifest at once
without marking the tab dirty — a manifest that cannot be written is not
reported, the same rule as the stamp. An item path is relative to the source — a
picked file is the item itself, a picked directory contains it — the saving test
writes the record in the shape `release.json` now has, the thumbnail path is
derived from the release directory and the item path while the tool is called at
half the duration the probe reported (the tool is a fake there), and the
thumbnail box shows an image only for a file that is on disk: the test submits a
path, the fake tool writes the file, and the box shows it; the poster and
thumbnail boxes are 16:9 and start at the same height, so the frame a video
produces is not cropped and the two columns line up, and the tracker and
release-type badges come after the name at the gap rather than at the right edge
of the heading. The box tests look past the Upload section's hoster icons, which
are `Image` widgets too, by matching only the images whose provider is a
`FileImage`. The poster tests cover the same shape: there is no poster path
before a poster is recorded, and after that the path comes from the record, a
missing file and a wrong extension are reported as `fileNotFound` and
`wrongFormat`, `setPoster()` calls the fake tool once — the poster at 1200 px —
and records the poster, and `removePoster()` deletes the file and the record;
the poster box shows nothing while no file is on disk, shows the poster with
`BoxFit.contain` and the remove button when one is, shows nothing again after
removing, and the record is gone with it. A pasted link is checked the same way
a picked file is — the format comes from the path when the link names one, so a
link with a query is still a jpg and a rejected link is never downloaded — and
then goes through the same resize call with the temporary download as the input,
and that file is gone afterwards. A link that names no format is judged by what
the fake answers with as its content type: `image/jpeg` is accepted, `image/png`
and a response that says nothing are not. The download is a fake there, so
nothing reaches the network. The cache test puts a real image in the cache for
the poster's path, lets the widget write over it, and checks both halves: the
entry is gone, and the key the image is built with changed — without either the
box would still show the first image. Fields are found by the `ValueKey` the
editor gives them, so the tests do not depend on which column a field is in. The
sections are keyed the same way, on the widget that is their root — a `Column`,
or the `Row` the Stash row is — because a `StatefulWidget` element has no render
object to measure. The layout tests set the window size and read the rectangles:
at 2000 px the scene row is the first row of the left column, under the poster
box, and for the types that can be one of them — the single video and the video
pack — the section, the Upload section with the Message section are the columns
after the form, and the Torrent section is the last thing in the form's second
column, below its last field with the gap between sections rather than the gap
between the rows of a column, in the four-column layout and in the single-column
For a photoset pack the section is in the fields' column instead, because for
that type the form's second column is its data block, and in both layouts it is
the row above the Upload section, at the width of the fields' column. The test
reads it in both: at 2000 px it is below the fields at that width, and at 800
px, where there is one column, it is still the row above the Upload section.
one. For the photoset pack the block is the page's second column, at the most
the width this feature gives it, and the photo area is what the row has left:
the test reads the two column widths, the area and the two gaps and checks that
together they make the page, so nothing is left over at the right, and that the
block and the area both start at the top of the row. The other half of the rule
is its own test, at a window where the row cannot hold one column of the grid:
there the area is below the row at the whole width and the space beside the
capped block is left empty, and the same is checked at a window with room for
one column only, where everything is stacked and the block is capped there too.
Which column a photo is drawn in is not this test's — that is
`test/photosets_test.dart`, where the drawing is checked against the assignment.
The test reads the rows inside the block — the source row and the count field —
because for a pack those are the block's rows rather than the form's. The Upload
section and the Message section with the draft are below the fields in the
fields' column, at its width. At 1200 px the sections are
the same width but below the form, at the left edge, for the types with two form
columns; for a pack that is only when a single column fits, which its test uses
800 px for, because a pack has no second form column to make two fit. A field's
rectangle is its column width, so a field's width is what those tests read as
the column width. The column titles are keyed as `columnTitle`, so a test reads
them as the widgets the editor builds rather than as text: a photoset pack shows
the word "Photosets" twice — as the heading of its block and as the label of its
photoset count field — and "Screenshots" once, as the title of the photo area,
because the only column the editor titles for a pack is the one with its fields,
"Release Info". The title tests read the titles at the top of each column and as
wide as it, the small gap after a title measured against the image box that is
the first row of the column, and what each type calls its right column; each
type is its own test, because a pump reuses the state of a widget that is in the
same place, so one test cannot open two types. The editor now renders the
Message section, so every test that builds it provides the message dependencies
through a shared helper; the bundle answers with nothing, so the box stays empty
and none of those tests reach the Generate button. The editor also renders the
Stash row, so the same tests provide a `StashClient` that answers with nothing,
a `DomainMap` whose bundle has no mapping, and a settings controller with no
key; none of those tests reach the Fetch button, and the row's own behaviour is
in `test/stash_section_test.dart`. The editor also renders the Upload draft
section, so the same tests provide a settings controller with a client that
answers with nothing, and the fake launcher; none of those tests reach the
Upload button or the link, and the section's own behaviour is in
`test/draft_section_test.dart`. The pack tests cover the field list as the
editor uses it: a photoset pack shows its own fields and none of the video ones,
a video pack shows its own four aggregates as read-only and none of the photoset
ones — the total first, and shown in the human form as the size field is —, a
single photoset shows its own fields and the words its type uses for names the
other types already have — Model and Set name — and none of the fields it does
not have, the values the scan will write are read-only, an image folder shows
only the four values the scan counts and the words its type uses for the three
photo names — Images (total), Minimum and Maximum image resolution — with no
left column, because it has no field the user writes, the section list is per
type in all five directions — a photoset pack form has the Photosets block and
its photo area and no Stash or Screenshots section, a single photoset form has
the block with no area beside it because a single set has no columns for its
pictures and no Stash or Screenshots section, a video pack form has the Video
pack section and neither of the other two, an image folder form has the Image
folder section and none of the others, including no Upload draft section because
it has no title to send, a video form has the Screenshots section and no pack
section — while the other four forms have the Upload draft section, which is the
field list deciding rather than the widget, and while the poster box is in all
five, the source row label is the one the release type has because a folder with
videos is a different thing to pick than a folder with photosets, a folder with
photos in it, or a folder with images in it, a new pack release starts with no
values because its field list has no defaults of its own, and picking a
directory records the source without creating an item — the items of a pack are
what the scan writes. `test/release_store_test.dart` covers the two dates the
manifest records: `create()` writes the creation date and the write that created
the release is its first edit, both dates are read back from the file, a
manifest without them or with a value that is not a date loads with none because
the app writes what the file contains rather than a date it invented, saving
stamps the last edit while keeping the creation date as it was, and the stamp
the operations that write files inside a release make changes only the timestamp
— the field values the user has not saved are not written, so a dirty tab keeps
its values — and reports false when the manifest is not there or is not an
object. It also covers the three keys that are not fields, dates or IDs: each is
written and read back, and a manifest without one, or with a value this version
does not know, reads as the default rather than being reported as an error — the
shape the files were written with, a message with the signature, and a private
torrent. The two flags are checked as values the store is given rather than
values it decides: a new release's come from the settings and a clone's from the
source, so the same write serves both paths. `test/clone_controller_test.dart`
covers the copy rules: the fields the user writes are copied and the six the app
fills from the movie file are not, `sceneUrl` is copied although it has no form
row, `draftUrl` is not copied because a run wrote it while `parentForum` is, the
two flags are the source's rather than the settings' defaults, the poster record
is copied with its URLs and no other record is, the poster file is copied to the
same relative path when it is on disk, and a record whose file is not there is
written without a file, a source with no poster copies no manifest, and the
three poster states are what the manifest says, while a poster record that
belongs to an item is not the poster. The name must differ from the source's
while the folder-name rules still apply, the default save path is the folder the
source is in, a copy that fails removes the folder the create made, and only a
successful create is recorded in the recent list.
`test/field_validation_test.dart` covers the rules as a function over a field
list: a required field with no value, including one the app fills, the optional
fields being allowed to be empty, the three shapes a date may hold, the spaces
around a value not being part of it, and the URL shape the Upload draft
section's field is gated on — an absolute URL on the site with a positive `f` —
and the shapes a request cannot be built from: an id on its own, a path with no
host, a host the app does not name, a page that is not a forum, and a parameter
that is not a number. The rule asked for one field is the rule in the list,
which is what a section that owns its row asks for. A field list that has not
stated its required set is not checked, and the problems are in the order the
list lists the fields. `test/image_dimensions_test.dart` covers the header
reader: the dimensions a JPEG, a PNG and each of the three WebP chunk types
declare, that a header it does not understand is not guessed at, and that a JPEG
whose frame marker is past the bound it reads is reported as unread.
`test/masonry_test.dart` covers the placement: a photo at or above the span
ratio takes two columns, one below it and one whose header could not be read
take one, a span starts where both of its columns are free so the other keeps a
gap, ties go to the lower column index, and a grid that caps its span at one
puts every photo in one column and packs them as the shortest column, which is
what the Screenshots grid asks for. It covers the columns the grid fits from the
two widths it is given: as many as fit at the portrait width, each drawn at the
share of the space so the space is used up rather than leaving a strip at the
right that is narrower than a column, and a space narrower than the width is one
column. It covers the number of columns a landscape takes as the rule that works
it out of the two widths, including a pair that is not a whole multiple apart,
which takes the nearest whole number, and a landscape narrower than one column,
which takes one. It covers the columns each kind of photo gets when a pack's
grid is split: a kind with no photos has none, a kind with photos has at least
one column — for a landscape that is one of its own, so the span — and never
more than its photos need, and what the two minimums do not take is shared in
proportion to the counts, with a zone already at its need giving its share to
the other; and that a space which cannot hold a column of both kinds is not
split at all, and that the share of the space is bounded only when the caller
gives a maximum: with one the columns are drawn at the bound and the width past
it is left, and a share below the bound is still the share.
`test/section_title_test.dart` covers the shared title row: the title is at the
left and the action at the right edge, the title is centred on the row because
the row is as tall as the action, that the action is at least `actionMinWidth`
wide, and that with no action the row is only the title and is not taller than
it — the shape a section shows when it has a placeholder instead of controls
that can run. The minimum is read from the constant, so the test follows
whatever value it is changed to. `test/photoset_scan_test.dart` covers the scan:
a directory under the source is an item, a loose file at the top level is
reported rather than counted, files outside the extension list are not counted,
a subfolder inside a set is not read, and when the boundary it is given is the
source the source itself is the item and its path is the source's own name, the
order is the order the source gives, the minimum and the maximum are decided by
pixel area across all photos, a photo whose header cannot be read is counted and
reported, the formats are the distinct extensions among the counted photos
the size a photo has is the bytes the source gives it — the size on disk for a
file in a folder, the entry's own length for an archive, including the cases
where the header holds placeholders instead of the sizes — and the total is
summed across the sets, so a photo whose header cannot be read is still in it,
lowercased and sorted, display names two items would share are reported rather
than renamed, a source that is not there is a failure, and the scan reads
through the reader interface — a test with a fake archive reader shows that
adding a format does not change it. The ZIP fixtures are written by hand,
because the point of the package is the cases a hand-written reader gets wrong:
a stored entry, a deflated one, a data descriptor, a zip64 central directory, an
encrypted entry with no password, and a file that is not an archive at all. A
JPEG is included because its header needs a second read, which has to start from
the beginning of the entry again rather than from where the first read ended.
`test/photosets_test.dart` covers the controller and the two widgets: the scan records the
items and the per-item counts and returns the values for the editor's write path, kept to
the names the type's field list has — a pack is not given the formats because it has no
such field, and a single photoset is not given a count of sets because it has no such field
— and a single photoset is the source itself, so the scan records one item named by the
source. A re-scan replaces the items, the display name is derived from the path rather than
stored, and the block shows the sets with their counts and reports what it could not take,
including a name two items would share, and shows the strings of the type it is showing,
and that its Scan and Pick buttons are in its heading row rather than in a row of their
own. A test builds the block and the area with the state they share, as the editor does,
and builds them again after a run, because a test is not the editor and the area shows what
a run wrote only when the page builds again. For a pack the test asks the rule for the
picks rather than assuming them, so the names it compares are the ones the pick writes, and
the drawing is checked against the assignment the service gives for those names, for each
zone on its own; the space the area was given is read from what it drew, and the number of
columns, the width each is drawn at, the number a landscape spans and the columns each kind
is given are worked out from it with the rule rather than assumed — so the test follows
whatever the constants are changed to. Each tile is expected to carry the line naming its
set and its file name, because nothing groups the photos, and the block's line is expected
once, not also above a column; the fixture is a space that can hold a column of both kinds
and has photos of both kinds, so neither zone is the single column a kind is given when it
has nothing else to fill it with — that is what the split is tested against, and each tile
is compared with the columns of its own kind, with the column its zone starts at added. A
set with no photos shows its line in the block and nothing in the grid. A single photoset
places its tiles by the same grid, not split, because one set is nothing to group, and a
landscape spans the columns the two widths give, because its block draws them itself, and a
tile there carries its file name only.
The header naming the list is its own test: before a scan it is not drawn, because there
is nothing to name above the placeholder that says the list is empty, and after one it is
read as being between the rows the block was given and the first line; the test for the
type with no list asserts it is absent there. The pair a line shows is checked as the
number the rule gives for the fixture and the number the fixture has, so both come from
the rule and the fixtures rather than from a number written out, and before a pick its
first number is 0. The values include the total size, and the number a test expects is the
sum of the bytes its fixtures wrote, so an expected total is computed from the fixtures
rather than written out.
`test/image_folder_test.dart` covers the controller and the section: the scan
records the one item the picked folder is, copies every image into the release
in filename order — the fixtures are written out of order, so the test shows the
order is the name order and not the creation order — records them as `kind:
photo` for that item, and returns the values it counted for the editor's write
path; the picked folder is left as it is, because the copy is what makes a
record uploadable. A file that is not an image is not counted and is reported by
the feature rather than by the scan, and a re-scan replaces the photos this run
writes while keeping the poster. The widget tests check that nothing is shown
before a scan, that the section shows the images it copied with the count line,
that the values go through the editor's write path rather than the section's,
that what the run could not take is reported, that a run with no picked folder
says which folder it needs, and that the Scan button is in the title row.
`test/video_scan_test.dart` covers the walk: every video file is an item
wherever it is, including the ones in subfolders, with the path relative to the
source; a file outside the extension list is reported rather than counted, the
list is matched case-insensitively, a file the probe cannot read is still an
item and is reported, a subfolder with no video in it is reported, the
resolutions are distinct and sorted numerically by height rather than as text,
the formats are the distinct extensions lowercased and sorted — from the file
name, not from what the probe reports as the container — the total sums the
sizes the files have on disk rather than what the probe reports for the
containers, so a file the probe cannot read is still counted, the probe is
called once per item in the order the walk found them, a picked file is treated
as a directory containing only itself, and a source that is not there is a
failure. The probe is a fake, so these tests do not need ffprobe. A folder the
walk could not read is not tested, as the photoset scan's unreadable entry is
not: making a directory unreadable needs file permissions, which a test process
may ignore — running as root it reads a mode 000 directory — so such a test
could only pass for the wrong reason. `test/video_pack_test.dart` covers the
controller and the section: the scan records the items and the values the probe
reported for each and returns the aggregates for the editor's write path, a file
that could not be probed is recorded with empty fields, a re-scan replaces the
items, the section shows each video as a table row with its name, size and
duration and shows the values the row does not only when the row is clicked, and
a release opened with items shows them without a scan, because the section reads
what the release stores. It also shows what the scan could not take — nothing
before a scan — and a source that is not there as a message. For the generation
it covers the run recording what it wrote for every item in the order the scan
recorded them and reporting each record as its file is written — the test
asserts the report arrives while the run is still going and that the reported
records are the same ones the manifest holds at the end — a run with 0 writing
only the screenlist, a file that failed not stopping the run, a tool that is not
available stopping it, and a record whose file was deleted not being shown. The
widget tests check the value columns are right-aligned and the name is not, the
rows alternate with the tint on every other row and not on the header, the tint
read from the row's own `Material` — the nearest one above its content, which is
the surface the hover highlight is painted on — and covering the detail as well
because the band belongs to the row, the slider starts at 0 with the range the
pack allows, the button is disabled until there are items, the Scan and Generate
buttons are in the title row while the row below it holds only the label, the
slider and the count, the two flag columns show the checkmark and the count
after a run and are empty before it, the files the run could not do are a report
line that a re-scan clears, a tool that is not installed is a message, the open
row shows the images the run wrote while a closed row shows none, a record whose
file was deleted is not shown in the open row, and a tile's key changes when the
run rewrites the file it shows. The tools are fakes that write the files the app
decides by, so these tests do not need ffmpeg or mtn. `test/tab_strip_test.dart`
covers the tab card clicks: the middle button closes a tab without selecting it,
the primary button still selects it, and the hover tint on an unselected card is
gone when the card is clicked while the pointer is still over it — the card is a
stateful widget that paints the tint from its own hover state, so the test
hovers it, reads the colour from its `Material`, clicks it, and reads the colour
again. `test/tab_close_test.dart` covers the shared close flow: a clean tab
closes without a popup, a dirty tab shows the three options, Cancel keeps it,
Close without saving closes it, Save and close writes the manifest and closes
it, a failed save keeps both the popup and the tab open, the flow selects the
tab each popup names, and closing the app asks for each dirty tab (Cancel
aborts, confirming all closes, a clean tab is skipped). The save is real file
IO, so those tests run inside `runAsync` and stay in it for the whole flow: once
a flow starts outside the fake-async zone, its continuations only run while that
zone is active.

`test/tab_navigation_test.dart` covers the content area's page keys. It runs on
`TargetPlatform.linux`, because a widget test reports a mobile platform where a
scroll view inherits the primary controller by default, and the inheritance the
widget asks for is what makes a page resolve to the one the content area owns;
the override is cleared inside the test, since the framework checks the debug
variables before it runs `tearDown`. It covers a page resolving to that
controller, the default focus reaching a page that has nothing focusable in it,
which is the shape the recent list has, Tab still reaching the first field
through it, a page move of one page height, a move past what the page has
stopping at its end, Home and End reaching the top and the bottom, a press that
arrives during a move starting from where the page is rather than from where the
first move was going, a focused text field keeping the keys for its caret, a
focus outside the content area reaching no page, and the empty state, where
nothing has attached a position so the key is declined rather than answered with
one that does not exist. Since a key starts a move rather than answering with
where it ended, the positions are read after the move finishes; the mid-
animation read is on the frame after the one the move starts on, because that
frame does not move the page, and repeated presses are settled one at a time so
they add up rather than cancel each other in a single frame. The declined cases
read the key result, which is what shows nothing handled them, and the focus-
outside test asks for focus on purpose because the content area would otherwise
hold it. The field tests compare against the position the page had before the
key was pressed, because showing the caret can move the page; the field is
placed below what one page shows, so focusing it is what moves the page.`test/app_shortcuts_test.dart` covers the app-level placement: the keys are
reached from a focus inside the app and from a focus inside a popup route, a
nearer handler is asked first, and Ctrl+S reaches the shared save flow with a
popup open. The app is built as `app.dart` builds it, with the widget placed in
`MaterialApp.builder`; the save is real file IO, so it runs inside `runAsync`
like the close flow's tests.

`test/media_info_test.dart` covers the parser against a captured
fixture: the six values formatted as `ai/release_editor.md` specifies, a part
ffprobe does not report left out, the first stream of each type, and the
container name. `test/file_size_test.dart` covers the size display: the byte
count with its human-friendly form, a byte count too small to have a shorter
form shown as the number alone, and a value that is not a number shown as it is.
It also covers the human form alone, the form a fixed-width cell shows, and the
same two edge cases through it. `test/native_tools_test.dart` runs the real
binaries through `ToolRunner`: `ffmpeg -version` succeeds, a nonexistent
executable reports `ToolRunNotAvailable`, a non-zero exit code reports
`ToolRunFailure` with its code and output, and a call given a shorter window
than the default is stopped at it: `sleep` on PATH with a 1s window reports
`ToolRunTimeout`, and its exit entry records no code, which is what shows the
window is the one the call was given rather than the constant. One real
`ffprobe` call on a generated file produces the values the editor shows, and one
real `ffmpeg` call writes a full-resolution screenshot JPEG — the frame the
Screenshots section and the video thumbnail both write — (`-g 1` makes every
frame a key frame so the seek lands on one), and its dimensions are read from
the JPEG header with the same reader the scans use, so the test shows the
picture is not scaled down, and one real `mtn` call writes the screenlist JPEG —
the generated video is long enough that mtn does not warn, because a warning
makes it exit non-zero even when it wrote the file. Another real `mtn` call runs
on a video that ends with a black section and succeeds, which is what shows the
flags keep blank frames in the grid: with the default `-b 0.80` mtn would skip a
shot there and exit non-zero. The same file covers the log the runner writes: a
call that writes one line produces a line entry and then an exit entry with its
code, the input is repeated on every entry so an entry stands on its own, and a
last line with no newline is still recorded. Another test shows the environment
reaching the child — `sh` on PATH echoes the variable the call was given — and
that the recorded input holds no copy of it, which is why a credential is passed
this way. The tests build the runner through `test/test_runner.dart`, which has
an empty bundle directory, so every tool is read from PATH: one the app does not
ship, and one that prefers the bundle but has nothing in it.
`test/tool_locator_test.dart` covers the resolution rule: a tool with a bundle
directory and no path fallback is read from the bundle, and a tool that is not
in the bundle is `ToolNotFound` even when PATH has it; a tool with the fallback
is read from the bundle when it is there and from PATH when it is not; a tool
with no bundle directory is read from PATH. A file without the execute bits is
not a tool, in the bundle as on PATH, so a tool with the fallback uses the
system copy instead. On Windows the name with the `.exe` extension is the one
found, in the bundle as on PATH — the case the resolver could not find before.
The PATH and the platform are constructor parameters, so the test points them at
a temporary directory and runs on either platform; the execute-bit tests are
skipped on Windows, where there are no permission bits for the rule to check.
`test/screenlist_rows_test.dart` covers the rows formula on its own, as the spec
asks: below the minimum, exactly one frame per minute, a duration rounded up to
a whole row, and above the maximum. It calls `ImageGenerator.screenlistRows`,
the service that owns the rule now. `test/screenshots_test.dart` covers the
Screenshots feature: the controller names the files `_rp_screenshotNN.jpg`,
seeks to the centre of each equal segment of the duration, calls mtn once with
the rows the duration gives, records the screenshots and the screenlist in
`images.json` with the item they belong to and their kind, relative to the
release directory, keeps the records of the other kinds and items when it
regenerates, decides the screenlist by the file on disk rather than by the exit
code, and reports an empty or missing path as `fileNotFound`, a screenlist that
was not written as `screenlistFailed` and mtn not being installed as
`mtnNotAvailable`; a run that does not finish still records and returns what it
wrote (the tools are fakes there). It also covers the reporting: each record is
reported when its file is written, not when the run ends, and the records
reported are the same ones the manifest holds, in the same order. A run with 0
records only the screenlist, and a record whose file was deleted is not shown,
because what a section shows is the records whose files are on disk. The widget
tests check the slider range, the Generate button and that it is in the title
row while the slider is not, that the label, the slider and the count are on one
row, that the section shows the images the fake tools write, that the
screenshots are still shown when the screenlist was not written, that the grid
is two equal columns with the gap between them and the screenlist as its first
tile at the top of the left one, that the name under a tile is centred, that the
button becomes "Regenerate" once images exist, and that a tile's key changes on
regeneration so the image re-resolves the rewritten file. It also covers the
placeholder: with no item the section shows the placeholder saying to select a
video first and shows no controls. It also covers the run as it goes: the fake
writes one frame and then waits for the test, so the section is looked at in the
middle of a run and shows only the frame it has been told about, and the
function the editor passed it is called when the run ends, not while it runs.
`test/uptooda_test.dart` covers the parser against a captured `rpstub` fixture:
the four URLs are read from the fields the tool reports, `success: false` is an
upload failure whether the process exited 0 or 1, output with no JSON is
`noResult` (which is the unknown hoster case), and the runner results map to
`toolNotAvailable` and `timeout`. Another test checks the arguments the spec
fixes: one image, one hoster, `--code_lang json`, `--thumb_width 300`, and no
`--code_type`. A last one checks that the environment a call is given reaches
the runner unchanged, so a credential is not in the recorded arguments.
`test/upload_controller_test.dart` covers the rules the upload spec states: an
image already recorded for a hoster is skipped and one that failed is tried
again, a hoster that is not selected is never called, the state read at open is
what `images.json` holds for every hoster in the registry, so a run starts from
what the hoster already has rather than from 0, a failed upload does not
increase `done`, a hoster with nothing to upload reports a complete run, one
image at a time per hoster while the hosters run at the same time (the fake
counts what is in flight), a successful upload is written to `images.json` in
the record shape, the work list is in the order the file lists the records, a
poster record has no item because a poster belongs to the release, and the
environment is built only for a hoster whose registry entry names a settings
service — an empty value is not passed as a variable. The tests take the hosters
from `hosters.dart`, so they test the same data the app uses. It also covers the
last-edit stamp: a run that wrote a record stamps it and one that wrote nothing
does not, with the store a fake that records the stamps.
`test/upload_section_test.dart` covers the widget: the title row with the Upload
button at the right, the hoster list is rendered with every hoster checked by
default, only the checked hosters are passed to the controller, and with the
`--dev` flag the real hosters are replaced by the mock ones, so the section
lists only those and a run calls them. A bar is drawn for every hoster from the
state read when the section is opened — a release opened with its images
uploaded shows full bars, and a hoster that cannot run, or that has none of the
release's images, still has a bar: an empty one with the count reading 0 / 0. It
also covers the placeholder: a release with no images, and one with a poster but
no screenshots, show the placeholder saying what has to happen first, no hoster
list, and no button in their title row. It also covers the counters being read
again when a generation run ends: the test takes the rebuild the section
registers with the editor, changes what the store holds, calls it, and the bars
show the new count. It also covers that a run here ends by telling the editor,
because the run is itself what changes what `images.json` holds. It also covers
the credential rule: a hoster whose value is empty is rendered with an inactive
checkbox and the tooltip that says where to set it, and is not called; with a
value its checkbox is active and the value reaches the call. The store is a fake
there, given the manifest the section is opened with, so the run completes
inside the fake-async zone instead of through `runAsync`, and the settings are a
real controller given values directly, because reading them from the store is
what `test/settings_test.dart` covers. `test/fake_secret_store.dart` is the
credential-store fake both test files use. `test/style_test.dart` covers the
style grammar: `{content}` as the wrapper, a value with no `{content}` emitted
as it is, an empty value as no wrapper, a comment only at the start of a line,
`{token}` as another key, a token cycle left as it is rather than resolved
forever, and an undefined slot returning its content unchanged.
`test/template_renderer_test.dart` covers the line rules: a variable produces
its value, a skipped section produces no line at all, an inverted section
renders when the value is empty, a style slot wraps its content, `{{blank}}`
produces an empty line while an empty line in the template produces nothing,
consecutive blanks collapse to one, leading and trailing blanks are trimmed, the
result has no trailing newline, a block variable is inserted with its own lines
— each of them subject to the same rules as a template line — and a section not
closed on the same line is reported. `test/message_controller_test.dart` covers
the value rules: a tracker and a release type become the folder and the file
name, a template not in the bundle is reported, the title is rendered from the
title template and written to `title.txt`, the title file of the release type is
read before the tracker's and the tracker's is the fallback when the type has no
file of its own, its parentheses are omitted when the site number is empty, a
tracker with no title template still generates the message with an empty title,
a type with no title (`hasTitle`) reads no title file and writes no `title.txt`,
the poster comes from `posterHoster` whatever order the record holds and has no
value when that hoster is absent, that the first poster record is the primary
one, that with `--dev` the poster hoster is the first test hoster and the block
names the test hosters with the second as the backup, the block is one spoiler
per hoster then the backup poster with the screenlist as the last item, that a
photo is rendered in the block like a screenshot, a hoster with nothing uploaded
produces no spoiler, an image with no `thumb_url` is skipped, a poster on the
poster hoster produces no backup spoiler, nothing uploaded produces an empty
block so its line is dropped, and the text is written to `message.txt` with no
trailing newline. The asset bundle is a fake that answers from a map, so the
path rule is tested without the bundle on disk, and it throws the shape the real
bundle throws for a key it does not have, so the store's guard is tested against
what the app actually gets. `test/message_section_test.dart` covers the widget:
the title row with the Generate button at the right, that the box and the title
line show what their files contain, that clicking Generate replaces the box and
writes both files, that a type with no title draws no title line and writes no
title file, that an edit in the box writes the file immediately, and that each
copy button puts its text on the clipboard — the clipboard is a platform
channel, so the test records what the app writes to it. It also covers what is
drawn when there is nothing to show: with the images uploaded and nothing
generated the section is its title row with the button and the placeholder — the
title row is the whole section, because the button is the part that can run —
and the title line appears only when a title exists. It also covers the
generation gate: with nothing uploaded to the poster hoster, and with a record
that has no entry for it, the title row has no button and the placeholder says
what has to happen first, and neither flag row is drawn in that state (rule 14)
— the test uses the video pack, the type that can draw the shape row, so both
rows are covered. The button and the rows appear when the editor calls the
rebuild the section registered, which the test does by changing what the fake
store holds and calling it. It also covers that the copy button for the box is
at its top rather than in its middle. `test/pornolab_client_test.dart` covers
the rules the client applies without making a request: a forum id read from a
URL — the accepted shapes and the ones the rule refuses — the draft id read from
a link the app stored, the link built from the site rather than from what was
pasted, the form body encoded as UTF-8 and read back the same, a token read from
either form the page writes it in, a body read as the charset the response
declares — windows-1251 and UTF-8 as they say, Latin-1 for a charset the app has
no codec for or none declared, including the token read from a page in the
site's charset, which is the case that failed, the response headers the log
records with the ones that carry a credential left out, and a response read as
JSON for `draft_id`, for `error_code` 1, for a code the app does not know, and
for a shape it does not read. The page is a trimmed fixture written as a string
in the test, because the file the sample came from names a real account and is
not in the repo. The header is checked against `app_info.dart`, so the name and
the version the app sends are the ones the app has, and the name as one word
rather than as the display name. A request that gets no answer is checked
through a fake `HttpClient` that answers with an error instead of a connection —
it has only a factory constructor, so it cannot be extended — and the test reads
the log back to see the request entry and then the failure entry with the
reason, so the log is what shows why a run could not be made. It also covers the
login: the form body encoded from its Windows-1251 bytes, including the word the
site's own form uses for its submit button, a value with non-ASCII characters, a
character the codepage cannot represent, and an escape for a byte under 0x10,
and the body with the captcha's two fields in the order the form declares them;
the three parts read out of a page that asks for a code, and a page with only
some of them not being a captcha; the `Cookie` value built from the `Set-Cookie`
headers — attributes dropped, pairs joined, more than one header, an answer with
no pairs; and the judgement of the three shapes. A wrong cookie on the page the
token is read from is checked as the answer the site gives it: the 302 with an
empty body, not followed, so the call ends there (`ai/uploading_draft.md` §6).
Those are the shapes the tests hold rather than shapes observed on the site, as
the rest of this feature's shapes are, except the captcha shape, which was read
from a page the site gave, and the redirect a wrong cookie gets. The login entry
is read back from the log to see the credentials as the marker and the form's
two constants as their values, and no entry holds a cookie; a captcha entry
records the code and the sid as their values while the cookie stays the marker.
The first request a login makes is checked for carrying no `Cookie` header, and
the request with a code for carrying the cookie the captcha page gave, and the
token cache for being dropped by a login. `test/draft_section_test.dart` covers
the section: the gates and the order the tooltip says them in — the message, a
stored cookie, the forum — the row not being drawn while nothing has been
generated and a link the release already holds still being shown there, the row
showing the words of the shape rule, a value typed into it going through the
editor's write path, a run sending the two files the Message section owns rather
than the text in the box, the link a run answers with being written through the
write path, a stored link's draft id being the one the next run uses, a run with
no cookie stored not being made and saying where to log in, a cookie the site
did not accept being said as the result it is with the run not made again, and a
run that fails for any other reason being made once, a refused run saying what
it refused, the link opening the browser through the fake launcher and a failure
to open being shown as text, the title naming the tracker and the label above
the link saying what it is, with the label not drawn when there is no link, the
copy button writing the link to the clipboard through the mock platform channel,
and the section rebuilding when the Message section changes what it shows. The
client is a fake, so no test reaches the network; it is
`test/fake_pornolab_client.dart`, the same one the settings tests use, because
both controllers take it as a constructor parameter and the same fake is what a
test reads the calls back from. The settings are the same fake `SecretStore` the
settings tests use. `test/settings_test.dart` covers the settings: settings.json
is written in the shape the format describes, a missing or unreadable file reads
as the defaults, values of the wrong type fall back to the defaults, changing a
setting writes the file immediately and notifies, the same value again is not a
write, a file that cannot be written is reported as `writeFailed`, a stored path
starting with `~` is expanded when the app uses it rather than when it is
stored, and the expanded path is built with the context's separator, checked
with a Windows context because a rule that reads the platform can only be tested
on the platform it reads. The system language asks for no locale, and the
settings tab is opened once rather than twice. For the credentials: a value goes
to the store rather than to settings.json when the store is reachable, a value
is stored plainly only when plain storage is allowed, clearing a field removes
the entry rather than storing an empty string, and plainly stored values are
read back when the store is not reachable. The widget tests cover the page: the
section list shows the three sections and selecting one shows that section's
content, choosing a language writes the file, the Releases section shows the
setting and the two defaults as the settings hold them — on by default as a
settings file that does not exist is — writes the setting when the field is
submitted, when it loses focus, and when the page is removed, writes a default
when its checkbox is clicked, and draws the field and the folder button on one
line with the button to the right of the field and the field capped as the rest
of the page is, and the same check at a window narrower than the two controls
need shows them on two lines, because the point where the row stops is what the
controls need rather than a page breakpoint, the Integration section shows the
store state and the plain option, and a key typed into the field is written to
the store, including text that is still in the field when the tab closes. The
test builds the page inside the provider so it can remove the page while the
provider stays, which is what closing a tab does. For the row the login is on:
the field list is the four entries with the flag that says which of them the
page obscures, the username shown plainly and the password masked, the three
controls on one line — checked by where they are drawn, as the Message section's
tests do, because the page has another row an ancestor finder would match —, the
fields capped at the same width as the API key fields, and the same check at a
window narrower than the three controls need shows them on three lines, because
the width where the row stops is what the controls need rather than a page
breakpoint. The fields are disabled while a cookie is stored and the button
commits the fields before it calls the site, says Log in when no cookie is
stored and Log out in the error colour when one is, is disabled while a
credential is empty or a call runs, and shows the words for a refused login in
the error colour and the word for a login that worked in the green the page uses
for it, changes when a login is made from elsewhere, and a logout removes the
value without calling the site and takes the word for the login that made the
session away, because the space says the outcome of the last action. For the
captcha the page shows when an answer asks for a code: the word, the image and
the field for the code, the button gated on the code, the second call made with
the captcha and what was typed into it, and a captcha kept only for the answer
that asked for it. The image is not fetched, so the test reads the provider the
widget was given rather than the image it resolves; building the widget starts a
load, so that one test does reach the network, and the image widget's error
builder is what keeps a load that does not work from being reported as an error.
A test that types into a field and does not commit it closes the page first,
because the commit at dispose time reaches a controller the provider has already
disposed. The plugin is a method channel and cannot be exercised in a test, so
these tests use a fake `SecretStore`; the reads and writes are real IO, so the
interactions run through `tester.runAsync`.
`test/release_wizard_controller_test.dart` covers the point where the two
defaults reach a manifest: the release is built with the values the controller
was given, and a release built while the settings said one thing keeps them when
the settings say another afterwards, because the flags on a release are read
from its own manifest. The wizard widget has no test of its own, so this is
where the defaults are checked: the widget reads them from `SettingsController`
and passes them, as it passes the directory, and the controller is the object
that hands them to the store. `test/stash_client_test.dart` covers the parser
against a captured StashDB response: the values are read from the fields the
schema names, a studio including the URLs the domain is read from with the site
each URL is recorded under and that site's category, because those two are what
say whether a URL is the studio's own site or a link to another database, and a
site or a category the response does not report reads as an empty name; the
image order is kept because the first image is the poster, a part the response
does not report is an empty string rather than a guess, and the shapes a failed
query can have are reported as their own cases. The transport is not covered,
because it needs a real client; that is what the user tests against the live
instance. `test/stash_controller_test.dart` covers the input rules — a UUID, or
the last part of a scene URL, with a query or a fragment not read as part of the
id — that an invalid input and a missing key are reported before anything is
asked for, the mapping from a scene to fields — including the date field taking
the release date and falling back to the production date, the subsite and site
field reading the domain from the URL the preference order names (the Primary
sources category, then the site named Studio, then the first URL with a host,
and a URL with no host is never a candidate) with the name's capitalization when
the name is the same word as the host and falling back to the name when there is
no URL with a host, and the title with the site number cut off every occurrence
of it and the ends of what is left trimmed — that the fields filled from the
movie file are never filled from StashDB, that a value the import changed is the
kind the widget maps to a message plus the parts the app keeps and the parts it
cut, that a domain read from a URL outside the Primary sources category is a
note naming the URL it was read from while one read from the URL the rule names
produces none, that the poster preview is written to a file named after the
scene and removed when the popup closes, and that a domain the bundled mapping
has is what the field gets before the rule — including through a URL with
capitals, `www.` or a path — while a studio with no URL has no domain to look up
and so is not mapped. The mapping is read through a fake bundle, so a test that
is not about the file is not also about the file. `test/domain_map_test.dart`
covers the mapping service against a fake bundle: a key is read as the app
computes the domain, while a value is used exactly as the file writes it, an
entry whose value is not a string is not read, an asset the bundle does not have
or that does not parse or is not an object gives an empty mapping rather than an
error, and the file the app ships is checked as the mapping the app reads.
`test/stash_section_test.dart` covers the widget: the input and the Fetch
button, that nothing is shown until a scene has answered, that a successful
fetch opens the popup with every value listed and its checkbox checked — the
values are read from the mapping through the provider scope, so the popup shows
what it holds after the read completes, and a domain the mapping has is what it
shows and what Apply writes — that closing the popup without applying — by
Cancel or by clicking outside it — writes nothing, that only the checked ones
reach the callbacks, that the poster goes to the poster callback and not to the
field one, that the poster row shows the image for the file the download reports
and shows only its link when the download fails, that the image is below the
link rather than beside it, at the width the row has and 240 px tall, fitted and
drawn to the left, that a value the import changed is listed in its own
subsection below the poster, under the "Import notes" title, as the message that
says what was done to it followed by the value with the part it cut struck
through and with no checkbox of its own, that a domain read from a URL outside
the Primary sources category is listed with the URL it was read from, and that
the two studios of one field each have their own note because the note's key
includes its place in the list, and that a value it did not change leaves that
subsection out, that the input has focus again after the popup closes, that the
popup is capped at 1000 px, and that a failure is shown as a message. Its
settings are a fake `SecretStore` with the values the test puts in it, its
settings store is a fake too, its `AssetBundle` answers from a map so the
mapping is what the test gives it rather than the file on disk, and its
`ImageDownloader` records the paths it is asked to write to and writes nothing,
so the poster row is checked as the widget it builds rather than as a decoded
image and the test still does no file IO and does not need `tester.runAsync`.
`test/recent_releases_test.dart` covers the index: the file is written in the
shape §7 describes, a missing or unreadable file reads as an empty list, a value
the model cannot read is not kept, recording the same directory updates the
entry rather than adding a row, the 51st entry drops the one opened least
recently, the sort orders by the column it is given and breaks a tie by the
directory path, sorting does not change the order the list holds, a row whose
manifest is gone is reported as unavailable, and the scan lists only the
subdirectories that hold a `release.json`, reads a directory that is not there
as nothing found, keeps a folder in both the index and the scan as one row with
the index values, and writes nothing to the file. It also covers the tab rules:
the startup read opens the recent tab once, and opening a release that is
already open selects the tab that exists rather than adding a second one. The
widget tests cover the page: a row for each entry, the marker on a row whose
folder is gone, a row the scan found showing the name and the path and nothing
else, a header click sorting the table by that column, and that a row click
opens the release it names. The store is pointed at a temp directory and so are
the settings the page reads, so the scan is asked for the temp directory rather
than the user's; the reads and writes are real IO, so the widget tests run them
through `tester.runAsync`. `test/window_size_test.dart` covers the window-size
record: the file is written in the shape §7 describes, a missing or unreadable
file reads as nothing, a line this version does not read reads as nothing — a
version the app does not write, a number that is not a whole number, a size that
is not positive, a line that is not three numbers — and a line this version does
read reads as the size it states. Recording the size the window has writes the
file, the same size as the one already recorded is not written again, a size the
app cannot store is not recorded and leaves what was recorded as it was, and a
file that cannot be written is reported rather than swallowed. The store is
pointed at a temp directory, so the file is the app data directory's file with
the name the format gives it. The window is `test/fake_window_gateway.dart`, the
fake the window tests use, because the plugin is a method channel and cannot be
exercised in a test; it answers with the size it is given, which is all the
feature asks the window for. What these tests cannot cover is the runners
reading the same file: there is no test host for the C and C++ runners, so the
version constant, the rules about a line, and the directory are written the same
way in all three readers — one rule with three implementations, not three rules.
`test/system_check_test.dart` covers the check: each result kind is mapped from
the tool's typed result, the first line with text is the version as the tool
wrote it, a call that printed nothing is reported rather than guessed at, the
one tool whose version call does not exit 0 — mtn — is shown by what it printed
rather than by its exit code, the arguments the mtn version call is given, and
the order the page lists the tools. It covers the concurrency as well: a wrapper
that does not answer until the test lets it is reported after the ones that
answered, so a hanging tool is not what the other results are waiting for. It
also covers the tab rule: the check tab is opened once. The widget test covers
the page: the title and the two column headers, a row for each tool with what it
reported, including the mtn row showing the version it printed to stderr, the
status icon each result maps to, the capped and centred block with the centred
title while the text inside the table stays at the start, and a row that shows
the spinner in the icon column until its own result arrives while the rows that
answered show what they reported. The tool wrappers are fakes that answer with a
result the test gives, so these tests do not need the tools installed; the one
test that checks where the log is written runs the real ffmpeg through
`testRunner()`, as the native tool tests do. `test/torrent_file_test.dart`
covers the bencode reader: the flag is read from the `info` dictionary, a flag
of 0 is false, a file whose `info` has no `private` key is not private, a value
there that is not an integer is not a flag and is not guessed at, bytes that are
not a bencoded dictionary are reported as unreadable, and a key that is not the
flag — one outside `info`, one inside a nested dictionary, one inside a list —
is skipped rather than read. The fixtures are built from the parts in
`test/test_bencode.dart`, the file both this test and the section test use, so a
dictionary is closed by the same rule the format has and the two fixtures cannot
disagree. `test/mkbrr_test.dart` covers the wrapper: the arguments the spec
fixes — the source, `--private=` with the value the call is given, and
`--output` with the path the app asked for rather than the tool's default; for a
modify, the file it is asked for, `--private=` again, and the name and the
directory as two arguments rather than one path, because the tool's default
output directory is the working directory the runner does not set — the typed
results, the window the create call asks the runner for (60 minutes, while the
version call keeps the default), that the line a failed modify prints is the
reason and not the exit code, and the progress reader against a captured sample
of the tool's output: the percentage is read from each carriage-return-separated
segment, the rate from the bracket before it and the time left from the pair
after it, a field a segment did not have is null, a segment with no percentage
is not progress, a segment split across two reads is still read, and the last
segment, which has no carriage return after it, is read after the process ends.
`test/torrent_section_test.dart` covers the section: the title row with the
Create button, the bar and the percentage as the callback reports them, the rate
and the time left as the lines that are drawn only when the segment had them,
the button disabled while a run is going, the output path built from the release
name, each result mapped to its message, the file already on disk when a release
is opened again and a file named after an older release name, which is not the
one this release would write, the link that opens the release directory and the
message a failed open shows, and that there is no link while nothing has run and
no file is found. It also covers the placeholder: with no source picked the
title row has no button, draws no flag row (rule 14), and the section says what
has to be picked first, with the wording the release type decides — a file for a
single video, a folder for a pack — and that the button appears when the editor
calls the rebuild the section registered. It also covers the flag row: that it
is the first thing under the title, that it shows the value the record has, and
that when a file is on disk it shows the value the file states rather than what
the record says; a file that cannot be read is reported as such and the row is
inactive. The row is not drawn when there is neither a source nor a file (rule
14), and it is drawn for a file that is already there even when no source has
been picked. Changing the flag with no file goes through the change path without
asking; with a file the section asks first, a decline writes nothing and the row
goes back to what the file states, and an agreement runs the tool and the value
goes through the save path, not the change path, which is what the test records.
A change the tool could not make says the reason it gave and leaves the row as
it was, and the row is inactive while a run is going. The tool and the folder
opener are fakes that answer with the result the test gives. The existing-file
test puts the file on disk before `pumpWidget`, and the check the widget makes
while it builds is a synchronous one, so it works in the fake-async zone. Each
mapping is its own test, because the section keeps the outcome as its own state:
pumping the same widget again would still show the previous run's outcome. The
model, store and controller tests are plain tests, not widget tests, so real IO
completes without `tester.runAsync`; the same is true of the video pack tests,
which need ffmpeg, ffprobe and mtn on PATH, because the test runner gives them
an empty bundle directory. Real file IO inside a widget test has to go through
`tester.runAsync` — the test body runs in a fake-async zone, so awaiting a plain
`dart:io` call there hangs. A widget test also has to put the file on disk
before `pumpWidget`: `tester.pump()` does not rebuild a widget whose subtree is
unchanged, so a box built for a missing file would still show nothing.
`dart_test.yaml` sets a 30s per-test timeout so a hang is reported instead of
blocking the run for the default ten minutes, and caps the runner at
`concurrency: 2` so a full run leaves headroom for the desktop instead of
freezing it. The only CI config is `.github/workflows/windows-release.yml`, the
release (§9). The suite is not run by CI, so the tool preconditions the tests
state are met by the machine the tests are run on. `analysis_options.yaml`
includes `package:flutter_lints/flutter.yaml` and excludes `build/`, `windows/`,
`macos/`, `linux/` from analysis.

---

## 10. Open work

From `lib/TODO.MD` (deduplicated) and the gaps in §2:

1. Open Release, remaining gaps: distinguish a missing or unreadable folder from a
   missing `release.json` (`lib/TODO.MD` — the popup reports
   `releaseManifestNotFound` for both today), and a busy/disabled state for the
   menu item while the picker and the load are in flight. A row of the recent list
   goes through the same flow, so both gaps reach it too; the recent table marks a
   row only when the file is not there, because marking one whose file cannot be
   parsed would mean reading every manifest in the list.
2. Editor, remaining gaps: validation (the subsite and site fields are the
   first), bbcode in description and additional info. A per-item form does not exist for either pack,
   so the values a scan writes for one item cannot be edited in the app. Fields for tracker and release
   type, and the release-notes editor, are still open.
3. Tracker icons: the dropdown, the tab strip and the editor draw them through
   `TrackerIcon`, but `trackerIconAssets` has only the PornoLab entry, so the
   other trackers in `Tracker` need assets. A tracker the app knows but has no
   asset for shows a placeholder.
4. Check that the required native tools are installed: implemented as the System
   Check tab (`Help` → `System Check`), which lists the tools the app calls —
   `ffprobe` (the editor probe), `ffmpeg` (the editor thumbnail and poster, the
   screenshots), `mtn` (the screenlist), `uptooda` (the Upload section) and
   `mkbrr` (the Torrent section) — and shows each one's version or the reason it
   could not be run. For uptooda and mkbrr "installed" means present in the app
   bundle, since neither is read from PATH; for ffmpeg, ffprobe and mtn it means
   the app's own copy when the bundle has one and the user's tool otherwise.
   What is left:
   - the resolver finds a tool under the name the platform expects, so the
     Windows binary is found as `uptooda-cli.exe`. Both committed binaries are
     the same version (1.4.8), so there is nothing to align before a release.
     The Windows one has been run with the flags the app uses, and its stream
     separation and exit codes match the Linux one, but that was checked on the
     previous build and has not been re-run on the current one; the encoding it
     writes in is still open (`ai/bundled_native_tools.md`). There is no macOS
     binary, so the Upload section cannot work on macOS.
   - mkbrr has a Linux and a Windows binary; macOS has none, so there the
     resolver reports the tool as not present and the Torrent section cannot
     work. The version the committed binaries were built from and the tool's
     license are not recorded in the repo (`ai/bundled_native_tools.md`).
   - the font the app ships is opened by path, and that is verified on Linux
     only; the Windows side has not been checked. The font is not on the System
     Check, because a font that cannot be opened is not a tool that is missing.
     The committed media directory is likewise not proven complete on its own:
     the three tools started on a Windows machine, but the loader falls back to
     PATH, so that machine's own copies may have supplied the DLLs
     (`ai/bundled_native_tools.md`). A run on a Windows CI runner with only that
     directory on PATH passed the tool tests, which is what proves the closure
     complete; nothing in the repo re-checks it, so a run on a Windows host is
     what would re-check it.
5. Paste an image from the clipboard. The text path is done: the poster box's
   paste-from-URL button reads the link with `Clipboard.getData(Clipboard.kTextPlain)`
   and the controller downloads it. Pasting the image itself is still open, because
   Flutter's `Clipboard` API is text-only — `ClipboardData` has no image, and the Linux
   embedder rejects non-text formats ("GTK clipboard API only supports text") — so it
   needs an external tool (`wl-paste` on Wayland, `xclip` on X11) — a new required
   native tool — plus a binary-stdout mode in `ToolRunner` (`stdoutEncoding: null`).
   The poster box is already focusable, so the paste can be scoped to it once that is
   agreed.

6. Description message: implemented (`ai/description_template.md`). What is left:
   - the hoster and URL type constants in `message_controller.dart` are a first-version
     hardcoding. They are per-tracker rules, so the right place for them is a config of its own,
     not the style file, which is appearance only.
   - the block titles are written in code, as the block is, so they are the second part of the
     message that is not data. A second tracker needs its own strings.
   - the per-item description and poster lines the second shape of the block could show are not
     written yet: they are what a per-video `stash_url` import would fill (`lib/TODO.MD`).
   - grouping the block per item is decided for the video pack only, because it is the type the
     post names item by item. The other types keep the flat block, and the rule for them is still
     open (`ai/release_structure.md` §5).
   - validation of templates and style files (`lib/TODO.MD`): a style that does not define a
     slot the template uses renders as plain content, and a tag outside the tracker's dialect
     is emitted as it is rather than reported.
   - user styles. They need a writable location, which is the app's first app-level state, so
     it changes the persistence story in §7. A style defines every slot it uses; there is no
     inheritance.
   - the form validation that decides which fields are required. Until it exists, an empty
     required field produces a label with nothing after it in the generated text.

7. Settings: the General section is implemented. The Integration section has the StashDB and
   Postimages API key fields and the two PornoLab credentials on one row with the login
   button, with the credential store behind all four; the values are read, by the Stash
   section, by the Upload section, and by the Upload draft section, and the cookie a login
   gives is the value the settings feature writes. What is left:
    - the languages are the two the app has translations for, listed in `AppLanguage`. A third
      language needs an entry there plus an arb file.

8. Upload draft: implemented (`ai/uploading_draft.md`, `ai/pornolab_login.md`). What is left:
    - the login's shapes are held in the tests rather than observed on the site: whether the
      form body is read as Windows-1251, whether a redirect is the only shape an accepted login
      has, and whether the login page is the only shape a refused one has
      (`ai/pornolab_login.md` §4, §6).
    - only `error_code` 1 is known, so every other code is one result and its text goes
      to the log rather than to the user. The codes the site actually answers with would
      let a run say which one it got.
    - a stale cookie and a rejected token are the same answer, so the words for that case
      cover both; telling them apart needs a request that says which.
    - a run cannot be stopped and a draft cannot be deleted. Both are the site's rules
      rather than gaps in the code.
    - the section is gated on `Tracker.pornolab`, which is always true while `Tracker` has
      one value. It is kept because it is the rule the spec states and the first place a
      second tracker would be decided by.

9. Window size: implemented (`ai/doc.md` §7). What is left:
   - position is not recorded, and the maximized state is not part of the
     record, so a window closed maximized is remembered at the size it was
     maximized to rather than the size it had before. Recording either needs a
     rule for what a maximized window's size is, and the toolkit reports the
     size it has, not the size the user chose.
   - the Linux and Windows runners read the record before they create the
     window; the macOS runner does not, so on macOS nothing applies the recorded
     size (`lib/TODO.MD`). Doing it there is the same reading as the other two
     in Swift, with `path_provider`'s macOS directory rule reproduced, which is
     what §7 keeps as one rule with three implementations.

---

## 11. Working rules for agents

- Keep the §4 invariants. If a change needs a second global listenable, stop
  and reconsider the design; if it needs to break rule 3, say so first.
- `app.dart` stays a composition point: new UI goes into the feature that owns
  it, not into `app.dart`. A new feature is its own files under
  `lib/feature/<feature>/` plus one entry in `lib/app/app_providers.dart`.
- Controllers take required constructor parameters. No optional default that
  builds its own dependency.
- Widgets resolve dependencies from the provider scope; nothing reads a static.
- Every new user-visible string goes into `app_en.arb` + `app_ru.arb` and is
  regenerated, never hardcoded — except a proper noun or a number, which is not
  translated and lives as a const (see `app/app_info.dart`).
- New widget → new co-located controller. If it is a `ChangeNotifier`, that is a
  deviation from rule 3 and needs the user's agreement.
- Do not hand-edit generated l10n files.
- A new native tool wrapper is added to `SystemCheckController.calls()`, because
  that is the one list of the tools the app calls: a tool the app calls that is
  not in it is a page that does not report it. The page needs no change, because
  it draws one row per entry, but the controller gains the wrapper as a
  constructor parameter, which means a provider entry in `app_providers.dart`,
  and the fakes in the other test files that implement the interface gain
  `version()`.
- Do not commit `.widget_preview/` (it is gitignored).
- `name` in a loaded `Release` comes from the directory basename; do not rely on
  a stored `name` field.
- Format with `dart format` (`lib` and `test`) before reporting work as done; the
  house style is what the formatter produces, so a change that leaves the tree
  unformatted is incomplete. Comments are wrapped to the same 80 columns by hand,
  because the formatter does not reflow them; a paragraph that already fits is
  left as it is.
- Run `flutter analyze` before reporting work as done; the tree is expected to
  stay issue-free.



