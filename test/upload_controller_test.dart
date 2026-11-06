import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/release/release_store.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/tracker.dart';
import 'package:release_prepper/feature/screenshots/images.dart';
import 'package:release_prepper/feature/screenshots/images_store.dart';
import 'package:release_prepper/feature/settings/settings.dart';
import 'package:release_prepper/feature/upload/hosters.dart';
import 'package:release_prepper/feature/upload/upload_controller.dart';
import 'package:release_prepper/service/native_tools/tool_runner.dart';
import 'package:release_prepper/service/native_tools/uptooda.dart';

import 'test_runner.dart';

void main() {
  Release releaseFor(String directoryPath) => Release(
    name: 'x',
    directoryPath: directoryPath,
    tracker: Tracker.pornolab,
    releaseType: ReleaseType.singleVideo,
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

  // The controller is given the registry records, not names, because the call
  // needs the hoster's `service`. The tests take them from the registry so they
  // test the same data the app uses (`ai/upload_images.md`).
  Hoster hosterNamed(String name) =>
      hosters.firstWhere((hoster) => hoster.name == name);

  // The skip rule (`ai/upload_images.md`): an image already uploaded to a
  // hoster is skipped, one that failed is tried again because nothing was
  // recorded for it, and a hoster that is not selected is never attempted. The
  // work list is in the order the file lists the records.
  test('an image already uploaded to a hoster is skipped', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final store = ImagesStore();
    await store.save(
      directory.path,
      ImagesManifest(
        images: [
          record(ImageKind.poster, '_rp_poster.jpg', {
            'fastpic.org': {'direct_url': 'https://example.com/poster'},
          }),
          record(
            ImageKind.screenshot,
            'images/movie.mp4/_rp_screenshot01.jpg',
            {},
          ),
          record(
            ImageKind.screenlist,
            'images/movie.mp4/_rp_screenlist.jpg',
            {},
          ),
        ],
      ),
    );

    final uptooda = _FakeUptooda(failures: const {});
    final progress = <UploadProgress>[];

    final result =
        await UploadController(
          release: releaseFor(directory.path),
          uptooda: uptooda,
          store: store,
          releaseStore: ReleaseStore(),
        ).upload(
          selected: [hosterNamed('fastpic.org')],
          secrets: const {},
          onProgress: progress.add,
        );

    expect(result, isA<UploadSuccess>());

    // The poster is not called because it is already recorded for this hoster;
    // the screenshot and the screenlist are, in the order the file lists them.
    expect(uptooda.calls['fastpic.org'], [
      p.join(directory.path, 'images/movie.mp4/_rp_screenshot01.jpg'),
      p.join(directory.path, 'images/movie.mp4/_rp_screenlist.jpg'),
    ]);

    // The bar counts against the images in the release, so the already-uploaded
    // poster is in the state the run starts from, and the run continues from
    // it.
    expect(progress.map((report) => (report.done, report.total)), [
      (1, 3),
      (2, 3),
      (3, 3),
    ]);

    directory.deleteSync(recursive: true);
  });

  // The state the bars show when the section is opened (`ai/upload_images.md`):
  // what each hoster has over the images in the release, for every hoster in
  // the registry, so a bar exists for a hoster that cannot run.
  test(
    'the state read at open is what images.json holds, for every hoster',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );

      final store = ImagesStore();
      await store.save(
        directory.path,
        ImagesManifest(
          images: [
            record(ImageKind.poster, '_rp_poster.jpg', {
              for (final hoster in hosters)
                hoster.name: {'direct_url': 'https://example.com/poster'},
            }),
            record(
              ImageKind.screenshot,
              'images/movie.mp4/_rp_screenshot01.jpg',
              {
                'fastpic.org': {'direct_url': 'https://example.com/screenshot'},
              },
            ),
          ],
        ),
      );

      final progress = UploadController(
        release: releaseFor(directory.path),
        uptooda: _FakeUptooda(failures: const {}),
        store: store,
        releaseStore: ReleaseStore(),
      ).progress();

      expect(progress.keys, [for (final hoster in hosters) hoster.name]);

      // The first hoster has both images, so it is full; the others have one of
      // the two.
      for (final hoster in hosters) {
        expect(progress[hoster.name]!.done, hoster == hosters.first ? 2 : 1);
        expect(progress[hoster.name]!.total, 2);
      }

      directory.deleteSync(recursive: true);
    },
  );

  test('a hoster that is not selected is never attempted', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final store = ImagesStore();
    await store.save(
      directory.path,
      ImagesManifest(
        images: [
          record(
            ImageKind.screenshot,
            'images/movie.mp4/_rp_screenshot01.jpg',
            {},
          ),
        ],
      ),
    );

    final uptooda = _FakeUptooda(failures: const {});

    await UploadController(
      release: releaseFor(directory.path),
      uptooda: uptooda,
      store: store,
      releaseStore: ReleaseStore(),
    ).upload(
      selected: [hosterNamed('fastpic.org')],
      secrets: const {},
      onProgress: (_) {},
    );

    expect(uptooda.calls.keys, ['fastpic.org']);
    expect(uptooda.calls['turboimagehost.com'], isNull);

    directory.deleteSync(recursive: true);
  });

  // A failed upload is not recorded, so the bar shows what was uploaded and
  // stays below full (`ai/upload_images.md`).
  test(
    'a failed upload does not count in the progress and is not recorded',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );

      const file = 'images/movie.mp4/_rp_screenshot01.jpg';
      const failed = 'images/movie.mp4/_rp_screenshot02.jpg';

      final store = ImagesStore();
      await store.save(
        directory.path,
        ImagesManifest(
          images: [
            record(ImageKind.screenshot, file, {}),
            record(ImageKind.screenshot, failed, {}),
          ],
        ),
      );

      final uptooda = _FakeUptooda(failures: {p.join(directory.path, failed)});
      final progress = <UploadProgress>[];

      await UploadController(
        release: releaseFor(directory.path),
        uptooda: uptooda,
        store: store,
        releaseStore: ReleaseStore(),
      ).upload(
        selected: [hosterNamed('fastpic.org')],
        secrets: const {},
        onProgress: progress.add,
      );

      expect(progress.map((report) => (report.done, report.total)), [
        (0, 2),
        (1, 2),
        (1, 2),
      ]);

      final manifest = await store.load(directory.path);

      expect(manifest.images.first.urls['fastpic.org'], isNotNull);
      expect(manifest.images.last.urls['fastpic.org'], isNull);

      directory.deleteSync(recursive: true);
    },
  );

  // One image at a time per hoster, several hosters at the same time. The fake
  // counts what is in flight, so the rule is what is asserted rather than the
  // order.
  test('one image at a time per hoster, hosters at the same time', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final store = ImagesStore();
    await store.save(
      directory.path,
      ImagesManifest(
        images: [
          for (var n = 1; n <= 2; n++)
            record(
              ImageKind.screenshot,
              'images/movie.mp4/_rp_screenshot0$n.jpg',
              {},
            ),
        ],
      ),
    );

    final uptooda = _FakeUptooda(failures: const {});

    await UploadController(
      release: releaseFor(directory.path),
      uptooda: uptooda,
      store: store,
      releaseStore: ReleaseStore(),
    ).upload(
      selected: [hosterNamed('fastpic.org'), hosterNamed('turboimagehost.com')],
      secrets: const {},
      onProgress: (_) {},
    );

    expect(uptooda.maxInFlightPerHoster, 1);
    expect(uptooda.maxInFlightTotal, 2);

    directory.deleteSync(recursive: true);
  });

  // A hoster with nothing to do is complete: the bar is what shows it, so the
  // report is still made.
  test('a hoster with nothing to upload reports a complete run', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final store = ImagesStore();
    await store.save(directory.path, ImagesManifest(images: const []));

    final progress = <UploadProgress>[];

    await UploadController(
      release: releaseFor(directory.path),
      uptooda: _FakeUptooda(failures: const {}),
      store: store,
      releaseStore: ReleaseStore(),
    ).upload(
      selected: [hosterNamed('fastpic.org')],
      secrets: const {},
      onProgress: progress.add,
    );

    expect(progress, hasLength(1));
    expect(progress.first.hoster, 'fastpic.org');
    expect(progress.first.done, 0);
    expect(progress.first.total, 0);

    directory.deleteSync(recursive: true);
  });

  test('the tool not being in the bundle is reported', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    const file = 'images/movie.mp4/_rp_screenshot01.jpg';

    final store = ImagesStore();
    await store.save(
      directory.path,
      ImagesManifest(images: [record(ImageKind.screenshot, file, {})]),
    );

    final result =
        await UploadController(
          release: releaseFor(directory.path),
          uptooda: _FakeUptooda(
            failures: {p.join(directory.path, file)},
            failureKind: UptoodaUploadFailureKind.toolNotAvailable,
          ),
          store: store,
          releaseStore: ReleaseStore(),
        ).upload(
          selected: [hosterNamed('fastpic.org')],
          secrets: const {},
          onProgress: (_) {},
        );

    expect(
      result,
      isA<UploadFailure>().having(
        (failure) => failure.kind,
        'kind',
        UploadFailureKind.toolNotAvailable,
      ),
    );

    directory.deleteSync(recursive: true);
  });

  // The URLs are written to images.json after each upload, so a run that is
  // stopped keeps what it already uploaded.
  test('a successful upload is written to images.json', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    const file = 'images/movie.mp4/_rp_screenshot01.jpg';

    final store = ImagesStore();
    await store.save(
      directory.path,
      ImagesManifest(images: [record(ImageKind.screenshot, file, {})]),
    );

    await UploadController(
      release: releaseFor(directory.path),
      uptooda: _FakeUptooda(failures: const {}),
      store: store,
      releaseStore: ReleaseStore(),
    ).upload(
      selected: [hosterNamed('fastpic.org'), hosterNamed('turboimagehost.com')],
      secrets: const {},
      onProgress: (_) {},
    );

    final written = jsonDecode(
      await File(p.join(directory.path, 'images.json')).readAsString(),
    ) as Map<String, dynamic>;

    expect(written['schema'], schemaVersion);
    expect(written['images'], [
      {
        'item': 'movie.mp4',
        'kind': 'screenshot',
        'file': file,
        'urls': {
          'fastpic.org': {
            for (final field in Uptooda.urlFields)
              field: 'https://example.com/fastpic.org/$field',
          },
          'turboimagehost.com': {
            for (final field in Uptooda.urlFields)
              field: 'https://example.com/turboimagehost.com/$field',
          },
        },
      },
    ]);

    directory.deleteSync(recursive: true);
  });

  // A poster belongs to the release rather than to an item, so its record is
  // the one with no item (`ai/release_structure.md` §4).
  test('a poster record has no item', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final store = ImagesStore();
    await store.save(
      directory.path,
      ImagesManifest(images: [record(ImageKind.poster, '_rp_poster.jpg', {})]),
    );

    await UploadController(
      release: releaseFor(directory.path),
      uptooda: _FakeUptooda(failures: const {}),
      store: store,
      releaseStore: ReleaseStore(),
    ).upload(
      selected: [hosterNamed('fastpic.org')],
      secrets: const {},
      onProgress: (_) {},
    );

    final written = jsonDecode(
      await File(p.join(directory.path, 'images.json')).readAsString(),
    ) as Map<String, dynamic>;

    expect((written['images'] as List).first['item'], isNull);

    directory.deleteSync(recursive: true);
  });

  // A credential goes through the environment, and only for the hosters whose
  // script reads it (`ai/bundled_native_tools.md`). That is what
  // `Hoster.field` is, so this is the rule as data: fastpic has none,
  // postimages has one.
  test(
    'the environment is built only for the hosters that need a credential',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );

      final store = ImagesStore();
      await store.save(
        directory.path,
        ImagesManifest(
          images: [record(ImageKind.poster, '_rp_poster.jpg', {})],
        ),
      );

      final uptooda = _FakeUptooda(failures: const {});

      await UploadController(
        release: releaseFor(directory.path),
        uptooda: uptooda,
        store: store,
        releaseStore: ReleaseStore(),
      ).upload(
        selected: [hosterNamed('fastpic.org'), hosterNamed('postimages.org')],
        secrets: {SettingsField.postimages.name: 'the-key'},
        onProgress: (_) {},
      );

      expect(uptooda.environments['fastpic.org'], const {});
      expect(uptooda.environments['postimages.org'], {
        Uptooda.apiKeyVariable: 'the-key',
      });

      directory.deleteSync(recursive: true);
    },
  );

  // An empty value is not passed as a variable. The section does not offer a
  // hoster that needs a credential as selected while its value is empty, so
  // this is the same rule from the controller's side: nothing reaches the tool
  // as an empty environment.
  test('an empty value is not passed', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final store = ImagesStore();
    await store.save(
      directory.path,
      ImagesManifest(images: [record(ImageKind.poster, '_rp_poster.jpg', {})]),
    );

    final uptooda = _FakeUptooda(failures: const {});

    await UploadController(
      release: releaseFor(directory.path),
      uptooda: uptooda,
      store: store,
      releaseStore: ReleaseStore(),
    ).upload(
      selected: [hosterNamed('postimages.org')],
      secrets: {SettingsField.postimages.name: ''},
      onProgress: (_) {},
    );

    expect(uptooda.environments['postimages.org'], const {});

    directory.deleteSync(recursive: true);
  });

  // The last-edit stamp (`ai/release_structure.md` §3) is the record of the
  // release changing, so it is written by a run that wrote a record and not by
  // one that wrote nothing.
  test('a run that wrote a record stamps the last edit, one that wrote nothing does not', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final store = ImagesStore();
    final releaseStore = _RecordingReleaseStore();
    final release = releaseFor(directory.path);

    // The record is already uploaded to this hoster, so the run is skipped and
    // nothing changes.
    await store.save(
      directory.path,
      ImagesManifest(
        images: [
          record(ImageKind.poster, '_rp_poster.jpg', {
            'fastpic.org': {'direct_url': 'https://example.com/poster'},
          }),
        ],
      ),
    );

    await UploadController(
      release: release,
      uptooda: _FakeUptooda(failures: const {}),
      store: store,
      releaseStore: releaseStore,
    ).upload(
      selected: [hosterNamed('fastpic.org')],
      secrets: const {},
      onProgress: (_) {},
    );

    expect(releaseStore.stamps, isEmpty);

    // A record with nothing for the hoster is work, and writing it is a change
    // to the release.
    await store.save(
      directory.path,
      ImagesManifest(images: [record(ImageKind.poster, '_rp_poster.jpg', {})]),
    );

    await UploadController(
      release: release,
      uptooda: _FakeUptooda(failures: const {}),
      store: store,
      releaseStore: releaseStore,
    ).upload(
      selected: [hosterNamed('fastpic.org')],
      secrets: const {},
      onProgress: (_) {},
    );

    expect(releaseStore.stamps, hasLength(1));

    directory.deleteSync(recursive: true);
  });
}

