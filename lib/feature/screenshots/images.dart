import '../../service/videos/image_generator.dart';

import '../release/release.dart';

/// The role an image has in the post (`ai/release_structure.md` §4). It is the
/// role, not the provenance: a record does not say whether the app generated
/// the file or the user copied it, because that is a property of the producer.
/// `kind` is what decides whether an image can be regenerated — a screenshot
/// can, a copied photo cannot.
enum ImageKind { poster, photo, screenshot, screenlist }

/// The kinds a generation run writes, so a run that regenerates replaces only
/// these: the poster and a copied photo are not a run's to replace.
const generatedImageKinds = {ImageKind.screenshot, ImageKind.screenlist};

/// The kind a file the run wrote becomes in `images.json`, from what the run
/// says it wrote it as. The service names the two things it can write and the
/// record's kind is the feature's, so this is the one place the two
/// vocabularies meet.
ImageKind imageKindFor(GeneratedImageKind kind) => switch (kind) {
  GeneratedImageKind.screenshot => ImageKind.screenshot,
  GeneratedImageKind.screenlist => ImageKind.screenlist,
};

/// One image tracked in `images.json` (`ai/doc.md` §2,
/// `ai/upload_images.md`), so its photo-hosting links can be recorded later.
class ImageRecord {
  const ImageRecord({
    required this.item,
    required this.kind,
    required this.file,
    required this.urls,
  });

  /// The item this image belongs to, as its path in `release.json`. Null for an
  /// image that belongs to the release rather than to an item — the poster,
  /// which both a single video post and a pack post use.
  final String? item;

  final ImageKind kind;

  /// The image path relative to the release directory, with `/` separators, so
  /// the manifest stays valid if the release folder is moved. It is the record
  /// ID: there is no generated id field, and a rename loses the record.
  final String file;

  /// The photo-hosting links, per hoster, per URL type (`ai/upload_images.md`).
  /// The URL types are the names the tool reports. Only successful uploads are
  /// stored, so a hoster with no entry here is one the image has not been
  /// uploaded to.
  ///
  /// Mutable: the Upload section fills it as hosters finish, and several
  /// hosters write to the same record at the same time.
  final Map<String, Map<String, String>> urls;

  Map<String, Object?> toJson() => {
    'item': item,
    'kind': kind.name,
    'file': file,
    'urls': urls,
  };

  /// A record is read as null when its `kind` is not one this version knows, so
  /// a manifest written by a later version still reads and the unknown record
  /// is dropped rather than guessed at.
  static ImageRecord? fromJson(Map<String, dynamic> json) {
    ImageKind? kind;

    for (final value in ImageKind.values) {
      if (value.name == json['kind']) {
        kind = value;
        break;
      }
    }

    if (kind == null) {
      return null;
    }

    return ImageRecord(
      item: json['item'] is String ? json['item'] as String : null,
      kind: kind,
      file: json['file'] is String ? json['file'] as String : '',
      urls: _urls(json['urls']),
    );
  }

  static Map<String, Map<String, String>> _urls(Object? value) =>
      value is Map<String, dynamic>
      ? {
          for (final hoster in value.entries)
            if (hoster.value is Map<String, dynamic>)
              hoster.key: {
                for (final url
                    in (hoster.value as Map<String, dynamic>).entries)
                  if (url.value is String) url.key: url.value as String,
              },
        }
      : {};
}

/// The contents of `images.json`: one flat list of records, in the order the
/// file lists them. Order is data — for copied images it is the order the
/// source gives, for generated images the generation order, and for posters the
/// priority, where the first poster record is the primary one
/// (`ai/release_structure.md` §4).
///
/// There is no key per kind, so a new kind is a value rather than a format
/// change.
class ImagesManifest {
  const ImagesManifest({required this.images});

  const ImagesManifest.empty() : images = const [];

  final List<ImageRecord> images;

  /// The records of one kind, in the order the file lists them.
  List<ImageRecord> of(ImageKind kind) => [
    for (final record in images)
      if (record.kind == kind) record,
  ];

  /// The primary poster: the first poster record, which is the one whose
  /// `item` is null (`ai/release_structure.md` §4). Null when there is no
  /// poster. The rule is the manifest's, because order is data, so the editor
  /// and the clone feature read it through this rather than each keeping its
  /// own copy.
  ImageRecord? primaryPoster() {
    for (final record in of(ImageKind.poster)) {
      if (record.item == null) {
        return record;
      }
    }

    return null;
  }

  /// The records a run keeps when it regenerates: everything that is not its
  /// own — an image of an item it did not run for, or a kind it does not write,
  /// such as the poster or a copied photo. Regenerating replaces only what it
  /// writes.
  ImagesManifest excluding(Set<String> items, Set<ImageKind> kinds) =>
      ImagesManifest(
        images: [
          for (final record in images)
            if (!items.contains(record.item) || !kinds.contains(record.kind))
              record,
        ],
      );

  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'images': [for (final record in images) record.toJson()],
  };

  static ImagesManifest fromJson(Map<String, dynamic> json) {
    final records = <ImageRecord>[];

    if (json['images'] is List) {
      for (final entry in json['images'] as List) {
        if (entry is Map<String, dynamic>) {
          final record = ImageRecord.fromJson(entry);

          if (record != null) {
            records.add(record);
          }
        }
      }
    }

    return ImagesManifest(images: records);
  }
}
