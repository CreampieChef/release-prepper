import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../service/template/template_renderer.dart';
import '../../service/template/template_store.dart';
import '../release/field_validation.dart';
import '../release/release.dart';
import '../release/release_store.dart';
import '../release/release_type.dart';
import '../screenshots/images_store.dart';
import '../section_title.dart';
import 'message_controller.dart';
import 'message_store.dart';
import 'screenshot_layout.dart';

/// The Message section below Upload (`ai/description_template.md`): its title
/// row with the Generate button at the right, the title line, and the large
/// text box showing the post text.
///
/// The title line is drawn only for a type that has a title (`hasTitle`) and
/// only when there is one. A type with no title has no title file, so there is
/// nothing to show and nothing to copy, and a row that holds nothing is noise
/// rather than a part of the section. The same is what the section shows while
/// nothing has been generated: the placeholder instead of a box with nothing in
/// it, like the Screenshots section does when it has no images.
///
/// The Generate button is in the title row, but only once every image the message
/// reads has been uploaded to the poster hoster: the message is made of those
/// URLs, so before any upload there is nothing it could say, and the placeholder
/// says what has to happen first instead. That is the one thing this section
/// cannot see for itself — the Upload section is what writes `images.json` — so
/// it registers its rebuild with the editor, the widget that places both, and the
/// editor calls it when a run ends. A plain callback, not a listener (rule 3).
///
/// Clicking it validates the fields first, and a generation that fails is said
/// rather than run: nothing is written, so the box and the files stay as they
/// were. The controller answers with field names, because a field list is data,
/// and the words for a problem come from `fieldProblemText` (rule 13). The
/// problems are shown as a message, one line per problem, and the same problems
/// are given to the editor, which is the widget that builds the rows and marks
/// the ones the user can type into.
///
/// The widget owns the box and the title line; the controller owns the render
/// and the write. An edit in the box writes `message.txt` immediately, like the
/// poster writes its file, so the files always match what the section shows,
/// and the message is not part of the dirty flag — `release.json` stores no
/// message. Writing a file stamps `lastEditDate` in the manifest, which is the
/// record of the release changing, not of its fields changing. A message can
/// therefore only be typed after something has been generated: while the box is
/// not drawn there is nowhere to type.
///
/// Regenerating replaces what is in the box: the render is the source of truth.
/// The title is read-only, so it has no edit path.
///
/// What the box shows is a render of the values the template reads, so when those
/// values change it is no longer what a render would produce, and the section
/// goes back to its placeholder: the title line and the box are cleared, and the
/// two files go with them, because the files always match what the section shows.
/// The two things that change those values are outside this widget — the form
/// and the Upload section — so the editor, the widget that places both, tells
/// this one through a plain callback (rule 3): when a field is written through
/// its single write path, and when a run ends. A field is any field, including
/// the ones the app fills, because the message reads the values rather than the
/// rows. An image is only a change when the run added a URL the message reads:
/// a run that wrote nothing, and a generation run that wrote files without URLs,
/// change what the render would produce by nothing, so they do not clear the box.
/// The reset is silent — it is not an error, and the section is already the thing
/// that shows the message.
///
/// The first row after the section's title is the checkbox for the app signature
/// (`ai/description_template.md` §App signature), above the title line. The flag
/// is part of `release.json`, so the write is the editor's: this widget builds
/// the row but does not own the record, and the notice that write sends is what
/// clears the box, because the flag is part of what a render would produce.
///
/// The two flag rows — the signature checkbox and the row of shapes — are
/// drawn only while the generation gate is open (rule 14): before any image
/// the message reads is uploaded there is no render, so a signature and a
/// shape have nothing to be part of, and a row that sets a value nothing uses
/// is noise. The values are still what `release.json` holds, so hiding a row
/// changes nothing: the rows show the same values again when an upload run
/// opens the gate, which is the rebuild this section registers with the editor.
///
/// The shape the screenshot block has is chosen here, for the type that can
/// choose it: the row of radio buttons is the row after the checkbox. The choice
/// is part of `release.json`, so it is written through the editor's single write
/// path rather than by this widget — it builds the row, but it does not own the
/// record. Choosing a shape changes what a render would produce, so it goes
/// through the same reset as a field: the box and the two files go back to the
/// placeholder, and the next generation uses the shape chosen.
///
/// Copying to the clipboard stays here: reading and writing the clipboard are
/// UI actions, like the file picker, not controller side effects.
class MessageSection extends StatefulWidget {
  const MessageSection({
    required this.release,
    required this.subscribeImagesChanged,
    required this.subscribeFieldsChanged,
    required this.onFieldsRefused,
    required this.onScreenshotLayoutChanged,
    required this.onAppSignatureChanged,
    required this.onMessageChanged,
    super.key,
  });

