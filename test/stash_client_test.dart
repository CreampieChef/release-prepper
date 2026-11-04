import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/service/network/stash_client.dart';

void main() {
  // A captured StashDB response for the query the app sends. The field names
  // are the schema's, so this is the shape the parser reads.
  const response = '''
{
  "data": {
    "findScene": {
      "id": "b3c6f0e4-8f1e-4c2b-9a1d-6f0a2b3c4d5e",
      "title": "Example title",
      "code": "12345",
      "details": "Description text",
      "release_date": "2024-06-01",
      "production_date": "2024-05-17",
      "studio": {
        "name": "Example Studio",
        "urls": [
          {
            "url": "https://www.example-studio.com",
            "site": {
              "name": "Example Site",
              "category": { "name": "Primary sources" }
            }
          }
        ],
        "parent": {
          "name": "Example Network",
          "urls": [
            {
              "url": "https://www.example-network.com",
              "site": {
                "name": "Example Network Site",
                "category": { "name": "Primary sources" }
              }
            }
          ]
        }
      },
      "tags": [ { "name": "anal" }, { "name": "solo" } ],
      "performers": [
        { "as": "Alias", "performer": { "name": "Real Name" } },
        { "as": null, "performer": { "name": "Another" } }
      ],
      "images": [
        { "url": "https://example.com/poster.jpg" },
        { "url": "https://example.com/second.jpg" }
      ]
    }
  }
}''';

  test('the values are read from the fields the schema names', () {
    final result = StashClient.parseResponse(jsonDecode(response));

    expect(result, isA<StashSceneSuccess>());

    final scene = (result as StashSceneSuccess).scene;

    expect(scene.id, 'b3c6f0e4-8f1e-4c2b-9a1d-6f0a2b3c4d5e');
    expect(scene.title, 'Example title');
    expect(scene.code, '12345');
    expect(scene.details, 'Description text');
    expect(scene.releaseDate, '2024-06-01');
    expect(scene.productionDate, '2024-05-17');
    expect(scene.studio.name, 'Example Studio');
    // A URL is read with the site it is recorded under and that site's
    // category, because that is what says whether it is the studio's own site
    // or a link to another database.
    expect(
      scene.studio.urls
          .map((entry) => (entry.url, entry.siteName, entry.categoryName))
          .toList(),
      [('https://www.example-studio.com', 'Example Site', 'Primary sources')],
    );
    expect(scene.parentStudio.name, 'Example Network');
    expect(
      scene.parentStudio.urls
          .map((entry) => (entry.url, entry.siteName, entry.categoryName))
          .toList(),
      [
        (
          'https://www.example-network.com',
          'Example Network Site',
          'Primary sources',
        ),
      ],
    );
    expect(scene.tags, ['anal', 'solo']);
    expect(
      scene.performers
          .map((appearance) => (appearance.name, appearance.alias))
          .toList(),
      [
        // The alias is what the scene credits the performer as; a null alias is
        // no alias.
        ('Real Name', 'Alias'),
        ('Another', ''),
      ],
    );

    // The order the response lists the images in is kept, because the first one
    // is the poster.
    expect(scene.images, [
      'https://example.com/poster.jpg',
      'https://example.com/second.jpg',
    ]);
  });

  // A part the response does not report is an empty string rather than a guess,
  // the same rule as MediaInfo.
  test('a part the response does not report is empty', () {
    final result = StashClient.parseResponse(
      jsonDecode('''
{"data": {"findScene": {
  "id": "b3c6f0e4-8f1e-4c2b-9a1d-6f0a2b3c4d5e",
  "title": null,
  "studio": null,
  "performers": [],
  "tags": null,
  "images": null
}}}'''),
    );

    final scene = (result as StashSceneSuccess).scene;

    expect(scene.title, '');
    expect(scene.releaseDate, '');
    expect(scene.productionDate, '');
    expect(scene.studio.isEmpty, isTrue);
    expect(scene.parentStudio.isEmpty, isTrue);
    expect(scene.performers, isEmpty);
    expect(scene.tags, isEmpty);
    expect(scene.images, isEmpty);
  });

  // A site is a part of the URL the response may not report, and a category is
  // a part of the site it may not report. Both read as an empty name, so the
  // app has no category to choose by and reads the domain from the first URL
  // with a host.
  test(
    'a URL with no site, or a site with no category, reads as no category',
    () {
      final result = StashClient.parseResponse(
        jsonDecode('''
{"data": {"findScene": {
  "id": "b3c6f0e4-8f1e-4c2b-9a1d-6f0a2b3c4d5e",
  "studio": {
    "name": "Example Studio",
    "urls": [
      { "url": "https://example-studio.com" },
      { "url": "https://iafd.com/name", "site": { "name": "IAFD", "category": null } }
    ]
  }
}}}'''),
      );

      final scene = (result as StashSceneSuccess).scene;

      expect(
        scene.studio.urls
            .map((entry) => (entry.url, entry.siteName, entry.categoryName))
            .toList(),
        [
          ('https://example-studio.com', '', ''),
          ('https://iafd.com/name', 'IAFD', ''),
        ],
      );
    },
  );

  test('a response that reports errors is a GraphQL error', () {
    expect(
      StashClient.parseResponse(
        jsonDecode('{"errors": [{"message": "invalid id"}]}'),
      ),
      isA<StashFailure>().having(
        (failure) => failure.kind,
        'kind',
        StashFailureKind.graphqlError,
      ),
    );
  });

  // findScene answers null for an id that is not a scene. That is not an error,
  // so it is reported as its own case.
  test('a query that answers with no scene is not found', () {
    expect(
      StashClient.parseResponse(jsonDecode('{"data": {"findScene": null}}')),
      isA<StashFailure>().having(
        (failure) => failure.kind,
        'kind',
        StashFailureKind.notFound,
      ),
    );
  });

  // The transport decodes the body before it calls this, so what reaches the
  // parser is whatever the body decoded to. A body that is not JSON never gets
  // here; what does is a JSON value that is not the shape a GraphQL response
  // has.
  test(
    'a response that is not the shape a GraphQL response has is no result',
    () {
      for (final decoded in [
        null,
        jsonDecode('[]'),
        jsonDecode('{"data": null}'),
      ]) {
        expect(
          StashClient.parseResponse(decoded),
          isA<StashFailure>().having(
            (failure) => failure.kind,
            'kind',
            StashFailureKind.badResponse,
          ),
          reason: '$decoded',
        );
      }
    },
  );
}
