import 'dart:io';

import 'package:path/path.dart' as p;

import '../fonts/font_store.dart';
import '../native_tools/ffmpeg.dart';
import '../native_tools/ffprobe.dart';
import '../native_tools/mtn.dart';
import '../native_tools/tool_runner.dart';

/// The rules that turn one video file into the images the app writes
/// (`ai/doc.md` §2): the key-frame times, the file names, the
/// screenlist rows, the ffmpeg and mtn calls. It writes the files and reports
/// what it wrote; it does not record them, because a record in `images.json`
/// belongs to the feature that tracks the images, not to the tools that made
/// them. Called only when the user asks.
class ImageGenerator {
  ImageGenerator({
    required this.ffmpeg,
    required this.ffprobe,
    required this.mtn,
    required this.fonts,
  });

  final Ffmpeg ffmpeg;
  final Ffprobe ffprobe;
  final Mtn mtn;

  /// The font the screenlist is drawn with. `Mtn` cannot resolve a font name
  /// through fontconfig, so it is given the path of the file this writes
  /// (`ai/bundled_native_tools.md`).
  final FontStore fonts;

  /// The slider maximum the spec gives. The minimum is not a rule of
  /// generation: it is what a section allows — 3 for a single video, 0 for a
  /// pack, where a run can write only the screenlist.
  static const maxCount = 20;

  /// The screenlist grid (`ai/doc.md` §2): 4 columns, and
  /// the frame count is one per minute of video, at least 16 and at most 96.
  static const screenlistColumns = 4;
  static const screenlistMinFrames = 16;
  static const screenlistMaxFrames = 96;

  /// `_rp_screenshotNN.jpg`, where NN is the two-digit screenshot number.
  static String screenshotFileName(int number) =>
      '_rp_screenshot${number.toString().padLeft(2, '0')}.jpg';

  /// The screenlist file, `_rp_screenlist.jpg`: mtn writes the name it is given
  /// by `-x` with the extension from `-o`.
  static String screenlistFileName() => '${Mtn.screenlistName}.jpg';

  /// The key frame times, evenly spread along the duration: the centre of each
  /// of [count] equal segments, so every frame lands inside the video. With 0
  /// there are no frames, which is what a run that writes only the screenlist
  /// asks for.
  static List<double> keyframeTimes(double durationSeconds, int count) =>
      List.generate(count, (index) => durationSeconds * (index + 0.5) / count);

  /// The screenlist rows (`ai/doc.md` §2): one frame per
  /// minute of video, at least 16 and at most 96 frames, 4 frames per row. A
  /// duration that is not a whole number of rows is rounded up, so the grid
  /// still has at least one frame per minute.
  static int screenlistRows(double durationSeconds) {
    final frames = (durationSeconds / 60).clamp(
      screenlistMinFrames.toDouble(),
      screenlistMaxFrames.toDouble(),
    );

    return (frames / screenlistColumns).ceil();
  }

  /// The folder the images go in: `<release dir>/images/<item path>`, the same
  /// folder the video thumbnail uses (`ai/doc.md` §2).
  static String imagesDirectory(String releaseDirectory, String itemPath) =>
      p.join(releaseDirectory, 'images', itemPath);

