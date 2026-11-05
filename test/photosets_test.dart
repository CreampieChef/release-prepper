import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:release_prepper/feature/photosets/photosets_controller.dart';
import 'package:release_prepper/feature/photosets/photosets_section.dart';
import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/release/release_store.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/tracker.dart';
import 'package:release_prepper/feature/section_title.dart';
import 'package:release_prepper/feature/tab/tab_manager.dart';
import 'package:release_prepper/l10n/app_localizations.dart';
import 'package:release_prepper/feature/screenshots/images.dart';
import 'package:release_prepper/feature/screenshots/images_store.dart';
import 'package:release_prepper/service/photosets/directory_reader.dart';
import 'package:release_prepper/service/photosets/photoset_scanner.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('release_prepper_test');
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
  });

  // A photo fixture: the bytes a PNG header has.
  List<int> pngPhoto(int width, int height) => [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    (width >> 24) & 0xFF,
    (width >> 16) & 0xFF,
    (width >> 8) & 0xFF,
    width & 0xFF,
    (height >> 24) & 0xFF,
    (height >> 16) & 0xFF,
    (height >> 8) & 0xFF,
    height & 0xFF,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
  ];

  void writePhoto(String setName, String name, int width, int height) {
    File(p.join(directory.path, setName, name))
        .writeAsBytesSync(pngPhoto(width, height));
  }

  // A photo under a folder, so the source and the release directory are not the
  // same place.
  void writePhotoAt(
    String folder,
    String name, [
    int width = 100,
    int height = 100,
  ]) {
    final set = Directory(p.join(directory.path, folder));
    set.createSync(recursive: true);
    File(p.join(set.path, name)).writeAsBytesSync(pngPhoto(width, height));
  }

  // A file with a photo extension and a header the reader does not understand:
  // it is counted as a photo and reported, and the grid lays its tile out as a
  // square.
  void writeRawAt(String folder, String name, List<int> bytes) {
    final set = Directory(p.join(directory.path, folder));
    set.createSync(recursive: true);
    File(p.join(set.path, name)).writeAsBytesSync(bytes);
  }

  Release testRelease(
    String source, {
    ReleaseType releaseType = ReleaseType.photosetPack,
  }) => Release(
    name: 'x',
    directoryPath: directory.path,
    tracker: Tracker.pornolab,
    releaseType: releaseType,
    source: source,
    fields: FieldValues(),
    items: [],
  );

  PhotosetScanner testScanner() =>
      PhotosetScanner(readers: [const DirectoryPhotosetReader()]);

  PhotosetController testController(
    Release release,
    ImagesStore store,
    TabManager tabManager,
    String tabId,
  ) => PhotosetController(
    release: release,
    scanner: testScanner(),
    store: store,
    releaseStore: ReleaseStore(),
    tabManager: tabManager,
    tabId: tabId,
  );

  // The scan and the pick are async, and the widget does not hand out their
  // future, so a test that clicks one has to wait for it. Waiting for a fixed
  // time is what made these tests fail when the whole suite ran at once: under
  // load the run did not finish in time. So the wait is on what the run shows,
  // with a bound, and a run that does not finish within it fails rather than
  // passing by luck.
  Future<void> clickAndWait(
    WidgetTester tester,
    Finder trigger,
    Finder until,
  ) async {
    await tester.runAsync(() async {
      await tester.tap(trigger);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump();
        if (until.evaluate().isNotEmpty) return;
        await Future.delayed(const Duration(milliseconds: 10));
      }
      throw StateError(
        'the run started by ${trigger.describeMatch(Plurality.one)} '
        'did not show ${until.describeMatch(Plurality.one)} within 10 seconds',
      );
    });
  }

  // The controller records the items, because an item is what the scan
  // produces, and returns the values for the editor's single write path.
  test(
    'the scan records the items and returns the values for the editor',
    () async {
      Directory(p.join(directory.path, 'set01')).createSync();
      writePhoto('set01', 'a.png', 100, 100);
      writePhoto('set01', 'b.png', 400, 150);

      final tabManager = TabManager();
      final release = testRelease(directory.path);
      final tabId = tabManager.addReleaseEditor(release);

      final controller = testController(
        release,
        ImagesStore(),
        tabManager,
        tabId,
      );

      final result = await controller.scan() as PhotosetSuccess;

      expect(release.items.single.path, 'set01');
      expect(release.items.single.type, 'photoset');
      expect(release.items.single.fields.value('photoCount'), '2');

      expect(result.values, {
        'photosetCount': '1',
        'totalPhotoCount': '2',
        'minResolution': '100x100',
        'maxResolution': '400x150',
      });

      expect(tabManager.tabs.single.hasUnsavedChanges, isTrue);
    },
  );

  // A single photoset is the source itself, so the scan records one item named
  // by the source, and the values it returns are the names this type has: the
  // formats, and no count of sets because there is only one
  // (`ai/single_photoset.md` §3, §5).
  test('a single photoset is the source itself, and its values are the names it has', () async {
    writePhotoAt('set01', 'a.jpg', 100, 100);
    writePhotoAt('set01', 'b.png', 400, 150);

    final tabManager = TabManager();
    final release = testRelease(
      p.join(directory.path, 'set01'),
      releaseType: ReleaseType.singlePhotoset,
    );
    final tabId = tabManager.addReleaseEditor(release);

    final controller = testController(
      release,
      ImagesStore(),
      tabManager,
      tabId,
    );

    final result = await controller.scan() as PhotosetSuccess;

    expect(release.items.single.path, 'set01');
    expect(release.items.single.fields.value('photoCount'), '2');

    expect(result.values, {
      'totalPhotoCount': '2',
      'minResolution': '100x100',
      'maxResolution': '400x150',
      'imageFormats': 'jpg, png',
    });
  });

  // The scan counts the formats for every photoset type, but a value for a name
  // the type does not have is stored and never shown, so it is not written
  // (`ai/single_photoset.md` §3).
  test('a value for a name the type does not have is not written', () async {
    writePhotoAt('set01', 'a.jpg', 100, 100);

    final tabManager = TabManager();
    final release = testRelease(directory.path);
    final tabId = tabManager.addReleaseEditor(release);

    final controller = testController(
      release,
      ImagesStore(),
      tabManager,
      tabId,
    );

    final result = await controller.scan() as PhotosetSuccess;

    expect(result.values.keys, [
      'photosetCount',
      'totalPhotoCount',
      'minResolution',
      'maxResolution',
    ]);
  });

  // A re-scan replaces the items, because the scan is what says what the source
  // contains.
  test('a re-scan replaces the items', () async {
    Directory(p.join(directory.path, 'set01')).createSync();
    writePhoto('set01', 'a.png', 100, 100);

    final tabManager = TabManager();
    final release = testRelease(directory.path);
    final tabId = tabManager.addReleaseEditor(release);

    final controller = testController(
      release,
      ImagesStore(),
      tabManager,
      tabId,
    );

    await controller.scan();

    // The source changed on disk: one set is gone and a loose file appeared.
    // The re-scan is what notices, and it replaces what it recorded before.
    Directory(p.join(directory.path, 'set01')).deleteSync(recursive: true);
    Directory(p.join(directory.path, 'set02')).createSync();
    writePhoto('set02', 'a.png', 100, 100);
    File(p.join(directory.path, 'cover.png'))
        .writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);

    final result = await controller.scan() as PhotosetSuccess;

    expect(release.items.map((item) => item.path), ['set02']);
    expect(result.skipped, ['cover.png']);
  });

  // The name shown is derived from the path, because the stored path is the
  // record ID.
  test('the display name is derived from the path, not stored', () {
    final controller = testController(
      testRelease(directory.path),
      ImagesStore(),
      TabManager(),
      'tab-1',
    );

    // The name is derived from the path, and the same name is the folder the
    // copied photos go in.
    expect(controller.displayName('set01.zip'), 'set01');
  });

  testWidgets('the section shows the photosets with their counts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    Directory(p.join(directory.path, 'set01')).createSync();
    writePhoto('set01', 'a.png', 100, 100);
    File(p.join(directory.path, 'cover.png'))
        .writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);

    final release = testRelease(directory.path);
    final applied = <Map<String, String>>[];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PhotosetScanner>(create: (_) => testScanner()),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PhotosetSection(
                release: release,
                tabId: 'tab-1',
                onApplyValues: (values) => applied.add(values),
              ),
            ),
          ),
        ),
      ),
    );

    // Nothing is shown before the scan: opening a release is a read and changes
    // nothing.
    expect(
      find.text('There are no photosets. Pick the folder and scan it.'),
      findsOneWidget,
    );

    await clickAndWait(tester, find.text('Scan'), find.text('set01'));

    expect(find.text('set01'), findsOneWidget);
    expect(find.text('1 photos'), findsOneWidget);

    // The values go through the editor's write path, not the section's.
    expect(applied.single['photosetCount'], '1');
    expect(applied.single['totalPhotoCount'], '1');

    // What the scan could not take is reported rather than guessed at.
    expect(find.text('Not photosets: cover.png'), findsOneWidget);
  });

  // The two buttons are in the title row, at the right of the section's title,
  // because they are the actions of the whole section rather than a row inside
  // it.
  testWidgets('the Scan and Pick buttons are in the title row', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final release = testRelease('');
    final applied = <Map<String, String>>[];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PhotosetScanner>(create: (_) => testScanner()),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PhotosetSection(
                release: release,
                tabId: 'tab-1',
                onApplyValues: (values) => applied.add(values),
              ),
            ),
          ),
        ),
      ),
    );

    for (final key in ['photosetScanButton', 'photosetPickButton']) {
      expect(
        find.ancestor(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(SectionTitle),
        ),
        findsOneWidget,
      );
    }
  });

  // The same widget for a single set: the layout is not branched on the type,
  // only the strings it shows are (`ai/single_photoset.md` §4, §7).
  testWidgets('the section shows the strings of the type it is showing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    writePhotoAt('set01', 'a.png', 100, 100);

    // The source is empty at first, so the section says which folder it needs.
    final release = testRelease('', releaseType: ReleaseType.singlePhotoset);
    final applied = <Map<String, String>>[];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PhotosetScanner>(create: (_) => testScanner()),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PhotosetSection(
                release: release,
                tabId: 'tab-1',
                onApplyValues: (values) => applied.add(values),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Photoset'), findsOneWidget);
    expect(
      find.text('There are no photos. Pick the folder and scan it.'),
      findsOneWidget,
    );

    await clickAndWait(
      tester,
      find.text('Scan'),
      find.text('Pick the folder with the photos first.'),
    );

    expect(find.text('Pick the folder with the photos first.'), findsOneWidget);

    // The scan itself is the same for both types; only the words differ.
    release.source = p.join(directory.path, 'set01');

    await clickAndWait(tester, find.text('Scan'), find.text('set01'));

    expect(find.text('set01'), findsOneWidget);
    expect(find.text('1 photos'), findsOneWidget);

    expect(applied.last['imageFormats'], 'png');
    expect(applied.last.containsKey('photosetCount'), isFalse);
  });

  testWidgets('a source that is not there is shown as a message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final release = testRelease(p.join(directory.path, 'missing'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PhotosetScanner>(create: (_) => testScanner()),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PhotosetSection(
                release: release,
                tabId: 'tab-1',
                onApplyValues: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    await clickAndWait(
      tester,
      find.text('Scan'),
      find.text('The picked folder was not found.'),
    );

    expect(find.text('The picked folder was not found.'), findsOneWidget);
  });

  testWidgets('a display name two items would share is shown as a message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    Directory(p.join(directory.path, 'set01')).createSync();
    writePhoto('set01', 'a.png', 100, 100);

    // The archive is not a real one: the point here is the report, not the
    // reader.
    File(p.join(directory.path, 'set01.zip'))
        .writeAsStringSync('not a real archive');

    final release = testRelease(directory.path);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PhotosetScanner>(
            create: (_) => PhotosetScanner(
              readers: [const DirectoryPhotosetReader(), _FakeArchiveReader()],
            ),
          ),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PhotosetSection(
                release: release,
                tabId: 'tab-1',
                onApplyValues: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    await clickAndWait(
      tester,
      find.text('Scan'),
      find.text('Names that collide: set01 (set01, set01.zip)'),
    );

    // The two items keep their own paths, which are their IDs; only the names
    // shown for them collide, and the scan reports that rather than renaming
    // anything.
    expect(
      find.text('Names that collide: set01 (set01, set01.zip)'),
      findsOneWidget,
    );
  });

  // The rule itself is tested in `photoset_pick_test.dart`. These are the parts
  // that write.
  test('the pick copies the photos the rule picked and records them', () async {
    // 20 photos in two sets: the rule picks 5, three from the first and two
    // from the second.
    for (var index = 0; index < 10; index++) {
      writePhotoAt('source/set01', '${index.toString().padLeft(3, '0')}.png');
    }

    for (var index = 0; index < 10; index++) {
      writePhotoAt('source/set02', '${index.toString().padLeft(3, '0')}.png');
    }

    final tabManager = TabManager();
    final store = ImagesStore();
    final release = testRelease(p.join(directory.path, 'source'));
    final tabId = tabManager.addReleaseEditor(release);

    final controller = testController(release, store, tabManager, tabId);

    final scan = await controller.scan() as PhotosetSuccess;
    final result = await controller.pick(scan.scan);

    // The release folder mirrors the structure the user picked, so the folder
    // carries the display name, and the record path is relative to the release
    // directory.
    expect(result.written.map((record) => record.file), [
      'set01/001.png',
      'set01/005.png',
      'set01/008.png',
      'set02/002.png',
      'set02/007.png',
    ]);

    for (final record in result.written) {
      expect(File(controller.absolutePath(record)).existsSync(), isTrue);
    }

    // The record links to the item by its path, which is the ID.
    expect(result.written.first.item, 'set01');
    expect(result.written.first.kind, ImageKind.photo);

    expect(store.loadSync(directory.path).of(ImageKind.photo), hasLength(5));
  });

  // With no override the rule is deterministic, so a second run writes the same
  // photos and the manifest holds them once.
  test('a re-pick replaces the photo records it writes', () async {
    for (var index = 0; index < 10; index++) {
      writePhotoAt('source/set01', '${index.toString().padLeft(3, '0')}.png');
    }

    final tabManager = TabManager();
    final store = ImagesStore();
    final release = testRelease(p.join(directory.path, 'source'));
    final tabId = tabManager.addReleaseEditor(release);

    final controller = testController(release, store, tabManager, tabId);

    final scan = await controller.scan() as PhotosetSuccess;

    await controller.pick(scan.scan);
    final second = await controller.pick(scan.scan);

    expect(
      store.loadSync(directory.path).of(ImageKind.photo),
      hasLength(second.written.length),
    );
  });

  // A poster belongs to the release rather than to an item, and a pick is not
  // what writes it.
  test('a pick keeps the records of other kinds', () async {
    for (var index = 0; index < 10; index++) {
      writePhotoAt('source/set01', '${index.toString().padLeft(3, '0')}.png');
    }

    final tabManager = TabManager();
    final store = ImagesStore();
    final release = testRelease(p.join(directory.path, 'source'));
    final tabId = tabManager.addReleaseEditor(release);

    final controller = testController(release, store, tabManager, tabId);

    await store.save(
      directory.path,
      ImagesManifest(
        images: [
          const ImageRecord(
            item: null,
            kind: ImageKind.poster,
            file: 'poster.png',
            urls: {},
          ),
        ],
      ),
    );

    final scan = await controller.scan() as PhotosetSuccess;
    final result = await controller.pick(scan.scan);

    final manifest = store.loadSync(directory.path);

    expect(manifest.of(ImageKind.poster), hasLength(1));
    expect(manifest.of(ImageKind.photo), hasLength(result.written.length));
  });

  test('a photo that cannot be copied is reported, not guessed at', () async {
    for (var index = 0; index < 10; index++) {
      writePhotoAt('source/set01', '${index.toString().padLeft(3, '0')}.png');
    }

    final tabManager = TabManager();
    final store = ImagesStore();
    final release = testRelease(p.join(directory.path, 'source'));
    final tabId = tabManager.addReleaseEditor(release);

    final controller = testController(release, store, tabManager, tabId);

    final scan = await controller.scan() as PhotosetSuccess;

    // The file the rule picked is gone by the time the pick runs.
    File(p.join(directory.path, 'source/set01/001.png')).deleteSync();

    final result = await controller.pick(scan.scan);

    expect(result.notCopied, ['set01/001.png']);
    expect(result.written.map((record) => record.file), [
      'set01/003.png',
      'set01/005.png',
      'set01/007.png',
      'set01/009.png',
    ]);
  });

  test('a set with no photos contributes nothing and is reported', () async {
    Directory(p.join(directory.path, 'source/set01'))
        .createSync(recursive: true);
    writePhotoAt('source/set02', 'a.png');

    final tabManager = TabManager();
    final store = ImagesStore();
    final release = testRelease(p.join(directory.path, 'source'));
    final tabId = tabManager.addReleaseEditor(release);

    final controller = testController(release, store, tabManager, tabId);

    final scan = await controller.scan() as PhotosetSuccess;
    final result = await controller.pick(scan.scan);

    expect(result.emptySets, ['set01']);
    expect(result.written.map((record) => record.file), ['set02/a.png']);
  });

  testWidgets('the picked photos are shown grouped per set', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    for (var index = 0; index < 10; index++) {
      writePhotoAt('source/set01', '${index.toString().padLeft(3, '0')}.png');
    }

    for (var index = 0; index < 10; index++) {
      writePhotoAt('source/set02', '${index.toString().padLeft(3, '0')}.png');
    }

    final release = testRelease(p.join(directory.path, 'source'));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PhotosetScanner>(create: (_) => testScanner()),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PhotosetSection(
                release: release,
                tabId: 'tab-1',
                onApplyValues: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    // The rule reads the counts, so it cannot run before the scan has.
    final pickButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('photosetPickButton')),
    );
    expect(pickButton.onPressed, isNull);

    await clickAndWait(tester, find.text('Scan'), find.text('set01'));

    // Nothing is copied yet, so nothing is shown: the section shows what is on
    // disk.
    expect(find.text('3 picked'), findsNothing);

    await clickAndWait(tester, find.text('Pick'), find.text('3 picked'));

    expect(find.text('3 picked'), findsOneWidget);
    expect(find.text('2 picked'), findsOneWidget);

    // The picks are the interval centres of each set, in the order the source
    // gives them.
    expect(find.text('001.png'), findsOneWidget);
    expect(find.text('005.png'), findsOneWidget);
    expect(find.text('008.png'), findsOneWidget);
    expect(find.text('002.png'), findsOneWidget);
    expect(find.text('007.png'), findsOneWidget);
  });

  testWidgets(
    'the grid places each tile where the packing put it, and a landscape spans two',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      // Three photos: a portrait, a landscape, and one whose header is not one
      // the reader understands. The tiles cannot share one shape, and the third
      // takes a square.
      writePhotoAt('source/set01', 'a.png', 100, 300);
      writePhotoAt('source/set01', 'b.png', 300, 100);
      writeRawAt('source/set01', 'c.png', [0x47, 0x49, 0x46, 0x38, 0x39]);

      final release = testRelease(p.join(directory.path, 'source'));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<PhotosetScanner>(create: (_) => testScanner()),
            ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
            Provider<ImagesStore>(create: (_) => ImagesStore()),
            Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: PhotosetSection(
                  release: release,
                  tabId: 'tab-1',
                  onApplyValues: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      await clickAndWait(tester, find.text('Scan'), find.text('set01'));

      await clickAndWait(tester, find.text('Pick'), find.byType(Positioned));

      final boxes = tester
          .widgetList<Positioned>(find.byType(Positioned))
          .toList();

      // The order is the order the source gives, so the second box is the
      // landscape: two columns wide, while the other two take one.
      expect(boxes.length, 3);

      final columnWidth = boxes[0].width!;

      expect(boxes[1].width, 2 * columnWidth);
      expect(boxes[2].width, columnWidth);

      // Each box is the shape the photo is. The name line and the gap are the
      // section's constants, so the image is the rest of the box. The widget
      // works with the width it is given, so the values are compared with the
      // rounding a division by a column count introduces.
      const labelAndGap = 28.0;

      expect(
        boxes[0].height! - labelAndGap,
        closeTo(columnWidth / (100 / 300), 0.01),
      );
      expect(
        boxes[1].height! - labelAndGap,
        closeTo(2 * columnWidth / (300 / 100), 0.01),
      );
      expect(boxes[2].height! - labelAndGap, closeTo(columnWidth, 0.01));
    },
  );
}

/// A reader for an archive, so two items can share a display name without
/// writing a real ZIP.
class _FakeArchiveReader implements PhotosetReader {
  @override
  bool canRead(SourceEntry entry) => entry.name.endsWith('.zip');

  @override
  Future<List<ScannedPhoto>> read(String path) async => [
    const ScannedPhoto(name: 'a.png'),
  ];

  @override
  Future<List<int>> photoBytes(String path, String name) async {
    try {
      return await File(p.join(path, name)).readAsBytes();
    } catch (_) {
      return const [];
    }
  }
}