  final Release release;

  /// Registers this section's rebuild with the editor, which calls it when an
  /// upload run ends: whether the generation can run is state the Upload section
  /// changes, so this one cannot read it on its own.
  final void Function(void Function() rebuild) subscribeImagesChanged;

  /// Registers this section's reset with the editor, which calls it when a field
  /// is written through its single write path. The form is not this widget, so
  /// the values the message reads are something it cannot see change (rule 3).
  final void Function(void Function() rebuild) subscribeFieldsChanged;

  /// Reports the fields a generation refused to the editor. The section shows
  /// the message, but the rows are the editor's — it is the widget that
  /// builds them — so marking a field is something it has to do itself. A
  /// plain callback, not a listener (rule 3), the same shape as the one above.
  final void Function(List<FieldProblem>) onFieldsRefused;

  /// Reports the chosen block shape to the editor, which is the widget with the
  /// write path for what `release.json` stores. A plain callback, not a listener
  /// (rule 3), the same shape as the two above.
  final void Function(ScreenshotLayout layout) onScreenshotLayoutChanged;

  /// Reports the chosen signature flag to the editor, which is the widget with the
  /// write path for what `release.json` stores. A plain callback, not a listener
  /// (rule 3), the same shape as the three above.
  final void Function(bool include) onAppSignatureChanged;

  /// Reports that the message changed: a generation wrote the two files, a reset
  /// removed them, or an edit in the box wrote one. The Upload draft section sends
  /// what the files hold, so it is the widget that needs to know, and it cannot
  /// see this one. A plain callback, not a listener (rule 3), the same shape as
  /// the three above; the editor is the widget that places both, so it is where
  /// they meet.
  final void Function() onMessageChanged;

  @override
  State<MessageSection> createState() => _MessageSectionState();
}

class _MessageSectionState extends State<MessageSection> {
  late final MessageController _controller;

  /// Whether every image the message reads is uploaded to the poster hoster.
  /// Widget state: it decides whether the section offers the Generate button, and
  /// a run in another section is what changes it, so the rebuild the editor calls
  /// reads it again.
  late bool _canGenerate;

  /// The post text. Widget state: the box shows it and the file is written from
  /// it.
  late final TextEditingController _text;

  /// The post title. Widget state: it is shown and copied, never edited. Empty
  /// for a type with no title, which draws no row.
  String _title = '';

  bool _busy = false;

  @override
  void initState() {
    super.initState();

    _controller = MessageController(
      release: widget.release,
      templates: context.read<TemplateStore>(),
      renderer: context.read<TemplateRenderer>(),
      images: context.read<ImagesStore>(),
      store: context.read<MessageStore>(),
      releaseStore: context.read<ReleaseStore>(),
    );

    _text = TextEditingController(
      text: _controller.store.loadSync(
        widget.release.directoryPath,
        MessageStore.messageFile,
      ),
    );
    // A type with no title has no title file, so there is nothing to read.
    if (hasTitle(widget.release.releaseType)) {
      _title = _controller.store.loadSync(
        widget.release.directoryPath,
        MessageStore.titleFile,
      );
    }

    _canGenerate = _controller.allImagesUploadedToPosterHoster();

    // The box shows what the files hold. Nothing here says what generated them,
    // so the values as they are now are taken as what they were built from, and
    // the first change to them is what makes the content stale.
    _controller.remember();

    // The copy buttons are enabled by what is there, which changes when the
    // user types or when a generation replaces the text.
    _text.addListener(_onTextChanged);

    widget.subscribeImagesChanged(_imagesChanged);
    widget.subscribeFieldsChanged(_fieldsChanged);
  }

  /// The generation gate is read again, and the content is cleared when the run
  /// added a URL the message reads. Both are the state `images.json` holds, so an
  /// upload run that wrote the URLs changes them; the editor calls this when one
  /// ends. A run that wrote nothing changes the values by nothing, and a
  /// generation run that wrote files without URLs is not something the render
  /// reads, so neither clears the box.
  void _imagesChanged() {
    if (!mounted) return;

    final stale = _controller.valuesChanged();

    setState(() {
      _canGenerate = _controller.allImagesUploadedToPosterHoster();

      if (stale) {
        _title = '';
        _text.clear();
      }
    });

    if (stale) {
      _clearFiles();
    }
  }

