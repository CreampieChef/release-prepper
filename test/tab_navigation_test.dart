import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/feature/tab/tab_navigation.dart';

void main() {
  // A widget test reports a mobile platform, where a scroll view inherits the
  // primary controller by default. The app is a desktop app, so these tests run
  // on the platform it runs on. The override has to be cleared inside the test,
  // because the framework checks the debug variables before it runs `tearDown`.
  Future<void> onLinux(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  // The content area as `app.dart` places it: what is below the menu bar and
  // the tab strip, which is the part these keys belong to. `aboveFocus` is what
  // stands for a widget outside the content area that can hold focus, so a test
  // can put focus where these keys do not belong.
  //
  // A page is built without a controller of its own, which is what the app's
  // pages do, so the position it resolves to is the one the content area owns —
  // the one these tests read through `pageView`.
  Future<ScrollController?> showContent(
    WidgetTester tester, {
    required Widget page,
    Finder? pageView,
    FocusNode? aboveFocus,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Focus(focusNode: aboveFocus, child: const Text('menu bar')),
              Expanded(child: TabNavigation(child: page)),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    if (pageView == null) {
      return null;
    }

    return PrimaryScrollController.maybeOf(tester.element(pageView));
  }

  // A page of rows with a fixed height each, so the content is clearly taller
  // than one page height and a page move is a move rather than a clamp. A row
  // is a plain widget, so nothing in this page can hold focus, as nothing in
  // the recent list can: its rows are `InkWell`s, which are not focusable.
  Widget rows() => ListView(
    children: List.generate(
      60,
      (index) => SizedBox(height: 40, child: Text('row $index')),
    ),
  );

  bool fieldHasFocus() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;

  // A focused field inside a page: the state the app is in while the user is
  // typing. The field is below what one page shows, so focusing it moves the
  // page; after that the caret is inside what the page shows, so a caret move
  // cannot itself move the page and the tests above read a page that stayed.
  Future<ScrollController> showFieldPage(
    WidgetTester tester, {
    required TextEditingController text,
    required FocusNode focusNode,
  }) async {
    final page = find.byType(SingleChildScrollView);

    final controller = (await showContent(
      tester,
      page: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 700),
            TextField(controller: text, maxLines: 3, focusNode: focusNode),
            const SizedBox(height: 500),
          ],
        ),
      ),
      pageView: page,
    ))!;

    focusNode.requestFocus();
    await tester.pumpAndSettle();

    text.selection = const TextSelection.collapsed(offset: 17);
    await tester.pumpAndSettle();

    return controller;
  }

  testWidgets('a page resolves to the controller the content area owns', (
    tester,
  ) async {
    await onLinux(tester, () async {
      final page = find.byType(ListView);
      final controller = await showContent(
        tester,
        page: rows(),
        pageView: page,
      );

      // On a mobile platform this is true by default; on the app's platform it
      // is true only because the inheritance is asked for, which is what the
      // widget does. Without it the page keeps its own controller and the keys
      // below have nothing to move.
      expect(controller!.hasClients, isTrue);
    });
  });

  // A key only reaches the handler through the focus chain, so the content area
  // is the default focus of its subtree; a page with nothing focusable in it is
  // reached through that. This is the recent list.
  testWidgets('a page with nothing focusable is reached', (tester) async {
    await onLinux(tester, () async {
      final page = find.byType(ListView);
      final controller = await showContent(
        tester,
        page: rows(),
        pageView: page,
      );

      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TabNavigation>(),
        isNotNull,
      );

      final pageHeight = tester.getSize(page).height;

      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);

      expect(handled, isTrue);

      await tester.pumpAndSettle();
      expect(controller!.position.pixels, pageHeight);
    });
  });

  // Not being a stop for traversal is what keeps Tab working: from the default
  // focus it goes to the first field, as it did before.
  testWidgets('Tab still reaches the first field', (tester) async {
    await onLinux(tester, () async {
      await showContent(
        tester,
        page: ListView(children: const [TextField(), SizedBox(height: 400)]),
      );

      expect(fieldHasFocus(), isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);

      expect(fieldHasFocus(), isTrue);
    });
  });

  testWidgets('PageDown and PageUp move by the height of the content area', (
    tester,
  ) async {
    await onLinux(tester, () async {
      final page = find.byType(ListView);
      final controller = await showContent(
        tester,
        page: rows(),
        pageView: page,
      );

      final pageHeight = tester.getSize(page).height;
      expect(controller!.position.maxScrollExtent, greaterThan(pageHeight));

      // The position is read after the move finishes, since the key starts the
      // move rather than answering with where it ended.
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(controller.position.pixels, pageHeight);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
      expect(controller.position.pixels, 0.0);

      // A move past what the page has stops at its end, so the key cannot put
      // the page somewhere it cannot be. Each move is settled on its own, so
      // the presses add up rather than cancel each other in one frame.
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pumpAndSettle();
      }

      expect(controller.position.pixels, controller.position.maxScrollExtent);
    });
  });

  // Repeated presses read as one continuous move because each starts from where
  // the page is at that moment, not from where the previous one was going.
  testWidgets('a press during the move starts from where the page is', (
    tester,
  ) async {
    await onLinux(tester, () async {
      final page = find.byType(ListView);
      final controller = (await showContent(
        tester,
        page: rows(),
        pageView: page,
      ))!;

      final pageHeight = tester.getSize(page).height;

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);

      // The frame the move starts on does not move the page, so the read is on
      // the frame after it: part way through the first move, which is where the
      // second press starts from.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final partway = controller.position.pixels;
      expect(partway, greaterThan(0.0));
      expect(partway, lessThan(pageHeight));

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();

      // The total is the two moves added, which is what pressing the key twice
      // in a browser does.
      expect(controller.position.pixels, partway + pageHeight);
    });
  });

  testWidgets('Home and End go to the top and the bottom of the page', (
    tester,
  ) async {
    await onLinux(tester, () async {
      final page = find.byType(ListView);
      final controller = await showContent(
        tester,
        page: rows(),
        pageView: page,
      );

      // Started somewhere in the middle, so the moves are reads of going to an
      // end rather than of staying where they were.
      controller!.jumpTo(100);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(controller.position.pixels, controller.position.maxScrollExtent);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(controller.position.pixels, 0.0);
    });
  });

  // A focused field keeps these keys: Home and End move the caret, PageUp and
  // PageDown scroll the field. Declining is what leaves them to it, so what the
  // field does is the framework's behaviour, not this widget's.
  testWidgets('a focused text input keeps these keys', (tester) async {
    await onLinux(tester, () async {
      final text = TextEditingController(text: 'first line\nsecond line');
      final focusNode = FocusNode();

      final controller = await showFieldPage(
        tester,
        text: text,
        focusNode: focusNode,
      );

      // The field has focus, so the key is the field's and not the page's.
      expect(fieldHasFocus(), isTrue);

      // The page is somewhere other than its top, so a move would show.
      final pageWasAt = controller.position.pixels;
      expect(pageWasAt, greaterThan(0.0));

      await tester.sendKeyEvent(LogicalKeyboardKey.home);

      // The caret went to the start of its line, and the page stayed.
      expect(text.selection.baseOffset, 11);
      expect(controller.position.pixels, pageWasAt);
    });
  });

  testWidgets('a modifier keeps the key with the field too', (tester) async {
    await onLinux(tester, () async {
      final text = TextEditingController(text: 'first line\nsecond line');
      final focusNode = FocusNode();

      final controller = await showFieldPage(
        tester,
        text: text,
        focusNode: focusNode,
      );

      final pageWasAt = controller.position.pixels;
      expect(pageWasAt, greaterThan(0.0));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      // Ctrl+Home is the field's key: the caret goes to the start of the text
      // and the page stayed where it was.
      expect(text.selection.baseOffset, 0);
      expect(controller.position.pixels, pageWasAt);
    });
  });

  // A focus outside the content area is not moved by these keys, as it is
  // today. Since the content area is the default focus of its subtree, the test
  // asks for focus outside it, which is what clicking the menu bar would do.
  testWidgets('a focus outside the content area does not move a page', (
    tester,
  ) async {
    await onLinux(tester, () async {
      final outside = FocusNode();
      addTearDown(outside.dispose);

      final page = find.byType(ListView);

      final controller = await showContent(
        tester,
        page: rows(),
        pageView: page,
        aboveFocus: outside,
      );

      outside.requestFocus();
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, outside);

      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);

      expect(handled, isFalse);
      expect(controller!.position.pixels, 0.0);
    });
  });

  testWidgets('the empty state has no page to move', (tester) async {
    await onLinux(tester, () async {
      await showContent(
        tester,
        page: const Center(child: Text('No tab is open')),
      );

      // Nothing has attached a position, so the key is declined rather than
      // answered with a position that does not exist.
      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.home);

      expect(handled, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
