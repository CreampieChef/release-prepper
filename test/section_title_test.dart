import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/feature/section_title.dart';

void main() {
  // The title row: the title at the left and the action at the right. The row
  // is as tall as the action, so the title is centred against it — a title
  // aligned to the top of a row that holds a button reads as being in the wrong
  // place.
  testWidgets('the title is at the left and the action at the right', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 200);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionTitle(
            title: 'Screenshots',
            action: FilledButton(
              onPressed: () {},
              child: const Text('Generate'),
            ),
          ),
        ),
      ),
    );

    final title = tester.getRect(find.text('Screenshots'));
    final button = tester.getRect(find.byType(FilledButton));

    expect(title.left, 0);
    expect(button.right, 600);

    expect(
      title.center.dy,
      closeTo(button.center.dy, 0.5),
      reason: 'the title is centred on the row, which is as tall as the button',
    );
  });

  // A section that shows a placeholder instead of its controls shows the title
  // with nothing on the right. The row is then only the title, and it is not
  // taller than the title: the placeholder case is the same row, not a row with
  // an empty space where the button would be.
  testWidgets('with no action the row is only the title', (tester) async {
    tester.view.physicalSize = const Size(600, 200);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SectionTitle(title: 'Upload images')),
      ),
    );

    expect(find.byType(SectionTitle), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);

    final row = tester.getRect(find.byType(SectionTitle));
    final title = tester.getRect(find.text('Upload images'));

    expect(row.height, closeTo(title.height, 0.5));
  });

  // The action is drawn at least `SectionTitle.actionMinWidth` wide, so a short
  // label is the same shape as a longer one. The label here is short on
  // purpose, so the minimum is what decides the width. The test reads the
  // constant rather than a number, so it follows whatever value the widget is
  // changed to.
  testWidgets('the action is at least the minimum width', (tester) async {
    tester.view.physicalSize = const Size(600, 200);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionTitle(
            title: 'Screenshots',
            action: FilledButton(onPressed: () {}, child: const Text('Scan')),
          ),
        ),
      ),
    );

    expect(
      tester.getRect(find.byType(FilledButton)).width,
      greaterThanOrEqualTo(SectionTitle.actionMinWidth),
    );
  });
}
