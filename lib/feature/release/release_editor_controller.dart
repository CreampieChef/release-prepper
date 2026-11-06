import 'dart:io';

import 'package:path/path.dart' as p;

import '../../feature/screenshots/images.dart';
import '../../feature/screenshots/images_store.dart';
import '../../service/native_tools/ffmpeg.dart';
import '../../service/native_tools/ffprobe.dart';
import '../../service/native_tools/tool_runner.dart';
import '../../service/network/image_downloader.dart';
import '../message/screenshot_layout.dart';
import '../tab/tab_manager.dart';
import 'release.dart';
import 'release_fields.dart';
import 'release_store.dart';

/// Editor state: the field values, the source path, the poster record, and the
/// dirty flag. It owns no `Listenable` (rule 3) — the widget binds its text
/// controllers to it and reports the tab state to `TabManager`, the only
/// listener in the app.
class ReleaseEditorController {
  ReleaseEditorController({
    required this.release,
    required this.store,
    required this.tabManager,
    required this.ffprobe,
    required this.ffmpeg,
    required this.downloader,
    required this.images,
    required this.tabId,
  });

  final Release release;
  final ReleaseStore store;
  final TabManager tabManager;
  final Ffprobe ffprobe;
  final Ffmpeg ffmpeg;
  final ImageDownloader downloader;

  /// `images.json`, for the poster record the Upload section needs.
  final ImagesStore images;

  final String tabId;

  /// The name the thumbnail is written under inside `images/`.
  static const thumbnailFileName = '_rp_thumbnail.jpg';

  /// The formats a poster may be.
  static const posterExtensions = {'jpg', 'jpeg', 'webp'};

  /// The schemes a pasted link must have.
  static const urlSchemes = {'http', 'https'};

  /// The poster is stored with neither dimension larger than 1200 px.
  static const posterMaxSize = 1200;

  /// The field values are the release's own model, so opening a release fills
  /// the form through it. Templates read the same values
  /// (`ai/release_structure.md` §3).
  FieldValues get fields => release.fields;

  /// The item this editor is working on. A Single video release has one item,
  /// the file the user picked; per-item forms are the part not built yet.
  ReleaseItem? singleItem() =>
      release.items.isEmpty ? null : release.items.first;

  /// Records a field value and marks the tab dirty — the tab record is the only
  /// place that state lives (rule 7). Returns whether the value changed, so the
  /// widget updates the field only when it actually did.
  bool setField(String name, String value) {
    if (fields.value(name) == value) {
      return false;
    }

    fields.setValue(name, value);
    tabManager.setUnsavedChanges(tabId, true);

    return true;
  }

  /// The shape the screenshot block has. It is not a field — `fields` is the
  /// name → string map a template reads — but it is part of `release.json`, so
  /// it is part of the save and marks the tab dirty the same way.
  bool setScreenshotLayout(ScreenshotLayout layout) {
    if (release.screenshotLayout == layout) {
      return false;
    }

    release.screenshotLayout = layout;
    tabManager.setUnsavedChanges(tabId, true);

    return true;
  }

  /// Whether the post ends with the app's signature. The same rule as the block
  /// shape: not a field, but part of `release.json`, so it is part of the save
  /// and marks the tab dirty the same way.
  bool setIncludeAppSignature(bool include) {
    if (release.includeAppSignature == include) {
      return false;
    }

    release.includeAppSignature = include;
    tabManager.setUnsavedChanges(tabId, true);

    return true;
  }

  /// Records the path the user picked.
  ///
  /// A picked file is treated as a directory containing only itself, so the
  /// item is the file and its path is the filename (`ai/release_structure.md`
  /// §2). A picked directory is the source the scan writes its items from, so
  /// nothing is created here: the items of a pack are the photosets the scan
  /// finds, and `type` is recorded by that scan rather than guessed from the
  /// path.
  ///
  /// This is part of the save, because `source` is in `release.json`.
  bool setSource(String path) {
    if (release.source == path) {
      return false;
    }

    release.source = path;

    if (File(path).existsSync()) {
      final item = ReleaseItem(
        path: p.basename(path),
        type: fieldListFor(release.releaseType).itemType,
        fields: FieldValues(),
      );

      if (release.items.isEmpty) {
        release.items.add(item);
      } else {
        release.items.first.path = item.path;
      }
    }

    tabManager.setUnsavedChanges(tabId, true);

    return true;
  }

