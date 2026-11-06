import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../service/network/image_downloader.dart';
import '../../service/network/stash_client.dart';
import '../../service/stashdb/domain_map.dart';
import '../image_tile.dart';
import '../release/release_fields.dart';
import '../release/release_type.dart';
import '../section_title.dart';
import '../settings/settings.dart';
import '../settings/settings_controller.dart';
import 'stash_controller.dart';

/// The StashDB row: the scene link field, which the form places at the top of
/// its left column, under the poster box (`ai/release_editor.md`). The widget
/// owns the input and the row; the controller owns the request and the mapping
/// to fields. It resolves its dependencies from the provider scope and builds
/// its own per-widget controller, as the other sections do.
///
/// The row does not write fields itself: it hands the chosen values to the
/// editor's single write path through `onApply`, so the tab becomes dirty and
/// Ctrl+S saves them. The poster is not a field, so it goes through `onPoster`,
/// which the editor wires to the same path a pasted poster link uses.
///
/// What a fetch gives is not shown in the form: it is shown in a popup, where
/// every value has a checkbox, checked when there is something to apply, and
/// only the checked ones are written. The popup owns the selection while it is
/// open, so the row keeps no state for a scene it is not showing, and closing
/// the popup without applying discards what it offered. The poster row shows
/// the image below its link, from the file the controller fetches it into.
///
/// The row owns the focus of its input and takes it back when the popup closes,
/// because the popup is a route and its focus scope is outside the row's, and
/// what the framework gives focus back to is whatever had it before the popup,
/// not the row's input. The save key reaches the editor from wherever the focus
/// is, so this is not what the key depends on.
class StashSection extends StatefulWidget {
  const StashSection({
    required this.releaseType,
    required this.onApply,
    required this.onPoster,
    required this.initialUrl,
    super.key,
  });

  /// The type the labels are resolved for, because `fieldLabel` needs it. This
  /// row is part of the Single video form only, so the type it is given is that
  /// one.
  final ReleaseType releaseType;

  /// Writes the chosen values through the editor's single write path.
  final void Function(Map<String, String> values) onApply;

  /// Writes the chosen poster through the editor's poster path: the same format
  /// check and the same write as a link the user pasted.
  final void Function(String url) onPoster;

  /// The scene link `release.json` holds for this item, which is what the input
  /// starts with: the input is the widget that field has, so a reopened release
  /// shows the link it was built from.
  final String initialUrl;

  @override
  State<StashSection> createState() => _StashSectionState();
}

class _StashSectionState extends State<StashSection> {
  late final StashController _controller;

  /// The input is the widget the scene link field has, so it starts with what
  /// the release stores for it.
  late final TextEditingController _input;

  /// The focus of the row's own input, which the row owns as the settings page
  /// owns the focus of its fields. It is what the popup gives focus back to
  /// when it closes, because the popup is a route and its focus scope is
  /// outside the row's.
  late final FocusNode _inputFocus;

  bool _busy = false;

  @override
  void initState() {
    super.initState();

    _controller = StashController(
      client: context.read<StashClient>(),
      downloader: context.read<ImageDownloader>(),
      domainMap: context.read<DomainMap>(),
    );
    _input = TextEditingController(text: widget.initialUrl);
    _inputFocus = FocusNode();
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _fetch(AppLocalizations l10n) async {
    // The key is read here, from the settings, so the controller builds no
    // dependency of its own (rule 4).
    final apiKey =
        context
            .read<SettingsController>()
            .secretValues[SettingsField.stashdb.name] ??
        '';

    setState(() => _busy = true);

    final result = await _controller.fetch(input: _input.text, apiKey: apiKey);

    if (!mounted) return;

    // The request has answered, so the row stops showing it as busy before the
    // popup opens.
    setState(() => _busy = false);

    switch (result) {
      case StashSceneSuccess(scene: final scene):
        await _showValues(scene);
      case StashFailure(kind: final kind):
        _showMessage(switch (kind) {
          StashFailureKind.invalidInput => l10n.stashInputInvalid,
          StashFailureKind.noApiKey => l10n.stashNoApiKey,
          StashFailureKind.requestFailed => l10n.stashRequestFailed,
          StashFailureKind.badResponse => l10n.stashBadResponse,
          StashFailureKind.graphqlError => l10n.stashGraphqlError,
          StashFailureKind.notFound => l10n.stashSceneNotFound,
        });
    }
  }

  /// The popup a successful fetch shows. The scene link is not one of the
  /// values the popup offers: it is what the user asked for by fetching the
  /// scene, so it is written on its own, and the input then shows what was
  /// stored — the link built from the id, not the text that was pasted.
  Future<void> _showValues(StashScene scene) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => _StashValuesDialog(
        controller: _controller,
        scene: scene,
        releaseType: widget.releaseType,
        onApply: (chosen, posterSelected) {
          final url = _controller.sceneUrl(scene);
          final poster = _controller.posterUrl(scene);

          widget.onApply({...chosen, 'sceneUrl': url});

          if (_input.text != url) {
            _input.text = url;
          }

          if (posterSelected && poster.isNotEmpty) widget.onPoster(poster);
        },
      ),
    );

