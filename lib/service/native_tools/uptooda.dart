import 'dart:convert';

import 'tool_locator.dart';
import 'tool_runner.dart';

/// uptooda-cli. Only the command the app uses is listed here.
///
/// The app ships this tool, because the upload scripts in its `Data/` are the
/// modified ones the app needs (`ai/bundled_native_tools.md`). A system install
/// has the unmodified scripts, so it is not an acceptable substitute and the
/// tool is resolved from the bundle only.
class Uptooda {
  Uptooda({required this.runner});

  static const tool = NativeTool(
    name: 'uptooda-cli',
    bundleDirectory: 'uptooda',
  );

  /// The app always asks for JSON, so the result is read from fields rather
  /// than from prose. `--code_type` is not passed: it only changes the bbcode
  /// form, and the app builds bbcode from the stored URLs.
  static const codeLang = 'json';

  /// 300 is the width the app uses for thumbnail links.
  static const thumbWidth = 300;

  /// The URL fields the tool reports. They are stored under the same names, so
  /// `images.json` matches the tool's output.
  static const urlFields = [
    'delete_url',
    'direct_url',
    'thumb_url',
    'view_url',
  ];

  /// The environment variable a hoster script reads its credential from. The
  /// name is the contract between the app and the modified scripts, so it is
  /// one constant rather than a string repeated at each call
  /// (`ai/bundled_native_tools.md`).
  static const apiKeyVariable = 'UPTOODA_HOSTER_API_KEY';

  final ToolRunner runner;

  /// The version line the tool prints for `--version`, used by the System Check
  /// tab.
  Future<ToolRunResult> version({required String releaseDirectory}) =>
      runner.run(tool, const ['--version'], releaseDirectory: releaseDirectory);

  /// One image to one hoster, as `ai/upload_images.md` describes: one file per
  /// call, so a failure affects one image rather than a batch. The app does not
  /// retry; the tool's built-in retries are used with their default values.
  ///
  /// `environment` is what this call adds to the environment the tool inherits.
  /// It is empty for a hoster that needs no credential, and the caller builds
  /// it only for the hosters that do (`ai/bundled_native_tools.md`).
  Future<UptoodaUploadResult> upload({
    required String releaseDirectory,
    required String hoster,
    required String filePath,
    required Map<String, String> environment,
  }) async {
    final result = await runner.run(
      tool,
      [
        '--server',
        hoster,
        '--code_lang',
        codeLang,
        '--thumb_width',
        thumbWidth.toString(),
        filePath,
      ],
      releaseDirectory: releaseDirectory,
      environment: environment,
    );

    return switch (result) {
      ToolRunNotAvailable() => const UptoodaUploadFailure(
        UptoodaUploadFailureKind.toolNotAvailable,
      ),
      ToolRunTimeout() => const UptoodaUploadFailure(
        UptoodaUploadFailureKind.timeout,
      ),
      // Success is decided by the `success` field, not by the exit code: the
      // tool exits 0 for an unknown hoster, where there is no result at all.
      ToolRunSuccess(stdout: final stdout) => _parse(stdout),
      ToolRunFailure(stdout: final stdout) => _parse(stdout),
    };
  }

  UptoodaUploadResult _parse(String stdout) {
    final decoded = _json(stdout);

    // With `--code_lang json` stdout is the result only. Nothing there means
    // the tool never reached an upload, which is what an unknown hoster gives.
    if (decoded is! List || decoded.isEmpty) {
      return const UptoodaUploadFailure(UptoodaUploadFailureKind.noResult);
    }

    final entry = decoded.first;

    if (entry is! Map<String, dynamic>) {
      return const UptoodaUploadFailure(UptoodaUploadFailureKind.noResult);
    }

    if (entry['success'] != true) {
      return const UptoodaUploadFailure(UptoodaUploadFailureKind.uploadFailed);
    }

    return UptoodaUploadSuccess({
      for (final field in urlFields)
        field: entry[field] is String ? entry[field] as String : '',
    });
  }

  Object? _json(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}

enum UptoodaUploadFailureKind {
  /// The tool is not in the bundle.
  toolNotAvailable,

  /// The call ran for longer than the runner's timeout.
  timeout,

  /// The tool wrote no result, which is what an unknown hoster gives.
  noResult,

  /// The tool reported a failed upload.
  uploadFailed,
}

sealed class UptoodaUploadResult {
  const UptoodaUploadResult();
}

final class UptoodaUploadSuccess extends UptoodaUploadResult {
  const UptoodaUploadSuccess(this.urls);

  /// The URLs the tool reported, under the field names it uses.
  final Map<String, String> urls;
}

final class UptoodaUploadFailure extends UptoodaUploadResult {
  const UptoodaUploadFailure(this.kind);

  final UptoodaUploadFailureKind kind;
}
