import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../service/images/image_dimensions.dart';
import '../../service/native_tools/ffmpeg.dart';
import '../../service/photosets/photoset_picker.dart';
import '../../service/photosets/photoset_scanner.dart';
import '../release/release.dart';
import '../release/release_fields.dart';
import '../release/release_store.dart';
import '../release/release_type.dart';
import '../screenshots/images.dart';
import '../screenshots/images_store.dart';
import '../tab/tab_manager.dart';

/// Photoset state and side effects (`ai/photoset_pack.md` §4). It owns no
/// `Listenable` (rule 3) and shows no messages (rule 13): the widget calls
/// `scan()`, shows what came back, and maps a result to localized text. It
/// reports what a run has done through a plain callback the widget passes in, as
/// the Upload and Screenshots controllers do, so a set is shown as it is read
/// rather than when the run ends.
///
/// It writes the items, because an item is what the scan produces — the same
/// kind of write as the source the editor records, and the user cannot add an
/// item that is not on disk. The values it counts are field values, so they are
/// not written here: the widget hands them to the editor's single write path,
/// as the Stash section does. The item-level values are written here because
/// they belong to the item being created, and there is no form row for them
/// yet.
///
/// The work it asks the scanner to do runs on another isolate, so reading a
/// large archive does not hold up the UI isolate (`ai/photoset_pack.md` §4).
/// That is why the run reports as it goes: the report is what lets the widget
/// build between two sets.
///
/// For a pack the run also writes a preview thumbnail next to each photo it
/// copies (`ai/picking.md` §8). That is the only place those files come from,
/// and nothing is recorded for them, so the path is derived here, from the
/// photo's record.
class PhotosetController {
  PhotosetController({
    required this.release,
    required this.scanner,
    required this.ffmpeg,
    required this.store,
    required this.releaseStore,
    required this.tabManager,
    required this.tabId,
  });

  final Release release;
  final PhotosetScanner scanner;

  /// The tool the run writes a preview thumbnail with. Only the pack's run asks
  /// for one, and a call that cannot run is not reported: the photo the tile
  /// shows is the one the run wrote, whatever the thumbnail did.
  final Ffmpeg ffmpeg;

  final ImagesStore store;

  /// `release.json`, for the last-edit stamp a pick writes. The scan changes no
  /// files, so it stamps nothing: opening a release is a read.
  final ReleaseStore releaseStore;

  final TabManager tabManager;
  final String tabId;

  /// The largest side a preview thumbnail is written at (`ai/picking.md` §8).
  static const thumbnailMaxSize = 800;

  /// The prefix a thumbnail's name has. The file is in the same folder as the
  /// photo it is a copy of, and nothing is recorded for it: a thumbnail is not
  /// an image the post uses, and the Upload section sends records, so there is
  /// nothing for it to send. This is the same shape as the video thumbnail's
  /// `_rp_thumbnail.jpg` (`ai/doc.md` §2).
  static const thumbnailPrefix = '_rp_thumb_';

  /// The name a photo's thumbnail is written under. The photo's own name is
  /// kept as it is, so two photos in one set cannot reach the same thumbnail
  /// name; the extension is the JPEG one the tool writes, and it is not added
  /// to a name that is already a JPEG, so `001.jpg` gives `_rp_thumb_001.jpg`
  /// and `001.png` gives `_rp_thumb_001.png.jpg` (`ai/picking.md` §8).
  static String thumbnailFileName(String name) {
    final extension = p.extension(name).toLowerCase();

    if (extension == '.jpg' || extension == '.jpeg') {
      return '$thumbnailPrefix$name';
    }

    return '$thumbnailPrefix$name.jpg';
  }

  /// Whether a run writes a thumbnail for a photo (`ai/picking.md` §8). Only
  /// the pack has them, for now. A photo already within the cap is not written,
  /// because the tool would write the same picture again and the only thing
  /// gained is a process. A photo whose header could not be read has no
  /// dimensions, so the rule cannot know it is within the cap and writes one:
  /// the rule skips what it can know, never what it guesses.
  bool writesThumbnail(ImageDimensions? dimensions) =>
      release.releaseType == ReleaseType.photosetPack &&
      (dimensions == null ||
          math.max(dimensions.width, dimensions.height) > thumbnailMaxSize);

