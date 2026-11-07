import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/feature/photosets/photosets_controller.dart';
import 'package:release_prepper/feature/photosets/photoset_block.dart';
import 'package:release_prepper/feature/photosets/photoset_gallery.dart';
import 'package:release_prepper/feature/photosets/photoset_group.dart';
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
import 'package:release_prepper/service/images/masonry.dart';
import 'package:release_prepper/service/photosets/directory_reader.dart';
import 'package:release_prepper/service/photosets/photoset_picker.dart';
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

  PhotosetController testController(
    Release release,
    ImagesStore store,
    TabManager tabManager,
    String tabId, {
    List<PhotosetReader>? readers,
  }) => PhotosetController(
    release: release,
    scanner: PhotosetScanner(
      readers: readers ?? [const DirectoryPhotosetReader()],
    ),
    store: store,
    releaseStore: ReleaseStore(),
    tabManager: tabManager,
    tabId: tabId,
  );

  // The state the two widgets share is built by the editor, so a test builds it the
  // way the editor does.
  PhotosetState testState(Release release, {List<PhotosetReader>? readers}) {
    final tabManager = TabManager();
    final tabId = tabManager.addReleaseEditor(release);

    return PhotosetState(
      controller: testController(
        release,
        ImagesStore(),
        tabManager,
        tabId,
        readers: readers,
      ),
    );
  }

  // The block is the page's first column and the gallery the columns after it, so a
  // test that shows a pack builds both with the state they share. A test is not the
  // editor, so it cannot rebuild on a run the way the editor does; where a test
  // needs the gallery to show what a run wrote, it calls this again, which builds
  // both widgets again against the state the run changed.
  Future<void> openPhotosets(
    WidgetTester tester,
    PhotosetState state, {
    void Function(Map<String, String> values) onApplyValues = discardValues,
    int? columnCount,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PhotosetBlock(
                  state: state,
                  onApplyValues: onApplyValues,
                  onRunWritten: () {},
                ),
                if (columnCount != null)
                  PhotosetGallery(state: state, columnCount: columnCount),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

  testWidgets('the block shows the photosets with their counts', (
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
    final state = testState(release);

    await openPhotosets(
      tester,
      state,
      onApplyValues: (values) => applied.add(values),
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

    // The values go through the editor's write path, not the block's.
    expect(applied.single['photosetCount'], '1');
    expect(applied.single['totalPhotoCount'], '1');

    // What the scan could not take is reported rather than guessed at.
    expect(find.text('Not photosets: cover.png'), findsOneWidget);
  });

  // The two buttons are in the block's heading row, at the right of its title,
  // because they are the actions of the whole block rather than a row inside it.
  testWidgets('the Scan and Pick buttons are in the heading row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final release = testRelease('');
    final state = testState(release);

    await openPhotosets(tester, state);

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

  // The same block for a single set: the strings are the ones that read wrong for
  // one set, so they are resolved per type, and it shows the photos itself because
  // a single set has no columns to put them in (`ai/single_photoset.md` §4, §7).
  testWidgets('the block shows the strings of the type it is showing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    writePhotoAt('set01', 'a.png', 100, 100);

    // The source is empty at first, so the block says which folder it needs.
    final release = testRelease('', releaseType: ReleaseType.singlePhotoset);
    final applied = <Map<String, String>>[];
    final state = testState(release);

    await openPhotosets(
      tester,
      state,
      onApplyValues: (values) => applied.add(values),
    );

    // One title, and it is the one this type reads right for one set.
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
    final state = testState(release);

    await openPhotosets(tester, state);

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
    final state = testState(
      release,
      readers: [const DirectoryPhotosetReader(), _FakeArchiveReader()],
    );

    await openPhotosets(tester, state);

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

  // The block names each set with its counts, and the gallery shows the photos the
  // rule picked for it in the column that set is placed in (`ai/picking.md` §7).
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
    final state = testState(release);

    await openPhotosets(tester, state, columnCount: 1);

    // The rule reads the counts, so it cannot run before the scan has.
    final pickButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('photosetPickButton')),
    );
    expect(pickButton.onPressed, isNull);

    await clickAndWait(tester, find.text('Scan'), find.text('set01'));

    // Nothing is copied yet, so nothing is shown: the block shows what is on disk.
    expect(
      find.descendant(
        of: find.byKey(ValueKey(('groupHeader', 'set01'))),
        matching: find.text('3 picked'),
      ),
      findsNothing,
    );

    await clickAndWait(tester, find.text('Pick'), find.text('3 picked'));

    // The counts are read from the block, which is where the sets are named. The
    // same line is drawn above each column, so the test reads the block's.
    expect(
      find.descendant(
        of: find.byKey(ValueKey(('groupHeader', 'set01'))),
        matching: find.text('3 picked'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey(('groupHeader', 'set02'))),
        matching: find.text('2 picked'),
      ),
      findsOneWidget,
    );

    // A run rebuilds the block, which is the widget that ran it. The gallery is
    // another widget, so it is rebuilt by the page that places both — here the test
    // builds it again the way the editor does.
    await openPhotosets(tester, state, columnCount: 1);

    // The picks are the interval centres of each set, in the order the source gives
    // them, and each is the tile the gallery draws in its own set's column.
    for (final name in [
      'set01/001.png',
      'set01/005.png',
      'set01/008.png',
      'set02/002.png',
      'set02/007.png',
    ]) {
      expect(
        find.byKey(ValueKey(('groupTile', p.join(directory.path, name)))),
        findsOneWidget,
      );
    }
  });

  // A single photoset is one set, so its photos are placed by the masonry: a
  // landscape spans two columns, and the tiles cannot share one shape
  // (`ai/single_photoset.md` §6). The block is the whole width below the form, so it
  // is not given columns and fits its own (`ai/picking.md` §7).
  testWidgets(
    'a single photoset places its tiles by the masonry, and a landscape spans two',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      // The source is the set, so the photos are at its top level. Three of
      // them: a portrait, a landscape, and one whose header is not one the
      // reader understands. The tiles cannot share one shape, and the third
      // takes a square. A set this small is picked in full (`ai/picking.md` §1),
      // so all three are drawn.
      writePhotoAt('source', 'a.png', 100, 300);
      writePhotoAt('source', 'b.png', 300, 100);
      writeRawAt('source', 'c.png', [0x47, 0x49, 0x46, 0x38, 0x39]);

      final release = testRelease(
        p.join(directory.path, 'source'),
        releaseType: ReleaseType.singlePhotoset,
      );
      final state = testState(release);

      await openPhotosets(tester, state);

      await clickAndWait(tester, find.text('Scan'), find.text('source'));

      // The block draws these itself, so it is the widget a run rebuilds.
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
      // constants the feature lays tiles out with, so the image is the rest of the
      // box. The widget works with the width it is given, so the values are compared
      // with the rounding a division by a column count introduces.
      final labelAndGap = photosetLabelHeight + photosetTileGap;

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

  // The pack groups by set instead: one column per set, its photos stacked at one
  // width, and the line naming the set above them (`ai/picking.md` §7,
  // `ai/photoset_pack.md` §6). The drawing uses the same heights the assignment
  // works with, so the test works the placement out with the rule and the packing
  // and compares the boxes against it.
  testWidgets('the pack draws each set in the column the assignment gives', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    // Four sets of three, so more sets than columns: the last one has to share
    // a column. The first set's photos are taller than the others, so the
    // shortest column is not the one with the set's number. The dimensions are
    // the ratios themselves, so the test compares with the same numbers the
    // reader will read from the fixtures.
    const sets = ['set01', 'set02', 'set03', 'set04'];
    const sizes = [
      [100, 300],
      [100, 100],
      [100, 100],
      [100, 100],
    ];
    final ratios = [for (final size in sizes) size[0] / size[1]];

    for (var set = 0; set < sets.length; set++) {
      for (var index = 0; index < 3; index++) {
        writePhotoAt(
          'source/${sets[set]}',
          'p$index.png',
          sizes[set][0],
          sizes[set][1],
        );
      }
    }

    const columnCount = 3;

    final release = testRelease(p.join(directory.path, 'source'));
    final state = testState(release);

    // What the rule picks for this fixture, in the order the source gives it:
    // the test asks the rule rather than assuming, so the names it compares are
    // the ones the pick will write.
    final scanned = [
      for (var set = 0; set < sets.length; set++)
        ScannedSet(
          entry: SourceEntry(
            name: sets[set],
            isDirectory: true,
            readPath: sets[set],
          ),
          photos: [
            for (var index = 0; index < 3; index++)
              ScannedPhoto(name: 'p$index.png'),
          ],
        ),
    ];
    final picks = PhotosetPicker.pick(scanned);

    await openPhotosets(tester, state, columnCount: columnCount);

    await clickAndWait(tester, find.text('Scan'), find.text('set01'));

    // The pick runs in the block, which is the widget that ran it; the gallery is
    // another widget, so a run reaches it only when the page builds again — here the
    // test builds it again the way the editor does. The wait is on the block's line,
    // because the pick is what makes the picked count appear on it.
    await clickAndWait(
      tester,
      find.text('Pick'),
      find.descendant(
        of: find.byKey(const ValueKey(('groupHeader', 'set01'))),
        matching: find.text('2 picked'),
      ),
    );

    await openPhotosets(tester, state, columnCount: columnCount);

    // The names the pick wrote, in the order the source gives them: the paths the
    // gallery keys its tiles by.
    final namesBySet = [
      for (final pick in picks.picks)
        [
          for (final photo in pick.photos)
            p.join(directory.path, pick.set.path, photo.name),
        ],
    ];

    // The constants the feature lays a group out with: the line naming it, the name
    // line under a tile, and the padding inside each tile. The gap between the
    // columns is the shared one.
    //
    // The width the gallery works with, taken from what it drew: the test cannot
    // know what a widget is given by its parent, so it reads the drawing. The first
    // group is always placed in the first column, so its line is where the test
    // reads the column width from.
    final firstLine = find.byKey(ValueKey(('groupColumnHeader', 0, sets[0])));
    final columnWidth = tester.getRect(firstLine).width;

    expect(namesBySet.map((names) => names.length).toList(), [2, 1, 1, 1]);

    final heights = [
      for (var set = 0; set < sets.length; set++)
        groupHeight(
          [for (final _ in namesBySet[set]) ratios[set]],
          columnWidth,
          photosetHeaderHeight,
          photosetLabelHeight,
          photosetTileGap,
        ),
    ];

    final columns = groupColumns(
      groupHeights: heights,
      columnCount: columnCount,
    );

    // The fourth set shares a column, and it is not the column with its number: it
    // is the one that was highest up when it was placed.
    expect(columns, [0, 1, 2, 1]);

    // The gallery's title row is above the grid, and its height comes from measuring
    // text, which the test cannot compute from the constants. So the test takes the
    // top of the grid from what it drew: the first group is the one at the top of the
    // first column, and every other group is compared against that origin.
    final gridTop = tester.getRect(firstLine).top;

    var columnTops = List.filled(columnCount, 0.0);

    for (var set = 0; set < sets.length; set++) {
      final column = columns[set];
      final left = column * (columnWidth + columnGap);
      final top = gridTop + columnTops[column];

      final line = tester.getRect(
        find.byKey(ValueKey(('groupColumnHeader', column, sets[set]))),
      );

      expect(line.left, closeTo(left, 0.5));
      expect(line.top, closeTo(top, 0.5));

      var tileTop = top + photosetHeaderHeight;

      for (final name in namesBySet[set]) {
        final tile = tester.getRect(find.byKey(ValueKey(('groupTile', name))));

        expect(tile.left, closeTo(left, 0.5));
        expect(tile.top, closeTo(tileTop, 0.5));

        tileTop += tileHeight(
          ratios[set],
          columnWidth,
          photosetLabelHeight,
          photosetTileGap,
        );
      }

      columnTops[column] += heights[set];
    }

    // The block in the first column lists the same lines, in the order the source
    // gives them, and says nothing about which column a set is drawn in — that is
    // what the assignment above works out (`ai/picking.md` §7).
    for (final set in sets) {
      expect(find.byKey(ValueKey(('groupHeader', set))), findsOneWidget);
    }
  });

  // A set with no photos still takes its column: the line naming it is drawn on
  // its own, because the scan found that set (`ai/photoset_pack.md` §6).
  testWidgets('a set with no picked photos still shows its line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    for (var index = 0; index < 3; index++) {
      writePhotoAt('source/set01', 'p$index.png', 100, 100);
    }

    // A set the scan finds but cannot read has nothing to show but its line.
    Directory(p.join(directory.path, 'source/set02'))
        .createSync(recursive: true);

    final release = testRelease(p.join(directory.path, 'source'));
    final state = testState(release);

    await openPhotosets(tester, state, columnCount: 3);

    await clickAndWait(tester, find.text('Scan'), find.text('set02'));

    // Each set is named in the block, and the same line is drawn above the column
    // its photos are in.
    for (final set in ['set01', 'set02']) {
      expect(find.byKey(ValueKey(('groupHeader', set))), findsOneWidget);
    }

    // A set this small is picked in full, so the pick writes all three; the set with
    // no photos is picked as nothing. The wait is on the block's line, because that
    // is where the picked count appears.
    await clickAndWait(
      tester,
      find.text('Pick'),
      find.descendant(
        of: find.byKey(const ValueKey(('groupHeader', 'set01'))),
        matching: find.text('3 picked'),
      ),
    );

    // The gallery shows what the pick wrote only when the page builds again, so the
    // test builds it again the way the editor does.
    await openPhotosets(tester, state, columnCount: 3);

    expect(
      find.byKey(const ValueKey(('groupColumnHeader', 0, 'set01'))),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey(('groupColumnHeader', 1, 'set02'))),
      findsOneWidget,
    );

    // Only the set with photos has anything under its line. The tile keys are the
    // paths the gallery shows the photos from, as in the drawing test.
    final names = [
      for (var index = 0; index < 3; index++)
        p.join(directory.path, 'set01', 'p$index.png'),
    ];

    for (final name in names) {
      expect(find.byKey(ValueKey(('groupTile', name))), findsOneWidget);
    }

    // Two lines and three tiles: nothing is drawn under the line of the set with
    // no photos.
    expect(find.byType(Positioned), findsNWidgets(2 + 3));
  });
}

/// What the block hands to the editor's write path is the values the scan counted.
/// A test that does not check them takes a function that takes nothing, because the
/// helper's default has to be one value rather than a function written at each call.
void discardValues(Map<String, String> values) {}

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
