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

    final height = span * columnWidth / ratio;

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
      heights[covered] = top + height + labelHeight + gap;
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
