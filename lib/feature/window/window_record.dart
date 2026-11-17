import '../release/release.dart';

import 'window_size.dart';

/// The record the app keeps of the window: the size, and whether the window was
/// maximized.
///
/// It is what `window_size.txt` holds, so the line is read as one thing rather
/// than as a size with an extra field. The two halves do not mean the same
/// thing and `ai/doc.md` §7 keeps them apart: the size is the last size the
/// window had while it was not maximized, which is the size the user chose by
/// dragging, and the state is how the window opens. A maximized window's size
/// is the size the desktop gave it, not a size the user chose, so it is not
/// what the record's size is for, and a state cannot be stored without a size
/// to go with it.
///
/// The line is four tokens rather than JSON because the Linux and Windows
/// runners read it before the window is created, and a C runner has no reader
/// for this app's JSON files.
class WindowRecord {
  WindowRecord({required this.size, required this.maximized});

  final WindowSize size;
  final bool maximized;

  /// The line the file is one of: the format version, the width, the height,
  /// the state.
  String encode() =>
      '$schemaVersion ${size.width} ${size.height} ${maximized ? 1 : 0}';

  /// A line that is not four whole numbers is read as nothing, and so is a
  /// version this app does not write, a size that is not usable, and a state
  /// that is not one of the two this app writes — this is a file the app writes
  /// rather than one the user edits. The runners follow the same rules
  /// (`ai/doc.md` §7), so a file one reader rejects is rejected by the other.
  static WindowRecord? decode(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));

    if (parts.length != 4 || parts[0] != '$schemaVersion') {
      return null;
    }

    final width = _whole(parts[1]);
    final height = _whole(parts[2]);
    final state = _whole(parts[3]);

    if (width == null || height == null || state == null) {
      return null;
    }

    final size = WindowSize(width: width, height: height);

    if (!size.isUsable || (state != 0 && state != 1)) {
      return null;
    }

    return WindowRecord(size: size, maximized: state == 1);
  }

  @override
  bool operator ==(Object other) =>
      other is WindowRecord &&
      other.size == size &&
      other.maximized == maximized;

  @override
  int get hashCode => Object.hash(size, maximized);
}

/// A token is a whole number, or the line is not one this app wrote. `1440.5`
/// is not read as `1440`, the same rule the runners follow.
int? _whole(String token) => int.tryParse(token);
