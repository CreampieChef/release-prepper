import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../service/images/masonry.dart';
import '../../service/photosets/photoset_picker.dart';
import '../image_tile.dart';
import '../release/release.dart';
import '../release/release_type.dart';
import '../screenshots/images.dart';
import 'photosets_controller.dart';

/// The parts the two widgets that show a photoset share (`ai/picking.md` §7):
///
/// the state the run and the pictures read, the strings resolved per type, one
///
/// set as it is laid out, and the tile showing one photo the rule picked.
///
/// `PhotosetBlock` and `PhotosetGallery` are in two files, so these are
///
/// package-private: a private helper in one file cannot be read from the other.

// The name line under a tile, with the gap above it. The packing counts it,
//
// because a tile is the image and the name together, and it is a fixed height
//
// rather than a share of the column width.
const photosetLabelHeight = 20.0;

// The space between two tiles, which is the padding inside each one.
const photosetTileGap = 8.0;

// The line naming the set a tile's photo is from, with the gap above it, at the
//
// style the tile draws it in. It is drawn only when the grid shows photos from
//
// more than one set, because a tile is a small area and its label line is the
//
// only place that can say which of them it is from, and a tile with one label
//
// has room for the file name only when there is nothing to tell apart
//
// (`ai/picking.md` §7).
const photosetSetLineHeight = 24.0;

// The width a portrait photo's column is, and the width a landscape's is
//
// (`ai/picking.md` §7): as many columns of the portrait width as fit in the
//
// space are drawn, and the space they cannot use is shared out rather than left
//
// as a strip at the right. A landscape takes as many of those columns as make
//
// it the landscape width, so the two numbers have to stay a whole multiple
//
// apart. These are the numbers to change when the grid is being tried at a
//
// different density; the columns have no gap of their own, because a spanned
//
// column must be exactly as many of them as these two say — the space between
//
// two tiles is the padding inside them.
const photosetColumnWidth = 200.0;
const photosetLandscapeWidth = 400.0;

// The widest a column of this grid may be stretched to: twice the portrait
//
// width. A zone capped at the columns its photos need cannot always use the
//
// whole space, and past this the space is left at the right rather than a
//
// column being made wider (`ai/picking.md` §7). The share is bounded because
//
// the grid is split by kind, and both photoset types split it, so both are
//
// bounded the same way.
const photosetColumnMaxWidth = 2 * photosetColumnWidth;

// The widest the block's column is. The width it does not use is the photo
//
// area's, so the cap does not leave an empty strip beside the block
//
// (`ai/picking.md` §7).
const photosetBlockMaxWidth = 400.0;

/// The state the block and the gallery read: the controller both use, the
///
/// generation the pictures are keyed with, and the records the run in progress
///
/// has written. The two are separate widgets in two grid cells for both
///
/// photoset types, so the run that writes the files and the pictures that show
///
/// them cannot be one widget's state, and neither the generation nor what a run
///
/// has written can be one widget's counter — the editor, which places both,
///
/// holds this (`AGENTS.md` §5).
class PhotosetState {
  PhotosetState({required this.controller});

  final PhotosetController controller;

  /// Changes on each run that wrote files, so a photo written under the same
  ///
  /// name is re-resolved against the emptied cache — `AGENTS.md` §5. Re-picking
  ///
  /// writes the same names, which is the case the poster does not have.
  int generation = 0;

  /// What the run in progress has written. A photo is shown as it is written,
  ///
  /// so the cache entry for its path is dropped and the generation moves at
  ///
  /// that moment rather than at the end of the run — the same rule the
  ///
  /// Screenshots section follows. It is cleared when the run ends, because from
  ///
  /// then on the manifest is what the two widgets read.
  final List<ImageRecord> running = [];

  void recordCopy(ImageRecord record) {
    // The thumbnail is rewritten under the same name too, so the rule covers it
    //
    // as well: both paths are emptied, and the picture is keyed with this
    //
    // generation so it resolves against the empty cache (`AGENTS.md` §5).
    final photo = controller.absolutePath(record);

    evictCachedImages([photo, controller.thumbnailPath(photo)]);

    running.add(record);
    generation += 1;
  }

  /// The run is over: what it wrote is in `images.json`, so the records the two
  ///
  /// widgets read are the manifest's again.
  void endRun() {
    running.clear();
  }
}

/// The strings this feature shows for the release type it is showing
///
/// (`ai/single_photoset.md` §4). They assume several sets, so they read wrong
///
/// for one, and they are resolved per type as `fieldLabel` is. The Scan and
///
/// Pick buttons, the count line and the report lines are not here: they say the
///
/// same thing for one set as for many.
class PhotosetStrings {
  const PhotosetStrings({
    required this.blockTitle,
    required this.photosTitle,
    required this.pickHint,
    required this.pickProgress,
    this.scanProgress,
    this.strategyChoices,
  });

