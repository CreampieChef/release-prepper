import 'dart:math' as math;

/// A tile's place in the grid: the photo it is, in the order the source gives,
/// the column it starts in, how many columns it spans, and the y its top is at,
/// in pixels.
class GridTile {
  const GridTile({
    required this.index,
    required this.column,
    required this.span,
    required this.top,
    required this.height,
  });

  final int index;
  final int column;
  final int span;
  final double top;

  /// The height of the image itself. The name under it is not part of it, but
  /// it is counted in the packing, because a tile is the image and the name
  /// together.
  final double height;
}

/// A photo this much wider than it is tall takes two columns. Below it a photo
/// is near enough to a square that two columns would only make it a square
/// twice as wide, which is not what a landscape looks like. 1.2 is 6:5, so the
/// common 4:3, 3:2 and 16:9 are all above it.
const landscapeSpanRatio = 1.2;

/// Whether a photo is a landscape, and so takes the span (`ai/picking.md` §7):
/// the line the grid and the counts of each kind both use, so they agree on
/// what a zone is. A photo whose header could not be read is the square the
/// drawing lays it out as, and a square is not a landscape.
bool isLandscape(double? ratio) => (ratio ?? 1) >= landscapeSpanRatio;

/// The widest a tile may be, in columns. This is 2 wherever a landscape is
/// meant to read as one; the Screenshots section asks for 1 because every file
/// there is a frame at the same ratio, so spans would make every tile as wide
/// as the grid and the grid would be one column.
const defaultMaxSpan = 2;

/// The narrowest a column of the page may be. The number of columns is however
/// many of this width fit in the space there is, so the editor's grid and a
/// section's own columns agree on the same number: a section placed as the
/// columns after the form lays out exactly those columns.
const minColumnWidth = 430.0;

/// The gap between two columns of the page, and the gap a section draws between
/// its own columns so that they are the page's columns.
const columnGap = 24.0;

/// How many columns of photos fit in [width] (`ai/picking.md` §7): as many as
/// fit at [min], so the grid is as dense as the width allows. At least one: a
/// space narrower than [min] is the one column it is, rather than no column at
/// all. The columns are not separated by a gap of their own, because a spanned
/// column has to be exactly as many of them as the numbers say: the space
/// between two tiles is the padding inside them.
int photoColumnCount({required double width, required double min}) =>
    math.max(width ~/ min, 1);

/// The width one of those columns is drawn at (`ai/picking.md` §7): the share
/// of [width], which is [min] or more, so the space is used up rather than
/// leaving a strip at the right that is narrower than a column. The drawing and
/// the assignment use this one width, so they agree on it. [maxWidth] bounds
/// the share for the feature that gives one: a column is never stretched past
/// it, and the width the columns cannot use is left at the right
/// (`ai/picking.md` §7).
double photoColumnWidth({
  required double width,
  required int columnCount,
  double? maxWidth,
}) {
  final share = width / columnCount;

  return maxWidth == null ? share : math.min(share, maxWidth);
}

/// The two zones the pack's grid is split into (`ai/picking.md` §7): the
/// columns each kind of photo gets, counted in the grid's base columns. A kind
/// with no photos has no zone, so its count is 0.
class PhotoZones {
  const PhotoZones({
    required this.portraitColumns,
    required this.landscapeColumns,
  });

  final int portraitColumns;
  final int landscapeColumns;
}

/// The columns each zone gets (`ai/picking.md` §7), from the counts and the
/// columns that fit. A kind with no photos gets nothing, and a kind with photos
/// gets at least one column — for a landscape that is one of its own, so
/// [landscapeSpan] of them — and never more than its photos need, which is one
/// column per photo. What the two minimums do not take is shared in proportion
/// to the counts, and a zone that is already at what its photos need gives its
/// share to the other.
///
/// Returns null when the space cannot hold one column of both kinds, which is
/// when the grid is not split and the photos are laid out as one grid instead.
PhotoZones? photoZoneColumnCounts({
  required int portraitPhotos,
  required int landscapePhotos,
  required int columnCount,
  required int landscapeSpan,
}) {
  // What each kind needs, in base columns: one column per photo, and a
  // landscape's photo needs the span.
  final portraitNeed = portraitPhotos == 0 ? 0 : math.max(portraitPhotos, 1);
  final landscapeNeed = landscapePhotos == 0
      ? 0
      : math.max(landscapePhotos, 1) * landscapeSpan;

  final portraitMin = portraitPhotos == 0 ? 0 : 1;
  final landscapeMin = landscapePhotos == 0 ? 0 : landscapeSpan;

  // The columns that are used: as many as fit, never more than the two together
  // need, so a zone is not given columns its photos cannot fill.
  final used = math.min(columnCount, portraitNeed + landscapeNeed);

  if (used < portraitMin + landscapeMin) {
    return null;
  }

  if (portraitPhotos == 0 || landscapePhotos == 0) {
    return PhotoZones(
      portraitColumns: portraitPhotos == 0 ? 0 : used,
      landscapeColumns: landscapePhotos == 0 ? 0 : used,
    );
  }

  // The share of what the minimums do not take, in proportion to the counts.
  // Rounding down is what the proportion is, and a zone at its cap gives what
  // it cannot take to the other.
  final counts = portraitPhotos + landscapePhotos;
  var portrait =
      portraitMin +
      (used - portraitMin - landscapeMin) * portraitPhotos ~/ counts;
  var landscape = used - portrait;

  if (portrait > portraitNeed) {
    portrait = portraitNeed;
    landscape = used - portrait;
  }

  if (landscape > landscapeNeed) {
    landscape = landscapeNeed;
    portrait = used - landscape;
  }

  return PhotoZones(portraitColumns: portrait, landscapeColumns: landscape);
}