  /// Runs ffprobe on the picked file. It does not write the fields and shows no
  /// messages: the widget applies the result through its own write path and
  /// maps a failure to localized text.
  Future<MediaProbeResult> probeMovieFile() async {
    final item = singleItem();

    if (item == null) {
      return const MediaProbeFailure(MediaProbeFailureKind.fileNotFound);
    }

    final path = release.absolutePath(item);

    if (path.isEmpty) {
      return const MediaProbeFailure(MediaProbeFailureKind.fileNotFound);
    }

    if (!await File(path).exists()) {
      return const MediaProbeFailure(MediaProbeFailureKind.fileNotFound);
    }

    return ffprobe.probe(
      releaseDirectory: release.directoryPath,
      filePath: path,
    );
  }

  /// The thumbnail the app writes for the video:
  /// `<release dir>/images/<item path>/_rp_thumbnail.jpg`. Nothing about it is
  /// stored in `images.json`, because the Upload section does not send
  /// thumbnails. Null when no file is picked.
  String? thumbnailPath() {
    final item = singleItem();

    if (item == null) {
      return null;
    }

    return p.join(
      release.directoryPath,
      'images',
      item.path,
      thumbnailFileName,
    );
  }

  /// The thumbnail path when its file is on disk, otherwise null. The widget
  /// only shows an image for a file that is there: Flutter remembers a failed
  /// load for the same path, so an image built for a missing file would stay
  /// empty even after the tool writes it.
  String? thumbnailOnDisk() {
    final path = thumbnailPath();

    if (path == null) {
      return null;
    }

    return File(path).existsSync() ? path : null;
  }

  /// Writes one frame of the video as the thumbnail, at the source resolution.
  /// It shows no messages: the widget maps a failure to localized text.
  Future<ThumbnailResult> generateThumbnail(double? durationSeconds) async {
    final item = singleItem();

    if (item == null) {
      return const ThumbnailFailure(ThumbnailFailureKind.fileNotFound);
    }

    final videoPath = release.absolutePath(item);

    if (videoPath.isEmpty || !await File(videoPath).exists()) {
      return const ThumbnailFailure(ThumbnailFailureKind.fileNotFound);
    }

    final outputPath = thumbnailPath()!;

    try {
      await Directory(p.dirname(outputPath)).create(recursive: true);
    } catch (_) {
      return const ThumbnailFailure(ThumbnailFailureKind.failed);
    }

    // The middle of the video. A file ffprobe did not report a duration for is
    // read from the start.
    final seekSeconds = durationSeconds == null ? 0.0 : durationSeconds / 2;

    final result = switch (await ffmpeg.screenshot(
      releaseDirectory: release.directoryPath,
      inputPath: videoPath,
      outputPath: outputPath,
      seekSeconds: seekSeconds,
    )) {
      ToolRunNotAvailable() => const ThumbnailFailure(
        ThumbnailFailureKind.toolNotAvailable,
      ),
      ToolRunFailure() => const ThumbnailFailure(ThumbnailFailureKind.failed),
      ToolRunTimeout() => const ThumbnailFailure(ThumbnailFailureKind.failed),
      ToolRunSuccess() => const ThumbnailSuccess(),
    };

    // The frame is a file the app wrote, so the release changed.
    if (result is ThumbnailSuccess) {
      await _stamp();
    }

    return result;
  }

  /// The poster record: the primary one, which is the manifest's rule
  /// (`images.dart`, `ai/release_structure.md` §4). Null when there is no
  /// poster.
  ImageRecord? posterRecord() =>
      images.loadSync(release.directoryPath).primaryPoster();

  /// The poster's path. The record is what says where the image is, because two
  /// posters cannot share one derived name.
  String? posterPath() {
    final record = posterRecord();

    if (record == null) {
      return null;
    }

    return p.join(release.directoryPath, record.file);
  }

