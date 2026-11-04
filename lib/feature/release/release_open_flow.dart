import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../main_menu_controller.dart';
import 'release_open_controller.dart';

String _reasonFor(ReleaseOpenFailureKind kind, AppLocalizations l10n) {
  return switch (kind) {
    ReleaseOpenFailureKind.folderPicker => l10n.folderPickerFailed,
    ReleaseOpenFailureKind.manifestNotFound => l10n.releaseManifestNotFound,
    ReleaseOpenFailureKind.loadFailed => l10n.releaseMetadataInvalid,
  };
}

/// Returns true when the user wants to pick a folder again.
///
/// `canPickAnother` is false for a row of the recent list: that row names a
/// folder the app has already read, so there is nothing to choose again and the
/// popup shows only Close. The reason text is the same one the menu item shows,
/// because it is the same failure.
Future<bool> _showOpenReleaseError(
  BuildContext context,
  AppLocalizations l10n,
  String reason, {
  bool canPickAnother = true,
}) async {
  final choice = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.openReleaseError),
      content: Text(reason),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.close),
        ),
        if (canPickAnother)
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.chooseAnotherFolder),
          ),
      ],
    ),
  );

  return choice ?? false;
}

/// The Open Release flow: pick, load, and the error popup with the option to
/// pick again. This is the single path the menu item and Ctrl-O both use, like
/// the shared close flow in `tab_close.dart`. It shows the popup, so it takes a
/// context (the same rule 13 exception as that flow); the dispatch stays in
/// `MainMenuController`.
///
/// `initialDirectory` is the default release directory from the settings, which
/// the widget reads from `SettingsController` and passes here: the picker opens
/// there.
Future<void> openReleaseWithErrors(
  BuildContext context,
  MainMenuController controller,
  AppLocalizations l10n,
  String initialDirectory,
) async {
  while (true) {
    final result = await controller.onOpenRelease(
      dialogTitle: l10n.chooseReleaseFolder,
      initialDirectory: initialDirectory,
    );

    if (!context.mounted) return;

    switch (result) {
      case ReleaseOpenSuccess():
      case ReleaseOpenCancelled():
        return;
      case ReleaseOpenFailure(kind: final kind):
        final retry = await _showOpenReleaseError(
          context,
          l10n,
          _reasonFor(kind, l10n),
        );
        if (!retry || !context.mounted) return;
    }
  }
}

/// The same flow for a folder the recent list names, so a row click reports a
/// failure the same way the menu item does. There is no picker and no retry:
/// the row names the folder, and the app cannot read it, so the popup has only
/// Close.
Future<void> openReleaseFromPathWithErrors(
  BuildContext context,
  MainMenuController controller,
  AppLocalizations l10n,
  String directoryPath,
) async {
  final result = await controller.onOpenPath(directoryPath);

  if (!context.mounted) return;

  if (result is ReleaseOpenFailure) {
    await _showOpenReleaseError(
      context,
      l10n,
      _reasonFor(result.kind, l10n),
      canPickAnother: false,
    );
  }
}
