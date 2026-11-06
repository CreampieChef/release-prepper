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

/// The app's Ctrl keys: Ctrl+N creates a new release, Ctrl-O opens a release
/// through the shared open flow, Ctrl+S saves the current tab through the
/// shared save flow, Ctrl-W closes the current tab through the shared close
/// flow. The menu items and these keys call the same callbacks.
///
/// It is placed at the app level, in `MaterialApp.builder`, so it is an
/// ancestor of every focus scope in the app, including a popup route's: the
/// keys reach it from wherever the focus is, which is what the per-widget
/// patches used to achieve one case at a time. A widget nearer in the focus
/// chain is asked first, so the editor's own Ctrl+S handler still wins for its
/// fields and this runs only when nothing nearer claims the key. Both paths
/// reach the same save.
///
/// What it cannot reach is a key with nothing focused at all: the event stops
/// at the root focus scope, which is above this widget, so nothing inside the
/// app can be asked. While a route is showing, its focus scope has focus, so
/// this is not a state the app is in.
///
/// The save flow shows its message through `ScaffoldMessenger`; `MaterialApp`
/// puts the one it provides above `builder`, so a message can be shown from
/// here even when the key was pressed with a popup open.
class AppShortcuts extends StatelessWidget {
  const AppShortcuts({required this.child, super.key});

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
          // opens in.
          openReleaseWithErrors(
            context,
            menuController,
            l10n,
            settings.defaultReleaseDirectory,
          );
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          // The tab the user is on, whether or not the focus is inside it.
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
