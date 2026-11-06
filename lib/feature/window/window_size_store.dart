import 'dart:io';

import 'package:path/path.dart' as p;

import 'window_size.dart';

/// Reads and writes `window_size.txt` in the app data directory — the one
/// `path_provider` gives and `settings.json` already lives in. It is not a
/// field inside `settings.json`, because settings are the user's choices and
/// this is a record of what the window was (`ai/doc.md` §7).
///
/// A missing or unreadable file reads as nothing: the window has never had a
/// size the app recorded, so the app has nothing to compare the size it is
/// asked to record against. The file is one line of three whole numbers, the
/// format the runners read too, written with a trailing newline.
///
/// The app is the only writer. The Linux and Windows runners read the same line
/// before the window is created, so the rules about what a line means are
/// stated in §7 and the two readers must agree; what this store does is the
/// file, not the interpretation, which is `WindowSize.decode`.
///
/// The directory is passed as a function rather than resolved inside the store,
/// because `path_provider` is async and a store builds no dependency of its own
/// (rule 4). A test points it at a temp directory.
class WindowSizeStore {
  WindowSizeStore({required this.appDirectory});

  final Future<Directory> Function() appDirectory;

  static const _fileName = 'window_size.txt';

  Future<String> filePath() async =>
      p.join((await appDirectory()).path, _fileName);

  Future<WindowSize?> load() async {
    final file = File(await filePath());

    if (!await file.exists()) {
      return null;
    }

    try {
      return WindowSize.decode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> save(WindowSize size) async {
    final file = File(await filePath());

    await file.writeAsString('${size.encode()}\n', flush: true);
  }
}
