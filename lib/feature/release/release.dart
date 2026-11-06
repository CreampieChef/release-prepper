import 'package:path/path.dart' as p;

import '../message/screenshot_layout.dart';
import 'release_fields.dart';
import 'release_type.dart';
import 'tracker.dart';

/// The version of the shape `release.json` and `images.json` write
/// (`ai/release_structure.md`). The app has not been released, so this is the
/// first shape and there is nothing to migrate from.
const schemaVersion = 1;

// The item types are part of the field list of the type that produces them
// (`release_fields.dart`), because what counts as an item depends on the
// release type and the decision has to be recorded rather than re-derived
// (`ai/release_structure.md` §2).

/// A release: the record `release.json` writes, plus the directory it lives in.
class Release {
  Release({
    required this.name,
    required this.directoryPath,
    required this.tracker,
    required this.releaseType,
    required this.source,
    required this.fields,
    required this.items,
    this.createdDate,
    this.lastEditDate,
    this.screenshotLayout = ScreenshotLayout.byHoster,
    this.includeAppSignature = true,
  });

  final String name;
  final String directoryPath;

  /// When the release was created. It never changes. Null for a manifest that
  /// does not have it, because the app writes what the file contains rather
  /// than a date it invented.
  final DateTime? createdDate;

  /// The last time the app changed something in the release. It is stamped by
  /// `ReleaseStore.save()` and by `ReleaseStore.touchLastEdit()`, which is what
  /// the operations that write files inside a release call.
  DateTime? lastEditDate;

  // These are selected during creation. The editor won't change releaseType.
  // They are the technical names, not the display strings: `release.json`
  // stores the ID, and the display name is resolved when it is shown
  // (`release_type.dart`, `tracker.dart`).
  final Tracker tracker;
  final ReleaseType releaseType;

  /// What the user picked: a file or a directory. Item paths are relative to
  /// it, and a picked file is treated as a directory containing only itself, so
  /// a single video's item path is its filename.
  ///
  /// This is the only absolute path in the format, and it is knowingly not
  /// portable: videos are never copied into the release. Every path inside the
  /// release stays relative, so the manifest remains valid if the release
  /// folder is moved.
  String source;

  /// The fields that belong to the release. Templates read these
  /// (`ai/description_template.md`).
  final FieldValues fields;

  /// Which shape the screenshot block has (`ai/video_pack.md` §7). Only the
  /// video pack can choose one, because the two shapes name a video; the other
  /// types keep the flat block. It is stored because the message file holds a
  /// block built with one of the two, so a release opened again shows the shape
  /// its post was written with.
  ScreenshotLayout screenshotLayout;

  /// Whether the post ends with the app's signature
  /// (`ai/description_template.md` §App signature). It is stored for the same
  /// reason the block shape is: `message.txt` holds a post written with or
  /// without the signature, so a release opened again has to show the state its
  /// post was written with. Every type can include it, because the signature is
  /// the tracker's text, so every type carries it.
  bool includeAppSignature;

  /// The real files on disk the release is made of. The user cannot add or
  /// remove an item that is not on disk.
  final List<ReleaseItem> items;

  /// Where an item's file is on disk. For a picked file the item is the source
  /// itself; otherwise its path is under the source.
  String absolutePath(ReleaseItem item) =>
      item.path == p.basename(source) ? source : p.join(source, item.path);

  /// Records that the app changed something in the release. The timestamp is
  /// UTC, the same as the tool log entries.
  void markEdited() => lastEditDate = DateTime.now().toUtc();

  Map<String, Object> toJson() => {
    'schema': schemaVersion,
    if (createdDate != null) 'createdDate': createdDate!.toIso8601String(),
    if (lastEditDate != null) 'lastEditDate': lastEditDate!.toIso8601String(),
    'tracker': tracker.name,
    'releaseType': releaseType.name,
    'source': source,
    'fields': fields.toJson(),
    'items': [for (final item in items) item.toJson()],
    'includeAppSignature': includeAppSignature,
    // Only a type that can choose writes it, so a release of another type does
    // not carry a shape it could never use.
    if (releaseType == ReleaseType.videoPack)
      'screenshotLayout': screenshotLayout.name,
  };
}

/// One file the release is made of: a video, a directory of images, or an
/// archive.
class ReleaseItem {
  ReleaseItem({required this.path, required this.type, required this.fields});

  /// The path relative to `Release.source`. It is the ID the image records link
  /// to, so it is not generated from anything: renaming the file changes it,
  /// and with it the records that point at this item.
  String path;

  final String type;

  /// The fields that belong to this item. For a Single video release the values
  /// are the release's own, so this is empty; the field list decides which
  /// level a value lives at (`ai/release_structure.md` §3).
  final FieldValues fields;

  Map<String, Object> toJson() => {
    'path': path,
    'type': type,
    'fields': fields.toJson(),
  };

  static ReleaseItem fromJson(Map<String, dynamic> json) => ReleaseItem(
    path: json['path'] is String ? json['path'] as String : '',
    type: json['type'] is String ? json['type'] as String : '',
    fields: json['fields'] is Map<String, dynamic>
        ? FieldValues.fromJson(json['fields'] as Map<String, dynamic>)
        : FieldValues(),
  );
}
