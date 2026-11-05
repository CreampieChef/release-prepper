import 'dart:io';

import 'package:path/path.dart' as p;

import '../../service/native_tools/media_info.dart';
import '../../service/videos/image_generator.dart';
import '../../service/videos/video_scanner.dart';
import '../release/release.dart';
import '../release/release_fields.dart';
import '../release/release_store.dart';
import '../screenshots/images.dart';
import '../screenshots/images_store.dart';
import '../tab/tab_manager.dart';

/// Video pack state and side effects (`ai/video_pack.md` §4, §5). It owns no
/// `Listenable` (rule 3) and shows no messages (rule 13): the widget calls
/// `scan()`, shows what came back, and maps a result to localized text.
///
/// It writes the items, because an item is what the scan produces — the same
/// kind of write as the source the editor records, and the user cannot add an
/// item that is not on disk. The values it counts are field values, so they are
/// not written here: the widget hands them to the editor's single write path.
/// The item-level values are written here, because they belong to the item the
/// scan produced.
///
/// Nothing is copied: videos are never copied into the release
/// (`ai/video_pack.md` §2). What this controller does write is `images.json`,
/// for the images the generation writes on disk — the same store the Single
/// video section uses, because a record is the same shape for both.
class VideoPackController {
  VideoPackController({
    required this.release,
    required this.scanner,
    required this.generator,
    required this.store,
    required this.releaseStore,
    required this.tabManager,
    required this.tabId,
  });

  final Release release;
  final VideoScanner scanner;
  final ImageGenerator generator;
  final ImagesStore store;
  final ReleaseStore releaseStore;
  final TabManager tabManager;
  final String tabId;

  /// Reads the source and records what it finds. A re-scan replaces the items,
  /// because the scan is what says what the source contains, and the aggregates
  /// are recomputed from what it finds rather than from the values a user may
  /// have corrected (`ai/video_pack.md` §4).
  Future<VideoPackResult> scan() async {
    if (release.source.trim().isEmpty) {
      return const VideoPackFailure(VideoPackFailureKind.sourceEmpty);
    }

    final result = await scanner.scan(
      sourcePath: release.source,
      releaseDirectory: release.directoryPath,
    );

    if (result is VideoScanFailure) {
      return VideoPackFailure(switch (result.kind) {
        VideoScanFailureKind.sourceNotFound =>
          VideoPackFailureKind.sourceNotFound,
        VideoScanFailureKind.sourceNotReadable =>
          VideoPackFailureKind.sourceNotReadable,
      });
    }

    final success = result as VideoScanSuccess;
    final fieldList = fieldListFor(release.releaseType);

    release.items.clear();

    for (final video in success.videos) {
      final item = ReleaseItem(
        path: video.path,
        type: fieldList.itemType,
        fields: FieldValues(),
      );

      final info = video.info;

      if (info != null) {
        for (final field in fieldList.itemFields) {
          item.fields.setValue(field.name, _probeValue(field.name, info));
        }
      }

      release.items.add(item);
    }

    // The write path is the editor's for the aggregates; the items are written
    // here, so the tab is marked dirty here.
    tabManager.setUnsavedChanges(tabId, true);

    return VideoPackSuccess(
      values: {
        'totalSize': '${success.totalSize}',
        'videoCount': '${success.videoCount}',
        'videoResolutions': success.resolutions.join(', '),
        'videoFormats': success.formats.join(', '),
      },
      skipped: success.skipped,
      unprobed: success.unprobed,
      emptyFolders: success.emptyFolders,
      unreadable: success.unreadable,
    );
  }

  /// The videos the release has, in the order the scan wrote them. The section
  /// shows these, because they are what the release stores: a release opened
  /// from a manifest shows what it recorded, not only what the last scan
  /// produced.
  List<ReleaseItem> videos() {
    final fieldList = fieldListFor(release.releaseType);

    return [
      for (final item in release.items)
        if (item.type == fieldList.itemType) item,
    ];
  }

  /// The tracked images of one item whose files are on disk, in the order
  /// `images.json` lists them. The table's two flag columns read this, so the
  /// same rule decides what a column shows and what the Single video section
  /// shows: a record whose file is not there says nothing the app can show.
  List<ImageRecord> imagesFor(ReleaseItem item) => [
    for (final record in store.loadSync(release.directoryPath).images)
      if (record.item == item.path && File(absolutePath(record)).existsSync())
        record,
  ];

