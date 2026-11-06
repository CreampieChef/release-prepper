import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/settings/secret_store.dart';
import 'package:release_prepper/feature/settings/settings.dart';
import 'package:release_prepper/feature/settings/settings_controller.dart';
import 'package:release_prepper/feature/settings/settings_store.dart';
import 'package:release_prepper/feature/stashdb/stash_section.dart';
import 'package:release_prepper/l10n/app_localizations.dart';
import 'package:release_prepper/service/network/image_downloader.dart';
import 'package:release_prepper/service/network/stash_client.dart';
import 'package:release_prepper/service/stashdb/domain_map.dart';

import 'fake_pornolab_client.dart';

void main() {
  const id = 'b3c6f0e4-8f1e-4c2b-9a1d-6f0a2b3c4d5e';
  const posterUrl = 'https://example.com/poster.jpg';

  const scene = StashScene(
    id: id,
    title: 'Example title',
    code: '12345',
    details: 'Description text',
    releaseDate: '2024-06-01',
    productionDate: '2024-05-17',
    studio: StashStudio(
      name: 'Example Studio',
      urls: [
        StashUrl(
          url: 'https://www.example-studio.com',
          siteName: 'Example Site',
          categoryName: 'Primary sources',
        ),
      ],
    ),
    parentStudio: StashStudio.empty,
    performers: [StashAppearance(name: 'Real Name', alias: '')],
    tags: ['anal'],
    images: [posterUrl],
  );

  Checkbox rowCheckbox(WidgetTester tester, String rowKey) =>
      tester.widget<Checkbox>(
        find.descendant(
          of: find.byKey(ValueKey(rowKey)),
          matching: find.byType(Checkbox),
        ),
      );

  Future<void> fetch(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('stashSceneInput')), id);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('stashFetchButton')));
    await tester.pumpAndSettle();
  }

  Future<void> pumpSection(
    WidgetTester tester,
    StashClient client,
    SettingsController settings,
    List<Map<String, String>> applied,
    List<String> posters, {
    String initialUrl = '',
    ImageDownloader? downloader,
    AssetBundle? bundle,
  }) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StashClient>(create: (_) => client),
          Provider<ImageDownloader>(
            create: (_) =>
                downloader ??
                _FakeDownloader(
                  const DownloadFailure(DownloadFailureKind.failed),
                ),
          ),
          Provider<DomainMap>(
            create: (_) => DomainMap(bundle: bundle ?? _FakeBundle({})),
          ),
          ChangeNotifierProvider<SettingsController>(create: (_) => settings),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: StashSection(
                releaseType: ReleaseType.singleVideo,
                onApply: (values) => applied.add(values),
                onPoster: posters.add,
                initialUrl: initialUrl,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<SettingsController> settingsWith(Map<String, String> values) async {
    final settings = SettingsController(
      // A store that does not touch the filesystem, so the read completes
      // inside the widget test's fake-async zone. The section only reads the
      // values, so nothing is written.
      store: _FakeSettingsStore(appDirectory: () async => Directory.systemTemp),
      secretStore: _FakeSecretStore(values),
      homeDirectory: '',
      pathContext: p.context,
      client: FakePornolabClient(),
      appDirectory: () async => Directory.systemTemp,
    );

    // The values the section reads are the ones the controller holds after its
    // read.
    await settings.load();

    return settings;
  }

  testWidgets('the row shows the input and nothing until a scene is fetched', (
    tester,
  ) async {
    final applied = <Map<String, String>>[];
    final posters = <String>[];
    final client = _FakeClient(const StashSceneSuccess(scene));

    await pumpSection(
      tester,
      client,
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
    );

    expect(find.byKey(const ValueKey('stashSceneInput')), findsOneWidget);

    // Nothing has been asked for, so there is nothing to select and nothing to
    // apply.
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byKey(const ValueKey('stashApplyButton')), findsNothing);

    // An empty input cannot be fetched.
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('stashFetchButton')))
          .onPressed,
      isNull,
    );

    await fetch(tester);

    // What the fetch gives is shown in a popup, not in the form, and each value
    // there is checked because there is something to apply — the poster row
    // among them.
    expect(find.text('Import from Stash DB'), findsOneWidget);

    for (final field in ['cast', 'videoTitle', 'siteNumber', 'description']) {
      expect(rowCheckbox(tester, 'stash-row-$field').value, true);
    }

    expect(rowCheckbox(tester, 'stash-row-poster').value, true);

    // The key is the one the settings hold.
    expect(client.calls, [(id, 'the-key')]);
  });

  // The popup is the only place the values are chosen, so closing it without
  // applying writes nothing; fetching again is what shows them again.
  testWidgets('closing the popup without applying writes nothing', (
    tester,
  ) async {
    final applied = <Map<String, String>>[];
    final posters = <String>[];

    await pumpSection(
      tester,
      _FakeClient(const StashSceneSuccess(scene)),
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
    );

    await fetch(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(applied, isEmpty);
    expect(posters, isEmpty);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('the Cancel button closes the popup without applying', (
    tester,
  ) async {
    final applied = <Map<String, String>>[];
    final posters = <String>[];

    await pumpSection(
      tester,
      _FakeClient(const StashSceneSuccess(scene)),
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
    );

    await fetch(tester);

    await tester.tap(find.byKey(const ValueKey('stashCancelButton')));
    await tester.pumpAndSettle();

    expect(applied, isEmpty);
    expect(posters, isEmpty);
    expect(find.byType(Checkbox), findsNothing);
  });

  // The link is what the row is, so it is shown first and the image it points
  // to below it.
  testWidgets(
    'the poster image is shown below its link, at the width the row has',
    (tester) async {
      final applied = <Map<String, String>>[];
      final posters = <String>[];

      await pumpSection(
        tester,
        _FakeClient(const StashSceneSuccess(scene)),
        await settingsWith({'stashdb': 'the-key'}),
        applied,
        posters,
        downloader: _FakeDownloader(DownloadSuccess('the-preview-file', null)),
      );

      await fetch(tester);

      final row = find.byKey(const ValueKey('stash-row-poster'));

      final link = tester.getRect(
        find.descendant(of: row, matching: find.text(posterUrl)),
      );
      final column = tester.getRect(
        find.descendant(of: row, matching: find.byType(Column)),
      );
      final image = find.descendant(of: row, matching: find.byType(Image));
      final imageRect = tester.getRect(image);

      expect(imageRect.top, greaterThan(link.bottom));

      // The box is the width the text column has rather than a square, so a
      // landscape poster fills it; a portrait one is kept at the left, where
      // the text above it is, rather than centred.
      expect(imageRect.width, closeTo(column.width, 0.5));
      expect(imageRect.height, 240);
      expect(tester.widget<Image>(image).alignment, Alignment.centerLeft);
    },
  );

  // A value the import changed is its own subsection below the poster: the
  // title "Import notes", then the message that says what was done to the value
  // followed by the value as the scene reported it, with the part the app cut
  // struck through. It has no checkbox, because it is not something to apply:
  // the row above is the value.
  testWidgets(
    'the popup shows what the import changed, with the part it cut struck through',
    (tester) async {
      const changed = StashScene(
        id: id,
        title: 'Example title 12345',
        code: '12345',
        details: '',
        releaseDate: '',
        productionDate: '',
        studio: StashStudio.empty,
        parentStudio: StashStudio.empty,
        performers: [],
        tags: [],
        images: [posterUrl],
      );

      final applied = <Map<String, String>>[];
      final posters = <String>[];

      await pumpSection(
        tester,
        _FakeClient(const StashSceneSuccess(changed)),
        await settingsWith({'stashdb': 'the-key'}),
        applied,
        posters,
        downloader: _FakeDownloader(DownloadSuccess('the-preview-file', null)),
      );

      await fetch(tester);

      // The row above is what the app writes: the title without the number.
      expect(find.text('Example title'), findsOneWidget);

      final heading = find.text('Import notes');
      expect(heading, findsOneWidget);

      expect(
        tester.getRect(heading).top,
        greaterThan(
          tester.getRect(find.byKey(const ValueKey('stash-row-poster'))).bottom,
        ),
      );

      final note = find.byKey(const ValueKey('stash-note-videoTitle-0'));
      expect(note, findsOneWidget);
      expect(
        tester.getRect(note).top,
        greaterThan(tester.getRect(heading).bottom),
      );

      expect(
        find.descendant(of: note, matching: find.byType(Checkbox)),
        findsNothing,
      );

      final noteSpan = tester.widget<Text>(note).textSpan as TextSpan;

      expect(
        noteSpan.children!
            .cast<TextSpan>()
            .map((part) => (part.text, part.style?.decoration))
            .toList(),
        [
          (
            'Video title in StashDB contains its site number, so it has been '
                'stripped from the title: ',
            null,
          ),
          ('Example title ', null),
          ('12345', TextDecoration.lineThrough),
        ],
      );
    },
  );

  // A value the import copied as the scene reported it is not a change, so the
  // subsection has nothing to show.
  testWidgets('a value the import did not change is not listed as changed', (
    tester,
  ) async {
    final applied = <Map<String, String>>[];
    final posters = <String>[];

    await pumpSection(
      tester,
      _FakeClient(const StashSceneSuccess(scene)),
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
    );

    await fetch(tester);

    expect(find.text('Import notes'), findsNothing);
    expect(find.byKey(const ValueKey('stash-note-videoTitle-0')), findsNothing);
  });

  // A domain read from a URL that is not in the Primary sources category is not
  // what the rule would give, so it is a change the popup lists: the message
  // that says what was done, then the URL it was read from.
  testWidgets('a domain read from another URL is listed with that URL', (
    tester,
  ) async {
    const changed = StashScene(
      id: id,
      title: '',
      code: '',
      details: '',
      releaseDate: '',
      productionDate: '',
      studio: StashStudio(
        name: 'Example Studio',
        urls: [
          StashUrl(
            url: 'https://example-studio.com',
            siteName: 'Studio',
            categoryName: '',
          ),
        ],
      ),
      parentStudio: StashStudio.empty,
      performers: [],
      tags: [],
      images: [],
    );

    final applied = <Map<String, String>>[];
    final posters = <String>[];

    await pumpSection(
      tester,
      _FakeClient(const StashSceneSuccess(changed)),
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
    );

    await fetch(tester);

    final note = find.byKey(const ValueKey('stash-note-subsiteAndSite-0'));
    expect(note, findsOneWidget);

    final noteSpan = tester.widget<Text>(note).textSpan as TextSpan;

    expect(
      noteSpan.children!.cast<TextSpan>().map((part) => part.text).toList(),
      [
        'Subsite and site: StashDB has no link in the Primary sources category, '
            'so the domain was read from this link: ',
        'https://example-studio.com',
      ],
    );
  });

  // The subsite and the site are two studios, and each one that had to be read
  // from another URL has its own note, so the same field can have more than
  // one; the index is what keeps their keys apart.
  testWidgets('each studio read from another URL has its own note', (
    tester,
  ) async {
    const changed = StashScene(
      id: id,
      title: '',
      code: '',
      details: '',
      releaseDate: '',
      productionDate: '',
      studio: StashStudio(
        name: 'Example Studio',
        urls: [
          StashUrl(
            url: 'https://example-studio.com',
            siteName: '',
            categoryName: '',
          ),
        ],
      ),
      parentStudio: StashStudio(
        name: 'Example Network',
        urls: [
          StashUrl(
            url: 'https://example-network.com',
            siteName: '',
            categoryName: '',
          ),
        ],
      ),
      performers: [],
      tags: [],
      images: [],
    );

    final applied = <Map<String, String>>[];
    final posters = <String>[];

    await pumpSection(
      tester,
      _FakeClient(const StashSceneSuccess(changed)),
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
    );

    await fetch(tester);

    expect(
      find.byKey(const ValueKey('stash-note-subsiteAndSite-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stash-note-subsiteAndSite-1')),
      findsOneWidget,
    );
  });

  // The row owns the focus of its input. The popup is a route, so its focus
  // scope is outside the row's, and the row asks for its input back when the
  // popup closes; what the framework would give it back to is whatever had
  // focus before the popup.
  testWidgets('the input has focus again after the popup closes', (
    tester,
  ) async {
    final applied = <Map<String, String>>[];
    final posters = <String>[];

    await pumpSection(
      tester,
      _FakeClient(const StashSceneSuccess(scene)),
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
    );

    final input = find.byKey(const ValueKey('stashSceneInput'));

    // `TextFormField` takes the node and hands it to the field it builds, so
    // the node the row owns is the one the field uses.
    final focus = tester
        .widget<TextField>(
          find.descendant(of: input, matching: find.byType(TextField)),
        )
        .focusNode!;

    await tester.enterText(input, id);
    focus.requestFocus();
    await tester.pump();

    expect(focus.hasFocus, isTrue);

    await tester.tap(find.byKey(const ValueKey('stashFetchButton')));
    await tester.pumpAndSettle();

    // The popup has it while it is open.
    expect(focus.hasFocus, isFalse);

    await tester.tap(find.byKey(const ValueKey('stashApplyButton')));
    await tester.pumpAndSettle();

    expect(focus.hasFocus, isTrue);
  });

  testWidgets('only the checked values are applied', (tester) async {
    final applied = <Map<String, String>>[];
    final posters = <String>[];
    final client = _FakeClient(const StashSceneSuccess(scene));

    await pumpSection(
      tester,
      client,
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
    );

    await fetch(tester);

    // The cast and the poster are unchecked, so neither is written.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('stash-row-cast')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('stash-row-poster')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('stashApplyButton')));
    await tester.pumpAndSettle();

    expect(applied.single.keys, [
      'videoTitle',
      'siteNumber',
      'subsiteAndSite',
      'productionDate',
      'genreTags',
      'description',
      'sceneUrl',
    ]);
    expect(applied.single['videoTitle'], 'Example title');
    expect(applied.single['cast'], isNull);
    expect(posters, isEmpty);
  });

  // The values come from the controller, which reads the mapping from the asset
  // bundle, so the popup shows the form the file gives rather than the domain
  // as the host is written. The read is async, so what the popup shows is what
  // it holds after the read completes.
  testWidgets('a domain in the mapping is what the popup applies', (
    tester,
  ) async {
    const mapped = StashScene(
      id: id,
      title: '',
      code: '',
      details: '',
      releaseDate: '',
      productionDate: '',
      studio: StashStudio(
        name: 'Jacquie et Michel TV',
        urls: [
          StashUrl(
            url: 'https://www.jacquieetmicheltv.net',
            siteName: '',
            categoryName: 'Primary sources',
          ),
        ],
      ),
      parentStudio: StashStudio.empty,
      performers: [],
      tags: [],
      images: [],
    );

    final applied = <Map<String, String>>[];
    final posters = <String>[];

    await pumpSection(
      tester,
      _FakeClient(const StashSceneSuccess(mapped)),
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
      bundle: _FakeBundle({
        DomainMap.assetPath:
            '{"jacquieetmicheltv.net": "JacquieEtMichelTV.net"}',
      }),
    );

    await fetch(tester);

    await tester.tap(find.byKey(const ValueKey('stashApplyButton')));
    await tester.pumpAndSettle();

    expect(applied.single['subsiteAndSite'], 'JacquieEtMichelTV.net');
  });

  // The link is not one of the values the user chooses, so it is not a row with
  // a checkbox; it is what they asked for by fetching the scene, and it is
  // written on its own.
  testWidgets('the scene link is written with what is applied', (tester) async {
    final applied = <Map<String, String>>[];
    final posters = <String>[];

    await pumpSection(
      tester,
      _FakeClient(const StashSceneSuccess(scene)),
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
    );

    await fetch(tester);
    await tester.tap(find.byKey(const ValueKey('stashApplyButton')));
    await tester.pumpAndSettle();

    // Built from the id the app asked for, so a pasted id becomes a link.
    expect(applied.single['sceneUrl'], 'https://stashdb.org/scenes/$id');
  });

  // A scene with no values still has its link, so applying it writes the link
  // and nothing else.
  testWidgets('the scene link is written on its own', (tester) async {
    final applied = <Map<String, String>>[];
    final posters = <String>[];
    final client = _FakeClient(
      const StashSceneSuccess(
        StashScene(
          id: id,
          title: '',
          code: '',
          details: '',
          releaseDate: '',
          productionDate: '',
          studio: StashStudio.empty,
          parentStudio: StashStudio.empty,
          performers: [],
          tags: [],
          images: [],
        ),
      ),
    );

    await pumpSection(
      tester,
      client,
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
    );

    await fetch(tester);

    // There is nothing to select, but the link is still something to apply.
    expect(find.byType(Checkbox), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('stashApplyButton')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('stashApplyButton')));
    await tester.pumpAndSettle();

    expect(applied.single.keys, ['sceneUrl']);
    expect(applied.single['sceneUrl'], 'https://stashdb.org/scenes/$id');
    expect(posters, isEmpty);
  });

  // The input is the widget the scene link field has, so a release opened from
  // disk shows the link its manifest holds, and after an apply it shows what
  // was stored rather than the text that was pasted.
  testWidgets('the input starts with the link the release stores', (
    tester,
  ) async {
    final stored = 'https://stashdb.org/scenes/$id';
    final applied = <Map<String, String>>[];

    await pumpSection(
      tester,
      _FakeClient(const StashSceneSuccess(scene)),
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      <String>[],
      initialUrl: stored,
    );

    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('stashSceneInput')))
          .controller
          ?.text,
      stored,
    );

    // An id was pasted over it, and applying stores the link, so the input
    // shows the link.
    await tester.enterText(find.byKey(const ValueKey('stashSceneInput')), id);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('stashFetchButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stashApplyButton')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('stashSceneInput')))
          .controller
          ?.text,
      stored,
    );
  });

  // The poster is not a field, so it does not go through the field write path;
  // it goes to the editor's poster path, the same one a pasted link uses.
  testWidgets('the checked poster is applied through the poster path', (
    tester,
  ) async {
    final applied = <Map<String, String>>[];
    final posters = <String>[];

    await pumpSection(
      tester,
      _FakeClient(const StashSceneSuccess(scene)),
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
    );

    await fetch(tester);

    await tester.tap(find.byKey(const ValueKey('stashApplyButton')));
    await tester.pumpAndSettle();

    expect(posters, [posterUrl]);
  });

  // The app shows no image it has not read from a file, so the popup shows the
  // poster from the file the controller downloads it into.
  testWidgets('the poster row shows the image the download wrote', (
    tester,
  ) async {
    final applied = <Map<String, String>>[];
    final posters = <String>[];
    final downloader = _FakeDownloader(
      DownloadSuccess('the-preview-file', null),
    );

    await pumpSection(
      tester,
      _FakeClient(const StashSceneSuccess(scene)),
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
      downloader: downloader,
    );

    await fetch(tester);

    // The name is the scene's, so a different scene is a different path and an
    // Image resolves it again rather than showing what the cache still holds.
    expect(downloader.paths.single, endsWith('rp_stash_preview_$id'));

    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const ValueKey('stash-row-poster')),
        matching: find.byType(Image),
      ),
    );

    expect(image.image, isA<FileImage>());
    expect((image.image as FileImage).file.path, downloader.paths.single);
  });

  testWidgets('a poster that cannot be downloaded shows its URL only', (
    tester,
  ) async {
    final applied = <Map<String, String>>[];
    final posters = <String>[];

    await pumpSection(
      tester,
      _FakeClient(const StashSceneSuccess(scene)),
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
    );

    await fetch(tester);

    expect(find.text(posterUrl), findsOneWidget);

    // Nothing was written, so there is no file to show.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stash-row-poster')),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
  });

  // The popup is capped at 1000 px, so a value longer than that does not make
  // it as wide as the window.
  testWidgets('the popup is capped at 1000 px wide', (tester) async {
    final applied = <Map<String, String>>[];
    final posters = <String>[];

    // A value wider than the cap, so the width the dialog gets is the cap
    // rather than the text.
    final wide = StashScene(
      id: id,
      title: '',
      code: '',
      details: 'x' * 200,
      releaseDate: '',
      productionDate: '',
      studio: StashStudio.empty,
      parentStudio: StashStudio.empty,
      performers: const [],
      tags: const [],
      images: const [],
    );

    await pumpSection(
      tester,
      _FakeClient(StashSceneSuccess(wide)),
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
    );

    await fetch(tester);

    // The dialog's own box rather than the area the route centres it in, which
    // is the whole window: the ConstrainedBox is the one the dialog builds from
    // the constraints it is given.
    expect(
      tester
          .getSize(
            find.byWidgetPredicate(
              (widget) =>
                  widget is ConstrainedBox &&
                  widget.constraints.maxWidth == 1000,
            ),
          )
          .width,
      1000,
    );
  });

  testWidgets('a failure is shown as a message and nothing is applied', (
    tester,
  ) async {
    final applied = <Map<String, String>>[];
    final posters = <String>[];
    final client = _FakeClient(const StashFailure(StashFailureKind.notFound));

    await pumpSection(
      tester,
      client,
      await settingsWith({'stashdb': 'the-key'}),
      applied,
      posters,
    );

    await fetch(tester);

    expect(find.text('StashDB has no scene with that ID.'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(applied, isEmpty);
    expect(posters, isEmpty);
  });
}

class _FakeClient implements StashClient {
  _FakeClient(this.result);

  final StashResult result;

  final calls = <(String, String)>[];

  @override
  HttpClient get client => HttpClient();

  @override
  Future<StashResult> findScene({
    required String sceneId,
    required String apiKey,
  }) async {
    calls.add((sceneId, apiKey));

    return result;
  }
}

/// A downloader that reaches nothing. It records the paths it was asked to
/// write to and answers with what the test gives it; it writes nothing, so the
/// image the popup shows is the one resolved for the path it returns rather
/// than a file on disk.
class _FakeDownloader implements ImageDownloader {
  _FakeDownloader(this.result);

  final DownloadResult result;

  final paths = <String>[];

  @override
  HttpClient get client => HttpClient();

  @override
  Future<DownloadResult> download(Uri url, String destinationPath) async {
    paths.add(destinationPath);

    // A success reports the file it was asked to write, the way the real one
    // does.
    if (result is DownloadSuccess) {
      return DownloadSuccess(destinationPath, null);
    }

    return result;
  }
}

/// A credential store that does not reach the plugin, so the settings the
/// section reads are the ones the test puts in it.
class _FakeSecretStore implements SecretStore {
  _FakeSecretStore(this.values);

  final Map<String, String> values;

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// settings.json, without the filesystem. The section reads the values only, so
/// the defaults are enough.
class _FakeSettingsStore implements SettingsStore {
  _FakeSettingsStore({required this.appDirectory});

  @override
  final Future<Directory> Function() appDirectory;

  @override
  Future<String> filePath() async => 'settings.json';

  @override
  Future<Settings> load() async => Settings.defaults();

  @override
  Future<void> save(Settings settings) async {}
}

/// An asset bundle that answers from a map, so the domain mapping is what the
/// test gives it rather than the file on disk.
class _FakeBundle extends AssetBundle {
  _FakeBundle(this.contents);

  final Map<String, String> contents;

  @override
  Future<ByteData> load(String key) async {
    final text = contents[key];

    if (text == null) {
      // The shape the real bundle throws, so the service's guard is tested
      // against it rather than against a plain Exception, which `on Exception`
      // would catch and the app would not.
      throw FlutterError('Unable to load asset: "$key".');
    }

    return ByteData.sublistView(utf8.encode(text));
  }
}