  /// A photo's thumbnail, as an absolute path, derived from the photo. Nothing
  /// is stored for it, as nothing is stored for the video thumbnail.
  String thumbnailPath(String photoAbsolutePath) => p.join(
    p.dirname(photoAbsolutePath),
    thumbnailFileName(p.basename(photoAbsolutePath)),
  );

  /// The same path when its file is on disk, otherwise null. The tile shows the
  /// photo for a photo whose thumbnail is not there, for the same reason the
  /// image boxes show only a file that exists: a tile built for a thumbnail the
  /// tool has not written stays empty for that path, whatever the tool writes
  /// later.
  String? thumbnailOnDisk(String photoAbsolutePath) {
    final path = thumbnailPath(photoAbsolutePath);

    return File(path).existsSync() ? path : null;
  }

  /// Reads the source and records what it finds. A re-scan replaces the items,
  /// because the scan is what says what the source contains; the image records
  /// that point at an item whose path changes are lost with it, which is the
  /// same rule as a rename losing a record (`ai/release_structure.md` §4).
  ///
  /// Each set is recorded as the scan reads it, so the caller can show a set
  /// before the run ends (`ai/photoset_pack.md` §4). The items are replaced at
  /// the point the scan has decided what the source contains — the report that
  /// only gives the total — so a scan that cannot read the folder replaces
  /// nothing.
  Future<PhotosetResult> scan({
    required void Function(ScanProgress progress) onProgress,
  }) async {
    if (release.source.trim().isEmpty) {
      return const PhotosetFailure(PhotosetFailureKind.sourceEmpty);
    }

    final fieldList = fieldListFor(release.releaseType);

    final result = await scanner.scan(
      release.source,
      fieldList.itemBoundary,
      onProgress: (progress) {
        if (progress.set == null) {
          release.items.clear();
        } else {
          _recordItem(fieldList, progress.set!);
        }

        onProgress(progress);
      },
    );

    if (result is ScanFailure) {
      return PhotosetFailure(switch (result.kind) {
        ScanFailureKind.sourceNotFound => PhotosetFailureKind.sourceNotFound,
        ScanFailureKind.sourceNotReadable =>
          PhotosetFailureKind.sourceNotReadable,
      });
    }

    final success = result as ScanSuccess;

    // The write path is the editor's, so the values are returned rather than
    // written. Marking the tab dirty here is for the items; the values mark it
    // through that path.
    tabManager.setUnsavedChanges(tabId, true);

    // What the scan counted, kept to the names this type has: a count that is
    // always the same for a type is not a field, and a name the type does not
    // have is not written (`ai/single_photoset.md` §3).
    final counted = {
      'photosetCount': '${success.sets.length}',
      'totalPhotoCount': '${success.totalPhotoCount}',
      'totalSize': '${success.totalSize}',
      'imageFormats': success.imageFormats.join(', '),
      if (success.minResolution != null)
        'minResolution': success.minResolution!.value,
      if (success.maxResolution != null)
        'maxResolution': success.maxResolution!.value,
    };

    return PhotosetSuccess(
      values: {
        for (final entry in counted.entries)
          if (fieldList.hasField(entry.key)) entry.key: entry.value,
      },
      skipped: success.skipped,
      unreadPhotos: success.unreadPhotos,
      nameCollisions: success.nameCollisions,
      scan: success,
    );
  }

  /// One item, as the scan read it. An item is what the scan produces, so this
  /// is the controller's write, not the editor's.
  void _recordItem(FieldList fieldList, ScannedSet set) {
    final item = ReleaseItem(
      path: set.path,
      type: fieldList.itemType,
      fields: FieldValues(),
    );

    for (final field in fieldList.itemFields) {
      item.fields.setValue(field.name, '${set.photoCount}');
    }

    release.items.add(item);
  }