  /// The heading of the data block: the line that names the folder the user
  ///
  /// picked and the counts the scan took from it.
  final String blockTitle;

  /// The title of the area that shows the picked photos. It is the key the
  ///
  /// Screenshots section titles itself with, for both photoset types: what the
  ///
  /// area shows is the pictures rather than what the block names, and the two
  ///
  /// areas show the same files the same way, so they say the same word. The
  ///
  /// heading of the block names the block, so it stays the word each type reads
  ///
  /// right for one set or for several (`ai/picking.md` §7).
  final String photosTitle;

  /// What the block says when the user asks it to pick before the source has
  ///
  /// been picked.
  final String pickHint;

  /// The words for a run's progress, with the two numbers it reports. The pick
  ///
  /// counts photos, which is the same measure for one set as for many, so it is
  ///
  /// one set of words. The scan counts the sets the scan found, and that is
  ///
  /// only a count for the type that has a list: for the type whose item is one
  ///
  /// folder the scan has one item, so a row counting it says nothing and is
  ///
  /// null there, and the block draws nothing (`ai/picking.md` §7).
  final String Function(int done, int total) pickProgress;
  final String Function(int done, int total)? scanProgress;

  /// The choices the strategy row offers, each with the label it has, in the
  ///
  /// order the row lists them. Only a pack has a choice: the two strategies
  ///
  /// differ in what the count is divided across, and for the type with one set
  ///
  /// the whole pack is that set, so the two answers are the same and there is
  ///
  /// nothing to choose. It is null for that type and the popup draws nothing
  ///
  /// (`ai/picking.md` §7, `ai/single_photoset.md` §6); the answer then carries
  ///
  /// the strategy the popup opens with, which is what both answers give for one
  ///
  /// set.
  final Map<PickStrategy, String>? strategyChoices;
}

PhotosetStrings photosetStrings(
  ReleaseType releaseType,
  AppLocalizations l10n,
) => switch (releaseType) {
  ReleaseType.photosetPack => PhotosetStrings(
    blockTitle: l10n.photosetPackSectionTitle,
    photosTitle: l10n.screenshotsSectionTitle,
    pickHint: l10n.photosetPackSourceEmpty,
    pickProgress: l10n.photosetPickProgress,
    scanProgress: l10n.photosetScanProgress,
    // Several sets, so the choice is a real one: the count can be divided
    //
    // across them or over the whole pack as one set, and the two give different
    //
    // picks. The order here is the order the row lists them.
    strategyChoices: {
      PickStrategy.perSet: l10n.pickStrategyPerSet,
      PickStrategy.wholePack: l10n.pickStrategyWholePack,
    },
  ),
  ReleaseType.singlePhotoset => PhotosetStrings(
    blockTitle: l10n.singlePhotosetSectionTitle,
    // The area shows the pictures, so it says the word the other area that
    //
    // shows the same files says (`ai/picking.md` §7).
    photosTitle: l10n.screenshotsSectionTitle,
    pickHint: l10n.singlePhotosetSourceEmpty,
    pickProgress: l10n.photosetPickProgress,
    // One item, so a row counting the items says nothing and the strings that
    //
    // assume several sets are not used here (`ai/picking.md` §7).
    scanProgress: null,
    // One set, so the whole pack is that set and the two strategies give the
    //
    // same picks: there is nothing to choose, so nothing is drawn
    //
    // (`ai/picking.md` §7, `ai/single_photoset.md` §6). The answer carries the
    //
    // strategy the popup opens with, which is what both answers give for one
    //
    // set.
    strategyChoices: null,
  ),
  // Only here because a switch over the release types has to be exhaustive:
  //
  // these have the Screenshots section, the Video pack section and the Image
  //
  // folder section, so they never reach it.
  ReleaseType.singleVideo ||
  ReleaseType.videoPack ||
  ReleaseType.imageFolderUpload => PhotosetStrings(
    blockTitle: l10n.photosetPackSectionTitle,
    photosTitle: l10n.photosetPackSectionTitle,
    pickHint: l10n.photosetPackSourceEmpty,
    pickProgress: l10n.photosetPickProgress,
    scanProgress: null,
    strategyChoices: null,
  ),
};

/// One photoset as the feature lays it out: the item, the photos the rule
///
/// picked for it in the order the source gives them, and the ratio each of
///
/// those has.
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

