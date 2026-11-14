import 'package:path/path.dart' as p;

import '../../app/app_info.dart';
import '../../service/template/template_renderer.dart';
import '../../service/template/template_store.dart';
import '../release/field_validation.dart';
import '../release/file_size.dart';
import '../release/release.dart';
import '../release/release_fields.dart';
import '../release/release_store.dart';
import '../release/release_type.dart';
import '../screenshots/images.dart';
import '../screenshots/images_store.dart';
import '../upload/hosters.dart';
import 'message_store.dart';
import 'screenshot_layout.dart';

/// The hoster and the URL types the message reads
/// (`ai/description_template.md`). These are per-tracker rules, not appearance
/// rules, so they do not belong in the style file; they belong in a config of
/// their own. Hardcoding them is the first-version choice.
///
/// The poster hoster is named per run: `fastpic.org` for a normal run,
/// `rptest-a` for a `--dev` run, which replaces the real hosters with the mock
/// ones (`ai/upload_images.md`). The first test hoster stands in for fastpic,
/// so a development run produces the same shape of message and the backup block
/// names the second test hoster. Every other hoster is the backup poster. The
/// screenshot block names the hoster on each line, so it needs no rule for
/// choosing one.
const realPosterHoster = 'fastpic.org';
const mockPosterHoster = 'rptest-a';

String get posterHoster => devMode ? mockPosterHoster : realPosterHoster;
const posterUrlType = 'direct_url';
const imageUrlType = 'view_url';
const thumbUrlType = 'thumb_url';

/// The block titles (`ai/description_template.md`). They are written here
/// because the block is built here, so they are the second part of the message
/// that is not data. They are the language the site's rules require, so a
/// second tracker needs its own strings.
const screenshotsTitle = 'Скриншоты';
const backupPosterTitle = 'Резервный постер';

/// The two lines the post shows for one video's streams (`ai/video_pack.md` §7).
/// The words are the same as the app's labels for those fields, but written here
/// as the post's language rather than as l10n keys, for the same reason as the
/// block titles above: the post is in the language the site publishes in, not the
/// language the app's UI is in.
const postVideoStreamLabel = 'Видео';
const postAudioStreamLabel = 'Аудио';

/// Message state and side effects (`ai/description_template.md`). It owns no
/// `Listenable` (rule 3) and shows no messages (rule 13): the widget owns the
/// text box, calls the controller, and maps a result to localized text.
///
/// A generation validates the fields first, so a post is never written from a
/// release that cannot say what the template reads. The validation itself is a
/// pure rule (`field_validation.dart`); this is the side-effect half that calls
/// it and reports what it found.
///
/// The text is written when the user generates it or edits the box, not on
/// save, so the message does not take part in the dirty flag — `release.json`
/// stores no message.
///
/// The controller also knows what the box was built from. The text is the render
/// of the values the template reads, so when those values change what the box
/// shows no longer matches what a render would produce, and the section clears it
/// (`ai/description_template.md` §Section). The values the last render read are
/// the snapshot it compares against.
class MessageController {
  MessageController({
    required this.release,
    required this.templates,
    required this.renderer,
    required this.images,
    required this.store,
    required this.releaseStore,
  });

  final Release release;
  final TemplateStore templates;
  final TemplateRenderer renderer;
  final ImagesStore images;
  final MessageStore store;

  /// `release.json`, for the last-edit stamp these writes make. Writing a file
  /// inside the release is a change to it, so the timestamp is stamped here
  /// too.
  final ReleaseStore releaseStore;

