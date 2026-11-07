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

// The line naming the set a tile's photo is from, with the gap above it, at the
// style the tile draws it in. It is drawn only when the grid shows photos from
// more than one set, which is the pack's, because with no grouping a tile has
// to say which set it is from (`ai/picking.md` §7). A single photoset has one
// set, which its block names above the photos, so its tiles keep one line.
const photosetSetLineHeight = 24.0;

// The width a portrait photo's column is, and the width a landscape's is
// (`ai/picking.md` §7): as many columns of the portrait width as fit in the
// space are drawn, and the space they cannot use is shared out rather than left
// as a strip at the right. A landscape takes as many of those columns as make
// it the landscape width, so the two numbers have to stay a whole multiple
// apart. These are the numbers to change when the grid is being tried at a
// different density; the columns have no gap of their own, because a spanned
// column must be exactly as many of them as these two say — the space between
// two tiles is the padding inside them.
const photosetColumnWidth = 200.0;
const photosetLandscapeWidth = 400.0;

// The widest a column of the pack's grid may be stretched to: twice the
// portrait width. A zone capped at the columns its photos need cannot always
// use the whole space, and past this the space is left at the right rather than
// a column being made wider (`ai/picking.md` §7). Only the pack bounds the
// share, because only the pack caps a zone at its photos: a single photoset
// uses the whole space as it is (`ai/single_photoset.md` §7).
const photosetColumnMaxWidth = 2 * photosetColumnWidth;

