import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:release_prepper/feature/image_folder/image_folder_controller.dart';
import 'package:release_prepper/feature/image_folder/image_folder_section.dart';
import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/release/release_store.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/tracker.dart';
import 'package:release_prepper/feature/screenshots/images.dart';
import 'package:release_prepper/feature/screenshots/images_store.dart';
import 'package:release_prepper/feature/section_title.dart';
import 'package:release_prepper/feature/tab/tab_manager.dart';
import 'package:release_prepper/l10n/app_localizations.dart';
import 'package:release_prepper/service/photosets/directory_reader.dart';
import 'package:release_prepper/service/photosets/photoset_scanner.dart';

void main() {
  // The release folder and the picked folder are two places, because that is
  // what the app is being exercised against: the images are copied from the
  // picked folder into the release.
  late Directory releaseDir;
  late Directory pickedDir;

  setUp(() {
    releaseDir = Directory.systemTemp.createTempSync('release_prepper_test');
    pickedDir = Directory.systemTemp.createTempSync('release_prepper_picked');
  });

  tearDown(() {
    releaseDir.deleteSync(recursive: true);
    pickedDir.deleteSync(recursive: true);
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

  void writePhoto(String name, [int width = 100, int height = 100]) {
    File(p.join(pickedDir.path, name))
        .writeAsBytesSync(pngPhoto(width, height));
  }

  Release testRelease(String source) => Release(
    name: 'x',
    directoryPath: releaseDir.path,
    tracker: Tracker.pornolab,
    releaseType: ReleaseType.imageFolderUpload,
    source: source,
    fields: FieldValues(),
    items: [],
  );

  ImageFolderController testController(
    Release release,
    ImagesStore store,
    TabManager tabManager,
    String tabId,
  ) => ImageFolderController(
    release: release,
    scanner: PhotosetScanner(readers: [const DirectoryPhotosetReader()]),
    store: store,
    releaseStore: ReleaseStore(),
    tabManager: tabManager,
    tabId: tabId,
  );

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

  Future<void> openSection(
    WidgetTester tester,
    Release release,
    List<Map<String, String>> applied,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PhotosetScanner>(
            create: (_) =>
                PhotosetScanner(readers: [const DirectoryPhotosetReader()]),
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
              child: ImageFolderSection(
                release: release,
                tabId: 'tab-1',
                onApplyValues: (values) => applied.add(values),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The scan records the one item the picked folder is, copies every image into
  // the release in filename order, and returns the values for the editor's
  // single write path (`ai/image_folder_upload.md` §2, §3).
  test(
    'the scan records the folder, copies the images and returns the values',
    () async {
      // Written out of order, so the order the records come back in is the
      // filename order and not the order the files were created.
      writePhoto('b.png', 400, 150);
      writePhoto('a.png', 100, 100);

      final tabManager = TabManager();
      final release = testRelease(pickedDir.path);
      final tabId = tabManager.addReleaseEditor(release);

      final store = ImagesStore();
      final controller = testController(release, store, tabManager, tabId);

      final result = await controller.scan() as ImageFolderSuccess;

      // The folder is the item, so it is named by the folder, as a single
      // photoset names its item. The name is a basename, so it is read with the
      // platform's separator, not by splitting on `/`: on Windows the temp path
      // the test made has `\` separators.
      expect(release.items.single.path, p.basename(pickedDir.path));
      expect(release.items.single.type, 'imageFolder');

      // The record path is relative to the release directory with `/`
      // separators, because that path is the record ID, and the release folder
      // mirrors the structure the user picked.
      expect(result.written.map((record) => record.file), [
        '${p.basename(pickedDir.path)}/a.png',
        '${p.basename(pickedDir.path)}/b.png',
      ]);
      expect(
        result.written.every((record) => record.kind == ImageKind.photo),
        isTrue,
      );

      expect(
        File(p.join(releaseDir.path, p.basename(pickedDir.path), 'a.png'))
            .existsSync(),
        isTrue,
      );

      expect(result.values, {
        'totalPhotoCount': '2',
        'minResolution': '100x100',
        'maxResolution': '400x150',
        'imageFormats': 'png',
      });

      expect(store.loadSync(releaseDir.path).of(ImageKind.photo), hasLength(2));
      expect(tabManager.tabs.single.hasUnsavedChanges, isTrue);
    },
  );

  // The images are copied rather than uploaded from where they were picked,
  // because the Upload section resolves a record path against the release
  // directory (`ai/image_folder_upload.md` §2). The picked folder is left as it
  // is.
  test('the images are copied into the release and the picked folder is left alone', () async {
    writePhoto('a.png');

    final controller = testController(
      testRelease(pickedDir.path),
      ImagesStore(),
      TabManager(),
      'tab-1',
    );

    final result = await controller.scan() as ImageFolderSuccess;

    expect(result.written.single.file, '${p.basename(pickedDir.path)}/a.png');
    expect(
      File(p.join(releaseDir.path, p.basename(pickedDir.path), 'a.png'))
          .existsSync(),
      isTrue,
    );
    expect(File(p.join(pickedDir.path, 'a.png')).existsSync(), isTrue);
  });

  // A file that is not an image is not counted, and it is reported rather than
  // guessed at (`ai/image_folder_upload.md` §3).
  test('files that are not images are reported and not counted', () async {
    writePhoto('a.png');
    File(p.join(pickedDir.path, 'notes.txt')).writeAsBytesSync([0x68, 0x69]);

    final controller = testController(
      testRelease(pickedDir.path),
      ImagesStore(),
      TabManager(),
      'tab-1',
    );

    final result = await controller.scan() as ImageFolderSuccess;

    expect(result.values['totalPhotoCount'], '1');
    expect(result.notImages, ['notes.txt']);
    expect(result.written.map((record) => record.file), [
      '${p.basename(pickedDir.path)}/a.png',
    ]);
  });

  // A re-scan replaces the item and the photo records this run writes; the
  // poster is not this run's to replace (`ai/release_structure.md` §4).
  test(
    'a re-scan replaces the photos it writes and keeps the poster',
    () async {
      writePhoto('a.png');

      final store = ImagesStore();
      await store.save(
        releaseDir.path,
        ImagesManifest(
          images: [
            const ImageRecord(
              item: null,
              kind: ImageKind.poster,
              file: '_rp_poster.jpg',
              urls: {},
            ),
          ],
        ),
      );

      final controller = testController(
        testRelease(pickedDir.path),
        store,
        TabManager(),
        'tab-1',
      );

      await controller.scan();

      File(p.join(pickedDir.path, 'b.png'))
          .writeAsBytesSync(pngPhoto(100, 100));
      File(p.join(pickedDir.path, 'a.png')).deleteSync();

      final result = await controller.scan() as ImageFolderSuccess;

      expect(result.written.map((record) => record.file), [
        '${p.basename(pickedDir.path)}/b.png',
      ]);
      expect(
        store.loadSync(releaseDir.path).images.map((record) => record.kind),
        [ImageKind.poster, ImageKind.photo],
      );
    },
  );

  testWidgets(
    'the section shows the images it copied and what it could not take',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      writePhoto('a.png');
      File(p.join(pickedDir.path, 'notes.txt')).writeAsBytesSync([0x68, 0x69]);

      final release = testRelease(pickedDir.path);
      final applied = <Map<String, String>>[];

      await openSection(tester, release, applied);

      // Nothing is shown before the scan: opening a release is a read and
      // changes nothing.
      expect(
        find.text('There are no images. Pick the folder and scan it.'),
        findsOneWidget,
      );

      await clickAndWait(tester, find.text('Scan'), find.text('1 images'));

      expect(find.text(p.basename(pickedDir.path)), findsOneWidget);
      expect(find.text('a.png'), findsOneWidget);

      // The values go through the editor's write path, not the section's.
      expect(applied.single['totalPhotoCount'], '1');

      // What the run could not take is reported rather than guessed at.
      expect(find.text('Not images: notes.txt'), findsOneWidget);
    },
  );

  testWidgets('the section says which folder it needs when none is picked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final applied = <Map<String, String>>[];

    await openSection(tester, testRelease(''), applied);

    await clickAndWait(
      tester,
      find.text('Scan'),
      find.text('Pick the folder with the images first.'),
    );

    expect(applied, isEmpty);
  });

  // The button is in the title row, at the right of the section's title,
  // because it is the action of the whole section rather than a row inside it.
  testWidgets('the Scan button is in the title row', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final applied = <Map<String, String>>[];

    await openSection(tester, testRelease(''), applied);

    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('imageFolderScanButton')),
        matching: find.byType(SectionTitle),
      ),
      findsOneWidget,
    );
  });
}
