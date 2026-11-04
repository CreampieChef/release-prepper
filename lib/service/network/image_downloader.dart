import 'dart:io';

/// One of the two Dart paths that make a network request. The client is
/// required, never built here, so a test can substitute it.
class ImageDownloader {
  ImageDownloader({required this.client});

  final HttpClient client;

  /// Downloads one file and writes it to [destinationPath]. It shows no
  /// messages: the widget maps a failure to localized text.
  ///
  /// It reports the content type the response gave, because a URL can name no
  /// format at all — a StashDB image is `stashdb.org/images/<uuid>` — so the
  /// response is the only thing that says what the bytes are.
  Future<DownloadResult> download(Uri url, String destinationPath) async {
    try {
      final request = await client.getUrl(url);
      final response = await request.close();

      if (response.statusCode != 200) {
        return const DownloadFailure(DownloadFailureKind.failed);
      }

      final chunks = await response.toList();
      final bytes = chunks.expand((chunk) => chunk).toList();

      await File(destinationPath).writeAsBytes(bytes);

      return DownloadSuccess(destinationPath, response.headers.contentType);
    } catch (_) {
      return const DownloadFailure(DownloadFailureKind.failed);
    }
  }
}

sealed class DownloadResult {
  const DownloadResult();
}

final class DownloadSuccess extends DownloadResult {
  const DownloadSuccess(this.path, this.contentType);

  final String path;

  /// What the response said the file is, or null when it said nothing. A URL
  /// can name no format at all — a StashDB image is `stashdb.org/images/<uuid>`
  /// — so this is the only thing that says what the bytes are.
  final ContentType? contentType;
}

final class DownloadFailure extends DownloadResult {
  const DownloadFailure(this.kind);

  final DownloadFailureKind kind;
}

enum DownloadFailureKind {
  /// The request failed: no connection, a non-200 response, or the file could
  /// not be written.
  failed,
}
