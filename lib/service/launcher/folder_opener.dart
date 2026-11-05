import 'package:url_launcher/url_launcher.dart';

/// Opens a folder in the file manager the OS uses. This is the app's only use of
/// url_launcher (`ai/torrents.md`).
class FolderOpener {
  const FolderOpener();

  /// Opens [directory]. It shows no messages: the widget maps a failure to
  /// localized text.
  Future<OpenFolderResult> open(String directory) async {
    try {
      // A path is not a URL, so it is given as a file URI. That is the form the
      // OS handlers accept for a folder.
      final opened = await launchUrl(Uri.file(directory));

      return opened ? const FolderOpened() : const FolderOpenFailed();
    } catch (_) {
      // The handler refused the URI or failed to start.
      return const FolderOpenFailed();
    }
  }
}

sealed class OpenFolderResult {
  const OpenFolderResult();
}

final class FolderOpened extends OpenFolderResult {
  const FolderOpened();
}

/// Nothing was opened.
final class FolderOpenFailed extends OpenFolderResult {
  const FolderOpenFailed();
}
