import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/feature/message/message_controller.dart';
import 'package:release_prepper/feature/recent_releases/recent_releases_controller.dart';
import 'package:release_prepper/feature/recent_releases/recent_releases_store.dart';
import 'package:release_prepper/feature/release/clone_wizard_controller.dart';
import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/release/release_store.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/release_wizard_controller.dart';
import 'package:release_prepper/feature/release/tracker.dart';
import 'package:release_prepper/feature/screenshots/images.dart';
import 'package:release_prepper/feature/screenshots/images_store.dart';
import 'package:release_prepper/feature/tab/tab_manager.dart';

/// A manifest that cannot be written, so a copy fails after the folder was
/// made. This is the fake the rollback test uses.
class FailingImagesStore extends ImagesStore {
  @override
  Future<void> save(String directoryPath, ImagesManifest manifest) async {
    throw Exception('the manifest cannot be written');
  }
}

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('clone_controller_test');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  Map<String, dynamic> readJson(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  // The source is a release as the app writes one, with the values the user
  // typed and the values the probe wrote, so the copy is tested against a
  // release shaped like one on disk.
  Future<Release> sourceRelease() async {
    final store = ReleaseStore();

    final source = await store.create(
      savePath: directory.path,
      name: 'source',
      tracker: Tracker.pornolab,
      releaseType: ReleaseType.singleVideo,
      // The flags off, so the copy is tested against a source that is not in
      // the state a new release starts with: what the copy takes is the
      // source's, not the default.
      torrentPrivate: false,
      includeAppSignature: false,
    );

    source.fields.setValue('cast', 'Alice');
    source.fields.setValue('videoTitle', 'Title');
    source.fields.setValue('sceneUrl', 'https://stashdb.org/scenes/1');

    // What the Upload draft feature stores: the forum is a value the user typed,
    // the link is a value a run wrote.
    source.fields.setValue(
      'parentForum',
      'https://pornolab.net/forum/posting.php?mode=newtopic&f=1013',
    );
    source.fields.setValue(
      'draftUrl',
      'https://pornolab.net/forum/posting.php?mode=newtopic&f=1013&draft=42',
    );

    // The fields the app fills from the movie file, so a clone cannot keep
    // them: they describe a different video.
    source.fields.setValue('fileSize', '1024');
    source.fields.setValue('duration', '00:12:34');

    await store.save(source);

    return source;
  }

  CloneWizardController cloneController(
    Release source, {
    ImagesStore? images,
    RecentReleasesController? recentReleases,
  }) => CloneWizardController(
    source: source,
    store: ReleaseStore(),
    images: images ?? ImagesStore(),
    recentReleases:
        recentReleases ??
        RecentReleasesController(
          store: RecentReleasesStore(appDirectory: () async => directory),
          tabManager: TabManager(),
        ),
  );

  Future<CloneCreationSuccess> createClone(
    Release source, {
    String name = 'clone',
  }) async {
    final result = await cloneController(source)
        .create(savePath: directory.path, name: name);

    expect(result, isA<CloneCreationSuccess>());

    return result as CloneCreationSuccess;
  }

  test('the fields the user writes are copied, and the ones the app fills from '
      'the movie file are not', () async {
    final source = await sourceRelease();
    final clone = await createClone(source);

    final saved = readJson(p.join(clone.release.directoryPath, 'release.json'));
    final fields = saved['fields'] as Map<String, dynamic>;

    expect(fields['cast'], 'Alice');
    expect(fields['videoTitle'], 'Title');

    // `sceneUrl` has no form row, but it is a value the user wrote, so it is
    // copied like the fields that do have one.
    expect(fields['sceneUrl'], 'https://stashdb.org/scenes/1');

    // A new release starts with the defaults of its type, and the probe's
    // fields are empty until it runs on the clone's own video.
    expect(fields['fileSize'], '');
    expect(fields['duration'], '');
    expect(fields['videoQuality'], 'SiteRip');

    // The clone is the same release with a different video, so the tracker
    // and the type are the source's.
    expect(saved['tracker'], 'pornolab');
    expect(saved['releaseType'], 'singleVideo');
  });

  // A value a run wrote is not copied, because it belongs to that run: the draft
  // link names the topic the source's draft was saved as, so a clone that kept it
  // would point at a draft it did not make. The forum is what the user typed, so
  // it is copied and the next run there is made in the same forum.
  test('the draft link is not copied, the parent forum is', () async {
    final source = await sourceRelease();
    final clone = await createClone(source);

    final saved = readJson(p.join(clone.release.directoryPath, 'release.json'));
    final fields = saved['fields'] as Map<String, dynamic>;

    expect(fields['parentForum'], source.fields.value('parentForum'));
    expect(fields['draftUrl'], '');
  });

  // The two flags are the source's, not the settings' defaults: the clone is
  // the same scene at another resolution, so the post it writes and the torrent
  // it builds are expected to be like the source's. What the settings say about
  // new releases is what a release made from the wizard gets.
  test('the two flags are copied from the source', () async {
    final source = await sourceRelease();
    final clone = await createClone(source);

    final saved = readJson(p.join(clone.release.directoryPath, 'release.json'));

    expect(saved['torrentPrivate'], isFalse);
    expect(saved['includeAppSignature'], isFalse);

    // The copy does not change the source.
    expect(source.torrentPrivate, isFalse);
    expect(source.includeAppSignature, isFalse);
  });

  test(
    'the poster record is copied with its URLs, and no other record is',
    () async {
      final source = await sourceRelease();

      final images = ImagesStore();
      await images.save(
        source.directoryPath,
        ImagesManifest(
          images: [
            ImageRecord(
              item: null,
              kind: ImageKind.poster,
              file: '_rp_poster.jpg',
              urls: {
                posterHoster: {posterUrlType: 'https://fastpic.org/1.jpg'},
                'other': {imageUrlType: 'https://example.com/1'},
              },
            ),
            ImageRecord(
              item: 'video',
              kind: ImageKind.screenshot,
              file: 'images/video/_rp_screenshot01.jpg',
              urls: {
                posterHoster: {posterUrlType: 'https://fastpic.org/2.jpg'},
              },
            ),
          ],
        ),
      );

      final clone = await createClone(source);
      final saved = readJson(
        p.join(clone.release.directoryPath, 'images.json'),
      );
      final records = saved['images'] as List;

      // The clone generates and uploads its own images, so only the poster is
      // there, as the primary poster record with the URLs the source has.
      expect(records.length, 1);

      final copied = records[0] as Map<String, dynamic>;
      expect(copied['item'], isNull);
      expect(copied['kind'], 'poster');
      expect(copied['file'], '_rp_poster.jpg');
      expect(copied['urls'], {
        posterHoster: {posterUrlType: 'https://fastpic.org/1.jpg'},
        'other': {imageUrlType: 'https://example.com/1'},
      });
    },
  );

  test('the poster file is copied to the same relative path', () async {
    final source = await sourceRelease();

    final images = ImagesStore();
    await images.save(
      source.directoryPath,
      ImagesManifest(
        images: [
          ImageRecord(
            item: null,
            kind: ImageKind.poster,
            file: '_rp_poster.jpg',
            urls: {},
          ),
        ],
      ),
    );

    File(p.join(source.directoryPath, '_rp_poster.jpg'))
        .writeAsStringSync('poster bytes');

    final clone = await createClone(source);

    expect(
      File(p.join(clone.release.directoryPath, '_rp_poster.jpg'))
          .readAsStringSync(),
      'poster bytes',
    );
  });

  // A record whose file is not on disk is still the poster the manifest holds,
  // so the record is copied and there is simply no file to copy.
  test('a poster that is not on disk is recorded without a file', () async {
    final source = await sourceRelease();

    await ImagesStore().save(
      source.directoryPath,
      ImagesManifest(
        images: [
          ImageRecord(
            item: null,
            kind: ImageKind.poster,
            file: '_rp_poster.jpg',
            urls: {},
          ),
        ],
      ),
    );

    final clone = await createClone(source);

    expect(
      File(p.join(clone.release.directoryPath, '_rp_poster.jpg')).existsSync(),
      isFalse,
    );

    final saved = readJson(p.join(clone.release.directoryPath, 'images.json'));
    expect((saved['images'] as List).length, 1);
  });

  // With no poster there is nothing to copy, so the clone is a plain new
  // release: no manifest, no file.
  test('a source with no poster copies no manifest', () async {
    final source = await sourceRelease();

    final clone = await createClone(source);

    expect(
      File(p.join(clone.release.directoryPath, 'images.json')).existsSync(),
      isFalse,
    );
  });

  test('the poster state is what the manifest says', () async {
    final source = await sourceRelease();
    final controller = cloneController(source);

    expect(controller.posterStatus(), ClonePosterStatus.noPoster);

    await ImagesStore().save(
      source.directoryPath,
      ImagesManifest(
        images: [
          ImageRecord(
            item: null,
            kind: ImageKind.poster,
            file: '_rp_poster.jpg',
            urls: {},
          ),
        ],
      ),
    );

    expect(controller.posterStatus(), ClonePosterStatus.notUploaded);

    await ImagesStore().save(
      source.directoryPath,
      ImagesManifest(
        images: [
          ImageRecord(
            item: null,
            kind: ImageKind.poster,
            file: '_rp_poster.jpg',
            urls: {
              posterHoster: {posterUrlType: 'https://fastpic.org/1.jpg'},
            },
          ),
        ],
      ),
    );

    expect(controller.posterStatus(), ClonePosterStatus.uploaded);
  });

  // The primary poster is the first poster record, the one with no item
  // (`ai/release_structure.md` §4), so a poster record for an item is not the
  // poster the copy takes.
  test('a poster record that belongs to an item is not the poster', () async {
    final source = await sourceRelease();

    await ImagesStore().save(
      source.directoryPath,
      ImagesManifest(
        images: [
          ImageRecord(
            item: 'video',
            kind: ImageKind.poster,
            file: 'images/video/poster.jpg',
            urls: {
              posterHoster: {posterUrlType: 'https://fastpic.org/1.jpg'},
            },
          ),
        ],
      ),
    );

    expect(cloneController(source).posterStatus(), ClonePosterStatus.noPoster);
  });

  test('the clone name must differ from the source name, and the folder-name rules '
      'still apply', () async {
    expect(validateCloneName('other', 'source'), isNull);
    expect(
      validateCloneName('source', 'source'),
      CloneNameValidationError.sameAsSource,
    );
    expect(validateCloneName('', 'source'), CloneNameValidationError.required);
    expect(
      validateCloneName('a/b', 'source'),
      CloneNameValidationError.invalid,
    );
  });

  // The form is prefilled with the folder the source is in, so the clone is its
  // neighbour unless the user picks another one.
  test(
    'the default save path is the folder the source release is in',
    () async {
      final source = await sourceRelease();

      expect(cloneController(source).defaultSavePath, directory.path);
    },
  );

  // The create is all-or-nothing: a copy that cannot be written is a failed
  // create, and the folder it made is removed rather than left half-copied.
  test('a copy that fails removes the folder the create made', () async {
    final source = await sourceRelease();

    await ImagesStore().save(
      source.directoryPath,
      ImagesManifest(
        images: [
          ImageRecord(
            item: null,
            kind: ImageKind.poster,
            file: '_rp_poster.jpg',
            urls: {},
          ),
        ],
      ),
    );

    File(p.join(source.directoryPath, '_rp_poster.jpg'))
        .writeAsStringSync('poster');

    // The file is copied before the manifest write fails, so the rollback has
    // to remove a folder that already has something in it.
    final result = await cloneController(
      source,
      images: FailingImagesStore(),
    ).create(savePath: directory.path, name: 'clone');

    expect(result, isA<CloneCreationFailure>());

    final created = (result as CloneCreationFailure).kind;
    expect(created, ReleaseCreationFailure.failed);

    expect(Directory(p.join(directory.path, 'clone')).existsSync(), isFalse);
  });

  // Only a successful create is an entry in the recent list, as an open is.
  test('a successful create is recorded and a failed one is not', () async {
    final source = await sourceRelease();

    // A poster is what makes the copy reach the manifest write, so the
    // failure is a copy failure rather than a create that copies nothing.
    await ImagesStore().save(
      source.directoryPath,
      ImagesManifest(
        images: [
          ImageRecord(
            item: null,
            kind: ImageKind.poster,
            file: '_rp_poster.jpg',
            urls: {},
          ),
        ],
      ),
    );

    final recentReleases = RecentReleasesController(
      store: RecentReleasesStore(appDirectory: () async => directory),
      tabManager: TabManager(),
    );

    final failed = await cloneController(
      source,
      images: FailingImagesStore(),
      recentReleases: recentReleases,
    ).create(savePath: directory.path, name: 'clone');

    expect(failed, isA<CloneCreationFailure>());
    expect(recentReleases.releases.entries, isEmpty);

    final succeeded = await cloneController(
      source,
      recentReleases: recentReleases,
    ).create(savePath: directory.path, name: 'clone2');

    expect(succeeded, isA<CloneCreationSuccess>());

    final clone = (succeeded as CloneCreationSuccess).release;
    expect(recentReleases.releases.entries.length, 1);
    expect(recentReleases.releases.entryFor(clone.directoryPath), isNotNull);
  });
}