/// Reads the sets as the feature lays them out, in the order the scan wrote
///
/// them. The manifest is read once for the whole list rather than once per set,
///
/// because a run rebuilds the list for every set it has already read.
List<PhotosetGroup> photosetGroups(
  PhotosetState state,
  List<ReleaseItem> items,
) {
  final manifest = state.controller.store.loadSync(
    state.controller.release.directoryPath,
  );

  return [for (final item in items) photosetGroup(state, item, manifest)];
}

/// Reads one set as the feature lays it out: the photos the rule picked for it
///
/// in the order the source gives them, and the ratio each of those has. A photo
///
/// whose header cannot be read is the null that lays out as a square
///
/// (`ai/picking.md` §7). The records are the manifest's plus the ones the run
///
/// in progress has written. A run replaces the records it writes, so the two
///
/// are the same set at the end of it; while it runs what is already on disk
///
/// stays shown and each new photo is added as it is written, so a re-pick does
///
/// not blank the list while it works. They are keyed by the record path,
///
/// because that is the record ID and the same photo cannot be counted twice.
PhotosetGroup photosetGroup(
  PhotosetState state,
  ReleaseItem item,
  ImagesManifest manifest,
) {
  final paths = <String>{};

  for (final path in state.controller.pickedPhotos(manifest, item.path)) {
    paths.add(path);
  }

  for (final record in state.running) {
    if (record.item == item.path) {
      paths.add(state.controller.absolutePath(record));
    }
  }

  final ordered = [for (final path in paths) path];

  return PhotosetGroup(
    item: item,
    paths: ordered,
    ratios: [for (final path in ordered) state.controller.aspectRatio(path)],
  );
}

/// One picked photo as the app shows it, in the box the packing worked out for
///
/// it, which is its own ratio, so nothing is cropped. `setName` is the line
///
/// naming the set the photo is from, which only a grid mixing sets draws
///
/// (`ai/picking.md` §7). The picture is the run's thumbnail when that file is
///
/// on disk, and the photo itself when it is not (`ai/picking.md` §8). The tile
///
/// is still the photo's: its key and the name under it are the photo's, not the
///
/// thumbnail's, because the tile is the record and the thumbnail is only how
///
/// the record is drawn. A tile that takes the fallback path is a photo the run
///
/// skipped or could not write, and the same rule as the image boxes applies:
///
/// only a file that is there is shown.
Widget photosetTile(
  PhotosetState state,
  String path,
  double pictureHeight, {
  String? setName,
}) {
  final picture = state.controller.thumbnailOnDisk(path) ?? path;

  return Padding(
    padding: EdgeInsets.all(photosetTileGap / 2),
    child: ImageTile(
      path: path,
      height: pictureHeight,
      groupLabel: setName,
      picture: imageFromFile(picture, state.generation, fit: BoxFit.cover),
    ),
  );
}

/// One photo in the grid: the set it is from and which of that set's photos it
///
/// is. The grid is the photos of every set together, in the order the source
///
/// gives the sets and, within a set, the order it gives the photos, so a tile
///
/// is not part of one set's stack (`ai/picking.md` §7).
class _GridPhoto {
  const _GridPhoto({required this.group, required this.index});

  final PhotosetGroup group;
  final int index;

  String get path => group.paths[index];
}

/// One zone of the grid: the photos of one kind and the columns that zone has,
///
/// counted from the column the zone starts at, so the drawing places the zones
///
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
/// The grid is split by kind (`ai/picking.md` §7): the counts decide the
/// columns each kind gets, a kind with no photos has none, and a zone is not
/// given more than its photos need. The zones are drawn side by side, portraits
/// first, each starting at the top of the area, and a kind is packed inside its
/// own zone, so a tile cannot cross into the other kind's columns. The grid is
/// the one zone that is the whole space when the space cannot hold a column of
/// both kinds, or when only one kind of photo is present.
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

      // The set line is only drawn where the grid mixes sets: a grid with one
      //
      // set has nothing to tell apart, so its tiles keep one label line.
      final showSet = groups.length > 1;
      final labelHeight =
          photosetLabelHeight + (showSet ? photosetSetLineHeight : 0);

      // The zones, in the order they are drawn: portraits first, then
      //
      // landscapes, which is what `ai/picking.md` §7 says. With one kind, or
      //
      // with a space that cannot hold a column of both, there is no split and
      //
      // the grid is the one zone that is the whole space.
      final zones = <_PhotoZone>[];
      final fit = photoColumnCount(width: width, min: photosetColumnWidth);

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
        maxWidth: photosetColumnMaxWidth,
      );

      // Each kind is packed inside its own zone, so a tile is never placed in
      //
      // the other kind's columns, and the height the grid takes is the tallest
      //
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