  /// Copies the photos the rule picked into the release and records them
  /// (`ai/picking.md` §7). The rule is pure and lives in the service; this is
  /// the part that writes. The scan result is passed in, not held here, as the
  /// count is passed to the screenshots controller, and the options the popup
  /// decided are passed in too: the popup owns them as widget state, and the
  /// controller runs the rule with what it chose.
  ///
  /// For a pack the run writes a preview thumbnail beside each photo it copies
  /// (`ai/picking.md` §8). It is not recorded, so nothing here returns it: the
  /// file is the photo's, and its path is derived from the record. A thumbnail
  /// that could not be written is not reported — the photo it is a copy of is
  /// on disk and the tile shows that, so a missing thumbnail is not a failure
  /// the user is told about.
  ///
  /// A run replaces the photo records it writes, so the poster and the records
  /// of other kinds are kept, the same way a generation run keeps them. With no
  /// override the rule is deterministic, so a second run writes the same photos
  /// again.
  ///
  /// The number the run reports against is what the rule chose, so it is known
  /// before anything is copied, and each photo is reported as it is written so
  /// the caller can show it before the run ends. The manifest is still written
  /// once, at the end, for the whole run.
  Future<PhotosetPickResult> pick(
    ScanSuccess scan,
    PickOptions options, {
    required void Function(CopyProgress progress) onProgress,
  }) async {
    final picked = PhotosetPicker.pick(scan.sets, options);

    final total = [for (final pick in picked.picks) pick.photos.length]
        .fold(0, (sum, count) => sum + count);

    final kept = [
      for (final record in (await store.load(release.directoryPath)).images)
        if (record.kind != ImageKind.photo) record,
    ];

    final written = <ImageRecord>[];
    final notCopied = <String>[];

    // The total is what the first report says, before anything has been copied.
    onProgress(CopyProgress(done: 0, total: total));

    for (final pick in picked.picks) {
      for (final photo in pick.photos) {
        final name = '${pick.set.path}/${photo.name}';
        final bytes = await scanner.photoBytes(pick.set, photo);

        if (bytes.isEmpty) {
          notCopied.add(name);
          continue;
        }

        // The release folder mirrors the structure the user picked for the
        // images that are copied into it, so the folder carries the display
        // name (`ai/release_structure.md` §4). The record path is relative to
        // the release directory with `/` separators, because that path is the
        // record ID.
        final relative = '${displayName(pick.set.path)}/${photo.name}';

        try {
          final target = File(p.join(release.directoryPath, relative));
          await target.parent.create(recursive: true);
          await target.writeAsBytes(bytes, flush: true);

          final record = ImageRecord(
            item: pick.set.path,
            kind: ImageKind.photo,
            file: relative,
            urls: const {},
          );

          // The thumbnail is written before the photo is reported, so the tile
          // built for it as the run goes shows the thumbnail rather than the
          // full file. The result is not kept: nothing the user is told depends
          // on it. A call that could not run leaves no file, and the tile falls
          // back to the photo (`ai/picking.md` §8).
          if (writesThumbnail(photo.dimensions)) {
            await ffmpeg.resizeImage(
              releaseDirectory: release.directoryPath,
              inputPath: target.path,
              outputPath: thumbnailPath(absolutePath(record)),
              maxSize: thumbnailMaxSize,
            );
          }

          written.add(record);

          onProgress(
            CopyProgress(done: written.length, total: total, record: record),
          );
        } catch (_) {
          // A photo that could not be written is reported, not guessed at.
          notCopied.add(name);
        }
      }
    }

    try {
      await store.save(
        release.directoryPath,
        ImagesManifest(images: [...kept, ...written]),
      );
    } catch (_) {
      // The files are on disk and the manifest is not. The next run writes it,
      // as a generation run does when the save fails.
    }

    // The run copied files into the release, so the release changed. Only the
    // timestamp is written, because the values the user has not saved are not
    // this run's to write.
    if (written.isNotEmpty) {
      await releaseStore.touchLastEdit(release);
    }

    // The write path is the editor's for the fields; the records and the files
    // are written here, so the tab is marked dirty here.
    tabManager.setUnsavedChanges(tabId, true);

    return PhotosetPickResult(
      written: written,
      notCopied: notCopied,
      emptySets: [
        for (final pick in picked.picks)
          if (pick.set.photoCount == 0) pick.set.path,
      ],
    );
  }

  /// The photosets the release has, in the order the scan wrote them.
  List<ReleaseItem> photosets() {
    final fieldList = fieldListFor(release.releaseType);

    return [
      for (final item in release.items)
        if (item.type == fieldList.itemType) item,
    ];
  }

  /// The picked photos of one set, in the order `images.json` lists them, as
  /// absolute paths. The section shows an image only for a file that is there,
  /// for the same reason the Screenshots section does (`ai/picking.md` §7).
  ///
  /// The manifest is given rather than read here, because the widget builds the
  /// list of sets in one pass and a run rebuilds that pass for every set it has
  /// already read: reading the file once per set is one parse per row per
  /// rebuild.
  List<String> pickedPhotos(ImagesManifest manifest, String itemPath) => [
    for (final record in manifest.of(ImageKind.photo))
      if (record.item == itemPath && File(absolutePath(record)).existsSync())
        absolutePath(record),
  ];