// The widest the block's column is. The width it does not use is the photo
// area's, so the cap does not leave an empty strip beside the block
// (`ai/picking.md` §7).
const photosetBlockMaxWidth = 400.0;

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
/// count. It is drawn once, in the block, because the grid no longer names a
/// set above its photos — the tile says which set its photo is from instead
/// (`ai/picking.md` §7).
Widget photosetLine(
  BuildContext context,
  AppLocalizations l10n,
  PhotosetState state,
  PhotosetGroup group,
) {
  final theme = Theme.of(context);

  return Row(
    // The key is the item's path, not the name it is shown under: two items whose
    // display names collide are still two sets (§5.3).
    key: ValueKey(('groupHeader', group.item.path)),
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

/// One picked photo as the app shows it, in the box the packing worked out for
/// it, which is its own ratio, so nothing is cropped. `setName` is the line
/// naming the set the photo is from, which only a grid mixing sets draws
/// (`ai/picking.md` §7).
Widget photosetTile(
  PhotosetState state,
  String path,
  double pictureHeight, {
  String? setName,
}) => Padding(
  padding: EdgeInsets.all(photosetTileGap / 2),
  child: ImageTile(
    path: path,
    height: pictureHeight,
    groupLabel: setName,
    picture: imageFromFile(path, state.generation, fit: BoxFit.cover),
  ),
);

/// One photo in the grid: the set it is from and which of that set's photos it
/// is. The grid is the photos of every set together, in the order the source
/// gives the sets and, within a set, the order it gives the photos, so a tile
/// is not part of one set's stack (`ai/picking.md` §7).
class _GridPhoto {
  const _GridPhoto({required this.group, required this.index});

  final PhotosetGroup group;
  final int index;

  String get path => group.paths[index];
}

/// One zone of the grid: the photos of one kind and the columns that zone has,
/// counted from the column the zone starts at, so the drawing places the zones
/// side by side (`ai/picking.md` §7).
class _PhotoZone {
  const _PhotoZone({
    required this.photos,
    required this.columns,
    required this.start,
  });

  /// The photos of this kind, in the order the source gives them.
  final List<_GridPhoto> photos;

  /// The columns this zone has, which its own photos are packed into.
  final int columns;

  /// The column the zone starts at, in the grid's base columns.
  final int start;
}

/// The picked photos as the grid draws them, at the two widths this file gives
/// (`ai/picking.md` §7): as many columns of `photosetColumnWidth` as fit in the
/// space, and the space the columns cannot use shared out rather than left as a
/// strip at the right. A photo clearly wider than it is tall takes the number
/// of columns that makes it `photosetLandscapeWidth` wide, which is what makes
/// a landscape read as a landscape; a photo whose header could not be read
/// takes a square tile.
///
/// For a pack the grid is split by kind (`ai/picking.md` §7): the counts decide
/// the columns each kind gets, a kind with no photos has none, and a zone is
/// not given more than its photos need. The zones are drawn side by side,
/// portraits first, each starting at the top of the area, and a kind is packed
/// inside its own zone, so a tile cannot cross into the other kind's columns. A
/// single photoset is not split (`ai/single_photoset.md` §7), so its photos are
/// the one zone that is the whole grid, and for a pack the grid is one zone too
/// when the space cannot hold a column of both kinds.
///
/// The columns have no gap of their own, because a spanned column must be
/// exactly as many of them as the two widths say: the space between two tiles
/// is the padding inside them.
///
/// A tile that spans cannot be a child of one column, so the grid is placed by
/// position rather than by nesting, and the positions come from the pure
/// function. A tile labels itself with its file name, and with the set it is
/// from when the grid has more than one set, because with no grouping a tile
/// has to say which set its photo is from.
Widget photosetPhotoGrid(PhotosetState state, List<PhotosetGroup> groups) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : photosetColumnWidth;

      final span = photoSpanCount(
        portraitWidth: photosetColumnWidth,
        landscapeWidth: photosetLandscapeWidth,
      );

      final photos = [
        for (final group in groups)
          for (var index = 0; index < group.paths.length; index++)
            _GridPhoto(group: group, index: index),
      ];

      // The set line is only drawn where the grid mixes sets, which is the
      // pack's: a single photoset's block names the one set above its photos.
      final showSet = groups.length > 1;
      final labelHeight =
          photosetLabelHeight + (showSet ? photosetSetLineHeight : 0);

      final isPack =
          state.controller.release.releaseType == ReleaseType.photosetPack;

      // The zones, in the order they are drawn: portraits first, then
      // landscapes, which is what `ai/picking.md` §7 says. With one kind, or
      // with a space that cannot hold a column of both, there is no split and
      // the grid is the one zone that is the whole space.
      final zones = <_PhotoZone>[];
      final fit = photoColumnCount(width: width, min: photosetColumnWidth);

      if (isPack) {
        final portrait = [
          for (final photo in photos)
            if (!isLandscape(photo.group.ratios[photo.index])) photo,
        ];
        final landscape = [
          for (final photo in photos)
            if (isLandscape(photo.group.ratios[photo.index])) photo,
        ];
        final split = photoZoneColumnCounts(
          portraitPhotos: portrait.length,
          landscapePhotos: landscape.length,
          columnCount: fit,
          landscapeSpan: span,
        );

        if (split != null) {
          zones.add(
            _PhotoZone(
              photos: portrait,
              columns: split.portraitColumns,
              start: 0,
            ),
          );
          zones.add(
            _PhotoZone(
              photos: landscape,
              columns: split.landscapeColumns,
              start: split.portraitColumns,
            ),
          );
        }
      }

      if (zones.isEmpty) {
        zones.add(_PhotoZone(photos: photos, columns: fit, start: 0));
      }

      var used = 0;

      for (final zone in zones) {
        used += zone.columns;
      }

      final columnWidth = photoColumnWidth(
        width: width,
        columnCount: used,
        maxWidth: isPack ? photosetColumnMaxWidth : null,
      );

      // Each kind is packed inside its own zone, so a tile is never placed in
      // the other kind's columns, and the height the grid takes is the tallest
      // of the zones, because they are drawn side by side.
      final grid = <Widget>[];
      var gridHeight = 0.0;

      for (final zone in zones) {
        final tiles = masonryPositions(
          ratios: [
            for (final photo in zone.photos) photo.group.ratios[photo.index],
          ],
          columnCount: zone.columns,
          columnWidth: columnWidth,
          labelHeight: labelHeight,
          gap: photosetTileGap,
          maxSpan: span,
        );

        for (final tile in tiles) {
          final photo = zone.photos[tile.index];
          final bottom = tile.top + tile.height + labelHeight + photosetTileGap;

          if (bottom > gridHeight) {
            gridHeight = bottom;
          }

          grid.add(
            Positioned(
              key: ValueKey(('photoTile', photo.path)),
              left: (zone.start + tile.column) * columnWidth,
              top: tile.top,
              width: tile.span * columnWidth,
              height: tile.height + labelHeight + photosetTileGap,
              child: photosetTile(
                state,
                photo.path,
                tile.height,
                setName: showSet
                    ? state.controller.displayName(photo.group.item.path)
                    : null,
              ),
            ),
          );
        }
      }

      return SizedBox(
        height: gridHeight,
        child: Stack(children: grid),
      );
    },
  );
}
