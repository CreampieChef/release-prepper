import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/feature/photosets/photosets_controller.dart';
import 'package:release_prepper/feature/photosets/photoset_block.dart';
import 'package:release_prepper/feature/photosets/photoset_gallery.dart';
import 'package:release_prepper/feature/photosets/photoset_group.dart';
import 'package:release_prepper/feature/progress_row.dart';
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

  // The size a photo has is the bytes the fixture wrote, so the total a test
  // expects is the sum of the fixtures it wrote rather than a number written
  // out.
  String totalOf(List<List<int>> fixtures) =>
      '${fixtures.fold(0, (total, bytes) => total + bytes.length)}';

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

  // The options a test that is not about the popup passes to the rule: the count
  // the curve gives for the total, the division per set, and the extremes not
  // asked for — the answer `confirmPick` gives the popup, so a controller test
  // and a widget test that compare the same fixture get the same picks.
  PickOptions defaultOptions(int total) => PickOptions(
    count: PhotosetPicker.initialCount(total),
    strategy: PickStrategy.perSet,
    includeExtremes: false,
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
  //
  // The gallery is only built when the test is about the pack, because a single
  // photoset has no area beside its block.
  Future<void> openPhotosets(
    WidgetTester tester,
    PhotosetState state, {
    void Function(Map<String, String> values) onApplyValues = discardValues,
    bool showGallery = false,
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
                if (showGallery) PhotosetGallery(state: state),
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
  //
  // A test that looks at what a run shows while it is going — a set that has
  // been read while the next one is still being read — waits on the count the
  // progress row says, so it uses `waitUntil` on its own. A test that needs the run
  // to be over cannot wait for the first thing the run draws, because a run draws
  // those before it ends: it waits for the end, which is what `scanAndWait` and
  // `confirmPick` do. Both only work inside `runAsync`, because the scan reads on
  // another isolate and the event loop is only real there.
  Future<void> waitUntil(WidgetTester tester, Finder until) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));

    while (DateTime.now().isBefore(deadline)) {
      await tester.pump();

      if (until.evaluate().isNotEmpty) {
        return;
      }

      await Future.delayed(const Duration(milliseconds: 10));
    }

    throw StateError(
      '${until.describeMatch(Plurality.one)} did not appear within 10 seconds',
    );
  }

  Future<void> clickAndWait(
    WidgetTester tester,
    Finder trigger,
    Finder until,
  ) async {
    await tester.runAsync(() async {
      await tester.tap(trigger);

      await waitUntil(tester, until);
    });
  }

  // A test that needs a run to be over — because what it asserts next is what the
  // run does at its end, or because it clicks a button that only works after the
  // run — waits for the end itself, not for the first thing the run shows. For the
  // block the end is the point Pick gains its action, because Pick is disabled until
  // a scan has run: the lines and the counts are drawn while the scan reads the
  // sets, so a test that waits for a line and then taps Pick taps a button with
  // nothing to do. The end of a run is one block in the widget, so when that action
  // exists the values the run applied and the report it showed are already there.
  Future<void> scanAndWait(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Scan'));

      final deadline = DateTime.now().add(const Duration(seconds: 10));

      while (DateTime.now().isBefore(deadline)) {
        await tester.pump();

        final pick = tester.widget<FilledButton>(
          find.byKey(const ValueKey('photosetPickButton')),
        );

        if (pick.onPressed != null) {
          return;
        }

        await Future.delayed(const Duration(milliseconds: 10));
      }

      throw StateError('Pick was not enabled within 10 seconds');
    });
  }

  // Pick now asks the popup first, so a test that wants the run to happen has to
  // answer it. These tests are not about the popup, so the helper answers with
  // what the popup opened with — the count and the strategy — and with the
  // extremes off, because a test that is not about the extremes builds a fixture
  // with no dimensions, and the extremes are the only part of the rule that reads
  // them. Answering with them on would pick photos the fixture cannot describe,
  // so the answer the helper gives is the one `defaultOptions` describes, and the
  // numbers a widget test compares are the run's own.
  //
  // `until` must be the last thing the run changes, not the first: the run
  // reports each photo as it copies it, so a wait that is satisfied by the first
  // number to move leaves the run going while the test asserts the rest of it.
  // Waiting on the last number the run can reach means the run is over when the
  // wait returns.
  Future<void> confirmPick(WidgetTester tester, Finder until) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('pickExtremesCheckbox')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('pickConfirmButton')));

      await waitUntil(tester, until);
    });
  }

  // The pair a set's line shows: the number the rule picked for that set and the
  // number the scan counted it (`ai/picking.md` §7). Both the waits and the
  // assertions use this, so a test compares against what the rule gave rather
  // than against numbers copied into the test.
  Finder lineFor(String set, int picked, int total) => find.descendant(
    of: find.byKey(ValueKey(('groupHeader', set))),
    matching: find.text('$picked / $total'),
  );

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

      final result = await controller.scan(
        onProgress: discardScanProgress,
      ) as PhotosetSuccess;

      expect(release.items.single.path, 'set01');
      expect(release.items.single.type, 'photoset');
      expect(release.items.single.fields.value('photoCount'), '2');

      expect(result.values, {
        'photosetCount': '1',
        'totalPhotoCount': '2',
        'totalSize': totalOf([pngPhoto(100, 100), pngPhoto(400, 150)]),
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

    final result = await controller.scan(
      onProgress: discardScanProgress,
    ) as PhotosetSuccess;

    expect(release.items.single.path, 'set01');
    expect(release.items.single.fields.value('photoCount'), '2');

    expect(result.values, {
      'totalPhotoCount': '2',
      'totalSize': totalOf([pngPhoto(100, 100), pngPhoto(400, 150)]),
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

    final result = await controller.scan(
      onProgress: discardScanProgress,
    ) as PhotosetSuccess;

    expect(result.values.keys, [
      'photosetCount',
      'totalPhotoCount',
      'totalSize',
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

    await controller.scan(onProgress: discardScanProgress);

    // The source changed on disk: one set is gone and a loose file appeared.
    // The re-scan is what notices, and it replaces what it recorded before.
    Directory(p.join(directory.path, 'set01')).deleteSync(recursive: true);
    Directory(p.join(directory.path, 'set02')).createSync();
    writePhoto('set02', 'a.png', 100, 100);
    File(p.join(directory.path, 'cover.png'))
        .writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);

    final result = await controller.scan(
      onProgress: discardScanProgress,
    ) as PhotosetSuccess;

    expect(release.items.map((item) => item.path), ['set02']);
    expect(result.skipped, ['cover.png']);
  });

  // What a run reports while it works is what the widgets show while it works, so
  // the reports and the state they change are checked together here
  // (`ai/photoset_pack.md` §4). The scan gives the total before it reads anything,
  // because it decides what the entries are first, and the controller records an
  // item at the report that names it.
  test('an item is recorded at the report that names it', () async {
    writePhotoAt('source/set01', 'a.png', 100, 100);
    writePhotoAt('source/set02', 'b.png', 100, 100);

    final tabManager = TabManager();
    final release = testRelease(p.join(directory.path, 'source'));
    final tabId = tabManager.addReleaseEditor(release);

    final controller = testController(
      release,
      ImagesStore(),
      tabManager,
      tabId,
    );

    // What the items are at each report: nothing at the report that only gives
    // the total, then one set, then two.
    final seen = <List<String>>[];

    final reports = <List<int>>[];

    final result = await controller.scan(
      onProgress: (progress) {
        reports.add([progress.scanned, progress.total]);
        seen.add([for (final item in release.items) item.path]);
      },
    ) as PhotosetSuccess;

    expect(result.scan.sets.map((set) => set.path), ['set01', 'set02']);

    expect(reports, [
      [0, 2],
      [1, 2],
      [2, 2],
    ]);

    expect(seen, [
      [],
      ['set01'],
      ['set01', 'set02'],
    ]);
  });

  // The items are replaced at the report that only gives the total, so a scan
  // that never gets there replaces nothing: a source that cannot be read is not
  // evidence that it is empty.
  test('a scan that does not reach the reading replaces nothing', () async {
    writePhotoAt('source/set01', 'a.png', 100, 100);

    final tabManager = TabManager();
    final release = testRelease(p.join(directory.path, 'source'));
    final tabId = tabManager.addReleaseEditor(release);

    final controller = testController(
      release,
      ImagesStore(),
      tabManager,
      tabId,
    );

    await controller.scan(onProgress: discardScanProgress);

    expect(release.items.map((item) => item.path), ['set01']);

    // The source is gone, so the scan fails before it can name an item, and no
    // report is made.
    Directory(p.join(directory.path, 'source')).deleteSync(recursive: true);

    final failed = await controller.scan(
      onProgress: discardScanProgress,
    ) as PhotosetFailure;

    expect(failed.kind, PhotosetFailureKind.sourceNotFound);
    expect(release.items.map((item) => item.path), ['set01']);
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

    // The wait is for the end of the run: the values and the report are what the
    // run does at its end, not what it draws while it reads the folder.
    await scanAndWait(tester);

    expect(find.text('set01'), findsOneWidget);
    expect(find.text('0 / 1'), findsOneWidget);

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

  // The header naming the list is drawn above the lines, and only for the type
  // that has a list: before a scan there is nothing to name, so nothing is
  // drawn above the placeholder (`ai/picking.md` §7).
  testWidgets('the header naming the list is drawn above the lines', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    writePhotoAt('source/set01', 'a.png', 100, 100);

    final release = testRelease(p.join(directory.path, 'source'));
    final state = testState(release);

    await openPhotosets(tester, state);

    expect(find.text('Photoset List'), findsNothing);

    await scanAndWait(tester);

    expect(find.text('Photoset List'), findsOneWidget);

    // The block's heading row names the block; the header names the lines, so
    // it is drawn below that row and above the first line.
    final heading = tester.getRect(find.text('Photosets'));
    final header = tester.getRect(find.text('Photoset List'));
    final line = tester.getRect(find.byKey(ValueKey(('groupHeader', 'set01'))));

    expect(header.top, greaterThan(heading.bottom));
    expect(line.top, greaterThan(header.bottom));
  });

  // A line appears while the scan is still reading the next set, so a root with
  // many sets shows what it has read rather than nothing until the run ends
  // (`ai/photoset_pack.md` §4). The reader here reads one set and then waits, so
  // the state between the two reports is what the test looks at.
  testWidgets('a line appears while the scan is reading the next set', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    writePhotoAt('source/set01', 'a.png', 100, 100);
    writePhotoAt('source/set02', 'b.png', 100, 100);

    final release = testRelease(p.join(directory.path, 'source'));
    final state = testState(release, readers: [_SlowReader(slow: 'set02')]);

    await openPhotosets(tester, state);

    await tester.runAsync(() async {
      await tester.tap(find.text('Scan'));

      // The count is what the entries gave before any reading, so it says two
      // while only one has been read.
      await waitUntil(tester, find.text('Photosets scanned: 1 / 2'));

      // The row is drawn while the run is going, so it is there in this window.
      expect(find.byType(ProgressRow), findsOneWidget);

      expect(find.text('set01'), findsOneWidget);
      expect(find.text('set02'), findsNothing);

      await waitUntil(tester, find.text('set02'));
    });

    await tester.pump();

    // The run is over, so the row is not drawn for a run that is not going, and
    // the two lines are there.
    expect(find.text('set01'), findsOneWidget);
    expect(find.text('set02'), findsOneWidget);
  });

  // Every other line of the list is tinted, so it reads as bands of text, as the
  // two tables the app has do (`ai/video_pack.md` §5). The parity is the position in
  // the order the items are stored — the order the scan wrote them here — rather
  // than anything the drawing decides.
  testWidgets('the lines of the list alternate', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    for (final set in ['set01', 'set02', 'set03']) {
      writePhotoAt('source/$set', 'a.png', 100, 100);
    }

    final release = testRelease(p.join(directory.path, 'source'));
    final state = testState(release);

    await openPhotosets(tester, state);

    // The wait is for the end of the run, so all three lines are there before they
    // are read: the lines appear one by one as the scan reads them.
    await scanAndWait(tester);

    final theme = Theme.of(tester.element(find.byType(PhotosetBlock)));

    // The line's own `Material` is the nearest one above it, which is the shape the
    // two tables use.
    Material lineMaterial(String path) => tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(ValueKey(('groupHeader', path))),
            matching: find.byType(Material),
          )
          .first,
    );

    expect(lineMaterial('set01').color, Colors.transparent);
    expect(lineMaterial('set02').color, theme.colorScheme.surfaceContainerHigh);
    expect(lineMaterial('set03').color, Colors.transparent);

    // The line's own `Material` is the nearest one above it: the header naming the
    // list is not a line, so it has no band of its own.
    expect(
      find.ancestor(
        of: find.text('Photoset List'),
        matching: find.byType(SectionTitle),
      ),
      findsOneWidget,
    );
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

    // One title, and it is the one this type reads right for one set. The
    // header naming a list is not drawn, because this type has one set
    // (`ai/picking.md` §7).
    expect(find.text('Photoset'), findsOneWidget);
    expect(find.text('Photoset List'), findsNothing);
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

    // The values are what the run applies at its end, so the wait is for the end
    // and not for the first line the scan draws. For this type the block draws no
    // scan row at all — a row counting items says nothing when the item is the
    // folder (`ai/picking.md` §7) — so `set01` and the pair below are the line the
    // block draws for the set it read, not a row for the run.
    await scanAndWait(tester);

    expect(find.text('set01'), findsOneWidget);
    expect(find.text('0 / 1'), findsOneWidget);

    expect(applied.last['imageFormats'], 'png');
    expect(applied.last.containsKey('photosetCount'), isFalse);
  });

  // The scan row is drawn only for the words the type has: for the type whose item
  // is the folder the user picked, a row counting items says nothing and its words
  // are null, so nothing is drawn (`ai/picking.md` §7). A row built from a null
  // value is a widget that throws, and a test that let the run finish before the
  // first build would never reach it — so the run here is genuinely going, held by
  // the reader's own delay, and the block is read while it is mid-run.
  testWidgets('the scan row is drawn only for the words the type has', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    writePhotoAt('source', 'a.png', 100, 100);

    final release = testRelease(
      p.join(directory.path, 'source'),
      releaseType: ReleaseType.singlePhotoset,
    );
    final state = testState(release, readers: [_SlowReader(slow: 'source')]);

    await openPhotosets(tester, state);

    await tester.runAsync(() async {
      await tester.tap(find.text('Scan'));

      // The first report is the one that only gives the total, and it comes before
      // any reading, so the block is built with a run going. The window is the
      // reader's hold, not a guess at how long a run takes.
      await Future.delayed(const Duration(milliseconds: 200));

      await tester.pump();

      // The block itself, not an error widget in its place: a build that threw is
      // the failure this test is about, and it would show here as well as in the
      // row's absence.
      expect(find.byKey(const ValueKey('photosetBlock')), findsOneWidget);
      expect(find.byType(ProgressRow), findsNothing);
    });
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

    final scan = await controller.scan(
      onProgress: discardScanProgress,
    ) as PhotosetSuccess;
    final result = await controller.pick(
      scan.scan,
      defaultOptions(20),
      onProgress: discardCopyProgress,
    );

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

    final scan = await controller.scan(
      onProgress: discardScanProgress,
    ) as PhotosetSuccess;

    await controller.pick(
      scan.scan,
      defaultOptions(10),
      onProgress: discardCopyProgress,
    );
    final second = await controller.pick(
      scan.scan,
      defaultOptions(10),
      onProgress: discardCopyProgress,
    );

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

    final scan = await controller.scan(
      onProgress: discardScanProgress,
    ) as PhotosetSuccess;
    final result = await controller.pick(
      scan.scan,
      defaultOptions(10),
      onProgress: discardCopyProgress,
    );

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

    final scan = await controller.scan(
      onProgress: discardScanProgress,
    ) as PhotosetSuccess;

    // The file the rule picked is gone by the time the pick runs.
    File(p.join(directory.path, 'source/set01/001.png')).deleteSync();

    final result = await controller.pick(
      scan.scan,
      defaultOptions(10),
      onProgress: discardCopyProgress,
    );

    expect(result.notCopied, ['set01/001.png']);
    expect(result.written.map((record) => record.file), [
      'set01/003.png',
      'set01/005.png',
      'set01/007.png',
      'set01/009.png',
    ]);
  });

  // The number a pick reports against is what the rule chose, so it is known
  // before anything is copied, and each photo is reported as it is written
  // (`ai/picking.md` §7).
  test('a pick reports each photo against the total the rule chose', () async {
    for (var index = 0; index < 10; index++) {
      writePhotoAt('source/set01', '${index.toString().padLeft(3, '0')}.png');
    }

    final tabManager = TabManager();
    final store = ImagesStore();
    final release = testRelease(p.join(directory.path, 'source'));
    final tabId = tabManager.addReleaseEditor(release);

    final controller = testController(release, store, tabManager, tabId);

    final scan = await controller.scan(
      onProgress: discardScanProgress,
    ) as PhotosetSuccess;

    final reports = <List<int>>[];
    final files = <String>[];

    final result = await controller.pick(
      scan.scan,
      defaultOptions(10),
      onProgress: (progress) {
        reports.add([progress.done, progress.total]);

        if (progress.record != null) {
          files.add(progress.record!.file);
        }
      },
    );

    // The first report gives the total with nothing written, so the bar has a
    // measure before the first file exists.
    expect(reports.first, [0, 5]);

    // Then one report per photo, in the order the run wrote them, each naming
    // the record it wrote so the caller can show it.
    expect(reports, [
      [0, 5],
      [1, 5],
      [2, 5],
      [3, 5],
      [4, 5],
      [5, 5],
    ]);

    expect(files, result.written.map((record) => record.file));
  });

  // A photo the run could not write does not move the count: the number is what
  // the run wrote, not what it tried, which is the rule the Upload section's bar
  // follows (`ai/upload_images.md`).
  test('a photo that could not be written does not move the count', () async {
    for (var index = 0; index < 10; index++) {
      writePhotoAt('source/set01', '${index.toString().padLeft(3, '0')}.png');
    }

    final tabManager = TabManager();
    final store = ImagesStore();
    final release = testRelease(p.join(directory.path, 'source'));
    final tabId = tabManager.addReleaseEditor(release);

    final controller = testController(release, store, tabManager, tabId);

    final scan = await controller.scan(
      onProgress: discardScanProgress,
    ) as PhotosetSuccess;

    File(p.join(directory.path, 'source/set01/001.png')).deleteSync();

    final reports = <List<int>>[];

    await controller.pick(
      scan.scan,
      defaultOptions(10),
      onProgress: (progress) {
        reports.add([progress.done, progress.total]);
      },
    );

    // Four of the five the rule chose were written, so the count reaches four
    // against five.
    expect(reports, [
      [0, 5],
      [1, 5],
      [2, 5],
      [3, 5],
      [4, 5],
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

    final scan = await controller.scan(
      onProgress: discardScanProgress,
    ) as PhotosetSuccess;
    final result = await controller.pick(
      scan.scan,
      defaultOptions(1),
      onProgress: discardCopyProgress,
    );

    expect(result.emptySets, ['set01']);
    expect(result.written.map((record) => record.file), ['set02/a.png']);
  });
  // The block names each set with its counts, and the grid shows the photos the
  // rule picked for it — every set's photos together, not one column per set,
  // so each tile says which set its photo is from as well as its file name
  // (`ai/picking.md` §7).
  testWidgets('the picked photos are one grid labelled with their set', (
    tester,
  ) async {
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

    await openPhotosets(tester, state, showGallery: true);

    // The rule reads the counts, so it cannot run before the scan has.
    final pickButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('photosetPickButton')),
    );
    expect(pickButton.onPressed, isNull);

    // Pick is the next step, so the run has to be over before it is clicked;
    // waiting on the first line the scan draws would click a button with nothing
    // to do. The lines are what the scan writes as it reads, so all of them are
    // there at the end of a run.
    await scanAndWait(tester);

    // What the rule gives for this fixture, asked rather than assumed, so the
    // names and the numbers the test compares are the rule's own.
    final result = PhotosetPicker.pick([
      for (final set in ['set01', 'set02'])
        ScannedSet(
          entry: SourceEntry(name: set, isDirectory: true, readPath: set),
          photos: [
            // The rule reads counts, not sizes, so the fixture gives none.
            for (var index = 0; index < 10; index++)
              ScannedPhoto(
                name: '${index.toString().padLeft(3, '0')}.png',
                size: 0,
              ),
          ],
        ),
    ], defaultOptions(20));

    // Before a run the first part of the pair is 0 while the second is the count
    // the scan wrote (`ai/picking.md` §7).
    for (final pick in result.picks) {
      expect(lineFor(pick.set.path, 0, pick.set.photoCount), findsOneWidget);
    }

    await clickAndWait(
      tester,
      find.text('Pick'),
      find.byKey(const ValueKey('pickOptionsDialog')),
    );

    // The popup confirms at the values it opened at, and the wait is on the
    // block's line, as it was before the popup existed. It is the last line the
    // run can reach, because the run copies in the order the source gives the
    // sets and reports each photo as it copies it; waiting on the first number
    // that moves would leave the run going while the rest is asserted.
    final last = result.picks.where((pick) => pick.photos.isNotEmpty).last;

    await confirmPick(
      tester,
      lineFor(last.set.path, last.photos.length, last.set.photoCount),
    );

    // Each set is named once, in the block, because the grid does not name a
    // set above its photos — the tile says which set its photo is from.
    for (final pick in result.picks) {
      expect(
        lineFor(pick.set.path, pick.photos.length, pick.set.photoCount),
        findsOneWidget,
      );
    }

    // A run rebuilds the block, which is the widget that ran it. The gallery is
    // another widget, so it is rebuilt by the page that places both — here the test
    // builds it again the way the editor does.
    await openPhotosets(tester, state, showGallery: true);

    // The picks, in the order the source gives the sets and, within a set, the
    // order it gives the photos.
    final picked = [
      for (final pick in result.picks)
        for (final photo in pick.photos) (pick.set.path, photo.name),
    ];

    for (final photo in picked) {
      final path = p.join(directory.path, photo.$1, photo.$2);
      final tile = find.byKey(ValueKey(('photoTile', path)));

      expect(tile, findsOneWidget);

      // The two lines a grid that mixes sets draws: the set it is from, and the
      // file.
      expect(
        find.descendant(of: tile, matching: find.text(photo.$1)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text(photo.$2)),
        findsOneWidget,
      );
    }
  });

  // Pick answers through the popup, so a test that is about the popup itself
  // reads what the popup opened with from the widgets rather than assuming it,
  // and a Cancel is not an agreement: it closes the popup and runs nothing, the
  // same rule as the close popup (`ai/picking.md` §7).
  testWidgets("the popup opens at the rule's values and a Cancel runs nothing", (
    tester,
  ) async {
    for (var set = 0; set < 2; set++) {
      for (var index = 0; index < 10; index++) {
        writePhotoAt(
          'source/set0${set + 1}',
          '${index.toString().padLeft(3, '0')}.png',
        );
      }
    }

    final release = testRelease(p.join(directory.path, 'source'));
    final state = testState(release);

    await openPhotosets(tester, state);

    // Pick cannot run before the scan has, so the wait is for the end of the run
    // rather than for the first line it draws.
    await scanAndWait(tester);

    await tester.tap(find.byKey(const ValueKey('photosetPickButton')));
    await tester.pumpAndSettle();

    // The values it opens at are the rule's: the count the curve gives for the
    // scanned total, the division per set, the extremes kept. The count row is
    // the same shape the Screenshots section has, so the test reads the row from
    // the same widgets.
    final checkbox = tester.widget<Checkbox>(
      find.byKey(const ValueKey('pickExtremesCheckbox')),
    );
    expect(checkbox.value, isTrue);

    final group = tester.widget<RadioGroup<PickStrategy>>(
      find.byKey(const ValueKey('pickStrategy')),
    );
    expect(group.groupValue, PickStrategy.perSet);

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('pickCountSlider')),
    );
    expect(slider.value, 5.0);

    // The initial value is the row's minimum, so the user can only raise it, and
    // only as far as this fixture has: the maximum is the cap taken as far as the
    // pack (`ai/picking.md` §1).
    expect(slider.min, 5.0);
    expect(slider.max, PhotosetPicker.maximumCountFor(20));

    await tester.tap(find.byKey(const ValueKey('pickCancel')));
    await tester.pumpAndSettle();

    // Nothing ran, so the lines still say that nothing has been picked, which is
    // what they say before a run.
    expect(find.byKey(const ValueKey('pickOptionsDialog')), findsNothing);

    for (final set in ['set01', 'set02']) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey(('groupHeader', set))),
          matching: find.text('0 / 10'),
        ),
        findsOneWidget,
      );
    }
  });

  // A pack at or below the rule's minimum: the number the count row would open at
  // is the whole of what the pack has, so there is no range to move it in and the
  // row is not drawn (`ai/picking.md` §1). The run takes what exists, which is the
  // clamping the rule already does, so the test compares against the rule rather
  // than against a number written in it. The part of the popup this fixture does
  // have is drawn: a pack has a choice of strategy, and the row for it is there.
  testWidgets("a pack at or below the rule's minimum shows no count row", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    for (var index = 0; index < 4; index++) {
      writePhotoAt('source/set01', '${index.toString().padLeft(3, '0')}.png');
    }

    final release = testRelease(p.join(directory.path, 'source'));
    final state = testState(release);

    await openPhotosets(tester, state);

    await scanAndWait(tester);

    await tester.tap(find.byKey(const ValueKey('photosetPickButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pickStrategy')), findsOneWidget);
    expect(find.byKey(const ValueKey('pickCountRow')), findsNothing);
    expect(find.byKey(const ValueKey('pickCountSlider')), findsNothing);

    // What the rule gives for this fixture: the count the row would have opened at,
    // taken as far as the four photos that exist.
    final result = PhotosetPicker.pick([
      ScannedSet(
        entry: SourceEntry(name: 'set01', isDirectory: true, readPath: 'set01'),
        photos: [
          // The rule reads counts, not sizes, so the fixture gives none.
          for (var index = 0; index < 4; index++)
            ScannedPhoto(
              name: '${index.toString().padLeft(3, '0')}.png',
              size: 0,
            ),
        ],
      ),
    ], defaultOptions(4));

    await confirmPick(
      tester,
      lineFor('set01', result.picks.single.photos.length, 4),
    );
  });

  // The same for the type whose item is the folder it picked: the count row is not
  // drawn either, because there is no range for it (`ai/picking.md` §1). Its
  // strategy row is absent for a different reason, which the test below this one
  // covers; here the fixture is one set, and its total is the set's own size.
  testWidgets(
    "a single photoset at or below the rule's minimum shows no count row",
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      for (var index = 0; index < 5; index++) {
        writePhotoAt('source', '${index.toString().padLeft(3, '0')}.png');
      }

      final release = testRelease(
        p.join(directory.path, 'source'),
        releaseType: ReleaseType.singlePhotoset,
      );
      final state = testState(release);

      await openPhotosets(tester, state);

      await scanAndWait(tester);

      await tester.tap(find.byKey(const ValueKey('photosetPickButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pickCountRow')), findsNothing);
      expect(find.byKey(const ValueKey('pickCountSlider')), findsNothing);

      // What the rule gives for this fixture: the count the row would have opened
      // at, taken as far as the five photos that exist. The row is absent because
      // the two bounds are equal there, not because the fixture is a particular
      // size, so the number the test compares is the rule's.
      final result = PhotosetPicker.pick([
        ScannedSet(
          entry: SourceEntry(
            name: 'source',
            isDirectory: true,
            readPath: 'source',
          ),
          photos: [
            // The rule reads counts, not sizes, so the fixture gives none.
            for (var index = 0; index < 5; index++)
              ScannedPhoto(
                name: '${index.toString().padLeft(3, '0')}.png',
                size: 0,
              ),
          ],
        ),
      ], defaultOptions(5));

      await confirmPick(
        tester,
        lineFor('source', result.picks.single.photos.length, 5),
      );
    },
  );

  // The popup is one implementation for both photoset types, so the rows it has
  // are drawn for both; the choice of strategy is not one for the type with a
  // single set, because the whole pack is that set and both answers give the same
  // picks, so its row is not drawn (`ai/picking.md` §7, `ai/single_photoset.md`
  // §6). What the popup answers with there is the strategy it opens with, which is
  // the only answer there is, so the run copies what the rule gives for the
  // fixture — the same as the tests that ask the rule rather than assume.
  testWidgets('the popup draws the choice only for the type that has one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    for (var index = 0; index < 10; index++) {
      writePhotoAt('source', '${index.toString().padLeft(3, '0')}.png');
    }

    final release = testRelease(
      p.join(directory.path, 'source'),
      releaseType: ReleaseType.singlePhotoset,
    );
    final state = testState(release);

    await openPhotosets(tester, state);

    await scanAndWait(tester);

    await tester.tap(find.byKey(const ValueKey('photosetPickButton')));
    await tester.pumpAndSettle();

    // The rows this type has are drawn: the checkbox and the slider, at the same
    // values the pack's popup opens at for the same number of photos.
    final checkbox = tester.widget<Checkbox>(
      find.byKey(const ValueKey('pickExtremesCheckbox')),
    );
    expect(checkbox.value, isTrue);

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('pickCountSlider')),
    );
    expect(slider.value, 5.0);

    // The group is not there at all, so a test that read its value would read
    // nothing; the labels for the choices are not drawn either.
    expect(find.byKey(const ValueKey('pickStrategy')), findsNothing);
    expect(find.byType(RadioGroup<PickStrategy>), findsNothing);

    // What the rule gives for this fixture. The strategy is not observable here,
    // because both answers are the same for one set, so what the test can observe
    // is that the run ran with the values the popup opened at.
    final result = PhotosetPicker.pick([
      ScannedSet(
        entry: SourceEntry(
          name: 'source',
          isDirectory: true,
          readPath: 'source',
        ),
        photos: [
          // The rule reads counts, not sizes, so the fixture gives none.
          for (var index = 0; index < 10; index++)
            ScannedPhoto(
              name: '${index.toString().padLeft(3, '0')}.png',
              size: 0,
            ),
        ],
      ),
    ], defaultOptions(10));

    await confirmPick(
      tester,
      lineFor('source', result.picks.single.photos.length, 10),
    );
  });

  // The strategy the popup answers with is what the rule runs with, so the
  // whole-pack choice reaches the files: the test asks the rule for the picks its
  // own fixture would give under that strategy, as the tests do, and compares the
  // names the run wrote against them.
  testWidgets('the strategy the popup answers with is what the run copies', (
    tester,
  ) async {
    for (var set = 0; set < 2; set++) {
      for (var index = 0; index < 10; index++) {
        writePhotoAt(
          'source/set0${set + 1}',
          '${index.toString().padLeft(3, '0')}.png',
        );
      }
    }

    final release = testRelease(p.join(directory.path, 'source'));
    final state = testState(release);

    await openPhotosets(tester, state, showGallery: true);

    // The rule is asked after the run, and Pick cannot run before the scan has,
    // so the wait is for the end of the run.
    await scanAndWait(tester);

    await clickAndWait(
      tester,
      find.byKey(const ValueKey('photosetPickButton')),
      find.byKey(const ValueKey('pickOptionsDialog')),
    );

    await tester.tap(find.byKey(const ValueKey('pickStrategy-wholePack')));
    await tester.pumpAndSettle();

    // What the rule gives for this fixture under the strategy the popup was
    // answered with: the interval centres of the whole 20, read back per set.
    // The test asks the rule rather than assuming, so the names it compares are
    // the ones the run wrote.
    final result = PhotosetPicker.pick(
      [
        for (final set in ['set01', 'set02'])
          ScannedSet(
            entry: SourceEntry(name: set, isDirectory: true, readPath: set),
            photos: [
              // The rule reads counts, not sizes, so the fixture gives none.
              for (var index = 0; index < 10; index++)
                ScannedPhoto(
                  name: '${index.toString().padLeft(3, '0')}.png',
                  size: 0,
                ),
            ],
          ),
      ],
      PickOptions(
        count: PhotosetPicker.initialCount(20),
        strategy: PickStrategy.wholePack,
        includeExtremes: false,
      ),
    );

    final picked = [
      for (final pick in result.picks)
        for (final photo in pick.photos) (pick.set.path, photo.name),
    ];

    final last = result.picks.where((pick) => pick.photos.isNotEmpty).last;

    await confirmPick(
      tester,
      lineFor(last.set.path, last.photos.length, last.set.photoCount),
    );

    // The gallery is another widget, so the test builds it again the way the
    // editor does, as the other pack tests do.
    await openPhotosets(tester, state, showGallery: true);

    for (final photo in picked) {
      expect(
        find.byKey(
          ValueKey(('photoTile', p.join(directory.path, photo.$1, photo.$2))),
        ),
        findsOneWidget,
      );
    }
  });

  // A single photoset is one set, so its photos are placed by the same grid: a
  // landscape spans the number of columns the two widths give, and the tiles
  // cannot share one shape (`ai/single_photoset.md` §6, `ai/picking.md` §7).
  // Its block names the one set above the photos, so a tile there keeps its
  // file name only.
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

      // Pick cannot run before the scan has, so the wait is for the end of the
      // run; the block title naming the folder the user picked is what the block
      // draws at its end too.
      await scanAndWait(tester);

      // The block draws these itself, so it is the widget a run rebuilds. A
      // pack of one is picked in full: the count the popup opened at is the
      // minimum, and the run takes what exists (`ai/picking.md` §1).
      await clickAndWait(
        tester,
        find.text('Pick'),
        find.byKey(const ValueKey('pickOptionsDialog')),
      );

      // The last photo the run writes is the last thing it changes, so waiting on
      // that tile means the run is over before the boxes are read; waiting on the
      // first tile to appear would read the drawing while the run is going.
      await confirmPick(
        tester,
        find.byKey(
          ValueKey(('photoTile', p.join(directory.path, 'source', 'c.png'))),
        ),
      );

      final boxes = tester
          .widgetList<Positioned>(find.byType(Positioned))
          .toList();

      // The order is the order the source gives, so the second box is the
      // landscape: as many columns wide as the two widths the feature gives
      // derive, while the other two take one.
      expect(boxes.length, 3);

      final columnWidth = boxes[0].width!;
      final span = photoSpanCount(
        portraitWidth: photosetColumnWidth,
        landscapeWidth: photosetLandscapeWidth,
      );

      expect(span, 2);
      expect(boxes[1].width, span * columnWidth);
      expect(boxes[2].width, columnWidth);

      // Each box is the shape the photo is. The name line and the gap are the
      // constants the feature lays tiles out with, so the image is the rest of
      // the box. One set, so one line (`ai/picking.md` §7).
      final labelAndGap = photosetLabelHeight + photosetTileGap;

      expect(
        boxes[0].height! - labelAndGap,
        closeTo(columnWidth / (100 / 300), 0.01),
      );
      expect(
        boxes[1].height! - labelAndGap,
        closeTo(span * columnWidth / (300 / 100), 0.01),
      );
      expect(boxes[2].height! - labelAndGap, closeTo(columnWidth, 0.01));

      // A tile here does not name its set, because there is one set and the
      // block names it above the photos.
      for (final name in ['a.png', 'b.png', 'c.png']) {
        final tile = find.byKey(
          ValueKey(('photoTile', p.join(directory.path, 'source', name))),
        );

        expect(
          find.descendant(of: tile, matching: find.text('source')),
          findsNothing,
        );
      }
    },
  );

  // The pack's grid is the same drawing at the same two widths, and a tile
  // there does name its set, because the grid mixes sets. The drawing uses the
  // same heights the assignment works with, so the test works the placement out
  // with the rule, including the split by kind, and compares the boxes against
  // it (`ai/picking.md` §7).
  testWidgets('the pack draws the photos in the columns the assignment gives', (
    tester,
  ) async {
    // A space that can hold a column of both kinds: one for a portrait and one
    // for a landscape is the least the two zones can be given, and below that
    // the grid is not split at all (`ai/picking.md` §7).
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;

    // Three sets of two, one landscape, one portrait, one read as a square, so
    // both kinds are present and the placement is not the same for every tile.
    // The dimensions are the ratios themselves, so the test compares with the
    // same numbers the reader reads from the fixtures.
    const sets = ['set01', 'set02', 'set03'];
    const sizes = [
      [300, 100],
      [100, 300],
      [100, 100],
    ];

    for (var set = 0; set < sets.length; set++) {
      for (var index = 0; index < 2; index++) {
        writePhotoAt(
          'source/${sets[set]}',
          'p$index.png',
          sizes[set][0],
          sizes[set][1],
        );
      }
    }

    final release = testRelease(p.join(directory.path, 'source'));
    final state = testState(release);

    // What the rule picks for this fixture, in the order the source gives the
    // sets and, within a set, the order it gives the photos: the test asks the
    // rule rather than assuming, so the names it compares are the ones the pick
    // writes, and the order the assignment works with is the order the drawing
    // uses.
    final scanned = [
      for (final set in sets)
        ScannedSet(
          entry: SourceEntry(name: set, isDirectory: true, readPath: set),
          photos: [
            // The rule reads counts, not sizes, so the fixture gives none.
            for (var index = 0; index < 2; index++)
              ScannedPhoto(name: 'p$index.png', size: 0),
          ],
        ),
    ];
    final result = PhotosetPicker.pick(scanned, defaultOptions(6));

    final picked = [
      for (final pick in result.picks)
        for (final photo in pick.photos) (pick.set.path, photo.name),
    ];

    await openPhotosets(tester, state, showGallery: true);

    // Pick cannot run before the scan has, so the wait is for the end of the run.
    await scanAndWait(tester);

    // The pick runs in the block, which is the widget that ran it; the gallery
    // is another widget, so a run reaches it only when the page builds again —
    // here the test builds it again the way the editor does. The wait is on the
    // block's line, because that is where the picked number changes, and on the
    // last set the rule gives photos to, so the run is over when it is satisfied.
    await clickAndWait(
      tester,
      find.text('Pick'),
      find.byKey(const ValueKey('pickOptionsDialog')),
    );

    final last = result.picks.where((pick) => pick.photos.isNotEmpty).last;

    await confirmPick(
      tester,
      lineFor(last.set.path, last.photos.length, last.set.photoCount),
    );

    await openPhotosets(tester, state, showGallery: true);

    // More than one photo and more than one set, which is what the drawing
    // needs: a grid that mixes sets names the set on each tile.
    expect(picked.length, greaterThan(1));
    expect(picked.map((photo) => photo.$1).toSet().length, greaterThan(1));

    final gallery = tester.getRect(
      find.byKey(const ValueKey('photosetGallery')),
    );

    // The test cannot know what a widget is given by its parent, so it reads
    // the drawing for the space, and from that the rule gives the columns and
    // the width each is drawn at. The drawing is then compared against both, so
    // the test follows whatever the two constants are changed to.
    final span = photoSpanCount(
      portraitWidth: photosetColumnWidth,
      landscapeWidth: photosetLandscapeWidth,
    );
    final fit = photoColumnCount(
      width: gallery.width,
      min: photosetColumnWidth,
    );

    final ratiosBySet = {
      for (var set = 0; set < sets.length; set++)
        sets[set]: sizes[set][0] / sizes[set][1],
    };

    // The two zones, in the order the drawing places them: portraits first,
    // then landscapes. Within a zone the order is the order the source gives,
    // which is the order the picked list is in, so the test keeps it as it is.
    final portraits = [
      for (final photo in picked)
        if (!isLandscape(ratiosBySet[photo.$1])) photo,
    ];
    final landscapes = [
      for (final photo in picked)
        if (isLandscape(ratiosBySet[photo.$1])) photo,
    ];
    final zones = photoZoneColumnCounts(
      portraitPhotos: portraits.length,
      landscapePhotos: landscapes.length,
      columnCount: fit,
      landscapeSpan: span,
    );

    // What makes this fixture worth drawing as two zones: both kinds have
    // photos, the space can hold a column of each, and neither zone is the
    // single column a kind is given when it has nothing else to fill it with.
    expect(fit, greaterThanOrEqualTo(1 + span));
    expect(zones, isNotNull);
    expect(portraits.length, greaterThan(1));
    expect(landscapes.length, greaterThan(1));
    expect(zones!.portraitColumns, greaterThan(1));
    expect(zones.landscapeColumns, greaterThan(span));

    final columnWidth = photoColumnWidth(
      width: gallery.width,
      columnCount: zones.portraitColumns + zones.landscapeColumns,
      maxWidth: photosetColumnMaxWidth,
    );

    final labelHeight = photosetLabelHeight + photosetSetLineHeight;

    // The gallery's title row is above the grid, and its height comes from
    // measuring text, which the test cannot compute from the constants. So the
    // origin is read from the drawing: the first photo of the first zone is
    // placed at the top of its first column, so its box is where the grid
    // starts.
    final origin = tester.getRect(
      find.byKey(
        ValueKey((
          'photoTile',
          p.join(directory.path, portraits.first.$1, portraits.first.$2),
        )),
      ),
    );

    var start = 0;

    for (final zone in [
      (photos: portraits, columns: zones.portraitColumns),
      (photos: landscapes, columns: zones.landscapeColumns),
    ]) {
      final tiles = masonryPositions(
        ratios: [for (final photo in zone.photos) ratiosBySet[photo.$1]!],
        columnCount: zone.columns,
        columnWidth: columnWidth,
        labelHeight: labelHeight,
        gap: photosetTileGap,
        maxSpan: span,
      );

      // A photo is placed in the columns of its own kind, so a tile is never
      // drawn in the other zone, and the second zone starts at the column the
      // first ends at and at the same top, which is what the expectation is.
      for (final tile in tiles) {
        final photo = zone.photos[tile.index];
        final finder = find.byKey(
          ValueKey(('photoTile', p.join(directory.path, photo.$1, photo.$2))),
        );
        final rect = tester.getRect(finder);

        expect(
          rect.left,
          closeTo(origin.left + (start + tile.column) * columnWidth, 0.5),
        );
        expect(rect.top, closeTo(origin.top + tile.top, 0.5));
        expect(rect.width, closeTo(tile.span * columnWidth, 0.5));
        expect(
          rect.height,
          closeTo(tile.height + labelHeight + photosetTileGap, 0.5),
        );

        // A tile in a grid that mixes sets names the set its photo is from,
        // because there is no group to say it, and its file name under that.
        expect(
          find.descendant(of: finder, matching: find.text(photo.$1)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: finder, matching: find.text(photo.$2)),
          findsOneWidget,
        );
      }

      start += zone.columns;
    }

    // The block lists each set once, in the order the source gives them, and
    // says nothing about which column a photo is drawn in — that is what the
    // assignment above works out (`ai/picking.md` §7).
    for (final set in sets) {
      expect(find.byKey(ValueKey(('groupHeader', set))), findsOneWidget);
    }
  });

  // A set with no picked photos is only in the block's list: with no grouping
  // there is no column for it to take, so nothing is drawn for it in the grid
  // (`ai/photoset_pack.md` §6).
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

    await openPhotosets(tester, state, showGallery: true);

    // Pick cannot run before the scan has, so the wait is for the end of the run;
    // the lines for both sets are drawn as the scan reads them, so they are all
    // there at its end.
    await scanAndWait(tester);

    // Each set is named in the block, and only there.
    for (final set in ['set01', 'set02']) {
      expect(find.byKey(ValueKey(('groupHeader', set))), findsOneWidget);
    }

    // A set this small is picked in full, so the pair is the whole count twice;
    // the set with no photos is picked as nothing, so its pair says 0. The wait
    // is on the line of the one set with photos, which is the last thing the run
    // can change.
    await clickAndWait(
      tester,
      find.text('Pick'),
      find.byKey(const ValueKey('pickOptionsDialog')),
    );

    await confirmPick(tester, lineFor('set01', 3, 3));

    // The gallery shows what the pick wrote only when the page builds again, so the
    // test builds it again the way the editor does.
    await openPhotosets(tester, state, showGallery: true);

    for (var index = 0; index < 3; index++) {
      expect(
        find.byKey(
          ValueKey((
            'photoTile',
            p.join(directory.path, 'set01', 'p$index.png'),
          )),
        ),
        findsOneWidget,
      );
    }

    // Three tiles and nothing else: the set with no photos has no tile, and its
    // line is not drawn again above a column.
    expect(find.byType(Positioned), findsNWidgets(3));
  });
}

