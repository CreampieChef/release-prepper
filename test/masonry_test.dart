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
  // A photo is placed at the ratio it has, so a tile is as wide as the columns
  // it takes and its height is that width divided by the ratio. A photo whose
  // header could not be read is laid out as a square.
  test('a photo is laid out at the ratio its column gives it', () {
    expect(pictureHeight(1.5, 100), 100 / 1.5);
    expect(pictureHeight(null, 100), 100);
  });

  // A span is as wide as the caller says, which is the number of columns the
  // two widths the feature gives derive; with the default it is two.
  test('a span is as many columns as the caller allows', () {
    final tiles = masonryPositions(
      ratios: [1.5],
      columnCount: 3,
      columnWidth: 100,
      labelHeight: 0,
      gap: 0,
      maxSpan: 3,
    );

    expect(tiles.single.span, 3);
    expect(tiles.single.height, 300 / 1.5);
  });

  // The grid's columns are the width the feature gives a portrait, and the
  // space is used up rather than leaving a strip at the right that is narrower
  // than a column, so a column is the share of the space (`ai/picking.md` §7).
  test('the number of columns is as many as fit at the width', () {
    // Eight fit in 1792, a ninth would need 1800, so each gets the share of the
    // space: 224, which is the width used up to.
    expect(photoColumnCount(width: 1792, min: 200), 8);
    expect(photoColumnWidth(width: 1792, columnCount: 8), 1792 / 8);
  });

  // A space narrower than the width can only hold one column, and that column
  // is the space itself: the number is what the width decides, so nothing is
  // left unused.
  test('a space narrower than the width is one column', () {
    expect(photoColumnCount(width: 199, min: 200), 1);
    expect(photoColumnWidth(width: 199, columnCount: 1), 199);
  });

  // How many columns a landscape takes is derived from the two widths rather
  // than being hard coded, so changing them changes the grid.
  test('a landscape takes the columns that make it its width', () {
    expect(photoSpanCount(portraitWidth: 200, landscapeWidth: 400), 2);

    // A grid can only be a whole number of columns wide, so a pair that is not
    // a whole multiple takes the nearest number.
    expect(photoSpanCount(portraitWidth: 200, landscapeWidth: 300), 2);
    expect(photoSpanCount(portraitWidth: 200, landscapeWidth: 250), 1);

    // A landscape narrower than one portrait column is one column.
    expect(photoSpanCount(portraitWidth: 200, landscapeWidth: 100), 1);
  });

  // The pack's grid is split by kind, and the counts decide the columns each
  // kind gets (`ai/picking.md` §7). The two widths here are the ones the
  // feature gives, so the test is the rule the drawing follows.
  test('a kind with no photos has no zone', () {
    // All landscape: no column is spent on a kind with nothing to show.
    final zones = photoZoneColumnCounts(
      portraitPhotos: 0,
      landscapePhotos: 6,
      columnCount: 8,
      landscapeSpan: 2,
    );

    expect(zones!.portraitColumns, 0);
    expect(zones.landscapeColumns, 8);

    // The other way round: six portraits need six columns, so the two columns
    // that fit and are not needed are not used (`ai/picking.md` §7).
    final other = photoZoneColumnCounts(
      portraitPhotos: 6,
      landscapePhotos: 0,
      columnCount: 8,
      landscapeSpan: 2,
    );

    expect(other!.portraitColumns, 6);
    expect(other.landscapeColumns, 0);
  });

  // Few photos of one kind get the one column they need, and everything else
  // goes to the kind that has the photos to fill it.
  test('a small group of one kind gets one column', () {
    final zones = photoZoneColumnCounts(
      portraitPhotos: 1,
      landscapePhotos: 9,
      columnCount: 12,
      landscapeSpan: 2,
    );

    expect(zones!.portraitColumns, 1);
    expect(zones.landscapeColumns, 11);

    // A landscape's one column is the span, so a zone that has a landscape is
    // never narrower than that.
    final other = photoZoneColumnCounts(
      portraitPhotos: 9,
      landscapePhotos: 1,
      columnCount: 12,
      landscapeSpan: 2,
    );

    expect(other!.portraitColumns, 9);
    expect(other.landscapeColumns, 2);
  });

  // A zone is never given more columns than its photos need, so a grid with few
  // photos is as few columns as those photos fill rather than as many as fit
  // (`ai/picking.md` §7).
  test('a zone is not given more columns than its photos need', () {
    // Three portraits and one landscape: three columns and the span, which is
    // what the two together need, and the rest of the space is not used.
    final zones = photoZoneColumnCounts(
      portraitPhotos: 3,
      landscapePhotos: 1,
      columnCount: 10,
      landscapeSpan: 2,
    );

    expect(zones!.portraitColumns, 3);
    expect(zones.landscapeColumns, 2);

    // What a zone cannot take because it is already at its need goes to the
    // other: the proportion alone gives the landscape zone three, which is more
    // than its one photo fills, so the one it cannot take goes to the
    // portraits.
    final other = photoZoneColumnCounts(
      portraitPhotos: 3,
      landscapePhotos: 1,
      columnCount: 5,
      landscapeSpan: 2,
    );

    expect(other!.portraitColumns, 3);
    expect(other.landscapeColumns, 2);
  });

  // A space that cannot hold a column of both kinds is not split, and the
  // photos are laid out as one grid instead (`ai/picking.md` §7).
  test('a space that cannot hold both kinds is not split', () {
    expect(
      photoZoneColumnCounts(
        portraitPhotos: 4,
        landscapePhotos: 4,
        columnCount: 2,
        landscapeSpan: 2,
      ),
      isNull,
    );

    // One portrait column and one landscape column is the least that can be
    // given, and at that number the split is exactly that.
    final zones = photoZoneColumnCounts(
      portraitPhotos: 4,
      landscapePhotos: 4,
      columnCount: 3,
      landscapeSpan: 2,
    );

    expect(zones!.portraitColumns, 1);
    expect(zones.landscapeColumns, 2);
  });

  // The share of the space is what a column is drawn at, and the feature gives
  // the pack a bound so a zone capped at its photos does not make a column as
  // wide as the whole area (`ai/picking.md` §7).
  test('the share of the space is bounded by the maximum the feature gives', () {
    // Without a bound the share is the whole width divided by the columns.
    expect(photoColumnWidth(width: 1800, columnCount: 3), closeTo(600, 0.01));

    // With the bound, the columns are drawn at it and the width they cannot use
    // is left at the right.
    expect(
      photoColumnWidth(width: 1800, columnCount: 3, maxWidth: 400),
      closeTo(400, 0.01),
    );

    // A share below the bound is the share, because the bound is a maximum.
    expect(
      photoColumnWidth(width: 1600, columnCount: 8, maxWidth: 400),
      closeTo(200, 0.01),
    );
  });
}
