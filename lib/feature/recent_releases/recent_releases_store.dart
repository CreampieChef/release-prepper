import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'recent_releases.dart';

/// Reads and writes `recent_releases.json` in the app data directory — the one
/// `path_provider` gives and `settings.json` already lives in. It is not a
/// field inside `settings.json`, because settings are the user's choices and
/// this is a record of what happened (`ai/recent_releases.md` §2).
///
/// A missing or unreadable file reads as an empty list: nothing has been
/// opened, so there is nothing to report. The file is written pretty-printed
/// with 2-space indent and a trailing newline, like the other files.
///
/// The directory is passed as a function rather than resolved inside the store,
/// because `path_provider` is async and a store builds no dependency of its own
/// (rule 4). A test points it at a temp directory.
class RecentReleasesStore {
  RecentReleasesStore({required this.appDirectory});

  final Future<Directory> Function() appDirectory;

  static const _fileName = 'recent_releases.json';

  Future<String> filePath() async =>
      p.join((await appDirectory()).path, _fileName);

  Future<RecentReleases> load() async {
    final file = File(await filePath());

    if (!await file.exists()) {
      return RecentReleases();
    }

    try {
      final decoded = jsonDecode(await file.readAsString());

      if (decoded is! Map<String, dynamic>) {
        return RecentReleases();
      }

      return RecentReleases.fromJson(decoded);
    } catch (_) {
      return RecentReleases();
    }
  }

  Future<void> save(RecentReleases releases) async {
    final file = File(await filePath());
    final prettyJson = const JsonEncoder.withIndent('  ')
        .convert(releases.toJson());

    await file.writeAsString('$prettyJson\n', flush: true);
  }
}
