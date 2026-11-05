import 'package:flutter/material.dart';

/// The icon a hoster is drawn with, at `size`. An asset that is not there shows
/// a neutral placeholder rather than nothing, for the same reason `TrackerIcon`
/// does, so a hoster with no icon still renders a recognizable row.
///
/// The hoster icons are PNG, so this is `Image.asset` and not `flutter_svg`:
/// the SVG renderer is used only for the tracker icons
/// (`lib/feature/tracker_icon.dart`).
class HosterIcon extends StatelessWidget {
  const HosterIcon({super.key, required this.assetPath, this.size = 24});

  final String assetPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Icon(Icons.circle, size: size),
    );
  }
}
