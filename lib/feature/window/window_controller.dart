import 'window_gateway.dart';
import 'window_record.dart';
import 'window_record_store.dart';

sealed class WindowRecordResult {
  const WindowRecordResult();
}

/// The record was written.
final class WindowRecordWritten extends WindowRecordResult {
  const WindowRecordWritten();
}

/// Nothing to write: the record is not one the app can store, or it is the
/// record already recorded. What is stored stays as it is.
final class WindowNothingToRecord extends WindowRecordResult {
  const WindowNothingToRecord();
}

/// `window_size.txt` could not be written.
final class WindowWriteFailed extends WindowRecordResult {
  const WindowWriteFailed();
}

/// Owns the record the app keeps of the window and writes it.
///
/// It has no widget, which is recorded as a deviation from rule 2 in
/// `ai/doc.md` §4: there is nothing it shows, so there is no widget to pair it
/// with. It is called from the close flow, which is the only place that knows
/// the app is closing for real, and from the window's events, which the
/// composition root registers on its `record` method — that is the whole
/// feature, so the provider entry is where the listener is attached.
///
/// It is not a `ChangeNotifier`, so rule 7 is intact: nothing observes it. It
/// holds no state, because the value it needs is the file: the record on disk
/// is the size the user chose by dragging, which is what the app writes
/// whenever it is told the window changed while it was not maximized. Nothing
/// is read at startup, because the app does not apply the record — the runners
/// do, before the window is created (`ai/doc.md` §7).
class WindowController {
  WindowController({required this.store, required this.gateway});

  final WindowRecordStore store;
  final WindowGateway gateway;

  /// Records the window as it is now, and writes the file when the record is
  /// one the app can store and not the record already recorded. The same record
  /// again is not a write, the same rule as the settings feature's.
  ///
  /// The size half is the size the user chose by dragging, so the size the
  /// window has is recorded when the window is not maximized, except at the
  /// un-maximize — there the size it has is the size the desktop chose to
  /// restore it to, so the size already recorded is kept and the window is
  /// asked for it, below. A maximized window reports the size the desktop gave
  /// it, which is not one the user chose, so the size stays the one already
  /// recorded and only the state changes. The one case that cannot be kept is a
  /// record with nothing in it yet, where the size the window has is the only
  /// size there is.
  ///
  /// A write that fails is reported rather than swallowed here, because the
  /// close must not depend on the write: the caller decides what to do with the
  /// answer, and at that point there is no widget left that could say a file
  /// was not written, so a failed write shows up on the next run — as a record
  /// the runners would have applied, and as the comparison this method makes.
  Future<WindowRecordResult> record(WindowEvent event) async {
    final recorded = await store.load();
    final current = await gateway.currentRecord();

    final chosen = event != WindowEvent.unmaximized && !current.maximized;

    final size = chosen && current.size.isUsable
        ? current.size
        : recorded?.size ?? current.size;

    if (!size.isUsable) {
      return const WindowNothingToRecord();
    }

    final record = WindowRecord(size: size, maximized: current.maximized);

    if (record == recorded) {
      return const WindowNothingToRecord();
    }

    try {
      await store.save(record);
    } catch (_) {
      return const WindowWriteFailed();
    }

    // At the un-maximize the window is at the size the desktop restored it to,
    // which is not the size the record holds unless the desktop happened to
    // choose the same one, so the app asks for the size the record holds. This
    // is the only point the app asks the window for a size, and the request may
    // be ignored — which is why the record was written first: the record is
    // what the app knows, and the request is what it would like the window to
    // be. Nothing can say whether the desktop honoured it, so nothing is
    // reported.
    if (event == WindowEvent.unmaximized && current.size != size) {
      await gateway.requestSize(size);
    }

    return const WindowRecordWritten();
  }
}