  /// Reads the templates and the style, builds the values, renders the message
  /// and — for a type that has a title — the title, and writes the files the
  /// type has: a type with no title writes no `title.txt`. Regenerating
  /// replaces what is in the box, so the render is the source of truth.
  ///
  /// The fields are validated before anything is read, so a release with a
  /// required field empty is reported as that rather than as a template that is
  /// not in the bundle. Nothing is written when a field is missing: a message
  /// built from an incomplete release is a post with a label and nothing after
  /// it, and the files the section shows would say that.
  Future<MessageResult> generate() async {
    final problems = validateFields(
      fieldListFor(release.releaseType),
      release.fields,
    );

    if (problems.isNotEmpty) {
      return MessageInvalid(problems);
    }

    final loaded = await templates.load(
      tracker: release.tracker,
      releaseType: release.releaseType,
    );

    if (loaded case TemplateFailure failure) {
      return MessageFailure(switch (failure.kind) {
        TemplateFailureKind.templateNotFound =>
          MessageFailureKind.templateNotFound,
        TemplateFailureKind.styleNotFound => MessageFailureKind.styleNotFound,
      });
    }

    final success = loaded as TemplateSuccess;

    // The values the render reads include the signature, so the text it is built
    // from has to be the same text this load read.
    _loaded = success;

    final read = values(await images.load(release.directoryPath));

    final message = renderer.render(
      template: success.template,
      style: success.style,
      values: read,
    );

    if (message case RenderFailure failure) {
      return MessageFailure(switch (failure.kind) {
        RenderFailureKind.unbalancedSection =>
          MessageFailureKind.templateInvalid,
      });
    }

    final text = (message as RenderSuccess).text;

    // A type with no title renders nothing and writes nothing: there is no
    // title file for it and no title row in the section (`hasTitle`,
    // `ai/image_folder_upload.md` §6). The post text does not depend on a
    // title, so a type without one still generates.
    String titleText = '';

    if (hasTitle(release.releaseType)) {
      // The title is plain text, so no style slot applies to it. A tracker
      // without a title template renders to nothing, which is the empty title.
      final title = renderer.render(
        template: success.title,
        style: success.style,
        values: read,
      );

      if (title case RenderFailure failure) {
        return MessageFailure(switch (failure.kind) {
          RenderFailureKind.unbalancedSection =>
            MessageFailureKind.templateInvalid,
        });
      }

      titleText = (title as RenderSuccess).text;
    }

    try {
      await store.save(release.directoryPath, MessageStore.messageFile, text);

      // The title file is written only for a type that has a title, so the
      // release folder of a type without one holds no `title.txt`.
      if (hasTitle(release.releaseType)) {
        await store.save(
          release.directoryPath,
          MessageStore.titleFile,
          titleText,
        );
      }
    } on Exception {
      return const MessageFailure(MessageFailureKind.messageFailed);
    }

    // Only a render that was written is what the box was built from. A write
    // that failed leaves the box and the files as they were, so the snapshot
    // stays the values the earlier content came from.
    _snapshot = read;

    await releaseStore.touchLastEdit(release);

    return MessageGenerated(title: titleText, text: text);
  }

  /// An edit in the box writes the file immediately, like the poster writes its
  /// file. The title is read-only, so it has no write path.
  Future<MessageResult> saveText(String text) async {
    try {
      await store.save(release.directoryPath, MessageStore.messageFile, text);
    } on Exception {
      return const MessageFailure(MessageFailureKind.messageFailed);
    }

    await releaseStore.touchLastEdit(release);

    return const MessageSaved();
  }

  /// The values the last render read. A generation sets it, and so does opening
  /// the section: the text read from the files is taken as what the values were
  /// at that moment, because nothing says what generated them. A reset takes the
  /// current values as the new snapshot, so the next change is a change to the
  /// content that comes after the reset, not to the one already cleared.
  Map<String, String> _snapshot = {};

  /// The templates the last load read, kept because `values()` is asked while the
  /// widget builds and cannot read the bundle again. The signature is one of the
  /// values a template reads, so the snapshot the reset compares against has to be
  /// built from the same text the render was built from. Before the first
  /// generation nothing has been read, and the snapshot taken then is built from
  /// nothing as well, so the comparison cannot see a change it did not record —
  /// the checkbox is what clears the box, through the editor's write path.
  TemplateSuccess? _loaded;