  /// The poster path when its file is on disk, otherwise null. The same rule as
  /// the video thumbnail: the box only shows an image for a file that is there.
  String? posterOnDisk() {
    final path = posterPath();

    if (path == null) {
      return null;
    }

    return File(path).existsSync() ? path : null;
  }

  /// The extension a path has, without the leading dot, as `posterExtensions`
  /// lists it.
  static String _extension(String path) {
    final extension = p.extension(path).toLowerCase();

    return extension.startsWith('.') ? extension.substring(1) : extension;
  }

  /// What a content type says the bytes are, as `posterExtensions` lists it. A
  /// response that names no image, or names nothing at all, gives an empty
  /// string, which is not in `posterExtensions`.
  static String _formatFromContentType(ContentType? type) {
    if (type == null || type.primaryType != 'image') {
      return '';
    }

    return type.subType;
  }

  /// Writes the poster the user chose into the release directory: the file
  /// itself with neither dimension larger than 1200 px. A poster that is
  /// already smaller is not resized. It shows no messages: the widget maps a
  /// failure to localized text.
  ///
  /// [format] is what the source is, as `posterExtensions` lists it. For a file
  /// on disk that is its extension, and it is read from the path when the
  /// caller does not give one. A downloaded file can have no extension at all,
  /// so the caller that learned its format from the response gives it here.
  Future<PosterResult> setPoster(String sourcePath, {String? format}) async {
    final source = File(sourcePath);

    if (!await source.exists()) {
      return const PosterFailure(PosterFailureKind.fileNotFound);
    }

    if (!posterExtensions.contains(format ?? _extension(source.path))) {
      return const PosterFailure(PosterFailureKind.wrongFormat);
    }

    // The first poster record is the primary one. A poster that has no record
    // yet gets one at the release directory root, which is where the first
    // poster of a release has always been.
    final manifest = await images.load(release.directoryPath);
    var record = manifest.primaryPoster();

    record ??= ImageRecord(
      item: null,
      kind: ImageKind.poster,
      file: '_rp_poster.jpg',
      urls: const {},
    );

    final posterPath = p.join(release.directoryPath, record.file);

    switch (await ffmpeg.resizeImage(
      releaseDirectory: release.directoryPath,
      inputPath: source.path,
      outputPath: posterPath,
      maxSize: posterMaxSize,
    )) {
      case ToolRunNotAvailable():
        return const PosterFailure(PosterFailureKind.toolNotAvailable);
      case ToolRunFailure():
        return const PosterFailure(PosterFailureKind.failed);
      case ToolRunTimeout():
        return const PosterFailure(PosterFailureKind.failed);
      case ToolRunSuccess():
        break;
    }

    // The poster is recorded so the Upload section knows to send it. A manifest
    // that could not be written is reported like any other failure to write the
    // release.
    if (!await _savePoster([
      ...manifest.images,
      if (manifest.primaryPoster() == null) record,
    ])) {
      return const PosterFailure(PosterFailureKind.manifestFailed);
    }

    await _stamp();

    return const PosterSuccess();
  }

