import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/feature/recent_releases/recent_releases_controller.dart';
import 'package:release_prepper/feature/recent_releases/recent_releases_store.dart';
import 'package:release_prepper/feature/release/release_store.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/release_wizard_controller.dart';
import 'package:release_prepper/feature/release/tracker.dart';
import 'package:release_prepper/feature/tab/tab_manager.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'release_wizard_controller_test',
    );
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  Map<String, dynamic> readJson(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  // The defaults are what the widget reads from the settings and passes here,
  // so the controller is the point where they reach the manifest. It is also
  // the point where the rule shows: a release is built with the values it was
  // given, and changing what the settings say afterwards does not change a
  // release that was already built.
  test('a new release is created with the defaults it was given, and an existing '
      'release keeps its own', () async {
    final before = ReleaseWizardController(
      store: ReleaseStore(),
      defaultReleaseDirectory: directory.path,
      defaultTorrentPrivate: true,
      defaultIncludeAppSignature: true,
      recentReleases: RecentReleasesController(
        store: RecentReleasesStore(appDirectory: () async => directory),
        tabManager: TabManager(),
      ),
    );

    final first = await before.create(
      savePath: directory.path,
      name: 'first',
      tracker: Tracker.pornolab,
      releaseType: ReleaseType.singleVideo,
    );

    expect(first, isNotNull);

    final after = ReleaseWizardController(
      store: ReleaseStore(),
      defaultReleaseDirectory: directory.path,
      defaultTorrentPrivate: false,
      defaultIncludeAppSignature: false,
      recentReleases: RecentReleasesController(
        store: RecentReleasesStore(appDirectory: () async => directory),
        tabManager: TabManager(),
      ),
    );

    final second = await after.create(
      savePath: directory.path,
      name: 'second',
      tracker: Tracker.pornolab,
      releaseType: ReleaseType.singleVideo,
    );

    expect(second, isNotNull);

    expect(
      readJson(p.join(second!.directoryPath, 'release.json')),
      isA<Map<String, dynamic>>()
          .having((json) => json['torrentPrivate'], 'torrentPrivate', false)
          .having(
            (json) => json['includeAppSignature'],
            'includeAppSignature',
            false,
          ),
    );

    // The release made while the defaults were on is still what it was when it
    // was made: the flag is read from its own manifest, not from the settings.
    final reloaded = await ReleaseStore().load(first!.directoryPath);

    expect(reloaded.torrentPrivate, isTrue);
    expect(reloaded.includeAppSignature, isTrue);

    before.dispose();
    after.dispose();
  });
}
