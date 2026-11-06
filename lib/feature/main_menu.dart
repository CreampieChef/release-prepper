import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import 'settings/settings_controller.dart';
import 'about.dart';
import 'main_menu_controller.dart';
import 'release/release_open_flow.dart';
import 'release/release_type.dart';
import 'tab/tab_close.dart';
import 'tab/tab_close_controller.dart';
import 'tab/tab_manager.dart';

/// The shared save flow: save the selected tab through `MainMenuController` and
/// show a message when the write fails. Used by the menu item and by Ctrl+S,
/// like the shared close flow in `tab_close.dart`. A tab that cannot be saved —
/// no tabs, or a wizard with no release — does nothing.
Future<void> saveCurrentTab(
  BuildContext context,
  MainMenuController controller,
  AppLocalizations l10n,
) async {
  if (!controller.tabManager.hasTabs) return;

  final tab = controller.tabManager.tabs[controller.tabManager.selectedIndex];
  if (tab.kind != AppTabKind.releaseEditor) return;

  if (!await controller.onSave()) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.releaseSaveFailed)));
  }
}

class MainMenu extends StatelessWidget {
  const MainMenu({super.key});

  /// A menu item's label with its hotkey hint, right-aligned with a minimum
  /// gap.
  ///
  /// The `Expanded` needs a bounded width, which the menu gives it: a submenu
  /// popup is vertical, and a vertical menu wraps each item's child in an
  /// `Expanded`, so the row fills the item, the gap is at least 60 px, and the
  /// hints line up at its right edge.
  ///
  /// The hint is drawn here rather than through `MenuItemButton.shortcut`: the
  /// framework renders the shortcut label with the item's own text style and a
  /// fixed spacing, which cannot be styled from outside. And `MenuItemButton`
  /// only shows a hint — it does not handle the key; the keys are handled by
  /// `AppShortcuts`, so nothing is lost by drawing the hint here.
  Widget _itemLabel(BuildContext context, String label, String hint) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 60),
        Text(
          hint,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.read<MainMenuController>();
    final closeController = context.read<TabCloseController>();

    // The default release directory is read here, from the settings, so the
    // open flow can open the picker there. Reading settings is what the widget
    // does; the controller is given the value it needs.
    final settings = context.read<SettingsController>();

    // The tab is watched for the enabled state of the items that act on the
    // selected tab: Save is disabled for a wizard tab, which has no release,
    // and Close tab is disabled when no tab is open. Clone Release is enabled
    // only for a single-video editor tab, because that is the only type the
    // clone feature covers.
    final tabManager = context.watch<TabManager>();
    final selectedTab = tabManager.hasTabs
        ? tabManager.tabs[tabManager.selectedIndex]
        : null;
    final canSave = selectedTab?.kind == AppTabKind.releaseEditor;
    final canClone =
        canSave && selectedTab!.release!.releaseType == ReleaseType.singleVideo;
    final canClose = tabManager.hasTabs;

    return SizedBox(
      width: double.infinity,
      child: MenuBar(
        children: [
          SubmenuButton(
            menuChildren: [
              // The hints are drawn by `_itemLabel`; the keys themselves are
              // handled by `AppShortcuts`, and both the item and its key call
              // the same callback.
              MenuItemButton(
                onPressed: controller.onNewRelease,
                child: _itemLabel(
                  context,
                  l10n.newRelease,
                  l10n.newReleaseShortcut,
                ),
              ),
              MenuItemButton(
                onPressed: () => openReleaseWithErrors(
                  context,
                  controller,
                  l10n,
                  settings.defaultReleaseDirectory,
                ),
                child: _itemLabel(
                  context,
                  l10n.openRelease,
                  l10n.openReleaseShortcut,
                ),
              ),
              // Clone Release has no hotkey, so it shows no hint, for the same
              // reason Settings and Recent releases show none. It acts on the
              // selected tab, so it is enabled only when that tab is a
              // single-video editor tab.
              MenuItemButton(
                onPressed: canClone ? controller.onCloneRelease : null,
                child: Text(l10n.cloneRelease),
              ),
              MenuItemButton(
                onPressed: canSave
                    ? () => saveCurrentTab(context, controller, l10n)
                    : null,
                child: _itemLabel(context, l10n.save, l10n.saveShortcut),
              ),
              // The same path as Ctrl-W and the strip: the shared close flow,
              // so a dirty tab gets the popup first.
              MenuItemButton(
                onPressed: canClose
                    ? () => closeTabWithConfirmation(
                        context,
                        closeController,
                        tabManager.tabs[tabManager.selectedIndex],
                        l10n,
                      )
                    : null,
                child: _itemLabel(
                  context,
                  l10n.closeTabItem,
                  l10n.closeTabShortcut,
                ),
              ),
              // Settings has no hotkey, so its item shows no hint: the hints
              // drawn here are the keys `AppShortcuts` handles, and there is no
              // key for this one.
              MenuItemButton(
                onPressed: controller.onSettings,
                child: Text(l10n.settings),
              ),
              // Recent releases has no hotkey either, for the same reason
              // Settings has none: there is no key `AppShortcuts` handles for
              // it.
              MenuItemButton(
                onPressed: controller.onRecentReleases,
                child: Text(l10n.recentReleases),
              ),
            ],
            child: Text(l10n.file),
          ),
          SubmenuButton(
            menuChildren: [
              // System Check has no hotkey either, for the same reason Settings
              // and Recent releases have none: there is no key `AppShortcuts`
              // handles for it.
              MenuItemButton(
                onPressed: controller.onSystemCheck,
                child: Text(l10n.systemCheck),
              ),
              MenuItemButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => const AboutPopup(),
                  );
                },
                child: Text(l10n.about),
              ),
            ],
            child: Text(l10n.help),
          ),
        ],
      ),
    );
  }
}
