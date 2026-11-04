import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/release/release_store.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/tracker.dart';
import 'package:release_prepper/feature/image_tile.dart';
import 'package:release_prepper/feature/screenshots/images.dart';
import 'package:release_prepper/feature/screenshots/images_store.dart';
import 'package:release_prepper/feature/screenshots/screenshots_controller.dart';
import 'package:release_prepper/feature/screenshots/screenshots_section.dart';
import 'package:release_prepper/feature/section_title.dart';
import 'package:release_prepper/l10n/app_localizations.dart';
import 'package:release_prepper/service/native_tools/ffmpeg.dart';
import 'package:release_prepper/service/native_tools/ffprobe.dart';
import 'package:release_prepper/service/native_tools/media_info.dart';
import 'package:release_prepper/service/native_tools/mtn.dart';
import 'package:release_prepper/service/native_tools/tool_runner.dart';
import 'package:release_prepper/service/videos/image_generator.dart';

import 'test_font_store.dart';
import 'test_runner.dart';

// The callbacks the sections pass. A test that does not display a run does not
// need the records, and a test that does not look at the upload counters does
// not need the notification, so they ignore them.
void ignoreRecord(ImageRecord record) {}

void ignoreImagesChanged() {}

const _probeInfo = MediaInfo(
  fileSize: '',
  duration: '',
  durationSeconds: 100,
  videoType: '',
  videoFormat: '',
  videoStream: '',
  audioStream: '',
);

