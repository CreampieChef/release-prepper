import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/tracker.dart';
import 'package:release_prepper/feature/section_title.dart';
import 'package:release_prepper/feature/torrent/torrent_section.dart';
import 'package:release_prepper/l10n/app_localizations.dart';
import 'package:release_prepper/service/launcher/folder_opener.dart';
import 'package:release_prepper/service/native_tools/mkbrr.dart';

import 'test_runner.dart';

// The wrapper answers with the result the test gives instead of running the tool.
// Only `create()` is overridden, so the arguments stay the ones the app builds.
class _FakeMkbrr extends Mkbrr {
  _FakeMkbrr(this.result, {this.progress = const []})
    : super(runner: testRunner());

  final MkbrrResult result;

  /// What the run reports while it works.
  final List<MkbrrProgress> progress;

  /// Set when a test wants to look at the section while the run is going.
  Completer<void>? gate;

  /// What each call was given, as the source and the output path.
  final calls = <List<String>>[];

  @override
  Future<MkbrrResult> create({
    required String releaseDirectory,
    required String sourcePath,
    required String outputPath,
    required void Function(MkbrrProgress progress) onProgress,
  }) async {
    calls.add([sourcePath, outputPath]);

    for (final segment in progress) {
      onProgress(segment);
    }

    if (gate != null) await gate!.future;

    return result;
  }
}

// The opener answers with the result the test gives instead of asking the OS.
class _FakeFolderOpener extends FolderOpener {
  _FakeFolderOpener(this.result);

  final OpenFolderResult result;

  /// The folders each call asked for.
  final calls = <String>[];

  @override
  Future<OpenFolderResult> open(String directory) async {
    calls.add(directory);

    return result;
  }
}

// The editor registers this section's rebuild. A test that does not look at what
// the source row says does not need it, so it ignores it. A default parameter
// must be a constant, so this is a named function rather than a lambda.
void ignoreSourceChanged(void Function() rebuild) {}

