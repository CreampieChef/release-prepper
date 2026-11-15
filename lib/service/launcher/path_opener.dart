import 'package:url_launcher/url_launcher.dart';

/// Opens a path with the handler the OS uses for it: a folder in the file
/// manager, a file in the application registered for its type. This is the
/// app's only use of url_launcher for a path (`ai/torrents.md`,
/// `ai/uploading_draft.md` §10, `ai/pornolab_upload.md` §11), and the same
/// call serves both, so a folder and a file are not two services.
class PathOpener {
  const PathOpener();

  /// Opens [path]. It shows no messages: the widget maps a failure to localized
  /// text.
  Future<OpenPathResult> open(String path) async {
    try {
      // A path is not a URL, so it is given as a file URI. That is the form the
      // OS handlers accept for a path.
      final opened = await launchUrl(Uri.file(path));

      return opened ? const PathOpened() : const PathOpenFailed();
    } catch (_) {
      // The handler refused the URI or failed to start.
      return const PathOpenFailed();
    }
  }
}

sealed class OpenPathResult {
  const OpenPathResult();
}

final class PathOpened extends OpenPathResult {
  const PathOpened();
}

/// Nothing was opened.
final class PathOpenFailed extends OpenPathResult {
  const PathOpenFailed();
}
