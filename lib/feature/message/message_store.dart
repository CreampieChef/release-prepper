import 'dart:io';

import 'package:path/path.dart' as p;

/// Reads and writes the text files the Message section owns: `message.txt` and
/// `title.txt` (`ai/description_template.md`). Each holds exactly the text the
/// section shows.
///
/// Neither ends with a trailing newline: the file, the box and the text the
/// user pastes are the same bytes. This is deliberate and differs from
/// `release.json`, which ends with a newline.
///
/// A missing or unreadable file reads as empty: the section shows nothing until
/// the first generation.
class MessageStore {
  static const messageFile = 'message.txt';
  static const titleFile = 'title.txt';

  String filePath(String directoryPath, String fileName) =>
      p.join(directoryPath, fileName);

  Future<String> load(String directoryPath, String fileName) async {
    final file = File(filePath(directoryPath, fileName));

    if (!await file.exists()) {
      return '';
    }

    try {
      return await file.readAsString();
    } on Exception {
      return '';
    }
  }

  Future<void> save(String directoryPath, String fileName, String text) async {
    await File(filePath(directoryPath, fileName))
        .writeAsString(text, flush: true);
  }

  /// Removes one of the two files. A reset leaves nothing to show, and the files
  /// always match what the section shows, so an empty box means no file. A file
  /// that is not there is not an error: there is nothing to remove.
  Future<void> delete(String directoryPath, String fileName) async {
    final file = File(filePath(directoryPath, fileName));

    if (!await file.exists()) {
      return;
    }

    await file.delete();
  }

  /// The same text read synchronously, so the section can show it while it
  /// builds.
  String loadSync(String directoryPath, String fileName) {
    final file = File(filePath(directoryPath, fileName));

    if (!file.existsSync()) {
      return '';
    }

    try {
      return file.readAsStringSync();
    } on Exception {
      return '';
    }
  }
}