  String absolutePath(ImageRecord record) =>
      p.join(release.directoryPath, record.file);

  /// Generates the images for every item, in the order the scan recorded them,
  /// and records what the run wrote in `images.json` once for the whole run: a
  /// pack is tens of items, and writing the file once per item would be tens of
  /// writes for one action the user asked for once.
  ///
  /// [onRecord] is called for each record as its file is written, so the
  /// section can show a frame before the run ends. The records it reports are
  /// the same records the manifest holds at the end of the run, in the same
  /// order, so the section shows one set and not two.
  ///
  /// A tool that is not available stops the run, because it does not become
  /// installed while the app is open; a file that failed does not stop the next
  /// one, as one file does not fail the scan.
  Future<VideoPackImagesResult> generateImages(
    int count,
    void Function(ImageRecord record) onRecord,
  ) async {
    final items = videos();
    final runs = <ImageGenerationResult>[];
    final written = <ImageRecord>[];

    for (final item in items) {
      final run = await generator.generate(
        releaseDirectory: release.directoryPath,
        itemPath: item.path,
        videoPath: release.absolutePath(item),
        count: count,
        onWritten: (file) {
          // A service reports files; a record is a file plus the item it
          // belongs to, so this is where the file becomes a record.
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

      runs.add(run);

      if (run.failure != null && run.failure!.stopsRun) {
        break;
      }
    }

    ImageGenerationFailureKind? failure;

    try {
      await store.save(
        release.directoryPath,
        ImagesManifest(
          images: [
            ...store.loadSync(release.directoryPath).excluding({
              for (final run in runs) run.item,
            }, generatedImageKinds).images,
            ...written,
          ],
        ),
      );
    } catch (_) {
      failure = ImageGenerationFailureKind.manifestFailed;
    }

    // The run wrote files, so the release changed. Only the timestamp is
    // written, because the field values the user has not saved are not this
    // run's to write.
    if (written.isNotEmpty) {
      await releaseStore.touchLastEdit(release);
    }

    return VideoPackImagesResult(
      runs: runs,
      written: written,
      failure: failure,
    );
  }

  /// The value one item field gets from a probe. A name the probe does not
  /// report is written as an empty value rather than guessed at, which is what
  /// a file that could not be probed gets.
  String _probeValue(String name, MediaInfo info) => switch (name) {
    'fileSize' => info.fileSize,
    'duration' => info.duration,
    'videoType' => info.videoType,
    'videoFormat' => info.videoFormat,
    'videoStream' => info.videoStream,
    'audioStream' => info.audioStream,
    _ => '',
  };
}

enum VideoPackFailureKind {
  /// No folder has been picked.
  sourceEmpty,

  /// The picked folder is not there.
  sourceNotFound,

  /// The picked folder itself could not be read. A folder inside it is reported
  /// by the scan instead of failing it, so this is only the source.
  sourceNotReadable,
}

sealed class VideoPackResult {
  const VideoPackResult();
}

final class VideoPackSuccess extends VideoPackResult {
  const VideoPackSuccess({
    required this.values,
    required this.skipped,
    required this.unprobed,
    required this.emptyFolders,
    required this.unreadable,
  });

  /// The values the scan counted, keyed by the field names of the type's field
  /// list. The widget writes them through the editor's single write path.
  final Map<String, String> values;

  /// Files the extension list does not accept, the videos the probe could not
  /// read, the subfolders with no video in them, and the folders the walk could
  /// not read. All four are reported, not guessed at (`ai/video_pack.md` §4).
  /// The counts in `values` do not include what the walk could not read, so
  /// they are known to be incomplete when this list is not empty.
  final List<String> skipped;
  final List<String> unprobed;
  final List<String> emptyFolders;
  final List<String> unreadable;
}

final class VideoPackFailure extends VideoPackResult {
  const VideoPackFailure(this.kind);

  final VideoPackFailureKind kind;
}

/// What a generation run did. One entry per item the run reached, in the order
/// it walked them, so the section can say which files it could not do;
/// `failure` is what the run itself failed at — the manifest write, which is
/// not one item's.
final class VideoPackImagesResult {
  const VideoPackImagesResult({
    required this.runs,
    required this.written,
    this.failure,
  });

  final List<ImageGenerationResult> runs;

  /// The images this run wrote, in the order they were written. The widget
  /// evicts the cache for these before it builds again, and shows them even
  /// when the run did not finish.
  final List<ImageRecord> written;

  final ImageGenerationFailureKind? failure;
}