void main() {
  // A release as the app builds it: the item is the file the user picked, so
  // its path is the filename (`ai/release_structure.md` §2). No source means no
  // item.
  Release testRelease(String directoryPath, {String source = ''}) => Release(
    name: 'x',
    directoryPath: directoryPath,
    tracker: Tracker.pornolab,
    releaseType: ReleaseType.singleVideo,
    source: source,
    fields: FieldValues(),
    items: source.isEmpty
        ? []
        : [
            ReleaseItem(
              path: p.basename(source),
              type: itemTypeVideo,
              fields: FieldValues(),
            ),
          ],
  );

  ImageGenerator testGenerator({
    required Ffmpeg ffmpeg,
    required Ffprobe ffprobe,
    required Mtn mtn,
  }) => ImageGenerator(
    ffmpeg: ffmpeg,
    ffprobe: ffprobe,
    mtn: mtn,
    fonts: testFontStore(),
  );

  // The controller writes the files and the manifest, so the whole flow runs in
  // runAsync: the test body is in a fake-async zone and real IO never completes
  // there.
  test('screenshots are named, spread evenly, and recorded in images.json', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final video = File('${directory.path}/movie.mp4');

    final release = testRelease(directory.path, source: video.path);
    final item = release.items.first;

    final ffmpeg = _FakeFfmpeg();
    final mtn = _FakeMtn();
    final controller = ScreenshotsController(
      release: release,
      generator: testGenerator(
        ffmpeg: ffmpeg,
        ffprobe: _FakeProbe(_probeInfo),
        mtn: mtn,
      ),
      store: ImagesStore(),
      releaseStore: ReleaseStore(),
    );

    expect(
      (await controller.generate(item, 3, ignoreRecord)).failure,
      ImageGenerationFailureKind.fileNotFound,
      reason: 'the item is there, but the file it names is not',
    );

    video.writeAsStringSync('not a real video file');

    final result = await controller.generate(item, 3, ignoreRecord);

    expect(result.failure, isNull);

    // The centre of each of three equal segments of a 100 s video.
    expect(ffmpeg.screenshotCalls.map((call) => call.seekSeconds), [
      closeTo(100 * 0.5 / 3, 0.001),
      closeTo(50, 0.001),
      closeTo(100 * 2.5 / 3, 0.001),
    ]);

    expect(ffmpeg.screenshotCalls.map((call) => call.outputPath), [
      '${directory.path}/images/movie.mp4/_rp_screenshot01.jpg',
      '${directory.path}/images/movie.mp4/_rp_screenshot02.jpg',
      '${directory.path}/images/movie.mp4/_rp_screenshot03.jpg',
    ]);

    // The screenlist is one call, in the same folder, with the rows the
    // duration gives: a 100 s video is below the minimum, so 16 frames = 4
    // rows.
    expect(mtn.screenlistCalls.map((call) => call.outputDirectory), [
      '${directory.path}/images/movie.mp4',
    ]);

    expect(mtn.screenlistCalls.map((call) => call.rows), [4]);

    // The manifest records the files relative to the release directory, with an
    // empty URL map until they are uploaded, and the item each of them belongs
    // to.
    final manifest = jsonDecode(
      await File('${directory.path}/images.json').readAsString(),
    ) as Map<String, dynamic>;

    expect(manifest['schema'], schemaVersion);

    expect(manifest['images'], [
      for (var n = 1; n <= 3; n++)
        {
          'item': 'movie.mp4',
          'kind': 'screenshot',
          'file':
              'images/movie.mp4/_rp_screenshot${n.toString().padLeft(2, '0')}.jpg',
          'urls': {},
        },
      {
        'item': 'movie.mp4',
        'kind': 'screenlist',
        'file': 'images/movie.mp4/_rp_screenlist.jpg',
        'urls': {},
      },
    ]);

    expect(
      controller
          .imagesFor(item)
          .map((record) => controller.absolutePath(record)),
      [
        '${directory.path}/images/movie.mp4/_rp_screenshot01.jpg',
        '${directory.path}/images/movie.mp4/_rp_screenshot02.jpg',
        '${directory.path}/images/movie.mp4/_rp_screenshot03.jpg',
        '${directory.path}/images/movie.mp4/_rp_screenlist.jpg',
      ],
    );

    directory.deleteSync(recursive: true);
  });

  // Each record is reported when its file is written, not when the run ends, so
  // the section can show a frame as it appears. The records it reports are the
  // same ones the manifest holds at the end, in the same order, so the section
  // shows one set and not two.
  test('each record is reported when its file is written', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final video = File('${directory.path}/movie.mp4');
    video.writeAsStringSync('not a real video file');

    final release = testRelease(directory.path, source: video.path);
    final item = release.items.first;

    final controller = ScreenshotsController(
      release: release,
      generator: testGenerator(
        ffmpeg: _FakeFfmpeg(),
        ffprobe: _FakeProbe(_probeInfo),
        mtn: _FakeMtn(),
      ),
      store: ImagesStore(),
      releaseStore: ReleaseStore(),
    );

    final reported = <String>[];
    var runEnded = false;

    await controller.generate(item, 3, (record) {
      reported.add(p.basename(record.file));

      // The run is still going. A report at the end of it would see it
      // finished, so this is what says the report is per file.
      expect(
        runEnded,
        isFalse,
        reason: 'the record is reported while the run is still writing',
      );
    });

    runEnded = true;

    expect(reported, [
      '_rp_screenshot01.jpg',
      '_rp_screenshot02.jpg',
      '_rp_screenshot03.jpg',
      '_rp_screenlist.jpg',
    ]);

    // The same records the manifest holds, in the same order.
    expect(
      controller.imagesFor(item).map((record) => p.basename(record.file)),
      reported,
    );

    directory.deleteSync(recursive: true);
  });

  // A run with 0 screenshots writes only the screenlist, because mtn reads the
  // video itself. This is what the Video pack section allows and the Single
  // video section does not.
  test('a run with 0 screenshots writes only the screenlist', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final video = File('${directory.path}/movie.mp4');
    video.writeAsStringSync('not a real video file');

    final release = testRelease(directory.path, source: video.path);
    final item = release.items.first;

    final ffmpeg = _FakeFfmpeg();
    final mtn = _FakeMtn();

    final controller = ScreenshotsController(
      release: release,
      generator: testGenerator(
        ffmpeg: ffmpeg,
        ffprobe: _FakeProbe(_probeInfo),
        mtn: mtn,
      ),
      store: ImagesStore(),
      releaseStore: ReleaseStore(),
    );

    final result = await controller.generate(item, 0, ignoreRecord);

    expect(result.failure, isNull);
    expect(ffmpeg.screenshotCalls, isEmpty);

    expect(result.written.map((record) => record.file), [
      'images/movie.mp4/_rp_screenlist.jpg',
    ]);

    directory.deleteSync(recursive: true);
  });

  // mtn exits with a non-zero code when it prints a warning, even when it wrote
  // the file, so the file is what decides.
  test(
    'a screenlist that was written is a success whatever the exit code',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );
      final video = File('${directory.path}/movie.mp4');
      video.writeAsStringSync('not a real video file');

      final release = testRelease(directory.path, source: video.path);
      final item = release.items.first;

      final controller = ScreenshotsController(
        release: release,
        generator: testGenerator(
          ffmpeg: _FakeFfmpeg(),
          ffprobe: _FakeProbe(_probeInfo),
          mtn: _FakeMtn(
            result: const ToolRunFailure(
              exitCode: 1,
              stdout: '',
              stderr: 'previous seek overshot target',
            ),
          ),
        ),
        store: ImagesStore(),
        releaseStore: ReleaseStore(),
      );

      final result = await controller.generate(item, 3, ignoreRecord);

      expect(result.failure, isNull);
      expect(result.written.length, 4);

      directory.deleteSync(recursive: true);
    },
  );

  // A run that does not finish still records what it wrote, so the section
  // shows the screenshots a failed screenlist follows.
  test('a screenlist that was not written is a failure, and the screenshots are still recorded', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final video = File('${directory.path}/movie.mp4');
    video.writeAsStringSync('not a real video file');

    final release = testRelease(directory.path, source: video.path);
    final item = release.items.first;

    final controller = ScreenshotsController(
      release: release,
      generator: testGenerator(
        ffmpeg: _FakeFfmpeg(),
        ffprobe: _FakeProbe(_probeInfo),
        mtn: _FakeMtn(
          result: const ToolRunFailure(exitCode: 1, stdout: '', stderr: ''),
          writesFile: false,
        ),
      ),
      store: ImagesStore(),
      releaseStore: ReleaseStore(),
    );

    final result = await controller.generate(item, 3, ignoreRecord);

    expect(result.failure, ImageGenerationFailureKind.screenlistFailed);

    expect(result.written.map((record) => record.file), [
      for (var n = 1; n <= 3; n++)
        'images/movie.mp4/_rp_screenshot${n.toString().padLeft(2, '0')}.jpg',
    ]);

    final manifest = jsonDecode(
      await File('${directory.path}/images.json').readAsString(),
    ) as Map<String, dynamic>;

    expect(manifest['images'], hasLength(3));

    expect(controller.imagesFor(item), hasLength(3));

    directory.deleteSync(recursive: true);
  });

  // A record whose file is not on disk is not shown, so deleting what the run
  // wrote takes the column back to empty.
  test('a record whose file was deleted is not tracked', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final video = File('${directory.path}/movie.mp4');
    video.writeAsStringSync('not a real video file');

    final release = testRelease(directory.path, source: video.path);
    final item = release.items.first;

    final controller = ScreenshotsController(
      release: release,
      generator: testGenerator(
        ffmpeg: _FakeFfmpeg(),
        ffprobe: _FakeProbe(_probeInfo),
        mtn: _FakeMtn(),
      ),
      store: ImagesStore(),
      releaseStore: ReleaseStore(),
    );

    final result = await controller.generate(item, 3, ignoreRecord);

    File(controller.absolutePath(result.written.first)).deleteSync();

    expect(controller.imagesFor(item), hasLength(3));

    directory.deleteSync(recursive: true);
  });

  // Regenerating replaces only what the run writes: a poster record and a
  // record of another item stay (`ai/video_pack.md` §5).
  test('regenerating keeps the records it did not write', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final video = File('${directory.path}/movie.mp4');
    video.writeAsStringSync('not a real video file');

    final release = testRelease(directory.path, source: video.path);
    final item = release.items.first;

    final store = ImagesStore();

    await store.save(
      directory.path,
      ImagesManifest(
        images: [
          ImageRecord(
            item: null,
            kind: ImageKind.poster,
            file: 'poster.jpg',
            urls: const {},
          ),
          ImageRecord(
            item: 'other.mp4',
            kind: ImageKind.screenshot,
            file: 'images/other.mp4/_rp_screenshot01.jpg',
            urls: const {},
          ),
        ],
      ),
    );

    final controller = ScreenshotsController(
      release: release,
      generator: testGenerator(
        ffmpeg: _FakeFfmpeg(),
        ffprobe: _FakeProbe(_probeInfo),
        mtn: _FakeMtn(),
      ),
      store: store,
      releaseStore: ReleaseStore(),
    );

    await controller.generate(item, 1, ignoreRecord);

    final manifest = jsonDecode(
      await File('${directory.path}/images.json').readAsString(),
    ) as Map<String, dynamic>;

    expect(
      (manifest['images'] as List).map((image) => (image as Map)['file']),
      [
        'poster.jpg',
        'images/other.mp4/_rp_screenshot01.jpg',
        'images/movie.mp4/_rp_screenshot01.jpg',
        'images/movie.mp4/_rp_screenlist.jpg',
      ],
    );

    directory.deleteSync(recursive: true);
  });

  test(
    'mtn not being installed is reported as the tool not being available',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );
      final video = File('${directory.path}/movie.mp4');
      video.writeAsStringSync('not a real video file');

      final release = testRelease(directory.path, source: video.path);
      final item = release.items.first;

      final controller = ScreenshotsController(
        release: release,
        generator: testGenerator(
          ffmpeg: _FakeFfmpeg(),
          ffprobe: _FakeProbe(_probeInfo),
          mtn: _FakeMtn(result: const ToolRunNotAvailable(), writesFile: false),
        ),
        store: ImagesStore(),
        releaseStore: ReleaseStore(),
      );

      expect(
        (await controller.generate(item, 3, ignoreRecord)).failure,
        ImageGenerationFailureKind.mtnNotAvailable,
      );

      directory.deleteSync(recursive: true);
    },
  );

  testWidgets(
    'the section shows the slider, the button, and the generated images',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      final directory = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );
      final video = File('${directory.path}/movie.mp4');
      video.writeAsStringSync('not a real video file');

      final release = testRelease(directory.path, source: video.path);

      final ffmpeg = _FakeFfmpeg();
      final mtn = _FakeMtn();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ImageGenerator>(
              create: (_) => testGenerator(
                ffmpeg: ffmpeg,
                ffprobe: _FakeProbe(_probeInfo),
                mtn: mtn,
              ),
            ),
            Provider<ImagesStore>(create: (_) => ImagesStore()),
            Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              // The section is a column that can be taller than the window, so
              // the editor puts it in a scroll view; the test does the same.
              body: SingleChildScrollView(
                child: ScreenshotsSection(
                  release: release,
                  onImagesChanged: ignoreImagesChanged,
                ),
              ),
            ),
          ),
        ),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 3);
      expect(slider.max, 20);

      expect(find.text('Generate'), findsOneWidget);

      // The button is in the title row, at the right of the section's title,
      // because it is the action of the whole section rather than one of the
      // controls that set what it does. The controls that remain are the label,
      // the slider and the count, on one row.
      expect(
        find.ancestor(
          of: find.text('Generate'),
          matching: find.byType(SectionTitle),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byType(Slider),
          matching: find.byType(SectionTitle),
        ),
        findsNothing,
      );

      // The label is on that same row, so the row is the label and the controls
      // it sets.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.byType(Slider),
            matching: find.byType(Row),
          ),
          matching: find.text('Number of screenshots'),
        ),
        findsOneWidget,
      );

      // Nothing is on disk yet, so the section shows no images.
      expect(find.byType(Image), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.text('Generate'));
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });

      // The screenshots the fake tool wrote, plus the screenlist.
      expect(find.byType(Image), findsNWidgets(6));

      // The tiles are placed by position, so the path in the image provider is
      // what identifies one. The key is the generation and the path, which is
      // what makes a rewritten file re-resolve.
      ValueKey<String> keyOf(String fileName) =>
          tester
                  .widgetList<Image>(find.byType(Image))
                  .firstWhere(
                    (image) =>
                        (image.image as FileImage).file.path.endsWith(fileName),
                  )
                  .key
              as ValueKey<String>;

      final screenlistKey = keyOf(ImageGenerator.screenlistFileName());

      // The grid is two equal columns with the gap between them, so a tile is
      // the width left after one gap is taken out of the section, and the
      // second column starts at the first plus the gap. Nothing spans: with
      // spans every frame would be as wide as the grid and the grid would be
      // one column. The screenlist is first in the order the section builds, so
      // it is the top of the left column, and the first frame goes to the right
      // one because the left is occupied.
      final placed = {
        for (final tile in tester.widgetList<Positioned>(
          find.byType(Positioned),
        ))
          p.basename((tile.child as ImageTile).path): tile,
      };

      final columnWidth = placed[ImageGenerator.screenlistFileName()]!.width!;

      expect(
        columnWidth,
        (tester
                    .getSize(find.byKey(const ValueKey('screenshotsSection')))
                    .width -
                12) /
            2,
      );

      expect(placed[ImageGenerator.screenlistFileName()]!.left, 0);
      expect(placed[ImageGenerator.screenlistFileName()]!.top, 0);
      expect(
        placed[ImageGenerator.screenshotFileName(1)]!.left,
        columnWidth + 12,
      );
      expect(placed[ImageGenerator.screenshotFileName(1)]!.top, 0);

      // The name under an image is centred, because the tile is the shared one
      // and the name is the label of a tile, not of a column.
      expect(
        tester
            .widget<Text>(find.text(ImageGenerator.screenshotFileName(1)))
            .textAlign,
        TextAlign.center,
      );

      // With images on disk the button offers to regenerate them.
      expect(find.text('Regenerate'), findsOneWidget);

      // Regenerating writes the same paths, so the only way the tiles show the
      // new files is that their keys change and the images re-resolve.
      final firstFrameKey = keyOf(ImageGenerator.screenshotFileName(1));

      await tester.runAsync(() async {
        await tester.tap(find.text('Regenerate'));
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });

      expect(
        keyOf(ImageGenerator.screenshotFileName(1)),
        isNot(firstFrameKey),
        reason: 'the tile must re-resolve the regenerated file',
      );

      expect(
        keyOf(ImageGenerator.screenlistFileName()),
        isNot(screenlistKey),
        reason: 'the screenlist is rewritten under the same name too',
      );

      directory.deleteSync(recursive: true);
    },
  );

  testWidgets(
    'the screenshots are still shown when the screenlist was not written',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      final directory = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );
      final video = File('${directory.path}/movie.mp4');
      video.writeAsStringSync('not a real video file');

      final release = testRelease(directory.path, source: video.path);

      final mtn = _FakeMtn(
        result: const ToolRunFailure(exitCode: 1, stdout: '', stderr: ''),
        writesFile: false,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ImageGenerator>(
              create: (_) => testGenerator(
                ffmpeg: _FakeFfmpeg(),
                ffprobe: _FakeProbe(_probeInfo),
                mtn: mtn,
              ),
            ),
            Provider<ImagesStore>(create: (_) => ImagesStore()),
            Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              // The section is a column that can be taller than the window, so
              // the editor puts it in a scroll view; the test does the same.
              body: SingleChildScrollView(
                child: ScreenshotsSection(
                  release: release,
                  onImagesChanged: ignoreImagesChanged,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await tester.tap(find.text('Generate'));
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });

      // The run failed, but the frames it wrote are recorded and shown, and the
      // failure is reported next to them.
      expect(find.byType(Image), findsNWidgets(5));
      expect(find.text('Could not create the screenlist.'), findsOneWidget);

      directory.deleteSync(recursive: true);
    },
  );

  // A frame is shown when it is written, not when the run ends. The fake writes
  // each frame and then waits for the test, so the test can look at the section
  // while the run is still going.
  testWidgets('the images appear as the run writes them', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final video = File('${directory.path}/movie.mp4');
    video.writeAsStringSync('not a real video file');

    final release = testRelease(directory.path, source: video.path);

    final ffmpeg = _SteppedFfmpeg();
    final changed = <String>[];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ImageGenerator>(
            create: (_) => testGenerator(
              ffmpeg: ffmpeg,
              ffprobe: _FakeProbe(_probeInfo),
              mtn: _FakeMtn(),
            ),
          ),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScreenshotsSection(
                release: release,
                onImagesChanged: () => changed.add('changed'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Generate'));

      // The run does real IO before it calls the tool, so the test waits for
      // the first frame to reach the fake. It is on disk, and the run is
      // waiting here for the test to let it continue.
      while (ffmpeg.steps.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      ffmpeg.steps.first.complete();
      await Future.delayed(const Duration(milliseconds: 10));
      await tester.pump();

      // The section shows the frame it has been told about, and nothing of the
      // rest of the run.
      expect(find.byType(Image), findsOneWidget);

      // The upload counters are not told while the run is going, because the
      // count reads records.
      expect(changed, isEmpty);

      // Let the rest of the run finish.
      ffmpeg.release = true;
      for (final step in ffmpeg.steps) {
        if (!step.isCompleted) step.complete();
      }

      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      // The five frames the fake writes, plus the screenlist.
      expect(find.byType(Image), findsNWidgets(6));
      expect(changed, ['changed']);
    });

    directory.deleteSync(recursive: true);
  });

  // With no video picked there is nothing this section can do, so it says what
  // has to happen first rather than showing controls that cannot run.
  testWidgets(
    'the section says to select a video first when there is no item',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      final directory = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ImageGenerator>(
              create: (_) => testGenerator(
                ffmpeg: _FakeFfmpeg(),
                ffprobe: _FakeProbe(_probeInfo),
                mtn: _FakeMtn(),
              ),
            ),
            Provider<ImagesStore>(create: (_) => ImagesStore()),
            Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ScreenshotsSection(
                  release: testRelease(directory.path),
                  onImagesChanged: ignoreImagesChanged,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Select a video first'), findsOneWidget);

      expect(find.byType(Slider), findsNothing);
      expect(find.byType(FilledButton), findsNothing);

      directory.deleteSync(recursive: true);
    },
  );
}

