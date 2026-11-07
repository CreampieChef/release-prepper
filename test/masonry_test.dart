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

  // The pack's grid (`ai/picking.md` §7): a group is placed whole, so the column
  // is chosen from the height the group takes as a block — its header plus its
  // photos, each at the column's width. A photo is never wider than its column,
  // so a landscape is not a two-column tile here.
  test('a group takes the width of its column, at the ratio the photo has', () {
    expect(pictureHeight(1.5, 100), 100 / 1.5);

    // A photo whose header could not be read is laid out as a square.
    expect(pictureHeight(null, 100), 100);
  });

  test('the height a group takes is its header and its photos', () {
    // One photo at the column's width plus its name line, with the header above
    // them, and the gap after the photo: that is what the drawing reserves in the
    // column before the next group can start.
    expect(groupHeight([1.0], 100, 24, 20, 8), 24 + (100 + 20 + 8));

    // A set the app could not read is shown as its header alone.
    expect(groupHeight([], 100, 24, 20, 8), 24);
  });

  test('a group goes to the column that is highest up when it is placed', () {
    expect(groupColumns(groupHeights: [200, 60, 200, 100], columnCount: 3), [
      0,
      1,
      2,
      1,
    ]);
  });

  test('ties go to the lower column index', () {
    expect(groupColumns(groupHeights: [100, 100], columnCount: 2), [0, 1]);

    // A group with no photos is its header alone, and a column with nothing in it
    // is higher up than one with a group, so the header takes its column.
    expect(
      groupColumns(
        groupHeights: [groupHeight([], 100, 24, 20, 8), 124],
        columnCount: 2,
      ),
      [0, 1],
    );
  });

  // The name line is a fixed height rather than a share of the column width, so
  // the same groups can be placed differently in a window of a different width —
  // the same reason the masonry packing works in pixels.
  test('the assignment depends on the column width', () {
    // Two short photos of the same height against one tall one: at a wide column
    // the photos are what decide it, at a narrow one the name lines are.
    final wide = [
      groupHeight([4, 4], 100, 24, 20, 8),
      groupHeight([1.0], 100, 24, 20, 8),
      groupHeight([4, 4], 100, 24, 20, 8),
    ];

    expect(groupColumns(groupHeights: wide, columnCount: 2), [0, 1, 0]);

    final narrow = [
      groupHeight([4, 4], 20, 24, 20, 8),
      groupHeight([1.0], 20, 24, 20, 8),
      groupHeight([4, 4], 20, 24, 20, 8),
    ];

    expect(groupColumns(groupHeights: narrow, columnCount: 2), [0, 1, 1]);
  });

  test('the same groups give the same placement twice', () {
    final List<List<double?>> groups = [
      [0.5, null],
      [1.5],
      [],
      [0.75, 2.0],
    ];
    final heights = [
      for (final group in groups) groupHeight(group, 100, 24, 20, 8),
    ];

    // The three columns hold the first three groups, and the fourth is bigger
    // than any of them, so it goes to the one that is highest up: the one with
    // only a header in it.
    expect(groupColumns(groupHeights: heights, columnCount: 3), [0, 1, 2, 2]);
    expect(
      groupColumns(groupHeights: heights, columnCount: 3),
      groupColumns(groupHeights: heights, columnCount: 3),
    );
  });
}
