import 'window_gateway.dart';
import 'window_size_store.dart';

sealed class WindowRecordResult {
  const WindowRecordResult();
}

/// The size was written.
final class WindowSizeRecorded extends WindowRecordResult {
  const WindowSizeRecorded();
}

/// Nothing to write: the size is not one the app can store, or it is the size
/// already recorded. What is stored stays as it is.
final class WindowNothingToRecord extends WindowRecordResult {
  const WindowNothingToRecord();
}

/// `window_size.txt` could not be written.
final class WindowWriteFailed extends WindowRecordResult {
  const WindowWriteFailed();
}

/// Owns the record the app keeps of the window size and writes it.
///
/// It has no widget, which is recorded as a deviation from rule 2 in
/// `ai/doc.md` §4: there is nothing it shows, so there is no widget to pair it
/// with. It is called from the close flow, which is the only place that knows
/// the app is closing for real, and it is the only place the feature is used
/// from.
///
/// It is not a `ChangeNotifier`, so rule 7 is intact: nothing observes it. It
/// has no state of its own either, and nothing is read at startup, because the
/// app does not apply a size — the runners do, before the window is created
/// (`ai/doc.md` §7).
///
/// The size is recorded once, at the end of a run, rather than as the window is
/// resized: that is the only point at which the app knows what the window was
/// for a whole run, and a drag is a stream of sizes whose last one cannot be
/// known before the window goes. What is recorded is the size the window had at
/// that point. The maximized state is not part of the record, so a window
/// closed maximized is remembered at the size it was maximized to — the app has
/// no way to know the size it had before maximizing.
class WindowController {
  WindowController({required this.store, required this.gateway});

  final WindowSizeStore store;
  final WindowGateway gateway;

  /// Records the size the window has now, and writes the file when it is a size
  /// the app can store and not the size already recorded. The same size again
  /// is not a write, the same rule as the settings feature's.
  ///
  /// A write that fails is reported rather than swallowed here, because the
  /// close must not depend on the write: the caller decides what to do with the
  /// answer, and at that point there is no widget left that could say a file
  /// was not written, so a failed write shows up on the next run — as a size
  /// the runners would have applied, and as the comparison this method makes.
  Future<WindowRecordResult> recordSize() async {
    final recorded = await store.load();
    final size = await gateway.currentSize();

    if (!size.isUsable || size == recorded) {
      return const WindowNothingToRecord();
    }

    try {
      await store.save(size);

      return const WindowSizeRecorded();
    } catch (_) {
      return const WindowWriteFailed();
    }
  }
}