/// A fake that writes each frame and then waits for the test, so the test can
/// look at the section in the middle of a run. `release` is what lets the rest
/// of the run through.
class _SteppedFfmpeg implements Ffmpeg {
  final steps = <Completer<void>>[];

  bool release = false;

  @override
  ToolRunner get runner => testRunner();

  @override
  Future<ToolRunResult> version({required String releaseDirectory}) async =>
      const ToolRunSuccess(stdout: '', stderr: '');

  @override
  Future<ToolRunResult> resizeImage({
    required String releaseDirectory,
    required String inputPath,
    required String outputPath,
    required int maxSize,
  }) async => const ToolRunSuccess(stdout: '', stderr: '');

  @override
  Future<ToolRunResult> screenshot({
    required String releaseDirectory,
    required String inputPath,
    required String outputPath,
    required double seekSeconds,
  }) async {
    // A file the widget test can find; its contents are not a real image.
    File(outputPath).writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);

    if (!release) {
      final step = Completer<void>();
      steps.add(step);
      await step.future;
    }

    return const ToolRunSuccess(stdout: '', stderr: '');
  }
}

class _FakeProbe implements Ffprobe {
  _FakeProbe(this.info);

  final MediaInfo info;

  @override
  ToolRunner get runner => testRunner();

  @override
  Future<ToolRunResult> version({required String releaseDirectory}) async =>
      const ToolRunSuccess(stdout: '', stderr: '');

