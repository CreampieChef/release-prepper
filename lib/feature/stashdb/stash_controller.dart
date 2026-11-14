import 'dart:io';

import 'package:path/path.dart' as p;

import '../../service/network/image_downloader.dart';
import '../../service/network/stash_client.dart';
import '../../service/stashdb/domain_map.dart';
import '../release/release_fields.dart';

/// StashDB state for the editor: what the app asks for, and which form field
/// each value goes into. It owns no `Listenable` (rule 3) and shows no messages
/// (rule 13): the widget calls `fetch()`, shows what came back, and maps a
/// failure to localized text.
class StashController {
  StashController({
    required this.client,
    required this.downloader,
    required this.domainMap,
    required this.fieldList,
  });

  final StashClient client;

  /// The poster the popup shows is bytes the app has to fetch before it can
  /// display them, and a download is a side effect, so it belongs here rather
  /// than in the widget (rule 2). The app shows no image it has not read from a
  /// file, so the popup shows the file this writes.
  final ImageDownloader downloader;

  /// The domains the app writes in a form of its own, from the bundled asset
  /// (`assets/stashdb/domain_map.json`). It is read by `fieldValues()`, which
  /// is the only path that needs it; the bundle caches what it has read, so the
  /// asset is read once rather than per field.
  final DomainMap domainMap;

  /// The field list of the type the section is filling, which is what says
  /// which names exist for it (`ai/release_structure.md` §3). The controller is
  /// not the place that knowledge is kept: it states which values a scene can
  /// answer for, and the field list decides which of them this type has a field
  /// for. The two site names are the same value written under different names,
  /// so a type with no name for a value is given nothing for it rather than a
  /// value for a field it does not have.
  final FieldList fieldList;

  /// The names a scene can answer for. Which of them the section shows with a
  /// checkbox is `fillableFields`, and the order the section lists the values
  /// in is the order the type's field list lists them. The two site names are
  /// the same value written under different names: the field that says the
  /// subsite and the site apart, and the single site field.
  static const _sceneValues = <String>[
    'cast',
    'videoTitle',
    'siteNumber',
    'subsiteAndSite',
    'siteOrJournal',
    'productionDate',
    'genreTags',
    'description',
  ];

  /// The fields the section can fill for this type: the names a scene can
  /// answer for that this type's field list has. The fields the app fills from
  /// the movie file are not among them, and `additionalInfo` has no StashDB
  /// value at all. `sceneUrl` is not among them either: it is not a value the
  /// section offers, it is what the user typed, and the section writes it
  /// through the same path. For a single video this is the seven names it has;
  /// for the single photoset the site is its own field and there is no site
  /// number to offer, because that type has no field for one
  /// (`ai/single_photoset.md` §9).
  List<String> fillableFields() => [
    for (final field in fieldList.fields)
      if (_sceneValues.contains(field.name)) field.name,
  ];

  /// The category a studio's own site is in. A studio's URL list can hold links
  /// to other databases, and those are often listed first, so the first URL is
  /// not the site the studio is on; the one in this category is.
  static const primarySourceCategory = 'Primary sources';

  /// The site a studio URL is recorded under when it does not match a site
  /// StashDB knows. It is what is tried when no URL is in the Primary sources
  /// category.
  static const studioSiteName = 'Studio';

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// A scene ID from what the user pasted: a UUID, or the last part of a scene
  /// URL. Null when the input is neither, so the widget says what is wrong
  /// rather than sending it.
  static String? sceneId(String input) {
    final text = input.trim();

    if (_uuid.hasMatch(text)) return text.toLowerCase();

    // A StashDB scene link is `<siteBase>/scenes/<uuid>`. The last part of the
    // path is the id whatever the rest of the link looks like, so a query or a
    // fragment is not read as part of it, and a link on another host still
    // gives the same id.
    final uri = Uri.tryParse(text);

    if (uri == null || !uri.hasScheme) return null;

    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();

    if (segments.isEmpty) return null;

    final last = segments.last;

    return _uuid.hasMatch(last) ? last.toLowerCase() : null;
  }

  /// Asks for one scene. The key is what the widget read from the settings, so
  /// the controller builds no dependency of its own (rule 4).
  Future<StashResult> fetch({
    required String input,
    required String apiKey,
  }) async {
    final id = sceneId(input);

    if (id == null) {
      return const StashFailure(StashFailureKind.invalidInput);
    }

    if (apiKey.isEmpty) {
      return const StashFailure(StashFailureKind.noApiKey);
    }

    return await client.findScene(sceneId: id, apiKey: apiKey);
  }

  /// The link the section stores: the scene link built from the id the app
  /// asked for, not the text the user pasted. So what `release.json` holds is
  /// always a link on the site the app queries — a pasted id becomes a link,
  /// and a pasted link keeps no query or fragment.
  String sceneUrl(StashScene scene) =>
      '${StashClient.siteBase}/scenes/${scene.id}';

  /// The poster. The first image the scene has is the poster, the same rule as
  /// `images.json`: the first poster record is the primary one
  /// (`ai/release_structure.md` §4). It is not a field, so it is not in
  /// `fieldValues`; the editor writes it through its own poster path.
  String posterUrl(StashScene scene) =>
      scene.images.isEmpty ? '' : scene.images.first;

