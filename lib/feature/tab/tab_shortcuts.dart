import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../main_menu.dart';
import '../main_menu_controller.dart';
import '../release/release_open_flow.dart';
import '../settings/settings_controller.dart';
import 'tab_close.dart';
import 'tab_close_controller.dart';
import 'tab_manager.dart';

/// The app's keyboard shortcuts: Ctrl+N creates a new release, Ctrl-O opens a
/// release, Ctrl+S saves the current tab, Ctrl-W closes the current tab. It
/// wraps the content so the key reaches it through the focus chain regardless
/// of which widget is focused. The editor's own Ctrl+S handler wins when a
/// field is focused; this is the fallback for when focus is elsewhere. Both
/// paths reach the same save. The menu items call the same callbacks as the
/// keys, so a menu action and its shortcut do the same thing.
///
/// It must sit inside the `Scaffold`, because the save flow shows a message
/// through `ScaffoldMessenger`, which the `Scaffold` provides.
class TabShortcuts extends StatelessWidget {
  const TabShortcuts({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tabManager = context.read<TabManager>();
    final controller = context.read<TabCloseController>();
    final menuController = context.read<MainMenuController>();
    final settings = context.read<SettingsController>();
    final l10n = AppLocalizations.of(context)!;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
          menuController.onNewRelease();
        },
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () {
          // The same path as the menu item, including the directory the picker
          // opens at.
          openReleaseWithErrors(
            context,
            menuController,
            l10n,
            settings.defaultReleaseDirectory,
          );
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          saveCurrentTab(context, menuController, l10n);
        },
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () {
          if (!tabManager.hasTabs) return;

          final tab = tabManager.tabs[tabManager.selectedIndex];
          closeTabWithConfirmation(context, controller, tab, l10n);
        },
      },
      child: child,
    );
  }
}
