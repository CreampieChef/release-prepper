import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:release_prepper/feature/recent_releases/recent_releases_controller.dart';
import 'package:release_prepper/feature/recent_releases/recent_releases_store.dart';
import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/release/release_store.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/tracker.dart';
import 'package:release_prepper/feature/tab/tab_close.dart';
import 'package:release_prepper/feature/tab/tab_close_controller.dart';
import 'package:release_prepper/feature/tab/tab_manager.dart';
import 'package:release_prepper/l10n/app_localizations.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('tab_close_test');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  // A harness that runs the shared close flow when a button is pressed. The
  // app-close button reports its result through onAppClose so the test can read
  // it.
  Future<void> showFlow(
    WidgetTester tester,
    TabManager tabManager,
    void Function(bool) onAppClose,
  ) async {
    final store = ReleaseStore();
    final recent = RecentReleasesController(
      store: RecentReleasesStore(appDirectory: () async => directory),
      tabManager: tabManager,
    );
    final controller = TabCloseController(
      store: store,
      tabManager: tabManager,
      recentReleases: recent,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReleaseStore>(create: (_) => store),
          ChangeNotifierProvider<TabManager>(create: (_) => tabManager),
          ChangeNotifierProvider<RecentReleasesController>(
            create: (_) => recent,
          ),
          Provider<TabCloseController>(create: (_) => controller),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context)!;

              return Scaffold(
                body: Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => closeTabWithConfirmation(
                        context,
                        controller,
                        tabManager.tabs.first,
                        l10n,
                      ),
                      child: const Text('close-tab'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        onAppClose(
                          await confirmCloseApp(context, controller, l10n),
                        );
                      },
                      child: const Text('close-app'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Release editorRelease(String directoryPath) => Release(
    name: 'x',
    directoryPath: directoryPath,
    tracker: Tracker.pornolab,
    releaseType: ReleaseType.singleVideo,
    source: '/home/user/videos',
    fields: FieldValues(),
    items: [
      ReleaseItem(
        path: 'movie.mp4',
        type: itemTypeVideo,
        fields: FieldValues(),
      ),
    ],
  );

  testWidgets('a clean tab closes without a popup', (tester) async {
    final tabManager = TabManager();
    tabManager.addNewReleaseWizard();

    await showFlow(tester, tabManager, (_) {});

    await tester.tap(find.text('close-tab'));
    await tester.pumpAndSettle();

    expect(tabManager.tabs, isEmpty);
  });

  testWidgets('a dirty tab shows the three options and Cancel keeps it', (
    tester,
  ) async {
    final tabManager = TabManager();
    final tabId = tabManager.addReleaseEditor(editorRelease('/tmp/x'));
    tabManager.setUnsavedChanges(tabId, true);

    await showFlow(tester, tabManager, (_) {});

    await tester.tap(find.text('close-tab'));
    await tester.pumpAndSettle();

    expect(find.text('Close without saving'), findsOneWidget);
    expect(find.text('Save and close'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tabManager.tabs.length, 1);
  });

  testWidgets('Close without saving closes a dirty tab', (tester) async {
    final tabManager = TabManager();
    final tabId = tabManager.addReleaseEditor(editorRelease('/tmp/x'));
    tabManager.setUnsavedChanges(tabId, true);

    await showFlow(tester, tabManager, (_) {});

    await tester.tap(find.text('close-tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close without saving'));
    await tester.pumpAndSettle();

    expect(tabManager.tabs, isEmpty);
  });

  // The save is real file IO, so the whole flow runs outside the fake-async
  // zone.
  testWidgets('Save and close writes the manifest and closes the tab', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final tabManager = TabManager();
    final tabId = tabManager.addReleaseEditor(editorRelease(directory.path));
    tabManager.setUnsavedChanges(tabId, true);

    await showFlow(tester, tabManager, (_) {});

    await tester.runAsync(() async {
      await tester.tap(find.text('close-tab'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save and close'));
      // The save is real IO on the event loop, so give it time to complete
      // before the flow closes the tab.
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
    });

    expect(tabManager.tabs, isEmpty);

    late final Map<String, dynamic> saved;

    await tester.runAsync(() async {
      saved = jsonDecode(
        await File(p.join(directory.path, 'release.json')).readAsString(),
      ) as Map<String, dynamic>;
    });

    expect(saved, isA<Map<String, dynamic>>());

    directory.deleteSync(recursive: true);
  });

  testWidgets('a failed save keeps the popup open and the tab', (tester) async {
    // A release whose directory does not exist, so the write cannot succeed.
    final tabManager = TabManager();
    final tabId = tabManager.addReleaseEditor(
      editorRelease('/tmp/release_prepper_test_missing_directory'),
    );
    tabManager.setUnsavedChanges(tabId, true);

    await showFlow(tester, tabManager, (_) {});

    // The save is real file IO, so the whole flow runs outside the fake-async
    // zone; once it starts there, its continuations only run while that zone is
    // active.
    await tester.runAsync(() async {
      await tester.tap(find.text('close-tab'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save and close'));
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not save the release'), findsOneWidget);
      expect(tabManager.tabs.length, 1);

      // The popup is still there, so the user can choose again.
      await tester.tap(find.text('Close without saving'));
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
    });

    expect(tabManager.tabs, isEmpty);
  });

  testWidgets('the close flow selects the tab the popup asks about', (
    tester,
  ) async {
    final tabManager = TabManager();
    final first = tabManager.addReleaseEditor(editorRelease('/tmp/a'));
    tabManager.addReleaseEditor(editorRelease('/tmp/b'));
    tabManager.setUnsavedChanges(first, true);

    // The user is looking at the second tab, but the popup is about the first.
    tabManager.selectTab(1);

    await showFlow(tester, tabManager, (_) {});

    await tester.tap(find.text('close-tab'));
    await tester.pumpAndSettle();

    expect(tabManager.selectedIndex, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tabManager.tabs.length, 2);
  });

  testWidgets('closing the app selects the tab each popup asks about', (
    tester,
  ) async {
    final tabManager = TabManager();
    final first = tabManager.addReleaseEditor(editorRelease('/tmp/a'));
    final second = tabManager.addReleaseEditor(editorRelease('/tmp/b'));
    tabManager.setUnsavedChanges(first, true);
    tabManager.setUnsavedChanges(second, true);

    // The user is on the second tab, but the first popup is about the first.
    tabManager.selectTab(1);

    var shouldClose = false;
    await showFlow(tester, tabManager, (result) => shouldClose = result);

    await tester.tap(find.text('close-app'));
    await tester.pumpAndSettle();

    expect(tabManager.selectedIndex, 0);

    // The next popup names the second tab, so the app shows it again.
    await tester.tap(find.text('Close without saving'));
    await tester.pumpAndSettle();

    expect(tabManager.selectedIndex, 1);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(shouldClose, isFalse);
  });

  testWidgets('closing the app asks for each dirty tab and cancels on Cancel', (
    tester,
  ) async {
    final tabManager = TabManager();
    final first = tabManager.addReleaseEditor(editorRelease('/tmp/a'));
    final second = tabManager.addReleaseEditor(editorRelease('/tmp/b'));
    tabManager.setUnsavedChanges(first, true);
    tabManager.setUnsavedChanges(second, true);

    var shouldClose = false;
    await showFlow(tester, tabManager, (result) => shouldClose = result);

    await tester.tap(find.text('close-app'));
    await tester.pumpAndSettle();

    // First tab: close without saving, then the second tab's popup appears.
    await tester.tap(find.text('Close without saving'));
    await tester.pumpAndSettle();

    // Second tab: cancel, so the app does not close.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(shouldClose, isFalse);
  });

  testWidgets('closing the app closes when every dirty tab is confirmed', (
    tester,
  ) async {
    final tabManager = TabManager();
    final first = tabManager.addReleaseEditor(editorRelease('/tmp/a'));
    final second = tabManager.addReleaseEditor(editorRelease('/tmp/b'));
    tabManager.setUnsavedChanges(first, true);
    tabManager.setUnsavedChanges(second, true);

    var shouldClose = false;
    await showFlow(tester, tabManager, (result) => shouldClose = result);

    await tester.tap(find.text('close-app'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close without saving'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close without saving'));
    await tester.pumpAndSettle();

    expect(shouldClose, isTrue);
  });

  // A clean tab is skipped: the only popup is for the dirty editor, named by
  // its release rather than the wizard title.
  testWidgets('closing the app skips a clean tab', (tester) async {
    final tabManager = TabManager();
    tabManager.addNewReleaseWizard();
    final dirty = tabManager.addReleaseEditor(editorRelease('/tmp/x'));
    tabManager.setUnsavedChanges(dirty, true);

    var shouldClose = false;
    await showFlow(tester, tabManager, (result) => shouldClose = result);

    await tester.tap(find.text('close-app'));
    await tester.pumpAndSettle();

    expect(find.textContaining('x'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(shouldClose, isFalse);
  });
}
