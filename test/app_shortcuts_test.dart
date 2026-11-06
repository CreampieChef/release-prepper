import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:release_prepper/feature/main_menu_controller.dart';
import 'package:release_prepper/feature/recent_releases/recent_releases_controller.dart';
import 'package:release_prepper/feature/recent_releases/recent_releases_store.dart';
import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/release/release_open_controller.dart';
import 'package:release_prepper/feature/release/release_store.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/tracker.dart';
import 'package:release_prepper/feature/settings/settings_controller.dart';
import 'package:release_prepper/feature/settings/settings_store.dart';
import 'package:release_prepper/feature/tab/app_shortcuts.dart';
import 'package:release_prepper/feature/tab/tab_close_controller.dart';
import 'package:release_prepper/feature/tab/tab_manager.dart';
import 'package:release_prepper/l10n/app_localizations.dart';

import 'fake_pornolab_client.dart';
import 'fake_secret_store.dart';
import 'test_fields.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('app_shortcuts_test');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  // The app as `app.dart` places it: the Ctrl keys are at the app level, so
  // they are an ancestor of every focus scope, a popup route's included. `home`
  // stands for the tab content, and the settings controller is what the open
  // flow is given; these tests do not read or write settings.
  Future<TabManager> showApp(WidgetTester tester, Widget home) async {
    final tabManager = TabManager();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ChangeNotifierProvider<TabManager>(create: (_) => tabManager),
          ChangeNotifierProvider<RecentReleasesController>(
            create: (context) => RecentReleasesController(
              store: RecentReleasesStore(appDirectory: () async => directory),
              tabManager: context.read<TabManager>(),
            ),
          ),
          Provider<TabCloseController>(
            create: (context) => TabCloseController(
              store: context.read<ReleaseStore>(),
              tabManager: context.read<TabManager>(),
              recentReleases: context.read<RecentReleasesController>(),
            ),
          ),
          ChangeNotifierProvider<SettingsController>(
            create: (context) => SettingsController(
              store: SettingsStore(appDirectory: () async => directory),
              secretStore: FakeSecretStore(available: false),
              homeDirectory: '',
              pathContext: p.context,
              client: FakePornolabClient(),
              appDirectory: () async => directory,
            ),
          ),
          Provider<MainMenuController>(
            create: (context) => MainMenuController(
              tabManager: context.read<TabManager>(),
              releaseOpenController: ReleaseOpenController(
                store: context.read<ReleaseStore>(),
              ),
              tabCloseController: context.read<TabCloseController>(),
              recentReleases: context.read<RecentReleasesController>(),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              AppShortcuts(child: child ?? const SizedBox.shrink()),
          home: home,
        ),
      ),
    );

    await tester.pump();

    return tabManager;
  }

  Future<void> pressControl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }

  // A popup is a route, which is what makes its focus scope separate from the
  // content area's.
  Widget popupOpener() => Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            content: TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('close'),
            ),
          ),
        ),
        child: const Text('open'),
      ),
    ),
  );

  Release testRelease() => Release(
    name: 'x',
    directoryPath: directory.path,
    tracker: Tracker.pornolab,
    releaseType: ReleaseType.singleVideo,
    source: '',
    fields: completeFields()..setValue('videoTitle', 'Edited title'),
    items: [],
  );

  // What the key is read to have done here is the flow the menu item calls, so
  // the observable result is the tab collection or the file the save writes.
  testWidgets('the app-level keys are reached from a focus inside the app', (
    tester,
  ) async {
    final tabManager = await showApp(
      tester,
      Scaffold(body: Focus(autofocus: true, child: const Text('content'))),
    );

    await pressControl(tester, LogicalKeyboardKey.keyN);

    expect(tabManager.tabs.single.kind, AppTabKind.releaseWizard);
  });

  testWidgets('the app-level keys are reached from a focus inside a popup', (
    tester,
  ) async {
    final tabManager = await showApp(tester, popupOpener());

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The popup's focus scope is not inside the content area, so this is the
    // case the per-widget patches used to handle one at a time; the app-level
    // placement is an ancestor of the route, so the key reaches the flow.
    await pressControl(tester, LogicalKeyboardKey.keyN);

    expect(tabManager.tabs.single.kind, AppTabKind.releaseWizard);
  });

  // The app-level map is the last handler in the focus chain, so a widget that
  // handles the key itself is asked first; that is why the editor's own Ctrl+S
  // keeps its fields.
  testWidgets('a nearer handler is asked first', (tester) async {
    var handled = false;

    final tabManager = await showApp(
      tester,
      Scaffold(
        body: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.keyN &&
                HardwareKeyboard.instance.isControlPressed) {
              handled = true;
              return KeyEventResult.handled;
            }

            return KeyEventResult.ignored;
          },
          child: const Text('content'),
        ),
      ),
    );

    await pressControl(tester, LogicalKeyboardKey.keyN);

    expect(handled, isTrue);
    expect(tabManager.tabs, isEmpty);
  });

  // Ctrl+S is the key the reports are about: it is expected to save the tab the
  // user is on, and with a popup open the focus is not in the content area, so
  // the app-level placement is what reaches the save.
  testWidgets('Ctrl+S saves the current tab with a popup open', (tester) async {
    final tabManager = await showApp(tester, popupOpener());

    final tabId = tabManager.addReleaseEditor(testRelease());
    tabManager.setUnsavedChanges(tabId, true);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Real file IO, because the save writes the manifest.
    await tester.runAsync(() async {
      await pressControl(tester, LogicalKeyboardKey.keyS);
      await Future.delayed(const Duration(milliseconds: 100));
    });

    expect(tabManager.tabs.single.hasUnsavedChanges, isFalse);

    late final Map<String, dynamic> saved;

    await tester.runAsync(() async {
      saved = jsonDecode(
        await File(p.join(directory.path, 'release.json')).readAsString(),
      ) as Map<String, dynamic>;
    });

    expect(saved['fields']['videoTitle'], 'Edited title');
  });
}
