import 'tool_locator.dart';
import 'tool_runner.dart';

/// The ffmpeg tool. Only the commands the app uses are listed here; the next
/// features add theirs. The runner is required, never built here.
class Ffmpeg {
  Ffmpeg({required this.runner});

  /// The app prefers its own copy and uses the user's when it has none. The
  /// Windows build is committed in `native/media/windows/` and installed as
  /// `<app directory>/media/`; nothing is committed for the other platforms, so
  /// there the tool is read from PATH. One directory holds ffmpeg, ffprobe and
  /// mtn because the three load one shared set of DLLs
  /// (`ai/bundled_native_tools.md`).
  static const tool = NativeTool(
    name: 'ffmpeg',
    bundleDirectory: 'media',
    pathFallback: true,
  );

  final ToolRunner runner;

  Future<ToolRunResult> version({required String releaseDirectory}) =>
      runner.run(tool, const ['-version'], releaseDirectory: releaseDirectory);

  /// An image file, written as a JPEG, with neither dimension larger than
  /// [maxSize]. `min(maxSize, iw)` never makes a dimension larger, so a smaller
  /// image is not resized, and `force_original_aspect_ratio=decrease` keeps the
  /// proportions for a portrait one. `force_divisible_by=2` is what the JPEG
  /// encoder needs. ffmpeg reads jpg and webp, and applies the orientation an
  /// EXIF tag gives a JPEG, so a phone photo comes out the right way round.
  Future<ToolRunResult> resizeImage({
    required String releaseDirectory,
    required String inputPath,
    required String outputPath,
    required int maxSize,
  }) => runner.run(tool, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-nostdin',
    '-y',
    '-i',
    inputPath,
    '-vf',
    "scale='min($maxSize,iw)':'min($maxSize,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
    '-q:v',
    '3',
    outputPath,
  ], releaseDirectory: releaseDirectory);

  /// One key frame of a video file, written as a JPEG at the source resolution
  /// (`ai/doc.md` §2). This is the call both the Screenshots
  /// section and the video thumbnail use: the picture keeps the source
  /// resolution, so the file is the full frame rather than a scaled-down copy.
  /// `-skip_frame nokey` is an input option, so ffmpeg decodes only key frames
  /// and the frame it writes is the key frame at or before [seekSeconds].
  Future<ToolRunResult> screenshot({
    required String releaseDirectory,
    required String inputPath,
    required String outputPath,
    required double seekSeconds,
  }) => runner.run(tool, [
    '-hide_banner',
    '-loglevel',
    'error',
    '-nostdin',
    '-y',
    '-skip_frame',
    'nokey',
    '-ss',
    seekSeconds.toStringAsFixed(3),
    '-i',
    inputPath,
    '-frames:v',
    '1',
    '-q:v',
    '3',
    outputPath,
  ], releaseDirectory: releaseDirectory);
}
