import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/feature/message/message_controller.dart';
import 'package:release_prepper/feature/message/message_store.dart';
import 'package:release_prepper/feature/message/screenshot_layout.dart';
import 'package:release_prepper/feature/release/field_validation.dart';
import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/release/release_store.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/tracker.dart';
import 'package:release_prepper/feature/screenshots/images.dart';
import 'package:release_prepper/feature/screenshots/images_store.dart';
import 'package:release_prepper/feature/upload/hosters.dart';
import 'package:release_prepper/service/template/template_renderer.dart';
import 'package:release_prepper/service/template/template_store.dart';

import 'test_fields.dart';

void main() {
  late Directory directory;
  late MessageStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('message_controller_test');
    store = MessageStore();
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  Release release({
    FieldValues? fields,
    ReleaseType releaseType = ReleaseType.singleVideo,
  }) => Release(
    name: directory.path,
    directoryPath: directory.path,
    tracker: Tracker.pornolab,
    releaseType: releaseType,
    source: '/home/user/videos',
    fields: fields ?? completeFields(),
    items: [
      ReleaseItem(
        path: 'movie.mp4',
        type: itemTypeVideo,
        fields: FieldValues(),
      ),
    ],
  );

  MessageController controller({
    required ImagesStore images,
    required AssetBundle bundle,
    FieldValues? fields,
    ReleaseType releaseType = ReleaseType.singleVideo,
  }) => MessageController(
    release: release(fields: fields, releaseType: releaseType),
    templates: TemplateStore(bundle: bundle),
    renderer: const TemplateRenderer(),
    images: images,
    store: store,
    releaseStore: ReleaseStore(),
  );

  test(
    'the folder and the template file are named by the technical names',
    () async {
      final bundle = _FakeBundle({
        'assets/templates/pornolab/singleVideo.txt': '{{videoTitle}}',
        'assets/templates/pornolab/vanilla.style': 'text = {content}',
      });

      final fields = completeFields();
      fields.setValue('videoTitle', 'Example title');

      final result = await controller(
        images: _FakeImagesStore(const ImagesManifest.empty()),
        bundle: bundle,
        fields: fields,
      ).generate();

      // The fields are the values, so the template reads the names release.json
      // writes.
      expect((result as MessageGenerated).text, 'Example title');
    },
  );

  test('a template that is not in the bundle is reported', () async {
    final result = await controller(
      images: _FakeImagesStore(const ImagesManifest.empty()),
      bundle: _FakeBundle({}),
    ).generate();

    expect(result, isA<MessageFailure>());
    expect(
      (result as MessageFailure).kind,
      MessageFailureKind.templateNotFound,
    );
  });

  test('the title is rendered from the title template and written to title.txt', () async {
    const titleTemplate =
        '[{{subsiteAndSite}}] {{cast}} - {{videoTitle}}{{#siteNumber}} ({{siteNumber}}){{/siteNumber}} [{{productionDate}}, {{genreTags}}, {{videoType}}, {{videoQuality}}]';
    const expected =
        '[M] Jane Doe - Example title (123) [2024-05-01, Drama, MP4, 1080p]';

    final fields = completeFields();
    fields.setValue('subsiteAndSite', 'M');
    fields.setValue('cast', 'Jane Doe');
    fields.setValue('videoTitle', 'Example title');
    fields.setValue('siteNumber', '123');
    fields.setValue('productionDate', '2024-05-01');
    fields.setValue('genreTags', 'Drama');
    fields.setValue('videoType', 'MP4');
    fields.setValue('videoQuality', '1080p');

    final result = await controller(
      images: _FakeImagesStore(const ImagesManifest.empty()),
      bundle: _FakeBundle({
        'assets/templates/pornolab/singleVideo.txt': '{{videoTitle}}',
        'assets/templates/pornolab/title.txt': titleTemplate,
        'assets/templates/pornolab/vanilla.style': 'text = {content}',
      }),
      fields: fields,
    ).generate();

    expect((result as MessageGenerated).title, expected);
    expect(
      File(store.filePath(directory.path, MessageStore.titleFile))
          .readAsStringSync(),
      expected,
    );
  });

  // The title is read per release type first, because a photoset has no video
  // quality to put in a title, so its rule is not the tracker's
  // (`ai/single_photoset.md` §8).
  test(
    'the title template of the type is read before the tracker\'s',
    () async {
      final fields = FieldValues();
      fields.setValue('videoTitle', 'Example title');

      final result = await controller(
        images: _FakeImagesStore(const ImagesManifest.empty()),
        bundle: _FakeBundle({
          'assets/templates/pornolab/singlePhotoset.txt': '{{videoTitle}}',
          'assets/templates/pornolab/singlePhotoset.title.txt':
              'set: {{videoTitle}}',
          'assets/templates/pornolab/title.txt': 'tracker title',
          'assets/templates/pornolab/vanilla.style': 'text = {content}',
        }),
        fields: fields,
        releaseType: ReleaseType.singlePhotoset,
      ).generate();

      expect((result as MessageGenerated).title, 'set: Example title');
    },
  );

  // A type without a title file of its own is not a failure: the tracker's rule
  // is the fallback, which is what the other types use.
  test(
    'a type without its own title file falls back to the tracker\'s',
    () async {
      final fields = FieldValues();
      fields.setValue('videoTitle', 'Example title');

      final result = await controller(
        images: _FakeImagesStore(const ImagesManifest.empty()),
        bundle: _FakeBundle({
          'assets/templates/pornolab/singlePhotoset.txt': '{{videoTitle}}',
          'assets/templates/pornolab/title.txt': 'tracker title',
          'assets/templates/pornolab/vanilla.style': 'text = {content}',
        }),
        fields: fields,
        releaseType: ReleaseType.singlePhotoset,
      ).generate();

      expect((result as MessageGenerated).title, 'tracker title');
    },
  );

  // The optional field is a conditional section, so its parentheses are not
  // written at all. The other fields in the title are required, so the test
  // gives them values and the expectation shows them.
  test('the parentheses are omitted when the site number is empty', () async {
    final fields = completeFields();
    fields.setValue('subsiteAndSite', 'M');
    fields.setValue('cast', 'Jane Doe');
    fields.setValue('videoTitle', 'Example title');
    fields.setValue('productionDate', '2024-05-01');
    fields.setValue('genreTags', 'Drama');
    fields.setValue('videoType', 'MP4');
    fields.setValue('videoQuality', '1080p');

    final result = await controller(
      images: _FakeImagesStore(const ImagesManifest.empty()),
      bundle: _FakeBundle({
        'assets/templates/pornolab/singleVideo.txt': '{{videoTitle}}',
        'assets/templates/pornolab/title.txt': '[{{subsiteAndSite}}] {{cast}} - {{videoTitle}}{{#siteNumber}} ({{siteNumber}}){{/siteNumber}} [{{productionDate}}, {{genreTags}}, {{videoType}}, {{videoQuality}}]',
        'assets/templates/pornolab/vanilla.style': 'text = {content}',
      }),
      fields: fields,
    ).generate();

    expect(
      (result as MessageGenerated).title,
      '[M] Jane Doe - Example title [2024-05-01, Drama, MP4, 1080p]',
    );
  });

  // A tracker without a title rule still gets its post text: the title is empty
  // rather than a failure, because the message does not depend on it.
  test('a tracker with no title template generates the message with an empty title', () async {
    final fields = completeFields();
    fields.setValue('videoTitle', 'Example title');

    final result = await controller(
      images: _FakeImagesStore(const ImagesManifest.empty()),
      bundle: _FakeBundle({
        'assets/templates/pornolab/singleVideo.txt': '{{videoTitle}}',
        'assets/templates/pornolab/vanilla.style': 'text = {content}',
      }),
      fields: fields,
    ).generate();

    final generated = result as MessageGenerated;

    expect(generated.title, '');
    expect(generated.text, 'Example title');
  });

  // A type with no title reads no title file (`hasTitle`), so a bundle without
  // one is not a failure, and its release folder holds no title.txt
  // (`ai/image_folder_upload.md` §6).
  test('a type with no title generates the message without reading or writing a title', () async {
    final fields = FieldValues();
    fields.setValue('totalPhotoCount', '3');

    final result = await controller(
      images: _FakeImagesStore(const ImagesManifest.empty()),
      bundle: _FakeBundle({
        'assets/templates/pornolab/imageFolderUpload.txt':
            '{{totalPhotoCount}}',
        'assets/templates/pornolab/vanilla.style': 'text = {content}',
      }),
      fields: fields,
      releaseType: ReleaseType.imageFolderUpload,
    ).generate();

    final generated = result as MessageGenerated;

    expect(generated.title, '');
    expect(generated.text, '3');
    expect(
      File(store.filePath(directory.path, MessageStore.titleFile)).existsSync(),
      isFalse,
    );
  });

  test('the poster comes from the poster hoster, not from the first hoster in the record', () async {
    final manifest = ImagesManifest(
      images: [
        _poster({
          'turboimagehost.com': {'direct_url': 'https://second.example/1.jpg'},
          'fastpic.org': {'direct_url': 'https://fastpic.example/1.jpg'},
        }),
      ],
    );

    expect(
      await _generate(manifest, '{{posterUrl}}'),
      'https://fastpic.example/1.jpg',
    );
  });

  test('a poster with no entry for the poster hoster has no value', () async {
    final manifest = ImagesManifest(
      images: [
        _poster({
          'turboimagehost.com': {'direct_url': 'https://second.example/1.jpg'},
        }),
      ],
    );

    expect(await _generate(manifest, '{{posterUrl}}'), '');
  });

  // The first poster record is the primary one, so a second poster does not
  // change what `posterUrl` is (`ai/release_structure.md` §4).
  test('the first poster record is the primary one', () async {
    final manifest = ImagesManifest(
      images: [
        _poster({
          'fastpic.org': {'direct_url': 'https://fastpic.example/1.jpg'},
        }),
        ImageRecord(
          item: null,
          kind: ImageKind.poster,
          file: 'images/second_poster.jpg',
          urls: {
            'fastpic.org': {'direct_url': 'https://fastpic.example/2.jpg'},
          },
        ),
      ],
    );

    expect(
      await _generate(manifest, '{{posterUrl}}'),
      'https://fastpic.example/1.jpg',
    );
  });

  // `--dev` replaces the real hosters with the mock ones, so the poster hoster
  // is the first test hoster and the message reads the same shape it reads in a
  // normal run (`ai/upload_images.md`).
  test('with --dev the poster comes from the first test hoster', () async {
    devMode = true;
    addTearDown(() => devMode = false);

    final manifest = ImagesManifest(
      images: [
        _poster({
          'rptest-b': {'direct_url': 'http://127.0.0.1/rptest-b/p.jpg'},
          'rptest-a': {'direct_url': 'http://127.0.0.1/rptest-a/p.jpg'},
        }),
      ],
    );

    expect(
      await _generate(manifest, '{{posterUrl}}'),
      'http://127.0.0.1/rptest-a/p.jpg',
    );
  });

  // The same block a normal run builds, with the test hosters in the places the
  // real ones have.
  test('with --dev the block names the test hosters and the backup is the second one', () async {
    devMode = true;
    addTearDown(() => devMode = false);

    final manifest = ImagesManifest(
      images: [
        _poster({
          'rptest-a': {'direct_url': 'http://127.0.0.1/rptest-a/p.jpg'},
          'rptest-b': {
            'view_url': 'http://127.0.0.1/rptest-b/p.jpg',
            'thumb_url': 'http://127.0.0.1/rptest-b/p_thumb.jpg',
          },
        }),
        _screenshot('_rp_screenshot01.jpg', {
          'rptest-a': {
            'view_url': 'http://127.0.0.1/rptest-a/1.jpg',
            'thumb_url': 'http://127.0.0.1/rptest-a/1_thumb.jpg',
          },
        }),
      ],
    );

    expect(
      await _generate(manifest, '{{screenshotSection}}'),
      [
        '[spoiler="Скриншоты"]',
        '[spoiler="Скриншоты rptest-a"]',
        '[url=http://127.0.0.1/rptest-a/1.jpg][img]http://127.0.0.1/rptest-a/1_thumb.jpg[/img][/url]',
        '[/spoiler]',
        '[spoiler="Резервный постер"]',
        '[url=http://127.0.0.1/rptest-b/p.jpg][img]http://127.0.0.1/rptest-b/p_thumb.jpg[/img][/url]',
        '[/spoiler]',
        '[/spoiler]',
      ].join('\n'),
    );
  });

  test('the block is one spoiler per hoster, then the backup poster', () async {
    final manifest = ImagesManifest(
      images: [
        _poster({
          'fastpic.org': {'direct_url': 'https://fastpic/direct/p.jpg'},
          'turboimagehost.com': {
            'view_url': 'https://turbo/view/p.jpg',
            'thumb_url': 'https://turbo/thumb/p.jpg',
          },
        }),
        _screenshot('_rp_screenshot01.jpg', {
          // A record appears under every hoster it was uploaded to.
          'turboimagehost.com': {
            'view_url': 'https://turbo/view/1.jpg',
            'thumb_url': 'https://turbo/thumb/1.jpg',
          },
          'fastpic.org': {
            'view_url': 'https://fastpic/view/1.jpg',
            'thumb_url': 'https://fastpic/thumb/1.jpg',
          },
        }),
        _screenshot('_rp_screenshot02.jpg', {
          'fastpic.org': {
            'view_url': 'https://fastpic/view/2.jpg',
            'thumb_url': 'https://fastpic/thumb/2.jpg',
          },
        }),
        // The screenlist is the last item of its hoster's spoiler.
        _record(ImageKind.screenlist, '_rp_screenlist.jpg', {
          'fastpic.org': {
            'view_url': 'https://fastpic/view/list.jpg',
            'thumb_url': 'https://fastpic/thumb/list.jpg',
          },
        }),
      ],
    );

    expect(
      await _generate(manifest, '{{screenshotSection}}'),
      [
        '[spoiler="Скриншоты"]',
        '[spoiler="Скриншоты fastpic.org"]',
        '[url=https://fastpic/view/1.jpg][img]https://fastpic/thumb/1.jpg[/img][/url]'
            '[url=https://fastpic/view/2.jpg][img]https://fastpic/thumb/2.jpg[/img][/url]'
            '[url=https://fastpic/view/list.jpg][img]https://fastpic/thumb/list.jpg[/img][/url]',
        '[/spoiler]',
        '[spoiler="Скриншоты turboimagehost.com"]',
        '[url=https://turbo/view/1.jpg][img]https://turbo/thumb/1.jpg[/img][/url]',
        '[/spoiler]',
        '[spoiler="Резервный постер"]',
        '[url=https://turbo/view/p.jpg][img]https://turbo/thumb/p.jpg[/img][/url]',
        '[/spoiler]',
        '[/spoiler]',
      ].join('\n'),
    );
  });

  // The pack is the type that groups per item, so its block is the shape the
  // release chose, and the default is the one by hoster (`ai/video_pack.md` §7).
  // An item is a nested spoiler: the title line, the two stream lines, then its
  // images, with the screenlist last.
  test(
    'the pack block is one spoiler per hoster, and inside it one per item',
    () async {
      final manifest = ImagesManifest(
        images: [
          _screenshot('s1.jpg', {
            'fastpic.org': {
              'view_url': 'https://fastpic/view/1.jpg',
              'thumb_url': 'https://fastpic/thumb/1.jpg',
            },
          }, item: 'a.mp4'),
          _record(ImageKind.screenlist, 'list.jpg', {
            'fastpic.org': {
              'view_url': 'https://fastpic/view/list.jpg',
              'thumb_url': 'https://fastpic/thumb/list.jpg',
            },
          }, item: 'a.mp4'),
          _screenshot('s2.jpg', {
            'fastpic.org': {
              'view_url': 'https://fastpic/view/2.jpg',
              'thumb_url': 'https://fastpic/thumb/2.jpg',
            },
          }, item: 'b.mp4'),
        ],
      );

      expect(
        await _generate(
          manifest,
          '{{screenshotSection}}',
          releaseType: ReleaseType.videoPack,
          items: [
            _item('a.mp4', {
              'duration': '00:12:30',
              'videoType': '1080p',
              'fileSize': '10737418240',
              'videoStream': 'HEVC',
              'audioStream': 'AAC',
            }),
            _item('b.mp4', {
              'duration': '00:05:00',
              'videoType': '720p',
              'fileSize': '2048',
              'videoStream': 'H264',
            }),
          ],
        ),
        [
          '[spoiler="Скриншоты"]',
          '[spoiler="Скриншоты fastpic.org"]',
          '[spoiler="a.mp4 | 00:12:30 | 1080p | 10.0 GiB"]',
          '[b]Видео[/b]: HEVC',
          '[b]Аудио[/b]: AAC',
          '[url=https://fastpic/view/1.jpg][img]https://fastpic/thumb/1.jpg[/img][/url]'
              '[url=https://fastpic/view/list.jpg][img]https://fastpic/thumb/list.jpg[/img][/url]',
          '[/spoiler]',
          '[spoiler="b.mp4 | 00:05:00 | 720p | 2.0 KiB"]',
          '[b]Видео[/b]: H264',
          '[url=https://fastpic/view/2.jpg][img]https://fastpic/thumb/2.jpg[/img][/url]',
          '[/spoiler]',
          '[/spoiler]',
          '[/spoiler]',
        ].join('\n'),
      );
    },
  );

  // The other shape is the same block with the two levels swapped: the item is
  // the group and the hosters are inside it.
  test(
    'the other shape is one spoiler per item, and inside it one per hoster',
    () async {
      final manifest = ImagesManifest(
        images: [
          _screenshot('s1.jpg', {
            'fastpic.org': {
              'view_url': 'https://fastpic/view/1.jpg',
              'thumb_url': 'https://fastpic/thumb/1.jpg',
            },
            'turboimagehost.com': {
              'view_url': 'https://turbo/view/1.jpg',
              'thumb_url': 'https://turbo/thumb/1.jpg',
            },
          }, item: 'a.mp4'),
          _screenshot('s2.jpg', {
            'fastpic.org': {
              'view_url': 'https://fastpic/view/2.jpg',
              'thumb_url': 'https://fastpic/thumb/2.jpg',
            },
          }, item: 'b.mp4'),
        ],
      );

      expect(
        await _generate(
          manifest,
          '{{screenshotSection}}',
          releaseType: ReleaseType.videoPack,
          layout: ScreenshotLayout.byItem,
          items: [
            _item('a.mp4', {
              'duration': '00:12:30',
              'videoType': '1080p',
              'fileSize': '10737418240',
              'videoStream': 'HEVC',
              'audioStream': 'AAC',
            }),
            _item('b.mp4', {
              'duration': '00:05:00',
              'videoType': '720p',
              'fileSize': '2048',
              'videoStream': 'H264',
            }),
          ],
        ),
        [
          '[spoiler="Скриншоты"]',
          '[spoiler="a.mp4 | 00:12:30 | 1080p | 10.0 GiB"]',
          '[b]Видео[/b]: HEVC',
          '[b]Аудио[/b]: AAC',
          '[spoiler="Скриншоты fastpic.org"]',
          '[url=https://fastpic/view/1.jpg][img]https://fastpic/thumb/1.jpg[/img][/url]',
          '[/spoiler]',
          '[spoiler="Скриншоты turboimagehost.com"]',
          '[url=https://turbo/view/1.jpg][img]https://turbo/thumb/1.jpg[/img][/url]',
          '[/spoiler]',
          '[/spoiler]',
          '[spoiler="b.mp4 | 00:05:00 | 720p | 2.0 KiB"]',
          '[b]Видео[/b]: H264',
          '[spoiler="Скриншоты fastpic.org"]',
          '[url=https://fastpic/view/2.jpg][img]https://fastpic/thumb/2.jpg[/img][/url]',
          '[/spoiler]',
          '[/spoiler]',
          '[/spoiler]',
        ].join('\n'),
      );
    },
  );

  // A value the item does not have is left out of the title line rather than
  // shown as an empty part, a stream line is drawn only for a value there is,
  // and an item with nothing uploaded draws nothing.
  test(
    'a title line shows only the values the item has, and an item with nothing '
    'uploaded is not drawn',
    () async {
      final manifest = ImagesManifest(
        images: [
          _screenshot('s1.jpg', {
            'fastpic.org': {
              'view_url': 'https://fastpic/view/1.jpg',
              'thumb_url': 'https://fastpic/thumb/1.jpg',
            },
          }, item: 'a.mp4'),
        ],
      );

      expect(
        await _generate(
          manifest,
          '{{screenshotSection}}',
          releaseType: ReleaseType.videoPack,
          items: [
            _item('a.mp4', {'duration': '00:01:00'}),
            _item('b.mp4', {'duration': '00:02:00'}),
          ],
        ),
        [
          '[spoiler="Скриншоты"]',
          '[spoiler="Скриншоты fastpic.org"]',
          '[spoiler="a.mp4 | 00:01:00"]',
          '[url=https://fastpic/view/1.jpg][img]https://fastpic/thumb/1.jpg[/img][/url]',
          '[/spoiler]',
          '[/spoiler]',
          '[/spoiler]',
        ].join('\n'),
      );
    },
  );

  // Only the pack can choose a shape, because the shapes name a video, so a type
  // with items but no video to name keeps the flat block.
  test(
    'a photoset pack keeps the flat block, because the shapes name a video',
    () async {
      final manifest = ImagesManifest(
        images: [
          _record(ImageKind.photo, 'photo_01.jpg', {
            'fastpic.org': {
              'view_url': 'https://fastpic/view/1.jpg',
              'thumb_url': 'https://fastpic/thumb/1.jpg',
            },
          }, item: 'set'),
        ],
      );

      expect(
        await _generate(
          manifest,
          '{{screenshotSection}}',
          releaseType: ReleaseType.photosetPack,
          items: [_item('set', {})],
        ),
        [
          '[spoiler="Скриншоты"]',
          '[spoiler="Скриншоты fastpic.org"]',
          '[url=https://fastpic/view/1.jpg][img]https://fastpic/thumb/1.jpg[/img][/url]',
          '[/spoiler]',
          '[/spoiler]',
        ].join('\n'),
      );
    },
  );

  // A photo is an image in the post like a screenshot is, so the block covers
  // it too.
  test('a photo is rendered in the block like a screenshot', () async {
    final manifest = ImagesManifest(
      images: [
        _record(ImageKind.photo, 'photo_01.jpg', {
          'fastpic.org': {
            'view_url': 'https://fastpic/view/1.jpg',
            'thumb_url': 'https://fastpic/thumb/1.jpg',
          },
        }),
      ],
    );

    expect(
      await _generate(manifest, '{{screenshotSection}}'),
      [
        '[spoiler="Скриншоты"]',
        '[spoiler="Скриншоты fastpic.org"]',
        '[url=https://fastpic/view/1.jpg][img]https://fastpic/thumb/1.jpg[/img][/url]',
        '[/spoiler]',
        '[/spoiler]',
      ].join('\n'),
    );
  });

  test('a hoster with nothing uploaded produces no spoiler', () async {
    final manifest = ImagesManifest(
      images: [
        _screenshot('_rp_screenshot01.jpg', {
          'fastpic.org': {
            'view_url': 'https://fastpic/view/1.jpg',
            'thumb_url': 'https://fastpic/thumb/1.jpg',
          },
        }),
      ],
    );

    expect(
      await _generate(manifest, '{{screenshotSection}}'),
      [
        '[spoiler="Скриншоты"]',
        '[spoiler="Скриншоты fastpic.org"]',
        '[url=https://fastpic/view/1.jpg][img]https://fastpic/thumb/1.jpg[/img][/url]',
        '[/spoiler]',
        '[/spoiler]',
      ].join('\n'),
    );
  });

  test('an image with no thumb_url is skipped', () async {
    final manifest = ImagesManifest(
      images: [
        _screenshot('_rp_screenshot01.jpg', {
          'fastpic.org': {'view_url': 'https://fastpic/view/1.jpg'},
        }),
        _screenshot('_rp_screenshot02.jpg', {
          'fastpic.org': {
            'view_url': 'https://fastpic/view/2.jpg',
            'thumb_url': 'https://fastpic/thumb/2.jpg',
          },
        }),
      ],
    );

    expect(
      await _generate(manifest, '{{screenshotSection}}'),
      [
        '[spoiler="Скриншоты"]',
        '[spoiler="Скриншоты fastpic.org"]',
        '[url=https://fastpic/view/2.jpg][img]https://fastpic/thumb/2.jpg[/img][/url]',
        '[/spoiler]',
        '[/spoiler]',
      ].join('\n'),
    );
  });

  // The poster is not in the block. Only its links on other hosters are, as the
  // backup.
  test('a poster on the poster hoster produces no backup spoiler', () async {
    final manifest = ImagesManifest(
      images: [
        _poster({
          'fastpic.org': {
            'direct_url': 'https://fastpic/direct/p.jpg',
            'view_url': 'https://fastpic/view/p.jpg',
            'thumb_url': 'https://fastpic/thumb/p.jpg',
          },
        }),
        _screenshot('_rp_screenshot01.jpg', {
          'fastpic.org': {
            'view_url': 'https://fastpic/view/1.jpg',
            'thumb_url': 'https://fastpic/thumb/1.jpg',
          },
        }),
      ],
    );

    expect(
      await _generate(manifest, '{{screenshotSection}}'),
      [
        '[spoiler="Скриншоты"]',
        '[spoiler="Скриншоты fastpic.org"]',
        '[url=https://fastpic/view/1.jpg][img]https://fastpic/thumb/1.jpg[/img][/url]',
        '[/spoiler]',
        '[/spoiler]',
      ].join('\n'),
    );
  });

  test(
    'nothing uploaded produces an empty block, so its line is dropped',
    () async {
      final manifest = ImagesManifest(
        images: [_record(ImageKind.screenlist, '_rp_screenlist.jpg', {})],
      );

      // The poster line renders to nothing and the blank collapses with it, so
      // the output is empty rather than a blank line.
      expect(
        await _generate(
          manifest,
          '{{posterUrl}}{{blank}}{{screenshotSection}}',
        ),
        '',
      );
    },
  );

  test('the text is written to message.txt with no trailing newline', () async {
    final result = await controller(
      images: _FakeImagesStore(const ImagesManifest.empty()),
      bundle: _FakeBundle({
        'assets/templates/pornolab/singleVideo.txt':
            'a\n{{blank}}\n{{screenshotSection}}',
        'assets/templates/pornolab/vanilla.style': 'text = {content}',
      }),
    ).generate();

    expect(result, isA<MessageGenerated>());
    expect(
      File(store.filePath(directory.path, MessageStore.messageFile))
          .readAsStringSync(),
      'a',
    );
  });

  // A generation is refused before anything is read, so a release with a
  // required field empty is reported as that field rather than as a template
  // the bundle does not have, and nothing is written.
  test(
    'a required field with no value is reported and nothing is written',
    () async {
      final fields = completeFields();
      fields.setValue('cast', '');

      final result = await controller(
        images: _FakeImagesStore(const ImagesManifest.empty()),
        bundle: _FakeBundle({}),
        fields: fields,
      ).generate();

      final invalid = result as MessageInvalid;

      expect(invalid.problems.map((problem) => problem.field), ['cast']);
      expect(
        File(store.filePath(directory.path, MessageStore.messageFile))
            .existsSync(),
        isFalse,
      );
    },
  );

  // The four names that may be empty: the three the template wraps as
  // conditional sections, and the scene link, which is only there to help fill
  // the other fields. An empty one does not stop a generation.
  test('the optional fields can be empty', () async {
    final fields = completeFields();

    for (final name in [
      'siteNumber',
      'description',
      'additionalInfo',
      'sceneUrl',
    ]) {
      fields.setValue(name, '');
    }

    final result = await controller(
      images: _FakeImagesStore(const ImagesManifest.empty()),
      bundle: _FakeBundle({
        'assets/templates/pornolab/singleVideo.txt': '{{videoTitle}}',
        'assets/templates/pornolab/vanilla.style': 'text = {content}',
      }),
      fields: fields,
    ).generate();

    expect((result as MessageGenerated).text, 'a');
  });

  // The date is a value the message shows, so a value that is not one of the
  // three shapes the field accepts is reported rather than put in the post.
  test('a date that is not one of the three shapes is reported', () async {
    final fields = completeFields();
    fields.setValue('productionDate', '2024-5-1');

    final result = await controller(
      images: _FakeImagesStore(const ImagesManifest.empty()),
      bundle: _FakeBundle({}),
      fields: fields,
    ).generate();

    final invalid = result as MessageInvalid;

    expect(invalid.problems.map((problem) => problem.kind), [
      FieldProblemKind.invalidDate,
    ]);
  });

  // A field list that has not stated its rules cannot be validated against
  // them, so a type whose required set is not known still generates
  // (`lib/TODO.MD`).
  test('a type whose required set is not stated is not validated', () async {
    final result = await controller(
      images: _FakeImagesStore(const ImagesManifest.empty()),
      bundle: _FakeBundle({
        'assets/templates/pornolab/singlePhotoset.txt': '{{videoTitle}}',
        'assets/templates/pornolab/vanilla.style': 'text = {content}',
      }),
      fields: FieldValues(),
      releaseType: ReleaseType.singlePhotoset,
    ).generate();

    expect(result, isA<MessageGenerated>());
  });

  // The box shows what a render produced from the values, so the controller keeps
  // what the last render read and says whether the values are still those
  // (`ai/description_template.md` §Section).
  test(
    'a generation records what it read, and a change to it is stale',
    () async {
      final fields = completeFields();
      fields.setValue('videoTitle', 'Example title');

      final images = _FakeImagesStore(
        ImagesManifest(
          images: [
            _poster({
              'example.com': {'direct_url': 'https://example.com/a.jpg'},
            }),
          ],
        ),
      );

      final c = controller(
        images: images,
        bundle: _FakeBundle({
          'assets/templates/pornolab/singleVideo.txt': '{{videoTitle}}',
          'assets/templates/pornolab/vanilla.style': 'text = {content}',
        }),
        fields: fields,
      );

      await c.generate();

      expect(c.valuesChanged(), isFalse);

      fields.setValue('videoTitle', 'Another title');

      expect(c.valuesChanged(), isTrue);
    },
  );

  // Opening a section reads the files rather than a render made here, so the
  // values as they are then are taken as what the text was built from.
  test(
    'what the section was opened with is taken as what the text read',
    () async {
      final fields = FieldValues();
      fields.setValue('videoTitle', 'Example title');

      final c = controller(
        images: _FakeImagesStore(const ImagesManifest.empty()),
        bundle: _FakeBundle({
          'assets/templates/pornolab/singleVideo.txt': '{{videoTitle}}',
          'assets/templates/pornolab/vanilla.style': 'text = {content}',
        }),
        fields: fields,
      );

      c.remember();

      expect(c.valuesChanged(), isFalse);

      fields.setValue('videoTitle', 'Another title');

      expect(c.valuesChanged(), isTrue);
    },
  );

  // A generation run writes files but no URLs, and the block shows only what is
  // uploaded, so a record with nothing uploaded is not a change the render reads.
  test('a record with no urls is not a change the render reads', () async {
    final images = _FakeImagesStore(const ImagesManifest.empty());

    final c = controller(
      images: images,
      bundle: _FakeBundle({
        'assets/templates/pornolab/singleVideo.txt': '{{posterUrl}}',
        'assets/templates/pornolab/vanilla.style': 'text = {content}',
      }),
    );

    await c.generate();

    images.manifest = ImagesManifest(images: [_poster(const {})]);

    expect(c.valuesChanged(), isFalse);

    // The same record with a URL is an upload, and that is what the message is
    // made of.
    images.manifest = ImagesManifest(
      images: [
        _poster({
          posterHoster: {posterUrlType: 'https://example.test/a.jpg'},
        }),
      ],
    );

    expect(c.valuesChanged(), isTrue);
  });

  // A reset leaves nothing to show, and the files always match what the section
  // shows, so an empty box means no file.
  test('a reset removes both files', () async {
    await store.save(directory.path, MessageStore.messageFile, 'the text');
    await store.save(directory.path, MessageStore.titleFile, 'the title');

    final result = await controller(
      images: _FakeImagesStore(const ImagesManifest.empty()),
      bundle: _FakeBundle({
        'assets/templates/pornolab/singleVideo.txt': '{{videoTitle}}',
        'assets/templates/pornolab/vanilla.style': 'text = {content}',
      }),
    ).clear();

    expect(result, isA<MessageCleared>());
    expect(
      File(store.filePath(directory.path, MessageStore.messageFile))
          .existsSync(),
      isFalse,
    );
    expect(
      File(store.filePath(directory.path, MessageStore.titleFile)).existsSync(),
      isFalse,
    );
  });

  // A type with no title has no title file, so a reset removes only the message
  // (`hasTitle`, `ai/image_folder_upload.md` §6).
  test('a type with no title removes only the message file', () async {
    await store.save(directory.path, MessageStore.messageFile, 'the text');
    await store.save(directory.path, MessageStore.titleFile, 'the title');

    await controller(
      images: _FakeImagesStore(const ImagesManifest.empty()),
      bundle: _FakeBundle({
        'assets/templates/pornolab/imageFolderUpload.txt': 'the text',
        'assets/templates/pornolab/vanilla.style': 'text = {content}',
      }),
      releaseType: ReleaseType.imageFolderUpload,
    ).clear();

    expect(
      File(store.filePath(directory.path, MessageStore.messageFile))
          .existsSync(),
      isFalse,
    );
    expect(
      File(store.filePath(directory.path, MessageStore.titleFile)).existsSync(),
      isTrue,
    );
  });
}