  /// A field was written through the editor's single write path, so what the box
  /// shows is no longer what a render would produce. Any field, including the
  /// ones the app fills: the message reads the values, not the rows. Nothing is
  /// cleared when there is nothing to clear.
  void _fieldsChanged() {
    if (!mounted) return;

    if (_title.isEmpty && _text.text.isEmpty) {
      return;
    }

    setState(() {
      _title = '';
      _text.clear();
    });

    _clearFiles();
  }

  /// The files go with the box, because the files always match what the section
  /// shows. The write is the controller's, and a failure is said rather than
  /// swallowed.
  Future<void> _clearFiles() async {
    final result = await _controller.clear();

    if (!mounted) return;

    if (result case MessageFailure failure) {
      _showMessage(_message(failure.kind, AppLocalizations.of(context)!));
    } else {
      // The files are gone, so the section that reads them has to see it.
      widget.onMessageChanged();
    }
  }

  @override
  void dispose() {
    _text.removeListener(_onTextChanged);
    _text.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _message(MessageFailureKind kind, AppLocalizations l10n) =>
      switch (kind) {
        MessageFailureKind.templateNotFound => l10n.templateNotFound,
        MessageFailureKind.styleNotFound => l10n.styleNotFound,
        MessageFailureKind.templateInvalid => l10n.templateInvalid,
        MessageFailureKind.messageFailed => l10n.messageSaveFailed,
      };

  /// The problems as the line the section shows. One line per problem, in the
  /// order the field list lists the fields, because that is the order the form
  /// shows them in. The words are `fieldProblemText`, the same ones the editor
  /// puts under the row it marks (rule 13).
  String _validationMessage(
    List<FieldProblem> problems,
    AppLocalizations l10n,
  ) => l10n.messageValidationFailed(
    [
      for (final problem in problems)
        fieldProblemText(problem, l10n, widget.release.releaseType),
    ].join('\n'),
  );

  Future<void> _generate(AppLocalizations l10n) async {
    setState(() => _busy = true);

    final result = await _controller.generate();

    if (!mounted) return;

    if (result case MessageGenerated generated) {
      // A write from outside the field, so it may move the caret: that is what
      // regenerating means here.
      _title = generated.title;
      _text.value = _text.value.copyWith(text: generated.text);

      // The two files were written, which is what the Upload draft section sends.
      widget.onMessageChanged();
    } else if (result case MessageInvalid invalid) {
      // The rows are the editor's, so it is the widget that marks them;
      // this one shows the message. Both use the same words for the same
      // problem.
      widget.onFieldsRefused(invalid.problems);
      _showMessage(_validationMessage(invalid.problems, l10n));
    } else if (result case MessageFailure failure) {
      _showMessage(_message(failure.kind, l10n));
    }

    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _saveText(String text, AppLocalizations l10n) async {
    if (await _controller.saveText(text) case MessageFailure failure) {
      _showMessage(_message(failure.kind, l10n));
      return;
    }

    // An edit in the box writes the file, and the file is what the Upload draft
    // section sends.
    widget.onMessageChanged();
  }

  Future<void> _copy(String text) async {
    if (text.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
  }

  IconButton _copyButton(String key, String text, AppLocalizations l10n) =>
      IconButton(
        key: ValueKey(key),
        tooltip: l10n.copyToClipboard,
        icon: const Icon(Icons.copy),
        onPressed: text.isEmpty ? null : () => _copy(text),
      );

  /// Whether the row of shapes is drawn. Only the video pack has a choice,
  /// because the two shapes name a video: a file name, a duration, a resolution
  /// and a size. The other types keep the flat block. The switch is exhaustive
  /// over the release types, so a type added to `ReleaseType` has to say whether
  /// it can choose.
  bool _hasLayoutChoice(ReleaseType releaseType) => switch (releaseType) {
    ReleaseType.videoPack => true,
    ReleaseType.singleVideo => false,
    ReleaseType.photosetPack => false,
    ReleaseType.singlePhotoset => false,
    ReleaseType.imageFolderUpload => false,
  };

  /// The words for one shape. The switch is exhaustive over the enum, so a shape
  /// added to it has to be named here.
  String _layoutLabel(ScreenshotLayout layout, AppLocalizations l10n) =>
      switch (layout) {
        ScreenshotLayout.byHoster => l10n.screenshotLayoutByHoster,
        ScreenshotLayout.byItem => l10n.screenshotLayoutByItem,
      };

  /// The row for the signature: the checkbox and the words for it, the checkbox
  /// first as the Upload section's rows put it. The flag is part of
  /// `release.json`, so the write is the editor's — this widget builds the row,
  /// but it does not own the record. The same notice that updates the row is what
  /// clears the box, because the flag is part of what a render would produce.
  Widget _signatureRow(AppLocalizations l10n) {
    final selected = widget.release.includeAppSignature;

    return Row(
      key: const ValueKey('appSignature'),
      children: [
        Checkbox(
          value: selected,
          onChanged: (value) {
            if (value == null || value == selected) {
              return;
            }

            widget.onAppSignatureChanged(value);

            // The row shows what the model holds, so it is updated after the
            // write, the same order as the single write path.
            setState(() {});
          },
        ),
        Expanded(child: Text(l10n.includeAppSignature)),
      ],
    );
  }

  /// The row of the two shapes, with the one the release has selected.
  Widget _layoutRow(AppLocalizations l10n) {
    final selected = widget.release.screenshotLayout;

    return RadioGroup<ScreenshotLayout>(
      key: const ValueKey('screenshotLayout'),
      groupValue: selected,
      onChanged: (layout) {
        if (layout == null || layout == selected) {
          return;
        }

        // The write is the editor's, because the choice is part of
        // `release.json`. The notice it sends is what clears the box: the text
        // shown is no longer what a render would produce with the other shape.
        // The row shows what the model holds, so it is updated after the write,
        // the same order as the single write path.
        widget.onScreenshotLayoutChanged(layout);

        setState(() {});
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.screenshotLayoutLabel),
          const SizedBox(height: 4),
          for (final layout in ScreenshotLayout.values)
            Row(
              children: [
                Radio<ScreenshotLayout>(
                  key: ValueKey('screenshotLayout-${layout.name}'),
                  value: layout,
                ),
                Expanded(child: Text(_layoutLabel(layout, l10n))),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // What the section shows is what there is to show: an empty title draws no
    // row, and an empty message shows the placeholder rather than a box with
    // nothing in it, the same as the Screenshots section does when it has no
    // images. While the images the message reads are not uploaded there is
    // nothing it could say, so the placeholder says what has to happen first and
    // the title row has no action, which is the same row as a title with nothing
    // on its right.
    final hasMessage = _text.text.isNotEmpty;

    return Column(
      key: const ValueKey('messageSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          title: l10n.messageSectionTitle,
          action: _canGenerate
              ? FilledButton(
                  onPressed: _busy ? null : () => _generate(l10n),
                  child: Text(l10n.generateMessage),
                )
              : null,
        ),
        const SizedBox(height: 12),
        // A row that sets a value the app cannot use is not drawn (rule 14).
        // While no image the message reads is uploaded there is no render,
        // so the signature has nothing to be part of and a shape nothing to
        // shape; the rows are drawn only when the gate is open. The values are
        // still what `release.json` holds: hiding a row is not changing what a
        // release was given before.
        if (_canGenerate) ...[
          _signatureRow(l10n),
          const SizedBox(height: 12),
          if (_hasLayoutChoice(widget.release.releaseType)) ...[
            _layoutRow(l10n),
            const SizedBox(height: 12),
          ],
        ],
        if (hasTitle(widget.release.releaseType) && _title.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: Text(_title, style: theme.textTheme.titleSmall)),
              _copyButton('copyTitle', _title, l10n),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (!hasMessage)
          Text(
            _canGenerate ? l10n.noMessage : l10n.messageNeedsImagesFirst,
            style: theme.textTheme.bodySmall,
          )
        else
          TextField(
            key: const ValueKey('messageText'),
            controller: _text,
            minLines: 12,
            maxLines: null,
            enabled: !_busy,
            // The copy button at the top of the box rather than in its middle.
            // `suffixIcon` is placed by `InputDecorator` at the centre of the
            // input area, and nothing the decoration takes changes that; the
            // `suffix` slot is placed on the text's baseline, so with the text
            // aligned to the top the button sits with the first line.
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              suffix: _copyButton('copyMessage', _text.text, l10n),
            ),
            onChanged: (value) => _saveText(value, l10n),
          ),
      ],
    );
  }
}
