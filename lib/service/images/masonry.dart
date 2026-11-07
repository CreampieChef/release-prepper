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

/// How many columns of photos fit in [width] (`ai/picking.md` §7): as many as fit
/// at [min], so the columns are as narrow as the minimum allows. The caller caps
/// the number at the number of groups, because a column with no group in it is not
/// a column the grid has.
int photoColumnCount({
  required double width,
  required double min,
  required double gap,
}) => math.max(((width + gap) / (min + gap)).floor(), 1);

/// The width one of those columns is drawn at (`ai/picking.md` §7): the share of
/// [width], but never more than [max]. A space that cannot hold both is read as the
/// minimum rather than as less than it, because the number of columns is what the
/// minimum decides: when the share is bigger than [max] the column is drawn at the
/// cap and the rest of the space is left unused rather than a column being made
/// narrower than the minimum. The drawing and the assignment use this one width, so
/// they agree on it.
double photoColumnWidth({
  required double width,
  required int columnCount,
  required double max,
  required double gap,
}) => math.min((width - gap * (columnCount - 1)) / columnCount, max);

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

/// The height a group takes in a column: its header line and then its photos,
/// each at its full height with the gap that is its own padding. A group is
/// placed as one block, so its height
/// is what decides which column it goes to, and the assignment compares the height
/// as the drawing reserves it. A group with no photos is its header alone, because
/// a set the app could not read is still shown (`ai/picking.md` §7).
double groupHeight(
  List<double?> ratios,
  double columnWidth,
  double headerHeight,
  double labelHeight,
  double gap,
) =>
    headerHeight +
    ratios.fold(
      0.0,
      (total, ratio) =>
          total + tileHeight(ratio, columnWidth, labelHeight, gap),
    );

/// Which column each group's stack goes to, in the order the source gives the
/// groups (`ai/picking.md` §7): the column that is highest up when the group is
/// placed, ties to the lower column index, so the same input gives the same
/// output. The returned list is one entry per group, in the order the groups were
/// given.
///
/// This is the packing with groups rather than photos: photos from one group never
/// share a column with photos from another, so a group is placed whole, and no
/// photo spans — every tile in a group is the width of its column, whether the
/// photo is portrait or landscape.
List<int> groupColumns({
  required List<double> groupHeights,
  required int columnCount,
}) {
  final heights = List<double>.filled(columnCount, 0);
  final columns = <int>[];

  for (final height in groupHeights) {
    var column = 0;

    for (var candidate = 1; candidate < columnCount; candidate++) {
      if (heights[candidate] < heights[column]) {
        column = candidate;
      }
    }

    columns.add(column);
    heights[column] += height;
  }

  return columns;
}

/// The grid the section draws (`ai/picking.md` §7): columns of equal width,
/// each photo placed at the point where its column is free, each tile at the
/// ratio the photo has, so nothing is cropped. A photo clearly wider than it is
/// tall spans two columns, which is what makes a landscape read as a landscape
/// rather than as a small tile, unless [maxSpan] says the grid does not span.
///
/// A spanning tile can only start where both of its columns are free, so it
/// starts at the lower of the two and the other column has a gap until it is
/// level. That is not a shortcut: with spans the columns are no longer
/// independent stacks, and a packing that filled those gaps would put a photo
/// out of the order the source gives, which is the rule the section keeps. So
/// the gaps are left.
///
/// The heights are in pixels rather than relative, because a tile is its image
/// plus the name under it, and the name is a fixed height, not a share of the
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

    // A tile spans only as far as the caller allows. With maxSpan 1 this is the
    // plain shortest-column packing.
    final span = ratio >= landscapeSpanRatio && columnCount >= 2 && maxSpan >= 2
        ? 2
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
