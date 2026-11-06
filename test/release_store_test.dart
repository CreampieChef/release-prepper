import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/feature/message/screenshot_layout.dart';
import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/release/release_store.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/tracker.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('release_store_test');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  // `create()` makes a folder inside the save path, so the release is the
  // folder it creates, not the temporary directory itself.
  String releasePath() => p.join(directory.path, 'release');

  Map<String, dynamic> readFile() =>
      jsonDecode(File(p.join(releasePath(), 'release.json')).readAsStringSync())
          as Map<String, dynamic>;

  Future<void> writeFile(Map<String, dynamic> json) async {
    // A manifest is written into a release folder, so the tests that write one
    // by hand make the folder first, as `create()` does.
    Directory(releasePath()).createSync(recursive: true);

    await File(p.join(releasePath(), 'release.json'))
        .writeAsString(jsonEncode(json));
  }

  // The two dates are the record of the release changing
  // (`ai/release_structure.md` §3): the creation one is written once here and
  // never changes, the other is stamped by every write.
  test('a new release records the date it was created, and the write that created it is its first edit', () async {
    final store = ReleaseStore();
    final release = await store.create(
      savePath: directory.path,
      name: 'release',
      tracker: Tracker.pornolab,
      releaseType: ReleaseType.singleVideo,
    );

    final saved = readFile();

    expect(saved['createdDate'], release.createdDate!.toIso8601String());
    expect(saved['lastEditDate'], release.lastEditDate!.toIso8601String());
  });

  test('both dates are read back from the file', () async {
    await writeFile({
      'schema': schemaVersion,
      'createdDate': '2026-01-02T03:04:05.000Z',
      'lastEditDate': '2026-02-03T04:05:06.000Z',
      'tracker': 'pornolab',
      'releaseType': 'singleVideo',
      'source': '/home/user/videos',
      'fields': {},
      'items': [],
    });

    final release = await ReleaseStore().load(releasePath());

    expect(release.createdDate, DateTime.utc(2026, 1, 2, 3, 4, 5));
    expect(release.lastEditDate, DateTime.utc(2026, 2, 3, 4, 5, 6));
  });

  // A manifest written before the app recorded dates, or one the user edited by
  // hand, is read as it is: a missing key or a value that is not a date is not
  // an error and nothing is invented for it, the same rule the field values
  // follow.
  test('a manifest without the dates loads with none, and a value that is not a date is read as none', () async {
    await writeFile({
      'schema': schemaVersion,
      'createdDate': 'not a date',
      'tracker': 'pornolab',
      'releaseType': 'singleVideo',
      'source': '/home/user/videos',
      'fields': {},
      'items': [],
    });

    final release = await ReleaseStore().load(releasePath());

    expect(release.createdDate, isNull);
    expect(release.lastEditDate, isNull);
  });

  test(
    'saving stamps the last edit and keeps the creation date as it was',
    () async {
      final store = ReleaseStore();
      final release = await store.create(
        savePath: directory.path,
        name: 'release',
        tracker: Tracker.pornolab,
        releaseType: ReleaseType.singleVideo,
      );

      final created = release.createdDate!;

      await Future.delayed(const Duration(milliseconds: 10));

      await store.save(release);

      final saved = readFile();

      expect(saved['createdDate'], created.toIso8601String());
      expect(
        DateTime.parse(saved['lastEditDate'] as String).isAfter(created),
        isTrue,
      );
    },
  );

  // The app writes what the file contains rather than a date it invented, so a
  // release it did not create stays without a creation date.
  test(
    'a release loaded without a creation date is saved without one',
    () async {
      final store = ReleaseStore();

      await writeFile({
        'schema': schemaVersion,
        'tracker': 'pornolab',
        'releaseType': 'singleVideo',
        'source': '/home/user/videos',
        'fields': {},
        'items': [],
      });

      final release = await store.load(releasePath());

      await store.save(release);

      final saved = readFile();

      expect(saved.containsKey('createdDate'), isFalse);
      expect(saved['lastEditDate'], isNotNull);
    },
  );

  // The stamp the operations that write files inside a release make is only the
  // timestamp: the field values the user has not saved are not that run's to
  // write, so a dirty tab keeps its values and stays dirty.
  test(
    'the stamp writes only the timestamp and leaves what the file holds',
    () async {
      final store = ReleaseStore();
      final release = await store.create(
        savePath: directory.path,
        name: 'release',
        tracker: Tracker.pornolab,
        releaseType: ReleaseType.singleVideo,
      );

      release.fields.setValue('videoTitle', 'Saved value');
      await store.save(release);

      final firstStamp = readFile()['lastEditDate'] as String;

      await Future.delayed(const Duration(milliseconds: 10));

      // An unsaved change in the model, which the stamp must not write.
      release.fields.setValue('videoTitle', 'Not saved yet');

      expect(await store.touchLastEdit(release), isTrue);

      final saved = readFile();

      expect(saved['fields']['videoTitle'], 'Saved value');
      expect(
        DateTime.parse(saved['lastEditDate'] as String)
            .isAfter(DateTime.parse(firstStamp)),
        isTrue,
      );
    },
  );

  // A run that cannot write the timestamp is not reported as a failure: the
  // files it wrote are what the user asked for, and the next write stamps it
  // again.
  test('the stamp reports false when the manifest is not there or is not an object', () async {
    final store = ReleaseStore();

    final release = Release(
      name: 'release',
      directoryPath: directory.path,
      tracker: Tracker.pornolab,
      releaseType: ReleaseType.singleVideo,
      source: '',
      fields: FieldValues(),
      items: [],
    );

    expect(await store.touchLastEdit(release), isFalse);

    await File(p.join(directory.path, 'release.json'))
        .writeAsString(jsonEncode([1, 2]));

    expect(await store.touchLastEdit(release), isFalse);
  });

  // A manifest naming a tracker or a release type this version does not know is
  // not opened: there is no field list, template, label or icon for it, so the
  // app cannot show or write what it cannot understand. It is reported, the
  // same way a value that is not a string is, rather than guessed at with a
  // type invented for it.
  test('a manifest naming a tracker or a release type this version does not know is reported', () async {
    final store = ReleaseStore();

    await writeFile({
      'schema': schemaVersion,
      'tracker': 'Stashdb',
      'releaseType': 'singleVideo',
      'source': '/home/user/videos',
      'fields': {},
      'items': [],
    });

    expect(store.load(releasePath()), throwsFormatException);

    await writeFile({
      'schema': schemaVersion,
      'tracker': 'pornolab',
      'releaseType': 'packOfVideos',
      'source': '/home/user/videos',
      'fields': {},
      'items': [],
    });

    expect(store.load(releasePath()), throwsFormatException);
  });

  // The shape the block has is part of the record, because `message.txt` holds a
  // block built with one of the two (`ai/video_pack.md` §7). Only a type that can
  // choose writes it, so a release of another type does not carry a shape it
  // could never use.
  test('the block shape is written for the type that can choose', () async {
    final store = ReleaseStore();

    final release = await store.create(
      savePath: directory.path,
      name: 'release',
      tracker: Tracker.pornolab,
      releaseType: ReleaseType.videoPack,
    );

    release.screenshotLayout = ScreenshotLayout.byItem;
    await store.save(release);

    expect(readFile()['screenshotLayout'], 'byItem');
    expect(
      (await store.load(releasePath())).screenshotLayout,
      ScreenshotLayout.byItem,
    );
  });

  test(
    'a release of a type that cannot choose does not write a shape',
    () async {
      final store = ReleaseStore();

      final release = await store.create(
        savePath: directory.path,
        name: 'release',
        tracker: Tracker.pornolab,
        releaseType: ReleaseType.singleVideo,
      );

      await store.save(release);

      expect(readFile().containsKey('screenshotLayout'), isFalse);
    },
  );

  // A manifest written before the choice existed is not an error, and neither is a
  // value this version does not know: both read as the shape those files were
  // written with.
  test(
    'a manifest without the key, or with a shape this version does not know, '
    'reads as the default',
    () async {
      final store = ReleaseStore();

      await writeFile({
        'schema': schemaVersion,
        'tracker': 'pornolab',
        'releaseType': 'videoPack',
        'source': '/home/user/videos',
        'fields': {},
        'items': [],
      });

      expect(
        (await store.load(releasePath())).screenshotLayout,
        ScreenshotLayout.byHoster,
      );

      await writeFile({
        'schema': schemaVersion,
        'tracker': 'pornolab',
        'releaseType': 'videoPack',
        'source': '/home/user/videos',
        'fields': {},
        'items': [],
        'screenshotLayout': 'byFile',
      });

      expect(
        (await store.load(releasePath())).screenshotLayout,
        ScreenshotLayout.byHoster,
      );
    },
  );

  // The flag is part of the record for the same reason the block shape is:
  // `message.txt` holds a post written with or without the signature, so a release
  // opened again has to show the state its post was written with
  // (`ai/description_template.md` §App signature). Every type can include it,
  // because the app signature is the app's own text, so every type writes it.
  test('the signature flag is written for every type', () async {
    final store = ReleaseStore();

    final release = await store.create(
      savePath: directory.path,
      name: 'release',
      tracker: Tracker.pornolab,
      releaseType: ReleaseType.singleVideo,
    );

    expect(readFile()['includeAppSignature'], isTrue);

    release.includeAppSignature = false;
    await store.save(release);

    expect(readFile()['includeAppSignature'], isFalse);
    expect((await store.load(releasePath())).includeAppSignature, isFalse);
  });

  // A manifest written before the flag existed is not an error, and neither is a
  // value this version does not know: both read as the state those files were
  // written with, the same rule as the block shape.
  test(
    'a manifest without the flag, or with a value this version does not know, '
    'reads as the default',
    () async {
      final store = ReleaseStore();

      await writeFile({
        'schema': schemaVersion,
        'tracker': 'pornolab',
        'releaseType': 'singleVideo',
        'source': '/home/user/videos',
        'fields': {},
        'items': [],
      });

      expect((await store.load(releasePath())).includeAppSignature, isTrue);

      await writeFile({
        'schema': schemaVersion,
        'tracker': 'pornolab',
        'releaseType': 'singleVideo',
        'source': '/home/user/videos',
        'fields': {},
        'items': [],
        'includeAppSignature': 'yes',
      });

      expect((await store.load(releasePath())).includeAppSignature, isTrue);
    },
  );

  // The Private flag is the one thing the Torrent feature records, because it is a
  // choice the user makes rather than a result of a run (`ai/torrents.md`). A
  // manifest written before it existed is not an error, and the default is the flag
  // those files were written with.
  test('the private flag is written and read back', () async {
    final store = ReleaseStore();

    final release = await store.create(
      savePath: directory.path,
      name: 'release',
      tracker: Tracker.pornolab,
      releaseType: ReleaseType.singleVideo,
    );

    expect(readFile()['torrentPrivate'], isTrue);

    release.torrentPrivate = false;
    await store.save(release);

    expect(readFile()['torrentPrivate'], isFalse);
    expect((await store.load(releasePath())).torrentPrivate, isFalse);
  });

  test('a manifest without the private flag, or with a value this version does not '
      'know, reads as the default', () async {
    final store = ReleaseStore();

    await writeFile({
      'schema': schemaVersion,
      'tracker': 'pornolab',
      'releaseType': 'singleVideo',
      'source': '/home/user/videos',
      'fields': {},
      'items': [],
    });

    expect((await store.load(releasePath())).torrentPrivate, isTrue);

    await writeFile({
      'schema': schemaVersion,
      'tracker': 'pornolab',
      'releaseType': 'singleVideo',
      'source': '/home/user/videos',
      'fields': {},
      'items': [],
      'torrentPrivate': 'yes',
    });

    expect((await store.load(releasePath())).torrentPrivate, isTrue);
  });
}
