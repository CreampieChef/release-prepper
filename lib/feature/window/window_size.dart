/// The size the window has, in the units the toolkit reports it in, which are
/// the units the runner that applies it reads it back in (`ai/doc.md` §7).
///
/// The size half of `WindowRecord`, which is what the app keeps of the window.
/// It is a type of its own because a size has its own rule — a window is never
/// zero wide or zero tall, so a number outside that is not a size — and because
/// the two halves of the record mean different things: the size is what the
/// user chose by dragging, and the record's size stays that size when the
/// window is maximized (`ai/doc.md` §7).
class WindowSize {
  WindowSize({required this.width, required this.height});

  final int width;
  final int height;

  /// Whether this is a size the app can store and a runner can use. A window is
  /// never zero wide or zero tall, so a number outside that is not a size: it
  /// is not recorded, and it is not read.
  bool get isUsable => width > 0 && height > 0;

  @override
  bool operator ==(Object other) =>
      other is WindowSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}