  /// The file the poster preview is written to, named after the scene so a
  /// different scene is a different path — which is what makes an `Image`
  /// resolve it again (`AGENTS.md` rule 5).
  String previewPath(StashScene scene) =>
      p.join(Directory.systemTemp.path, 'rp_stash_preview_${scene.id}');

  /// The poster bytes for the popup to show. The format is not checked here:
  /// the image is only displayed, not stored, and Flutter reads a file by
  /// looking at its bytes; the poster path is the one that checks the format
  /// before it writes the file.
  Future<DownloadResult> downloadPoster(StashScene scene) =>
      downloader.download(Uri.parse(posterUrl(scene)), previewPath(scene));

  /// Removes the preview file when the popup closes. Failing to remove it
  /// changes nothing the user sees, because the popup is already gone.
  Future<void> removePreview(StashScene scene) async {
    try {
      await File(previewPath(scene)).delete();
    } catch (_) {
      // Nothing to report.
    }
  }

  /// The values for the form, in the order the type's field list lists them, so
  /// a value for a name the type does not have is not offered for it. A field
  /// is the value as the scene reported it, except where the import changes it,
  /// which is what `changedValues()` describes. A field StashDB has nothing for
  /// is left out rather than written as an empty string, so the section shows
  /// only what it can actually fill.
  ///
  /// It is async because the domains the app writes in a form of its own come
  /// from a bundled asset, and an asset read is async. The mapping is read once
  /// here and passed to `_domain()`, so the field path does not read the asset
  /// per studio. `changedValues()` is not async: the mapping changes a value,
  /// not which URL a value was read from, so it has nothing to note.
  Future<Map<String, String>> fieldValues(StashScene scene) async {
    final domains = await domainMap.load();

    String value(String name) => switch (name) {
      // The credit as the scene shows it: the alias when the scene uses one.
      'cast' => [
        for (final appearance in scene.performers)
          appearance.alias.isEmpty ? appearance.name : appearance.alias,
      ].join(', '),
      'videoTitle' => _kept(_titleParts(scene)),
      'siteNumber' => scene.code,
      // The subsite is the studio when it has a parent, and the parent is the
      // site, and both are written as their domain rather than as the name
      // StashDB holds. The two names the types use for this value are the same
      // value written under different names: the single video's field says both
      // parts, separated by " / ", and the single photoset has one site field,
      // so the same string is what goes into it (`ai/single_photoset.md` §9).
      'subsiteAndSite' || 'siteOrJournal' =>
        scene.parentStudio.isEmpty
            ? _domain(scene.studio, domains)
            : '${_domain(scene.studio, domains)} / '
                  '${_domain(scene.parentStudio, domains)}',
      // The app's field is the production date, but StashDB has a value for
      // `production_date` only when someone entered one; the date a scene
      // usually has is its release date. So the release date is what the field
      // gets, and the production date is the fallback.
      'productionDate' =>
        scene.releaseDate.isEmpty ? scene.productionDate : scene.releaseDate,
      'genreTags' => scene.tags.join(', '),
      'description' => scene.details,
      // Reached only for a name a scene cannot answer for, which
      // `fillableFields()` keeps out of the map.
      _ => '',
    };

    return {
      for (final field in fillableFields())
        if (value(field).isNotEmpty) field: value(field),
    };
  }

  /// What the import changed rather than copied, in the order the type's field
  /// list lists the values — the order the popup lists them in. A value it
  /// copied as the scene reported it is not here: the popup shows what was done
  /// to a value, so the user can see that what the app writes is not what
  /// StashDB reported. A field this type has no name for produces no note,
  /// because there is no value for it to describe.
  List<ImportNote> changedValues(StashScene scene) {
    final notes = <ImportNote>[];

    for (final field in fillableFields()) {
      switch (field) {
        case 'videoTitle':
          final parts = _titleParts(scene);

          if (parts.any((part) => part.cut)) {
            notes.add(
              ImportNote(
                field: field,
                kind: ImportNoteKind.siteNumberStrippedFromTitle,
                parts: parts,
              ),
            );
          }

        case 'subsiteAndSite':
        case 'siteOrJournal':
          // A domain read from a URL that is not in the Primary sources
          // category is not what the rule would give, so the note shows the URL
          // it was read from, and names the field it is written into, which is
          // the name this type has for it. The subsite is the first part of the
          // value, so its note comes first, and a studio with no URL to read
          // has no URL to show.
          for (final studio in [scene.studio, scene.parentStudio]) {
            final source = _source(studio);

            if (source == null ||
                source.url.categoryName == primarySourceCategory) {
              continue;
            }

            notes.add(
              ImportNote(
                field: field,
                kind: ImportNoteKind.domainFromOtherUrl,
                parts: [ImportPart(text: source.url.url, cut: false)],
              ),
            );
          }

        default:
          // A value the import copies as the scene reported it has nothing to
          // note.
          break;
      }
    }

    return notes;
  }

