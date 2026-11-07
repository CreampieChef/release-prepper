import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../service/images/masonry.dart';
import '../image_tile.dart';
import '../release/release.dart';
import '../release/release_type.dart';
import 'photosets_controller.dart';

/// The parts the two widgets that show a photoset share (`ai/picking.md` §7): the
/// state the run and the pictures read, the strings resolved per type, one set as
/// it is laid out, the line naming it, and the tile showing one photo the rule
/// picked. `PhotosetBlock` and `PhotosetGallery` are in two files, so these are
/// package-private: a private helper in one file cannot be read from the other.

// The name line under a tile, with the gap above it. The packing counts it,
// because a tile is the image and the name together, and it is a fixed height
// rather than a share of the column width.
const photosetLabelHeight = 20.0;

// The space between two tiles, which is the padding inside each one.
const photosetTileGap = 8.0;

// The line naming a set, with the space above and below it. The packing counts
// it, because a group is its line and its photos stacked, and the height of a
// group is what decides which column it goes to.
const photosetHeaderHeight = 24.0;

// The width a tile is laid out at when the page has given the section no columns,
// which is the single photoset's whole-width masonry. Only that grid uses this:
// the pack's grid lays its own columns out, at the widths below.
const photosetTileWidth = 160.0;

// The narrowest and the widest a column of the pack's grid may be
// (`ai/picking.md` §7). The number of columns is as many as fit at the narrowest,
// so a grid is as dense as the minimum allows, and each column is drawn at the
// share of the space but never wider than the widest — so with fewer sets than the
// space has room for columns, or a space too narrow for both numbers, the extra is
// left unused rather than a column being made wider or narrower than these say.
// These are the two numbers to change when the pack's layout is being tried at a
// different density; the gap between the columns is the page's, and is the shared
// `columnGap`.
const photosetColumnMin = 180.0;
const photosetColumnMax = 200.0;

/// The state the block and the gallery read: the controller both use, and the
/// generation the pictures are keyed with. For a pack the two are separate
/// widgets in two grid cells, so the run that writes the files and the pictures
/// that show them cannot be one widget's state, and the generation cannot be one
/// widget's counter — the editor, which places both, holds this (`AGENTS.md` §5).
class PhotosetState {
  PhotosetState({required this.controller});

  final PhotosetController controller;

  /// Changes on each run that wrote files, so a photo written under the same name
  /// is re-resolved against the emptied cache — `AGENTS.md` §5. Re-picking writes
  /// the same names, which is the case the poster does not have.
  int generation = 0;

  /// What a run wrote. The cache entry for each file is dropped here, because
  /// evicting alone is not enough: the widget that shows the picture must also
  /// re-resolve, and it does when the editor builds again with the generation
  /// this recorded. A run that wrote nothing changes nothing, so nothing is
  /// evicted and the generation stays.
  void recordRun(List<String> paths) {
    if (paths.isEmpty) return;

    evictCachedImages(paths);
    generation += 1;
  }
}

/// The strings this feature shows for the release type it is showing
/// (`ai/single_photoset.md` §4). They assume several sets, so they read wrong for
/// one, and they are resolved per type as `fieldLabel` is. The Scan and Pick
/// buttons, the count line and the report lines are not here: they say the same
/// thing for one set as for many.
class PhotosetStrings {
  const PhotosetStrings({
    required this.blockTitle,
    required this.photosTitle,
    required this.emptyText,
    required this.pickHint,
  });

  /// The heading of the data block: the line that names the folder the user
  /// picked and the counts the scan took from it.
  final String blockTitle;

  /// The title of the area that shows the picked photos. For a pack it is the key
  /// the Screenshots section titles itself with, because what a pack shows is the
  /// pictures rather than the list of sets, and the two areas show the same files
  /// the same way, so they use the same word. For a single photoset there is no
  /// area apart from the block, so it is the same word as the block's
  /// (`ai/picking.md` §7).
  final String photosTitle;

  final String emptyText;

  /// What the block says when the user asks it to pick before the source has been
  /// picked.
  final String pickHint;
}

PhotosetStrings photosetStrings(
  ReleaseType releaseType,
  AppLocalizations l10n,
) => switch (releaseType) {
  ReleaseType.photosetPack => PhotosetStrings(
    blockTitle: l10n.photosetPackSectionTitle,
    photosTitle: l10n.screenshotsSectionTitle,
    emptyText: l10n.photosetPackNoPhotosets,
    pickHint: l10n.photosetPackSourceEmpty,
  ),
  ReleaseType.singlePhotoset => PhotosetStrings(
    blockTitle: l10n.singlePhotosetSectionTitle,
    photosTitle: l10n.singlePhotosetSectionTitle,
    emptyText: l10n.singlePhotosetNoPhotosets,
    pickHint: l10n.singlePhotosetSourceEmpty,
  ),
  // Only here because a switch over the release types has to be exhaustive: these
  // have the Screenshots section, the Video pack section and the Image folder
  // section, so they never reach it.
  ReleaseType.singleVideo ||
  ReleaseType.videoPack ||
  ReleaseType.imageFolderUpload => PhotosetStrings(
    blockTitle: l10n.photosetPackSectionTitle,
    photosTitle: l10n.photosetPackSectionTitle,
    emptyText: l10n.photosetPackNoPhotosets,
    pickHint: l10n.photosetPackSourceEmpty,
  ),
};