  /// Whether the values the render reads are not the ones the box was built from.
  /// This is the image half of the reset rule: an upload run that added a URL the
  /// message reads changes them, and a run that wrote nothing does not. Neither
  /// does a generation run that wrote files without URLs, because the block shows
  /// only what is uploaded (`ai/description_template.md` §Section).
  bool valuesChanged() =>
      !_same(values(images.loadSync(release.directoryPath)), _snapshot);

  /// Takes the values as they are now as the snapshot, for the case where the box
  /// shows text read from the files rather than a render made in this session.
  void remember() => _snapshot = values(images.loadSync(release.directoryPath));

  /// Removes the two files, so they match the empty box the section shows after a
  /// reset. The title file is removed only for a type that has a title, the same
  /// rule as the write. The snapshot is taken again, because from here the box
  /// holds nothing that a change could make stale.
  Future<MessageResult> clear() async {
    try {
      await store.delete(release.directoryPath, MessageStore.messageFile);

      if (hasTitle(release.releaseType)) {
        await store.delete(release.directoryPath, MessageStore.titleFile);
      }
    } on Exception {
      return const MessageFailure(MessageFailureKind.messageFailed);
    }

    _snapshot = values(images.loadSync(release.directoryPath));

    await releaseStore.touchLastEdit(release);

    return const MessageCleared();
  }

  /// The values the template reads: the fields as `release.json` writes them,
  /// the release record, the image variables, `appVersion`, the two values the
  /// render builds from the fields — the resolution line, and the formats
  /// as the post lists them — and the app signature block
  /// (`ai/description_template.md` §Variables, §App signature). A local path is
  /// not something a post shows, so the source is not a value.
  ///
  /// Only the release's own fields are here. A per-item value is not one a
  /// template can read, because the renderer has no iteration; showing items
  /// needs the block grouping rule that decides how they would be shown
  /// (`ai/release_structure.md` §3, `ai/video_pack.md` §8).
  ///
  /// Only the fields a template reads are here, which is what the field list
  /// says with `readByTemplate`. The two draft names are stored but no template
  /// reads them, so they are not part of what a render would produce, and
  /// writing one must not make the content the Message section shows stale
  /// (`ai/uploading_draft.md` §4). A key the field list does not know is not a
  /// value a template can read either — except the values the app builds from
  /// the ones it does know, which no field list can state and which the
  /// paragraph above names.
  Map<String, String> values(ImagesManifest manifest) {
    final read = {
      for (final field in fieldListFor(release.releaseType).fields)
        if (field.readByTemplate) field.name: release.fields.value(field.name),
      'name': release.name,
      'tracker': release.tracker.name,
      'releaseType': release.releaseType.name,
      'posterUrl': _url(
        _first(manifest.of(ImageKind.poster)),
        posterHoster,
        posterUrlType,
      ),
      'screenshotSection': _screenshotSection(manifest),
      'appVersion': appVersion,
    };

    // The values a render reads that no field list can state: a block variable
    // is not something a template can read from itself; the two resolutions are
    // one line of the post, so the value for that line is built here; and the
    // formats are the one field value a post lists differently from the way the
    // app shows it (`ai/description_template.md` §Variables).
    return {
      ...read,
      'resolutionMinMax': _resolutionMinMax(
        read['minResolution'],
        read['maxResolution'],
      ),
      'imageFormats': _messageFormats(read['imageFormats']),
      'appSignature': _appSignature(read),
    };
  }

  /// The two resolutions as one line of the post says them: `min-max`, or the
  /// value once when the smallest and the largest photo are the same photo —
  /// a set with one photo cannot be described as a range — or nothing when
  /// neither has been written, so a title line that shows the pair does not
  /// say an empty half (`ai/description_template.md` §Variables).
  String _resolutionMinMax(String? min, String? max) {
    final lower = min ?? '';
    final upper = max ?? '';

    if (lower.isEmpty) {
      return upper;
    }

    if (upper.isEmpty || lower == upper) {
      return lower;
    }

    return '$lower-$upper';
  }