/// What the block hands to the editor's write path is the values the scan counted.
/// A test that does not check them takes a function that takes nothing, because the
/// helper's default has to be one value rather than a function written at each call.
void discardValues(Map<String, String> values) {}

/// The same for the two progress callbacks: a test that is not about what a run
/// reports while it works takes a function that does nothing with the report, so
/// the tests that are about it are the ones that read it.
void discardScanProgress(ScanProgress progress) {}

void discardCopyProgress(CopyProgress progress) {}

/// A reader that reads one set and then waits, so a test can look at what a
/// widget shows between two reports (`ai/photoset_pack.md` §4). A reader is called
/// on another isolate, so it holds nothing an isolate cannot take: the name it was
/// given and the files it lists.
class _SlowReader implements PhotosetReader {
  _SlowReader({required this.slow});

  /// How long this reader waits on the name it is given. The window between two
  /// reports has to be wide enough that the test sees the state between them
  /// rather than racing it, and it stays inside the bound the test's wait uses.
  static const delay = Duration(seconds: 5);

  /// The set this reader waits on, named as the scan names an entry. The scan
  /// reads the items in order, so the sets before it are read first and reported
  /// first.
  final String slow;

  @override
  bool canRead(SourceEntry entry) => entry.isDirectory;

  @override
  Future<List<ScannedPhoto>> read(String path) async {
    if (p.basename(path) == slow) {
      await Future.delayed(delay);
    }

    final entries = await Directory(path).list().toList();

    final names = [for (final entry in entries) p.basename(entry.path)];

    return [
      for (final name in names)
        ScannedPhoto(name: name, size: await File(p.join(path, name)).length()),
    ];
  }

  @override
  Future<List<int>> photoBytes(String path, String name) async {
    try {
      return await File(p.join(path, name)).readAsBytes();
    } catch (_) {
      return const [];
    }
  }
}

/// A reader for an archive, so two items can share a display name without
/// writing a real ZIP.
class _FakeArchiveReader implements PhotosetReader {
  @override
  bool canRead(SourceEntry entry) => entry.name.endsWith('.zip');

  @override
  Future<List<ScannedPhoto>> read(String path) async => [
    const ScannedPhoto(name: 'a.png', size: 0),
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