/// One photoset as the feature lays it out: the item, the photos the rule picked
/// for it in the order the source gives them, and the ratio each of those has.
class PhotosetGroup {
  const PhotosetGroup({
    required this.item,
    required this.paths,
    required this.ratios,
  });

  final ReleaseItem item;
  final List<String> paths;
  final List<double?> ratios;
}

/// Reads one set as the feature lays it out. The ratios are read here because both
/// grids need them before they draw, and a photo whose header cannot be read is the
/// null that lays out as a square (`ai/picking.md` §7).
PhotosetGroup photosetGroup(PhotosetState state, ReleaseItem item) {
  final paths = state.controller.pickedPhotos(item.path);

  return PhotosetGroup(
    item: item,
    paths: paths,
    ratios: [for (final path in paths) state.controller.aspectRatio(path)],
  );
}

/// The count a line shows. The model stores it as a string, so a value that is not
/// a number — a manifest edited by the user — is shown as it is, the same way the
/// size field shows a value it cannot format.
String photosetCountText(
  AppLocalizations l10n,
  PhotosetState state,
  ReleaseItem item,
) {
  final value = item.fields.value('photoCount');
  final count = int.tryParse(value);

  return count == null ? value : l10n.photosetPhotoCount(count);
}

/// The line naming one set: its name, the count the scan wrote, and the picked
/// count. Shared, because the block and the grid both draw it. The key is the one
/// the caller gives: for a pack the same set is named twice — in the block and
/// above its column — so the two lines cannot carry the key the model gives them
/// (`ai/picking.md` §7).
Widget photosetLine(
  BuildContext context,
  AppLocalizations l10n,
  PhotosetState state,
  PhotosetGroup group,
  Key key,
) {
  final theme = Theme.of(context);

  return Row(
    // The key is the item's path, not the name it is shown under: two items whose
    // display names collide are still two sets (§5.3).
    key: key,
    children: [
      Expanded(
        child: Text(
          state.controller.displayName(group.item.path),
          style: theme.textTheme.bodyMedium,
        ),
      ),
      Text(
        photosetCountText(l10n, state, group.item),
        style: theme.textTheme.bodySmall,
      ),
      // The picked number comes from the records that exist, so it appears only
      // after a pick: the feature shows what is on disk.
      if (group.paths.isNotEmpty)
        Text(
          l10n.photosetPickedCount(group.paths.length),
          style: theme.textTheme.bodySmall,
        ),
    ],
  );
}

/// One picked photo as the app shows it, in the box the packing worked out for it,
/// which is its own ratio, so nothing is cropped.
Widget photosetTile(PhotosetState state, String path, double pictureHeight) =>
    Padding(
      padding: EdgeInsets.all(photosetTileGap / 2),
      child: ImageTile(
        path: path,
        height: pictureHeight,
        picture: imageFromFile(path, state.generation, fit: BoxFit.cover),
      ),
    );