ImageRecord _poster(Map<String, Map<String, String>> urls) =>
    _record(ImageKind.poster, '_rp_poster.jpg', urls);

ImageRecord _screenshot(
  String name,
  Map<String, Map<String, String>> urls, {
  String item = 'movie.mp4',
}) => _record(ImageKind.screenshot, name, urls, item: item);

/// A record as `images.json` holds it: the item it belongs to, the kind, the
/// path relative to the release directory. A poster belongs to the release, so
/// its item is null (`ai/release_structure.md` §4).
ImageRecord _record(
  ImageKind kind,
  String name,
  Map<String, Map<String, String>> urls, {
  String item = 'movie.mp4',
}) => ImageRecord(
  item: kind == ImageKind.poster ? null : item,
  kind: kind,
  file: kind == ImageKind.poster ? name : 'images/$item/$name',
  urls: urls,
);

/// An item with the values the probe wrote for it, which is what the title line
/// and the two stream lines read.
ReleaseItem _item(String path, Map<String, String> values) {
  final fields = FieldValues();

  for (final entry in values.entries) {
    fields.setValue(entry.key, entry.value);
  }

  return ReleaseItem(path: path, type: itemTypeVideo, fields: fields);
}

Future<String> _generate(
  ImagesManifest manifest,
  String template, {
  ReleaseType releaseType = ReleaseType.singleVideo,
  ScreenshotLayout layout = ScreenshotLayout.byHoster,
  List<ReleaseItem>? items,
}) async {
  final directory = Directory.systemTemp.createTempSync(
    'message_controller_test',
  );

  try {
    final result = await MessageController(
      release: Release(
        name: directory.path,
        directoryPath: directory.path,
        tracker: Tracker.pornolab,
        releaseType: releaseType,
        source: '/home/user/videos',
        fields: completeFields(),
        items:
            items ??
            [
              ReleaseItem(
                path: 'movie.mp4',
                type: itemTypeVideo,
                fields: FieldValues(),
              ),
            ],
        screenshotLayout: layout,
      ),
      templates: TemplateStore(
        bundle: _FakeBundle({
          'assets/templates/pornolab/${releaseType.name}.txt': template,
          'assets/templates/pornolab/vanilla.style': 'text = {content}',
        }),
      ),
      renderer: const TemplateRenderer(),
      images: _FakeImagesStore(manifest),
      store: MessageStore(),
      releaseStore: ReleaseStore(),
    ).generate();

    return (result as MessageGenerated).text;
  } finally {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

/// An asset bundle that answers from a map, so the path rule can be tested
/// without the bundle on disk.
class _FakeBundle extends AssetBundle {
  _FakeBundle(this.contents);

  final Map<String, String> contents;

  @override
  Future<ByteData> load(String key) async {
    final text = contents[key];

    if (text == null) {
      // The shape the real bundle throws, so the store's guard is tested
      // against it rather than against a plain Exception, which `on Exception`
      // would catch and the app would not.
      throw FlutterError('Unable to load asset: "$key".');
    }

    return ByteData.sublistView(utf8.encode(text));
  }
}

class _FakeImagesStore implements ImagesStore {
  _FakeImagesStore(this.manifest);

  /// Set when a test wants the controller to read a different state.
  ImagesManifest manifest;

  @override
  String filePath(String directoryPath) => directoryPath;

  @override
  Future<ImagesManifest> load(String directoryPath) async => manifest;

  @override
  ImagesManifest loadSync(String directoryPath) => manifest;

  @override
  Future<void> save(String directoryPath, ImagesManifest manifest) async {}
}