  /// A record's file path resolved against the release directory. The manifest
  /// stores it relative, so the widget needs this to show the image.
  String absolutePath(ImageRecord record) =>
      p.join(release.directoryPath, record.file);

  /// The ratio a tile is laid out at, read from the header of the file the
  /// section shows. Null for a photo whose header cannot be read, which the
  /// grid lays out as a square (`ai/picking.md` §7).
  double? aspectRatio(String absolutePath) {
    final dimensions = readImageDimensionsSync(absolutePath);

    if (dimensions == null || dimensions.height == 0) {
      return null;
    }

    return dimensions.width / dimensions.height;
  }

  /// The name a photoset is shown by: its path without the extension. It is
  /// derived here and not stored, because the stored path is the ID the image
  /// records link to and `set01.zip` and `set01/` would collide on it
  /// (`ai/photoset_pack.md` §2). It is also the folder the copied photos go in,
  /// because the release folder mirrors the structure the user picked.
  String displayName(String path) => p.basenameWithoutExtension(path);
}

enum PhotosetFailureKind {
  /// No folder has been picked.
  sourceEmpty,

  /// The picked folder is not there.
  sourceNotFound,

  /// The picked folder is there but could not be read.
  sourceNotReadable,
}

sealed class PhotosetResult {
  const PhotosetResult({
    this.values = const {},
    this.skipped = const [],
    this.unreadPhotos = const [],
    this.nameCollisions = const {},
  });

  /// The values the scan counted, keyed by the field names of the type's field
  /// list. The widget writes them through the editor's single write path. A
  /// result that did not count anything has none, so the widget writes nothing.
  final Map<String, String> values;

  /// Top-level entries that are not photosets, the photos whose header could
  /// not be read, and the display names more than one item would share. All
  /// three are reported, not guessed at (`ai/photoset_pack.md` §4).
  final List<String> skipped;
  final List<String> unreadPhotos;

  /// A display name and the item paths that would show under it.
  final Map<String, List<String>> nameCollisions;
}

final class PhotosetSuccess extends PhotosetResult {
  const PhotosetSuccess({
    required super.values,
    required super.skipped,
    required super.unreadPhotos,
    required super.nameCollisions,
    required this.scan,
  });

  /// What the scan read, kept by the widget so the pick can be asked for the
  /// same photos. The pick needs the photo names, and the names are what the
  /// scan read, so a fresh start cannot pick until the user scans again
  /// (`ai/picking.md` §7).
  final ScanSuccess scan;
}

final class PhotosetFailure extends PhotosetResult {
  const PhotosetFailure(
    this.kind, {
    super.values = const {},
    super.skipped = const [],
    super.unreadPhotos = const [],
    super.nameCollisions = const {},
  });

  final PhotosetFailureKind kind;
}

/// What a pick wrote: the records it wrote, the photos it could not copy, and
/// the sets with no photos. All three are reported rather than guessed at
/// (`ai/picking.md` §2).
class PhotosetPickResult {
  const PhotosetPickResult({
    required this.written,
    required this.notCopied,
    required this.emptySets,
  });

  /// The records this run wrote, in the order the source gives them. The widget
  /// evicts the cache for these before it builds again, as the Screenshots
  /// section does.
  final List<ImageRecord> written;

  /// The photos the rule picked that could not be read or written.
  final List<String> notCopied;

  /// The sets with no photos. They contribute nothing to the pick, so they are
  /// reported.
  final List<String> emptySets;
}

/// What a run that copies files reports while it works: the photos copied over
/// the photos it decided to copy — the ones the picking rule chose, or the ones
/// the scan counted for the type that copies all of them. A photo that could not
/// be read or written does not move [done], so the count is what was copied, the
/// same rule the Upload section's bars follow (`ai/upload_images.md`).
///
/// [record] is the record this run has just written, so the widget can show the
/// photo as it is written; the report at the start of a run has none, because it
/// only gives the total the run will reach. This is shared by the two features
/// that copy files into a release, so one shape reports both.
class CopyProgress {
  const CopyProgress({required this.done, required this.total, this.record});

  final int done;
  final int total;

  final ImageRecord? record;
}
