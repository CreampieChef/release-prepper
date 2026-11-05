import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:release_prepper/feature/main_menu_controller.dart';
import 'package:release_prepper/feature/recent_releases/recent_releases.dart';
import 'package:release_prepper/feature/recent_releases/recent_releases_controller.dart';
import 'package:release_prepper/feature/recent_releases/recent_releases_page.dart';
import 'package:release_prepper/feature/recent_releases/recent_releases_store.dart';
import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/release/release_open_controller.dart';
import 'package:release_prepper/feature/release/release_store.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/tracker.dart';
import 'package:release_prepper/feature/settings/settings_controller.dart';
import 'package:release_prepper/feature/settings/settings_store.dart';
import 'package:release_prepper/feature/tab/tab_close_controller.dart';
import 'package:release_prepper/feature/tab/tab_manager.dart';
import 'package:release_prepper/l10n/app_localizations.dart';

import 'fake_pornolab_client.dart';
import 'fake_secret_store.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('recent_releases_test');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  RecentReleasesStore store() =>
      RecentReleasesStore(appDirectory: () async => directory);

  RecentReleasesController controller(TabManager tabManager) =>
      RecentReleasesController(store: store(), tabManager: tabManager);

  Map<String, dynamic> readFile() => jsonDecode(
    File(p.join(directory.path, 'recent_releases.json')).readAsStringSync(),
  ) as Map<String, dynamic>;

  Release release(
    String name, {
    String? source,
    DateTime? createdDate,
    DateTime? lastEditDate,
  }) => Release(
    name: name,
    directoryPath: '/releases/$name',
    tracker: Tracker.pornolab,
    releaseType: ReleaseType.singleVideo,
    source: source ?? '/sources/$name',
    fields: FieldValues(),
    items: const [],
    createdDate: createdDate,
    lastEditDate: lastEditDate,
  );

  RecentRelease entry(
    String name, {
    DateTime? createdDate,
    DateTime? lastEditDate,
    DateTime? lastOpenedDate,
  }) => RecentRelease(
    directoryPath: '/releases/$name',
    tracker: 'pornolab',
    releaseType: 'singleVideo',
    source: '/sources/$name',
    createdDate: createdDate,
    lastEditDate: lastEditDate,
    lastOpenedDate: lastOpenedDate,
  );

  RecentRelease entryAt(String path) => RecentRelease(
    directoryPath: path,
    tracker: 'pornolab',
    releaseType: 'singleVideo',
    source: '/sources/one',
    createdDate: null,
    lastEditDate: null,
    lastOpenedDate: null,
  );

  // The page reads the default release directory from the settings and passes
  // it to the scan, so the test points the settings at the temp directory
  // rather than at the user's.
  SettingsController settings() {
    final settings = SettingsController(
      store: SettingsStore(appDirectory: () async => directory),
      secretStore: FakeSecretStore(available: false),
      homeDirectory: directory.path,
      pathContext: p.context,
      client: FakePornolabClient(),
      appDirectory: () async => directory,
    );

    settings.settings.defaultReleaseDirectory = directory.path;

    return settings;
  }

  Widget app(RecentReleasesController recent, TabManager tabManager) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TabManager>(create: (_) => tabManager),
          ChangeNotifierProvider<RecentReleasesController>(
            create: (_) => recent,
          ),
          ChangeNotifierProvider<SettingsController>(create: (_) => settings()),
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          Provider<MainMenuController>(
            create: (context) => MainMenuController(
              tabManager: context.read<TabManager>(),
              releaseOpenController: ReleaseOpenController(
                store: context.read<ReleaseStore>(),
              ),
              tabCloseController: TabCloseController(
                store: context.read<ReleaseStore>(),
                tabManager: context.read<TabManager>(),
                recentReleases: context.read<RecentReleasesController>(),
              ),
              recentReleases: context.read<RecentReleasesController>(),
            ),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: RecentReleasesPage()),
        ),
      );

  // The page asks the controller to check the rows when it opens, and that is
  // real IO, so the test runs in runAsync and gives the event loop a turn for
  // it to finish inside the test rather than after it.
  Future<void> pumpPage(
    WidgetTester tester,
    RecentReleasesController recent,
    TabManager tabManager,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await tester.runAsync(() async {
      await tester.pumpWidget(app(recent, tabManager));
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
  }

  test(
    'recent_releases.json is written in the shape the format describes',
    () async {
      final releases = RecentReleases([
        entry('one', lastOpenedDate: DateTime.utc(2026, 3, 11)),
      ]);

      await store().save(releases);

      expect(readFile(), {
        'schema': schemaVersion,
        'entries': [
          {
            'directoryPath': '/releases/one',
            'tracker': 'pornolab',
            'releaseType': 'singleVideo',
            'source': '/sources/one',
            'lastOpenedDate': '2026-03-11T00:00:00.000Z',
          },
        ],
      });
    },
  );

  // Nothing has been opened, so there is nothing to report. A file that cannot
  // be read is the same as a missing one: the app shows what it can read rather
  // than guessing at a row.
  test('a missing or unreadable list file reads as empty', () async {
    expect((await store().load()).entries, isEmpty);

    await File(p.join(directory.path, 'recent_releases.json'))
        .writeAsString('not json');

    expect((await store().load()).entries, isEmpty);
  });

  // This is a file the user may have edited, so a value that is not a date is
  // read as none rather than reported, and a row that is not an object is not
  // kept.
  test('a value this version does not read is not kept', () async {
    await File(p.join(directory.path, 'recent_releases.json')).writeAsString(
      '{"schema": 1, "entries": [{"directoryPath": "/releases/one",'
      '"tracker": "pornolab", "releaseType": "singleVideo",'
      '"source": "/sources/one", "createdDate": "not a date", "lastOpenedDate": 4},'
      ' "not an entry"]}',
    );

    final loaded = await store().load();

    expect(loaded.entries.length, 1);
    expect(loaded.entries.first.createdDate, isNull);
    expect(loaded.entries.first.lastOpenedDate, isNull);
  });

  // The key is the directory, because that is what identifies a release on
  // disk: the name is the basename and two releases can have the same one.
  test(
    'recording the same directory updates the entry instead of adding a row',
    () async {
      final releases = RecentReleases();

      releases.record(
        release('one', lastEditDate: DateTime.utc(2026, 3, 1)),
        now: DateTime.utc(2026, 3, 2),
      );
      releases.record(
        release('one', lastEditDate: DateTime.utc(2026, 3, 14)),
        now: DateTime.utc(2026, 3, 15),
      );

      expect(releases.entries.length, 1);
      expect(releases.entries.first.lastEditDate, DateTime.utc(2026, 3, 14));
      expect(releases.entries.first.lastOpenedDate, DateTime.utc(2026, 3, 15));
    },
  );

  // The list is a convenience, not an archive, so it has a limit, and the entry
  // that leaves is the one opened least recently — the only order a list of
  // recents has.
  test('the cap drops the entry opened least recently', () async {
    final releases = RecentReleases();

    for (final index in List.generate(maxRecentEntries, (i) => i)) {
      releases.record(
        release('release-$index'),
        now: DateTime.utc(2026, 1, 1).add(Duration(minutes: index)),
      );
    }

    expect(releases.entries.length, maxRecentEntries);

    // The oldest opened is the first one added, so recording a new release
    // drops it.
    releases.record(release('new-one'), now: DateTime.utc(2026, 2, 1));

    expect(releases.entries.length, maxRecentEntries);
    expect(releases.entryFor('/releases/release-0'), isNull);
    expect(releases.entryFor('/releases/new-one'), isNotNull);

    // Re-opening an entry that is already in the list refreshes its opened
    // date, so it is no longer the one that goes.
    releases.record(release('release-1'), now: DateTime.utc(2026, 3, 1));
    releases.record(release('another-new-one'), now: DateTime.utc(2026, 3, 2));

    expect(releases.entries.length, maxRecentEntries);
    expect(releases.entryFor('/releases/release-1'), isNotNull);
    expect(releases.entryFor('/releases/release-2'), isNull);
  });

  // A tie is broken by the key, so the same data gives the same order, and a
  // date the file does not have is none: it is at the end of a newest-first
  // order rather than in the middle of it.
  test(
    'the sort orders by the column and breaks a tie by the directory path',
    () async {
      final entries = [
        entry('b', lastEditDate: DateTime.utc(2026, 3, 1)),
        entry('a', lastEditDate: DateTime.utc(2026, 3, 1)),
        entry('c', lastEditDate: null),
      ];

      final newestFirst = sortEntries(
        entries,
        compare: (x, y) => compareDates(x.lastEditDate, y.lastEditDate),
        descending: true,
      );

      expect(newestFirst.map((e) => e.name), ['b', 'a', 'c']);

      final oldestFirst = sortEntries(
        entries,
        compare: (x, y) => compareDates(x.lastEditDate, y.lastEditDate),
        descending: false,
      );

      expect(oldestFirst.map((e) => e.name), ['c', 'a', 'b']);
    },
  );

  // The sort does not change the order the file lists: that is data, so a sort
  // is only what the table shows.
  test('sorting does not change the order the list holds', () async {
    final releases = RecentReleases([entry('b'), entry('a')]);

    sortEntries(
      releases.entries,
      compare: (x, y) => x.name.compareTo(y.name),
      descending: false,
    );

    expect(releases.entries.map((e) => e.name), ['b', 'a']);
  });

  // A row whose folder is gone is marked rather than dropped: the values the
  // index holds are still what the app read, and the folder may come back.
  test('a row whose manifest is gone is marked as unavailable', () async {
    final present = p.join(directory.path, 'present');
    final gone = p.join(directory.path, 'gone');

    final recent = controller(TabManager());

    recent.releases = RecentReleases([entryAt(present), entryAt(gone)]);

    await File(p.join(present, 'release.json')).create(recursive: true);

    await recent.checkAvailability();

    expect(recent.unavailablePaths, {gone});
  });

  // The table also shows the folders in the default release directory. A
  // subdirectory without a manifest is not a release, so it is not a row, and a
  // directory that is not there reads as nothing found rather than as an error
  // (`ai/recent_releases.md` §5).
  test('the scan lists the subdirectories that hold a release.json', () async {
    final recent = controller(TabManager());

    await Directory(p.join(directory.path, 'found')).create();
    await File(p.join(directory.path, 'found/release.json')).create();
    await Directory(p.join(directory.path, 'not-a-release')).create();
    await File(p.join(directory.path, 'a-file')).create();

    await recent.scanDefaultDirectory(directory.path);

    expect(recent.discoveredPaths, {p.join(directory.path, 'found')});
  });

  test(
    'a default directory that is not there reads as nothing found',
    () async {
      final recent = controller(TabManager());

      await recent.scanDefaultDirectory(p.join(directory.path, 'not-there'));

      expect(recent.discoveredPaths, isEmpty);
    },
  );

  // A folder in both is one row, with the values the index holds: the index is
  // the record, and the scan only says the folder is there.
  test(
    'a folder in both the index and the scan is one row with the index values',
    () async {
      final found = p.join(directory.path, 'found');
      final recent = controller(TabManager());

      await Directory(found).create();
      await File(p.join(found, 'release.json')).create();

      recent.releases = RecentReleases([entryAt(found)]);

      await recent.scanDefaultDirectory(directory.path);

      expect(recent.rows, [recent.releases.entryFor(found)]);
    },
  );

  // A folder the scan found has nothing stored, so the row has nothing but the
  // path; the name is the basename, as it is everywhere else.
  test(
    'a folder only in the scan is a row with nothing but the path',
    () async {
      final found = p.join(directory.path, 'found');
      final recent = controller(TabManager());

      await Directory(found).create();
      await File(p.join(found, 'release.json')).create();

      await recent.scanDefaultDirectory(directory.path);

      final row = recent.rows.single;

      expect(row.directoryPath, found);
      expect(row.name, 'found');
      expect(row.tracker, '');
      expect(row.source, '');
      expect(row.lastEditDate, isNull);
    },
  );

  // The scan is what the table draws, not what the file holds: nothing is
  // written from it, so the entries the file has are the entries the app
  // recorded.
  test('the scan does not write the file', () async {
    final recent = controller(TabManager());

    await Directory(p.join(directory.path, 'found')).create();
    await File(p.join(directory.path, 'found/release.json')).create();

    await recent.scanDefaultDirectory(directory.path);

    expect(
      File(p.join(directory.path, 'recent_releases.json')).existsSync(),
      isFalse,
    );
  });

  // Recording is the side effect the open, create and save paths call, and it
  // writes the file as it goes: there is no save step, so the tab has no dirty
  // flag.
  test('recording a release writes the file', () async {
    final recent = controller(TabManager());

    await recent.record(release('one'));

    expect(readFile()['entries'], isNotEmpty);

    // A release the app has just read is a folder it can read, so its row is
    // not marked.
    recent.unavailablePaths.add('/releases/one');
    await recent.record(release('one'));

    expect(recent.unavailablePaths, isEmpty);
  });

  // The tab the app opens at startup is opened once: the list is app-level, so
  // a second tab would show the same table twice.
  test('the startup read opens the recent tab once', () async {
    final tabManager = TabManager();
    final recent = controller(tabManager);

    await recent.start();

    expect(tabManager.tabs.length, 1);
    expect(tabManager.tabs.first.kind, AppTabKind.recentReleases);

    // The menu item calls the same method, so opening it again selects the tab
    // rather than adding a second one.
    tabManager.addRecentReleases();

    expect(tabManager.tabs.length, 1);
    expect(tabManager.selectedIndex, 0);
  });

  // One tab per release directory: opening the same folder twice shows the tab
  // that is already there, the same as the settings tab and the same as the
  // list has one row for it.
  test('opening a release that is already open selects the existing tab', () {
    final tabManager = TabManager();

    final first = tabManager.addReleaseEditor(release('one'));
    tabManager.addNewReleaseWizard();
    tabManager.addReleaseEditor(release('two'));

    tabManager.addReleaseEditor(release('one'));

    expect(tabManager.tabs.length, 3);
    expect(tabManager.tabs[tabManager.selectedIndex].id, first);
  });

  testWidgets('the table shows a row for each entry', (tester) async {
    final recent = controller(TabManager());
    recent.releases = RecentReleases([entry('one')]);

    await pumpPage(tester, recent, TabManager());

    expect(find.byKey(ValueKey('recentRow-/releases/one')), findsOneWidget);
    expect(find.text('/sources/one'), findsOneWidget);
  });

  testWidgets('a row whose folder is gone is marked', (tester) async {
    final recent = controller(TabManager());
    recent.releases = RecentReleases([entry('gone')]);

    await pumpPage(tester, recent, TabManager());

    expect(
      find.byKey(ValueKey('recentUnavailable-/releases/gone')),
      findsOneWidget,
    );
  });

  // A folder the scan found shows the name and the path and nothing else,
  // because nothing about it was read. The name is the basename, as it is
  // everywhere else.
  testWidgets(
    'a folder the scan found shows the name and the path and nothing else',
    (tester) async {
      final recent = controller(TabManager());

      // The folders have to be on disk before the page is built, and real file
      // IO only completes inside runAsync, because the test body runs in a
      // fake-async zone.
      late String found;

      await tester.runAsync(() async {
        found = p.join(directory.path, 'found');

        await Directory(found).create();
        await File(p.join(found, 'release.json')).create();
      });

      await pumpPage(tester, recent, TabManager());

      final row = find.byKey(ValueKey('recentRow-$found'));

      expect(row, findsOneWidget);

      expect(
        tester
            .widgetList(find.descendant(of: row, matching: find.byType(Text)))
            .map((widget) => (widget as Text).data ?? '')
            .where((text) => text.isNotEmpty)
            .toList(),
        ['found', found],
      );
    },
  );

  testWidgets('clicking a header sorts the table by that column', (
    tester,
  ) async {
    final recent = controller(TabManager());
    recent.releases = RecentReleases([
      entry('b', lastEditDate: DateTime.utc(2026, 3, 14)),
      entry('a', lastEditDate: DateTime.utc(2026, 3, 1)),
    ]);

    await pumpPage(tester, recent, TabManager());

    // The default order is the last edit date, newest first.
    expect(
      tester.getTopLeft(find.byKey(ValueKey('recentRow-/releases/b'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(ValueKey('recentRow-/releases/a'))).dy,
      ),
    );

    // A name column starts ascending, so the order changes; clicking it again
    // reverses it.
    await tester.tap(find.byKey(ValueKey('recentSort-name')));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.byKey(ValueKey('recentRow-/releases/a'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(ValueKey('recentRow-/releases/b'))).dy,
      ),
    );

    await tester.tap(find.byKey(ValueKey('recentSort-name')));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.byKey(ValueKey('recentRow-/releases/b'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(ValueKey('recentRow-/releases/a'))).dy,
      ),
    );
  });

  // A row click is the same command as the menu item, with the picker skipped,
  // so it reports a failure through the same popup.
  testWidgets('clicking a row opens the release it names', (tester) async {
    final tabManager = TabManager();
    final recent = controller(tabManager);

    // The store is async, so the manifest is written inside runAsync; outside
    // it the test's fake clock does not drive the event loop and the call never
    // completes.
    late Release created;

    await tester.runAsync(() async {
      created = await ReleaseStore().create(
        savePath: directory.path,
        name: 'on-disk',
        tracker: Tracker.pornolab,
        releaseType: ReleaseType.singleVideo,
      );
    });

    recent.releases = RecentReleases([
      RecentRelease(
        directoryPath: created.directoryPath,
        tracker: 'pornolab',
        releaseType: 'singleVideo',
        source: created.source,
        createdDate: created.createdDate,
        lastEditDate: created.lastEditDate,
        lastOpenedDate: DateTime.utc(2026, 3, 1),
      ),
    ]);

    await pumpPage(tester, recent, tabManager);

    await tester.runAsync(() async {
      await tester.tap(
        find.byKey(ValueKey('recentRow-${created.directoryPath}')),
      );

      // The open is real IO, so the event loop needs a turn for it to finish
      // inside the test.
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    expect(tabManager.tabs.length, 1);
    expect(tabManager.tabs.first.kind, AppTabKind.releaseEditor);
  });
}