void main() {
  final release = Release(
    name: 'my release',
    directoryPath: '/tmp/release_prepper_test',
    tracker: Tracker.pornolab,
    releaseType: ReleaseType.singleVideo,
    source: '/home/user/videos/movie.mp4',
    fields: FieldValues(),
    items: [
      ReleaseItem(
        path: 'movie.mp4',
        type: itemTypeVideo,
        fields: FieldValues(),
      ),
    ],
  );

  Widget app({
    required _FakeMkbrr mkbrr,
    required _FakeFolderOpener opener,
    required Release release,
    // The editor registers this section's rebuild; a test that does not look at
    // what the source row says does not need it, so the default is the no-op
    // above.
    void Function(void Function()) subscribeSourceChanged = ignoreSourceChanged,
  }) => MultiProvider(
    providers: [
      Provider<Mkbrr>(create: (_) => mkbrr),
      Provider<FolderOpener>(create: (_) => opener),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: TorrentSection(
            release: release,
            subscribeSourceChanged: subscribeSourceChanged,
          ),
        ),
      ),
    ),
  );

  // One run per test: the section keeps the outcome as its own state, so a test
  // that ran once and then pumped the same widget again would still show the
  // first run's outcome.
  Future<void> run(
    WidgetTester tester,
    AppLocalizations l10n,
    MkbrrResult result, {
    _FakeFolderOpener? opener,
  }) async {
    await tester.pumpWidget(
      app(
        mkbrr: _FakeMkbrr(result),
        opener: opener ?? _FakeFolderOpener(const FolderOpened()),
        release: release,
      ),
    );

    await tester.tap(find.text(l10n.torrentButton));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the title row has the Create button, and there is no bar before a run',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.pumpWidget(
        app(
          mkbrr: _FakeMkbrr(const MkbrrCreated(path: 'out.torrent')),
          opener: _FakeFolderOpener(const FolderOpened()),
          release: release,
        ),
      );

      expect(find.byType(SectionTitle), findsOneWidget);
      expect(find.text(l10n.torrentSectionTitle), findsOneWidget);
      expect(find.text(l10n.torrentButton), findsOneWidget);

      // Nothing has run, so there is nothing to show.
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  // With no source picked there is nothing to hash, so the title row has no
  // action and the section says what has to happen first instead. Which of the
  // two wordings it says is the release type's rule (`release_fields.dart`): the
  // single video type picks a file, a pack picks a folder.
  testWidgets('with no source picked the section says what to pick first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      app(
        mkbrr: _FakeMkbrr(const MkbrrNotPresent()),
        opener: _FakeFolderOpener(const FolderOpened()),
        release: Release(
          name: 'my release',
          directoryPath: '/tmp/release_prepper_test',
          tracker: Tracker.pornolab,
          releaseType: ReleaseType.singleVideo,
          source: '',
          fields: FieldValues(),
          items: [],
        ),
      ),
    );

    expect(find.text(l10n.torrentButton), findsNothing);
    expect(find.text(l10n.torrentPickFileFirst), findsOneWidget);
  });

  testWidgets('a type that picks a folder says so', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      app(
        mkbrr: _FakeMkbrr(const MkbrrNotPresent()),
        opener: _FakeFolderOpener(const FolderOpened()),
        release: Release(
          name: 'my release',
          directoryPath: '/tmp/release_prepper_test',
          tracker: Tracker.pornolab,
          releaseType: ReleaseType.videoPack,
          source: '',
          fields: FieldValues(),
          items: [],
        ),
      ),
    );

    expect(find.text(l10n.torrentPickFolderFirst), findsOneWidget);
  });

  // The source row is not part of this section, and typing in it does not rebuild
  // the editor, so the section is only updated through the rebuild it registered
  // (`ai/torrents.md`).
  testWidgets('the button appears when the editor says a source was picked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    void Function()? rebuild;

    final picked = Release(
      name: 'my release',
      directoryPath: '/tmp/release_prepper_test',
      tracker: Tracker.pornolab,
      releaseType: ReleaseType.singleVideo,
      source: '',
      fields: FieldValues(),
      items: [],
    );

    await tester.pumpWidget(
      app(
        mkbrr: _FakeMkbrr(const MkbrrNotPresent()),
        opener: _FakeFolderOpener(const FolderOpened()),
        release: picked,
        subscribeSourceChanged: (callback) => rebuild = callback,
      ),
    );

    expect(find.text(l10n.torrentButton), findsNothing);

    // The path is written to the model, and the editor tells this section.
    picked.source = '/home/user/videos/movie.mp4';

    rebuild!();
    await tester.pump();

    expect(find.text(l10n.torrentButton), findsOneWidget);
    expect(find.text(l10n.torrentPickFileFirst), findsNothing);
  });

  testWidgets(
    'the bar shows the percentage as the tool reports it, and the button is '
    'disabled while the run is going',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      final mkbrr = _FakeMkbrr(
        const MkbrrCreated(path: 'out.torrent'),
        progress: [const MkbrrProgress(percent: 78)],
      );

      // The run is held so the section can be looked at while it works.
      final gate = Completer<void>();
      mkbrr.gate = gate;

      await tester.pumpWidget(
        app(
          mkbrr: mkbrr,
          opener: _FakeFolderOpener(const FolderOpened()),
          release: release,
        ),
      );

      await tester.tap(find.text(l10n.torrentButton));

      // One frame, not a settled one: the run has not ended.
      await tester.pump();

      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.78,
      );
      expect(find.text(l10n.torrentProgress(78)), findsOneWidget);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l10n.torrentButton),
      );
      expect(button.onPressed, null);

      gate.complete();
      await tester.pumpAndSettle();

      // The run ended, so the outcome is shown with the bar.
      expect(find.text(l10n.torrentCreated('out.torrent')), findsOneWidget);
    },
  );

  // The rate and the remaining time are shown as the tool gives them, each on
  // its own line, and only when the segment had it.
  testWidgets('what the tool reports while it works is shown with the bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final mkbrr = _FakeMkbrr(
      const MkbrrCreated(path: 'out.torrent'),
      progress: [
        const MkbrrProgress(percent: 78, speed: '3.7 GiB/s', eta: '2m 3s'),
      ],
    );

    final gate = Completer<void>();
    mkbrr.gate = gate;

    await tester.pumpWidget(
      app(
        mkbrr: mkbrr,
        opener: _FakeFolderOpener(const FolderOpened()),
        release: release,
      ),
    );

    await tester.tap(find.text(l10n.torrentButton));
    await tester.pump();

    expect(find.text(l10n.torrentProgress(78)), findsOneWidget);
    expect(find.text(l10n.torrentSpeed('3.7 GiB/s')), findsOneWidget);
    expect(find.text(l10n.torrentEta('2m 3s')), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a segment that reports no rate shows no line for it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final mkbrr = _FakeMkbrr(
      const MkbrrCreated(path: 'out.torrent'),
      progress: [const MkbrrProgress(percent: 40)],
    );

    final gate = Completer<void>();
    mkbrr.gate = gate;

    await tester.pumpWidget(
      app(
        mkbrr: mkbrr,
        opener: _FakeFolderOpener(const FolderOpened()),
        release: release,
      ),
    );

    await tester.tap(find.text(l10n.torrentButton));
    await tester.pump();

    expect(find.text(l10n.torrentProgress(40)), findsOneWidget);

    // The lines are built only from a value the segment had, so the English
    // strings the loaded delegate gives appear nowhere.
    expect(find.textContaining('Speed:'), findsNothing);
    expect(find.textContaining('ETA:'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('the output is the release name in the release directory', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final mkbrr = _FakeMkbrr(const MkbrrCreated(path: 'out.torrent'));

    await tester.pumpWidget(
      app(
        mkbrr: mkbrr,
        opener: _FakeFolderOpener(const FolderOpened()),
        release: release,
      ),
    );

    await tester.tap(find.text(l10n.torrentButton));
    await tester.pumpAndSettle();

    expect(mkbrr.calls.first, [
      '/home/user/videos/movie.mp4',
      '/tmp/release_prepper_test/my release.torrent',
    ]);
  });

  testWidgets('a run that wrote the file says where', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await run(tester, l10n, const MkbrrCreated(path: 'out.torrent'));

    expect(find.text(l10n.torrentCreated('out.torrent')), findsOneWidget);
  });

  // A release opened again can already have the file, and the app records
  // nothing for it, so the section says what it finds on disk before any run.
  testWidgets('a release whose file is already on disk says so', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    File('${directory.path}/my release.torrent').writeAsBytesSync([1]);

    await tester.pumpWidget(
      app(
        mkbrr: _FakeMkbrr(const MkbrrNotPresent()),
        opener: _FakeFolderOpener(const FolderOpened()),
        release: Release(
          name: 'my release',
          directoryPath: directory.path,
          tracker: Tracker.pornolab,
          releaseType: ReleaseType.singleVideo,
          source: '/home/user/videos/movie.mp4',
          fields: FieldValues(),
          items: [],
        ),
      ),
    );

    expect(
      find.text(
        l10n.torrentAlreadyCreated('${directory.path}/my release.torrent'),
      ),
      findsOneWidget,
    );

    directory.deleteSync(recursive: true);
  });

  // A file under another name is not the one this release would write, so it is
  // not what the section reports.
  testWidgets('a file named after an older release name is not reported', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    File('${directory.path}/older name.torrent').writeAsBytesSync([1]);

    await tester.pumpWidget(
      app(
        mkbrr: _FakeMkbrr(const MkbrrNotPresent()),
        opener: _FakeFolderOpener(const FolderOpened()),
        release: Release(
          name: 'my release',
          directoryPath: directory.path,
          tracker: Tracker.pornolab,
          releaseType: ReleaseType.singleVideo,
          source: '/home/user/videos/movie.mp4',
          fields: FieldValues(),
          items: [],
        ),
      ),
    );

    expect(
      find.text(
        l10n.torrentAlreadyCreated('${directory.path}/older name.torrent'),
      ),
      findsNothing,
    );

    directory.deleteSync(recursive: true);
  });

  // The path the section shows is text that opens the folder it is in.
  testWidgets('the path is a link that opens the release directory', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final opener = _FakeFolderOpener(const FolderOpened());

    await run(
      tester,
      l10n,
      const MkbrrCreated(path: 'out.torrent'),
      opener: opener,
    );

    expect(
      find.widgetWithText(TextButton, '/tmp/release_prepper_test'),
      findsOneWidget,
    );

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(opener.calls, ['/tmp/release_prepper_test']);
    expect(find.text(l10n.folderOpenFailed), findsNothing);
  });

  testWidgets('a folder that could not be opened says so', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final opener = _FakeFolderOpener(const FolderOpenFailed());

    await tester.pumpWidget(
      app(
        mkbrr: _FakeMkbrr(const MkbrrCreated(path: 'out.torrent')),
        opener: opener,
        release: release,
      ),
    );

    await tester.tap(find.text(l10n.torrentButton));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(TextButton, '/tmp/release_prepper_test'),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.folderOpenFailed), findsOneWidget);
  });

  // There is no path before anything has run or been found, so there is no link.
  testWidgets('there is no link while nothing has run and no file is found', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      app(
        mkbrr: _FakeMkbrr(const MkbrrNotPresent()),
        opener: _FakeFolderOpener(const FolderOpened()),
        release: release,
      ),
    );

    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('a tool that is not in the bundle is shown as such', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await run(tester, l10n, const MkbrrNotPresent());

    expect(find.text(l10n.mkbrrNotAvailable), findsOneWidget);
  });

  testWidgets('a run that exited with a non-zero code says the code', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await run(tester, l10n, const MkbrrRunFailed(exitCode: 1));

    expect(find.text(l10n.mkbrrRunFailed(1)), findsOneWidget);
  });

  testWidgets('a run stopped by the timeout is shown as such', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await run(tester, l10n, const MkbrrRunTimeout());

    expect(find.text(l10n.mkbrrRunTimeout), findsOneWidget);
  });
}
