import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:release_prepper/feature/message/message_controller.dart';
import 'package:release_prepper/feature/message/message_store.dart';
import 'package:release_prepper/feature/message/screenshot_layout.dart';
import 'package:release_prepper/feature/photosets/photoset_group.dart';
import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/release/release_editor.dart';
import 'package:release_prepper/feature/release/release_editor_controller.dart';
import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/release/release_store.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/tracker.dart';
import 'package:release_prepper/feature/screenshots/images.dart';
import 'package:release_prepper/feature/screenshots/images_store.dart';
import 'package:release_prepper/feature/settings/secret_store.dart';
import 'package:release_prepper/feature/settings/settings.dart';
import 'package:release_prepper/feature/settings/settings_controller.dart';
import 'package:release_prepper/feature/settings/settings_store.dart';
import 'package:release_prepper/feature/tab/tab_manager.dart';
import 'package:release_prepper/l10n/app_localizations.dart';
import 'package:release_prepper/service/images/masonry.dart';
import 'package:release_prepper/service/launcher/folder_opener.dart';
import 'package:release_prepper/service/launcher/url_opener.dart';
import 'package:release_prepper/service/native_tools/ffmpeg.dart';
import 'package:release_prepper/service/native_tools/ffprobe.dart';
import 'package:release_prepper/service/native_tools/media_info.dart';
import 'package:release_prepper/service/native_tools/mkbrr.dart';
import 'package:release_prepper/service/native_tools/mtn.dart';
import 'package:release_prepper/service/native_tools/tool_runner.dart';
import 'package:release_prepper/service/native_tools/uptooda.dart';
import 'package:release_prepper/service/network/image_downloader.dart';
import 'package:release_prepper/service/network/pornolab_client.dart';
import 'package:release_prepper/service/network/stash_client.dart';
import 'package:release_prepper/service/photosets/directory_reader.dart';
import 'package:release_prepper/service/photosets/photoset_scanner.dart';
import 'package:release_prepper/service/stashdb/domain_map.dart';
import 'package:release_prepper/service/template/template_renderer.dart';
import 'package:release_prepper/service/template/template_store.dart';
import 'package:release_prepper/service/videos/image_generator.dart';
import 'package:release_prepper/service/videos/video_scanner.dart';

import 'fake_pornolab_client.dart';
import 'test_fields.dart';
import 'test_font_store.dart';
import 'test_runner.dart';

// The editor also draws the Upload section's hoster icons, and those are
// `Image` widgets too, so a test that looks at one of the boxes has to look
// past them. A box shows a file from disk, so a `FileImage` is what identifies
// the image a box shows.
Finder boxImage() => find.byWidgetPredicate(
  (widget) => widget is Image && widget.image is FileImage,
);

// The poster box and the video box are the same widget, so a test that looks at
// one has to say which one it means; an empty box draws its own icon, so the
// box is found through it.
Finder videoBox(WidgetTester tester) => find.ancestor(
  of: find.byIcon(Icons.smart_display_outlined),
  matching: find.byType(AspectRatio),
);

// The editor renders the Message section, so every test that builds it has to
// provide its dependencies. The bundle answers with nothing, so the section
// shows an empty box: none of these tests reach the Generate button, and the
// Message behaviour is in `test/message_section_test.dart`. A test that does
// reach it — the one about the rows a refused generation marks, which this
// widget draws — gives a bundle with a template.
List<SingleChildWidget> messageProviders([AssetBundle? bundle]) => [
  Provider<TemplateStore>(
    create: (_) => TemplateStore(bundle: bundle ?? _EmptyBundle()),
  ),
  Provider<TemplateRenderer>(create: (_) => const TemplateRenderer()),
  Provider<MessageStore>(create: (_) => MessageStore()),
];

// The editor renders the StashDB section, so every test that builds it provides
// its dependencies too. The client answers with nothing, the settings hold no
// key and the bundle has no mapping, so none of these tests reach the Fetch
// button; the Stash behaviour is in `test/stash_section_test.dart`.
List<SingleChildWidget> stashProviders() => [
  Provider<StashClient>(create: (_) => _FakeStashClient()),
  Provider<DomainMap>(create: (_) => DomainMap(bundle: _EmptyBundle())),
  ChangeNotifierProvider<SettingsController>(
    create: (_) => SettingsController(
      store: _FakeSettingsStore(),
      secretStore: _FakeSecretStore(),
      homeDirectory: '',
      pathContext: p.context,
      client: FakePornolabClient(),
      appDirectory: () async => Directory.systemTemp,
    ),
  ),
];

// The editor renders the Upload draft section, so every test that builds it has
// to provide its client and the launcher the draft link uses. The client answers
// with nothing and the settings hold no credentials, so none of these tests
// reach the Upload button or the link; the draft behaviour is in
// `test/draft_section_test.dart`.
List<SingleChildWidget> draftProviders() => [
  Provider<PornolabClient>(create: (_) => FakePornolabClient()),
  Provider<UrlOpener>(create: (_) => const UrlOpener()),
];

// The Screenshots section and the Video pack section build their controllers
// from the generator, so every test that builds the editor has to provide it.
// It is the same test runner the tools these tests already provide, so a call
// through it is a call through the same fake. None of these tests reach a
// Generate button; the generation behaviour is in `test/screenshots_test.dart`
// and `test/video_pack_test.dart`.
List<SingleChildWidget> imageGeneratorProviders() => [
  Provider<ImageGenerator>(
    create: (context) => ImageGenerator(
      ffmpeg: context.read<Ffmpeg>(),
      ffprobe: context.read<Ffprobe>(),
      mtn: context.read<Mtn>(),
      fonts: testFontStore(),
    ),
  ),
];

// The editor renders the Torrent section, so every test that builds it has to
// provide its tool and the folder opener the section's link uses. The test
// runner resolves nothing, so a call through it says the tool is not present;
// none of these tests reach the Create button or the link, and the torrent
// behaviour is in `test/torrent_section_test.dart`.
List<SingleChildWidget> torrentProviders() => [
  Provider<Mkbrr>(create: (_) => Mkbrr(runner: testRunner())),
  Provider<FolderOpener>(create: (_) => const FolderOpener()),
];

class _FakeStashClient implements StashClient {
  @override
  HttpClient get client => HttpClient();

  @override
  Future<StashResult> findScene({
    required String sceneId,
    required String apiKey,
  }) async => const StashFailure(StashFailureKind.noApiKey);
}

class _FakeSecretStore implements SecretStore {
  @override
  Future<Map<String, String>> readAll() async => {};

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

class _FakeSettingsStore implements SettingsStore {
  @override
  Future<Directory> Function() get appDirectory =>
      () async => Directory.systemTemp;

  @override
  Future<String> filePath() async => 'settings.json';

  @override
  Future<Settings> load() async => Settings.defaults();

  @override
  Future<void> save(Settings settings) async {}
}

class _EmptyBundle extends AssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw Exception('missing asset: $key');
}

// A bundle that answers with one template, for the test that reaches the
// Generate button. The style is the one the renderer reads, so the answer is
// the same as the real one.
class _FakeBundle extends AssetBundle {
  _FakeBundle(this.template);

  final String template;

  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('.style')) {
      return ByteData.sublistView(utf8.encode('text = {content}'));
    }

    return ByteData.sublistView(utf8.encode(template));
  }
}