  @override
  Future<MediaProbeResult> probe({
    required String releaseDirectory,
    required String filePath,
  }) async => MediaProbeSuccess(info);
}

class _FakeFfmpeg implements Ffmpeg {
  final screenshotCalls =
      <({String inputPath, String outputPath, double seekSeconds})>[];

  @override
  ToolRunner get runner => testRunner();

  @override
  Future<ToolRunResult> version({required String releaseDirectory}) async =>
      const ToolRunSuccess(stdout: '', stderr: '');

  @override
  Future<ToolRunResult> resizeImage({
    required String releaseDirectory,
    required String inputPath,
    required String outputPath,
    required int maxSize,
  }) async => const ToolRunSuccess(stdout: '', stderr: '');

  @override
  Future<ToolRunResult> screenshot({
    required String releaseDirectory,
    required String inputPath,
    required String outputPath,
    required double seekSeconds,
  }) async {
    screenshotCalls.add((
      inputPath: inputPath,
      outputPath: outputPath,
      seekSeconds: seekSeconds,
    ));

    // A file the widget test can find; its contents are not a real image.
    File(outputPath).writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);

    return const ToolRunSuccess(stdout: '', stderr: '');
  }
}

class _FakeMtn implements Mtn {
  _FakeMtn({ToolRunResult? result, this.writesFile = true})
    : result = result ?? const ToolRunSuccess(stdout: '', stderr: '');

  /// What the call reports.
  final ToolRunResult result;

  /// Whether it leaves a file behind, which is what the app decides by: mtn can
  /// exit non-zero on a warning and still write the screenlist.
  final bool writesFile;

  final screenlistCalls =
      <({String inputPath, String outputDirectory, int rows})>[];

  @override
  ToolRunner get runner => testRunner();

  @override
  Future<ToolRunResult> version({required String releaseDirectory}) async =>
      result;

  @override
  Future<ToolRunResult> screenlist({
    required String releaseDirectory,
    required String inputPath,
    required String outputDirectory,
    required int rows,
    required String fontPath,
  }) async {
    screenlistCalls.add((
      inputPath: inputPath,
      outputDirectory: outputDirectory,
      rows: rows,
    ));

    if (writesFile) {
      File('$outputDirectory/${Mtn.screenlistName}.jpg')
          .writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
    }

    return result;
  }
}
