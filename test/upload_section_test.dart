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
import 'package:release_prepper/feature/settings/settings.dart';
import 'package:release_prepper/feature/settings/settings_controller.dart';
import 'package:release_prepper/feature/settings/settings_store.dart';
import 'package:release_prepper/feature/upload/hosters.dart';
import 'package:release_prepper/feature/upload/upload_section.dart';
import 'package:release_prepper/l10n/app_localizations.dart';
import 'package:release_prepper/service/native_tools/tool_runner.dart';
import 'package:release_prepper/service/native_tools/uptooda.dart';

import 'fake_pornolab_client.dart';
import 'fake_secret_store.dart';
import 'test_runner.dart';

// The editor registers this section's rebuild. A test that does not look at the
// counters does not need it, so it ignores it. A default parameter must be a
// constant, so this is a named function rather than a lambda.
void ignoreImagesChanged(void Function() rebuild) {}

// The same for the notice a run ends with.
void ignoreRunEnded() {}

void main() {
  // A release of one type, because the gate is a rule of the type. The item
  // type is the one its field list says, so a test does not invent one.
  Release releaseOf(ReleaseType type) => Release(
    name: 'x',
    directoryPath: '/tmp/release_prepper_test',
    tracker: Tracker.pornolab,
    releaseType: type,
    source: '/home/user/videos',
    fields: FieldValues(),
    items: [
      ReleaseItem(
        path: 'movie.mp4',
        type: fieldListFor(type).itemType,
        fields: FieldValues(),
      ),
    ],
  );

  // The section reads the Integration values from the settings, so a test gives
  // it a controller with them. Reading them from the credential store is what
  // `test/settings_test.dart` covers, so this sets the values directly.
  SettingsController settingsWith(Map<String, String> values) {
    final controller = SettingsController(
      store: SettingsStore(appDirectory: () async => Directory.systemTemp),
      secretStore: FakeSecretStore(available: true),
      homeDirectory: '/home/test',
      pathContext: p.context,
      client: FakePornolabClient(),
      appDirectory: () async => Directory.systemTemp,
    );

    controller.secretValues = values;

    return controller;
  }

  // A record as `images.json` holds it, so a test can say what the section is
  // opened with.
  ImageRecord record(
    ImageKind kind,
    String file,
    Map<String, Map<String, String>> urls,
  ) => ImageRecord(
    item: kind == ImageKind.poster ? null : 'movie.mp4',
    kind: kind,
    file: file,
    urls: urls,
  );

  Map<String, String> urlsFor(String hoster) => {
    for (final field in Uptooda.urlFields)
      field: 'https://example.com/$hoster/$field',
  };

  // A release with the images a run here has to do — a poster and a screenshot
  // — and nothing uploaded to any hoster, so the section shows the hoster list
  // rather than the placeholder. The urls map is not const because the run
  // writes to it.
  ImagesManifest nothingUploaded() => ImagesManifest(
    images: [
      record(ImageKind.poster, '_rp_poster.jpg', {}),
      record(ImageKind.screenshot, 'images/movie.mp4/_rp_screenshot01.jpg', {}),
    ],
  );

  Widget app({
    required SettingsController settings,
    required _FakeUptooda uptooda,
    required _FakeStore store,
    // The gate is a rule of the type, so a test that looks at it says which
    // type the section is opened for.
    ReleaseType releaseType = ReleaseType.singleVideo,
    // The editor registers this section's rebuild; a test that does not look at
    // the counters does not need it, so the default is the no-op above.
    void Function(void Function()) subscribeImagesChanged = ignoreImagesChanged,
    void Function() onImagesChanged = ignoreRunEnded,
  }) => MultiProvider(
    providers: [
      Provider<Uptooda>(create: (_) => uptooda),
      Provider<ImagesStore>(create: (_) => store),
      Provider<ReleaseStore>(create: (_) => _FakeReleaseStore()),
      ChangeNotifierProvider<SettingsController>(create: (_) => settings),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: UploadSection(
            release: releaseOf(releaseType),
            subscribeImagesChanged: subscribeImagesChanged,
            onImagesChanged: onImagesChanged,
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'the hosters are listed checked by default, and only the checked ones run',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      final uptooda = _FakeUptooda();
      final store = _FakeStore(manifest: nothingUploaded());

      await tester.pumpWidget(
        app(settings: settingsWith(const {}), uptooda: uptooda, store: store),
      );

      expect(find.text('Upload images'), findsOneWidget);

      // The button is in the title row, at the right of the section's title,
      // because it is the action of the whole section rather than one of the
      // hoster rows it acts on.
      expect(
        find.ancestor(
          of: find.text('Upload'),
          matching: find.byType(SectionTitle),
        ),
        findsOneWidget,
      );

      // Checked by default, in the order the registry lists them — except for a
      // hoster that needs a credential and has none: it cannot run, so it is
      // not checked and its checkbox is inactive (`ai/upload_images.md`).
      for (final hoster in hosters) {
        expect(find.text(hoster.name), findsOneWidget);

        final checkbox = tester.widget<Checkbox>(
          find.byType(Checkbox).at(hosters.indexOf(hoster)),
        );

        expect(checkbox.value, hoster.field == null);
        expect(checkbox.onChanged, hoster.field == null ? isNotNull : isNull);
      }

      // The bars are there before anything runs, showing what `images.json`
      // holds: nothing is uploaded, so every hoster is at 0 of the two images
      // the release has (`ai/upload_images.md`).
      expect(
        find.byType(LinearProgressIndicator),
        findsNWidgets(hosters.length),
      );
      expect(find.text('0 / 2'), findsNWidgets(hosters.length));

      // The second hoster is unchecked, so it is not called. The hoster that
      // needs a credential is not called either, because it cannot be selected
      // while its value is empty. What runs is the rest of the list.
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();

      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();

      final ran = [
        for (final hoster in hosters)
          if (hoster.field == null && hoster != hosters[1]) hoster.name,
      ];

      expect(uptooda.calls.keys, ran);

      // A hoster that ran is now full; the ones that did not still show what
      // they had before, because the bar counts against the images in the
      // release, not the run.
      for (final hoster in hosters) {
        final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator).at(hosters.indexOf(hoster)),
        );

        expect(bar.value, ran.contains(hoster.name) ? 1.0 : 0.0);
      }

      expect(find.text('2 / 2'), findsNWidgets(ran.length));
      expect(find.text('0 / 2'), findsNWidgets(hosters.length - ran.length));

      // The record is written through the store after each upload, so the
      // manifest the widget's controller holds is what the store was given.
      expect(
        store.saved.first.images.first.urls[hosters.first.name],
        isNotNull,
      );
    },
  );

  // `--dev` replaces the real hosters with the mock ones
  // (`ai/upload_images.md`), so the section lists only the mock hosters, all of
  // them checked, and a run calls them.
  testWidgets('with --dev the real hosters are replaced with the mock ones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    // `main()` sets this from the command line; a test sets it here because the
    // widget reads the registry through it.
    devMode = true;
    addTearDown(() => devMode = false);

    final uptooda = _FakeUptooda();
    final store = _FakeStore(manifest: nothingUploaded());

    await tester.pumpWidget(
      app(settings: settingsWith(const {}), uptooda: uptooda, store: store),
    );

    expect(find.byType(Checkbox), findsNWidgets(mockHosters.length));

    for (final hoster in mockHosters) {
      expect(find.text(hoster.name), findsOneWidget);

      expect(
        tester
            .widget<Checkbox>(
              find.byType(Checkbox).at(mockHosters.indexOf(hoster)),
            )
            .value,
        true,
      );
    }

    // The real hosters are not listed at all.
    for (final hoster in realHosters) {
      expect(find.text(hoster.name), findsNothing);
    }

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(uptooda.calls.keys, [for (final hoster in mockHosters) hoster.name]);
  });

  // The bars are drawn from what `images.json` holds, so a release opened with
  // its images uploaded shows them full before anything runs
  // (`ai/upload_images.md`).
  testWidgets(
    'a release opened with every image uploaded shows full bars for every hoster',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      final store = _FakeStore(
        manifest: ImagesManifest(
          images: [
            record(ImageKind.poster, '_rp_poster.jpg', {
              for (final hoster in hosters) hoster.name: urlsFor(hoster.name),
            }),
            record(
              ImageKind.screenshot,
              'images/movie.mp4/_rp_screenshot01.jpg',
              {for (final hoster in hosters) hoster.name: urlsFor(hoster.name)},
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        app(
          settings: settingsWith(const {}),
          uptooda: _FakeUptooda(),
          store: store,
        ),
      );

      // Every hoster has a bar, including the one that cannot run because its
      // credential is missing, and every one of them is full.
      expect(
        find.byType(LinearProgressIndicator),
        findsNWidgets(hosters.length),
      );

      for (final hoster in hosters) {
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find
                    .byType(LinearProgressIndicator)
                    .at(hosters.indexOf(hoster)),
              )
              .value,
          1.0,
        );
      }

      expect(find.text('2 / 2'), findsNWidgets(hosters.length));
    },
  );

  // The count is the count the release has, so a generation run that adds
  // images changes it. This section cannot see the Screenshots section, so it
  // is the editor — the widget that places both — that calls the rebuild
  // registered here (`ai/upload_images.md`).
  testWidgets('the counters are rebuilt when a generation run ends', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    void Function()? rebuild;

    final store = _FakeStore(manifest: nothingUploaded());

    await tester.pumpWidget(
      app(
        settings: settingsWith(const {}),
        uptooda: _FakeUptooda(),
        store: store,
        subscribeImagesChanged: (callback) => rebuild = callback,
      ),
    );

    expect(find.text('0 / 2'), findsNWidgets(hosters.length));

    // A run writes a second image, and the editor tells this section about it.
    store.manifest = ImagesManifest(
      images: [
        ...store.manifest.images,
        record(
          ImageKind.screenshot,
          'images/movie.mp4/_rp_screenshot02.jpg',
          {},
        ),
      ],
    );

    rebuild!();
    await tester.pump();

    expect(find.text('0 / 3'), findsNWidgets(hosters.length));
  });

  // A run here is itself a change to what `images.json` holds, so it is
  // something the other sections show; the editor is what tells them, so a run
  // ends by calling the notice it was given (`ai/upload_images.md`).
  testWidgets('the editor is told when a run ends', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final notices = <String>[];

    await tester.pumpWidget(
      app(
        settings: settingsWith(const {}),
        uptooda: _FakeUptooda(),
        store: _FakeStore(manifest: nothingUploaded()),
        onImagesChanged: () => notices.add('ended'),
      ),
    );

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(notices, ['ended']);
  });

  // A release with no images has nothing this section could upload, so it says
  // what has to happen first instead of listing hosters with empty bars
  // (`ai/upload_images.md`).
  testWidgets(
    'a release with no images shows the placeholder instead of the hoster list',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        app(
          settings: settingsWith(const {}),
          uptooda: _FakeUptooda(),
          store: _FakeStore(manifest: const ImagesManifest.empty()),
        ),
      );

      expect(
        find.text('Add a poster and generate screenshots first'),
        findsOneWidget,
      );

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    },
  );

  // The placeholder waits for the pair, not for one of them: a poster alone is
  // still nothing this section could upload, so it stays.
  testWidgets('a poster without screenshots still shows the placeholder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      app(
        settings: settingsWith(const {}),
        uptooda: _FakeUptooda(),
        store: _FakeStore(
          manifest: ImagesManifest(
            images: [record(ImageKind.poster, '_rp_poster.jpg', {})],
          ),
        ),
      ),
    );

    expect(
      find.text('Add a poster and generate screenshots first'),
      findsOneWidget,
    );

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  // The gate is the poster plus the kind the type's run produces, so for a
  // pack a screenlist is what opens the section and a screenshot is not: a run
  // over a pack can be asked to write only the screenlist (`ai/video_pack.md`
  // §5).
  testWidgets(
    'a video pack with a poster and a screenlist shows the hoster list',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        app(
          settings: settingsWith(const {}),
          uptooda: _FakeUptooda(),
          store: _FakeStore(
            manifest: ImagesManifest(
              images: [
                record(ImageKind.poster, '_rp_poster.jpg', {}),
                record(
                  ImageKind.screenlist,
                  'images/movie.mp4/_rp_screenlist.txt',
                  {},
                ),
              ],
            ),
          ),
          releaseType: ReleaseType.videoPack,
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsWidgets);
      expect(find.byType(FilledButton), findsOneWidget);
    },
  );

  // And the words name the kind the type is waiting for, so a pack with
  // screenshots and no screenlist says the screenlists.
  testWidgets(
    'a video pack with screenshots and no screenlist names the screenlists',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        app(
          settings: settingsWith(const {}),
          uptooda: _FakeUptooda(),
          store: _FakeStore(
            manifest: ImagesManifest(
              images: [
                record(ImageKind.poster, '_rp_poster.jpg', {}),
                record(
                  ImageKind.screenshot,
                  'images/movie.mp4/_rp_screenshot01.jpg',
                  {},
                ),
              ],
            ),
          ),
          releaseType: ReleaseType.videoPack,
        ),
      );

      expect(
        find.text('Add a poster and generate screenlists first'),
        findsOneWidget,
      );
      expect(
        find.text('Add a poster and generate screenshots first'),
        findsNothing,
      );

      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  // The same rule for the types whose run has a photo rather than a screenshot:
  // a photo is what opens the section for them (`ai/photoset_pack.md` §5).
  testWidgets(
    'a photoset pack with a poster and a photo shows the hoster list',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        app(
          settings: settingsWith(const {}),
          uptooda: _FakeUptooda(),
          store: _FakeStore(
            manifest: ImagesManifest(
              images: [
                record(ImageKind.poster, '_rp_poster.jpg', {}),
                record(ImageKind.photo, 'fotopset/first.jpg', {}),
              ],
            ),
          ),
          releaseType: ReleaseType.photosetPack,
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsWidgets);
      expect(find.byType(FilledButton), findsOneWidget);
    },
  );

  testWidgets('a hoster that needs a credential is inactive while its value is empty, and '
      'says where to set it', (tester) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final uptooda = _FakeUptooda();

    await tester.pumpWidget(
      app(
        settings: settingsWith(const {}),
        uptooda: uptooda,
        store: _FakeStore(manifest: nothingUploaded()),
      ),
    );

    final hoster = hosters.firstWhere((hoster) => hoster.field != null);

    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Set up the API key in Settings → Integration',
    );

    // A hoster that cannot run is not offered as selected, so the run never
    // calls it with an empty credential. Tapping its inactive checkbox does
    // nothing.
    await tester.tap(find.byType(Checkbox).at(hosters.indexOf(hoster)));
    await tester.pump();

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(uptooda.calls.keys, isNot(contains(hoster.name)));
  });

  testWidgets(
    'a hoster with its credential is active, and the value is passed to the call',
    (tester) async {
      tester.view.physicalSize = const Size(2000, 2000);
      tester.view.devicePixelRatio = 1.0;

      final uptooda = _FakeUptooda();
      final settings = settingsWith({SettingsField.postimages.name: 'the-key'});

      await tester.pumpWidget(
        app(
          settings: settings,
          uptooda: uptooda,
          store: _FakeStore(manifest: nothingUploaded()),
        ),
      );

      final hoster = hosters.firstWhere((hoster) => hoster.field != null);
      final checkbox = tester.widget<Checkbox>(
        find.byType(Checkbox).at(hosters.indexOf(hoster)),
      );

      expect(checkbox.onChanged, isNotNull);
      expect(checkbox.value, true);

      await tester.tap(find.text('Upload'));
      await tester.pumpAndSettle();

      // Only the hoster whose script reads a credential gets the variable, and
      // it is the value the settings hold (`ai/bundled_native_tools.md`).
      expect(uptooda.environments[hoster.name], {
        Uptooda.apiKeyVariable: 'the-key',
      });
      expect(uptooda.environments[hosters.first.name], const {});
    },
  );
}