void main() {
  // A release as the app builds it: the item is the file the user picked, so
  // its path is the filename (`ai/release_structure.md` §2). No source means no
  // item.
  Release testRelease(
    String directoryPath, {
    String source = '/home/user/videos',
    FieldValues? fields,
  }) => Release(
    name: 'x',
    directoryPath: directoryPath,
    tracker: Tracker.pornolab,
    releaseType: ReleaseType.singleVideo,
    source: source,
    fields: fields ?? FieldValues(),
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

  // A photoset pack as the app builds it: the source is the folder the user
  // picked and the items are what the scan writes, so a new pack has none.
  Release testPackRelease(String directoryPath, {String source = ''}) =>
      Release(
        name: 'x',
        directoryPath: directoryPath,
        tracker: Tracker.pornolab,
        releaseType: ReleaseType.photosetPack,
        source: source,
        fields: FieldValues(),
        items: [],
      );

  // A video pack as the app builds it: the source is the folder the user picked
  // and the items are what the scan writes, so a new pack has none.
  Release testVideoPackRelease(String directoryPath, {String source = ''}) =>
      Release(
        name: 'x',
        directoryPath: directoryPath,
        tracker: Tracker.pornolab,
        releaseType: ReleaseType.videoPack,
        source: source,
        fields: FieldValues(),
        items: [],
      );

  // A single photoset as the app builds it: the source is the folder the user
  // picked and it is the item itself, so a new one has no items until the scan
  // runs.
  Release testSinglePhotosetRelease(
    String directoryPath, {
    String source = '',
  }) => Release(
    name: 'x',
    directoryPath: directoryPath,
    tracker: Tracker.pornolab,
    releaseType: ReleaseType.singlePhotoset,
    source: source,
    fields: FieldValues(),
    items: [],
  );

  // An image folder as the app builds it: the source is the folder the user
  // picked and it is the item itself, so a new one has no items until the scan
  // runs.
  Release testImageFolderRelease(String directoryPath, {String source = ''}) =>
      Release(
        name: 'x',
        directoryPath: directoryPath,
        tracker: Tracker.pornolab,
        releaseType: ReleaseType.imageFolderUpload,
        source: source,
        fields: FieldValues(),
        items: [],
      );

  // The editor with the providers its sections read.
  Future<void> openEditor(
    WidgetTester tester,
    Release release, {
    // The bundle the Message section reads. The default is the empty one
    // above, so a test that does not generate is not also about a template.
    AssetBundle? messageBundle,
    // The tool the poster path calls. The default is the test runner, which
    // resolves nothing, so a test that writes a poster has to give the fake.
    Ffmpeg? ffmpeg,
    // The same for the download a pasted link goes through: the default client
    // answers with nothing under the test binding, so a test that reaches the
    // poster path through a link has to give the fake.
    ImageDownloader? downloader,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          ...messageProviders(messageBundle),
          ...stashProviders(),
          ...draftProviders(),
          ...torrentProviders(),
          Provider<Uptooda>(create: (_) => Uptooda(runner: testRunner())),
          Provider<Ffprobe>(create: (_) => Ffprobe(runner: testRunner())),
          Provider<Ffmpeg>(
            create: (_) => ffmpeg ?? Ffmpeg(runner: testRunner()),
          ),
          Provider<Mtn>(create: (_) => Mtn(runner: testRunner())),
          ...imageGeneratorProviders(),
          Provider<ImageDownloader>(
            create: (_) => downloader ?? ImageDownloader(client: HttpClient()),
          ),
          Provider<PhotosetScanner>(
            create: (_) =>
                PhotosetScanner(readers: [const DirectoryPhotosetReader()]),
          ),
          Provider<VideoScanner>(
            create: (context) => VideoScanner(probe: context.read<Ffprobe>()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReleaseEditor(release: release, tabId: 'tab-1'),
          ),
        ),
      ),
    );
  }

  // A poster record, because the record is what says where the image is
  // (`ai/release_structure.md` §4). Real IO, so the caller runs it in runAsync.
  // No URLs by default, because a test that looks at the box is not about the
  // upload; a test that reaches the Generate button has to say the poster is
  // on the poster hoster, because that is what the generation gate reads.
  Future<void> writePosterRecord(
    String directoryPath, {
    Map<String, Map<String, String>> urls = const {},
  }) => ImagesStore().save(
    directoryPath,
    ImagesManifest(
      images: [
        ImageRecord(
          item: null,
          kind: ImageKind.poster,
          file: '_rp_poster.jpg',
          urls: urls,
        ),
      ],
    ),
  );

  // The editor gives every field a key, so a test finds it by the field name
  // rather than by its position in the form, which the two columns change.
  TextField fieldOf(WidgetTester tester, String name) =>
      tester.widget<TextField>(
        find.descendant(
          of: find.byKey(ValueKey(name)),
          matching: find.byType(TextField),
        ),
      );

  // The titles are read from the editor's State, and a pump reuses the State of
  // a widget that is in the same place, so a test cannot open two release types
  // in one run.
  Future<List<String>> titlesOf(WidgetTester tester, Release release) async {
    await openEditor(tester, release);

    return find
        .byKey(const ValueKey('columnTitle'))
        .evaluate()
        .map((element) => (element.widget as Text).data!)
        .toList();
  }

  // Real file IO cannot be awaited inside a widget test: the test body runs in
  // a fake-async zone, so an IO completion never arrives. Every disk access
  // here goes through tester.runAsync.
  testWidgets('a picked date is written into its field', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final release = testRelease('/tmp/x', fields: FieldValues());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          ...messageProviders(),
          ...stashProviders(),
          ...draftProviders(),
          ...torrentProviders(),
          Provider<Uptooda>(create: (_) => Uptooda(runner: testRunner())),
          Provider<Ffprobe>(create: (_) => Ffprobe(runner: testRunner())),
          Provider<Ffmpeg>(create: (_) => Ffmpeg(runner: testRunner())),
          Provider<Mtn>(create: (_) => Mtn(runner: testRunner())),
          ...imageGeneratorProviders(),
          Provider<ImageDownloader>(
            create: (_) => ImageDownloader(client: HttpClient()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReleaseEditor(release: release, tabId: 'tab-1'),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Choose date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(fieldOf(tester, 'productionDate').controller?.text, isNotEmpty);
  });

  testWidgets(
    'the form fills from the manifest, marks the tab dirty, and saves',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      final directory = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );
      final store = ReleaseStore();

      await tester.runAsync(() async {
        await File(p.join(directory.path, 'release.json')).writeAsString(
          jsonEncode({
            'schema': schemaVersion,
            'tracker': 'pornolab',
            'releaseType': 'singleVideo',
            'source': '/home/user/videos',
            'fields': {
              'videoTitle': 'Loaded title',
              'productionDate': '2024-05-06',
            },
            'items': [
              {'path': 'movie.mp4', 'type': 'video', 'fields': {}},
            ],
          }),
        );
      });

      late final Release release;

      await tester.runAsync(() async {
        release = await store.load(directory.path);
      });

      final tabManager = TabManager();
      final tabId = tabManager.addReleaseEditor(release);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ReleaseStore>(create: (_) => store),
            ChangeNotifierProvider<TabManager>(create: (_) => tabManager),
            Provider<ImagesStore>(create: (_) => ImagesStore()),
            ...messageProviders(),
            ...stashProviders(),
            ...draftProviders(),
            ...torrentProviders(),
            Provider<Uptooda>(create: (_) => Uptooda(runner: testRunner())),
            Provider<Ffprobe>(create: (_) => Ffprobe(runner: testRunner())),
            Provider<Ffmpeg>(create: (_) => Ffmpeg(runner: testRunner())),
            Provider<Mtn>(create: (_) => Mtn(runner: testRunner())),
            ...imageGeneratorProviders(),
            Provider<ImageDownloader>(
              create: (_) => ImageDownloader(client: HttpClient()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ReleaseEditor(release: release, tabId: tabId),
            ),
          ),
        ),
      );

      expect(fieldOf(tester, 'videoTitle').controller?.text, 'Loaded title');
      expect(fieldOf(tester, 'productionDate').controller?.text, '2024-05-06');

      expect(tabManager.tabs.single.hasUnsavedChanges, isFalse);

      await tester.enterText(
        find.byKey(const ValueKey('videoTitle')),
        'Edited title',
      );
      await tester.pump();

      expect(tabManager.tabs.single.hasUnsavedChanges, isTrue);

      await tester.runAsync(() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await Future.delayed(const Duration(milliseconds: 100));
      });

      late final Map<String, dynamic> saved;

      await tester.runAsync(() async {
        saved = jsonDecode(
          await File(p.join(directory.path, 'release.json')).readAsString(),
        ) as Map<String, dynamic>;
      });

      expect(saved['fields']['videoTitle'], 'Edited title');

      // The record is the shape `release.json` writes
      // (`ai/release_structure.md`), and the path the user picked is part of
      // it, so saving writes it too.
      expect(saved['schema'], schemaVersion);
      expect(saved['source'], '/home/user/videos');
      expect(saved['items'], [
        {'path': 'movie.mp4', 'type': 'video', 'fields': {}},
      ]);

      expect(tabManager.tabs.single.hasUnsavedChanges, isFalse);

      directory.deleteSync(recursive: true);
    },
  );

  // The scene link is a field, so a manifest holds it like any other field
  // value. Its row is the Stash row at the top of the form's left column, and
  // that widget keys its own input, so the field name is not a key in the form.
  testWidgets('the scene link a manifest holds is what the Stash input shows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final store = ReleaseStore();

    await tester.runAsync(() async {
      await File(p.join(directory.path, 'release.json')).writeAsString(
        jsonEncode({
          'schema': schemaVersion,
          'tracker': 'pornolab',
          'releaseType': 'singleVideo',
          'source': '/home/user/videos',
          'fields': {'sceneUrl': 'https://stashdb.org/scenes/abc'},
          'items': [],
        }),
      );
    });

    late final Release release;

    await tester.runAsync(() async {
      release = await store.load(directory.path);
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReleaseStore>(create: (_) => store),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          ...messageProviders(),
          ...stashProviders(),
          ...draftProviders(),
          ...torrentProviders(),
          Provider<Uptooda>(create: (_) => Uptooda(runner: testRunner())),
          Provider<Ffprobe>(create: (_) => Ffprobe(runner: testRunner())),
          Provider<Ffmpeg>(create: (_) => Ffmpeg(runner: testRunner())),
          Provider<Mtn>(create: (_) => Mtn(runner: testRunner())),
          ...imageGeneratorProviders(),
          Provider<ImageDownloader>(
            create: (_) => ImageDownloader(client: HttpClient()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReleaseEditor(release: release, tabId: 'tab-1'),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('stashSceneInput')))
          .controller
          ?.text,
      'https://stashdb.org/scenes/abc',
    );
    expect(find.byKey(const ValueKey('sceneUrl')), findsNothing);

    directory.deleteSync(recursive: true);
  });

  // Items 8, 9, 11, 12, 13 and 16 of ai/release_editor.md are filled from the
  // movie file, so they are read-only.
  testWidgets('the fields ffprobe fills are read-only', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final release = testRelease('/tmp/x', fields: FieldValues());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          ...messageProviders(),
          ...stashProviders(),
          ...draftProviders(),
          ...torrentProviders(),
          Provider<Uptooda>(create: (_) => Uptooda(runner: testRunner())),
          Provider<Ffprobe>(create: (_) => Ffprobe(runner: testRunner())),
          Provider<Ffmpeg>(create: (_) => Ffmpeg(runner: testRunner())),
          Provider<Mtn>(create: (_) => Mtn(runner: testRunner())),
          ...imageGeneratorProviders(),
          Provider<ImageDownloader>(
            create: (_) => ImageDownloader(client: HttpClient()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReleaseEditor(release: release, tabId: 'tab-1'),
          ),
        ),
      ),
    );

    for (final field in singleVideoFieldList.fields) {
      // A field whose row is another widget's is edited there: the scene link
      // is the Stash row, and its input is keyed by the widget, not by the
      // field name.
      if (!field.hasFormRow) {
        expect(find.byKey(ValueKey(field.name)), findsNothing);
        continue;
      }

      expect(
        fieldOf(tester, field.name).readOnly,
        field.filledByApp,
        reason: field.name,
      );
    }
  });

  // Item 16: the model stores the byte count, and the field shows it in a
  // human-friendly form as well. A manifest holds the byte count, so a release
  // opened from disk shows the same text as one the probe just read.
  testWidgets(
    'the size field shows the byte count formatted, and the model keeps '
    'the bytes',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      final directory = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );
      final store = ReleaseStore();

      await tester.runAsync(() async {
        await File(p.join(directory.path, 'release.json')).writeAsString(
          jsonEncode({
            'schema': schemaVersion,
            'tracker': 'pornolab',
            'releaseType': 'singleVideo',
            'source': '/home/user/videos',
            'fields': {'fileSize': '10200000000'},
            'items': [],
          }),
        );
      });

      late final Release release;

      await tester.runAsync(() async {
        release = await store.load(directory.path);
      });

      final tabManager = TabManager();
      final tabId = tabManager.addReleaseEditor(release);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ReleaseStore>(create: (_) => store),
            ChangeNotifierProvider<TabManager>(create: (_) => tabManager),
            Provider<ImagesStore>(create: (_) => ImagesStore()),
            ...messageProviders(),
            ...stashProviders(),
            ...draftProviders(),
            ...torrentProviders(),
            Provider<Uptooda>(create: (_) => Uptooda(runner: testRunner())),
            Provider<Ffprobe>(create: (_) => Ffprobe(runner: testRunner())),
            Provider<Ffmpeg>(create: (_) => Ffmpeg(runner: testRunner())),
            Provider<Mtn>(create: (_) => Mtn(runner: testRunner())),
            ...imageGeneratorProviders(),
            Provider<ImageDownloader>(
              create: (_) => ImageDownloader(client: HttpClient()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ReleaseEditor(release: release, tabId: tabId),
            ),
          ),
        ),
      );

      expect(
        fieldOf(tester, 'fileSize').controller?.text,
        '9.5 GiB (10200000000 bytes)',
      );
      expect(
        release.fields.value('fileSize'),
        '10200000000',
        reason: 'the value that is saved is the byte count, not the text shown',
      );

      directory.deleteSync(recursive: true);
    },
  );

  // The same field filled by the probe goes through the single write path, so
  // the model gets the byte count and the field shows the derived text.
  testWidgets(
    'the size the probe reports is stored as bytes and shown formatted',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      final directory = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );
      final video = File(p.join(directory.path, 'movie.mp4'));
      video.writeAsStringSync('not a real video file');

      final fields = FieldValues();
      final release = testRelease(
        directory.path,
        source: video.path,
        fields: fields,
      );

      final probe = _FakeProbe(
        const MediaInfo(
          fileSize: '10200000000',
          duration: '',
          durationSeconds: null,
          videoType: '',
          videoFormat: '',
          videoStream: '',
          audioStream: '',
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ReleaseStore>(create: (_) => ReleaseStore()),
            ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
            Provider<ImagesStore>(create: (_) => ImagesStore()),
            ...messageProviders(),
            ...stashProviders(),
            ...draftProviders(),
            ...torrentProviders(),
            Provider<Uptooda>(create: (_) => Uptooda(runner: testRunner())),
            Provider<Ffprobe>(create: (_) => probe),
            Provider<Ffmpeg>(create: (_) => _FakeFfmpeg()),
            Provider<Mtn>(create: (_) => Mtn(runner: testRunner())),
            ...imageGeneratorProviders(),
            Provider<ImageDownloader>(
              create: (_) => ImageDownloader(client: HttpClient()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ReleaseEditor(release: release, tabId: 'tab-1'),
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await tester.enterText(find.byKey(sourceRowKey), video.path);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      });

      expect(release.fields.value('fileSize'), '10200000000');
      expect(
        fieldOf(tester, 'fileSize').controller?.text,
        '9.5 GiB (10200000000 bytes)',
      );

      directory.deleteSync(recursive: true);
    },
  );

  // Typing must not be echoed back into the field. Writing the value the field
  // already shows moves the caret to the end and clears the IME composition,
  // which is what made typing stop after one character.
  testWidgets('typing keeps the caret where the user put it', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final release = testRelease('/tmp/x', fields: FieldValues());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          ...messageProviders(),
          ...stashProviders(),
          ...draftProviders(),
          ...torrentProviders(),
          Provider<Uptooda>(create: (_) => Uptooda(runner: testRunner())),
          Provider<Ffprobe>(create: (_) => Ffprobe(runner: testRunner())),
          Provider<Ffmpeg>(create: (_) => Ffmpeg(runner: testRunner())),
          Provider<Mtn>(create: (_) => Mtn(runner: testRunner())),
          ...imageGeneratorProviders(),
          Provider<ImageDownloader>(
            create: (_) => ImageDownloader(client: HttpClient()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReleaseEditor(release: release, tabId: 'tab-1'),
          ),
        ),
      ),
    );

    final field = find.byKey(const ValueKey('videoTitle'));
    await tester.showKeyboard(field);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    // The user moves the caret into the middle of the word and types.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'heXllo',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();

    final controller = fieldOf(tester, 'videoTitle').controller!;

    expect(controller.text, 'heXllo');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
  });

  // The user's scenario: the path is submitted, the tool writes the file, and
  // the box shows it. The box builds an image only for a file that is on disk,
  // because Flutter remembers a failed load for the same path — an image built
  // for a file that is not there stays empty even after the tool writes it.
  testWidgets('the thumbnail box shows the file the tool writes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final video = File(p.join(directory.path, 'movie.mp4'));
    video.writeAsStringSync('not a real video file');

    final fields = FieldValues();
    final release = testRelease(
      directory.path,
      source: video.path,
      fields: fields,
    );

    final probe = _FakeProbe(
      const MediaInfo(
        fileSize: '',
        duration: '00:00:08',
        durationSeconds: 8,
        videoType: '',
        videoFormat: '',
        videoStream: '',
        audioStream: '',
      ),
    );
    final ffmpeg = _FakeFfmpeg();
    final downloader = _FakeDownloader(
      DownloadSuccess('', ContentType('image', 'jpeg')),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          ...messageProviders(),
          ...stashProviders(),
          ...draftProviders(),
          ...torrentProviders(),
          Provider<Uptooda>(create: (_) => Uptooda(runner: testRunner())),
          Provider<Ffprobe>(create: (_) => probe),
          Provider<Ffmpeg>(create: (_) => ffmpeg),
          Provider<Mtn>(create: (_) => Mtn(runner: testRunner())),
          ...imageGeneratorProviders(),
          Provider<ImageDownloader>(create: (_) => downloader),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReleaseEditor(release: release, tabId: 'tab-1'),
          ),
        ),
      ),
    );

    // Nothing is on disk yet, so the box shows no image.
    expect(boxImage(), findsNothing);

    // The controller reads the disk, which only completes outside the
    // fake-async zone, so the whole flow runs in runAsync.
    await tester.runAsync(() async {
      await tester.enterText(find.byKey(sourceRowKey), video.path);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    expect(boxImage(), findsOneWidget);
    expect(
      (tester.widget<Image>(boxImage()).image as FileImage).file.path,
      p.join(directory.path, 'images/movie.mp4/_rp_thumbnail.jpg'),
      reason: 'the box shows the file the tool wrote',
    );

    directory.deleteSync(recursive: true);
  });

  // An empty video box says what it is missing, because the two empty cases are
  // different things: no video is picked, versus a video that is there with no
  // frame. Clicking the box does the same as the pick button on the source row,
  // because that is where the user is looking — the same shape the poster box
  // has.
  testWidgets(
    'the empty video box says no video is selected and can be clicked',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      final release = testRelease('/tmp/x', source: '', fields: FieldValues());

      await openEditor(tester, release);

      expect(find.text('No video selected'), findsOneWidget);
      expect(find.text('Click to choose a video.'), findsOneWidget);

      final well = tester.widget<InkWell>(
        find.descendant(of: videoBox(tester), matching: find.byType(InkWell)),
      );
      expect(
        well.onTap,
        isNotNull,
        reason: 'the box is the place the user is looking at',
      );

      // The poster box is not a box for a video, so it still says no image.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.byIcon(Icons.image_outlined),
            matching: find.byType(AspectRatio),
          ),
          matching: find.text('No image selected'),
        ),
        findsOneWidget,
      );
    },
  );

  // A video that is there with no frame is not a video that is not there, so
  // the box says no image and does not invite the user to pick a file they have
  // already picked.
  testWidgets('a video with no frame says no image, not no video', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final release = testRelease(
      '/tmp/x',
      source: '/home/user/videos/movie.mp4',
      fields: FieldValues(),
    );

    await openEditor(tester, release);

    expect(
      find.descendant(
        of: videoBox(tester),
        matching: find.text('No image selected'),
      ),
      findsOneWidget,
    );
    expect(find.text('No video selected'), findsNothing);
    expect(
      find.text('Click to choose a video.'),
      findsNothing,
      reason: 'the video is already picked',
    );
  });

  // Clicking the box reaches the picker through the same method the button on
  // the source row uses, so the two cannot disagree about what a click does.
  // The picker is a plugin, so the test puts a fake platform in for the
  // duration of the test; what the pick then does — write the source, probe,
  // write the frame — is the path the test above covers.
  testWidgets('clicking the video box opens the picker', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final original = FilePickerPlatform.instance;
    final picker = _FakeFilePicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = original);

    final release = testRelease('/tmp/x', source: '', fields: FieldValues());

    await openEditor(tester, release);

    await tester.runAsync(() async {
      await tester.tap(
        find.descendant(of: videoBox(tester), matching: find.byType(InkWell)),
      );
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    expect(
      picker.calls,
      1,
      reason: 'the box is the place the user is looking at',
    );
  });

  // The poster box shows the poster's UI thumbnail, and only for a file that is
  // on disk, for the same reason the thumbnail box does. A poster is usually
  // portrait, so it is fitted inside the box rather than cropped to it.
  testWidgets('the poster box shows nothing while no poster file is on disk', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final release = testRelease('/tmp/x', fields: FieldValues());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          ...messageProviders(),
          ...stashProviders(),
          ...draftProviders(),
          ...torrentProviders(),
          Provider<Uptooda>(create: (_) => Uptooda(runner: testRunner())),
          Provider<Ffprobe>(create: (_) => Ffprobe(runner: testRunner())),
          Provider<Ffmpeg>(create: (_) => _FakeFfmpeg()),
          Provider<Mtn>(create: (_) => Mtn(runner: testRunner())),
          ...imageGeneratorProviders(),
          Provider<ImageDownloader>(
            create: (_) => ImageDownloader(client: HttpClient()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReleaseEditor(release: release, tabId: 'tab-1'),
          ),
        ),
      ),
    );

    expect(boxImage(), findsNothing);
    expect(find.byTooltip('Choose image'), findsOneWidget);
    expect(find.byTooltip('Paste from URL'), findsOneWidget);
    expect(
      find.byTooltip('Remove image'),
      findsNothing,
      reason: 'there is no poster to remove',
    );
  });

  testWidgets('the poster box shows the poster file that is on disk', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    File(p.join(directory.path, '_rp_poster.jpg'))
        .writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);

    final release = testRelease(directory.path, fields: FieldValues());

    // The box shows the image its record points at, so the record has to be
    // there.
    await tester.runAsync(() => writePosterRecord(directory.path));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          ...messageProviders(),
          ...stashProviders(),
          ...draftProviders(),
          ...torrentProviders(),
          Provider<Uptooda>(create: (_) => Uptooda(runner: testRunner())),
          Provider<Ffprobe>(create: (_) => Ffprobe(runner: testRunner())),
          Provider<Ffmpeg>(create: (_) => _FakeFfmpeg()),
          Provider<Mtn>(create: (_) => Mtn(runner: testRunner())),
          ...imageGeneratorProviders(),
          Provider<ImageDownloader>(
            create: (_) => ImageDownloader(client: HttpClient()),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReleaseEditor(release: release, tabId: 'tab-1'),
          ),
        ),
      ),
    );

    expect(boxImage(), findsOneWidget);

    final image = tester.widget<Image>(boxImage());
    expect(
      (image.image as FileImage).file.path,
      p.join(directory.path, '_rp_poster.jpg'),
    );
    expect(
      image.fit,
      BoxFit.contain,
      reason: 'a portrait poster is not cropped',
    );

    expect(find.byTooltip('Remove image'), findsOneWidget);

    // Removing it takes the file away, so the box shows nothing again.
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Remove image'));
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    expect(boxImage(), findsNothing);
    expect(
      File(p.join(directory.path, '_rp_poster.jpg')).existsSync(),
      isFalse,
    );

    // Removing the poster removes its record too, so the Upload section no
    // longer has an image that is not on disk.
    final manifest = await tester.runAsync(
      () => ImagesStore().load(directory.path),
    );
    expect(manifest!.of(ImageKind.poster), isEmpty);

    directory.deleteSync(recursive: true);
  });

  // The image cache is keyed by the file path, so a poster that replaces one
  // already shown would still be displayed as the image decoded from the file
  // the first time. The widget drops the cached image for the path it writes,
  // and the image is keyed with a generation that changes on every write so the
  // widget resolves against the now-empty cache. The test puts a real image in
  // the cache for the path, then lets the widget write over it, and checks both
  // halves.
  testWidgets('a poster written over one already shown is shown again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final posterPath = p.join(directory.path, '_rp_poster.jpg');

    // A real image, so the box decodes it and the cache keeps it.
    File(posterPath).writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGM4kWIEAANWAV/oF4RSAAAAAElFTkSuQmCC',
      ),
    );

    final downloader = _FakeDownloader(
      DownloadSuccess('', ContentType('image', 'jpeg')),
    );

    final release = testRelease(directory.path, fields: FieldValues());

    // The box shows the image its record points at, so the record has to be
    // there.
    await tester.runAsync(() => writePosterRecord(directory.path));

    // The link the clipboard holds.
    final channel = SystemChannels.platform;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'Clipboard.getData'
          ? {'text': 'https://example.com/poster.jpg'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
          Provider<ImagesStore>(create: (_) => ImagesStore()),
          ...messageProviders(),
          ...stashProviders(),
          ...draftProviders(),
          ...torrentProviders(),
          Provider<Uptooda>(create: (_) => Uptooda(runner: testRunner())),
          Provider<Ffprobe>(create: (_) => Ffprobe(runner: testRunner())),
          Provider<Ffmpeg>(create: (_) => _FakeFfmpeg()),
          Provider<Mtn>(create: (_) => Mtn(runner: testRunner())),
          ...imageGeneratorProviders(),
          Provider<ImageDownloader>(create: (_) => downloader),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReleaseEditor(release: release, tabId: 'tab-1'),
          ),
        ),
      ),
    );

    final provider = FileImage(File(posterPath));
    final sentinel = _SentinelCompleter();
    final cache = PaintingBinding.instance.imageCache;

    await tester.runAsync(() async {
      await tester.pumpAndSettle();

      final first = cache.putIfAbsent(provider, () => sentinel);
      expect(
        first,
        isNot(same(sentinel)),
        reason: 'the box put the image for that path in the cache',
      );

      final keyBefore = tester.widget<Image>(boxImage()).key;

      // The fake tool writes a different image at the same path.
      await tester.tap(find.byTooltip('Paste from URL'));
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      expect(
        cache.putIfAbsent(provider, () => sentinel),
        isNot(same(first)),
        reason: 'the image cached for the file the widget wrote is gone',
      );

      // Evicting is only half of it. The key the image is built with has to
      // change too, otherwise the mounted widget keeps the stream it resolved
      // the first time.
      expect(
        tester.widget<Image>(boxImage()).key,
        isNot(same(keyBefore)),
        reason: 'the box resolves the rewritten file rather than showing the first image',
      );
    });

    directory.deleteSync(recursive: true);
  });

  // The poster is a record in `images.json`, so writing one is a change the
  // Upload section shows: the pair its placeholder waits for is complete when
  // the poster arrives. The two widgets cannot see each other, so the editor —
  // the one that places both — tells the section (`ai/upload_images.md`).
  testWidgets('a poster added after screenshots shows the hoster list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    // The screenshots half of the pair is already there, so the poster is the
    // only thing the section is waiting for.
    await tester.runAsync(
      () => ImagesStore().save(
        directory.path,
        ImagesManifest(
          images: [
            ImageRecord(
              item: 'movie.mp4',
              kind: ImageKind.screenshot,
              file: 'images/movie.mp4/_rp_screenshot01.jpg',
              urls: const {},
            ),
          ],
        ),
      ),
    );

    final release = testRelease(directory.path, fields: FieldValues());

    // The link the clipboard holds, so the poster goes through the editor's
    // poster path. The download and the tool are the fakes the other poster
    // tests use, because under the test binding neither gives anything.
    final channel = SystemChannels.platform;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'Clipboard.getData'
          ? {'text': 'https://example.com/poster.jpg'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await openEditor(
      tester,
      release,
      ffmpeg: _FakeFfmpeg(),
      downloader: _FakeDownloader(
        DownloadSuccess('', ContentType('image', 'jpeg')),
      ),
    );

    expect(
      find.text('Add a poster and generate screenshots first'),
      findsOneWidget,
    );

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Paste from URL'));
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    expect(
      find.text('Add a poster and generate screenshots first'),
      findsNothing,
      reason: 'the poster the editor wrote completes the pair',
    );
    expect(find.byType(LinearProgressIndicator), findsWidgets);

    directory.deleteSync(recursive: true);
  });

  // The other half of the same notice: removing the poster takes its record
  // away, so the pair is incomplete again and the section goes back to saying
  // what has to happen first.
  testWidgets('removing the poster hides the hoster list again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    // The box shows a file that is on disk, so the Remove button is there only
    // when the poster file is.
    File(p.join(directory.path, '_rp_poster.jpg'))
        .writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);

    await tester.runAsync(
      () => ImagesStore().save(
        directory.path,
        ImagesManifest(
          images: [
            ImageRecord(
              item: null,
              kind: ImageKind.poster,
              file: '_rp_poster.jpg',
              urls: const {},
            ),
            ImageRecord(
              item: 'movie.mp4',
              kind: ImageKind.screenshot,
              file: 'images/movie.mp4/_rp_screenshot01.jpg',
              urls: const {},
            ),
          ],
        ),
      ),
    );

    final release = testRelease(directory.path, fields: FieldValues());

    await openEditor(tester, release);

    expect(find.byType(LinearProgressIndicator), findsWidgets);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Remove image'));
      await Future.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });

    expect(
      find.text('Add a poster and generate screenshots first'),
      findsOneWidget,
      reason: 'the release no longer has the poster the pair waits for',
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);

    directory.deleteSync(recursive: true);
  });

  // Most videos are 16:9, so the boxes that show a frame are 16:9 too and the
  // frame is not cropped. The height comes from the width the column gives the
  // box, so the test checks the rendered size rather than a fixed number.
  //
  // The two boxes are in two columns, so they line up only when the label rows
  // above them are the same height. A row sizes itself to its tallest child,
  // and an icon button is taller than a label, so the box with buttons started
  // lower than the one without them.
  testWidgets(
    'the poster and thumbnail boxes are 16:9 and start at the same height',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      final release = testRelease('/tmp/x', fields: FieldValues());

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ReleaseStore>(create: (_) => ReleaseStore()),
            ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),
            Provider<ImagesStore>(create: (_) => ImagesStore()),
            ...messageProviders(),
            ...stashProviders(),
            ...draftProviders(),
            ...torrentProviders(),
            Provider<Uptooda>(create: (_) => Uptooda(runner: testRunner())),
            Provider<Ffprobe>(create: (_) => Ffprobe(runner: testRunner())),
            Provider<Ffmpeg>(create: (_) => Ffmpeg(runner: testRunner())),
            Provider<Mtn>(create: (_) => Mtn(runner: testRunner())),
            ...imageGeneratorProviders(),
            Provider<ImageDownloader>(
              create: (_) => ImageDownloader(client: HttpClient()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ReleaseEditor(release: release, tabId: 'tab-1'),
            ),
          ),
        ),
      );

      final boxes = find.byType(AspectRatio);
      expect(
        boxes,
        findsNWidgets(2),
        reason: 'the poster box and the thumbnail box',
      );

      final rects = <Rect>[];

      for (final box in tester.widgetList<AspectRatio>(boxes)) {
        expect(box.aspectRatio, 16 / 9);
        rects.add(tester.getRect(find.byWidget(box)));
      }

      for (final rect in rects) {
        expect(rect.height, closeTo(rect.width * 9 / 16, 0.5));
      }

      expect(
        rects[0].top,
        rects[1].top,
        reason: 'the two columns start at the same height',
      );
    },
  );

  // The scene link row is the first row of the left column, under the poster
  // box, because the values a fetch gives are what the form is filled with.
  testWidgets('the scene row is the first row of the left column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await openEditor(tester, testRelease('/tmp/x'));

    final poster = tester.getRect(find.byType(AspectRatio).first);
    final row = tester.getRect(find.byKey(const ValueKey('stashSection')));
    final columnWidth = tester
        .getRect(find.byKey(const ValueKey('videoTitle')))
        .width;

    expect(
      row.width,
      closeTo(columnWidth, 0.5),
      reason: 'the width of one form column',
    );

    // Below the poster box and above the first field of the column.
    expect(row.left, closeTo(poster.left, 0.5));
    expect(row.top, greaterThan(poster.bottom));
    expect(
      row.top,
      lessThan(tester.getRect(find.byKey(const ValueKey('videoTitle'))).top),
    );
  });

  // The sections are the width of one form column, and they are the columns
  // after the form when there is room for them: the Screenshots section, and
  // the Upload section with the Message section (`ai/doc.md` §2,
  // `ai/upload_images.md`, `ai/description_template.md`). A field is as wide as
  // the column it is in, so a field says what a column is.
  testWidgets(
    'the sections are the columns after the form when there is room for four',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testRelease('/tmp/x'));

      final columnWidth = tester
          .getRect(find.byKey(const ValueKey('videoTitle')))
          .width;

      final screenshots = tester.getRect(
        find.byKey(const ValueKey('screenshotsSection')),
      );
      final upload = tester.getRect(
        find.byKey(const ValueKey('uploadSection')),
      );
      final message = tester.getRect(
        find.byKey(const ValueKey('messageSection')),
      );

      expect(
        screenshots.width,
        closeTo(columnWidth, 0.5),
        reason: 'the width of one form column',
      );
      expect(upload.width, closeTo(columnWidth, 0.5));
      expect(message.width, closeTo(columnWidth, 0.5));

      // To the right of both form columns, each section in its own column.
      final rightColumn = tester.getRect(
        find.byKey(const ValueKey('videoQuality')),
      );
      expect(screenshots.left, greaterThan(rightColumn.right));
      expect(upload.left, greaterThan(screenshots.right));

      // The Message section is in that fourth column, below the Upload section.
      expect(message.left, closeTo(upload.left, 0.5));
      expect(message.top, greaterThan(upload.bottom));
    },
  );

  // When only the form's own columns fit, the sections are still one column
  // wide, but they are under the form rather than beside it.
  testWidgets(
    'the sections are below the form when only the form columns fit',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testRelease('/tmp/x'));

      final left = tester.getRect(find.byKey(const ValueKey('videoTitle')));

      // Two form columns, so one of them is half the width.
      expect(
        tester.getRect(find.byKey(const ValueKey('videoQuality'))).width,
        closeTo(left.width, 0.5),
      );

      final screenshots = tester.getRect(
        find.byKey(const ValueKey('screenshotsSection')),
      );
      final upload = tester.getRect(
        find.byKey(const ValueKey('uploadSection')),
      );

      expect(screenshots.width, closeTo(left.width, 0.5));
      expect(upload.width, closeTo(left.width, 0.5));

      // Below the form, at the left edge.
      expect(screenshots.top, greaterThan(left.bottom));
      expect(screenshots.left, closeTo(left.left, 0.5));
      expect(upload.top, greaterThan(screenshots.bottom));
    },
  );

  // The same shape for a video pack: its section is the third column and the
  // Upload section with the Message section the fourth. A table is the whole
  // width for the other types, but the page is the same for the two video
  // types, so this one is placed at a column width too (`ai/video_pack.md` §5).
  testWidgets(
    'a video pack is the columns after the form when there is room for four',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testVideoPackRelease('/tmp/x'));

      final columnWidth = tester
          .getRect(find.byKey(const ValueKey('subsiteAndSite')))
          .width;

      final videos = tester.getRect(
        find.byKey(const ValueKey('videoPackSection')),
      );
      final upload = tester.getRect(
        find.byKey(const ValueKey('uploadSection')),
      );
      final message = tester.getRect(
        find.byKey(const ValueKey('messageSection')),
      );

      expect(
        videos.width,
        closeTo(columnWidth, 0.5),
        reason: 'the width of one form column',
      );
      expect(upload.width, closeTo(columnWidth, 0.5));
      expect(message.width, closeTo(columnWidth, 0.5));

      // To the right of both form columns, each section in its own column.
      final rightColumn = tester.getRect(
        find.byKey(const ValueKey('videoCount')),
      );
      expect(videos.left, greaterThan(rightColumn.right));
      expect(upload.left, greaterThan(videos.right));

      // The Message section is in that fourth column, below the Upload section.
      expect(message.left, closeTo(upload.left, 0.5));
      expect(message.top, greaterThan(upload.bottom));
    },
  );

  // And the same fallback: when only the form's own columns fit, a video pack's
  // sections are still one column wide, but under the form rather than beside
  // it, and the Message section is the whole width below everything.
  testWidgets('a video pack is below the form when only the form columns fit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;

    await openEditor(tester, testVideoPackRelease('/tmp/x'));

    final left = tester.getRect(find.byKey(const ValueKey('subsiteAndSite')));

    // Two form columns, so one of them is half the width.
    expect(
      tester.getRect(find.byKey(const ValueKey('videoCount'))).width,
      closeTo(left.width, 0.5),
    );

    final videos = tester.getRect(
      find.byKey(const ValueKey('videoPackSection')),
    );
    final upload = tester.getRect(find.byKey(const ValueKey('uploadSection')));
    final message = tester.getRect(
      find.byKey(const ValueKey('messageSection')),
    );

    expect(videos.width, closeTo(left.width, 0.5));
    expect(upload.width, closeTo(left.width, 0.5));

    // Below the form, at the left edge.
    expect(videos.top, greaterThan(left.bottom));
    expect(videos.left, closeTo(left.left, 0.5));
    expect(upload.top, greaterThan(videos.bottom));

    // The Message section is not a column here, so it is the whole width.
    expect(message.width, greaterThan(videos.width));
    expect(message.left, closeTo(left.left, 0.5));
  });
  // The photoset pack's first column is the fields it has and the sections that
  // need a column's width, and its second column is the Photosets block at the
  // most the width this feature gives it; the photo area is what the row has
  // left, and inside that space it fits its own columns (`ai/picking.md` §7).
  // The width the page gives is read from the field, and the padding from where
  // the first column starts, so the numbers the test compares are the constants
  // rather than what they work out to here.
  testWidgets(
    'a photoset pack puts its block in the second column and its photos in the space left',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testPackRelease('/tmp/x'));

      final field = tester.getRect(find.byKey(const ValueKey('siteOrJournal')));
      final columnWidth = field.width;

      // The page is the window with the padding the editor puts around it, and
      // the padding is where the first column starts.
      final pageWidth =
          tester.getSize(find.byType(SingleChildScrollView)).width -
          2 * field.left;

      // A page column is wider than the block's cap here, so the block is drawn
      // at the cap, and the width it does not use is the photo area's rather
      // than empty space beside it.
      final block = tester.getRect(find.byKey(const ValueKey('photosetBlock')));
      expect(block.width, closeTo(photosetBlockMaxWidth, 0.5));
      expect(block.left, closeTo(field.right + columnGap, 0.5));

      // The block is a section, so it starts at the top of its column the way a
      // titled column does.
      final title = tester.getRect(find.byKey(const ValueKey('columnTitle')));
      expect(block.top, closeTo(title.top, 0.5));

      // The rows the block draws are the ones the editor built, because they are
      // form rows: the path the user picked and the counts the scan took from it.
      // For every other type these are rows of the second block of the form.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('photosetBlock')),
          matching: find.byKey(const ValueKey('source')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('photosetBlock')),
          matching: find.byKey(const ValueKey('photosetCount')),
        ),
        findsOneWidget,
      );

      // The word is what the block is called and what one of its rows is called, so
      // it is said twice.
      expect(find.text('Photosets'), findsNWidgets(2));

      // The sections that need a column's width stay below the fields, in the
      // first column, because the block's column is too narrow for their rows.
      final upload = tester.getRect(
        find.byKey(const ValueKey('uploadSection')),
      );
      final message = tester.getRect(
        find.byKey(const ValueKey('messageSection')),
      );

      expect(upload.width, closeTo(columnWidth, 0.5));
      expect(upload.left, closeTo(field.left, 0.5));
      expect(upload.top, greaterThan(field.bottom));

      expect(message.width, closeTo(columnWidth, 0.5));
      expect(message.left, closeTo(field.left, 0.5));
      expect(message.top, greaterThan(upload.bottom));

      // What the row has left is the area, and the three widths with the two
      // gaps make the page: nothing is left over at the right, and the area
      // starts at the top of the row like the columns beside it.
      final gallery = tester.getRect(
        find.byKey(const ValueKey('photosetGallery')),
      );

      expect(
        columnWidth + block.width + gallery.width + 2 * columnGap,
        closeTo(pageWidth, 0.5),
      );
      expect(gallery.left, closeTo(block.right + columnGap, 0.5));
      expect(gallery.top, closeTo(block.top, 0.5));

      // The space it was given holds more than one column of the grid, which is
      // what puts it beside the row rather than below it.
      expect(
        photoColumnCount(width: gallery.width, min: photosetColumnWidth),
        greaterThan(1),
      );

      // Said once, because it is the title of the area rather than of a set.
      expect(find.text('Screenshots'), findsOneWidget);
    },
  );

  // The same rule at a width where the row cannot hold one column of the grid:
  // the area is below the row at the whole width, and the space beside the
  // capped block is empty, which is what a strict maximum costs at a narrow
  // window (`ai/picking.md` §7).
  testWidgets(
    'a photoset pack shows its photos below the row when the row has no room for a column',
    (tester) async {
      tester.view.physicalSize = const Size(950, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testPackRelease('/tmp/x'));

      final field = tester.getRect(find.byKey(const ValueKey('siteOrJournal')));
      final pageWidth =
          tester.getSize(find.byType(SingleChildScrollView)).width -
          2 * field.left;

      // There is room for two columns, so the block is still the second one, at
      // its cap rather than at the page's column width.
      expect(field.width, greaterThan(photosetBlockMaxWidth));

      final block = tester.getRect(find.byKey(const ValueKey('photosetBlock')));
      expect(block.width, closeTo(photosetBlockMaxWidth, 0.5));
      expect(block.left, closeTo(field.right + columnGap, 0.5));

      // What the row has left is less than one column of the grid, so the area
      // is not beside it: it is below the whole row, at the whole width, and
      // the space beside the block is left empty.
      expect(
        pageWidth - field.width - block.width - 2 * columnGap,
        lessThan(photosetColumnWidth),
      );

      final gallery = tester.getRect(
        find.byKey(const ValueKey('photosetGallery')),
      );

      expect(gallery.width, closeTo(pageWidth, 0.5));
      expect(gallery.left, closeTo(field.left, 0.5));
      expect(gallery.top, greaterThan(block.bottom));
    },
  );

  // And the same at a width with room for one column only: everything is
  // stacked, and the block is capped there too, at the left of the space it is
  // given (`ai/picking.md` §7).
  testWidgets(
    'a photoset pack shows its photos below the form when only one column fits',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testPackRelease('/tmp/x'));

      final field = tester.getRect(find.byKey(const ValueKey('siteOrJournal')));

      // One column, so the field is the whole width, and the block is below the
      // fields at its cap rather than at that width.
      expect(field.width, greaterThan(photosetBlockMaxWidth));

      final block = tester.getRect(find.byKey(const ValueKey('photosetBlock')));
      expect(block.width, closeTo(photosetBlockMaxWidth, 0.5));
      expect(block.left, closeTo(field.left, 0.5));
      expect(block.top, greaterThan(field.bottom));

      final upload = tester.getRect(
        find.byKey(const ValueKey('uploadSection')),
      );
      final message = tester.getRect(
        find.byKey(const ValueKey('messageSection')),
      );

      expect(upload.width, closeTo(field.width, 0.5));
      expect(message.width, closeTo(field.width, 0.5));

      // Below everything, at the whole width: the one column the area fits is
      // that width.
      final gallery = tester.getRect(
        find.byKey(const ValueKey('photosetGallery')),
      );

      expect(gallery.width, closeTo(field.width, 0.5));
      expect(gallery.left, closeTo(field.left, 0.5));
      expect(gallery.top, greaterThan(message.bottom));
    },
  );

  // The Upload draft section is the part of the Message section that sends what
  // it shows, so it follows it in whichever place that one is: the fourth column
  // when there is room for four (`ai/uploading_draft.md` §4).
  testWidgets('the Upload draft section is below the Message section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await openEditor(tester, testRelease('/tmp/x'));

    final message = tester.getRect(
      find.byKey(const ValueKey('messageSection')),
    );
    final draft = tester.getRect(find.byKey(const ValueKey('draftSection')));

    // The same column, so the same width and the same left edge.
    expect(draft.width, closeTo(message.width, 0.5));
    expect(draft.left, closeTo(message.left, 0.5));
    expect(draft.top, greaterThan(message.bottom));
  });

  // And the same in the layout where the Message section is not a column: the
  // section that sends what it shows is still below it, at the same width.
  testWidgets(
    'the Upload draft section is below the Message section when that is the whole width',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testRelease('/tmp/x'));

      final message = tester.getRect(
        find.byKey(const ValueKey('messageSection')),
      );
      final draft = tester.getRect(find.byKey(const ValueKey('draftSection')));

      expect(draft.width, closeTo(message.width, 0.5));
      expect(draft.left, closeTo(message.left, 0.5));
      expect(draft.top, greaterThan(message.bottom));
    },
  );

  // The Torrent section is the last thing in the form's second column, in every
  // layout (`ai/torrents.md`): it belongs to the column that lists the release's
  // files rather than to the columns after the form. A field is as wide as the
  // column it is in, so the last field of the column says what the column is,
  // and the gap before the section is the one between sections rather than the
  // one between the rows of a column.
  testWidgets('the torrent section is at the end of the second form column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await openEditor(tester, testRelease('/tmp/x'));

    final lastField = tester.getRect(find.byKey(const ValueKey('audioStream')));
    final section = tester.getRect(
      find.byKey(const ValueKey('torrentSection')),
    );

    expect(
      section.width,
      closeTo(lastField.width, 0.5),
      reason: 'the width of the column it is in',
    );
    expect(section.left, closeTo(lastField.left, 0.5));

    // Below the rows of that column, with the gap between sections.
    expect(section.top - lastField.bottom, closeTo(24, 0.5));

    // It is not a column of its own: the section columns are still to its right.
    final screenshots = tester.getRect(
      find.byKey(const ValueKey('screenshotsSection')),
    );
    expect(section.right, lessThan(screenshots.left));
  });

  // The same when the page is narrow enough that the form is one column: the
  // section is at the end of that column, not below the form.
  testWidgets(
    'the torrent section is at the end of the column when the form is one '
    'column',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testRelease('/tmp/x'));

      final lastField = tester.getRect(
        find.byKey(const ValueKey('audioStream')),
      );
      final section = tester.getRect(
        find.byKey(const ValueKey('torrentSection')),
      );

      expect(section.width, closeTo(lastField.width, 0.5));
      expect(section.left, closeTo(lastField.left, 0.5));
      expect(section.top - lastField.bottom, closeTo(24, 0.5));
    },
  );

  // The same for a video pack: its second column is the folder the user picked
  // and the three values the scan counted, and the section is at the end of
  // that column rather than one of the columns after the form.
  testWidgets('the torrent section is at the end of a video pack column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await openEditor(tester, testVideoPackRelease('/tmp/x'));

    final lastField = tester.getRect(
      find.byKey(const ValueKey('videoFormats')),
    );
    final section = tester.getRect(
      find.byKey(const ValueKey('torrentSection')),
    );

    expect(
      section.width,
      closeTo(lastField.width, 0.5),
      reason: 'the width of the column it is in',
    );
    expect(section.left, closeTo(lastField.left, 0.5));
    expect(section.top - lastField.bottom, closeTo(24, 0.5));

    // It is not a column of its own: the video pack's section is still to its
    // right.
    final videos = tester.getRect(
      find.byKey(const ValueKey('videoPackSection')),
    );
    expect(section.right, lessThan(videos.left));
  });

  // The tracker and release-type badges follow the name, because they say what
  // the name is for, rather than being pushed to the right edge of the heading.
  testWidgets('the badges come after the release name', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await openEditor(tester, testRelease('/tmp/x'));

    // A badge is the bordered box, not its label, so the gap is measured to the
    // box.
    Rect badge(String text) => tester.getRect(
      find.ancestor(of: find.text(text), matching: find.byType(Container)),
    );

    final name = tester.getRect(find.text('x'));
    final tracker = badge('PornoLab');
    final type = badge('Single video');

    // Right after the name, at the gap, not at the end of the row.
    expect(tracker.left, closeTo(name.right + 12, 0.5));
    expect(type.left, closeTo(tracker.right + 8, 0.5));

    // The row is not filled: what is left after the badges is far more than the
    // gap before them.
    expect(2000 - type.right, greaterThan(100));
  });

  // The heading is the title of the page rather than of a column, so the gap
  // below it is the one a section title has before its content, not the smaller
  // one a form column has.
  testWidgets('the gap below the release name is the section one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await openEditor(tester, testRelease('/tmp/x'));

    // The gap is below the heading row rather than below the name text: the
    // badges are taller than the text, so the row is as tall as they are. The
    // first thing below it is the title of the first column.
    final heading = tester.getRect(
      find.ancestor(of: find.text('x'), matching: find.byType(Row)),
    );
    final title = tester.getRect(
      find.byKey(const ValueKey('columnTitle')).at(0),
    );

    expect(title.top - heading.bottom, 12);
  });

  // Each column of the form is titled by what it holds, with the same title
  // style the sections use: at the top of the column and as wide as it. A
  // column has no action, so it is the text on its own.
  testWidgets('the form columns are titled by what they hold', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await openEditor(tester, testRelease('/tmp/x'));

    final titles = find.byKey(const ValueKey('columnTitle'));
    expect(titles, findsNWidgets(2));

    expect(tester.widget<Text>(titles.at(0)).data, 'Release Info');
    expect(tester.widget<Text>(titles.at(1)).data, 'Video');

    final leftTitle = tester.getRect(titles.at(0));
    final rightTitle = tester.getRect(titles.at(1));
    final leftField = tester.getRect(find.byKey(const ValueKey('videoTitle')));
    final rightField = tester.getRect(
      find.byKey(const ValueKey('videoQuality')),
    );

    expect(
      leftTitle.width,
      closeTo(leftField.width, 0.5),
      reason: 'the width of its column',
    );
    expect(leftTitle.left, closeTo(leftField.left, 0.5));
    expect(
      leftTitle.top,
      lessThan(leftField.top),
      reason: 'above the first field of the column',
    );

    expect(rightTitle.width, closeTo(rightField.width, 0.5));
    expect(rightTitle.left, closeTo(rightField.left, 0.5));
    expect(rightTitle.top, lessThan(rightField.top));
  });

  // The gap after a column title is smaller than the one a section has, because
  // the first row of these columns is an image box whose label row has its own
  // space above its label.
  testWidgets('the gap after a column title is the small one', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await openEditor(tester, testRelease('/tmp/x'));

    // The label row is the top of the image box, so the gap is measured to it.
    // It is the only ancestor of the label that is a box with a height, which
    // is what tells it from the box that gives the column its width.
    double gap(int index, String label) {
      final title = tester.getRect(
        find.byKey(const ValueKey('columnTitle')).at(index),
      );
      final labelRow = tester.getRect(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (widget) => widget is SizedBox && widget.height != null,
          ),
        ),
      );

      return labelRow.top - title.bottom;
    }

    expect(gap(0, 'Poster image'), 4);
    expect(gap(1, 'Video thumbnail'), 4);
  });

  // The right column is what the scan or the probe read, so its title names
  // what that type holds. A single video's is one video, so it names a video; a
  // video pack's is the folder the user picked and the counts taken from it, so
  // it names the folder. The image folder type has no column of fields, so the
  // column that is the poster box and nothing else has no title.
  testWidgets('a single video titles its right column Video', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    expect(await titlesOf(tester, testRelease('/tmp/x')), [
      'Release Info',
      'Video',
    ]);
  });

  // The pack has one titled column: the form's fields and its scan values are
  // all in the first one, and the columns after it belong to the Screenshots
  // section, which titles itself (`ai/picking.md` §7).
  testWidgets('a photoset pack titles only its first column', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    expect(await titlesOf(tester, testPackRelease('/tmp/x')), ['Release Info']);
  });

  testWidgets('a video pack titles its right column Source folder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    expect(await titlesOf(tester, testVideoPackRelease('/tmp/x')), [
      'Release Info',
      'Source folder',
    ]);
  });

  testWidgets('a single photoset titles its right column Photosets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    expect(await titlesOf(tester, testSinglePhotosetRelease('/tmp/x')), [
      'Release Info',
      'Photosets',
    ]);
  });

  testWidgets(
    'an image folder titles its right column and not its poster column',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      expect(await titlesOf(tester, testImageFolderRelease('/tmp/x')), [
        'Images',
      ]);
    },
  );

  test('the probe is called with the path in the field', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final file = File(p.join(directory.path, 'movie.mp4'));
    file.writeAsStringSync('not a real video file');

    final tabManager = TabManager();
    final release = testRelease(directory.path, fields: FieldValues());
    final tabId = tabManager.addReleaseEditor(release);

    final probe = _FakeProbe(
      const MediaInfo(
        fileSize: '',
        duration: '00:01:23',
        durationSeconds: 83.45,
        videoType: '2160p',
        videoFormat: 'MP4',
        videoStream: 'AVC',
        audioStream: 'AAC LC',
      ),
    );

    final controller = ReleaseEditorController(
      release: release,
      store: ReleaseStore(),
      tabManager: tabManager,
      ffprobe: probe,
      ffmpeg: _FakeFfmpeg(),
      downloader: _FakeDownloader(
        DownloadSuccess('', ContentType('image', 'jpeg')),
      ),
      images: ImagesStore(),
      tabId: tabId,
    );

    final empty = await controller.probeMovieFile();

    expect(
      (empty as MediaProbeFailure).kind,
      MediaProbeFailureKind.fileNotFound,
      reason: 'an empty path is not a file',
    );

    controller.setSource(file.path);

    final result = await controller.probeMovieFile();

    expect(result, isA<MediaProbeSuccess>());
    expect((result as MediaProbeSuccess).info.duration, '00:01:23');
    expect(probe.probedPath, file.path);

    controller.setSource(p.join(directory.path, 'missing.mp4'));

    final missing = await controller.probeMovieFile();

    expect(missing, isA<MediaProbeFailure>());
    expect(
      (missing as MediaProbeFailure).kind,
      MediaProbeFailureKind.fileNotFound,
    );

    directory.deleteSync(recursive: true);
  });

  // The thumbnail is not stored in release.json: its path comes from the
  // release directory and the item path, and the frame is written at half the
  // duration through the same call the Screenshots section uses, so it is the
  // source resolution.
  test('the thumbnail is written under images/<item path>', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final file = File(p.join(directory.path, 'movie.mp4'));
    file.writeAsStringSync('not a real video file');

    final tabManager = TabManager();
    final release = testRelease(directory.path, source: '');
    final tabId = tabManager.addReleaseEditor(release);

    final ffmpeg = _FakeFfmpeg();
    final controller = ReleaseEditorController(
      release: release,
      store: ReleaseStore(),
      tabManager: tabManager,
      ffprobe: _FakeProbe(
        const MediaInfo(
          fileSize: '',
          duration: '',
          durationSeconds: null,
          videoType: '',
          videoFormat: '',
          videoStream: '',
          audioStream: '',
        ),
      ),
      ffmpeg: ffmpeg,
      downloader: _FakeDownloader(
        DownloadSuccess('', ContentType('image', 'jpeg')),
      ),
      images: ImagesStore(),
      tabId: tabId,
    );

    expect(controller.thumbnailPath(), isNull, reason: 'no video is set');

    expect(
      (await controller.generateThumbnail(null) as ThumbnailFailure).kind,
      ThumbnailFailureKind.fileNotFound,
      reason: 'an empty path is not a file',
    );

    controller.setSource(file.path);

    expect(
      controller.thumbnailPath(),
      p.join(directory.path, 'images/movie.mp4/_rp_thumbnail.jpg'),
    );

    final result = await controller.generateThumbnail(83.45);

    expect(result, isA<ThumbnailSuccess>());

    final frame = ffmpeg.screenshotCalls.first;
    expect(frame.outputPath, controller.thumbnailPath());
    expect(frame.seekSeconds, 41.725, reason: 'the middle of the video');

    // A file ffprobe did not report a duration for is read from the start.
    await controller.generateThumbnail(null);
    expect(ffmpeg.screenshotCalls.last.seekSeconds, 0);

    directory.deleteSync(recursive: true);
  });

  // The poster's path comes from its record, because two posters cannot share
  // one derived name (`ai/release_structure.md` §4). The first poster record is
  // the primary one, and a poster that has no record yet gets one at the
  // release directory root, where the first poster of a release has always
  // been. The file is written with neither dimension larger than 1200 px, and
  // that file is what the box shows — there is no second, smaller copy of it.
  test('the poster is written at the path its record gives', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final tabManager = TabManager();
    final release = testRelease(directory.path, fields: FieldValues());
    final tabId = tabManager.addReleaseEditor(release);

    final ffmpeg = _FakeFfmpeg();
    final images = ImagesStore();
    final controller = ReleaseEditorController(
      release: release,
      store: ReleaseStore(),
      tabManager: tabManager,
      ffprobe: _FakeProbe(
        const MediaInfo(
          fileSize: '',
          duration: '',
          durationSeconds: null,
          videoType: '',
          videoFormat: '',
          videoStream: '',
          audioStream: '',
        ),
      ),
      ffmpeg: ffmpeg,
      downloader: _FakeDownloader(
        DownloadSuccess('', ContentType('image', 'jpeg')),
      ),
      images: images,
      tabId: tabId,
    );

    expect(
      controller.posterPath(),
      isNull,
      reason: 'no poster is recorded yet',
    );

    final missing = await controller.setPoster(
      p.join(directory.path, 'missing.jpg'),
    );
    expect((missing as PosterFailure).kind, PosterFailureKind.fileNotFound);

    final png = File(p.join(directory.path, 'poster.png'));
    png.writeAsStringSync('not a real image');

    final wrongFormat = await controller.setPoster(png.path);
    expect((wrongFormat as PosterFailure).kind, PosterFailureKind.wrongFormat);
    expect(
      ffmpeg.resizeCalls,
      isEmpty,
      reason: 'a rejected file is not resized',
    );
    expect(images.loadSync(directory.path).of(ImageKind.poster), isEmpty);

    // The source is a real image, so ffmpeg does the work: the stored file at
    // most 1200 px on the bigger dimension, and nothing else.
    final poster = File(p.join(directory.path, 'poster.jpg'));
    poster.writeAsStringSync('not a real image');

    expect(await controller.setPoster(poster.path), isA<PosterSuccess>());

    // Writing a poster records it, so the Upload section has an image to send.
    expect(
      images.loadSync(directory.path).of(ImageKind.poster).single.item,
      isNull,
    );

    expect(ffmpeg.resizeCalls, [
      (
        inputPath: poster.path,
        outputPath: p.join(directory.path, '_rp_poster.jpg'),
        maxSize: 1200,
      ),
    ]);

    expect(controller.posterOnDisk(), controller.posterPath());

    expect(await controller.removePoster(), isTrue);
    expect(controller.posterOnDisk(), isNull);
    expect(images.loadSync(directory.path).of(ImageKind.poster), isEmpty);

    directory.deleteSync(recursive: true);
  });

  // A pasted link is processed exactly like a file the user picked: the same
  // format check, the same resize. The download itself goes to a temporary
  // file, because ffmpeg reads files, and is removed afterwards.
  test('a pasted link is processed like a picked file', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final tabManager = TabManager();
    final release = testRelease(directory.path, fields: FieldValues());
    final tabId = tabManager.addReleaseEditor(release);

    final ffmpeg = _FakeFfmpeg();
    final downloader = _FakeDownloader(
      DownloadSuccess('', ContentType('image', 'jpeg')),
    );
    final controller = ReleaseEditorController(
      release: release,
      store: ReleaseStore(),
      tabManager: tabManager,
      ffprobe: _FakeProbe(
        const MediaInfo(
          fileSize: '',
          duration: '',
          durationSeconds: null,
          videoType: '',
          videoFormat: '',
          videoStream: '',
          audioStream: '',
        ),
      ),
      ffmpeg: ffmpeg,
      downloader: downloader,
      images: ImagesStore(),
      tabId: tabId,
    );

    expect(
      (await controller.setPosterFromUrl('not a link') as PosterFailure).kind,
      PosterFailureKind.invalidUrl,
    );

    expect(
      (await controller.setPosterFromUrl(
        'ftp://example.com/poster.jpg',
      ) as PosterFailure).kind,
      PosterFailureKind.invalidUrl,
      reason: 'only http and https',
    );

    expect(
      (await controller.setPosterFromUrl(
        'https://example.com/poster.png',
      ) as PosterFailure).kind,
      PosterFailureKind.wrongFormat,
      reason: 'a link that names a format is judged from its path, not from its query',
    );

    expect(
      downloader.requestedUrl,
      isNull,
      reason: 'a link that is rejected is not downloaded',
    );

    downloader.result = const DownloadFailure(DownloadFailureKind.failed);

    expect(
      (await controller.setPosterFromUrl(
        'https://example.com/poster.jpg',
      ) as PosterFailure).kind,
      PosterFailureKind.downloadFailed,
    );

    // The same path as a picked file: the poster at most 1200 px, and the
    // temporary download is not left behind.
    downloader.result = DownloadSuccess('', ContentType('image', 'jpeg'));

    expect(
      await controller.setPosterFromUrl(
        'https://example.com/images/poster.jpg?width=800',
      ),
      isA<PosterSuccess>(),
    );

    expect(
      downloader.requestedUrl,
      Uri.parse('https://example.com/images/poster.jpg?width=800'),
    );

    expect(ffmpeg.resizeCalls, [
      (
        inputPath: downloader.destinationPath,
        outputPath: controller.posterPath(),
        maxSize: 1200,
      ),
    ]);

    expect(
      File(downloader.destinationPath!).existsSync(),
      isFalse,
      reason: 'the download is not part of the release',
    );

    directory.deleteSync(recursive: true);
  });

  // A link that names no format is judged by what its response says. A StashDB
  // image is `stashdb.org/images/<uuid>`, which is such a link.
  test('a link that names no format is judged by its response', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final tabManager = TabManager();
    final release = testRelease(directory.path, fields: FieldValues());
    final tabId = tabManager.addReleaseEditor(release);

    final ffmpeg = _FakeFfmpeg();
    final downloader = _FakeDownloader(
      DownloadSuccess('', ContentType('image', 'jpeg')),
    );
    final controller = ReleaseEditorController(
      release: release,
      store: ReleaseStore(),
      tabManager: tabManager,
      ffprobe: _FakeProbe(
        const MediaInfo(
          fileSize: '',
          duration: '',
          durationSeconds: null,
          videoType: '',
          videoFormat: '',
          videoStream: '',
          audioStream: '',
        ),
      ),
      ffmpeg: ffmpeg,
      downloader: downloader,
      images: ImagesStore(),
      tabId: tabId,
    );

    const link =
        'https://stashdb.org/images/0f9d6b7c-8a2e-4c1b-9d3f-6e5a4b3c2d1e';

    expect(await controller.setPosterFromUrl(link), isA<PosterSuccess>());

    expect(
      p.extension(downloader.destinationPath!),
      isEmpty,
      reason: 'the name of the temporary file carries no format',
    );

    // The same link answered with something the app does not accept is
    // rejected, even though its path would have passed.
    downloader.result = DownloadSuccess('', ContentType('image', 'png'));

    expect(
      (await controller.setPosterFromUrl(link) as PosterFailure).kind,
      PosterFailureKind.wrongFormat,
    );

    // A response that says nothing is rejected too.
    downloader.result = DownloadSuccess('', null);

    expect(
      (await controller.setPosterFromUrl(link) as PosterFailure).kind,
      PosterFailureKind.wrongFormat,
    );

    expect(
      ffmpeg.resizeCalls.length,
      1,
      reason: 'only the accepted link reached ffmpeg',
    );

    directory.deleteSync(recursive: true);
  });

  // The defaults belong to the field list, not to the values, so a new release
  // gets them when the store creates it and a loaded one shows what its file
  // contains.
  test('a new release starts with the default video quality', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final release = await ReleaseStore().create(
      savePath: directory.path,
      name: 'x',
      tracker: Tracker.pornolab,
      releaseType: ReleaseType.singleVideo,
      torrentPrivate: true,
      includeAppSignature: true,
    );

    expect(release.fields.value('videoQuality'), 'SiteRip');

    // A loaded release shows what its manifest contains, not the default.
    expect(
      FieldValues.fromJson({'videoQuality': 'BDRip'}).value('videoQuality'),
      'BDRip',
    );
    expect(FieldValues.fromJson({}).value('videoQuality'), '');

    directory.deleteSync(recursive: true);
  });

  // Nothing is picked when a release is created, so there is no source and no
  // item: an item is a real file on disk (`ai/release_structure.md` §2).
  test('a new release has no source and no item', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final release = await ReleaseStore().create(
      savePath: directory.path,
      name: 'x',
      tracker: Tracker.pornolab,
      releaseType: ReleaseType.singleVideo,
      torrentPrivate: true,
      includeAppSignature: true,
    );

    expect(release.source, '');
    expect(release.items, isEmpty);

    directory.deleteSync(recursive: true);
  });

  // Picking a file records what was picked and the item it is. A picked file is
  // treated as a directory containing only itself, so the item path is the
  // filename, and that path is the record id the image records link to.
  test('picking a file records the source and the item it is', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final file = File(p.join(directory.path, 'movie.mp4'));
    file.writeAsStringSync('not a real video file');

    final tabManager = TabManager();
    final release = testRelease(directory.path);
    final tabId = tabManager.addReleaseEditor(release);

    final controller = ReleaseEditorController(
      release: release,
      store: ReleaseStore(),
      tabManager: tabManager,
      ffprobe: _FakeProbe(
        const MediaInfo(
          fileSize: '',
          duration: '',
          durationSeconds: null,
          videoType: '',
          videoFormat: '',
          videoStream: '',
          audioStream: '',
        ),
      ),
      ffmpeg: _FakeFfmpeg(),
      downloader: _FakeDownloader(
        DownloadSuccess('', ContentType('image', 'jpeg')),
      ),
      images: ImagesStore(),
      tabId: tabId,
    );

    expect(controller.setSource(file.path), isTrue);
    expect(release.source, file.path);
    expect(release.items.single.path, 'movie.mp4');
    expect(release.items.single.type, itemTypeVideo);
    expect(release.absolutePath(release.items.single), file.path);
    expect(tabManager.tabs.single.hasUnsavedChanges, isTrue);

    // The same path again is not a change, so it does not mark the tab dirty
    // again.
    expect(controller.setSource(file.path), isFalse);

    directory.deleteSync(recursive: true);
  });

  // The shape the block has is part of `release.json`, so it is part of the save
  // and marks the tab dirty the same way a field does.
  test(
    'the block shape marks the tab dirty, and the same shape again does not',
    () {
      final tabManager = TabManager();
      final release = testVideoPackRelease('/tmp/x');
      final tabId = tabManager.addReleaseEditor(release);

      final controller = ReleaseEditorController(
        release: release,
        store: ReleaseStore(),
        tabManager: tabManager,
        ffprobe: _FakeProbe(
          const MediaInfo(
            fileSize: '',
            duration: '',
            durationSeconds: null,
            videoType: '',
            videoFormat: '',
            videoStream: '',
            audioStream: '',
          ),
        ),
        ffmpeg: _FakeFfmpeg(),
        downloader: _FakeDownloader(
          DownloadSuccess('', ContentType('image', 'jpeg')),
        ),
        images: ImagesStore(),
        tabId: tabId,
      );

      expect(controller.setScreenshotLayout(ScreenshotLayout.byItem), isTrue);
      expect(release.screenshotLayout, ScreenshotLayout.byItem);
      expect(tabManager.tabs.single.hasUnsavedChanges, isTrue);

      expect(controller.setScreenshotLayout(ScreenshotLayout.byItem), isFalse);
    },
  );

  // The signature flag is part of `release.json` for the same reason the block
  // shape is, so it marks the tab dirty the same way a field does.
  test(
    'the signature flag marks the tab dirty, and the same flag again does not',
    () {
      final tabManager = TabManager();
      final release = testVideoPackRelease('/tmp/x');
      final tabId = tabManager.addReleaseEditor(release);

      final controller = ReleaseEditorController(
        release: release,
        store: ReleaseStore(),
        tabManager: tabManager,
        ffprobe: _FakeProbe(
          const MediaInfo(
            fileSize: '',
            duration: '',
            durationSeconds: null,
            videoType: '',
            videoFormat: '',
            videoStream: '',
            audioStream: '',
          ),
        ),
        ffmpeg: _FakeFfmpeg(),
        downloader: _FakeDownloader(
          DownloadSuccess('', ContentType('image', 'jpeg')),
        ),
        images: ImagesStore(),
        tabId: tabId,
      );

      expect(controller.setIncludeAppSignature(false), isTrue);
      expect(release.includeAppSignature, isFalse);
      expect(tabManager.tabs.single.hasUnsavedChanges, isTrue);

      expect(controller.setIncludeAppSignature(false), isFalse);
    },
  );

  // The Private flag is part of `release.json` for the same reason the signature
  // flag is, so it marks the tab dirty the same way a field does. The row is the
  // Torrent section's, so the write is the controller's and the section reports it.
  test(
    'the private flag marks the tab dirty, and the same flag again does not',
    () {
      final tabManager = TabManager();
      final release = testVideoPackRelease('/tmp/x');
      final tabId = tabManager.addReleaseEditor(release);

      final controller = ReleaseEditorController(
        release: release,
        store: ReleaseStore(),
        tabManager: tabManager,
        ffprobe: _FakeProbe(
          const MediaInfo(
            fileSize: '',
            duration: '',
            durationSeconds: null,
            videoType: '',
            videoFormat: '',
            videoStream: '',
            audioStream: '',
          ),
        ),
        ffmpeg: _FakeFfmpeg(),
        downloader: _FakeDownloader(
          DownloadSuccess('', ContentType('image', 'jpeg')),
        ),
        images: ImagesStore(),
        tabId: tabId,
      );

      expect(controller.setTorrentPrivate(false), isTrue);
      expect(release.torrentPrivate, isFalse);
      expect(tabManager.tabs.single.hasUnsavedChanges, isTrue);

      expect(controller.setTorrentPrivate(false), isFalse);
    },
  );

  // A confirmed change is a run that already changed the file the flag describes, so
  // the record has to agree with it at once: the value is written there and then,
  // and the tab is not marked dirty, because there is nothing left to save.
  test(
    'the flag a run changed is written to the manifest and does not mark the '
    'tab dirty',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );

      final store = ReleaseStore();
      final release = await store.create(
        savePath: directory.path,
        name: 'release',
        tracker: Tracker.pornolab,
        releaseType: ReleaseType.singleVideo,
        torrentPrivate: true,
        includeAppSignature: true,
      );

      final tabManager = TabManager();
      final tabId = tabManager.addReleaseEditor(release);

      final controller = ReleaseEditorController(
        release: release,
        store: store,
        tabManager: tabManager,
        ffprobe: _FakeProbe(
          const MediaInfo(
            fileSize: '',
            duration: '',
            durationSeconds: null,
            videoType: '',
            videoFormat: '',
            videoStream: '',
            audioStream: '',
          ),
        ),
        ffmpeg: _FakeFfmpeg(),
        downloader: _FakeDownloader(
          DownloadSuccess('', ContentType('image', 'jpeg')),
        ),
        images: ImagesStore(),
        tabId: tabId,
      );

      await controller.saveTorrentPrivate(false);

      final written = jsonDecode(
        File(p.join(release.directoryPath, 'release.json')).readAsStringSync(),
      ) as Map<String, dynamic>;

      expect(written['torrentPrivate'], isFalse);
      expect(tabManager.tabs.single.hasUnsavedChanges, isFalse);

      directory.deleteSync(recursive: true);
    },
  );

  // A manifest that could not be written is not reported, the same rule as the stamp:
  // the file the run changed is the thing the flag describes, and the next write puts
  // the record right.
  test('a manifest that cannot be written is not reported', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final store = ReleaseStore();
    final release = await store.create(
      savePath: directory.path,
      name: 'release',
      tracker: Tracker.pornolab,
      releaseType: ReleaseType.singleVideo,
      torrentPrivate: true,
      includeAppSignature: true,
    );

    final tabManager = TabManager();
    final tabId = tabManager.addReleaseEditor(release);

    final controller = ReleaseEditorController(
      release: release,
      store: store,
      tabManager: tabManager,
      ffprobe: _FakeProbe(
        const MediaInfo(
          fileSize: '',
          duration: '',
          durationSeconds: null,
          videoType: '',
          videoFormat: '',
          videoStream: '',
          audioStream: '',
        ),
      ),
      ffmpeg: _FakeFfmpeg(),
      downloader: _FakeDownloader(
        DownloadSuccess('', ContentType('image', 'jpeg')),
      ),
      images: ImagesStore(),
      tabId: tabId,
    );

    directory.deleteSync(recursive: true);

    await controller.saveTorrentPrivate(false);

    expect(release.torrentPrivate, isFalse);
    expect(tabManager.tabs.single.hasUnsavedChanges, isFalse);
  });

  // For a picked directory the item is under it, which is what a pack needs. A
  // picked file is treated as a directory containing only itself, so the item
  // is the source.
  test('an item path is relative to the source', () {
    final pickedDirectory = Release(
      name: 'x',
      directoryPath: '/tmp/x',
      tracker: Tracker.pornolab,
      releaseType: ReleaseType.photosetPack,
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

    expect(
      pickedDirectory.absolutePath(pickedDirectory.items.single),
      p.join('/home/user/videos', 'movie.mp4'),
    );

    final pickedFile = testRelease(
      '/tmp/x',
      source: '/home/user/videos/movie.mp4',
    );

    expect(
      pickedFile.absolutePath(pickedFile.items.single),
      '/home/user/videos/movie.mp4',
    );
  });

  // A photoset pack has its own field list, so the form shows those names and
  // none of the video ones. The values the scan counts are read-only, because
  // the user cannot edit what the app fills.
  testWidgets('a photoset pack shows its own fields', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await openEditor(tester, testPackRelease('/tmp/x'));

    for (final name in ['siteOrJournal', 'period', 'genreTags']) {
      expect(fieldOf(tester, name).readOnly, isFalse, reason: name);
    }

    for (final name in [
      'photosetCount',
      'totalPhotoCount',
      'minResolution',
      'maxResolution',
    ]) {
      expect(fieldOf(tester, name).readOnly, isTrue, reason: name);
    }

    // The video field list is not part of a pack form.
    for (final name in ['videoTitle', 'cast', 'videoQuality', 'fileSize']) {
      expect(find.byKey(ValueKey(name)), findsNothing, reason: name);
    }
  });

  // A photoset is not a StashDB scene and a pack has no frames to generate, so
  // the Stash section is not part of its form. The section it does have is the
  // one that lists the sets, but its title is the Screenshots one, because what
  // the pack shows is the picked pictures (`ai/picking.md` §7); the first column
  // has no title of its own, it is titled Release Info. The poster belongs to
  // the release rather than to an item, so a pack still has it.
  testWidgets(
    'a pack form shows the Photosets block and its photo area, not the video sections',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testPackRelease('/tmp/x'));

      expect(find.byKey(const ValueKey('stashSection')), findsNothing);
      expect(find.text('Screenshots'), findsOneWidget);
      expect(find.byKey(const ValueKey('photosetBlock')), findsOneWidget);
      expect(find.byKey(const ValueKey('photosetGallery')), findsOneWidget);
      expect(find.text('Poster image'), findsOneWidget);
    },
  );

  // The other way round: the section list is per release type, not one list for
  // everything.
  testWidgets(
    'a video form shows the Screenshots section and not the Photosets block',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testRelease('/tmp/x'));

      expect(find.text('Screenshots'), findsOneWidget);
      expect(find.byKey(const ValueKey('photosetBlock')), findsNothing);
      expect(find.byKey(const ValueKey('photosetGallery')), findsNothing);
    },
  );

  // The defaults belong to the field list, so a type with no defaults of its
  // own starts with empty values.
  test('a new pack release starts with no values', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final release = await ReleaseStore().create(
      savePath: directory.path,
      name: 'x',
      tracker: Tracker.pornolab,
      releaseType: ReleaseType.photosetPack,
      torrentPrivate: true,
      includeAppSignature: true,
    );

    for (final name in [
      'siteOrJournal',
      'period',
      'genreTags',
      'photosetCount',
    ]) {
      expect(release.fields.value(name), '', reason: name);
    }

    directory.deleteSync(recursive: true);
  });

  // A video pack has its own field list. The names it reuses are the ones the
  // other types already have, so they are editable here as everywhere; the
  // three aggregates are what the scan writes, so they read as text the app
  // wrote (`ai/video_pack.md` §3, §6).
  testWidgets('a video pack shows its own fields', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await openEditor(tester, testVideoPackRelease('/tmp/x'));

    for (final name in [
      'subsiteAndSite',
      'cast',
      'period',
      'genreTags',
      'description',
      'additionalInfo',
    ]) {
      expect(fieldOf(tester, name).readOnly, isFalse, reason: name);
    }

    for (final name in [
      'totalSize',
      'videoCount',
      'videoResolutions',
      'videoFormats',
    ]) {
      expect(fieldOf(tester, name).readOnly, isTrue, reason: name);
    }

    // The names another type has are not part of this form.
    for (final name in ['photosetCount', 'siteOrJournal', 'videoQuality']) {
      expect(find.byKey(ValueKey(name)), findsNothing, reason: name);
    }
  });

  // The column shows the aggregates in the order the field list writes them, and
  // the total is the first of them.
  testWidgets(
    'the total size row is the first row of the Source folder column',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testVideoPackRelease('/tmp/x'));

      final total = tester.getRect(find.byKey(const ValueKey('totalSize')));
      final count = tester.getRect(find.byKey(const ValueKey('videoCount')));

      expect(total.left, closeTo(count.left, 0.5), reason: 'one column');
      expect(total.top, lessThan(count.top));
    },
  );

  // The same rule as the size field's: the model stores the byte count and the
  // row shows the human form as well. Which fields do that is the field list's,
  // so the total is shown the same way as a single video's size.
  testWidgets('the total size row shows the byte count formatted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final release = testVideoPackRelease('/tmp/x');
    release.fields.setValue('totalSize', '10200000000');

    await openEditor(tester, release);

    expect(
      fieldOf(tester, 'totalSize').controller?.text,
      '9.5 GiB (10200000000 bytes)',
    );
    expect(
      release.fields.value('totalSize'),
      '10200000000',
      reason: 'the value that is saved is the byte count, not the text shown',
    );
  });

  // A pack is not one scene and has no single video to take a frame from, so
  // the Stash section and the video thumbnail are not part of its form, and the
  // Video pack section takes the place of the Screenshots one. The poster
  // belongs to the release rather than to an item, so a pack still has it
  // (`ai/video_pack.md` §6).
  testWidgets(
    'a video pack form shows the Video pack section and not the video sections',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testVideoPackRelease('/tmp/x'));

      expect(find.byKey(const ValueKey('stashSection')), findsNothing);
      expect(find.text('Screenshots'), findsNothing);
      expect(find.text('Video thumbnail'), findsNothing);
      expect(find.byKey(const ValueKey('photosetBlock')), findsNothing);
      expect(find.byKey(const ValueKey('videoPackSection')), findsOneWidget);
      expect(find.text('Poster image'), findsOneWidget);
    },
  );

  // The source row is not a field, so its label is the one the release type
  // has: a folder with videos is a different thing to pick than a folder with
  // photosets.
  testWidgets('a video pack form labels its source row as the video folder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await openEditor(tester, testVideoPackRelease('/tmp/x'));

    expect(find.text('Folder with the videos'), findsOneWidget);
    expect(find.text('Folder with the photosets'), findsNothing);
  });

  // The names a single photoset has are the ones the other types already have,
  // so the form is the same shape; only the words differ, because a model is
  // the same value as a cast and a set name the same value as a title
  // (`ai/single_photoset.md` §4).
  testWidgets('a single photoset shows its own fields and its own labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await openEditor(tester, testSinglePhotosetRelease('/tmp/x'));

    for (final name in [
      'cast',
      'videoTitle',
      'siteOrJournal',
      'productionDate',
      'genreTags',
      'description',
    ]) {
      expect(fieldOf(tester, name).readOnly, isFalse, reason: name);
    }

    for (final name in [
      'totalPhotoCount',
      'minResolution',
      'maxResolution',
      'imageFormats',
    ]) {
      expect(fieldOf(tester, name).readOnly, isTrue, reason: name);
    }

    // One set has no count of sets, and a photoset has no period.
    for (final name in ['photosetCount', 'period']) {
      expect(find.byKey(ValueKey(name)), findsNothing, reason: name);
    }

    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Set name'), findsOneWidget);
    expect(find.text('Cast'), findsNothing);
    expect(find.text('Video title'), findsNothing);
  });

  // The same section as a pack, because nothing in its layout branches on the
  // type; only the strings it shows do (`ai/single_photoset.md` §7).
  testWidgets(
    'a single photoset form shows the Photoset block and not the video sections',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testSinglePhotosetRelease('/tmp/x'));

      expect(find.byKey(const ValueKey('stashSection')), findsNothing);
      expect(find.text('Screenshots'), findsNothing);
      expect(find.byKey(const ValueKey('photosetBlock')), findsOneWidget);

      // One set has no columns to put its pictures in, so the block draws them
      // itself and there is no area beside it (`ai/picking.md` §7).
      expect(find.byKey(const ValueKey('photosetGallery')), findsNothing);

      expect(find.text('Poster image'), findsOneWidget);
    },
  );

  // A single set is a folder with photos in it, not a folder with sets in it,
  // so the source row says which one it is.
  testWidgets(
    'a single photoset form labels its source row as the folder with the photos',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testSinglePhotosetRelease('/tmp/x'));

      expect(find.text('Folder with the photos'), findsOneWidget);
      expect(find.text('Folder with the photosets'), findsNothing);
    },
  );

  // The catch-all type has no field the user writes, so the form is the poster
  // box and the values the scan counted. The names are the ones the photoset
  // types already have; only the words differ, because a folder of images is
  // not a set of photos (`ai/release_structure.md` §6,
  // `ai/image_folder_upload.md` §4).
  testWidgets('an image folder shows its own fields and its own labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await openEditor(tester, testImageFolderRelease('/tmp/x'));

    for (final name in [
      'totalPhotoCount',
      'minResolution',
      'maxResolution',
      'imageFormats',
    ]) {
      expect(fieldOf(tester, name).readOnly, isTrue, reason: name);
    }

    // There is no left column: this type has no field the user writes.
    for (final name in [
      'cast',
      'videoTitle',
      'siteOrJournal',
      'productionDate',
      'genreTags',
      'description',
      'photosetCount',
      'period',
    ]) {
      expect(find.byKey(ValueKey(name)), findsNothing, reason: name);
    }

    expect(find.text('Images (total)'), findsOneWidget);
    expect(find.text('Minimum image resolution'), findsOneWidget);
    expect(find.text('Maximum image resolution'), findsOneWidget);
    expect(find.text('Photos (total)'), findsNothing);
    expect(find.text('Minimum photo resolution'), findsNothing);
  });

  // The section the type has is its own, and the poster belongs to the release
  // rather than to an item, so this type has it too (`ai/doc.md` §5).
  testWidgets(
    'an image folder form shows the Image folder section and not the other sections',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testImageFolderRelease('/tmp/x'));

      expect(find.byKey(const ValueKey('stashSection')), findsNothing);
      expect(find.text('Screenshots'), findsNothing);
      expect(find.byKey(const ValueKey('photosetBlock')), findsNothing);
      expect(find.byKey(const ValueKey('videoPackSection')), findsNothing);
      expect(find.byKey(const ValueKey('imageFolderSection')), findsOneWidget);
      expect(find.text('Poster image'), findsOneWidget);

      // The image folder type has no title to send, so it is not one of the
      // types the Upload draft feature covers (`ai/uploading_draft.md` §4).
      expect(find.byKey(const ValueKey('draftSection')), findsNothing);
    },
  );

  // A folder with images in it is a different thing to pick than a folder with
  // photosets, so the source row says which one it is.
  testWidgets(
    'an image folder form labels its source row as the folder with the images',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await openEditor(tester, testImageFolderRelease('/tmp/x'));

      expect(find.text('Folder with the images'), findsOneWidget);
      expect(find.text('Folder with the photosets'), findsNothing);
    },
  );

  // A picked directory is the source the scan writes its items from, so picking
  // one records the source and creates no item (`ai/photoset_pack.md` §4).
  test('picking a directory records the source but creates no item', () {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final tabManager = TabManager();
    final release = testPackRelease(directory.path);
    final tabId = tabManager.addReleaseEditor(release);

    final controller = ReleaseEditorController(
      release: release,
      store: ReleaseStore(),
      tabManager: tabManager,
      ffprobe: _FakeProbe(
        const MediaInfo(
          fileSize: '',
          duration: '',
          durationSeconds: null,
          videoType: '',
          videoFormat: '',
          videoStream: '',
          audioStream: '',
        ),
      ),
      ffmpeg: _FakeFfmpeg(),
      downloader: _FakeDownloader(
        DownloadSuccess('', ContentType('image', 'jpeg')),
      ),
      images: ImagesStore(),
      tabId: tabId,
    );

    expect(controller.setSource(directory.path), isTrue);
    expect(release.source, directory.path);
    expect(release.items, isEmpty);

    directory.deleteSync(recursive: true);
  });

  // The Message section shows the message and the editor marks the row, so the
  // two are tested together: the section is the widget that runs the check,
  // this widget is the one that builds the rows. Only a row the user can type
  // into is marked; the ones the app fills are not, because the user cannot
  // fix them here.
  testWidgets('a field a generation refused is marked on its row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    // The Generate button is drawn only when the poster is on the poster
    // hoster, so the record has to say it is.
    await tester.runAsync(
      () => writePosterRecord(
        directory.path,
        urls: {
          posterHoster: {'direct_url': 'https://example.test/poster.jpg'},
        },
      ),
    );

    final fields = completeFields();
    fields.setValue('cast', '');

    await openEditor(
      tester,
      testRelease(directory.path, fields: fields),
      messageBundle: _FakeBundle('{{videoTitle}}'),
    );

    await tester.runAsync(() async {
      // The Screenshots section has a Generate button too, so the tap has to
      // say which one it means.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('messageSection')),
          matching: find.widgetWithText(FilledButton, 'Generate'),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // The row shows the words for the problem, the same ones the message
    // shows. The message is the joined lines, so this finds the row rather
    // than the message.
    expect(find.text('Cast is required.'), findsOneWidget);

    // Filling the field takes the error away, because the row shows the rule
    // as it stands rather than what was reported once.
    await tester.enterText(find.byKey(const ValueKey('cast')), 'Jane Doe');
    await tester.pump();

    expect(find.text('Cast is required.'), findsNothing);

    directory.deleteSync(recursive: true);
  });

  // What the Message section shows is a render of the values the form holds, so
  // a field this widget writes makes it stale. The section is not the widget
  // that builds the rows, so the notice goes out from the single write path
  // (rule 3).
  testWidgets('typing in a field clears what the Message section shows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    // The box is drawn only when there is something in it, and the generation
    // gate needs the poster on the poster hoster.
    await tester.runAsync(() async {
      await writePosterRecord(
        directory.path,
        urls: {
          posterHoster: {'direct_url': 'https://example.test/poster.jpg'},
        },
      );
      await MessageStore().save(
        directory.path,
        MessageStore.messageFile,
        'a generated message',
      );
    });

    await openEditor(
      tester,
      testRelease(directory.path),
      messageBundle: _FakeBundle('{{videoTitle}}'),
    );

    final box = find.byKey(const ValueKey('messageText'));

    expect(
      tester.widget<TextField>(box).controller!.text,
      'a generated message',
    );

    await tester.runAsync(() async {
      await tester.enterText(find.byKey(const ValueKey('cast')), 'Jane Doe');
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // An empty box is not drawn: the section shows its placeholder instead,
    // which is what an empty message looks like.
    expect(find.byKey(const ValueKey('messageText')), findsNothing);
    expect(find.text('Nothing generated yet.'), findsOneWidget);

    // The files go with the box, because the files always match what the section
    // shows.
    expect(
      File(p.join(directory.path, MessageStore.messageFile)).existsSync(),
      isFalse,
    );

    directory.deleteSync(recursive: true);
  });
}

class _FakeProbe implements Ffprobe {
  _FakeProbe(this.info);

  final MediaInfo info;

  String? probedPath;

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
    probedPath = filePath;

    return MediaProbeSuccess(info);
  }
}

