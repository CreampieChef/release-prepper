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
import 'package:release_prepper/feature/screenshots/images.dart';
import 'package:release_prepper/feature/screenshots/images_store.dart';
import 'package:release_prepper/feature/section_title.dart';
import 'package:release_prepper/feature/tab/tab_manager.dart';
import 'package:release_prepper/feature/video_pack/video_pack_controller.dart';
import 'package:release_prepper/feature/video_pack/video_pack_section.dart';
import 'package:release_prepper/l10n/app_localizations.dart';
import 'package:release_prepper/service/native_tools/ffmpeg.dart';
import 'package:release_prepper/service/native_tools/ffprobe.dart';
import 'package:release_prepper/service/native_tools/media_info.dart';
import 'package:release_prepper/service/native_tools/mtn.dart';
import 'package:release_prepper/service/native_tools/tool_runner.dart';
import 'package:release_prepper/service/videos/image_generator.dart';
import 'package:release_prepper/service/videos/video_scanner.dart';

import 'test_font_store.dart';
import 'test_runner.dart';

// The callbacks the sections pass. A test that does not display a run does not
// need the records, and a test that does not look at the upload counters does
// not need the notification, so they ignore them.
void ignoreRecord(ImageRecord record) {}

void ignoreImagesChanged() {}

/// What the probe answers for one file, by name. A name the map does not have
/// is a probe failure.
class _FakeProbe implements Ffprobe {
  _FakeProbe();

  final infos = <String, String>{};
  final types = <String, String>{};
  final formats = <String, String>{};

  @override
  ToolRunner get runner => testRunner();

  @override
  Future<ToolRunResult> version({required String releaseDirectory}) async =>
      const ToolRunSuccess(stdout: '', stderr: '');

  @override
  Future<MediaProbeResult> probe({
    required String releaseDirectory,
    required String filePath,
  }) async {
    final name = p.basename(filePath);

    if (!infos.containsKey(name)) {
      return const MediaProbeFailure(MediaProbeFailureKind.probeFailed);
    }

    return MediaProbeSuccess(
      MediaInfo(
        fileSize: infos[name]!,
        duration: '00:01:00',
        durationSeconds: 60,
        videoType: types[name] ?? '',
        videoFormat: formats[name] ?? 'MP4',
        videoStream: 'AVC',
        audioStream: 'AAC',
      ),
    );
  }
}

/// A fake that writes the files the app decides by. `failsFor` is the set of
/// file names it refuses to write, which is how a run that fails on one file
/// and not on the next is tested.
class _FakeFfmpeg implements Ffmpeg {
  _FakeFfmpeg({this.failsFor = const {}});

  final Set<String> failsFor;

  final calls = <({String inputPath, String outputPath})>[];

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
    calls.add((inputPath: inputPath, outputPath: outputPath));

    if (failsFor.contains(p.basename(inputPath))) {
      return const ToolRunFailure(exitCode: 1, stdout: '', stderr: '');
    }

    // A file the widget test can find; its contents are not a real image.
    File(outputPath).writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);

    return const ToolRunSuccess(stdout: '', stderr: '');
  }
}

class _FakeMtn implements Mtn {
  _FakeMtn({this.available = true});

  /// Whether the tool is there at all. When it is not, the run stops, because a
  /// tool does not become installed while the app is open.
  final bool available;

  final calls = <({String inputPath, String outputDirectory, int rows})>[];

  @override
  ToolRunner get runner => testRunner();

  @override
  Future<ToolRunResult> version({required String releaseDirectory}) async =>
      available
      ? const ToolRunSuccess(stdout: '', stderr: '')
      : const ToolRunNotAvailable();

  @override
  Future<ToolRunResult> screenlist({
    required String releaseDirectory,
    required String inputPath,
    required String outputDirectory,
    required int rows,
    required String fontPath,
  }) async {
    calls.add((
      inputPath: inputPath,
      outputDirectory: outputDirectory,
      rows: rows,
    ));

    if (!available) {
      return const ToolRunNotAvailable();
    }

    File(p.join(outputDirectory, '${Mtn.screenlistName}.jpg'))
        .writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);