  /// The formats as the post lists them: the value as the field stores it, and
  /// nothing when every format in it is jpg or jpeg, because the site does not
  /// write a line for a post whose images are all jpg
  /// (`ai/description_template.md` §Variables). The field, its row and
  /// `release.json` keep what the scan counted, so the app still shows an
  /// all-jpg set as `jpg`; only what a render reads is the empty one, and that
  /// is what makes the line the site wants dropped stay dropped. A mixed set
  /// still lists jpg with the others.
  String _messageFormats(String? stored) {
    final value = stored ?? '';

    return value.split(', ').every(_isJpeg) ? '' : value;
  }

  /// Whether a format is the one the site does not list. `jpg` and `jpeg` are
  /// the same format, and both are in the photo extension list, so the pair is
  /// what the rule has to name.
  bool _isJpeg(String format) => format == 'jpg' || format == 'jpeg';

  /// The app signature block (`ai/description_template.md` §App signature): the
  /// app signature file rendered with the values above, or nothing when the
  /// release does not include it. A block variable has no failure path — the
  /// renderer reports an unbalanced section only to the caller that reads a
  /// template, and here the caller is the value map — so a signature that cannot
  /// be rendered produces nothing; validating the asset files is in `lib/TODO.MD`.
  String _appSignature(Map<String, String> values) {
    final loaded = _loaded;

    if (loaded == null || !release.includeAppSignature) {
      return '';
    }

    final block = renderer.render(
      template: loaded.signature,
      style: loaded.style,
      values: values,
    );

    return block is RenderSuccess ? block.text : '';
  }

