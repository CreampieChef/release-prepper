import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/service/images/masonry.dart';

void main() {
  // The label and the gap are set to zero here so the numbers are the tile
  // heights alone. The column width is 100, so a tile of one column is 100 wide
  // and its height is 100 / ratio.
  List<GridTile> place(List<double?> ratios, int columnCount) =>
      masonryPositions(
        ratios: ratios,
        columnCount: columnCount,
        columnWidth: 100,
        labelHeight: 0,
        gap: 0,
      );

  // GridTile is a value the test compares field by field, so the same input
  // placed twice gives the same list.
  List<List<Object?>> shape(List<GridTile> tiles) => [
    for (final tile in tiles)
      [tile.index, tile.column, tile.span, tile.top, tile.height],
  ];

  test('a photo clearly wider than it is tall spans two columns', () {
    final tiles = place([1.5], 2);

    expect(tiles.single.span, 2);
    expect(tiles.single.column, 0);
    expect(tiles.single.height, 200 / 1.5);
  });

  test('a portrait and a near-square take one column', () {
    // 1.1 is below the line, so it is not read as a landscape.
    expect(place([0.5], 2).single.span, 1);
    expect(place([1.1], 2).single.span, 1);
    expect(place([null], 2).single.span, 1);
  });

  // The Screenshots grid asks for this: every file there is a frame at the same
  // ratio, so spans would make every tile as wide as the grid and the grid
  // would be one column.
  test('a grid that may not span puts every photo in one column', () {
    List<GridTile> placeNoSpan(List<double?> ratios) => masonryPositions(
      ratios: ratios,
      columnCount: 2,
      columnWidth: 100,
      labelHeight: 0,
      gap: 0,
      maxSpan: 1,
    );

    expect(placeNoSpan([1.5]).single.span, 1);

    // Without spans the packing is the plain shortest column, so two landscapes
    // of the same height alternate.
    final tiles = placeNoSpan([1.5, 1.5]);

    expect(tiles[0].column, 0);
    expect(tiles[0].height, 100 / 1.5);
    expect(tiles[1].column, 1);
    expect(tiles[1].top, 0);
  });

  test('a span starts at the pair of columns that is highest up', () {
    // The portrait makes column 0 the lower point, so the landscape takes the
    // pair that is free.
    final tiles = place([0.5, 1.5, 1.5], 3);

    expect(tiles[0].column, 0);
    expect(tiles[0].top, 0);
    expect(tiles[0].height, 200);

    expect(tiles[1].column, 1);
    expect(tiles[1].top, 0);

    // Both columns of the span advance to the same point, so the second span
    // starts after the first.
    expect(tiles[2].column, 1);
    expect(tiles[2].top, 200 / 1.5);
  });

  test('the shorter column of a span keeps the gap it left, rather than being filled out of order', () {
    // The span cannot start before column 0 is free, so column 1 is empty until
    // that point.
    final tiles = place([0.5, 1.5], 2);

    expect(tiles[0].top, 0);
    expect(tiles[1].top, 200);
  });

  test('ties go to the lower column index', () {
    // Both pairs are at the same point at the start, so the first one is taken.
    expect(place([1.5, 1.5], 3)[0].column, 0);
  });

  test('nothing spans when there is only one column', () {
    expect(place([1.5, 1.5], 1).map((tile) => tile.span), [1, 1]);
  });

  test('the same input gives the same output twice', () {
    final ratios = [0.5, 1.5, 1.1, null, 1.5, 0.75];

    expect(shape(place(ratios, 3)), shape(place(ratios, 3)));
  });
}
