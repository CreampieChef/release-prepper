import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../service/native_tools/ffmpeg.dart';
import '../../service/native_tools/ffprobe.dart';
import '../../service/native_tools/media_info.dart';
import '../../service/network/image_downloader.dart';
import '../draft/draft_section.dart';
import '../image_folder/image_folder_section.dart';
import '../message/message_section.dart';
import '../message/screenshot_layout.dart';
import '../photosets/photosets_section.dart';
import '../screenshots/images_store.dart';
import '../screenshots/screenshots_section.dart';
import '../stashdb/stash_section.dart';
import '../tab/tab_manager.dart';
import '../torrent/torrent_section.dart';
import '../tracker_icon.dart';
import '../upload/upload_section.dart';
import '../video_pack/video_pack_section.dart';
import 'field_validation.dart';
import 'file_size.dart';
import 'release.dart';
import 'release_editor_controller.dart';
import 'release_fields.dart';
import 'release_store.dart';
import 'release_type.dart';
import 'tracker.dart';

/// The key of the row that shows the path the user picked. It is not a field,
/// so it has no field name to key itself by.
const sourceRowKey = ValueKey('source');

class ReleaseEditor extends StatefulWidget {
  const ReleaseEditor({required this.release, required this.tabId, super.key});

  final Release release;

  /// The tab this editor belongs to; the dirty flag is reported to it.
  final String tabId;

  @override
  State<ReleaseEditor> createState() => _ReleaseEditorState();
}

class _ReleaseEditorState extends State<ReleaseEditor> {
  late final ReleaseEditorController _controller;

  /// The field list of the type this release is. It is what says which names
  /// exist; the values are the same `FieldValues` model for every type. Every
  /// type the app can open has one, so there is no type to be without a field
  /// list for.
  late final FieldList _fieldList = fieldListFor(widget.release.releaseType);

  /// One text controller per field the form shows, seeded from the field model.
  /// Keyed by the field name, because a field list is data and has no type to
  /// key by.
  final Map<String, TextEditingController> _textControllers = {};

  /// The text controller for the source row. It is not a field: the path the
  /// user picked is part of the release record, not one of its fields
  /// (`ai/release_structure.md` §2).
  late final TextEditingController _sourceController;

  /// The movie file is being read. Widget state: it only decides what the row
  /// shows while the probe is in flight.
  bool _probing = false;

  /// The poster is being written. Widget state, for the same reason.
  bool _posterBusy = false;

  /// Increments on every poster write. It is part of the key of the poster
  /// box's image, so a poster written over one already shown is re-resolved.
  /// The poster file keeps the same name (`_rp_poster.jpg`), so evicting the
  /// cache entry is not enough on its own — see the note on the image cache in
  /// `ai/doc.md`.
  int _posterGeneration = 0;

  /// The fields the last generation refused, as the rule sees them
  /// (`ai/description_template.md` §Validation). The Message section reports
  /// them: it is the widget that runs the check, and the rows are this
  /// widget's, so the problems reach it through a plain callback (rule 3).
  ///
  /// After a generation is refused the form shows the rule as it stands, so
  /// an error goes away when the field is filled; a change to a field is
  /// read through the same rule rather than remembered as what was reported
  /// once.
  ///
  /// Only a row the user can type into shows it: a row the app fills is not
  /// something the user can fix here, so it is said in the message the section
  /// shows instead.
  Map<String, FieldProblem> _refusedFields = {};

  /// The rule, read as the values are now. It is the same function the
  /// controller calls, so the row and the message cannot disagree.
  Map<String, FieldProblem> _fieldProblems() => {
    for (final problem in validateFields(_fieldList, _controller.fields))
      problem.field: problem,
  };

  void _fieldsRefused(List<FieldProblem> problems) {
    _refusedFields = {for (final problem in problems) problem.field: problem};

    setState(() {});
  }

  /// What the sections rebuild with, registered by them when they open. A change
  /// in one is something another one shows: an upload run changes the counts the
  /// Upload section shows and whether the Message section can generate, the source
  /// row changes what the Torrent section can run on, a field written through the
  /// write path is a value the Message section's message was built from, and the
  /// two files the Message section writes are what the Upload draft section sends.
  /// The sections cannot see each other, so the editor — the widget that places
  /// them all — is where they meet. A plain callback, not a listener (rule 3).
  final List<void Function()> _imageRebuilds = [];
  final List<void Function()> _sourceRebuilds = [];
  final List<void Function()> _fieldRebuilds = [];
  final List<void Function()> _messageRebuilds = [];

  void _registerImageRebuild(void Function() rebuild) =>
      _imageRebuilds.add(rebuild);

  void _registerSourceRebuild(void Function() rebuild) =>
      _sourceRebuilds.add(rebuild);

  void _registerFieldRebuild(void Function() rebuild) =>
      _fieldRebuilds.add(rebuild);

  void _registerMessageRebuild(void Function() rebuild) =>
      _messageRebuilds.add(rebuild);

  void _imagesChanged() {
    for (final rebuild in _imageRebuilds) {
      rebuild();
    }
  }

  void _sourceChanged() {
    for (final rebuild in _sourceRebuilds) {
      rebuild();
    }
  }

  /// A field, or the block shape, was written through the single write path. Only
  /// the Message section shows something that depends on the values, and it is not
  /// the widget that builds the rows, so the notice goes to it alone (rule 3).
  void _fieldsChanged() {
    for (final rebuild in _fieldRebuilds) {
      rebuild();
    }
  }