    if (!mounted) return;

    // The popup took focus because it is a route, and what the framework gives
    // focus back to is whatever had it before the popup, so the row asks for
    // its own input here.
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // The same shape as the form rows that have a button, because this is one
    // of them.
    return Row(
      key: const ValueKey('stashSection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            key: const ValueKey('stashSceneInput'),
            controller: _input,
            focusNode: _inputFocus,
            decoration: InputDecoration(
              // The scene link is the field this row is, so its label is the
              // input's label.
              labelText: fieldLabel('sceneUrl', l10n, widget.releaseType),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  key: const ValueKey('stashFetchButton'),
                  tooltip: l10n.stashFetchButton,
                  onPressed: _busy || _input.text.trim().isEmpty
                      ? null
                      : () => _fetch(l10n),
                  icon: const Icon(Icons.download),
                ),
        ),
      ],
    );
  }
}

/// The popup a fetch shows: the values with a checkbox each, checked when there
/// is something to apply, and the Apply button. It owns the selection while it
/// is open; the row owns the input and the request. A scene with no values
/// still has its link, so the button is enabled for any scene the popup is
/// showing. Cancel closes it without applying, which is the same as closing it
/// by other means: the selection is the popup's, so it is discarded with it.
///
/// The poster row shows the image as well as its link, the image below the
/// link. The app shows no image it has not read from a file, so the popup asks
/// the controller to fetch the poster into a temporary file and shows that; a
/// poster that cannot be fetched shows its link only. The file is removed when
/// the popup closes.
///
/// Below the poster the popup has its "Import notes" subsection: the values the
/// import changed rather than copied, each one the message that says what was
/// done to it followed by the value as the scene reported it, with the part the
/// app cut struck through. A value it copied as it came is not listed, so what
/// is there is only what was done to a value. A domain read from a URL that is
/// not in the Primary sources category is such a value, because the rule would
/// have given a different one: the note is the URL it was read from, and there
/// is one for each of the two studios that had to be read that way. The
/// subsection titles itself with `SectionTitle`, the row every section uses.
class _StashValuesDialog extends StatefulWidget {
  const _StashValuesDialog({
    required this.controller,
    required this.scene,
    required this.releaseType,
    required this.onApply,
  });

  final StashController controller;
  final StashScene scene;
  final ReleaseType releaseType;

  /// What is checked when Apply is pressed: the field values, and whether the
  /// poster is among them. The scene link is not part of the selection, so it
  /// is not here; the row adds it.
  final void Function(Map<String, String> values, bool posterSelected) onApply;

  @override
  State<_StashValuesDialog> createState() => _StashValuesDialogState();
}

class _StashValuesDialogState extends State<_StashValuesDialog> {
  /// The field values, and the fields among them that are checked. They are not
  /// there on the first frame: the domain mapping is a bundled asset, so the
  /// values are read in `_loadValues()`, which `initState` starts, and the
  /// popup shows them when the read completes.
  Map<String, String> _values = {};
  Set<String> _selected = {};

  late final String _poster;

  /// The values the import changed rather than copied, which the popup lists
  /// below the poster.
  late final List<ImportNote> _notes;

  /// The poster is not a field, so it is not in the set above; it is the one
  /// other row the popup can offer.
  bool _posterSelected = false;

  /// The file the poster was fetched into, or null while it is not there.
  String? _posterPath;

  /// Increments on every fetch. It is part of the key of the poster image, so a
  /// scene fetched again resolves against the file it just wrote rather than
  /// the one the image cache still holds (`AGENTS.md` rule 5).
  int _generation = 0;

  @override
  void initState() {
    super.initState();

    _notes = widget.controller.changedValues(widget.scene);
    _poster = widget.controller.posterUrl(widget.scene);
    _posterSelected = _poster.isNotEmpty;

    _loadValues();

    if (_poster.isNotEmpty) _fetchPoster();
  }

  Future<void> _loadValues() async {
    final values = await widget.controller.fieldValues(widget.scene);

    if (!mounted) return;

    setState(() {
      _values = values;
      _selected = values.keys.toSet();
    });
  }

  @override
  void dispose() {
    // Only a file the download actually wrote is removed.
    if (_posterPath != null) widget.controller.removePreview(widget.scene);

    super.dispose();
  }

