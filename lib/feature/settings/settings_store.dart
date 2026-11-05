import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'settings.dart';

/// Reads and writes `settings.json` in the app data directory (`ai/doc.md` §7).
/// It is the app's first app-level state.
///
/// A missing or unreadable file reads as the defaults: settings have never been
/// saved, so there is nothing to report. The file is written pretty-printed
/// with 2-space indent and a trailing newline, like `release.json`.
///
/// The directory is passed as a function rather than resolved inside the store,
/// because `path_provider` is async and a store builds no dependency of its own
/// (rule 4). A test points it at a temp directory.
class SettingsStore {
  SettingsStore({required this.appDirectory});

  final Future<Directory> Function() appDirectory;

  static const _fileName = 'settings.json';

  Future<String> filePath() async =>
      p.join((await appDirectory()).path, _fileName);

  Future<Settings> load() async {
    final file = File(await filePath());

    if (!await file.exists()) {
      return Settings.defaults();
    }

    try {
      final decoded = jsonDecode(await file.readAsString());

      if (decoded is! Map<String, dynamic>) {
        return Settings.defaults();
      }

      return Settings.fromJson(decoded);
    } catch (_) {
      return Settings.defaults();
    }
  }

  Future<void> save(Settings settings) async {
    final file = File(await filePath());
    final prettyJson = const JsonEncoder.withIndent('  ')
        .convert(settings.toJson());

    await file.writeAsString('$prettyJson\n', flush: true);
  }
}
