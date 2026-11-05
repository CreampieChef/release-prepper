import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// The font the app ships, materialised into the app data directory so the tool
/// can open it by path (`ai/bundled_native_tools.md`).
///
/// libgd, which is what draws the screenlist, resolves a font name only through
/// fontconfig's own configuration, and that configuration names the system font
/// directories, not anything the app controls; it does not read
/// `FONTCONFIG_FILE` or `FONTCONFIG_PATH`. What it does resolve is a path, so
/// the tool is given the path of the file written here.
///
/// The font is written once. A file whose length already matches the asset is
/// left alone, so a run that writes screenlists does not rewrite 170 KB on every
/// call.
///
/// Only the weight the tool draws with is written here. The app's own text gets
/// the same font from the asset bundle through `pubspec.yaml`, so the other
/// weight in `assets/fonts/` is never read from this directory.
///
/// The asset bundle and the app data directory are constructor parameters rather
/// than `rootBundle` and `path_provider` inside the service (rule 10), so a test
/// can substitute both.
class FontStore {
  FontStore({required this.bundle, required this.appDirectory});

  final AssetBundle bundle;
  final Future<Directory> Function() appDirectory;

  /// The font the tool draws with. `Mtn` passes the path of the file written
  /// here, so the argument and the file have to be the same name; it is defined
  /// once, here.
  static const fontFileName = 'Roboto-Regular.ttf';

  static const _directoryName = 'fonts';

  /// The path of the font file, written here when it is not already what the
  /// asset is.
  Future<String> fontPath() async {
    final directory = p.join((await appDirectory()).path, _directoryName);

    await Directory(directory).create(recursive: true);

    final bytes = await bundle.load('assets/fonts/$fontFileName');
    final file = File(p.join(directory, fontFileName));

    if (await file.exists() && await file.length() == bytes.lengthInBytes) {
      return file.path;
    }

    await file.writeAsBytes(bytes.buffer.asUint8List());

    return file.path;
  }
}