  /// Two value maps as the render would read them. A map has no value equality,
  /// so this is the comparison the staleness check needs.
  bool _same(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) {
      return false;
    }

    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }

    return true;
  }

  /// Whether every image the message shows has been uploaded to the poster
  /// hoster. The message is made of those URLs, so while none of them exists
  /// there is nothing to put in the post, and the section does not offer a
  /// generation until there is (`ai/description_template.md` §3).
  ///
  /// The check is per record, not per kind: a record holds only the hosters it
  /// was uploaded to, so a record with no entry for the poster hoster is an
  /// upload that did not happen. An empty manifest is not "all uploaded", it is
  /// nothing uploaded.
  bool allImagesUploadedToPosterHoster() {
    final manifest = images.loadSync(release.directoryPath);

    final records = [
      ...manifest.of(ImageKind.poster),
      ...manifest.of(ImageKind.photo),
      ...manifest.of(ImageKind.screenshot),
      ...manifest.of(ImageKind.screenlist),
    ];

    if (records.isEmpty) {
      return false;
    }

    return records.every(
      (record) =>
          (record.urls[posterHoster] ?? const <String, String>{}).isNotEmpty,
    );
  }

  /// A URL from a record for one hoster. A record holds only the hosters it was
  /// uploaded to, so an entry that is absent is an upload that did not happen.
  String _url(ImageRecord? record, String hosterName, String urlType) {
    if (record == null) {
      return '';
    }

    return record.urls[hosterName]?[urlType] ?? '';
  }

  /// The block of post images (`ai/description_template.md`): one spoiler
  /// holding one spoiler per hoster, then the backup poster. A record appears
  /// under every hoster it was uploaded to; a hoster with nothing uploaded
  /// produces no spoiler, and an image with no `thumb_url` is skipped. The
  /// images of one hoster are on one line with nothing between them, so the
  /// site renders them as one block; the spoiler tags stay on their own lines.
  /// The shape is written here, so the style file cannot change it.
  ///
  /// The block of post images (`ai/description_template.md`): the outer spoiler,
  /// then the backup poster. Only the video pack has a choice of shape, because
  /// the two shapes name a video — a file name, a duration, a resolution and a
  /// size — and the other types have nothing to name, so the flat block is the
  /// only shape they can have. The switch is exhaustive over the release types, so
  /// a type added to `ReleaseType` has to say which shape it uses.
  String _screenshotSection(ImagesManifest manifest) =>
      switch (release.releaseType) {
        ReleaseType.videoPack => switch (release.screenshotLayout) {
          ScreenshotLayout.byHoster => _blockByHoster(manifest),
          ScreenshotLayout.byItem => _blockByItem(manifest),
        },
        ReleaseType.singleVideo => _blockFlat(manifest),
        ReleaseType.photosetPack => _blockFlat(manifest),
        ReleaseType.singlePhotoset => _blockFlat(manifest),
        ReleaseType.imageFolderUpload => _blockFlat(manifest),
      };

  /// The records the block shows, in the order it shows them: photos, then
  /// screenshots, then the screenlist. The poster is not one of them; it is the
  /// backup half of the block.
  List<ImageRecord> _blockRecords(ImagesManifest manifest) => [
    ...manifest.of(ImageKind.photo),
    ...manifest.of(ImageKind.screenshot),
    ...manifest.of(ImageKind.screenlist),
  ];

  /// The records of one item, in the same order. For a pack every block record
  /// names the item it was generated for, so the grouping covers all of them;
  /// the poster is the one record that does not, and the backup half shows it.
  List<ImageRecord> _itemRecords(ImagesManifest manifest, String itemPath) => [
    for (final record in _blockRecords(manifest))
      if (record.item == itemPath) record,
  ];

  /// The lines one hoster has for a set of records. A record it was not uploaded
  /// to draws nothing, so a group with nothing in it is not built.
  List<String> _hosterLines(List<ImageRecord> records, String hosterName) {
    final lines = <String>[];

    for (final record in records) {
      final line = _item(record, hosterName);

      if (line.isNotEmpty) {
        lines.add(line);
      }
    }

    return lines;
  }

  /// The flat shape, for the types that cannot group: one spoiler per hoster with
  /// every image that hoster has.
  String _blockFlat(ImagesManifest manifest) {
    final groups = <String>[];

    for (final hoster in hosters) {
      final lines = _hosterLines(_blockRecords(manifest), hoster.name);

      if (lines.isEmpty) {
        continue;
      }

      groups.add(_hosterGroup(hoster.name, [lines.join()]));
    }

    return _block(groups, manifest);
  }

  /// Layout 1: one spoiler per hoster, and inside it one per item — the title
  /// line, the two stream lines, then that item's images on that hoster.
  String _blockByHoster(ImagesManifest manifest) {
    final groups = <String>[];

    for (final hoster in hosters) {
      final items = <String>[];

      for (final item in release.items) {
        final lines = _hosterLines(
          _itemRecords(manifest, item.path),
          hoster.name,
        );

        if (lines.isEmpty) {
          continue;
        }

        items.add(_itemGroup(item, [lines.join()]));
      }

      if (items.isEmpty) {
        continue;
      }

      groups.add(_hosterGroup(hoster.name, items));
    }

    return _block(groups, manifest);
  }

  /// Layout 2: one spoiler per item — the title line, the two stream lines, then
  /// one spoiler per hoster inside it.
  String _blockByItem(ImagesManifest manifest) {
    final groups = <String>[];

    for (final item in release.items) {
      final records = _itemRecords(manifest, item.path);

      if (records.isEmpty) {
        continue;
      }

      final hosterGroups = <String>[];

      for (final hoster in hosters) {
        final lines = _hosterLines(records, hoster.name);

        if (lines.isEmpty) {
          continue;
        }

        hosterGroups.add(_hosterGroup(hoster.name, [lines.join()]));
      }

      if (hosterGroups.isEmpty) {
        continue;
      }

      groups.add(_itemGroup(item, hosterGroups));
    }

    return _block(groups, manifest);
  }

  /// One hoster's group. The images of one hoster are one line, so the site
  /// renders them as one block; a caller that has whole groups passes them as
  /// they are, because each is its own line.
  String _hosterGroup(String hosterName, List<String> lines) =>
      _spoiler('$screenshotsTitle $hosterName', lines);

  /// One item's group: the title line, the two stream lines, then whatever the
  /// layout puts after them.
  String _itemGroup(ReleaseItem item, List<String> content) =>
      _spoiler(_titleLine(item), [..._streamLines(item), ...content]);

  /// The line an item's group is titled with: the file name, the duration, the
  /// resolution and the size. A value the item does not have is left out rather
  /// than shown as an empty part, the same rule as the rest of the section.
  String _titleLine(ReleaseItem item) => [
    p.basename(item.path),
    item.fields.value('duration'),
    item.fields.value('videoType'),
    humanFileSize(item.fields.value('fileSize')),
  ].where((part) => part.isNotEmpty).join(' | ');

  /// The two lines the post shows for one video's streams, and only the ones it
  /// has a value for. The label is bold: the tags are part of the block's shape,
  /// which is written here like the spoiler tags are, so the style file cannot
  /// change them.
  List<String> _streamLines(ReleaseItem item) => [
    if (item.fields.value('videoStream').isNotEmpty)
      '[b]$postVideoStreamLabel[/b]: ${item.fields.value('videoStream')}',
    if (item.fields.value('audioStream').isNotEmpty)
      '[b]$postAudioStreamLabel[/b]: ${item.fields.value('audioStream')}',
  ];

  /// The outer block: the groups, then the backup poster. The shapes differ only
  /// in how the groups are built, so the backup half and the empty case are
  /// written once.
  String _block(List<String> groups, ImagesManifest manifest) {
    final backup = <String>[];

    for (final record in manifest.of(ImageKind.poster)) {
      for (final hoster in hosters) {
        if (hoster.name == posterHoster) {
          continue;
        }

        final item = _item(record, hoster.name);

        if (item.isNotEmpty) {
          backup.add(item);
        }
      }
    }

    if (backup.isNotEmpty) {
      groups.add(_spoiler(backupPosterTitle, [backup.join()]));
    }

    if (groups.isEmpty) {
      return '';
    }

    return _spoiler(screenshotsTitle, groups);
  }

  /// A spoiler: the title line, the lines inside it, the closing tag. The lines
  /// of a group are each their own line, which is what keeps the nested
  /// spoilers apart.
  String _spoiler(String title, List<String> lines) =>
      ['[spoiler="$title"]', ...lines, '[/spoiler]'].join('\n');

  /// One image, or an empty string when the record was not uploaded to that
  /// hoster or has no thumb. The link is the view URL, the picture shown is the
  /// thumb URL.
  String _item(ImageRecord record, String hosterName) {
    final view = _url(record, hosterName, imageUrlType);
    final thumb = _url(record, hosterName, thumbUrlType);

    if (view.isEmpty || thumb.isEmpty) {
      return '';
    }

    return '[url=$view][img]$thumb[/img][/url]';
  }

  ImageRecord? _first(List<ImageRecord> records) =>
      records.isEmpty ? null : records.first;
}

