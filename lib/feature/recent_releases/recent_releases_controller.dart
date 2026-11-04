import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../release/release.dart';
import '../tab/tab_manager.dart';
import 'recent_releases.dart';
import 'recent_releases_store.dart';

/// Owns the recent list and writes it.
///
/// It is a `ChangeNotifier`, which is a deviation from rules 3 and 7, recorded
/// in `ai/doc.md` §4: the list is app-level state shown in a table, and a row
/// appears when a release is opened while that table is open, so a plain
/// callback controller cannot serve it. It is the third Listenable in the app,
/// after `TabManager` and `SettingsController`, for the same reason
/// `SettingsController` is the second.
///
/// The file is written as the list changes, the way `SettingsStore` writes
/// settings.json: there is no save step, so the tab has no dirty flag and is
/// not part of Ctrl+S. The model is written first and the widget shows it, the
/// same order as the editor's write path; when the write fails the table still
/// shows what the app recorded, and the page says the file was not written.
///
/// The table also shows the folders in the default release directory
/// (`ai/recent_releases.md` §5), which are not entries and are never written:
/// the scan says a folder is there, and the merged view is what the table draws
/// rather than what the file holds.
class RecentReleasesController extends ChangeNotifier {
  RecentReleasesController({required this.store, required this.tabManager});

  final RecentReleasesStore store;
  final TabManager tabManager;

  RecentReleases releases = RecentReleases();

  /// The rows whose `release.json` is not there any more. Filled by
  /// `checkAvailability`, which the page asks for when it opens.
  Set<String> unavailablePaths = {};

  /// The folders in the default release directory that hold a `release.json`,
  /// filled by `scanDefaultDirectory`, which the page asks for when it opens
  /// (`ai/recent_releases.md` §5). These are not entries: nothing was read, so
  /// nothing is stored, and the file is never written from them.
  Set<String> discoveredPaths = {};

  /// What the table shows: the index, plus a row for a folder the scan found
  /// that the index does not have. A folder in both is one row, with the values
  /// the index holds, because the index is the record and the scan only says
  /// the folder is there. This is what the table draws, not what the file
  /// holds.
  List<RecentRelease> get rows => [
    for (final entry in releases.entries) entry,
    for (final path in discoveredPaths)
      if (releases.entryFor(path) == null) RecentRelease.discovered(path),
  ];

  /// Whether the last record could not be written. The page shows it as a line.
  bool writeFailed = false;

  /// Reads the file, then opens the tab the app opens at startup
  /// (`ai/recent_releases.md` §1). The first frames show an empty table, and
  /// the stored entries apply when the read completes.
  ///
  /// Opening a tab is a side effect, so it is here rather than in `app.dart`,
  /// which composes (rule 8); the same shape as `SettingsController.load()`
  /// being called at the composition root.
  Future<void> start() async {
    releases = await store.load();
    notifyListeners();

    tabManager.addRecentReleases();
  }

  /// Records one release: the entry for its directory is updated, or added, and
  /// the file is written.
  Future<void> record(Release release) async {
    releases.record(release, now: DateTime.now().toUtc());

    // A release the app has just read is a folder it can read, so the row is
    // not marked as unavailable any more.
    unavailablePaths.remove(release.directoryPath);

    notifyListeners();

    try {
      await store.save(releases);
      writeFailed = false;
    } catch (_) {
      writeFailed = true;
    }
  }

  /// Which rows no longer have a `release.json`. This is a stat per row, not a
  /// read of the manifest: the page asks once when it opens, and a row whose
  /// folder is gone is marked rather than dropped (`ai/recent_releases.md` §4).
  /// A file that is there but cannot be parsed is not marked, because marking
  /// it would mean reading every manifest in the list, which is what storing
  /// the values exists to avoid; a row whose file cannot be read reports that
  /// when it is clicked, through the open flow.
  Future<void> checkAvailability() async {
    final unavailable = <String>{};

    for (final entry in releases.entries) {
      if (!await File(p.join(entry.directoryPath, 'release.json')).exists()) {
        unavailable.add(entry.directoryPath);
      }
    }

    unavailablePaths = unavailable;

    notifyListeners();
  }

  /// Lists the immediate subdirectories of the default release directory and
  /// keeps the ones with a `release.json` (`ai/recent_releases.md` §5). A
  /// subdirectory without a manifest is not a release, so it is not a row. A
  /// directory that is not there reads as nothing found, the same as a store
  /// that cannot be reached: the table shows what it has and does not report
  /// the folder.
  Future<void> scanDefaultDirectory(String directory) async {
    final found = <String>{};
    final root = Directory(directory);

    if (await root.exists()) {
      await for (final entry in root.list()) {
        if (entry is! Directory) {
          continue;
        }

        if (await File(p.join(entry.path, 'release.json')).exists()) {
          found.add(entry.path);
        }
      }
    }

    discoveredPaths = found;

    notifyListeners();
  }
}