class _FakeFfmpeg implements Ffmpeg {
  /// Every resize call, in the order the controller made them.
  final resizeCalls = <({String inputPath, String outputPath, int maxSize})>[];

  /// Every screenshot call, in the order the controller made them.
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
  }) async {
    resizeCalls.add((
      inputPath: inputPath,
      outputPath: outputPath,
      maxSize: maxSize,
    ));

    writeImage(outputPath);

    return const ToolRunSuccess(stdout: '', stderr: '');
  }

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

    writeImage(outputPath);

    return const ToolRunSuccess(stdout: '', stderr: '');
  }

  /// The widget test needs a file to be there. Its contents are not a real
  /// image: that test checks that the box shows an image for this path, not
  /// that it decodes one.
  void writeImage(String path) {
    File(path).writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
  }
}

/// A completer the test can tell apart from the ones the image cache holds, so
/// it can tell whether a path is in the cache.
class _SentinelCompleter extends ImageStreamCompleter {}

class _FakeDownloader implements ImageDownloader {
  _FakeDownloader(this.result);

  /// What the next call answers with.
  DownloadResult result;

  Uri? requestedUrl;
  String? destinationPath;

  @override
  HttpClient get client => HttpClient();

  @override
  Future<DownloadResult> download(Uri url, String destinationPath) async {
    requestedUrl = url;
    this.destinationPath = destinationPath;

    // A failure means nothing was written, so the caller can tell the two
    // apart.
    if (result is DownloadSuccess) {
      File(destinationPath).writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
    }

    return result;
  }
}

// The picker is a plugin, so a test that reaches it installs its platform
// interface. Nothing is returned, so the widget stops after the pick and the
// test only sees that the pick was asked for.
class _FakeFilePicker extends FilePickerPlatform {
  int calls = 0;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls += 1;

    return null;
  }
}
