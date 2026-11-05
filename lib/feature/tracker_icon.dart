import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'release/tracker.dart';

/// The asset each tracker is drawn with. Add an entry per tracker here; the
/// renderer is chosen from the extension, so `.svg` and `.png` both work.
///
/// Reading an SVG is the one exception to the no-third-party-packages rule:
/// Flutter has no built-in SVG renderer, so this file is the only place
/// `flutter_svg` is used.
const trackerIconAssets = {Tracker.pornolab: 'assets/icons/pornolab.svg'};

/// The icon for a tracker, drawn at `size`. A tracker the app knows but has no
/// asset for shows a neutral placeholder rather than nothing, so a tracker
/// added to [Tracker] before its icon exists still renders a recognizable row
/// in the tab strip and the editor.
class TrackerIcon extends StatelessWidget {
  const TrackerIcon({super.key, required this.tracker, this.size = 24});

  final Tracker tracker;
  final double size;

  @override
  Widget build(BuildContext context) {
    final assetPath = trackerIconAssets[tracker];

    if (assetPath == null) {
      return Icon(Icons.circle, size: size);
    }

    if (assetPath.toLowerCase().endsWith('.svg')) {
      return SvgPicture.asset(assetPath, width: size, height: size);
    }

    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
