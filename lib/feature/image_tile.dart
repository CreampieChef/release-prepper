import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// One image as the app shows it: the picture with its file name centered under
/// it. Shared UI, because the Screenshots, Photosets and Video pack sections
/// show the same files the same way.
///
/// `showName` is false where the names are all the same shape — the small tiles
/// in a table row do not repeat them, because the row already names the item.
class ImageTile extends StatelessWidget {
  const ImageTile({
    required this.path,
    required this.picture,
    this.height,
    this.showName = true,
    super.key,
  });

  final String path;
  final Widget picture;

  /// The height of the bordered box, when the caller has worked one out — the
  /// masonry packing sizes each photo's box, so the box is that height and the
  /// picture is inside it. Without it the box is the size the picture takes.
  final double? height;

  final bool showName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(6);

    // Stretch, because the tile is shown inside a column that gives it its
    // width: the picture fills that width, whether it is an aspect ratio or a
    // box the caller sized itself.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: height,
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: radius,
          ),
          child: ClipRRect(borderRadius: radius, child: picture),
        ),
        if (showName) ...[
          const SizedBox(height: 4),
          Text(
            p.basename(path),
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// An image read from a file on disk, with the key that makes it re-resolve
/// when the app rewrites that file under the same name (`AGENTS.md` rule 5):
/// `Image` resolves its provider once and only re-resolves when the key
/// changes, and the key is the path, which is the same on a rewrite. The
/// generation is the widget's own counter, so it is passed in here rather than
/// held here.
///
/// `fit` and `alignment` are what the caller wants the picture to be inside the
/// box it is given: nothing is known about the image before it is decoded, so
/// the box is the caller's and the picture is fitted into it.
Widget imageFromFile(
  String path,
  int generation, {
  BoxFit? fit,
  Alignment? alignment,
}) => Image.file(
  File(path),
  key: ValueKey('$generation-$path'),
  fit: fit,
  alignment: alignment ?? Alignment.center,
  errorBuilder: (_, _, _) => const SizedBox.shrink(),
);

/// Drops the cached image for each file the app has just rewritten, so the
/// tiles that show them resolve against an empty cache. This is the other half
/// of the rule `imageFromFile` implements: evicting alone is not enough,
/// because an already-mounted `Image` keeps the stream it resolved the first
/// time. The two belong together, which is why they are in this file.
void evictCachedImages(List<String> paths) {
  for (final path in paths) {
    PaintingBinding.instance.imageCache.evict(FileImage(File(path)));
  }
}