/// The picked photos of one set as the plain masonry (`ai/picking.md` §7): columns
/// of equal width, each photo placed where its column is free, and a photo clearly
/// wider than it is tall spanning two columns. A photo whose header could not be
/// read takes a square tile.
///
/// This is the shape for a single photoset, which is the whole width below the form
/// and is read at that width, so it fits its own columns rather than being given
/// the page's. A tile that spans two columns cannot be a child of one column, so
/// the grid is placed by position rather than by nesting, and the positions come
/// from the pure function.
Widget photosetMasonry(
  BuildContext context,
  AppLocalizations l10n,
  PhotosetState state,
  PhotosetGroup group,
) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : photosetTileWidth * 3;

      // At least one column. Each column is at least the tile width, so the
      // number of columns is bounded by the space there is, and no cap is
      // needed. With one column nothing can span.
      final columnCount = width >= photosetTileWidth
          ? width ~/ photosetTileWidth
          : 1;
      final columnWidth = width / columnCount;

      final tiles = masonryPositions(
        ratios: group.ratios,
        columnCount: columnCount,
        columnWidth: columnWidth,
        labelHeight: photosetLabelHeight,
        gap: photosetTileGap,
      );

      var gridHeight = 0.0;

      for (final tile in tiles) {
        final bottom =
            tile.top + tile.height + photosetLabelHeight + photosetTileGap;

        if (bottom > gridHeight) {
          gridHeight = bottom;
        }
      }

      return SizedBox(
        height: gridHeight,
        child: Stack(
          children: [
            for (final tile in tiles)
              Positioned(
                left: tile.column * columnWidth,
                top: tile.top,
                width: tile.span * columnWidth,
                height: tile.height + photosetLabelHeight + photosetTileGap,
                child: photosetTile(
                  state,
                  group.paths[tile.index],
                  tile.height,
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// The picked photos as the pack's grid (`ai/picking.md` §7): one column per set,
/// its photos stacked in that column at one width, and the sets placed in the
/// column that is highest up when each is placed — so a set that does not fit
/// continues below the sets already in a column, and nothing is cropped. The line
/// naming the set is above its photos, because a column of pictures has to say
/// which set they are from.
///
/// The columns are the grid's own: as many as fit at `photosetColumnMin`, each
/// drawn at the share of the space but never more than `photosetColumnMax`, with
/// the page's gap between them. What is left when the share is more than the cap is
/// unused, rather than a column being made wider or narrower than the two say.
/// Their number is capped at the number of groups: a column with no group in it is
/// not a column the grid has, and a set the app could not read still takes its
/// column with its line and nothing under it.
Widget photosetGroupGrid(
  BuildContext context,
  AppLocalizations l10n,
  PhotosetState state,
  List<PhotosetGroup> groups,
) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : photosetColumnMin;

      final columns = math.max(
        math.min(
          photoColumnCount(
            width: width,
            min: photosetColumnMin,
            gap: columnGap,
          ),
          groups.length,
        ),
        1,
      );

      final columnWidth = photoColumnWidth(
        width: width,
        columnCount: columns,
        max: photosetColumnMax,
        gap: columnGap,
      );

      final assignment = groupColumns(
        groupHeights: [
          for (final group in groups)
            groupHeight(
              group.ratios,
              columnWidth,
              photosetHeaderHeight,
              photosetLabelHeight,
              photosetTileGap,
            ),
        ],
        columnCount: columns,
      );

      final byColumn = [
        for (var column = 0; column < columns; column++)
          [
            for (var index = 0; index < groups.length; index++)
              if (assignment[index] == column) groups[index],
          ],
      ];

      return Row(
        // Drawn at the left: when the columns are at the cap the space that is left
        // over is not part of any column, so it is the empty area at the right of
        // the grid.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var column = 0; column < columns; column++) ...[
            if (column > 0) SizedBox(width: columnGap),
            SizedBox(
              width: columnWidth,
              child: photosetGroupColumn(
                context,
                l10n,
                state,
                column,
                byColumn[column],
                columnWidth,
              ),
            ),
          ],
        ],
      );
    },
  );
}

/// One column of the pack's grid: the groups placed in it, in the order the source
/// gives them, each as its line and then its photos stacked under it. The boxes are
/// the heights the packing worked with — the line, and each photo's name line and
/// picture at the column's width, with the gap — so what is drawn is what the
/// assignment placed. A column with nothing in it draws nothing, because an empty
/// column is not a column the page has.
Widget photosetGroupColumn(
  BuildContext context,
  AppLocalizations l10n,
  PhotosetState state,
  int column,
  List<PhotosetGroup> groups,
  double columnWidth,
) {
  var top = 0.0;

  final boxes = <Widget>[];

  for (final group in groups) {
    boxes.add(
      Positioned(
        left: 0,
        top: top,
        width: columnWidth,
        height: photosetHeaderHeight,
        child: photosetLine(
          context,
          l10n,
          state,
          group,
          ValueKey(('groupColumnHeader', column, group.item.path)),
        ),
      ),
    );

    top += photosetHeaderHeight;

    for (var index = 0; index < group.paths.length; index++) {
      final picture = pictureHeight(group.ratios[index], columnWidth);

      boxes.add(
        Positioned(
          key: ValueKey(('groupTile', group.paths[index])),
          left: 0,
          top: top,
          width: columnWidth,
          height: tileHeight(
            group.ratios[index],
            columnWidth,
            photosetLabelHeight,
            photosetTileGap,
          ),
          child: photosetTile(state, group.paths[index], picture),
        ),
      );

      // The tile's height already reserves its own padding, so the column
      // advances by exactly what was drawn.
      top += tileHeight(
        group.ratios[index],
        columnWidth,
        photosetLabelHeight,
        photosetTileGap,
      );
    }
  }

  return SizedBox(
    key: ValueKey(('photosetColumn', column)),
    height: top,
    child: Stack(children: boxes),
  );
}
