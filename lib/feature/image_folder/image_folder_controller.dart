import 'dart:io';

import 'package:path/path.dart' as p;

import '../../service/images/image_dimensions.dart';
import '../../service/photosets/photoset_scanner.dart';
import '../release/release.dart';
import '../release/release_fields.dart';
import '../release/release_store.dart';
import '../screenshots/images.dart';
import '../screenshots/images_store.dart';
import '../tab/tab_manager.dart';

/// Image folder state and side effects (`ai/image_folder_upload.md`). It owns
/// no `Listenable` (rule 3) and shows no messages (rule 13): the widget calls
/// `scan()`, shows what came back, and maps a result to localized text.
///
/// One action rather than the Photoset section's two, because for this type the
/// scan and the copy are the same thing: what the rule copies is every image in
/// the folder, so there is nothing left to choose after the scan. The images
/// are copied into the release rather than uploaded from where they were
/// picked, because a record path is relative to the release directory and the
/// Upload section resolves it there — a record pointing at the picked folder
/// could not be uploaded (`ai/upload_images.md`) — and the release folder
/// mirrors the structure the user picked (`ai/release_structure.md` §4).
class ImageFolderController {
  ImageFolderController({
    required this.release,
    required this.scanner,
    required this.store,
    required this.releaseStore,
    required this.tabManager,
    required this.tabId,
  });

  final Release release;
  final PhotosetScanner scanner;
  final ImagesStore store;

  /// `release.json`, for the last-edit stamp a run writes. The scan changes no
  /// files until it copies, so opening a release is a read
  /// (`ai/release_structure.md` §4).
  final ReleaseStore releaseStore;

  final TabManager tabManager;
  final String tabId;

