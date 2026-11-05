import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../service/launcher/url_opener.dart';
import '../../service/network/pornolab_client.dart';
import '../message/message_store.dart';
import '../pornolab_results.dart';
import '../release/field_validation.dart';
import '../release/release.dart';
import '../release/release_fields.dart';
import '../settings/settings_controller.dart';
import '../section_title.dart';
import 'draft_controller.dart';

/// The Upload draft section (`ai/uploading_draft.md`): its title row with the
/// Upload button at the right, the parent forum row, and the link to the draft
/// the last run saved, with the label that says what it is above it and the copy
/// button next to it.
///
/// Which release types this section is drawn for is the editor's decision,
/// because it is the widget that places it; the field list is what says whether
/// a type has the field at all (`ai/uploading_draft.md` §4).
///
/// The row is this section's, not one the form builds, so the section owns the
/// input, as the Stash row owns its input. It does not own the record: the field
/// and the stored link are written through the editor's single write path, so
/// the tab becomes dirty and Ctrl+S saves them.
///
/// What the section shows depends on two things outside it: whether a message
/// exists, which the Message section changes, and the cookie, which the Settings
/// page changes. The first is reported to the editor and reaches this section as
/// a rebuild (rule 3); the second is read from `SettingsController`, which is
/// the widget that holds it. A section with nothing to send shows what has to
/// happen first instead of its action, as the Screenshots section does when it
/// has no item.
///
/// The link is shown whenever the release has one, even when the box was reset:
/// a stored link is not something a reset takes away, the same rule as the
/// Torrent section's path. Its text is the link itself, because a link is data,
/// and the label above it is what says what it is — the words of the field this
/// section owns, taken from `fieldLabel` as the StashDB section's input does.
class DraftSection extends StatefulWidget {
  const DraftSection({
    required this.release,
    required this.onApply,
    required this.subscribeMessageChanged,
    super.key,
  });

  final Release release;

  /// Writes the field and the stored link through the editor's single write
  /// path.
  final void Function(Map<String, String> values) onApply;

  /// Registers this section's rebuild with the editor, which calls it when the
  /// Message section writes or clears the two files. Whether there is something
  /// to send is state that section changes, so this one cannot read it on its
  /// own (rule 3).
  final void Function(void Function() rebuild) subscribeMessageChanged;

  @override
  State<DraftSection> createState() => _DraftSectionState();
}

class _DraftSectionState extends State<DraftSection> {
  late final DraftController _controller;
  late final UrlOpener _opener;

  /// The parent forum input. The section owns the row, so it owns the
  /// controller; the value it holds is the field, and it is written through the
  /// editor.
  late final TextEditingController _input;

  /// What the last run ended with. Widget state, as the Torrent section's is:
  /// the section shows it, and nothing else can know what a run said.
  PornolabResult? _result;

  bool _busy = false;

  bool _openFailed = false;

  @override
  void initState() {
    super.initState();

    _controller = DraftController(
      release: widget.release,
      store: context.read<MessageStore>(),
      client: context.read<PornolabClient>(),
      settings: context.read<SettingsController>(),
    );
    _opener = context.read<UrlOpener>();

    // The input starts with what `release.json` holds for the field: this is the
    // widget that field has, so a reopened release shows the URL it was stored
    // with.
    _input = TextEditingController(
      text: widget.release.fields.value('parentForum'),
    );

    widget.subscribeMessageChanged(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() => _busy = true);

    final result = await _controller.run();

    if (!mounted) return;

    setState(() {
      _busy = false;
      _result = result;
    });

    if (result case DraftSaved(draftUrl: final url)) {
      // The link is stored through the editor's single write path, so the tab
      // becomes dirty and Ctrl+S saves it, the same way the Stash row writes.
      widget.onApply({'draftUrl': url});
    }
  }

