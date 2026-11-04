import 'dart:convert';
import 'dart:io';

/// StashDB, over its GraphQL API
/// (`https://github.com/stashapp/stash-box/tree/master/graphql/schema`).
///
/// A GraphQL request is one POST with a JSON body, so this uses the same
/// `HttpClient` the image downloader uses; the app has no GraphQL package. Only
/// the fields the form reads are selected, so a response is not read for values
/// the app does not use.
///
/// What comes back is the scene as the schema describes it. Which value goes
/// into which form field is the feature's decision, in `StashController`, not
/// here.
class StashClient {
  StashClient({required this.client});

  static const endpoint = 'https://stashdb.org/graphql';

  /// The site the app links to. The scene link stored in `release.json` is
  /// built from it, so a stored link always points at the site the app queries,
  /// whatever the user pasted.
  static const siteBase = 'https://stashdb.org';

  /// The one query the app sends. `findScene` is the schema's read for a scene
  /// by ID, and the API key is what gives the caller the READ role it needs. A
  /// raw string, because `$id` is the GraphQL variable and not Dart
  /// interpolation.
  static const query = r'''
query($id: ID!) {
  findScene(id: $id) {
    id
    title
    code
    details
    release_date
    production_date
    studio {
      name
      urls { url site { category { name } } }
      parent { name urls { url site { category { name } } } }
    }
    tags { name }
    performers { as performer { name } }
    images { url }
  }
}
''';

  final HttpClient client;

  /// One scene by ID. It shows no messages: the widget maps a failure to
  /// localized text.
  Future<StashResult> findScene({
    required String sceneId,
    required String apiKey,
  }) async {
    try {
      final request = await client.postUrl(Uri.parse(endpoint));

      // stash-box reads the key from the `ApiKey` header, not from
      // Authorization.
      request.headers.set('ApiKey', apiKey);
      request.headers.contentType = ContentType.json;

      request.write(
        jsonEncode({
          'query': query,
          'variables': {'id': sceneId},
        }),
      );

      final response = await request.close();

      if (response.statusCode != 200) {
        return const StashFailure(StashFailureKind.requestFailed);
      }

      return parseResponse(
        jsonDecode(await response.transform(utf8.decoder).join()),
      );
    } catch (_) {
      return const StashFailure(StashFailureKind.requestFailed);
    }
  }

  /// Reads one response. This is the part `test/stash_client_test.dart`
  /// exercises against a captured fixture, because the transport above cannot
  /// be exercised in a test.
  static StashResult parseResponse(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      return const StashFailure(StashFailureKind.badResponse);
    }

    // A response that reports errors has no data for the fields asked for.
    if (decoded['errors'] is List && (decoded['errors'] as List).isNotEmpty) {
      return const StashFailure(StashFailureKind.graphqlError);
    }

    final data = decoded['data'];

    if (data is! Map<String, dynamic>) {
      return const StashFailure(StashFailureKind.badResponse);
    }

    // `findScene` answers null for an id that is not a scene.
    final scene = data['findScene'];

    if (scene is! Map<String, dynamic>) {
      return const StashFailure(StashFailureKind.notFound);
    }

    return StashSceneSuccess(StashScene._parse(scene));
  }
}

/// The scene, as the query above asks for it. A part StashDB does not report is
/// an empty string rather than a guess, the same rule as `MediaInfo`.
class StashScene {
  const StashScene({
    required this.id,
    required this.title,
    required this.code,
    required this.details,
    required this.releaseDate,
    required this.productionDate,
    required this.studio,
    required this.parentStudio,
    required this.performers,
    required this.tags,
    required this.images,
  });

  final String id;

  /// The scene title.
  final String title;

  /// The number on the site, which is what StashDB calls the scene code.
  final String code;

  /// The scene description.
  final String details;

  /// `release_date`. This is the date a scene usually has, and the one
  /// StashDB's page shows. `date` is the deprecated name for the same value, so
  /// it is not read.
  final String releaseDate;

  /// `production_date`. A scene has a value for this only when someone entered
  /// one, which is uncommon.
  final String productionDate;

  /// The studio the scene belongs to. When it has a parent, the studio is the
  /// subsite and the parent is the site.
  final StashStudio studio;

  final StashStudio parentStudio;

  final List<StashAppearance> performers;

