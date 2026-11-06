import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_localizations.dart';
import '../window/window_controller.dart';
import 'tab_close.dart';
import 'tab_close_controller.dart';

/// Runs the unsaved-changes popup once per tab when the user tries to close the
/// app, and closes the window only if no tab is cancelled. It renders its child
/// unchanged; it only registers the window-close listener.
class AppCloseHandler extends StatefulWidget {
  const AppCloseHandler({required this.child, super.key});

  final Widget child;

  @override
  State<AppCloseHandler> createState() => _AppCloseHandlerState();
}

class _AppCloseHandlerState extends State<AppCloseHandler> with WindowListener {
  /// Set once the window is closing for real, so the second `delete-event` that
  /// `destroy()` causes does not ask the user again.
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // Without this the toolkit closes the window straight away, so the popup is
    // never answered. The window now closes only through `destroy()` below.
    windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (_closing) return;

    final l10n = AppLocalizations.of(context)!;
    final controller = context.read<TabCloseController>();

    // Read before the popup, because the popup is a route and the widget may be
    // gone when the answer comes.
    final window = context.read<WindowController>();

    if (await confirmCloseApp(context, controller, l10n)) {
      _closing = true;

      // The size is recorded here because this is the only point at which the
      // app knows what the window was for a whole run. The answer is not shown:
      // there is no widget left that could say the file was not written, so a
      // failed write shows up on the next start. The close does not depend on
      // the write.
      await window.recordSize();

      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
