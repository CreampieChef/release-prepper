import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'tool_log_entry.dart';

/// The tool log (`ai/upload_images.md`): one JSON object per line, appended as
/// the tool writes. A file is named after the first entry it holds, so every
/// later entry goes into the same file.
///
/// Writes are serialised here: several hosters run at the same time, and a JSON
/// Lines file cannot be appended to from two places at once.
class ToolLog {
  static const directoryName = 'logs';
  static const filePrefix = 'log_';

  Future<void> _writes = Future<void>.value();

  Future<void> write(String releaseDirectory, ToolLogEntry entry) {
    final next = _writes.then((_) => _append(releaseDirectory, entry));

    // A failed write must not stop the entries after it.
    _writes = next.catchError((_) {});

    return next;
  }

  Future<void> _append(String releaseDirectory, ToolLogEntry entry) async {
    final directory = Directory(p.join(releaseDirectory, directoryName));

    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    final file =
        _existingFile(directory) ??
        File(
          p.join(
            directory.path,
            '$filePrefix${_date(DateTime.now().toUtc())}.json',
          ),
        );

    await file.writeAsString(
      '${jsonEncode(entry.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// The log file that is already there, or null when this is the first entry.
  File? _existingFile(Directory directory) {
    for (final entry in directory.listSync()) {
      if (entry is File) {
        final name = p.basename(entry.path);

        if (name.startsWith(filePrefix) && name.endsWith('.json')) {
          return entry;
        }
      }
    }

    return null;
  }

  String _date(DateTime date) => date.toIso8601String().split('T').first;
}
