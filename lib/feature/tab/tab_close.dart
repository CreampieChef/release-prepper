import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'tab_close_controller.dart';
import 'tab_manager.dart';

/// The choice the user makes in the unsaved-changes popup.
enum TabCloseChoice { closeWithoutSaving, saveAndClose, cancel }

/// The title a tab shows in the strip and in the popup. Shared by `TabStrip`
/// and the close flow so both name the tab the same way.
String tabTitle(AppTab tab, AppLocalizations l10n) {
  return switch (tab.kind) {
    AppTabKind.releaseWizard => l10n.newRelease,
    AppTabKind.cloneWizard => l10n.cloneRelease,
    AppTabKind.releaseEditor => tab.release!.name,
    AppTabKind.settings => l10n.settings,
    AppTabKind.recentReleases => l10n.recentReleases,
    AppTabKind.systemCheck => l10n.systemCheck,
  };
}

/// The three-option popup for a tab with unsaved changes. The first option is
/// the danger one, and a dismissed dialog counts as Cancel.
///
/// The save runs from its own button, so a failed write does not close the
/// popup: the tab is kept, the error is shown inside the dialog, and the user
/// can retry or choose another option. The popup therefore only returns a
/// choice that actually closed the tab, or Cancel.
class _UnsavedChangesPopup extends StatefulWidget {
  const _UnsavedChangesPopup({required this.title, required this.save});

  final String title;
  final Future<bool> Function() save;

  @override
  State<_UnsavedChangesPopup> createState() => _UnsavedChangesPopupState();
}

class _UnsavedChangesPopupState extends State<_UnsavedChangesPopup> {
  String? _error;

  Future<void> _saveAndClose() async {
    final saved = await widget.save();

    // The dialog can be dismissed while the write is in flight, so the state
    // may be gone by the time it finishes.
    if (!mounted) return;

    if (!saved) {
      setState(() => _error = AppLocalizations.of(context)!.releaseSaveFailed);
      return;
    }

    Navigator.of(context).pop(TabCloseChoice.saveAndClose);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.closeUnsavedTitle),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.closeUnsavedMessage(widget.title)),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () =>
              Navigator.of(context).pop(TabCloseChoice.closeWithoutSaving),
          child: Text(l10n.closeWithoutSaving),
        ),
        TextButton(onPressed: _saveAndClose, child: Text(l10n.saveAndClose)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(TabCloseChoice.cancel),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

Future<TabCloseChoice> _showUnsavedChangesPopup(
  BuildContext context,
  String title,
  Future<bool> Function() save,
) async {
  final choice = await showDialog<TabCloseChoice>(
    context: context,
    builder: (context) => _UnsavedChangesPopup(title: title, save: save),
  );

  return choice ?? TabCloseChoice.cancel;
}

/// Close one tab, whatever the method: a clean tab closes directly, a dirty one
/// shows the popup first. This is the single path the strip, Ctrl-W, and
/// closing the app all use.
Future<void> closeTabWithConfirmation(
  BuildContext context,
  TabCloseController controller,
  AppTab tab,
  AppLocalizations l10n,
) async {
  if (!tab.hasUnsavedChanges) {
    controller.closeTab(tab);
    return;
  }

  // The popup names a tab, so show that tab: otherwise the user decides about
  // one tab while looking at another.
  controller.selectTab(tab);

  final choice = await _showUnsavedChangesPopup(
    context,
    tabTitle(tab, l10n),
    () => controller.saveTab(tab),
  );

  if (choice != TabCloseChoice.cancel) {
    controller.closeTab(tab);
  }
}

/// The same popup, once per tab, when the user tries to close the app. Returns
/// false when the user cancels, so the app does not close.
Future<bool> confirmCloseApp(
  BuildContext context,
  TabCloseController controller,
  AppLocalizations l10n,
) async {
  for (final tab in controller.tabManager.tabs) {
    if (!tab.hasUnsavedChanges) {
      continue;
    }

    if (!context.mounted) return false;

    // The popup names a tab, so show that tab: otherwise the user decides about
    // one tab while looking at another.
    controller.selectTab(tab);

    final choice = await _showUnsavedChangesPopup(
      context,
      tabTitle(tab, l10n),
      () => controller.saveTab(tab),
    );

    if (!context.mounted) return false;

    if (choice == TabCloseChoice.cancel) {
      return false;
    }
  }

  return true;
}