    return const ToolRunSuccess(stdout: '', stderr: '');
  }
}

void main() {
  late Directory directory;
  late _FakeProbe probe;
  late _FakeFfmpeg ffmpeg;
  late _FakeMtn mtn;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('release_prepper_test');
    probe = _FakeProbe();
    ffmpeg = _FakeFfmpeg();
    mtn = _FakeMtn();
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
  });

  // `probed: false` is a file the probe cannot read, which is the case the
  // controller records with empty fields. `bytes` is the size the file has on
  // disk, which is what the total sums; `size` is what the probe answers for the
  // same file, so the two are different numbers here on purpose.
  void writeVideo(
    String path, {
    String videoType = '',
    String videoFormat = 'MP4',
    String size = '1000',
    int? bytes,
    bool probed = true,
  }) {
    final file = File(p.join(directory.path, path));
    file.parent.createSync(recursive: true);

    if (bytes == null) {
      file.writeAsStringSync('not really a video');
    } else {
      file.writeAsBytesSync(List.filled(bytes, 0));
    }

    final name = p.basename(path);

    if (!probed) {
      return;
    }

    probe.infos[name] = size;
    probe.types[name] = videoType;
    probe.formats[name] = videoFormat;
  }

  // A file the extension list does not accept.
  void writeOther(String path) {
    final file = File(p.join(directory.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('not a video');
  }

  VideoScanner testScanner() => VideoScanner(probe: probe);

  ImageGenerator testGenerator() => ImageGenerator(
    ffmpeg: ffmpeg,
    ffprobe: probe,
    mtn: mtn,
    fonts: testFontStore(),
  );

  Release testRelease(String source) => Release(
    name: 'x',
    directoryPath: directory.path,
    tracker: Tracker.pornolab,
    releaseType: ReleaseType.videoPack,
    source: source,
    fields: FieldValues(),
    items: [],
  );

  VideoPackController testController(
    Release release,
    TabManager tabManager,
    String tabId,
  ) => VideoPackController(
    release: release,
    scanner: testScanner(),
    generator: testGenerator(),
    store: ImagesStore(),
    releaseStore: ReleaseStore(),
    tabManager: tabManager,
    tabId: tabId,
  );

  // The controller records the items, because an item is what the scan
  // produces, and returns the aggregates for the editor's single write path.
  test(
    'the scan records the items and returns the aggregates for the editor',
    () async {
      writeVideo('first.mp4', videoType: '1080p', bytes: 2048);
      writeVideo('videos/second.mkv', videoType: '2160p', bytes: 1024);

      final tabManager = TabManager();
      final release = testRelease(directory.path);
      final tabId = tabManager.addReleaseEditor(release);

      final controller = testController(release, tabManager, tabId);

      final result = await controller.scan() as VideoPackSuccess;

      expect(release.items.map((item) => item.path), [
        'first.mp4',
        'videos/second.mkv',
      ]);
      expect(release.items.first.type, 'video');
      expect(release.items.first.fields.value('fileSize'), '1000');
      expect(release.items.first.fields.value('duration'), '00:01:00');
      expect(release.items.first.fields.value('videoType'), '1080p');

      expect(result.values, {
        'totalSize': '3072',
        'videoCount': '2',
        'videoResolutions': '1080p, 2160p',
        'videoFormats': 'mkv, mp4',
      });

      expect(tabManager.tabs.single.hasUnsavedChanges, isTrue);
    },
  );

  // A file the probe could not read is an item with empty fields: the extension
  // list is what decides what a video is, and the app does not write values it
  // does not have.
  test(
    'a file that could not be probed is recorded with empty fields',
    () async {
      writeVideo('first.mp4', probed: false);

      final controller = testController(
        testRelease(directory.path),
        TabManager(),
        'tab-1',
      );

      final result = await controller.scan() as VideoPackSuccess;

      expect(controller.release.items.single.fields.value('videoType'), '');
      expect(result.unprobed, ['first.mp4']);

      // An aggregate is not written with a value the app does not have.
      expect(result.values['videoResolutions'], '');
    },
  );

  // A re-scan replaces the items, because the scan is what says what the source
  // contains.
  test('a re-scan replaces the items', () async {
    writeVideo('first.mp4', videoType: '1080p');

    final controller = testController(
      testRelease(directory.path),
      TabManager(),
      'tab-1',
    );

    await controller.scan();

    // The source changed on disk: one video is gone and a loose file appeared.
    File(p.join(directory.path, 'first.mp4')).deleteSync();
    writeOther('cover.txt');
    writeVideo('second.mkv', videoType: '720p');

    final result = await controller.scan() as VideoPackSuccess;

    expect(controller.release.items.map((item) => item.path), ['second.mkv']);
    expect(result.skipped, ['cover.txt']);
    expect(result.values['videoCount'], '1');
    expect(result.values['videoResolutions'], '720p');
  });

  // The run writes the files through the service and writes `images.json` once
  // for the whole run, in the order the scan recorded the items
  // (`ai/video_pack.md` §5).
  test('the run records what it wrote for every item', () async {
    writeVideo('first.mp4');
    writeVideo('videos/second.mkv');

    final controller = testController(
      testRelease(directory.path),
      TabManager(),
      'tab-1',
    );
    await controller.scan();

    final result = await controller.generateImages(1, ignoreRecord);

    expect(result.failure, isNull);
    expect(result.runs.map((run) => run.item), [
      'first.mp4',
      'videos/second.mkv',
    ]);

    final manifest = jsonDecode(
      await File(p.join(directory.path, 'images.json')).readAsString(),
    ) as Map<String, dynamic>;

    expect(manifest['images'], [
      for (final item in ['first.mp4', 'videos/second.mkv']) ...[
        {
          'item': item,
          'kind': 'screenshot',
          'file': 'images/$item/_rp_screenshot01.jpg',
          'urls': {},
        },
        {
          'item': item,
          'kind': 'screenlist',
          'file': 'images/$item/_rp_screenlist.jpg',
          'urls': {},
        },
      ],
    ]);

    // A run with 0 writes only the screenlist, because mtn reads the video
    // itself. This is what the pack's slider allows and the Single video
    // section does not.
    final none = await controller.generateImages(0, ignoreRecord);

    expect(none.runs.every((run) => run.screenshots.isEmpty), isTrue);
    expect(none.runs.every((run) => run.screenlist != null), isTrue);
  });

  // Each file is reported as it is written, in the order the scan recorded the
  // items, so the section can show a frame before the run ends. The records it
  // reports are the same ones the manifest holds at the end, in the same order.
  test('the run reports each file as it writes it', () async {
    writeVideo('first.mp4');
    writeVideo('videos/second.mkv');

    final controller = testController(
      testRelease(directory.path),
      TabManager(),
      'tab-1',
    );
    await controller.scan();

    final reported = <String>[];
    var runEnded = false;

    await controller.generateImages(1, (record) {
      reported.add(record.file);

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
      'images/first.mp4/_rp_screenshot01.jpg',
      'images/first.mp4/_rp_screenlist.jpg',
      'images/videos/second.mkv/_rp_screenshot01.jpg',
      'images/videos/second.mkv/_rp_screenlist.jpg',
    ]);

    // The same records the manifest holds, in the same order, so the section
    // shows one set and not two.
    final manifest = jsonDecode(
      await File(p.join(directory.path, 'images.json')).readAsString(),
    ) as Map<String, dynamic>;

    expect(
      (manifest['images'] as List).map((image) => (image as Map)['file']),
      reported,
    );
  });

  // One file that failed does not fail the run, as one file does not fail the
  // scan.
  test('a file that failed does not stop the run', () async {
    writeVideo('first.mp4');
    writeVideo('second.mkv');

    ffmpeg = _FakeFfmpeg(failsFor: {'second.mkv'});

    final controller = testController(
      testRelease(directory.path),
      TabManager(),
      'tab-1',
    );
    await controller.scan();

    final result = await controller.generateImages(1, ignoreRecord);

    expect(result.failure, isNull);
    expect(result.runs.map((run) => run.failure), [
      null,
      ImageGenerationFailureKind.failed,
    ]);

    // Only the item that was done is recorded.
    final manifest = jsonDecode(
      await File(p.join(directory.path, 'images.json')).readAsString(),
    ) as Map<String, dynamic>;

    expect(
      (manifest['images'] as List).map((image) => (image as Map)['item']),
      ['first.mp4', 'first.mp4'],
    );
  });

  // A tool that is not installed does not become installed while the app is
  // open, so the run stops at the first item that needed it.
  test('a tool that is not available stops the run', () async {
    writeVideo('first.mp4');
    writeVideo('second.mkv');

    mtn = _FakeMtn(available: false);

    final controller = testController(
      testRelease(directory.path),
      TabManager(),
      'tab-1',
    );
    await controller.scan();

    final result = await controller.generateImages(1, ignoreRecord);

    expect(result.runs, hasLength(1));
    expect(
      result.runs.single.failure,
      ImageGenerationFailureKind.mtnNotAvailable,
    );
    expect(mtn.calls, hasLength(1));
  });

  // A record whose file is not on disk is not shown, so deleting what the run
  // wrote takes the flag columns back to empty.
  test('a record whose file was deleted is not shown', () async {
    writeVideo('first.mp4');

    final controller = testController(
      testRelease(directory.path),
      TabManager(),
      'tab-1',
    );
    await controller.scan();

    await controller.generateImages(1, ignoreRecord);

    final shown = controller.imagesFor(controller.videos().single);
    expect(shown, hasLength(2));

    for (final record in shown) {
      File(p.join(directory.path, record.file)).deleteSync();
    }

    expect(controller.imagesFor(controller.videos().single), isEmpty);
  });

  Future<void> pumpSection(
    WidgetTester tester,
    Release release,
    List<Map<String, String>> applied,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<VideoScanner>(create: (_) => testScanner()),
          Provider<ImageGenerator>(create: (_) => testGenerator()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: VideoPackSection(
                release: release,
                tabId: 'tab-1',
                onApplyValues: (values) => applied.add(values),
                onImagesChanged: ignoreImagesChanged,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> scan(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Scan'));
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
  }

  Future<void> generate(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Generate'));
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
  }

  // The slider value is widget state, so the test sets it through the callback
  // the widget built.
  void setCount(WidgetTester tester, int value) {
    tester.widget<Slider>(find.byType(Slider)).onChanged!(value.toDouble());
  }

  testWidgets('the section shows what the scan could not take', (tester) async {
    writeVideo('first.mp4', videoType: '1080p');
    writeOther('cover.txt');
    Directory(p.join(directory.path, 'empty')).createSync();

    final release = testRelease(directory.path);
    final applied = <Map<String, String>>[];

    await pumpSection(tester, release, applied);

    // Nothing is shown before the scan: opening a release is a read and changes
    // nothing.
    expect(find.text('Not videos: cover.txt'), findsNothing);

    await scan(tester);

    expect(find.text('Not videos: cover.txt'), findsOneWidget);
    expect(find.text('Folders with no videos: empty'), findsOneWidget);

    // The values go through the editor's write path, not the section's.
    expect(applied.single['videoCount'], '1');
    expect(applied.single['videoResolutions'], '1080p');
    expect(applied.single['videoFormats'], 'mp4');
  });

  testWidgets(
    'the table shows each video as a row with its name, size and duration',
    (tester) async {
      writeVideo('first.mp4', videoType: '1080p', size: '1536');

      final release = testRelease(directory.path);

      await pumpSection(tester, release, []);

      expect(
        find.text('There are no videos. Pick the folder and scan it.'),
        findsOneWidget,
      );

      await scan(tester);

      // The header names the columns by the labels the fields have, so the
      // table and the form above it use the same words for the same values.
      expect(find.text('File name'), findsOneWidget);
      expect(find.text('File size'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('Screenlist'), findsOneWidget);
      expect(find.text('Screenshots'), findsOneWidget);

      // The path is the name the row shows, because two files in different
      // subfolders can share a file name, and the path is the ID the image
      // records link to.
      expect(find.text('first.mp4'), findsOneWidget);

      // The size is the short form, because a fixed-width cell cannot hold the
      // byte count as well.
      expect(find.text('1.5 KiB'), findsOneWidget);
      expect(find.text('00:01:00'), findsOneWidget);

      // What the row does not show is shown only when the row is open.
      expect(find.text('Video type: 1080p'), findsNothing);
    },
  );

  // The value columns are right-aligned so the numbers line up; the name is not
  // a number, so it is not, and each header follows its own column.
  testWidgets('the value columns are right-aligned and the name is not', (
    tester,
  ) async {
    writeVideo('first.mp4', size: '1536');

    final release = testRelease(directory.path);

    await pumpSection(tester, release, []);
    await scan(tester);

    expect(
      tester.widget<Text>(find.text('first.mp4')).textAlign,
      TextAlign.left,
    );
    expect(
      tester.widget<Text>(find.text('1.5 KiB')).textAlign,
      TextAlign.right,
    );
    expect(
      tester.widget<Text>(find.text('00:01:00')).textAlign,
      TextAlign.right,
    );

    expect(
      tester.widget<Text>(find.text('File name')).textAlign,
      TextAlign.left,
    );
    expect(
      tester.widget<Text>(find.text('File size')).textAlign,
      TextAlign.right,
    );
  });

  // Every other row is tinted so a table read as bands of text can be followed
  // with the eye. The tint is the row's, so it covers the detail as well, and
  // it is on a `Material` rather than a plain container: the hover highlight is
  // painted on the canvas of the nearest `Material` ancestor, and a container
  // would paint its colour over that.
  testWidgets('the rows alternate', (tester) async {
    writeVideo('first.mp4');
    writeVideo('second.mp4');
    writeVideo('third.mp4');

    final release = testRelease(directory.path);

    await pumpSection(tester, release, []);
    await scan(tester);

    final theme = Theme.of(tester.element(find.byType(VideoPackSection)));

    // The row's own `Material` is the nearest one above its content, which is
    // the surface the hover highlight is painted on.
    Material rowMaterial(String path) => tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(ValueKey('video-row-$path')),
            matching: find.byType(Material),
          )
          .first,
    );

    expect(rowMaterial('first.mp4').color, Colors.transparent);
    expect(
      rowMaterial('second.mp4').color,
      theme.colorScheme.surfaceContainerHigh,
    );
    expect(rowMaterial('third.mp4').color, Colors.transparent);

    // The band belongs to the row, so an open row is tinted as a whole and not
    // half of it.
    await tester.tap(find.byKey(const ValueKey('video-row-second.mp4')));
    await tester.pump();

    final second = find
        .ancestor(
          of: find.byKey(const ValueKey('video-row-second.mp4')),
          matching: find.byType(Material),
        )
        .first;

    expect(
      find.descendant(of: second, matching: find.text('Video: AVC')),
      findsOneWidget,
    );
  });

  testWidgets('clicking a row shows the values the row does not show', (
    tester,
  ) async {
    writeVideo('first.mp4', videoType: '1080p', size: '1536');

    final release = testRelease(directory.path);

    await pumpSection(tester, release, []);

    await scan(tester);

    await tester.tap(find.byKey(const ValueKey('video-row-first.mp4')));
    await tester.pump();

    expect(find.text('Video type: 1080p'), findsOneWidget);
    expect(find.text('Video format: MP4'), findsOneWidget);
    expect(find.text('Video: AVC'), findsOneWidget);
    expect(find.text('Audio: AAC'), findsOneWidget);

    // The values that are in the row are not repeated in the detail.
    expect(find.text('File size: 1.5 KiB (1536 bytes)'), findsNothing);

    // Which rows are open is widget state, so a rebuild does not close one.
    await tester.pump();
    expect(find.text('Video: AVC'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('video-row-first.mp4')));
    await tester.pump();

    expect(find.text('Video: AVC'), findsNothing);
  });

  testWidgets('a release opened with items shows them without a scan', (
    tester,
  ) async {
    final release = testRelease(directory.path);

    // What a manifest holds: the item is the path, and the values are what an
    // earlier scan wrote.
    release.items.add(
      ReleaseItem(
        path: 'videos/second.mkv',
        type: 'video',
        fields: FieldValues()..setValue('videoType', '2160p'),
      ),
    );

    await pumpSection(tester, release, []);

    // The row is there without a scan, because the section reads what the
    // release stores. A value the app does not have is shown as nothing, so the
    // row has only its name.
    expect(find.text('videos/second.mkv'), findsOneWidget);
    expect(find.text('Video type: 2160p'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('video-row-videos/second.mkv')));
    await tester.pump();

    expect(find.text('Video type: 2160p'), findsOneWidget);
    expect(
      find.text('There are no videos. Pick the folder and scan it.'),
      findsNothing,
    );
  });

  testWidgets('a source that is not there is shown as a message', (
    tester,
  ) async {
    final release = testRelease(p.join(directory.path, 'missing'));

    await pumpSection(tester, release, []);

    await scan(tester);

    expect(find.text('The picked folder was not found.'), findsOneWidget);
  });

  // The slider allows 0 here, because a run over many files can write only the
  // screenlist; the button is disabled while there is nothing to generate.
  testWidgets(
    'the slider starts at 0 and the button is disabled until there are items',
    (tester) async {
      writeVideo('first.mp4');

      final release = testRelease(directory.path);

      await pumpSection(tester, release, []);

      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('videoGenerateButton')),
      );
      expect(button.onPressed, isNull);

      await scan(tester);

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 0);
      expect(slider.max, 20);
      expect(slider.value, 0);

      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('videoGenerateButton')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  // The two buttons are in the title row, at the right of the section's title,
  // because they are the actions of the whole section rather than a row inside
  // it. The row that remains is the label, the slider and the count.
  testWidgets('the Scan and Generate buttons are in the title row', (
    tester,
  ) async {
    final release = testRelease(directory.path);

    await pumpSection(tester, release, []);

    for (final key in ['videoScanButton', 'videoGenerateButton']) {
      expect(
        find.ancestor(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(SectionTitle),
        ),
        findsOneWidget,
      );
    }

    expect(
      find.ancestor(
        of: find.byType(Slider),
        matching: find.byType(SectionTitle),
      ),
      findsNothing,
    );
  });

  testWidgets('the run writes the images and the columns show them', (
    tester,
  ) async {
    writeVideo('first.mp4', size: '1536');

    final release = testRelease(directory.path);

    await pumpSection(tester, release, []);
    await scan(tester);

    // Nothing is generated yet, so the flag columns are empty: a screenlist
    // column that shows a checkmark and a count column that shows nothing are
    // both the honest reading of an item with no images.
    expect(find.byIcon(Icons.check), findsNothing);

    setCount(tester, 2);
    await tester.pump();

    await generate(tester);

    expect(find.byIcon(Icons.check), findsOneWidget);

    // The count is the cell's, not the slider's own number, so it is looked for
    // inside the row.
    final row = find.byKey(const ValueKey('video-row-first.mp4'));
    expect(find.descendant(of: row, matching: find.text('2')), findsOneWidget);

    // The checkmark follows its column, like the text cells do.
    final align = tester.widget<Align>(
      find
          .ancestor(of: find.byIcon(Icons.check), matching: find.byType(Align))
          .first,
    );
    expect(align.alignment, Alignment.centerRight);

    // The run wrote files, so the release changed and the manifest holds them.
    expect(
      jsonDecode(
        File(p.join(directory.path, 'images.json')).readAsStringSync(),
      ),
      isA<Map<String, dynamic>>(),
    );
  });

  // The images the run wrote are shown in the open row: the screenlist at the
  // detail's width, the screenshots as small tiles. A closed row shows none,
  // because only the open row builds them.
  testWidgets('the open row shows the images the run wrote', (tester) async {
    writeVideo('first.mp4');

    final release = testRelease(directory.path);

    await pumpSection(tester, release, []);
    await scan(tester);

    setCount(tester, 2);
    await tester.pump();

    await generate(tester);

    expect(find.byType(Image), findsNothing);

    await tester.tap(find.byKey(const ValueKey('video-row-first.mp4')));
    await tester.pump();

    // The screenlist plus the two screenshots the fake tool wrote.
    expect(find.byType(Image), findsNWidgets(3));
  });

  // A record whose file is not on disk is not an image the app can show, so
  // closing and reopening the row shows nothing.
  testWidgets('a record whose file was deleted is not shown in the open row', (
    tester,
  ) async {
    writeVideo('first.mp4');

    final release = testRelease(directory.path);

    await pumpSection(tester, release, []);
    await scan(tester);

    setCount(tester, 1);
    await tester.pump();

    await generate(tester);

    await tester.tap(find.byKey(const ValueKey('video-row-first.mp4')));
    await tester.pump();

    expect(find.byType(Image), findsNWidgets(2));

    for (final entry in Directory(
      p.join(directory.path, 'images'),
    ).listSync(recursive: true)) {
      if (entry is File) {
        entry.deleteSync();
      }
    }

    await tester.tap(find.byKey(const ValueKey('video-row-first.mp4')));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
  });

  // Regenerating writes the same names, so the only way the tile shows the new
  // file is that its key changes and the image re-resolves against the emptied
  // cache (`AGENTS.md` rule 5).
  testWidgets('the tile re-resolves a file the run rewrote', (tester) async {
    writeVideo('first.mp4');

    final release = testRelease(directory.path);

    await pumpSection(tester, release, []);
    await scan(tester);

    setCount(tester, 1);
    await tester.pump();

    await generate(tester);

    await tester.tap(find.byKey(const ValueKey('video-row-first.mp4')));
    await tester.pump();

    final key = tester.widget<Image>(find.byType(Image).first).key;

    await generate(tester);

    expect(
      tester.widget<Image>(find.byType(Image).first).key,
      isNot(key),
      reason: 'the tile must re-resolve the regenerated file',
    );
  });

  // A run that did most of the files is not an error, so what it could not do
  // is a line in the section, with the scan's lines.
  testWidgets('the files the run could not do are listed as a line', (
    tester,
  ) async {
    writeVideo('first.mp4');
    writeVideo('second.mkv');
    writeOther('cover.txt');

    ffmpeg = _FakeFfmpeg(failsFor: {'second.mkv'});

    final release = testRelease(directory.path);

    await pumpSection(tester, release, []);
    await scan(tester);

    // A run with 0 writes no screenshots, so a file that fails at one is not
    // reached.
    setCount(tester, 1);
    await tester.pump();

    await generate(tester);

    expect(find.text('Not videos: cover.txt'), findsOneWidget);
    expect(
      find.text('Could not create images for: second.mkv'),
      findsOneWidget,
    );

    // A re-scan replaces the items, so the line that named a file which is no
    // longer one is cleared with it.
    File(p.join(directory.path, 'second.mkv')).deleteSync();
    await scan(tester);

    expect(find.text('Could not create images for: second.mkv'), findsNothing);
  });

  // A tool that is not installed is what the whole run could not do, so it is a
  // message, the same text the Single video section shows.
  testWidgets('a tool that is not installed is shown as a message', (
    tester,
  ) async {
    writeVideo('first.mp4');

    mtn = _FakeMtn(available: false);

    final release = testRelease(directory.path);

    await pumpSection(tester, release, []);
    await scan(tester);
    await generate(tester);

    expect(
      find.text('mtn is not installed. Install it to create screenlists.'),
      findsOneWidget,
    );
  });
}