  /// Tag names, as StashDB holds them: always in English.
  final List<String> tags;

  /// The scene's images, in the order the response lists them. The first is the
  /// poster, the same rule as `images.json`: the first poster record is the
  /// primary one (`ai/release_structure.md` §4).
  final List<String> images;

  static StashScene _parse(Map<String, dynamic> json) {
    final studio = _map(json['studio']);
    final parent = _map(studio['parent']);

    return StashScene(
      id: _string(json['id']),
      title: _string(json['title']),
      code: _string(json['code']),
      details: _string(json['details']),
      releaseDate: _string(json['release_date']),
      productionDate: _string(json['production_date']),
      studio: StashStudio._parse(studio),
      parentStudio: StashStudio._parse(parent),
      performers: [
        for (final entry in _list(json['performers']))
          if (entry is Map<String, dynamic>)
            StashAppearance(
              name: _string(_map(entry['performer'])['name']),
              alias: _string(entry['as']),
            ),
      ],
      tags: [
        for (final entry in _list(json['tags']))
          if (entry is Map<String, dynamic>) _string(entry['name']),
      ],
      images: [
        for (final entry in _list(json['images']))
          if (entry is Map<String, dynamic>) _string(entry['url']),
      ],
    );
  }
}

/// One studio as the schema describes it: the name, and the URLs it has. The
/// domain the app writes for a studio is read from those URLs, so the name
/// alone is not enough here. A part the response does not report is empty, the
/// same rule as the rest of the scene.
class StashStudio {
  const StashStudio({required this.name, required this.urls});

  static const empty = StashStudio(name: '', urls: []);

  final String name;

  /// The URLs, in the order the response lists them. Which of them is the
  /// studio's own site is what the app reads the domain from, and that is only
  /// known from the category the site is in, so a URL is read with its site.
  final List<StashUrl> urls;

  /// Nothing at all: no name and no URL, which is what a scene with no studio,
  /// or a studio with no parent, reads as.
  bool get isEmpty => name.isEmpty && urls.isEmpty;

  static StashStudio _parse(Map<String, dynamic> json) => StashStudio(
    name: _string(json['name']),
    urls: [
      for (final entry in _list(json['urls']))
        if (entry is Map<String, dynamic>) StashUrl._parse(entry),
    ],
  );
}

/// One URL a studio has: the URL, and the site it is recorded under with that
/// site's category. A studio's URL list is not only its own site: it can hold
/// links to other databases, so the URL alone does not say which one is the
/// site. A part the response does not report is empty, the same rule as the
/// rest of the scene.
class StashUrl {
  const StashUrl({
    required this.url,
    required this.siteName,
    required this.categoryName,
  });

  final String url;

  /// The name of the site the URL is recorded under. A URL is recorded under a
  /// site whether it is that site's own or a link to another database.
  final String siteName;

  /// The name of that site's category, as StashDB holds it. A site with no
  /// category reads as an empty name.
  final String categoryName;

  static StashUrl _parse(Map<String, dynamic> json) {
    final site = _map(json['site']);

    return StashUrl(
      url: _string(json['url']),
      siteName: _string(site['name']),
      categoryName: _string(_map(site['category'])['name']),
    );
  }
}

/// One performer as the scene credits them: the name, and the alias the scene
/// uses.
class StashAppearance {
  const StashAppearance({required this.name, required this.alias});

  final String name;

  final String alias;
}

sealed class StashResult {
  const StashResult();
}

final class StashSceneSuccess extends StashResult {
  const StashSceneSuccess(this.scene);

  final StashScene scene;
}

final class StashFailure extends StashResult {
  const StashFailure(this.kind);

  final StashFailureKind kind;
}

/// What can go wrong when the app asks StashDB for a scene. The first two are
/// checked before the request is made, by `StashController`; the rest are what
/// the request itself can give.
enum StashFailureKind {
  /// The input is neither a scene ID nor a URL that ends with one.
  invalidInput,

  /// No key is stored for StashDB.
  noApiKey,

  /// No connection, or a response that is not 200.
  requestFailed,

  /// A response that is not JSON, or not the shape a GraphQL response has.
  badResponse,

  /// The response reports GraphQL errors.
  graphqlError,

  /// The query answered with no scene.
  notFound,
}

String _string(Object? value) => value is String ? value : '';

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];