  /// Downloads a poster from a link and processes it exactly like a file the
  /// user picked: the same format check and the same write. The download goes
  /// to a temporary file, which is deleted afterwards, because ffmpeg needs a
  /// file to read. It shows no messages: the widget maps a failure to localized
  /// text.
  ///
  /// The format is what the link names when it names one, and what its response
  /// says when it names none. A StashDB image is `stashdb.org/images/<uuid>`,
  /// which is a link with no extension in it, so its content type is the only
  /// thing that says what the bytes are.
  Future<PosterResult> setPosterFromUrl(String url) async {
    final uri = Uri.tryParse(url.trim());

    if (uri == null || !urlSchemes.contains(uri.scheme)) {
      return const PosterFailure(PosterFailureKind.invalidUrl);
    }

    final extension = _extension(uri.path);

    // A link that names a format is judged before anything is downloaded, so a
    // link that will be rejected is never fetched. A link that names none can
    // only be judged from its response.
    if (extension.isNotEmpty && !posterExtensions.contains(extension)) {
      return const PosterFailure(PosterFailureKind.wrongFormat);
    }

    // The format is not in the name of the temporary file, because it is not
    // something the name can say when the link names no format. ffmpeg reads a
    // file by looking at its bytes, and the format is given to `setPoster()` by
    // the caller.
    final tempPath = p.join(Directory.systemTemp.path, 'rp_poster_download');

    switch (await downloader.download(uri, tempPath)) {
      case DownloadFailure():
        return const PosterFailure(PosterFailureKind.downloadFailed);
      case DownloadSuccess(contentType: final contentType):
        final format = extension.isEmpty
            ? _formatFromContentType(contentType)
            : extension;

        final result = await setPoster(tempPath, format: format);

        // The download is not part of the release, so it is cleaned up. Failing
        // to remove it does not change the result the user was given.
        try {
          await File(tempPath).delete();
        } catch (_) {
          // Nothing to report.
        }

        return result;
    }
  }

  /// Removes the poster file and the record for the primary poster, so the
  /// Upload section no longer has an image that is not on disk. Returns false
  /// when a file or the manifest could not be written; the widget turns that
  /// into a localized message.
  Future<bool> removePoster() async {
    final manifest = await images.load(release.directoryPath);
    final record = manifest.primaryPoster();

    if (record == null) {
      return true;
    }

    final path = p.join(release.directoryPath, record.file);

    try {
      final existing = File(path);

      if (await existing.exists()) {
        await existing.delete();
      }
    } catch (_) {
      return false;
    }

    if (!await _savePoster([
      for (final existing in manifest.images)
        if (existing != record) existing,
    ])) {
      return false;
    }

    // Removing the poster files and its record is a change to the release.
    await _stamp();

    return true;
  }

  /// Writes `images.json`, leaving the records that are not the poster as they
  /// are.
  Future<bool> _savePoster(List<ImageRecord> records) async {
    try {
      await images.save(release.directoryPath, ImagesManifest(images: records));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Records that the app changed a file inside the release. Only the timestamp
  /// is written, not the model, because the field values the user has not saved
  /// are not this write's to write — the poster and the message are written
  /// without a save step. A manifest that could not be written is not reported:
  /// the file the user asked for is on disk, and the next write stamps it
  /// again.
  Future<void> _stamp() async => await store.touchLastEdit(release);

  /// Writes the fields to `release.json` and clears the dirty flag. Returns
  /// false when the manifest could not be written; the widget turns that into a
  /// localized message.
  Future<bool> save() async {
    try {
      await store.save(release);
    } catch (_) {
      return false;
    }

    tabManager.setUnsavedChanges(tabId, false);

    return true;
  }
}

enum ThumbnailFailureKind {
  /// The path is empty or the video file is not there.
  fileNotFound,

  /// ffmpeg could not be started.
  toolNotAvailable,

  /// ffmpeg ran and the frame was not written.
  failed,
}

sealed class ThumbnailResult {
  const ThumbnailResult();
}

final class ThumbnailSuccess extends ThumbnailResult {
  const ThumbnailSuccess();
}

final class ThumbnailFailure extends ThumbnailResult {
  const ThumbnailFailure(this.kind);

  final ThumbnailFailureKind kind;
}

sealed class PosterResult {
  const PosterResult();
}

final class PosterSuccess extends PosterResult {
  const PosterSuccess();
}

final class PosterFailure extends PosterResult {
  const PosterFailure(this.kind);

  final PosterFailureKind kind;
}

enum PosterFailureKind {
  /// The path is empty or the file is not there.
  fileNotFound,

  /// Not a jpg or webp.
  wrongFormat,

  /// The pasted text is not an http or https link.
  invalidUrl,

  /// The link could not be downloaded.
  downloadFailed,

  /// ffmpeg could not be started.
  toolNotAvailable,

  /// ffmpeg ran and the file was not written.
  failed,

  /// The poster was written but `images.json` could not be.
  manifestFailed,
}