  /// The title as the parts the app keeps and the parts it cuts. For the single
  /// video the site number is a field of its own, so a title that contains it
  /// says the same thing twice, and every occurrence is cut; for the single
  /// photoset there is no field for the number, but the number is still cut,
  /// because a set name is the title without it (`ai/single_photoset.md` §9). A
  /// number that is not in the title, or a scene with no number, leaves the
  /// title as one kept part; an empty stretch of text is not a part.
  List<ImportPart> _titleParts(StashScene scene) {
    final code = scene.code;

    if (code.isEmpty) {
      return [
        if (scene.title.isNotEmpty) ImportPart(text: scene.title, cut: false),
      ];
    }

    final parts = <ImportPart>[];
    var rest = scene.title;

    while (true) {
      final at = rest.indexOf(code);

      if (at < 0) {
        if (rest.isNotEmpty) {
          parts.add(ImportPart(text: rest, cut: false));
        }
        break;
      }

      if (at > 0) {
        parts.add(ImportPart(text: rest.substring(0, at), cut: false));
      }

      parts.add(ImportPart(text: code, cut: true));

      rest = rest.substring(at + code.length);
    }

    return parts;
  }

  /// The value as the app writes it: the parts it keeps, joined, with the ends
  /// trimmed, because a cut leaves the space that was in front of the number.
  String _kept(List<ImportPart> parts) => [
    for (final part in parts)
      if (!part.cut) part.text,
  ].join().trim();

  /// The domain a studio is known by: the host of the URL the app reads it
  /// from, without `www.`. A host is lowercase, so the brand part keeps the
  /// studio name's capitalization when the name is the same word as the host's
  /// label; when they are not the same word, the host is written as the URL
  /// gives it. A studio with no URL with a host has no domain to read, so the
  /// name as StashDB reports it is what the field gets — nothing is invented.
  ///
  /// A domain that is in the mapping is what the field gets before any of
  /// this, because the mapping is the list of the domains the app writes in a
  /// form the rule cannot give; the value is used exactly as the file writes
  /// it. A studio with no URL has no domain to look up, so the mapping cannot
  /// apply to it.
  String _domain(StashStudio studio, Map<String, String> domains) {
    final source = _source(studio);

    if (source == null) return studio.name;

    final mapped = domains[source.host];

    if (mapped != null) return mapped;

    final host = source.host;
    final dot = host.indexOf('.');

    if (dot <= 0) return host;

    final label = host.substring(0, dot);
    final tld = host.substring(dot);

    final name = studio.name.replaceAll(' ', '');

    return name.toLowerCase() == label ? '$name$tld' : '$label$tld';
  }

  /// The URL the domain is read from, with its host, or null when the studio
  /// has no URL with a host. A URL with no host is not a domain, so it is not a
  /// candidate at any step. The first URL is not the site the studio is on when
  /// the list has links to other databases in it, and it often does, so the URL
  /// in the Primary sources category is the one the domain is read from. When
  /// none is in that category, the URL recorded under the site named Studio is
  /// what is tried next; when there is neither, the first URL with a host is
  /// what is read, as before.
  ({StashUrl url, String host})? _source(StashStudio studio) {
    ({StashUrl url, String host})? first;
    ({StashUrl url, String host})? site;

    for (final url in studio.urls) {
      final host = _host(url);

      if (host == null) continue;

      final candidate = (url: url, host: host);

      first ??= candidate;

      if (url.siteName == studioSiteName) site ??= candidate;

      if (url.categoryName == primarySourceCategory) return candidate;
    }

    return site ?? first;
  }

  /// The host of one URL, without `www.`. A value with no scheme is read as a
  /// host, because StashDB stores URLs as text and one without a scheme is
  /// still the host of a site.
  String? _host(StashUrl url) {
    final text = url.url.trim();

    if (text.isEmpty) return null;

    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');

    if (uri == null || uri.host.isEmpty) return null;

    return uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
  }
}

/// One value the import changed rather than copied: the field it is for, what
/// was done to it, and the value as the scene reported it as its parts. The
/// popup lists these under "Import notes", with the cut parts struck through, so
/// what the app writes is not shown as if it were what StashDB reported.
class ImportNote {
  const ImportNote({
    required this.field,
    required this.kind,
    required this.parts,
  });

  /// The field the value goes into, which is the name the popup's row has, so
  /// the widget resolves its label through AppLocalizations.
  final String field;

  /// What was done to the value, which is the message the widget picks for it.
  final ImportNoteKind kind;

  final List<ImportPart> parts;
}

/// What an import post-processing did to a value. The widget maps a kind to one
/// of its messages, the same way a failure kind is mapped (rule 13), so a new
/// post-processing is a new kind and a new message rather than a new widget.
enum ImportNoteKind {
  /// The title contained the site number, so it was cut off the title.
  siteNumberStrippedFromTitle,

  /// The domain was read from a URL that is not in the Primary sources
  /// category, so the value is not what the rule would give. The parts are the
  /// URL it was read from.
  domainFromOtherUrl,
}

/// One part of a value: the text, and whether the app cuts it.
class ImportPart {
  const ImportPart({required this.text, required this.cut});

  final String text;

  final bool cut;
}