  /// The Message section wrote or cleared the two text files. Only the Upload
  /// draft section shows something that depends on them, and it is not the widget
  /// that writes them, so the notice goes to it alone (rule 3).
  void _messageChanged() {
    for (final rebuild in _messageRebuilds) {
      rebuild();
    }
  }

  /// Which fields are in which column is the widget's layout, not the field
  /// model. The switch is exhaustive over the release types, so a type added to
  /// `ReleaseType` has to be given a layout here; the compiler says so, which
  /// is what a runtime fallback used to do silently.
  List<List<FieldSpec>> _columns() {
    List<FieldSpec> rows(List<String> names) => [
      for (final name in names) _fieldList.field(name),
    ];

    return switch (_fieldList.releaseType) {
      ReleaseType.singleVideo => [
        rows(_singleVideoLeft),
        rows(_singleVideoRight),
      ],
      ReleaseType.photosetPack => [
        rows(_photosetPackLeft),
        rows(_photosetPackRight),
      ],
      ReleaseType.videoPack => [rows(_videoPackLeft), rows(_videoPackRight)],
      ReleaseType.singlePhotoset => [
        rows(_singlePhotosetLeft),
        rows(_singlePhotosetRight),
      ],
      // The catch-all type has no fields the user writes, so the left column is
      // the poster box and nothing else; the right column is what the scan
      // counted, as it is for every other type (`ai/image_folder_upload.md`
      // §4).
      ReleaseType.imageFolderUpload => [const [], rows(_imageFolderRight)],
    };
  }

  /// The title each column of the form has: what its rows are. A switch, like
  /// `fieldLabel`, so a type added to `ReleaseType` has to say what its columns
  /// are called. The image folder type has no column of fields, so its left
  /// column — the poster box and nothing else — has no title.
  List<String?> _columnTitles(
    AppLocalizations l10n,
  ) => switch (_fieldList.releaseType) {
    ReleaseType.singleVideo => [
      l10n.columnTitleReleaseInfo,
      l10n.columnTitleVideo,
    ],
    // A pack's second column is the folder the user picked and the three
    // counts the scan took from it, so it is named by the folder rather than
    // by what one value in it is, as the other types name theirs
    // (`ai/video_pack.md` §6).
    ReleaseType.videoPack => [
      l10n.columnTitleReleaseInfo,
      l10n.columnTitleSourceFolder,
    ],
    ReleaseType.photosetPack => [
      l10n.columnTitleReleaseInfo,
      l10n.columnTitlePhotosets,
    ],
    ReleaseType.singlePhotoset => [
      l10n.columnTitleReleaseInfo,
      l10n.columnTitlePhotosets,
    ],
    ReleaseType.imageFolderUpload => [null, l10n.columnTitleImages],
  };

  static const _singleVideoLeft = [
    'videoTitle',
    'cast',
    'subsiteAndSite',
    'siteNumber',
    'productionDate',
    'genreTags',
    'description',
    'additionalInfo',
  ];

  static const _singleVideoRight = [
    'videoQuality',
    'fileSize',
    'duration',
    'videoType',
    'videoFormat',
    'videoStream',
    'audioStream',
  ];

  static const _photosetPackLeft = ['siteOrJournal', 'period', 'genreTags'];

  static const _photosetPackRight = [
    'photosetCount',
    'totalPhotoCount',
    'minResolution',
    'maxResolution',
  ];

  // The names a video pack has are the ones the other two types already have,
  // so the left column reads like the other forms; only the four aggregates are
  // this type's (`ai/video_pack.md` §3), and the right column lists them in the
  // order the field list writes them, the total first.
  static const _videoPackLeft = [
    'subsiteAndSite',
    'cast',
    'period',
    'genreTags',
    'description',
    'additionalInfo',
  ];

  static const _videoPackRight = [
    'totalSize',
    'videoCount',
    'videoResolutions',
    'videoFormats',
  ];

  // The same shape as the other forms: the fields the user writes on the left,
  // the values the scan counted on the right (`ai/single_photoset.md` §3). The
  // names are the ones the other types already have, so the left column reads
  // like them.
  static const _singlePhotosetLeft = [
    'cast',
    'videoTitle',
    'siteOrJournal',
    'productionDate',
    'genreTags',
    'description',
  ];

  static const _singlePhotosetRight = [
    'totalPhotoCount',
    'minResolution',
    'maxResolution',
    'imageFormats',
  ];

  // The names are the ones the photoset types already have, so this is the same
  // right column; only the words differ, and those are `fieldLabel`'s
  // (`ai/image_folder_upload.md` §4). There is no left column: this type has no
  // field the user writes.
  static const _imageFolderRight = [
    'totalPhotoCount',
    'minResolution',
    'maxResolution',
    'imageFormats',
  ];

  @override
  void initState() {
    super.initState();
    _controller = ReleaseEditorController(
      release: widget.release,
      store: context.read<ReleaseStore>(),
      tabManager: context.read<TabManager>(),
      ffprobe: context.read<Ffprobe>(),
      ffmpeg: context.read<Ffmpeg>(),
      downloader: context.read<ImageDownloader>(),
      images: context.read<ImagesStore>(),
      tabId: widget.tabId,
    );

    // A text controller only for the fields the form shows. `sceneUrl` is a
    // field, but its row is the StashDB section's, and that widget owns its own
    // input, so it has no row here.
    final fieldList = _fieldList;

    for (final field in fieldList.formRows) {
      _textControllers[field.name] = TextEditingController(
        text: _controller.fields.value(field.name),
      );
    }

    _sourceController = TextEditingController(text: _controller.release.source);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // A byte-count field is the kind of field whose text is not the value the
    // model holds: it shows the bytes in a human-friendly form as well.
    // Localizations cannot be read in initState, so that text is put in here —
    // on the first build and whenever the app's language changes. A type with no
    // such field has nothing to derive, so it is not reached here.
    final l10n = AppLocalizations.of(context)!;

    for (final field in _fieldList.formRows) {
      if (!field.isByteCount) {
        continue;
      }

      final textController = _textControllers[field.name];

      if (textController == null) {
        continue;
      }

      final display = _displayValue(
        field,
        _controller.fields.value(field.name),
        l10n,
      );

      if (textController.text != display) {
        textController.text = display;
      }
    }
  }