/// A store that records the stamps, which is what the test is about. The rest
/// of it is not used by the controller.
class _RecordingReleaseStore implements ReleaseStore {
  final stamps = <Release>[];

  @override
  Future<Release> create({
    required String savePath,
    required String name,
    required Tracker tracker,
    required ReleaseType releaseType,
    required bool torrentPrivate,
    required bool includeAppSignature,
  }) async => throw UnsupportedError('this test does not create a release');

  @override
  Future<Release> load(String directoryPath) async =>
      throw UnsupportedError('this test does not load a release');

  @override
  Future<void> save(Release release) async {}

  @override
  Future<bool> touchLastEdit(Release release) async {
    stamps.add(release);
    return true;
  }
}

class _FakeUptooda implements Uptooda {
  _FakeUptooda({
    required this.failures,
    this.failureKind = UptoodaUploadFailureKind.uploadFailed,
  });

  /// The file paths that do not upload.
  final Set<String> failures;

  final UptoodaUploadFailureKind failureKind;

  final calls = <String, List<String>>{};

  /// What each hoster's calls were given as their environment.
  final environments = <String, Map<String, String>>{};

  int maxInFlightPerHoster = 0;
  int maxInFlightTotal = 0;

  final _inFlightPerHoster = <String, int>{};
  int _inFlightTotal = 0;

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

    _inFlightTotal += 1;
    _inFlightPerHoster[hoster] = (_inFlightPerHoster[hoster] ?? 0) + 1;

    if (_inFlightTotal > maxInFlightTotal) maxInFlightTotal = _inFlightTotal;
    if (_inFlightPerHoster[hoster]! > maxInFlightPerHoster) {
      maxInFlightPerHoster = _inFlightPerHoster[hoster]!;
    }

    // A call that does something takes time, so the hosters overlap.
    await Future<void>.delayed(const Duration(milliseconds: 5));

    _inFlightTotal -= 1;
    _inFlightPerHoster[hoster] = _inFlightPerHoster[hoster]! - 1;

    if (failures.contains(filePath)) {
      return UptoodaUploadFailure(failureKind);
    }

    return UptoodaUploadSuccess({
      for (final field in Uptooda.urlFields)
        field: 'https://example.com/$hoster/$field',
    });
  }
}
