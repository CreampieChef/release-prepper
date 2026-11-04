import 'dart:io';

import 'package:path/path.dart' as p;

import '../../service/images/image_dimensions.dart';
import '../../service/videos/image_generator.dart';
import '../release/release.dart';
import '../release/release_store.dart';
import 'images.dart';
import 'images_store.dart';

/// Screenshots state and side effects for one item
/// (`ai/doc.md` §2). It owns no `Listenable` (rule 3) and shows
/// no messages (rule 13): the widget owns the slider value and the layout,
/// calls `generate()`, and maps a result to localized text.
///
/// The generation rules — the key-frame times, the names, the rows, the tool
/// calls — are the service's. What is the feature's is the record and the
/// stamp, so that is what is here: a service reports files, and a record is a
/// file plus the item it belongs to.
class ScreenshotsController {
  ScreenshotsController({
    required this.release,
    required this.generator,
    required this.store,
    required this.releaseStore,
  });

  final Release release;
  final ImageGenerator generator;
  final ImagesStore store;
  final ReleaseStore releaseStore;

  /// The kinds a run writes. Regenerating replaces only these, for the item it
  /// ran for.
  static const writtenKinds = {ImageKind.screenshot, ImageKind.screenlist};

  /// The item the images are generated for. A Single video release has one
  /// item, the file the user picked. A pack has many, and its own controller
  /// generates for all of them (rule 2).
  ReleaseItem? singleItem() =>
      release.items.isEmpty ? null : release.items.first;

  /// The tracked images of one item whose files are on disk, in the order
  /// `images.json` lists them. A record whose file is not there says nothing
  /// the app can show, for the same reason the image boxes show only a file
  /// that exists.
  List<ImageRecord> imagesFor(ReleaseItem item) => [
    for (final record in store.loadSync(release.directoryPath).images)
      if (record.item == item.path && File(absolutePath(record)).existsSync())
        record,
  ];

  /// A record's file path resolved against the release directory. The manifest
  /// stores it relative, so the widget needs this to show the image.
  String absolutePath(ImageRecord record) =>
      p.join(release.directoryPath, record.file);

  /// The ratio a tile is laid out at, read from the header of the file the
  /// section shows. Null for a file whose header cannot be read, which the grid
  /// lays out as a square (`ai/picking.md` §7) — the same rule the photoset
  /// grid uses. A frame is not assumed to be 16:9: ffmpeg writes it at the
  /// source resolution, so the shape is whatever the file says.
  double? aspectRatio(String absolutePath) {
    final dimensions = readImageDimensionsSync(absolutePath);

    if (dimensions == null || dimensions.height == 0) {
      return null;
    }

    return dimensions.width / dimensions.height;
  }

  /// Generates [count] screenshots and the screenlist for [item], and records
  /// what the run wrote in `images.json`. A run that does not finish still
  /// records the files it wrote, so the section shows them: a screenlist that
  /// failed must not hide screenshots that succeeded. [onRecord] is called for
  /// each record as its file is written, so the section can show a frame before
  /// the run ends. The records it reports are the same records the manifest
  /// holds at the end of the run, in the same order, so the section shows one
  /// set and not two.
  Future<ScreenshotsResult> generate(
    ReleaseItem item,
    int count,
    void Function(ImageRecord record) onRecord,
  ) async {
    final written = <ImageRecord>[];

    final result = await generator.generate(
      releaseDirectory: release.directoryPath,
      itemPath: item.path,
      videoPath: release.absolutePath(item),
      count: count,
      onWritten: (file) {
        // A service reports files; a record is a file plus the item it belongs
        // to, so this is where the file becomes a record.
        final record = ImageRecord(
          item: file.item,
          kind: imageKindFor(file.kind),
          file: file.path,
          urls: const {},
        );

        written.add(record);
        onRecord(record);
      },
    );

    var failure = result.failure;

    try {
      await store.save(
        release.directoryPath,
        ImagesManifest(
          images: [
            ...store.loadSync(release.directoryPath).excluding({
              item.path,
            }, generatedImageKinds).images,
            ...written,
          ],
        ),
      );
    } catch (_) {
      failure ??= ImageGenerationFailureKind.manifestFailed;
    }

    // The run wrote files, so the release changed. Only the timestamp is
    // written, because the field values the user has not saved are not this
    // run's to write.
    if (written.isNotEmpty) {
      await releaseStore.touchLastEdit(release);
    }

    return ScreenshotsResult(written: written, failure: failure);
  }
}

/// What a run did: the records it wrote and what stopped it. A run that wrote
/// files and then failed reports both, because the files it wrote are on disk
/// and are shown.
final class ScreenshotsResult {
  const ScreenshotsResult({required this.written, this.failure});

  /// The images this run wrote, in the order they were written. The widget
  /// evicts the cache for these before it builds again, and shows them even
  /// when the run did not finish.
  final List<ImageRecord> written;

  final ImageGenerationFailureKind? failure;
}