sealed class MessageResult {
  const MessageResult();
}

/// A generation: the title and the text, both rendered and both written.
final class MessageGenerated extends MessageResult {
  const MessageGenerated({required this.title, required this.text});

  final String title;
  final String text;
}

/// A write of the text box. There is nothing to report back: the widget already
/// has the text.
final class MessageSaved extends MessageResult {
  const MessageSaved();
}

/// The two files removed by a reset. Nothing to report back either: the widget
/// has already cleared the box and the title line.
final class MessageCleared extends MessageResult {
  const MessageCleared();
}

/// A generation refused before anything was read: the fields the message reads
/// are not complete. The answer is field names, not labels — a field list is
/// data, and the words for a problem come from `fieldProblemText` (rule 13).
final class MessageInvalid extends MessageResult {
  const MessageInvalid(this.problems);

  final List<FieldProblem> problems;
}

final class MessageFailure extends MessageResult {
  const MessageFailure(this.kind);

  final MessageFailureKind kind;
}

enum MessageFailureKind {
  /// The template for this tracker and release type is not in the bundle. Other
  /// release types have no field list yet, so they have no template either.
  templateNotFound,

  /// The style file is not in the bundle.
  styleNotFound,

  /// A section is not closed on the same line.
  templateInvalid,

  /// `message.txt` could not be written.
  messageFailed,
}