  Future<void> _fetchPoster() async {
    final result = await widget.controller.downloadPoster(widget.scene);

    if (!mounted) return;

    switch (result) {
      case DownloadSuccess(path: final path):
        // Evicting alone is not enough, because an already-mounted Image keeps
        // the stream it resolved the first time; the key changes with it.
        evictCachedImages([path]);

        setState(() {
          _posterPath = path;
          _generation++;
        });
      case DownloadFailure():
      // Nothing to show, so the row keeps the link it already shows.
    }
  }

  /// One value: its checkbox, what it is for, and the text StashDB gave for it.
  /// The poster row is the one that also shows an image, below the link,
  /// because the link is what the row is and the image is what it points to.
  Widget _valueRow({
    required String rowKey,
    required String label,
    required String value,
    required bool checked,
    required void Function(bool) onToggle,
    required ThemeData theme,
    Widget? image,
  }) {
    return Row(
      key: ValueKey(rowKey),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(value: checked, onChanged: (state) => onToggle(state == true)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodySmall),
              if (image != null) ...[const SizedBox(height: 8), image],
            ],
          ),
        ),
      ],
    );
  }

  /// The poster, fitted inside the box rather than cropped to it, because a
  /// poster is usually portrait. The box is the width the row has and 240 px
  /// tall, so a landscape poster fills it; a portrait one is kept at the left,
  /// where the text above it is, rather than centred in the space. The height
  /// is fixed because nothing is known about the image before it is decoded.
  Widget _posterImage() => SizedBox(
    width: double.infinity,
    height: 240,
    child: imageFromFile(
      _posterPath!,
      _generation,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
    ),
  );

  /// A value the import changed. It has no checkbox, because it is not
  /// something to apply: the row above is the value, and this is what was done
  /// to it. The kind is what was done, which is the message the widget picks
  /// (rule 13); the value follows the message with the parts the app cut struck
  /// through, so the change is in the text itself rather than described beside
  /// it. The index is part of the key because the same field can have more than
  /// one note: the subsite and the site are two studios, and each one that had
  /// to be read from another URL has its own.
  Widget _noteRow(
    ImportNote note,
    int index,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final explanation = switch (note.kind) {
      ImportNoteKind.siteNumberStrippedFromTitle =>
        l10n.stashNoteSiteNumberStripped(
          fieldLabel(note.field, l10n, widget.releaseType),
        ),
      ImportNoteKind.domainFromOtherUrl => l10n.stashNoteDomainFromOtherUrl(
        fieldLabel(note.field, l10n, widget.releaseType),
      ),
    };

    return Text.rich(
      TextSpan(
        style: theme.textTheme.bodySmall,
        children: [
          TextSpan(text: '$explanation '),
          for (final part in note.parts)
            TextSpan(
              text: part.text,
              style: part.cut
                  ? theme.textTheme.bodySmall!.copyWith(
                      decoration: TextDecoration.lineThrough,
                    )
                  : null,
            ),
        ],
      ),
      key: ValueKey('stash-note-${note.field}-$index'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // The popup is capped at 1000 px: a dialog given no constraints of its own
    // is limited only by the screen, and the values it lists are text that can
    // be as long as a URL.
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 1000),
      title: Text(l10n.stashImportTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in _values.entries) ...[
              _valueRow(
                rowKey: 'stash-row-${entry.key}',
                label: fieldLabel(entry.key, l10n, widget.releaseType),
                value: entry.value,
                checked: _selected.contains(entry.key),
                onToggle: (checked) => setState(() {
                  if (checked) {
                    _selected.add(entry.key);
                  } else {
                    _selected.remove(entry.key);
                  }
                }),
                theme: theme,
              ),
              const SizedBox(height: 4),
            ],
            if (_poster.isNotEmpty) ...[
              _valueRow(
                rowKey: 'stash-row-poster',
                label: l10n.posterImageLabel,
                value: _poster,
                checked: _posterSelected,
                onToggle: (checked) =>
                    setState(() => _posterSelected = checked),
                theme: theme,
                image: _posterPath == null ? null : _posterImage(),
              ),
            ],
            if (_notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              SectionTitle(
                key: const ValueKey('stashNotesTitle'),
                title: l10n.stashImportNotesTitle,
              ),
              const SizedBox(height: 4),
              for (final (index, note) in _notes.indexed) ...[
                _noteRow(note, index, l10n, theme),
                const SizedBox(height: 4),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('stashCancelButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('stashApplyButton'),
          onPressed: () {
            final chosen = {
              for (final entry in _values.entries)
                if (_selected.contains(entry.key)) entry.key: entry.value,
            };

            widget.onApply(chosen, _posterSelected);
            Navigator.of(context).pop();
          },
          child: Text(l10n.stashApplyButton),
        ),
      ],
    );
  }
}
