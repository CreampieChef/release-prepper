import 'package:window_manager/window_manager.dart';

import 'window_size.dart';

/// The window itself: the size it has.
///
/// It is an interface because the plugin is a method channel and cannot be
/// exercised in a test, the same reason `SecretStore` is one (rule 4): the
/// feature is tested against a fake, and the plugin instance comes from the
/// composition root rather than being built here.
///
/// The app does not ask the window for a size. The size the app recorded is
/// applied by the runners before the window is created (`ai/doc.md` §7),
/// because a size asked for after the window exists is a request the desktop
/// may ignore, and a window that is resized after it appears is a jump the user
/// sees. So this is the one thing the app can do with the window: read what it
/// is, at the point it is closing.
abstract class WindowGateway {
  /// The size the window has now.
  Future<WindowSize> currentSize();
}

class PluginWindowGateway implements WindowGateway {
  PluginWindowGateway({required this.windowManager});

  final WindowManager windowManager;

  @override
  Future<WindowSize> currentSize() async {
    final size = await windowManager.getSize();

    return WindowSize(width: size.width.round(), height: size.height.round());
  }
}
