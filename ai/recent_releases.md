# Recent releases

Implemented: the menu item, the tab, the index file and the table. `ai/doc.md` describes it as part of
the app — §2 as a feature, §3 as files, §4 as the recorded deviations below, §5 as the runtime flow, §6
as the l10n keys, §7 as the file format, and §9 as its tests.

## 1. What it is

**File → Recent releases** opens a tab that lists the releases the app has opened, and the folders in the
default release directory (§5), so the user can go back to one without picking the folder again.

The tab is app-level state, so it follows the rule the Settings tab already follows: it is opened
once, and the menu item selects the one already open, because a second tab would show the same list
twice. Its icon in the strip is a clock (`Icons.schedule`), and its title is an `AppLocalizations`
key (rule 11). It has no dirty flag and is not part of Ctrl+S, because it holds nothing the user
edits — the same as the Settings tab, and closing it goes through the shared close flow without a
popup.

**The app opens it at startup, as the first tab, before any other tab.** Opening a tab is a side
effect, so this belongs to the feature's controller at startup, in the same shape as
`SettingsController.load()`, and not to `app.dart`, which composes (rule 8). The first frames show an
empty table, and the stored entries apply when the read completes — the same as the settings.

## 2. The index

`recent_releases.json` in the app data directory — the one `path_provider` gives and `settings.json`
already lives in. It is not a field inside `settings.json`, because settings are the user's choices
and this is a record of what happened; putting a history in settings would make it a setting.

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

- `schema` is 1, the same `schemaVersion` the other files write (`ai/release_structure.md`).
- `directoryPath` is the key. It is what identifies a release on disk, and it is the only absolute
  path here, as `source` is the only absolute path in `release.json`.
- `name` is not stored: it is derived from the directory basename, as it is everywhere else (§7).
  Storing it would make two releases with the same name disagree with the folder they are in.
- `tracker` and `releaseType` are the technical names, the enum values, as they are in
  `release.json`. The table shows the display names resolved when it draws, and a name this version
  does not know is shown as the string the file holds, because there is no label for something the
  app does not have.
- `source` is what the user picked, as the manifest holds it. It is a column because a video pack
  depends on that folder staying where it is, and a row that cannot say which folder it came from
  cannot be opened.
- The dates are UTC ISO 8601, the same as `release.json`, and are shown in local time.
- `lastOpenedDate` is not a column. It is stored because the cap needs a rule for which entry to
  drop, and the only thing a list of recents can order by is when it was opened.
- A missing or unreadable file reads as an empty list, as `ImagesStore` and `SettingsStore` read a
  missing file as empty. A value that is not a date is read as none rather than reported, because
  this is a file the user may have edited.
- The file is written as the list changes, so the tab has no save step and nothing to be dirty
  about. The model is written first and the widget shows it, the same order as the editor's write
  path; a write that fails does not change what the table shows, so the page says the file was not
  written, as the settings page says the same for settings.json.
- **At most 50 entries.** When a 51st is added, the entry opened least recently is dropped. There is
  no per-row remove and no Clear list, because the cap is what decides what leaves; a row the user
  could remove would be a row the app has to ask about for something the cap already settles.

## 3. What counts as an entry

- **Every successful open and every successful create**: File → Open Release, Ctrl+O, and the wizard,
  plus a save, which is what refreshes the edit date. A failed pick or an invalid folder is not
  recorded, because nothing was opened, and a write that failed is not recorded, because the date the
  file does not have is not a date the list should claim.
- **One entry per release directory.** Re-opening refreshes that entry's dates and moves it in the
  sort; it does not add a second row.
- **The dates are the values the app read the last time it touched the release**, refreshed on open
  and on save, not a live read of `release.json` when the table draws. They are stored for one
  reason: a row whose folder is gone still has to show something, and a table that reads each
  release.json to draw itself is fifty file reads for one screen.

## 4. The table

Columns: name, path, source, creation date, last edit date, tracker, release type.

One row per entry, plus one row per folder the scan in §5 finds.

- **Path is a column.** The name is the basename, so two releases can share it, and the path is the
  key the index is built on; a row that cannot say which release it is cannot be opened.
- Tracker and type show the labels the app already resolves — `Tracker.displayName` and
  `releaseTypeLabel` — so the table agrees with the editor badges and the wizard dropdowns and adds
  no new label vocabulary. The name, tracker and type headers are the existing keys; only path, the
  two dates, the empty state and the two failure lines are new ones.
- **Sortable by every column.** Clicking a header sorts by it; clicking it again reverses the
  direction. Default: last edit date, newest first. A column that was not the sorted one starts in its
  natural direction: newest first for a date, A to Z for a text column. Ties are broken by the
  directory path, in the same direction as the sort, so the same data gives the same order and
  reversing reverses the whole table rather than leaving ties where they were. A date the file does not
  have is none, and none is the earliest, so a row without a date is at the end of a newest-first
  order rather than in the middle of it.