/// How many columns a landscape takes (`ai/picking.md` §7): the number that
/// makes a column [landscapeWidth] wide when a portrait's column is
/// [portraitWidth]. A grid can only be a whole number of columns wide, so when
/// the two are not a whole multiple apart this is the nearest whole number, and
/// a pair below one column is one column.
int photoSpanCount({
  required double portraitWidth,
  required double landscapeWidth,
}) => math.max((landscapeWidth / portraitWidth).round(), 1);

/// The height a photo takes in a column of this width: the image at the ratio it
/// has, plus the name line under it. The name line is a fixed height rather than
/// a share of the column width, which is why the packing works in pixels. A photo
/// whose header could not be read is laid out as a square.
/// The height the picture itself takes in a column of this width, at the ratio
/// the photo has. A photo whose header could not be read is laid out as a square.
double pictureHeight(double? ratio, double columnWidth) =>
    columnWidth / (ratio ?? 1);

/// The height a tile takes in a column of this width: the picture plus the name
/// line under it, with the gap that is the tile's own padding. The name line is
/// a fixed height rather than a share of the column width, which is why the
/// packing works in pixels. The caller reserves exactly this height per tile, so
/// the drawing and the assignment add the gap the same once.
double tileHeight(
  double? ratio,
  double columnWidth,
  double labelHeight,
  double gap,
) => pictureHeight(ratio, columnWidth) + labelHeight + gap;

/// The grid the section draws (`ai/picking.md` §7): columns of equal width,
/// each photo placed at the point where its column is free, each tile at the
/// ratio the photo has, so nothing is cropped. A photo clearly wider than it is
/// tall spans as many columns as [maxSpan] says, which is what makes a
/// landscape read as a landscape rather than as a small tile, unless [maxSpan]
/// says the grid does not span.
///
/// A spanning tile can only start where both of its columns are free, so it
/// starts at the lower of the two and the other column has a gap until it is
/// level. That is not a shortcut: with spans the columns are no longer
/// independent stacks, and a packing that filled those gaps would put a photo
/// out of the order the source gives, which is the rule the section keeps. So
/// the gaps are left.
///
/// The heights are in pixels rather than relative, because a tile is its image
/// plus the lines under it, and those are a fixed height, not a share of the
/// column width. So the assignment does depend on the column width, and a
/// resized window can lay the same photos out differently.
///
/// Ties go to the lower column index, so the same input gives the same output.
List<GridTile> masonryPositions({
  required List<double?> ratios,
  required int columnCount,
  required double columnWidth,
  required double labelHeight,
  required double gap,
  int maxSpan = defaultMaxSpan,
}) {
  final heights = List<double>.filled(columnCount, 0);
  final tiles = <GridTile>[];

  for (var index = 0; index < ratios.length; index++) {
    // A photo whose header could not be read is laid out as a square, and a
    // square is one column.
    final ratio = ratios[index] ?? 1;

    // A tile spans as far as the caller allows, and only as far as the grid has
    // columns for. With maxSpan 1 this is the plain shortest-column packing.
    final span =
        isLandscape(ratios[index]) && maxSpan >= 2 && columnCount >= maxSpan
        ? maxSpan
        : 1;

    var column = 0;
    var top = _lowestPoint(heights, 0, span);

    for (var candidate = 1; candidate + span <= columnCount; candidate++) {
      final point = _lowestPoint(heights, candidate, span);

      if (point < top) {
        column = candidate;
        top = point;
      }
    }

    final height = span * pictureHeight(ratio, columnWidth);

    tiles.add(
      GridTile(
        index: index,
        column: column,
        span: span,
        top: top,
        height: height,
      ),
    );

    // Every column the tile covers is occupied for the same band, so all of
    // them advance to the same point, and the columns stay level with each
    // other from there.
    for (var covered = column; covered < column + span; covered++) {
      heights[covered] =
          top + tileHeight(ratio, span * columnWidth, labelHeight, gap);
    }
  }

  return tiles;
}

/// The y a tile starting at `column` can be placed at: the point where every
/// column it covers is free, which is the lower of them.
double _lowestPoint(List<double> heights, int column, int span) {
  var point = 0.0;

  for (var covered = column; covered < column + span; covered++) {
    if (heights[covered] > point) {
      point = heights[covered];
    }
  }

  return point;
}
