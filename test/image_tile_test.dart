import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/feature/image_tile.dart';

void main() {
  // A tile is the picture and the lines under it, and the height the packing
  // reserves for it counts one line for each label (`ai/picking.md` §7). So a
  // label cannot take more than one line whatever the text is: two tiles at the
  // same width that differ only in the length of their text have to be the same
  // height, or the drawing is taller than the box the packing sized. The test
  // reads both tiles from one run, so it does not depend on what a line of the
  // label style measures.
  testWidgets('a label longer than the width the tile is drawn at is cut', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 600);
    tester.view.devicePixelRatio = 1.0;

    const short = 'p001.png';
    const long = 'IMG_2024-11-15_101530_original_export_version_2.png';

    Widget tile(String name) =>
        ImageTile(path: name, picture: const SizedBox(height: 100));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              KeyedSubtree(
                key: const ValueKey('short'),
                child: SizedBox(width: 200, child: tile(short)),
              ),
              KeyedSubtree(
                key: const ValueKey('long'),
                child: SizedBox(width: 200, child: tile(long)),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getRect(find.byKey(const ValueKey('long'))).height,
      closeTo(tester.getRect(find.byKey(const ValueKey('short'))).height, 0.5),
      reason:
          'the name line is one line, so a long name does not make the tile '
          'taller than the box the packing reserves',
    );

    // The whole name is still what the widget holds: only what is painted is
    // cut, so the feature that shows the name still has it.
    expect(find.text(long), findsOneWidget);
  });

  // The line naming the group is the same case, at the style the tile draws it
  // in, so it is cut rather than wrapped too.
  testWidgets('the line naming the group is cut too', (tester) async {
    tester.view.physicalSize = const Size(600, 600);
    tester.view.devicePixelRatio = 1.0;

    const shortGroup = 'set01';
    const longGroup = 'set01_with_a_name_longer_than_the_column_can_show';

    Widget tile(String group) => ImageTile(
      path: 'p001.png',
      groupLabel: group,
      picture: const SizedBox(height: 100),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              KeyedSubtree(
                key: const ValueKey('short'),
                child: SizedBox(width: 200, child: tile(shortGroup)),
              ),
              KeyedSubtree(
                key: const ValueKey('long'),
                child: SizedBox(width: 200, child: tile(longGroup)),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getRect(find.byKey(const ValueKey('long'))).height,
      closeTo(tester.getRect(find.byKey(const ValueKey('short'))).height, 0.5),
      reason:
          'the group line is one line, so a long name does not make the '
          'tile taller than the box the packing reserves',
    );

    expect(find.text(longGroup), findsOneWidget);
  });
}
