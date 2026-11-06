import 'package:release_prepper/feature/window/window_gateway.dart';
import 'package:release_prepper/feature/window/window_size.dart';

/// The window is a method channel, so it cannot be exercised in a test. This is
/// the fake the window tests use: it answers with the size it is given, which
/// is all the feature asks the window for.
class FakeWindowGateway implements WindowGateway {
  FakeWindowGateway({required this.current});

  /// The size the window has. A test sets it to one the app cannot store to get
  /// the size the plugin reports for a window that has not been mapped.
  WindowSize current;

  @override
  Future<WindowSize> currentSize() async => current;
}