  @override
  void dispose() {
    for (final textController in _textControllers.values) {
      textController.dispose();
    }

    _sourceController.dispose();
    super.dispose();
  }

  /// The single write path for the source row, the same rule as for a field:
  /// the model first, then the row showing it, and a value the row already
  /// shows is not written back for the same reason typing must not stop after
  /// one character.
  bool _writeSource(String value) {
    if (!_controller.setSource(value)) {
      return false;
    }

    if (_sourceController.text != value) {
      _sourceController.text = value;
    }

    // The row is the only place the source is written to, and the sections that
    // show what it is cannot see it, so the notice goes out from here.
    _sourceChanged();

    return true;
  }

  /// The single write path: the model first, then the field showing it. Returns
  /// whether the value changed.
  ///
  /// A value that came from the field itself is already shown there, so it is
  /// not written back: writing it would move the caret to the end and clear the
  /// IME composition, which stops typing after one character. Only writes that
  /// come from outside the field — the probe, the date picker, the file picker
  /// — update it.
  bool _writeField(FieldSpec field, String value) {
    if (!_controller.setField(field.name, value)) {
      return false;
    }

    // The notice goes out for every field the message is built from, including
    // one whose row is another widget's, because the Message section reads the
    // values and not the rows. A field no template reads — the two draft names —
    // is not something a render would change, so the notice does not go out for
    // it (`ai/uploading_draft.md` §4).
    if (field.readByTemplate) {
      _fieldsChanged();
    }

    final textController = _textControllers[field.name];

    // A field whose widget is not in this form — the scene link is the StashDB
    // section's input — has no row to update.
    if (textController == null) {
      return true;
    }

    final display = _displayValue(field, value, AppLocalizations.of(context)!);

    if (textController.text != display) {
      textController.text = display;
    }

    return true;
  }

  /// The single write path for the block shape, the same rule as for a field: the
  /// model first, then the row showing it. The row is the Message section's, so
  /// the notice is what updates it, and the same notice is what clears the box,
  /// because the shape is what the block inside the message is built with.
  bool _writeScreenshotLayout(ScreenshotLayout layout) {
    if (!_controller.setScreenshotLayout(layout)) {
      return false;
    }

    _fieldsChanged();

    return true;
  }

  /// The single write path for the signature flag, the same rule as for a field
  /// and for the block shape: the model first, then the row showing it. The row
  /// is the Message section's, so the notice is what updates it, and the same
  /// notice is what clears the box, because the flag is what a render would
  /// produce the signature with.
  bool _writeIncludeAppSignature(bool include) {
    if (!_controller.setIncludeAppSignature(include)) {
      return false;
    }

    _fieldsChanged();

    return true;
  }

  /// The text a field shows. For every field but a byte count that is the value
  /// itself; a size field shows the byte count in a human-friendly form as well,
  /// so its text is derived from the value rather than being the value. Which
  /// fields are sizes is the field list's, not a list of names this widget
  /// knows.
  String _displayValue(FieldSpec field, String value, AppLocalizations l10n) =>
      field.isByteCount ? formatFileSize(value, l10n) : value;

  /// The fields ffprobe fills (items 8, 9, 11, 12, 13, 16) through that same
  /// write path, so the tab becomes dirty and Ctrl+S saves them.
  void _applyMediaInfo(MediaInfo info) {
    void write(String name, String value) =>
        _writeField(_fieldList.field(name), value);

    write('fileSize', info.fileSize);
    write('duration', info.duration);
    write('videoType', info.videoType);
    write('videoFormat', info.videoFormat);
    write('videoStream', info.videoStream);
    write('audioStream', info.audioStream);
  }

  /// The values a section has to write — the Stash section's chosen values, the
  /// values the scan counted — through the single write path, so the tab
  /// becomes dirty and Ctrl+S saves them. The sections have no write path of
  /// their own.
  void _applyFieldValues(Map<String, String> values) {
    for (final entry in values.entries) {
      _writeField(_fieldList.field(entry.key), entry.value);
    }
  }

  /// One text box in the form. Every row is this widget; what differs is the
  /// label, the controller, and where a change is written to. A field writes to
  /// the field model; the source row writes to the release record, because the
  /// path the user picked is not a field (`ai/release_structure.md` §2).
  Widget _textField({
    required Key key,
    required String label,
    required TextEditingController controller,
    required void Function(String) onChanged,
    String? hint,
    String? errorText,
    bool multiline = false,
    bool grows = false,
    bool readOnly = false,
    void Function(String)? onSubmitted,
  }) {
    final theme = Theme.of(context);

    return TextFormField(
      key: key,
      controller: controller,
      readOnly: readOnly,
      minLines: multiline ? 4 : 1,
      // A one-line field that grows below when the text does not fit.
      maxLines: multiline || grows ? null : 1,
      decoration: readOnly
          // A field the app fills is not editable, so it does not look like an
          // input either: no border, a muted background, the value as plain
          // text. It is still a text box, so the value can be selected and
          // copied.
          ? InputDecoration(
              labelText: label,
              hintText: hint,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHigh,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            )
          : InputDecoration(
              labelText: label,
              hintText: hint,
              // The words for the problem this row has, when the last
              // The words for the problem this row has, when the last
              // generation refused the field. `InputDecoration` draws them
              // under the field and turns the border red, which is the
              // highlight. A row the app fills is never given one, because
              // the user cannot fix it here.
              errorText: errorText,
              border: const OutlineInputBorder(),
            ),
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
    );
  }