- **Sorting is widget state**, as the Video pack table's open rows are (`ai/video_pack.md` §5). The
  order the file lists is data (`ai/release_structure.md` §4) and is not rewritten by a sort.
- **The rows scroll; the header does not.** The table can be longer than the tab — the scan has no cap
  (§5) — so the rows are a scrollable area and the header stays fixed above them, because the header is
  the control the table is sorted through. The write-failure line is a page-level message, so it stays
  outside the scroll and is always visible.
- A row whose `release.json` is not there any more is drawn with the values the index holds, dimmed,
  with an icon next to the name whose tooltip gives the reason, and marked as unavailable, not dropped:
  the folder may come back, and a row that disappears because of one failed read is a row the user did
  not ask to lose. Which
  rows are unavailable is a stat per row, asked once when the tab opens — not a read of each manifest,
  which is the same fifty reads the stored values exist to avoid. A file that is there but cannot be
  parsed is not marked; it reports itself when the row is clicked, through the open flow.

## 5. The default release directory

The table also lists the folders in the default release directory, so the user can go back to a release
the app has not recorded. These are not entries: nothing was read about them, so a row shows the name
and the path and nothing else, and nothing is written from them — the file holds what the app recorded,
and the merged view is what the table draws.

- **Immediate subdirectories with a `release.json`.** A subdirectory without a manifest is not a
  release, so it is not a row. The scan is a listing, not a read of each manifest, which is the same
  fifty reads the stored values exist to avoid.
- **The scan runs when the tab opens**, the same as the availability check, and the page passes the
  directory it reads from `SettingsController`, because a controller builds no dependency of its own
  (rule 4). It is deferred to a microtask, because a controller that notifies while the frame that
  created it is still building marks the provider scope as needing build while the framework is locked —
  which is what happens when the list is empty and the check finishes without an await.
- **A folder in both is one row**, with the values the index holds: the index is the record, and the
  scan only says the folder is there.
- **A directory that is not there reads as nothing found**, the same as a store that cannot be reached:
  the table shows what it has and does not report the folder.
- **No cap.** The 50 is a rule about the stored list, not about what a folder holds, so a directory
  with more than 50 releases shows all of them.
- A row the scan found is never marked unavailable, because the scan only lists folders that have the
  manifest. Clicking one opens it through the same flow, and the open records it, so after the first
  open it is a normal entry with dates.

## 6. Clicking a row

Clicking a row opens the release through the shared open flow (`release_open_flow.dart`), so the error
popup is the same one the menu item and Ctrl+O show, except that it offers only Close: the row names a
folder the app has already read, so there is nothing to choose again. When the release is already open,
the row selects that tab instead of opening a second one — the single-instance rule the Settings tab
uses, applied per directory.

This is a change to the open flow, which before could put the same release in two tabs.

## 7. Where the code goes

`lib/feature/recent_releases/`:

- `recent_releases.dart` — the entry model, the cap, the date comparison and the sort, and the row the
  scan found, which has nothing but the path because nothing was read. The comparator
  is built by the widget, because a column shows a display name and a display name is localized (rule
  13); this stays pure.
- `recent_releases_store.dart` — load/save for the JSON in the app data directory.
- `recent_releases_controller.dart` — the record rule, the availability check, the scan, the merged view
  the table draws, the startup read and the tab it opens. It is a provider entry, not a per-widget
  controller, because the index is app-level state, as `SettingsController` is (rule 5).
- `recent_releases_page.dart` — the table, and the widget state that says which column it is ordered
  by. It asks for the two checks when it opens and passes the default directory to the scan.

Plus the places the tab kind reaches: `AppTabKind.recentReleases`, the strip icon, `tabTitle`, the
`TabView` case, the File menu item, one entry in `app_providers.dart`, and the l10n keys for the title,
the new headers, the empty state and the two failure lines.

Recording is called from the three paths that touch a release — `MainMenuController` for an open,
`ReleaseWizardController` for a create, `TabCloseController` for a save — because each of them owns its
own side effect and none of them owns the list.

## 8. The decisions this took

- **Rule 12 limits `intl` to the formatting the generated l10n code needs.** Showing dates in local
  time uses it for date formatting, which extends its defined job; the rule text says so. The format is
  the locale-aware short date with the time, `DateFormat.yMd(locale).add_Hm()`, so a Russian locale gets
  the order it expects.
- **The controller is a `ChangeNotifier`**, the third Listenable in the app after `TabManager` and
  `SettingsController`, for the same reason the second is: the list is app-level state shown in a
  table, and a row appears when a release is opened while that table is open, so a plain callback
  controller cannot serve it. Recorded in `ai/doc.md` §4.
- **The startup tab is opened by the controller at startup**, not by the first frame of the tab view,
  because that keeps rule 8.
