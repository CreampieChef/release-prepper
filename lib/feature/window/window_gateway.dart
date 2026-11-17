import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import 'window_record.dart';
import 'window_size.dart';

/// The point the app records the window at: the window's events, and the close.
///
/// A value says what changed, not what the window is now: the plugin reports
/// the window after the change, so the record is read with `currentRecord()`.
/// What a value means for the record is what `WindowController.record` decides,
/// and `ai/doc.md` §7 is the rule for it.
enum WindowEvent {
  /// The window's size changed. While the window is not maximized this is the
  /// size the user chose by dragging, which is what the record's size half is
  /// for, so a size change is recorded as it happens.
  resized,

  /// The window became maximized. The size it has then is the size the desktop
  /// gave it, not one the user chose.
  maximized,

  /// The window stopped being maximized. The size it has at that point is the
  /// size the desktop chose to restore it to, which is not necessarily the size
  /// the record holds — so the record keeps the size it had, and the window is
  /// asked for it (`requestSize`).
  unmaximized,

  /// The app is closing for real. This is not an event the gateway reports: the
  /// close flow confirms with the user first, so the record is written from the
  /// flow, and this is the value it writes it with.
  closed,
}

/// Called at the points the app records the window.
///
/// It is a callback rather than a listener interface, because the window
/// feature has no widget and `WindowListener` is a mixin meant for one
/// (`ai/doc.md` §4 rule 2). It returns a `Future` so the caller that registers
/// it can await the write it starts; the plugin itself cannot, and does not.
typedef WindowRecordListener = Future<void> Function(WindowEvent event);

/// The window itself: the record the app keeps of it, read from the window.
///
/// It is an interface because the plugin is a method channel and cannot be
/// exercised in a test, the same reason `SecretStore` is one (rule 4): the
/// feature is tested against a fake, and the plugin instance comes from the
/// composition root rather than being built here.
///
/// The record is applied by the runners before the window is created, because a
/// size asked for after the window exists is a request the desktop may ignore,
/// and a window that is resized after it appears is a jump the user sees. So
/// the app reads the window and is told when it changes, and asks for a size at
/// the one point where asking is what the record needs — `requestSize`.
abstract class WindowGateway {
  /// The record the window is now: its size, and whether it is maximized.
  Future<WindowRecord> currentRecord();

  /// Asks the window for `size`, in the units the plugin reports sizes in,
  /// which are the ones a read gives back — so a size the app reads is a size
  /// it can ask for again on the same platform. It is a request the desktop may
  /// ignore, and the plugin cannot say whether it was honoured, so nothing
  /// depends on the answer and nothing is reported for it. It is made at one
  /// point, the un-maximize, where the window may be at a size the record does
  /// not hold.
  Future<void> requestSize(WindowSize size);

  /// Registers `listener` for the window's events.
  void addEventListener(WindowRecordListener listener);
}

class PluginWindowGateway with WindowListener implements WindowGateway {
  PluginWindowGateway({required this.windowManager});

  final WindowManager windowManager;

  final List<WindowRecordListener> _listeners = [];

  @override
  Future<WindowRecord> currentRecord() async {
    final size = await windowManager.getSize();

    return WindowRecord(
      size: WindowSize(width: size.width.round(), height: size.height.round()),
      maximized: await windowManager.isMaximized(),
    );
  }

  @override
  Future<void> requestSize(WindowSize size) => windowManager.setSize(
    Size(size.width.toDouble(), size.height.toDouble()),
  );

  @override
  void addEventListener(WindowRecordListener listener) {
    // Registered for the first listener, so the same object is not put on the
    // plugin's list twice and the callback is not called twice for one event.
    if (_listeners.isEmpty) {
      windowManager.addListener(this);
    }

    _listeners.add(listener);
  }

  // The size change is reported twice by the plugin: while the window is being
  // dragged, and once at the end of the drag. Both are the same point for the
  // record, and the app writes it as the size changes, so both are forwarded.
  @override
  void onWindowResize() {
    _call(WindowEvent.resized);
  }

  @override
  void onWindowResized() {
    _call(WindowEvent.resized);
  }

  @override
  void onWindowMaximize() {
    _call(WindowEvent.maximized);
  }

  @override
  void onWindowUnmaximize() {
    _call(WindowEvent.unmaximized);
  }

  void _call(WindowEvent event) {
    for (final listener in _listeners) {
      listener(event);
    }
  }
}