  Widget _field(
    FieldSpec field,
    AppLocalizations l10n, {
    String? hint,
    bool multiline = false,
    bool grows = false,
    void Function(String)? onSubmitted,
  }) {
    final problem = _refusedFields[field.name];

    // Only a row the user can type into shows the error. A row the app fills is
    // not something the user can fix here, so it is said in the message the
    // section shows instead.
    final errorText = problem == null || field.filledByApp
        ? null
        : fieldProblemText(problem, l10n, _fieldList.releaseType);

    return _textField(
      key: ValueKey(field.name),
      label: fieldLabel(field.name, l10n, _fieldList.releaseType),
      controller: _textControllers[field.name]!,
      onChanged: (value) {
        if (!_writeField(field, value)) {
          return;
        }

        // Nothing was refused, so no row shows an error and a keystroke cannot
        // change what is drawn.
        if (_refusedFields.isEmpty) {
          return;
        }

        // The row shows the rule as it stands, so a field that becomes
        // correct has to be redrawn, and one that becomes wrong as well.
        // Only when the answer for this field changes: a keystroke in a
        // field that was already fine needs no rebuild.
        final problems = _fieldProblems();

        if (problems.containsKey(field.name) !=
            _refusedFields.containsKey(field.name)) {
          _refusedFields = problems;
          setState(() {});
        }
      },
      // A field the app fills is not editable: the probe for a video, the scan
      // for a pack.
      readOnly: field.filledByApp,
      hint: hint,
      errorText: errorText,
      multiline: multiline,
      grows: grows,
      onSubmitted: onSubmitted,
    );
  }

  /// The label of the source row. The row is not a field, so it is not in
  /// `fieldLabel`; and the label cannot come from `sourceKind` alone, because
  /// "folder with the photosets" and "folder with the videos" are different
  /// things to pick. It is the label the release type has.
  String _sourceLabel(AppLocalizations l10n) =>
      switch (_fieldList.releaseType) {
        ReleaseType.singleVideo => l10n.movieFilePathLabel,
        ReleaseType.photosetPack => l10n.photosetPackFolderLabel,
        ReleaseType.videoPack => l10n.videoFolderLabel,
        ReleaseType.singlePhotoset => l10n.singlePhotosetFolderLabel,
        ReleaseType.imageFolderUpload => l10n.imageFolderFolderLabel,
      };

  /// The row for the path the user picked. For a video the picked file is the
  /// release, so this row is what creates the item it is. For a pack the picked
  /// folder contains the items, and the items are what the scan writes.
  Widget _sourceRow(AppLocalizations l10n) {
    final isDirectory = _fieldList.sourceKind == SourceKind.directory;

    return _rowWithButton(
      _textField(
        key: sourceRowKey,
        label: _sourceLabel(l10n),
        controller: _sourceController,
        onChanged: (value) => _writeSource(value),
        onSubmitted: isDirectory ? null : (_) => _probeMovieFile(l10n),
      ),
      tooltip: isDirectory ? l10n.chooseFolder : l10n.chooseFile,
      icon: isDirectory ? Icons.folder_outlined : Icons.file_open,
      onPressed: () => _pickSource(l10n),
      busy: _probing,
    );
  }

  /// The scene link field as the form shows it: the StashDB widget is the
  /// widget that field has, so its row is the row the form shows for it, and it
  /// starts with what the release stores. A pack is not one scene, so no other
  /// type has this row.
  Widget _stashRow(AppLocalizations l10n) {
    return StashSection(
      releaseType: _fieldList.releaseType,
      onApply: _applyFieldValues,
      onPoster: (url) => _applyPosterFromUrl(url, l10n),
      initialUrl: _controller.fields.value('sceneUrl'),
    );
  }

  /// One field as the form shows it: the ones with a button, the one that
  /// grows, and the plain text boxes. These are the shapes a row can have, so
  /// they are the widget's, not the field model's.
  Widget _fieldWidget(FieldSpec field, AppLocalizations l10n) {
    switch (field.name) {
      case 'productionDate':
        return _rowWithButton(
          _field(field, l10n),
          tooltip: l10n.chooseDate,
          icon: Icons.event,
          onPressed: () => _pickProductionDate(l10n),
        );
      case 'genreTags':
        return _field(field, l10n, grows: true);
      case 'duration':
        return _field(field, l10n, hint: l10n.durationHint);
      case 'description':
      case 'additionalInfo':
        return _field(field, l10n, multiline: true);
      default:
        return _field(field, l10n);
    }
  }

