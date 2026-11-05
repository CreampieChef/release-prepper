import 'dart:convert';

import 'media_info.dart';
import 'tool_locator.dart';
import 'tool_runner.dart';

/// ffprobe. One call returns everything the editor needs for a file: the
/// container, the duration, and both streams. The runner is required, never
/// built here.
class Ffprobe {
  Ffprobe({required this.runner});

  /// The app prefers its own copy and uses the user's when it has none, as
  /// `Ffmpeg` does. The three media tools are committed together and load the
  /// same DLLs, so ffprobe is looked for in the same directory as ffmpeg
  /// (`ai/bundled_native_tools.md`).
  static const tool = NativeTool(
    name: 'ffprobe',
    bundleDirectory: 'media',
    pathFallback: true,
  );

  final ToolRunner runner;

  /// The version line the tool prints for `-version`, used by the System Check
  /// tab. The first line of its output is the version, as the tool writes it.
  Future<ToolRunResult> version({required String releaseDirectory}) =>
      runner.run(tool, const ['-version'], releaseDirectory: releaseDirectory);

  Future<MediaProbeResult> probe({
    required String releaseDirectory,
    required String filePath,
  }) async {
    final result = await runner.run(tool, [
      '-hide_banner',
      '-of',
      'json',
      '-show_format',
      '-show_streams',
      filePath,
    ], releaseDirectory: releaseDirectory);

    return switch (result) {
      ToolRunNotAvailable() => const MediaProbeFailure(
        MediaProbeFailureKind.toolNotAvailable,
      ),
      ToolRunFailure() => const MediaProbeFailure(
        MediaProbeFailureKind.probeFailed,
      ),
      // A probe that ran for the whole timeout is treated as a failed probe:
      // the app has no message for a timeout, and one call reading a file is
      // not expected to take a minute.
      ToolRunTimeout() => const MediaProbeFailure(
        MediaProbeFailureKind.probeFailed,
      ),
      ToolRunSuccess(stdout: final stdout) => _parse(stdout),
    };
  }

  MediaProbeResult _parse(String stdout) {
    try {
      final decoded = jsonDecode(stdout);

      if (decoded is! Map<String, dynamic>) {
        return const MediaProbeFailure(MediaProbeFailureKind.probeFailed);
      }

      return MediaProbeSuccess(MediaInfo.parse(decoded));
    } on FormatException {
      return const MediaProbeFailure(MediaProbeFailureKind.probeFailed);
    }
  }
}

enum MediaProbeFailureKind {
  /// The path is empty or the file is not there.
  fileNotFound,

  /// ffprobe could not be started.
  toolNotAvailable,

  /// ffprobe ran and the file could not be read, or is not a media file.
  probeFailed,
}

sealed class MediaProbeResult {
  const MediaProbeResult();
}

final class MediaProbeSuccess extends MediaProbeResult {
  const MediaProbeSuccess(this.info);

  final MediaInfo info;
}

final class MediaProbeFailure extends MediaProbeResult {
  const MediaProbeFailure(this.kind);

  final MediaProbeFailureKind kind;
}
