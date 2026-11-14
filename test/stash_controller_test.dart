import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/stashdb/stash_controller.dart';
import 'package:release_prepper/service/network/image_downloader.dart';
import 'package:release_prepper/service/network/stash_client.dart';
import 'package:release_prepper/service/stashdb/domain_map.dart';

void main() {
  const id = 'b3c6f0e4-8f1e-4c2b-9a1d-6f0a2b3c4d5e';

  StashUrl urlWith(String url, {String site = '', String category = ''}) =>
      StashUrl(url: url, siteName: site, categoryName: category);

  StashStudio studioWith(String name, [List<StashUrl> urls = const []]) =>
      StashStudio(name: name, urls: urls);

  StashScene scene({
    String cast = '',
    String title = '',
    String code = '',
    String details = '',
    String releaseDate = '',
    String productionDate = '',
    StashStudio studio = StashStudio.empty,
    StashStudio parentStudio = StashStudio.empty,
    List<StashAppearance> performers = const [],
    List<String> tags = const [],
    List<String> images = const [],
  }) => StashScene(
    id: id,
    title: title,
    code: code,
    details: details,
    releaseDate: releaseDate,
    productionDate: productionDate,
    studio: studio,
    parentStudio: parentStudio,
    performers: performers,
    tags: tags,
    images: images,
  );

  test('the input is a scene ID, or the last part of a scene URL', () {
    expect(StashController.sceneId(id), id);
    expect(StashController.sceneId('  $id  '), id);
    expect(StashController.sceneId('https://stashdb.com/scenes/$id'), id);

    // A query or a fragment is not part of the path, so it is not read as part
    // of the id.
    expect(StashController.sceneId('https://stashdb.com/scenes/$id?x=1'), id);
    expect(StashController.sceneId('https://stashdb.com/scenes/$id#note'), id);

    // An uppercase id is the same id.
    expect(StashController.sceneId(id.toUpperCase()), id);

    expect(StashController.sceneId('https://stashdb.com/scenes'), isNull);
    expect(StashController.sceneId('not an id'), isNull);
    expect(StashController.sceneId(''), isNull);
  });

  /// These tests check the request and the mapping, so the downloader is one
  /// that reaches nothing; the preview tests below give the controller a fake
  /// they can look at. The domain map answers from a map rather than from the
  /// asset on disk, so a test that is not about the mapping is not also about
  /// the file. The field list is the single video's, because that is the type
  /// the mapping is described for; a test about which names another type has
  /// passes its list instead.
  StashController stashController(
    StashClient client, {
    Map<String, String> domains = const {},
    FieldList fieldList = singleVideoFieldList,
  }) => StashController(
    client: client,
    downloader: _FakeDownloader(
      const DownloadFailure(DownloadFailureKind.failed),
    ),
    domainMap: DomainMap(
      bundle: _FakeBundle({DomainMap.assetPath: jsonEncode(domains)}),
    ),
    fieldList: fieldList,
  );

  test(
    'an input that is not an id is reported before anything is asked for',
    () async {
      final client = _FakeClient(StashSceneSuccess(scene()));

      expect(
        await stashController(client)
            .fetch(input: 'not an id', apiKey: 'the-key'),
        isA<StashFailure>().having(
          (failure) => failure.kind,
          'kind',
          StashFailureKind.invalidInput,
        ),
      );

      expect(client.calls, isEmpty);
    },
  );

  test('no key is reported before anything is asked for', () async {
    final client = _FakeClient(StashSceneSuccess(scene()));

    expect(
      await stashController(client).fetch(input: id, apiKey: ''),
      isA<StashFailure>().having(
        (failure) => failure.kind,
        'kind',
        StashFailureKind.noApiKey,
      ),
    );

    expect(client.calls, isEmpty);
  });

  test('a valid input is asked for with the key the settings hold', () async {
    final client = _FakeClient(StashSceneSuccess(scene()));

    final result = await stashController(client)
        .fetch(input: 'https://stashdb.com/scenes/$id', apiKey: 'the-key');

    expect(client.calls, [(id, 'the-key')]);
    expect(result, isA<StashSceneSuccess>());
  });

  test('the values are the fields StashDB has a value for', () async {
    final controller = stashController(_FakeClient(null));

    final values = await controller.fieldValues(
      scene(
        title: 'Example title',
        code: '12345',
        details: 'Description text',
        releaseDate: '2024-06-01',
        productionDate: '2024-05-17',
        studio: studioWith('MILFSoup', [
          urlWith('https://www.milfsoup.com', category: 'Primary sources'),
        ]),
        parentStudio: studioWith('BangBros', [
          urlWith('https://www.bangbros.com', category: 'Primary sources'),
        ]),
        performers: const [
          StashAppearance(name: 'Real Name', alias: 'Alias'),
          StashAppearance(name: 'Another', alias: ''),
        ],
        tags: const ['anal', 'solo'],
      ),
    );

    expect(values['cast'], 'Alias, Another');
    expect(values['videoTitle'], 'Example title');
    expect(values['siteNumber'], '12345');
    // The field is "subsite and site", so the subsite comes first, and both are
    // the domains rather than the names StashDB holds.
    expect(values['subsiteAndSite'], 'MILFSoup.com / BangBros.com');
    // The date field is the production date, but StashDB usually has only the
    // release date, so the release date is what the field gets when both exist.
    expect(values['productionDate'], '2024-06-01');
    expect(values['genreTags'], 'anal, solo');
    expect(values['description'], 'Description text');
  });

  // The same rules write the values for the single photoset under the names its
  // own field list has: the site is one field there, so the two parts are
  // written into it as the same string, and the number is written nowhere,
  // because the type has no field for it (`ai/single_photoset.md` §9).
  test('the same values are written under the names the type has', () async {
    final controller = stashController(
      _FakeClient(null),
      fieldList: singlePhotosetFieldList,
    );

    final values = await controller.fieldValues(
      scene(
        title: 'Example title 12345',
        code: '12345',
        details: 'Description text',
        releaseDate: '2024-06-01',
        studio: studioWith('MILFSoup', [
          urlWith('https://www.milfsoup.com', category: 'Primary sources'),
        ]),
        parentStudio: studioWith('BangBros', [
          urlWith('https://www.bangbros.com', category: 'Primary sources'),
        ]),
        performers: const [StashAppearance(name: 'Real Name', alias: 'Alias')],
        tags: const ['anal'],
      ),
    );

    expect(values.keys, [
      'siteOrJournal',
      'cast',
      'videoTitle',
      'productionDate',
      'genreTags',
      'description',
    ]);

    expect(values['siteOrJournal'], 'MILFSoup.com / BangBros.com');

    // The number is cut from the title for this type too, so a title that
    // contains it is a value the import changed.
    expect(values['videoTitle'], 'Example title');

    expect(values['cast'], 'Alias');
    expect(values['productionDate'], '2024-06-01');
    expect(values['genreTags'], 'anal');
    expect(values['description'], 'Description text');
  });

  // StashDB has a production date only when someone entered one, so the release
  // date is the usual source and the production date is what is left when there
  // is no release date.
  test('the date field takes the release date, or the production date when there is none', () async {
    final controller = stashController(_FakeClient(null));

    expect(
      (await controller.fieldValues(
        scene(releaseDate: '2024-06-01'),
      ))['productionDate'],
      '2024-06-01',
    );

    expect(
      (await controller.fieldValues(
        scene(productionDate: '2024-05-17'),
      ))['productionDate'],
      '2024-05-17',
    );

    // Neither is not a value, so there is nothing to apply.
    expect((await controller.fieldValues(scene())).keys, isEmpty);
  });

  test(
    'a field StashDB has nothing for is left out rather than written as empty',
    () async {
      final controller = stashController(_FakeClient(null));

      final values = await controller.fieldValues(
        scene(title: 'Example title'),
      );

      expect(values.keys, ['videoTitle']);
    },
  );

  // The fields the app reads from the movie file are not StashDB's to fill, and
  // additionalInfo has no StashDB value at all.
  test(
    'the fields filled from the movie file are never filled from StashDB',
    () {
      for (final fieldList in [singleVideoFieldList, singlePhotosetFieldList]) {
        final controller = stashController(
          _FakeClient(null),
          fieldList: fieldList,
        );

        for (final name in controller.fillableFields()) {
          expect(fieldList.field(name).filledByApp, isFalse, reason: name);
        }

        expect(controller.fillableFields(), isNot(contains('additionalInfo')));
      }
    },
  );

  // Which names the section offers is the field list of the type, not a list
  // the controller holds: the site is the same value written under the name the
  // type has, and a value the type has no field for is not offered for it. The
  // order is the order the type's field list lists them, which is the order the
  // popup shows them in (`ai/single_photoset.md` §9).
  test('the values offered are the names the type has a field for', () {
    expect(stashController(_FakeClient(null)).fillableFields(), [
      'cast',
      'videoTitle',
      'siteNumber',
      'subsiteAndSite',
      'productionDate',
      'genreTags',
      'description',
    ]);

    expect(
      stashController(
        _FakeClient(null),
        fieldList: singlePhotosetFieldList,
      ).fillableFields(),
      [
        'siteOrJournal',
        'cast',
        'videoTitle',
        'productionDate',
        'genreTags',
        'description',
      ],
    );
  });

  // The link is not a value the section offers with a checkbox: it is what the
  // user typed, and the section writes it through the same path. It is built
  // from the id the app asked for, so what a manifest holds is always a link on
  // the site the app queries.
  test(
    'the scene link is built from the id, not from the text that was pasted',
    () {
      final controller = stashController(_FakeClient(null));

      expect(controller.sceneUrl(scene()), 'https://stashdb.org/scenes/$id');
      expect(controller.fillableFields(), isNot(contains('sceneUrl')));
    },
  );

  test('a studio with no parent is the domain alone', () async {
    final controller = stashController(_FakeClient(null));

    expect(
      await controller.fieldValues(
        scene(
          studio: studioWith('AdultTime', [
            urlWith('https://www.adulttime.com', category: 'Primary sources'),
          ]),
        ),
      ),
      {'subsiteAndSite': 'AdultTime.com'},
    );
  });

  // The domain is the host of the URL the app reads it from, without www.,
  // written with the name's capitalization when the name is the same word as
  // the host's label. A host that is not the name is written as the URL gives
  // it, and a studio with no URL with a host has no domain to read, so the name
  // is what the field gets rather than a TLD the app invented. The URLs here
  // have no category, so each one is read as the first URL with a host, and the
  // mapping is empty, so these are the rule rather than the file.
  test('the domain is the URL host, with the name capitalization', () async {
    final controller = stashController(_FakeClient(null));

    Future<Map<String, String>> values(StashStudio studio) =>
        controller.fieldValues(scene(studio: studio));

    expect(
      (await values(
        studioWith('MILFSoup', [urlWith('https://www.milfsoup.com')]),
      ))['subsiteAndSite'],
      'MILFSoup.com',
    );

    // A URL with no scheme is still the host of a site.
    expect(
      (await values(
        studioWith('MILFSoup', [urlWith('www.milfsoup.com')]),
      ))['subsiteAndSite'],
      'MILFSoup.com',
    );

    // A name that is not the same word as the host is not a capitalization
    // the app can apply, so the host is written as the URL gives it.
    expect(
      (await values(
        studioWith('Example Studio', [urlWith('https://example-studio.com')]),
      ))['subsiteAndSite'],
      'example-studio.com',
    );

    // Nothing to read, so nothing is invented.
    expect(
      (await values(studioWith('Example Studio')))['subsiteAndSite'],
      'Example Studio',
    );

    // A studio with neither a name nor a URL has no value, so the field is
    // not offered at all.
    expect((await values(StashStudio.empty)).keys, isEmpty);
  });

  // A domain in the mapping is what the field gets, before the rule, because
  // the file is the list of the domains the app writes in a form the rule
  // cannot give. The key is the domain as the app computes it, so a URL with
  // capitals, www. or a path still finds its entry; a studio with no URL has
  // no domain to look up, so the mapping does not apply to it.
  test('a domain in the mapping is what the field gets', () async {
    final controller = stashController(
      _FakeClient(null),
      domains: {'jacquieetmicheltv.net': 'JacquieEtMichelTV.net'},
    );

    expect(
      (await controller.fieldValues(
        scene(
          studio: studioWith('Jacquie et Michel TV', [
            urlWith(
              'https://www.jacquieetmicheltv.net',
              category: 'Primary sources',
            ),
          ]),
        ),
      ))['subsiteAndSite'],
      'JacquieEtMichelTV.net',
    );

    expect(
      (await controller.fieldValues(
        scene(
          studio: studioWith('Jacquie et Michel TV', [
            urlWith('https://www.JacquieEtMichelTV.net/somewhere'),
          ]),
        ),
      ))['subsiteAndSite'],
      'JacquieEtMichelTV.net',
    );

    // Nothing to look up, so the mapping does not apply.
    expect(
      (await controller.fieldValues(
        scene(studio: studioWith('Jacquie et Michel TV')),
      ))['subsiteAndSite'],
      'Jacquie et Michel TV',
    );
  });

  // A studio's URL list is not only its own site: it can hold links to other
  // databases, and those are often listed first, so the first URL is not the
  // site the studio is on. The URL in the Primary sources category is the site,
  // so it is the one the domain is read from, whatever its place in the list
  // is.
  test(
    'the domain is read from the URL in the Primary sources category',
    () async {
      final controller = stashController(_FakeClient(null));

      expect(
        (await controller.fieldValues(
          scene(
            studio: studioWith('MILFSoup', [
              urlWith('https://iafd.com/name', site: 'IAFD', category: 'Other'),
              urlWith(
                'https://www.milfsoup.com',
                site: 'MILFSoup',
                category: 'Primary sources',
              ),
              urlWith(
                'https://www.bangbros.com',
                site: 'BangBros',
                category: 'Primary sources',
              ),
            ]),
          ),
        ))['subsiteAndSite'],
        'MILFSoup.com',
      );
    },
  );

  // When no URL is in that category, the one recorded under the site named
  // Studio is what is tried next, because that is the site a studio URL is
  // recorded under when it does not match a site StashDB knows.
  test('the site named Studio is what is tried when no URL is in the Primary sources category', () async {
    final controller = stashController(_FakeClient(null));

    expect(
      (await controller.fieldValues(
        scene(
          studio: studioWith('Example Studio', [
            urlWith(
              'https://www.instagram.com/example',
              site: 'Instagram',
              category: 'Social media',
            ),
            urlWith('https://example-studio.com', site: 'Studio'),
          ]),
        ),
      ))['subsiteAndSite'],
      'example-studio.com',
    );
  });

  // Neither, so the first URL with a host is what is read, as before.
  test(
    'the first URL with a host is what is read when neither is there',
    () async {
      final controller = stashController(_FakeClient(null));

      expect(
        (await controller.fieldValues(
          scene(
            studio: studioWith('Example Studio', [
              urlWith('https://example-studio.com', category: 'Other'),
              urlWith('https://iafd.com/name', category: 'Other'),
            ]),
          ),
        ))['subsiteAndSite'],
        'example-studio.com',
      );
    },
  );

  // A URL with no host is not a domain, so it is not a candidate at any step: a
  // URL in the Primary sources category with no host does not win over one that
  // has a host.
  test('a URL with no host is not a candidate at any step', () async {
    final controller = stashController(_FakeClient(null));

    expect(
      (await controller.fieldValues(
        scene(
          studio: studioWith('Example Studio', [
            urlWith('', site: 'Example Site', category: 'Primary sources'),
            urlWith('https://example-studio.com', site: 'Example Site'),
          ]),
        ),
      ))['subsiteAndSite'],
      'example-studio.com',
    );
  });

  // The site number is a field of its own, so a title that contains it says the
  // same thing twice; every occurrence is cut off the title, and the ends of
  // what is left are trimmed, because a cut leaves the space that was in front
  // of the number.
  test('the title is what is left after the site number is cut off it', () async {
    final controller = stashController(_FakeClient(null));

    expect(
      (await controller.fieldValues(
        scene(
          title: 'May Thai Has All Hole Plugged in BDSM DP GP2352',
          code: 'GP2352',
        ),
      ))['videoTitle'],
      'May Thai Has All Hole Plugged in BDSM DP',
    );

    // Every occurrence, not only the one at the end.
    expect(
      (await controller.fieldValues(
        scene(title: 'GP2352 title GP2352', code: 'GP2352'),
      ))['videoTitle'],
      'title',
    );

    // A title that does not contain the number is the title as StashDB gave it,
    // and a scene with no number has nothing to cut.
    expect(
      (await controller.fieldValues(
        scene(title: 'Example title', code: '12345'),
      ))['videoTitle'],
      'Example title',
    );

    expect(
      (await controller.fieldValues(
        scene(title: 'Example title'),
      ))['videoTitle'],
      'Example title',
    );
  });

  // The popup shows what the import changed rather than copied, so a value it
  // copied as the scene reported it produces no note. The note is what was done
  // to the value — the kind the widget maps to a message — and the value as the
  // scene gave it, as the parts the app keeps and the part it cut.
  test('a value the import changed is listed with the part it cut', () {
    final controller = stashController(_FakeClient(null));

    final notes = controller.changedValues(
      scene(
        title: 'May Thai Has All Hole Plugged in BDSM DP GP2352',
        code: 'GP2352',
      ),
    );

    expect(notes.single.field, 'videoTitle');
    expect(notes.single.kind, ImportNoteKind.siteNumberStrippedFromTitle);
    expect(notes.single.parts.map((part) => (part.text, part.cut)).toList(), [
      ('May Thai Has All Hole Plugged in BDSM DP ', false),
      ('GP2352', true),
    ]);

    // Nothing was cut, so there is nothing to show.
    expect(controller.changedValues(scene(title: 'Example title')), isEmpty);
  });

  // A domain read from a URL that is not in the Primary sources category is not
  // what the rule would give, so it is a change the popup lists: the note is
  // the URL the domain was read from.
  test('a domain read from another URL is listed with that URL', () {
    final controller = stashController(_FakeClient(null));

    final notes = controller.changedValues(
      scene(
        studio: studioWith('Example Studio', [
          urlWith('https://example-studio.com', site: 'Studio'),
        ]),
        parentStudio: studioWith('Example Network', [
          urlWith('https://iafd.com/network', site: 'IAFD', category: 'Other'),
          urlWith(
            'https://example-network.com',
            site: 'Example Network',
            category: 'Primary sources',
          ),
        ]),
      ),
    );

    // Only the subsite had to be read from another URL, so only it is listed.
    expect(notes.single.field, 'subsiteAndSite');
    expect(notes.single.kind, ImportNoteKind.domainFromOtherUrl);
    expect(notes.single.parts.map((part) => (part.text, part.cut)).toList(), [
      ('https://example-studio.com', false),
    ]);
  });

  // A domain read from the URL the rule names is the value as the rule gives
  // it, so there is nothing to show, and a studio with no URL has no URL to
  // show.
  test(
    'a domain read from the Primary sources URL is not listed as changed',
    () {
      final controller = stashController(_FakeClient(null));

      expect(
        controller.changedValues(
          scene(
            studio: studioWith('MILFSoup', [
              urlWith('https://www.milfsoup.com', category: 'Primary sources'),
            ]),
          ),
        ),
        isEmpty,
      );

      expect(
        controller.changedValues(scene(studio: studioWith('Example Studio'))),
        isEmpty,
      );
    },
  );

  // Both parts of the field can have been read from another URL, and each one
  // is its own note, the subsite first because it is the first part of the
  // field; the notes are in the order the popup lists the values.
  test('the notes are in the order the popup lists the values', () {
    final controller = stashController(_FakeClient(null));

    final notes = controller.changedValues(
      scene(
        title: 'Example title 12345',
        code: '12345',
        studio: studioWith('Example Studio', [
          urlWith('https://example-studio.com'),
        ]),
        parentStudio: studioWith('Example Network', [
          urlWith('https://example-network.com'),
        ]),
      ),
    );

    expect(notes.map((note) => note.field).toList(), [
      'videoTitle',
      'subsiteAndSite',
      'subsiteAndSite',
    ]);
    expect(
      notes.map((note) => note.parts.map((part) => part.text).join()).toList(),
      [
        'Example title 12345',
        'https://example-studio.com',
        'https://example-network.com',
      ],
    );
  });

  // A note names the field the value is written into, so for the single
  // photoset it names the name that type's field list has rather than the
  // single video's, and the notes are in the order that list lists the values —
  // the site before the set name, which is the order the popup shows them in
  // (`ai/single_photoset.md` §9).
  test(
    'a note names the field the type has, in the order that list lists them',
    () {
      final controller = stashController(
        _FakeClient(null),
        fieldList: singlePhotosetFieldList,
      );

      final notes = controller.changedValues(
        scene(
          title: 'Example title 12345',
          code: '12345',
          studio: studioWith('Example Studio', [
            urlWith('https://example-studio.com'),
          ]),
        ),
      );

      expect(notes.map((note) => note.field).toList(), [
        'siteOrJournal',
        'videoTitle',
      ]);
    },
  );

  // The poster is the first image the scene has, the same rule as images.json:
  // the first poster record is the primary one. It is not a field, so it is not
  // in fieldValues.
  test('the poster is the first image the scene has', () {
    final controller = stashController(_FakeClient(null));

    expect(
      controller.posterUrl(
        scene(
          images: [
            'https://example.com/poster.jpg',
            'https://example.com/second.jpg',
          ],
        ),
      ),
      'https://example.com/poster.jpg',
    );

    expect(controller.posterUrl(scene()), '');
  });

  // The app shows no image it has not read from a file, so the popup shows the
  // poster from the file the controller downloads it into. The name is the
  // scene's, so a different scene is a different path, which is what makes an
  // Image resolve it again (`AGENTS.md` rule 5).
  test(
    'the poster preview is written to a file named after the scene',
    () async {
      final downloader = _FakeDownloader(DownloadSuccess('', null));
      final controller = StashController(
        client: _FakeClient(null),
        downloader: downloader,
        domainMap: DomainMap(bundle: _FakeBundle({})),
        fieldList: singleVideoFieldList,
      );

      await controller.downloadPoster(scene());

      expect(
        downloader.paths.single,
        p.join(Directory.systemTemp.path, 'rp_stash_preview_$id'),
      );
    },
  );

  test('the preview file is removed when the popup closes', () async {
    final controller = StashController(
      client: _FakeClient(null),
      downloader: _FakeDownloader(
        const DownloadFailure(DownloadFailureKind.failed),
      ),
      domainMap: DomainMap(bundle: _FakeBundle({})),
      fieldList: singleVideoFieldList,
    );

    final path = controller.previewPath(scene());
    File(path).writeAsStringSync('x');

    await controller.removePreview(scene());

    expect(File(path).existsSync(), isFalse);
  });
}

class _FakeClient implements StashClient {
  _FakeClient(this.result);

  final StashResult? result;

  final calls = <(String, String)>[];

  @override
  HttpClient get client => HttpClient();

  @override
  Future<StashResult> findScene({
    required String sceneId,
    required String apiKey,
  }) async {
    calls.add((sceneId, apiKey));

    return result ?? const StashFailure(StashFailureKind.badResponse);
  }
}

/// A downloader that reaches nothing. It records the paths it was asked to
/// write to and answers with what the test gives it; it writes nothing, so a
/// test that checks what the widget shows checks the widget rather than the
/// filesystem.
class _FakeDownloader implements ImageDownloader {
  _FakeDownloader(this.result);

  final DownloadResult result;

  final paths = <String>[];

  @override
  HttpClient get client => HttpClient();

  @override
  Future<DownloadResult> download(Uri url, String destinationPath) async {
    paths.add(destinationPath);

    return result;
  }
}

/// An asset bundle that answers from a map, so the mapping is read from what
/// the test gives it rather than from the asset on disk.
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