  Widget _rowWithButton(
    Widget field, {
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool busy = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: busy
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: tooltip,
                  onPressed: onPressed,
                  icon: Icon(icon),
                ),
        ),
      ],
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Drops the image the widget has cached for a file it is about to show
  /// again.
  ///
  /// The image cache is keyed by the file path, so a file the app rewrites is
  /// still shown as the image decoded from it the first time: a poster that
  /// replaces one already shown would not appear. The entry has to be dropped
  /// before the widget builds again.
  void _evictCachedImage(String? path) {
    if (path == null) return;

    PaintingBinding.instance.imageCache.evict(FileImage(File(path)));
  }

  Future<void> _save(AppLocalizations l10n) async {
    if (!await _controller.save()) {
      _showMessage(l10n.releaseSaveFailed);
    }
  }

  Future<void> _pickSource(AppLocalizations l10n) async {
    try {
      final path = _controller.release.source.trim();
      var initialDirectory = '';

      if (path.isNotEmpty) {
        // The picker opens where the source is: for a picked directory that is
        // the directory itself, for a picked file its parent.
        final directory = Directory(path);
        final parent = directory.existsSync()
            ? directory
            : Directory(p.dirname(path));

        if (await parent.exists()) {
          initialDirectory = parent.path;
        }
      }

      final isDirectory = _fieldList.sourceKind == SourceKind.directory;
      final start = initialDirectory.isEmpty ? null : initialDirectory;
      String? pickedPath;

      if (isDirectory) {
        pickedPath = await FilePicker.getDirectoryPath(
          dialogTitle: l10n.chooseFolder,
          initialDirectory: start,
        );
      } else {
        pickedPath = (await FilePicker.pickFile(
          dialogTitle: l10n.chooseFile,
          initialDirectory: start,
        ))?.path;
      }

      if (!mounted || pickedPath == null || pickedPath.isEmpty) return;

      if (_writeSource(pickedPath) && !isDirectory) {
        await _probeMovieFile(l10n);
      }
    } catch (_) {
      _showMessage(l10n.filePickerFailed);
    }
  }

  Future<void> _probeMovieFile(AppLocalizations l10n) async {
    setState(() => _probing = true);

    final result = await _controller.probeMovieFile();

    if (!mounted) return;

    switch (result) {
      case MediaProbeSuccess(info: final info):
        _applyMediaInfo(info);
        await _generateThumbnail(l10n, info.durationSeconds);
      case MediaProbeFailure(kind: final kind):
        _showMessage(switch (kind) {
          MediaProbeFailureKind.fileNotFound => l10n.movieFileNotFound,
          MediaProbeFailureKind.toolNotAvailable => l10n.probeToolNotAvailable,
          MediaProbeFailureKind.probeFailed => l10n.probeFailed,
        });
    }

    if (!mounted) return;
    setState(() => _probing = false);
  }

  /// The frame ffmpeg writes for the video. On success the box shows the file,
  /// so the widget only needs to build again; a failure is mapped to localized
  /// text.
  Future<void> _generateThumbnail(
    AppLocalizations l10n,
    double? durationSeconds,
  ) async {
    switch (await _controller.generateThumbnail(durationSeconds)) {
      case ThumbnailSuccess():
        if (!mounted) return;
        _evictCachedImage(_controller.thumbnailPath());
        setState(() {});
      case ThumbnailFailure(kind: final kind):
        _showMessage(switch (kind) {
          ThumbnailFailureKind.fileNotFound => l10n.movieFileNotFound,
          ThumbnailFailureKind.toolNotAvailable => l10n.ffmpegNotAvailable,
          ThumbnailFailureKind.failed => l10n.thumbnailFailed,
        });
    }
  }

  /// The poster the user chose. The picker is filtered to the formats a poster
  /// may be; the controller writes it into the release directory. On success
  /// the box shows the thumbnail it wrote, so the widget only needs to build
  /// again; a failure is mapped to localized text.
  Future<void> _choosePoster(AppLocalizations l10n) async {
    PlatformFile? picked;

    try {
      picked = await FilePicker.pickFile(
        dialogTitle: l10n.chooseImage,
        type: FileType.custom,
        allowedExtensions: ReleaseEditorController.posterExtensions.toList(),
      );
    } catch (_) {
      _showMessage(l10n.filePickerFailed);
      return;
    }

    if (!mounted || picked?.path == null) return;

    setState(() => _posterBusy = true);

    _finishPoster(await _controller.setPoster(picked!.path!), l10n);
  }

  /// What happens after a poster is written: the box shows the file the tool
  /// wrote, so the image cached for that path is dropped first and the
  /// generation the image is keyed with changes, so the widget resolves against
  /// the now-empty cache. The widget builds again. A failure is mapped to
  /// localized text.
  ///
  /// A poster that was written is a record in `images.json`, so it is something
  /// the sections that read that file show: the Upload section's placeholder
  /// waits for the poster, and the counters count it. Only a write that
  /// succeeded is such a change, because a failed one leaves the manifest as it
  /// was.
  void _finishPoster(PosterResult result, AppLocalizations l10n) {
    if (!mounted) return;

    switch (result) {
      case PosterSuccess():
        _evictCachedImage(_controller.posterPath());
        _posterGeneration += 1;
        _imagesChanged();
      case PosterFailure(kind: final kind):
        _showMessage(_posterMessage(l10n, kind));
    }

    setState(() => _posterBusy = false);
  }

  /// What a poster failure says. One mapping for the picked file and the pasted
  /// link, because after the file is there both go through the same path.
  String _posterMessage(AppLocalizations l10n, PosterFailureKind kind) =>
      switch (kind) {
        PosterFailureKind.fileNotFound => l10n.posterFileNotFound,
        PosterFailureKind.wrongFormat => l10n.posterWrongFormat,
        PosterFailureKind.invalidUrl => l10n.posterUrlInvalid,
        PosterFailureKind.downloadFailed => l10n.posterDownloadFailed,
        PosterFailureKind.toolNotAvailable => l10n.ffmpegNotAvailable,
        PosterFailureKind.failed => l10n.posterWriteFailed,
        PosterFailureKind.manifestFailed => l10n.imagesManifestFailed,
      };

  /// A poster URL, through the path a pasted link uses: the same format check
  /// and the same write. The StashDB section applies its poster here, and the
  /// paste button reads the clipboard and calls the same method.
  Future<void> _applyPosterFromUrl(String url, AppLocalizations l10n) async {
    setState(() => _posterBusy = true);

    _finishPoster(await _controller.setPosterFromUrl(url), l10n);
  }

  /// The link in the clipboard. The image it points at is processed exactly
  /// like a file the user picked, so the same format check and the same write
  /// apply. Flutter's clipboard API reads text, which is what a link is.
  Future<void> _pastePosterFromUrl(AppLocalizations l10n) async {
    final url = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();

    if (url == null || url.isEmpty) {
      _showMessage(l10n.nothingToPaste);
      return;
    }

    await _applyPosterFromUrl(url, l10n);
  }

  /// Removes both poster files. The box shows nothing again once they are gone.
  /// The record goes with them, so the sections that read it are told, the same
  /// as for a write: without the notice the Upload section keeps showing the
  /// list for an image the release no longer has.
  Future<void> _removePoster(AppLocalizations l10n) async {
    if (!await _controller.removePoster()) {
      _showMessage(l10n.posterRemoveFailed);
      return;
    }

    if (!mounted) return;

    _imagesChanged();
    setState(() {});
  }

  DateTime? _parseDate(String value) {
    try {
      return DateTime.parse(value.trim());
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickProductionDate(AppLocalizations l10n) async {
    final firstDate = DateTime(1900);
    final lastDate = DateTime.now();

    // A date typed into the field can be outside the picker's range, and
    // showDatePicker asserts that initialDate is inside it.
    var initialDate =
        _parseDate(_controller.fields.value('productionDate')) ?? lastDate;

    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (!mounted || picked == null) return;
    _writeField(_fieldList.field('productionDate'), _formatDate(picked));
  }

  static String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyS ||
        !HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }

    _save(AppLocalizations.of(context)!);
    return KeyEventResult.handled;
  }

  /// What a box shows when there is nothing to show. The message is the
  /// caller's, because an empty box says what that box is for, and the two
  /// video cases read differently: no video is picked, versus a video that is
  /// there with no frame.
  Widget _noImageContent(IconData icon, String message, {String? hint}) {
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 32, color: theme.colorScheme.outline),
        const SizedBox(height: 8),
        Text(message, style: theme.textTheme.bodySmall),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// The poster or thumbnail box: the label with its buttons, then the space
  /// the image takes.
  ///
  /// The box is 16:9, the shape of the frames it shows, so a video frame fills
  /// it without being cropped. Its height comes from the width the column gives
  /// it.
  ///
  /// The label row is the same height with or without buttons, so the two boxes
  /// in the two columns start at the same height: a row sizes itself to its
  /// tallest child, and an icon button is taller than a label. The height of an
  /// image box's label row, with or without buttons.
  static const _labelRowHeight = 48.0;

  Widget _imageBox(
    String label,
    IconData icon,
    String message, {
    Widget? image,
    Widget? actions,
    VoidCallback? onTap,
    String? hint,
  }) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(8);

    final box = Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: radius,
      ),
      child: image == null
          ? _noImageContent(icon, message, hint: hint)
          : ClipRRect(borderRadius: radius, child: image),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _labelRowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Text(label, style: theme.textTheme.labelMedium)),
              ?actions,
            ],
          ),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 16 / 9,
          // Clicking the box does the same as the button in the label row,
          // because that is the place the user is looking at. An InkWell with
          // an onTap is focusable, which is where Ctrl+V will paste from the
          // clipboard.
          child: onTap == null ? box : InkWell(onTap: onTap, child: box),
        ),
      ],
    );
  }

  /// The poster box: the label with its buttons, then the poster itself.
  /// The remove button is there only when a poster is.
  Widget _posterBox(AppLocalizations l10n) {
    final posterPath = _controller.posterOnDisk();

    final image = posterPath == null
        ? null
        : Image.file(
            File(posterPath),
            // The key carries the generation, so a poster written over one
            // already shown is re-resolved — the file keeps the same name.
            key: ValueKey('poster-$_posterGeneration-$posterPath'),
            width: double.infinity,
            // A poster is usually portrait, so it is fitted inside the box
            // rather than cropped to it.
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _noImageContent(
              Icons.image_outlined,
              l10n.noImageSelected,
              hint: l10n.posterHint,
            ),
          );

    return _imageBox(
      l10n.posterImageLabel,
      Icons.image_outlined,
      l10n.noImageSelected,
      image: image,
      hint: l10n.posterHint,
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_posterBusy)
            SizedBox(
              width: 24,
              height: 24,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            IconButton(
              tooltip: l10n.chooseImage,
              onPressed: () => _choosePoster(l10n),
              icon: const Icon(Icons.image_outlined),
            ),
            IconButton(
              tooltip: l10n.pasteFromUrl,
              onPressed: () => _pastePosterFromUrl(l10n),
              icon: const Icon(Icons.link_outlined),
            ),
          ],
          if (posterPath != null)
            IconButton(
              tooltip: l10n.removeImage,
              onPressed: () => _removePoster(l10n),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      onTap: _posterBusy ? null : () => _choosePoster(l10n),
    );
  }

  /// A badge next to the title: the tracker with its icon, and the release
  /// type.
  Widget _badge({Widget? icon, required String text}) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon, const SizedBox(width: 6)],
          Text(text, style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }

  /// The gap between the columns and between the sections.
  static const _columnGap = 24.0;

  /// The narrowest a column may be. The number of columns is however many of
  /// this width fit in the space the page has. The columns after the two the
  /// form has are the sections' columns, and only the types
  /// `_sectionsAreColumns` says have them; for the others the section is the
  /// whole width below the form.
  static const _minColumnWidth = 430.0;

  /// Whether the type's section can be one of the columns after the form. A
  /// switch, like the other per-type rules, so a type added to `ReleaseType`
  /// has to say. The two video types can, because the page is the same shape
  /// for them. The masonry types cannot: a masonry is read at the whole width,
  /// so their sections stay below the form (`ai/photoset_pack.md` §6,
  /// `ai/image_folder_upload.md` §5).
  bool _sectionsAreColumns(ReleaseType type) => switch (type) {
    ReleaseType.singleVideo => true,
    ReleaseType.videoPack => true,
    ReleaseType.photosetPack || ReleaseType.singlePhotoset => false,
    ReleaseType.imageFolderUpload => false,
  };

  /// How many columns of at least the minimum width fit in the space the page
  /// has.
  int _columnCount(double width, int maxColumns) {
    var count = 1;

    while (count < maxColumns &&
        width >= (count + 1) * _minColumnWidth + count * _columnGap) {
      count += 1;
    }

    return count;
  }

  /// One column of the form: its title, then the image box at the top when this
  /// type has one, then its rows. The title is drawn the same way the sections
  /// draw theirs, so a column and a section read the same.
  ///
  /// The gap after the title is smaller than the one a section has: the first
  /// thing in a form column is an image box, and its label row has its own
  /// space above the label, so the same gap would read as a bigger one here
  /// than in a section whose first content is plain text.
  Widget _column(List<Widget> rows, {String? title, Widget? imageBox}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(
            title,
            key: const ValueKey('columnTitle'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
        ],
        ?imageBox,
        for (final row in rows) ...[const SizedBox(height: 16), row],
      ],
    );
  }

  /// The sections stacked with the gap between them, as the page places them.
  /// No gap before the first one, because as a column it starts at the top like
  /// the form columns do.
  Widget _stack(List<Widget> sections) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: _columnGap),
          sections[i],
        ],
      ],
    );
  }

  /// The section the release type has. The Upload section is not part of it,
  /// because the two are placed separately: the Upload section is the only
  /// place it and the sections that write images can meet, so the editor passes
  /// it the callback that tells it when a run ends (`ai/upload_images.md`).
  Widget _typeSection(AppLocalizations l10n) {
    final release = _controller.release;

    return switch (_fieldList.releaseType) {
      ReleaseType.singleVideo => ScreenshotsSection(
        release: release,
        onImagesChanged: _imagesChanged,
      ),
      ReleaseType.photosetPack || ReleaseType.singlePhotoset => PhotosetSection(
        release: release,
        tabId: widget.tabId,
        onApplyValues: _applyFieldValues,
      ),
      ReleaseType.videoPack => VideoPackSection(
        release: release,
        tabId: widget.tabId,
        onApplyValues: _applyFieldValues,
        onImagesChanged: _imagesChanged,
      ),
      ReleaseType.imageFolderUpload => ImageFolderSection(
        release: release,
        tabId: widget.tabId,
        onApplyValues: _applyFieldValues,
      ),
    };
  }

  /// The video thumbnail box: the frame ffmpeg wrote for the item. Only a file
  /// that is on disk is shown as an image; a failed load is remembered for the
  /// same path, so building an image for a missing file would stay empty after
  /// the tool writes it.
  ///
  /// An empty box says what it is missing, because the two cases are different
  /// things: no video is picked, versus a video that is there with no frame.
  /// Clicking it does the same as the pick button on the source row, because
  /// that is where the user is looking; the row's spinner is already the busy
  /// display, so the box does not show a second one.
  Widget _thumbnailBox(AppLocalizations l10n) {
    final hasVideo = _controller.release.source.trim().isNotEmpty;
    final thumbnailPath = _controller.thumbnailOnDisk();

    final message = hasVideo ? l10n.noImageSelected : l10n.noVideoSelected;

    final image = thumbnailPath == null
        ? null
        : Image.file(
            File(thumbnailPath),
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                _noImageContent(Icons.smart_display_outlined, message),
          );

    return _imageBox(
      l10n.videoThumbnailLabel,
      Icons.smart_display_outlined,
      message,
      image: image,
      // The hint is only for the box that has nothing in it, and only for the
      // case where clicking it is what fills it.
      hint: hasVideo ? null : l10n.videoHint,
      onTap: _probing ? null : () => _pickSource(l10n),
    );
  }

  /// Whether this release has the Upload draft section. The field list is what
  /// says which types have the field — the image folder type has no title to send
  /// — and the tracker is what says whether the release is on the site the feature
  /// belongs to (`ai/uploading_draft.md` §4).
  bool _hasDraftSection(Release release) =>
      release.tracker == Tracker.pornolab &&
      fieldListFor(release.releaseType).hasField('parentForum');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final release = _controller.release;
    final fieldList = _fieldList;

    // The Stash section and the video thumbnail belong to a release whose
    // source is one file, so neither is part of a pack form: a pack is not one
    // scene and has no single video to take a frame from. The poster belongs to
    // the release rather than to an item, so every type has it
    // (`ai/release_structure.md` §4, `ai/video_pack.md` §6).
    final isSingleVideo = fieldList.releaseType == ReleaseType.singleVideo;
    final sectionColumns = _sectionsAreColumns(fieldList.releaseType);
    final hasDraftSection = _hasDraftSection(release);
    final columns = _columns();

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // A type whose section can be a column has as many columns as fit:
            // the two the form has, its section, and the Upload section with
            // the Message section. The other types stop at two, because their
            // section is a masonry that cannot be read at one column width.
            final count = _columnCount(width, sectionColumns ? 4 : 2);
            final columnWidth = (width - _columnGap * (count - 1)) / count;

            final titles = _columnTitles(l10n);

            final typeSection = _typeSection(l10n);
            final upload = UploadSection(
              release: release,
              subscribeImagesChanged: _registerImageRebuild,
              onImagesChanged: _imagesChanged,
            );
            final message = MessageSection(
              release: release,
              subscribeImagesChanged: _registerImageRebuild,
              subscribeFieldsChanged: _registerFieldRebuild,
              onFieldsRefused: _fieldsRefused,
              onScreenshotLayoutChanged: _writeScreenshotLayout,
              onAppSignatureChanged: _writeIncludeAppSignature,
              onMessageChanged: _messageChanged,
            );
            // The Upload draft section is drawn for the types its field list has
            // the field for, and only for the site it is the site's feature
            // (`ai/uploading_draft.md` §4).
            final draft = hasDraftSection
                ? DraftSection(
                    release: release,
                    onApply: _applyFieldValues,
                    subscribeMessageChanged: _registerMessageRebuild,
                  )
                : null;
            final torrent = TorrentSection(
              release: release,
              subscribeSourceChanged: _registerSourceRebuild,
            );

            final left = _column(
              [
                // The scene link row is the first one, because it is what the
                // form is filled from, and the poster box is the top of this
                // column.
                if (isSingleVideo) _stashRow(l10n),
                for (final field in columns[0]) _fieldWidget(field, l10n),
              ],
              title: titles[0],
              imageBox: _posterBox(l10n),
            );

            // The second column, with the Torrent section at its end. It is
            // part of this column rather than one of the columns after the form
            // (`ai/torrents.md`), so the gap before it is the one between
            // sections rather than the one between the rows of a column.
            final right = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _column(
                  [
                    // The path the user picked is the first row of the right
                    // column, where the path field has always been.
                    _sourceRow(l10n),
                    for (final field in columns[1]) _fieldWidget(field, l10n),
                  ],
                  title: titles[1],
                  imageBox: isSingleVideo ? _thumbnailBox(l10n) : null,
                ),
                const SizedBox(height: _columnGap),
                torrent,
              ],
            );

            // One column when there is room for one, two when there is room for
            // two.
            final form = count == 1
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      left,
                      SizedBox(height: _columnGap),
                      right,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: columnWidth, child: left),
                      SizedBox(width: _columnGap),
                      SizedBox(width: columnWidth, child: right),
                    ],
                  );

            // The sections stacked at one column width, which is what lets them
            // be a column of the page.
            Widget sectionColumn(List<Widget> sections) =>
                SizedBox(width: columnWidth, child: _stack(sections));

            // The sections are the columns after the form when there is room
            // for them; otherwise they are below the form, left-aligned, at the
            // same width.
            final Widget grid;
            if (sectionColumns && count >= 3) {
              grid = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  form,
                  SizedBox(width: _columnGap),
                  // Without a fourth column the Upload section is below the
                  // type's section in the same column.
                  sectionColumn(
                    count == 4 ? [typeSection] : [typeSection, upload],
                  ),
                  if (count == 4) ...[
                    SizedBox(width: _columnGap),
                    // The Upload draft section is the part of the Message section's
                    // column below it, because it is the section that sends what
                    // that one shows (`ai/uploading_draft.md` §5).
                    sectionColumn([upload, message, ?draft]),
                  ],
                ],
              );
            } else {
              // A fixed width is only kept when the surrounding column does not
              // stretch it, so the sections that can be a column sit in a row
              // that holds their width.
              final below = sectionColumns
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        sectionColumn([typeSection, upload]),
                        const Spacer(),
                      ],
                    )
                  : _stack([typeSection, upload]);

              grid = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  form,
                  SizedBox(height: _columnGap),
                  below,
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    // The badges follow the name, because they say what the
                    // name is for. `Flexible` rather than `Expanded`: the text
                    // takes only the width its name needs, so the badges come
                    // after it, and a name long enough to fill the row still
                    // cannot push them off it.
                    Flexible(
                      child: Text(
                        release.name,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _badge(
                      icon: TrackerIcon(tracker: release.tracker, size: 16),
                      text: release.tracker.displayName,
                    ),
                    const SizedBox(width: 8),
                    _badge(text: releaseTypeLabel(release.releaseType, l10n)),
                  ],
                ),
                // The heading is the title of the page rather than of a column,
                // so it keeps the gap a section title has before its content.
                const SizedBox(height: 12),
                grid,
                // The Message section, below the form and the sections, at the
                // whole width, unless it is the fourth column
                // (`ai/description_template.md`). The Upload draft section follows
                // it in whichever of the two places that is
                // (`ai/uploading_draft.md` §5).
                if (!(sectionColumns && count == 4)) ...[
                  const SizedBox(height: 24),
                  message,
                  if (draft != null) ...[const SizedBox(height: 24), draft],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
