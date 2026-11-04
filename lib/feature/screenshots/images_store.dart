import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'images.dart';

/// Reads and writes `images.json` at the release directory root, alongside
/// `release.json`. It is the tracking file for the images the app generated.
///
/// A missing or unreadable file is read as an empty manifest: the section shows
/// nothing, and the next generation writes the file. This is a file the app
/// writes, not one the user edits, so there is nothing to report when it is
/// absent.
class ImagesStore {
  static const _fileName = 'images.json';

  String filePath(String directoryPath) => p.join(directoryPath, _fileName);

  Future<ImagesManifest> load(String directoryPath) async {
    final file = File(filePath(directoryPath));

    if (!await file.exists()) {
      return const ImagesManifest.empty();
    }

    try {
      final decoded = jsonDecode(await file.readAsString());

      return decoded is Map<String, dynamic>
          ? ImagesManifest.fromJson(decoded)
          : const ImagesManifest.empty();
    } on FormatException {
      return const ImagesManifest.empty();
    }
  }

  /// The same manifest read synchronously, so a widget can show it while it
  /// builds.
  ImagesManifest loadSync(String directoryPath) {
    final file = File(filePath(directoryPath));

    if (!file.existsSync()) {
      return const ImagesManifest.empty();
    }

    try {
      final decoded = jsonDecode(file.readAsStringSync());

      return decoded is Map<String, dynamic>
          ? ImagesManifest.fromJson(decoded)
          : const ImagesManifest.empty();
    } on FormatException {
      return const ImagesManifest.empty();
    }
  }

  Future<void> save(String directoryPath, ImagesManifest manifest) async {
    final file = File(filePath(directoryPath));
    final prettyJson = const JsonEncoder.withIndent('  ')
        .convert(manifest.toJson());

    await file.writeAsString('$prettyJson\n', flush: true);
  }
}