  /// Reads the picked folder, records the one item it is, and copies every
  /// image in it into the release in filename order. A re-scan replaces the
  /// item, because the scan is what says what the folder contains, and replaces
  /// the photo records this run writes, so the poster and the records of other
  /// kinds are kept — the same rules as the photoset scan and pick.
  Future<ImageFolderResult> scan() async {
    if (release.source.trim().isEmpty) {
      return const ImageFolderFailure(ImageFolderFailureKind.sourceEmpty);
    }

    final fieldList = fieldListFor(release.releaseType);
    final result = await scanner.scan(release.source, fieldList.itemBoundary);

    if (result is ScanFailure) {
      return ImageFolderFailure(switch (result.kind) {
        ScanFailureKind.sourceNotFound => ImageFolderFailureKind.sourceNotFound,
        ScanFailureKind.sourceNotReadable =>
          ImageFolderFailureKind.sourceNotReadable,
      });
    }

    final success = result as ScanSuccess;

    // The item is the picked folder, named by it, as a single photoset names
    // its item (`ai/single_photoset.md` §5). There is exactly one, because the
    // folder is the item.
    release.items.clear();

    for (final set in success.sets) {
      release.items.add(
        ReleaseItem(
          path: set.path,
          type: fieldList.itemType,
          fields: FieldValues(),
        ),
      );
    }

    final kept = [
      for (final record in (await store.load(release.directoryPath)).images)
        if (record.kind != ImageKind.photo) record,
    ];

    final written = <ImageRecord>[];
    final notCopied = <String>[];

    for (final set in success.sets) {
      for (final photo in set.photos) {
        final bytes = await scanner.photoBytes(set, photo);

        if (bytes.isEmpty) {
          notCopied.add(photo.name);
          continue;
        }

        // The item path is the picked folder's name, so the mirror is that
        // folder under the release directory. The record path is relative to
        // the release directory with `/` separators, because that path is the
        // record ID.
        final relative = '${set.path}/${photo.name}';

        try {
          final target = File(p.join(release.directoryPath, relative));
          await target.parent.create(recursive: true);
          await target.writeAsBytes(bytes, flush: true);

          written.add(
            ImageRecord(
              item: set.path,
              kind: ImageKind.photo,
              file: relative,
              urls: const {},
            ),
          );
        } catch (_) {
          // An image that could not be written is reported, not guessed at.
          notCopied.add(photo.name);
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
      // as a photoset pick does when the save fails.
    }

    // The run copied files into the release, so the release changed. Only the
    // timestamp is written, because the values the user has not saved are not
    // this run's to write.
    if (written.isNotEmpty) {
      await releaseStore.touchLastEdit(release);
    }

    // The write path for the fields is the editor's, so the values are returned
    // rather than written. Marking the tab dirty here is for the item and the
    // records.
    tabManager.setUnsavedChanges(tabId, true);

    final counted = {
      'totalPhotoCount': '${success.totalPhotoCount}',
      'imageFormats': success.imageFormats.join(', '),
      if (success.minResolution != null)
        'minResolution': success.minResolution!.value,
      if (success.maxResolution != null)
        'maxResolution': success.maxResolution!.value,
    };

    return ImageFolderSuccess(
      values: {
        for (final entry in counted.entries)
          if (fieldList.hasField(entry.key)) entry.key: entry.value,
      },
      // The reader counts only the images and does not report what it skipped,
      // so the files it did not count are listed here, by the feature that
      // reports them (`ai/image_folder_upload.md` §3).
      notImages: await _notImages(release.source),
      unreadImages: [
        for (final set in success.sets)
          for (final photo in set.photos)
            if (photo.dimensions == null) photo.name,
      ],
      notCopied: notCopied,
      written: written,
    );
  }

  /// The files directly inside the picked folder that are not images, in
  /// filename order. The scan's rule for what an image is is the shared
  /// extension list, so this uses it rather than a rule of its own; a subfolder
  /// is not read, for the same reason the reader does not read one
  /// (`ai/photoset_pack.md` §9). A folder that cannot be listed reports
  /// nothing, because the scan already reports the folder.
  Future<List<String>> _notImages(String sourcePath) async {
    final names = <String>[];

    try {
      await for (final entity in Directory(sourcePath).list()) {
        if (entity is File && !isPhotoExtension(entity.path)) {
          names.add(p.basename(entity.path));
        }
      }
    } catch (_) {
      return const [];
    }

    return names..sort((a, b) => a.compareTo(b));
  }

  /// The images the release has, in the order the scan wrote them. There is one
  /// item, the folder.
  List<ReleaseItem> imageFolder() {
    final fieldList = fieldListFor(release.releaseType);

    return [
      for (final item in release.items)
        if (item.type == fieldList.itemType) item,
    ];
  }

  /// The tracked images of one item whose files are on disk, in the order
  /// `images.json` lists them — the same rule as the other sections
  /// (`ai/picking.md` §7). Only the photos this type writes are shown: the
  /// poster belongs to the release, not to the item.
  List<ImageRecord> imagesFor(ReleaseItem item) => [
    for (final record
        in store.loadSync(release.directoryPath).of(ImageKind.photo))
      if (record.item == item.path && File(absolutePath(record)).existsSync())
        record,
  ];

  /// A record's file path resolved against the release directory. The manifest
  /// stores it relative, so the widget needs this to show the image.
  String absolutePath(ImageRecord record) =>
      p.join(release.directoryPath, record.file);

  /// The ratio a tile is laid out at, read from the header of the file the
  /// section shows. Null for an image whose header cannot be read, which the
  /// grid lays out as a square (`ai/picking.md` §7).
  double? aspectRatio(String absolutePath) {
    final dimensions = readImageDimensionsSync(absolutePath);

    if (dimensions == null || dimensions.height == 0) {
      return null;
    }

    return dimensions.width / dimensions.height;
  }
}

enum ImageFolderFailureKind {
  /// No folder has been picked.
  sourceEmpty,

  /// The picked folder is not there.
  sourceNotFound,

  /// The picked folder is there but could not be read.
  sourceNotReadable,
}

sealed class ImageFolderResult {
  const ImageFolderResult();
}

final class ImageFolderSuccess extends ImageFolderResult {
  const ImageFolderSuccess({
    required this.values,
    required this.notImages,
    required this.unreadImages,
    required this.notCopied,
    required this.written,
  });

  /// The values the scan counted, keyed by the field names of the type's field
  /// list. The widget writes them through the editor's single write path. A run
  /// that counted nothing has none, so the widget writes nothing.
  final Map<String, String> values;

  /// The files in the picked folder that are not images, the images whose
  /// header could not be read, and the images that could not be copied. All
  /// three are reported, not guessed at.
  final List<String> notImages;
  final List<String> unreadImages;
  final List<String> notCopied;

  /// The records this run wrote, in filename order. The widget evicts the cache
  /// for these before it builds again, as the other sections do.
  final List<ImageRecord> written;
}

final class ImageFolderFailure extends ImageFolderResult {
  const ImageFolderFailure(this.kind);

  final ImageFolderFailureKind kind;
}
