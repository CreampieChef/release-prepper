import 'package:release_prepper/feature/window/window_gateway.dart';
import 'package:release_prepper/feature/window/window_record.dart';
import 'package:release_prepper/feature/window/window_size.dart';

/// The window is a method channel, so it cannot be exercised in a test. This is
/// the fake the window tests use: it answers with the record it is given, which
/// is all the feature asks the window for, keeps the sizes it is asked for so a
/// test can read them, and a test can fire an event through the callback the
/// feature registers.
class FakeWindowGateway implements WindowGateway {
  FakeWindowGateway({required this.current});

  /// The record the window is. A test sets it to one the app cannot store to
  /// get the record the plugin reports for a window that has not been mapped.
  WindowRecord current;

  /// The sizes the fake was asked for, in the order it was asked. Whether the
  /// request is honoured cannot be known — the plugin cannot say either — so
  /// the fake does not change `current` and a test reads what was asked for.
  final List<WindowSize> requested = [];

  final List<WindowRecordListener> _listeners = [];

  /// The test's stand for the window changing. The fake has no state of its own
  /// to work out — the plugin reads the real window's — so a test sets
  /// `current` to what the window would be after the change and calls this,
  /// which is the write the feature would do at that point.
  Future<void> event(WindowEvent event) async {
    for (final listener in _listeners) {
      await listener(event);
    }
  }

  @override
  Future<WindowRecord> currentRecord() async => current;

  @override
  Future<void> requestSize(WindowSize size) async {
    requested.add(size);
  }

  @override
  void addEventListener(WindowRecordListener listener) {
    _listeners.add(listener);
  }
}
