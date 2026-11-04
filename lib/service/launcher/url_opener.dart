import 'package:url_launcher/url_launcher.dart';

/// Opens a link in the browser the OS uses. This is the second job for
/// url_launcher — `FolderOpener` is the first — so the rule that scopes the
/// package to opening a folder now covers opening a link as well
/// (`ai/uploading_draft.md` §5).
class UrlOpener {
  const UrlOpener();

  /// Opens [url]. It shows no messages: the widget maps a failure to localized
  /// text.
  Future<OpenUrlResult> open(String url) async {
    try {
      final opened = await launchUrl(Uri.parse(url));

      return opened ? const UrlOpened() : const UrlOpenFailed();
    } catch (_) {
      // The handler refused the URL or failed to start.
      return const UrlOpenFailed();
    }
  }
}

sealed class OpenUrlResult {
  const OpenUrlResult();
}

final class UrlOpened extends OpenUrlResult {
  const UrlOpened();
}

/// Nothing was opened.
final class UrlOpenFailed extends OpenUrlResult {
  const UrlOpenFailed();
}