  /// One item: [count] screenshots and the screenlist, written into
  /// [imagesDirectory]. It reports the files it wrote as paths relative to the
  /// release directory with `/` separators, because that is the shape
  /// `images.json` stores, and what stopped this item, if anything.
  ///
  /// A run that does not finish still reports the files it wrote: a screenlist
  /// that failed must not hide screenshots that succeeded.
  ///
  /// [onWritten] is called for each file as it is written, with the same
  /// relative path, so the caller can show a frame as soon as it exists rather
  /// than only at the end of the run. It is a plain callback the caller passes
  /// in, not a listener the service owns.
  Future<ImageGenerationResult> generate({
    required String releaseDirectory,
    required String itemPath,
    required String videoPath,
    required int count,
    required void Function(GeneratedImageFile file) onWritten,
  }) async {
    if (videoPath.isEmpty || !await File(videoPath).exists()) {
      return ImageGenerationResult(
        item: itemPath,
        screenshots: const [],
        failure: ImageGenerationFailureKind.fileNotFound,
      );
    }

    final probe = await ffprobe.probe(
      releaseDirectory: releaseDirectory,
      filePath: videoPath,
    );

    if (probe is MediaProbeFailure) {
      return ImageGenerationResult(
        item: itemPath,
        screenshots: const [],
        failure: switch (probe.kind) {
          MediaProbeFailureKind.fileNotFound =>
            ImageGenerationFailureKind.fileNotFound,
          MediaProbeFailureKind.toolNotAvailable =>
            ImageGenerationFailureKind.probeToolNotAvailable,
          MediaProbeFailureKind.probeFailed =>
            ImageGenerationFailureKind.probeFailed,
        },
      );
    }

    final durationSeconds = (probe as MediaProbeSuccess).info.durationSeconds;

    if (durationSeconds == null) {
      return ImageGenerationResult(
        item: itemPath,
        screenshots: const [],
        failure: ImageGenerationFailureKind.probeFailed,
      );
    }

    final directory = imagesDirectory(releaseDirectory, itemPath);

    try {
      await Directory(directory).create(recursive: true);
    } catch (_) {
      return ImageGenerationResult(
        item: itemPath,
        screenshots: const [],
        failure: ImageGenerationFailureKind.failed,
      );
    }

    final relativeDirectory = 'images/$itemPath';
    final times = keyframeTimes(durationSeconds, count);
    final screenshots = <String>[];
    String? screenlist;
    ImageGenerationFailureKind? failure;

    // Each file is reported as it is written, with the same relative path the
    // result reports, so the caller can show a frame before the run ends.
    void report(GeneratedImageKind kind, String path) =>
        onWritten(GeneratedImageFile(item: itemPath, kind: kind, path: path));

    for (var index = 0; index < count && failure == null; index++) {
      final name = screenshotFileName(index + 1);

      switch (await ffmpeg.screenshot(
        releaseDirectory: releaseDirectory,
        inputPath: videoPath,
        outputPath: p.join(directory, name),
        seekSeconds: times[index],
      )) {
        case ToolRunNotAvailable():
          failure = ImageGenerationFailureKind.ffmpegNotAvailable;
        case ToolRunFailure():
          failure = ImageGenerationFailureKind.failed;
        case ToolRunTimeout():
          failure = ImageGenerationFailureKind.failed;
        case ToolRunSuccess():
          // The manifest stores the path with `/` separators, relative to the
          // release directory, because that path is the record ID.
          final path = '$relativeDirectory/$name';
          screenshots.add(path);
          report(GeneratedImageKind.screenshot, path);
      }
    }

    if (failure == null) {
      final name = screenlistFileName();

      switch (await mtn.screenlist(
        releaseDirectory: releaseDirectory,
        inputPath: videoPath,
        outputDirectory: directory,
        rows: screenlistRows(durationSeconds),
        fontPath: await fonts.fontPath(),
      )) {
        case ToolRunNotAvailable():
          failure = ImageGenerationFailureKind.mtnNotAvailable;
        case ToolRunSuccess():
          screenlist = '$relativeDirectory/$name';
        case ToolRunFailure():
        case ToolRunTimeout():
          // mtn exits with a non-zero code when it prints a warning, including
          // for a skipped shot, even when it wrote the file, so the file is
          // what decides.
          if (File(p.join(directory, name)).existsSync()) {
            screenlist = '$relativeDirectory/$name';
          } else {
            failure = ImageGenerationFailureKind.screenlistFailed;
          }
      }

      if (screenlist != null) {
        report(GeneratedImageKind.screenlist, screenlist);
      }
    }

    return ImageGenerationResult(
      item: itemPath,
      screenshots: screenshots,
      screenlist: screenlist,
      failure: failure,
    );
  }
}

/// What one item's run produced: the files it wrote and what stopped it, if
/// anything. The caller decides whether a tool that is not available stops the
/// run — it does not become installed while the app is open — and whether a
/// file that failed stops the next one, which it does not.
final class ImageGenerationResult {
  const ImageGenerationResult({
    required this.item,
    required this.screenshots,
    this.screenlist,
    this.failure,
  });

  /// The item this run was for, as its path in `release.json`: the ID the
  /// records link to, so the controller that builds them is not told it again.
  final String item;

  /// The screenshots, as paths relative to the release directory with `/`
  /// separators, in the order they were written.
  final List<String> screenshots;

  /// The screenlist, as the same kind of path, or null when the run did not
  /// write one.
  final String? screenlist;

  final ImageGenerationFailureKind? failure;
}

/// One file as the run wrote it, reported while the run is still going: the
/// item it belongs to, what the run wrote it as, and the path relative to the
/// release directory with `/` separators — the same shape the result reports at
/// the end. The service reports files, not records: the record, and the kind a
/// file is in `images.json`, belong to the feature that tracks the images.
final class GeneratedImageFile {
  const GeneratedImageFile({
    required this.item,
    required this.kind,
    required this.path,
  });

  final String item;
  final GeneratedImageKind kind;
  final String path;
}

/// What a run wrote a file as. This is the service's vocabulary, the two things
/// it can write; the feature's `ImageKind` has more, because a release also
/// holds posters and copied photos, so the feature maps one vocabulary to the
/// other.
enum GeneratedImageKind { screenshot, screenlist }

/// What stopped a run. `manifestFailed` is the one value the tools do not
/// produce: it is what the controller that writes `images.json` reports when
/// the write fails, and it is here because the widget maps one vocabulary to
/// text, not two.
enum ImageGenerationFailureKind {
  /// The video path is empty or the file is not there.
  fileNotFound,

  /// ffprobe could not be started.
  probeToolNotAvailable,

  /// ffprobe ran and the duration could not be read.
  probeFailed,

  /// ffmpeg could not be started.
  ffmpegNotAvailable,

  /// ffmpeg ran and a frame was not written.
  failed,

  /// mtn could not be started.
  mtnNotAvailable,

  /// mtn ran and the screenlist was not written.
  screenlistFailed,

  /// `images.json` could not be written.
  manifestFailed;

  /// Whether this stops the whole run. A tool that is not available does not
  /// become installed while the app is open, and a manifest that cannot be
  /// written is not a file problem one item has on its own, so the rest of the
  /// items cannot be done either. A file that failed does not stop the next
  /// one, as one file does not fail the scan.
  bool get stopsRun => switch (this) {
    probeToolNotAvailable => true,
    ffmpegNotAvailable => true,
    mtnNotAvailable => true,
    manifestFailed => true,
    _ => false,
  };
}