  Future<void> _open(String url) async {
    if (await _opener.open(url) is UrlOpenFailed) {
      if (mounted) setState(() => _openFailed = true);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  Widget _forumRow(
    AppLocalizations l10n,
    FieldProblem? problem,
  ) => TextFormField(
    // A row the form does not build is keyed by the widget that has it, as the
    // Stash row keys its input, so the test that says the form builds no row for
    // this field can still find the row that does.
    key: const ValueKey('draftForumInput'),
    controller: _input,
    decoration: InputDecoration(
      labelText: l10n.parentForumLabel,
      // The words for the problem this row has. The row is this section's, so
      // the section says them here; they are the same ones the editor puts under
      // a row it marks (rule 13).
      errorText: problem == null
          ? null
          : fieldProblemText(problem, l10n, widget.release.releaseType),
      border: const OutlineInputBorder(),
    ),
    onChanged: (value) {
      // Written through the editor's single write path. The row shows what was
      // typed already, so what changes here is the problem and the button.
      widget.onApply({'parentForum': value});
      setState(() {});
    },
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // The cookie is a setting, so the section reads it through the controller that
    // holds it and watches it: a login made on the settings page is something this
    // section shows.
    final settings = context.watch<SettingsController>();

    final hasMessage = _controller.hasMessage();
    final hasCookie = _controller.hasCookie();
    final problem = _controller.forumProblem();
    final hasForum = _input.text.trim().isNotEmpty && problem == null;

    // What the button needs before it can run, in the order the section can be
    // missing them. The field's shape is said by its own row, so the tooltip
    // names an empty field rather than repeating the rule. The login is one of
    // these because the app does not make one by itself
    // (`ai/pornolab_login.md` §7).
    final needs = !hasMessage
        ? null
        : !hasCookie
        ? l10n.draftNeedsLoginFirst
        : !hasForum
        ? l10n.draftNeedsForumFirst
        : null;

    final button = FilledButton(
      key: const ValueKey('draftUploadButton'),
      onPressed: _busy || needs != null ? null : () => _run(),
      child: Text(l10n.draftUploadButton),
    );

    final url = widget.release.fields.value('draftUrl');

    return Column(
      key: const ValueKey('draftSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The button is in the title row because it is the action of the whole
        // section. It is not there when there is no message to send, and it is
        // disabled while something it reads is missing.
        SectionTitle(
          title: l10n.draftSectionTitle,
          action: hasMessage
              ? needs == null
                    ? button
                    : Tooltip(message: needs, child: button)
              : null,
        ),
        const SizedBox(height: 12),
        // The row is drawn only when there is something to send, because a run
        // cannot be made without a message and the field is the section's own.
        // What has to happen first is shown instead of it.
        if (!hasMessage) ...[
          Text(l10n.draftNeedsMessageFirst, style: theme.textTheme.bodySmall),
        ] else ...[
          _forumRow(l10n, problem),

          // What a run ended with. A run that had to make a new draft says so,
          // because the link the release holds changed and the user cannot see
          // why otherwise (`ai/uploading_draft.md` §6).
          if (_result case DraftSaved(recreated: true)) ...[
            const SizedBox(height: 8),
            Text(l10n.draftRecreated, style: theme.textTheme.bodySmall),
          ] else if (_result case PornolabFailure failure) ...[
            const SizedBox(height: 8),
            Text(
              pornolabResultText(failure.kind, l10n, settings),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
        if (_openFailed) ...[
          const SizedBox(height: 4),
          Text(l10n.linkOpenFailed, style: theme.textTheme.bodySmall),
        ],
        if (url.isNotEmpty) ...[
          const SizedBox(height: 4),
          // The text of the link is the link itself, because a link is data, so
          // the label is what says what it is. It is the words of the field this
          // section owns, asked for the way the StashDB section asks for its
          // input's, and it is drawn only when there is a link to label.
          Text(
            fieldLabel('draftUrl', l10n, widget.release.releaseType),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          // The copy button is next to the link because the text is what a user
          // takes somewhere else: a browser they paste it into, another post. It
          // is the same call the Message section's copy buttons make, and it
          // says nothing when it works, as they do.
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => _open(url),
                  child: Text(url),
                ),
              ),
              IconButton(
                key: const ValueKey('copyDraftLink'),
                tooltip: l10n.copyToClipboard,
                icon: const Icon(Icons.copy),
                onPressed: () => _copy(url),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