class _FakeUptooda implements Uptooda {
  final calls = <String, List<String>>{};

  final environments = <String, Map<String, String>>{};

  @override
  ToolRunner get runner => testRunner();

  @override
  Future<ToolRunResult> version({required String releaseDirectory}) async =>
      const ToolRunSuccess(stdout: '', stderr: '');

  @override
  Future<UptoodaUploadResult> upload({
    required String releaseDirectory,
    required String hoster,
    required String filePath,
    required Map<String, String> environment,
  }) async {
    calls.putIfAbsent(hoster, () => []).add(filePath);
    environments[hoster] = environment;

    return UptoodaUploadSuccess({
      for (final field in Uptooda.urlFields)
        field: 'https://example.com/$hoster/$field',
    });
  }
}

/// A store that does not touch the filesystem, so the last-edit stamp a run
/// writes completes inside the widget test's fake-async zone, as the images
/// store does.
class _FakeReleaseStore implements ReleaseStore {
  @override
  Future<Release> create({
    required String savePath,
    required String name,
    required Tracker tracker,
    required ReleaseType releaseType,
  }) async => throw UnsupportedError('this test does not create a release');

  @override
  Future<Release> load(String directoryPath) async =>
      throw UnsupportedError('this test does not load a release');

  @override
  Future<void> save(Release release) async {}

  @override
  Future<bool> touchLastEdit(Release release) async => true;
}

/// A store that does not touch the filesystem, so the run completes inside the
/// widget test's fake-async zone. The manifest is what the section shows when
/// it is opened and what the controller writes through it. A test changes it to
/// be what a run wrote.
class _FakeStore implements ImagesStore {
  _FakeStore({required this.manifest});

  ImagesManifest manifest;

  final saved = <ImagesManifest>[];

  @override
  String filePath(String directoryPath) => 'images.json';

  @override
  ImagesManifest loadSync(String directoryPath) => manifest;

  @override
  Future<ImagesManifest> load(String directoryPath) async => manifest;

  @override
  Future<void> save(String directoryPath, ImagesManifest manifest) async {
    saved.add(manifest);
  }
}
