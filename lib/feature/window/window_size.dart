import '../release/release.dart';

/// The size the window had at the end of the last run, in the units the toolkit
/// reports it in, which are the units the runner that applies it reads it back
/// in (`ai/doc.md` §7).
///
/// It is a record of what the window was, not a value the user chooses on the
/// settings page, so it lives in a file of its own rather than as a key inside
/// `settings.json` — the same distinction `recent_releases.json` is made for.
///
/// Size only. Position is not recorded, because the app has one window and the
/// size is what the user chose by dragging; the desktop may restore the
/// position on its own, and a second rule for it would be a second source of
/// the same thing.
///
/// The file is one line of three whole numbers rather than JSON because the
/// Linux and Windows runners read it before the window is created, and a C
/// runner has no reader for this app's JSON files. Adding a JSON library to
/// parse two numbers would be a dependency for nothing.
class WindowSize {
  WindowSize({required this.width, required this.height});

  final int width;
  final int height;

  /// Whether this is a size the app can store and a runner can use. A window is
  /// never zero wide or zero tall, so a number outside that is not a size: it
  /// is not recorded, and it is not read.
  bool get isUsable => width > 0 && height > 0;

  /// The line the file is one of: the format version, the width, the height.
  String encode() => '$schemaVersion $width $height';

  /// A line that is not three whole numbers is read as nothing, and so is a
  /// version this app does not write, and a size that is not usable — this is a
  /// file the app writes rather than one the user edits. The runners follow the
  /// same rules (`ai/doc.md` §7), so a file one reader rejects is rejected by
  /// the other.
  static WindowSize? decode(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));

    if (parts.length != 3 || parts[0] != '$schemaVersion') {
      return null;
    }

    final width = _whole(parts[1]);
    final height = _whole(parts[2]);

    if (width == null || height == null) {
      return null;
    }

    final size = WindowSize(width: width, height: height);

    return size.isUsable ? size : null;
  }

  @override
  bool operator ==(Object other) =>
      other is WindowSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// A token is a whole number, or the line is not one this app wrote. `1440.5`
/// is not read as `1440`, the same rule the runners follow.
int? _whole(String token) => int.tryParse(token);
