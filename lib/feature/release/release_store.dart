import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../message/screenshot_layout.dart';
import 'release.dart';
import 'release_fields.dart';
import 'release_type.dart';
import 'tracker.dart';

class ReleaseAlreadyExistsException implements Exception {
  const ReleaseAlreadyExistsException();
}

class ReleaseManifestNotFoundException implements Exception {}

class ReleaseStore {
  static const _metadataFileName = 'release.json';

  Future<Release> create({
    required String savePath,
    required String name,
    required Tracker tracker,
    required ReleaseType releaseType,
  }) async {
    final saveDirectory = Directory(savePath);
    await saveDirectory.create(recursive: true);

    final releaseDirectory = Directory(p.join(savePath, name));

    if (await releaseDirectory.exists()) {
      throw const ReleaseAlreadyExistsException();
    }

    await releaseDirectory.create();

    try {
      // Nothing is picked yet, so there is no source and no item: an item is a
      // real file on disk, and the user cannot add one that is not
      // (`ai/release_structure.md` §2).
      //
      // The fields a new release starts with are the defaults of its type's
      // field list.
      final fields = FieldValues();

      for (final field in fieldListFor(releaseType).fields) {
        fields.setValue(field.name, field.defaultValue);
      }

      // The creation date is set here and never changes; `save()` stamps the
      // last edit.
      final release = Release(
        name: name,
        directoryPath: releaseDirectory.path,
        tracker: tracker,
        releaseType: releaseType,
        source: '',
        fields: fields,
        items: [],
        createdDate: DateTime.now().toUtc(),
      );

      await save(release);
      return release;
    } catch (_) {
      try {
        await releaseDirectory.delete(recursive: true);
      } catch (_) {
        // Keep the original error.
      }
      rethrow;
    }
  }

  Future<Release> load(String directoryPath) async {
    final directory = Directory(directoryPath);
    final file = File(p.join(directory.path, _metadataFileName));

    if (!await file.exists()) {
      throw ReleaseManifestNotFoundException();
    }

    final decoded = jsonDecode(await file.readAsString());

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid release metadata.');
    }

    final tracker = decoded['tracker'];
    final releaseType = decoded['releaseType'];
    final source = decoded['source'];

    if (tracker is! String || releaseType is! String || source is! String) {
      throw const FormatException('Invalid release metadata.');
    }

    // A manifest naming a tracker or a type this version does not know is not
    // opened: there is no field list, no template, no label and no icon for it,
    // so the app cannot show or write what it cannot understand. It is reported
    // rather than guessed at.
    final knownTracker = trackerFromName(tracker);
    final knownType = releaseTypeFromName(releaseType);

    if (knownTracker == null || knownType == null) {
      throw const FormatException('Invalid release metadata.');
    }

    return Release(
      name: p.basename(directory.path),
      directoryPath: directory.path,
      tracker: knownTracker,
      releaseType: knownType,
      source: source,
      fields: decoded['fields'] is Map<String, dynamic>
          ? FieldValues.fromJson(decoded['fields'] as Map<String, dynamic>)
          : FieldValues(),
      items: _items(decoded['items']),
      screenshotLayout: _layout(decoded['screenshotLayout']),
      createdDate: _date(decoded['createdDate']),
      lastEditDate: _date(decoded['lastEditDate']),
    );
  }

  /// The block shape, or the default when the key is absent or names a shape
  /// this version does not know. A manifest written before the choice existed is
  /// not an error, and the default is the shape those files were written with.
  static ScreenshotLayout _layout(Object? value) =>
      ScreenshotLayout.values.firstWhere(
        (layout) => layout.name == value,
        orElse: () => ScreenshotLayout.byHoster,
      );

  /// A date, or null when the key is absent or is not a date the file can be
  /// read as. A manifest the app did not write is what the user may have
  /// edited, so an unreadable date is not an error and nothing is invented for
  /// it.
  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toUtc() : null;

  /// The items, or an empty list when the key is absent or not a list, so a
  /// manifest written before an entry had it still reads.
  static List<ReleaseItem> _items(Object? value) => value is List
      ? [
          for (final item in value)
            if (item is Map<String, dynamic>) ReleaseItem.fromJson(item),
        ]
      : [];

  Future<void> save(Release release) async {
    final directory = Directory(release.directoryPath);

    if (!await directory.exists()) {
      throw FileSystemException(
        'Release directory does not exist.',
        release.directoryPath,
      );
    }

    // A write of the manifest is a change to the release, so the timestamp is
    // stamped on the model before the file is written and the two agree.
    release.markEdited();

    final file = File(p.join(directory.path, _metadataFileName));
    final prettyJson = const JsonEncoder.withIndent('  ')
        .convert(release.toJson());

    await file.writeAsString('$prettyJson\n', flush: true);
  }

  /// Stamps `lastEditDate` in the file without writing the rest of the model.
  ///
  /// The operations that write files inside a release — a generation run, a
  /// pick, an upload, a message — are not part of the save, so they must not
  /// write the field values the user has not saved. This changes only the
  /// timestamp in the file that is on disk, so a tab that was dirty stays dirty
  /// and the file keeps what it holds. Returns whether the file was written; a
  /// run that cannot write it is not reported as a failure, because the files
  /// it wrote are what the user asked for, and the next write stamps it again.
  Future<bool> touchLastEdit(Release release) async {
    final file = File(p.join(release.directoryPath, _metadataFileName));

    try {
      final decoded = jsonDecode(await file.readAsString());

      if (decoded is! Map<String, dynamic>) {
        return false;
      }

      release.markEdited();
      decoded['lastEditDate'] = release.lastEditDate!.toIso8601String();

      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(decoded)}\n',
        flush: true,
      );

      return true;
    } catch (_) {
      return false;
    }
  }
}
