import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:release_prepper/feature/recent_releases/recent_releases_controller.dart';
import 'package:release_prepper/feature/recent_releases/recent_releases_store.dart';
import 'package:release_prepper/feature/release/release_store.dart';
import 'package:release_prepper/feature/tab/tab_close_controller.dart';
import 'package:release_prepper/feature/tab/tab_manager.dart';
import 'package:release_prepper/feature/tab/tab_strip.dart';
import 'package:release_prepper/l10n/app_localizations.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('tab_strip_test');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  Future<TabManager> showStrip(WidgetTester tester) async {
    final tabManager = TabManager();

    // Two tabs with the first one selected, so the second card is an unselected
    // one: adding a tab selects it, and the tests below are about a card that
    // is not the selected one.
    tabManager.addNewReleaseWizard();
    tabManager.addNewReleaseWizard();
    tabManager.selectTab(0);

    final recent = RecentReleasesController(
      store: RecentReleasesStore(appDirectory: () async => directory),
      tabManager: tabManager,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ChangeNotifierProvider<TabManager>(create: (_) => tabManager),
          ChangeNotifierProvider<RecentReleasesController>(
            create: (_) => recent,
          ),
          Provider<TabCloseController>(
            create: (context) => TabCloseController(
              store: context.read<ReleaseStore>(),
              tabManager: context.read<TabManager>(),
              recentReleases: context.read<RecentReleasesController>(),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: TabStrip()),
        ),
      ),
    );

    return tabManager;
  }

  Future<void> click(WidgetTester tester, Finder target, int buttons) async {
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.mouse,
      buttons: buttons,
    );

    await gesture.up();
    addTearDown(gesture.removePointer);

    await tester.pump();
  }

  testWidgets('the middle button closes a tab without selecting it', (
    tester,
  ) async {
    final tabManager = await showStrip(tester);

    await click(tester, find.text('New Release').at(1), kMiddleMouseButton);

    expect(tabManager.tabs.length, 1);
    expect(tabManager.selectedIndex, 0);
  });

  testWidgets('the other buttons still select the tab', (tester) async {
    final tabManager = await showStrip(tester);

    await click(tester, find.text('New Release').at(1), kPrimaryMouseButton);

    expect(tabManager.tabs.length, 2);
    expect(tabManager.selectedIndex, 1);
  });

  // The tint is painted from the widget's own hover state rather than by
  // `InkWell`, because `InkWell` resolves its hover colour once, when the
  // highlight is created, and keeps it until the pointer leaves. A card that is
  // hovered and then clicked would keep the tint it had before the click, which
  // is what the user sees as the highlight not going away.
  testWidgets('the hover tint is gone when a hovered card is clicked', (
    tester,
  ) async {
    final tabManager = await showStrip(tester);

    // The second card: the one that is not selected.
    final card = find.text('New Release').at(1);

    // The card's own `Material` is the nearest one above the title, which is
    // the widget the colour is painted on.
    Material cardMaterial() => tester.widget<Material>(
      find.ancestor(of: card, matching: find.byType(Material)).first,
    );

    expect(cardMaterial().color, const Color(0xFFE8EAED));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);

    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(card));
    await tester.pump();

    final theme = Theme.of(tester.element(card));

    expect(
      cardMaterial().color,
      Color.alphaBlend(theme.hoverColor, const Color(0xFFE8EAED)),
    );

    // The pointer is still over the card, so the only thing that changes is the
    // selection: the tint is gone and the card shows the selected colour.
    await click(tester, card, kPrimaryMouseButton);

    expect(tabManager.selectedIndex, 1);
    expect(cardMaterial().color, Colors.white);
  });
}
