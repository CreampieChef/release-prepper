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

/// The Upload draft section (`ai/uploading_draft.md`, `ai/pornolab_upload.md`):
/// its title row with the two actions at the right, the parent forum row with
/// the name the site gives for the forum it holds, the outcome of the last run,
/// and the links the release has, each with the label that says what it is and
/// the copy button.
///
/// Which release types this section is drawn for is the editor's decision,
/// because it is the widget that places it; the field list is what says whether
/// a type has the field at all (`ai/uploading_draft.md` §4).
///
/// The row is this section's, not one the form builds, so the section owns the
/// input, as the Stash row owns its input. It does not own the record: the
/// field and the links are written through the editor's single write path, so
/// the tab becomes dirty and Ctrl+S saves them.
///
/// The publish action is drawn only for a release that has a draft, because a
/// post is made from a draft; and not for one that already has a topic, because
/// a second post would be a second topic for the same text
/// (`ai/pornolab_upload.md` §5). It is the first action of the app whose result
/// the user cannot take back, so it is asked for before it runs, and the
/// checkbox in the popup is what makes the answer an agreement: a dismissed
/// popup is not one.
///
/// The name on the row is what a page said, so it is widget state and nothing
/// stored: the run works from the id the value names, which is why a page with
/// no name leaves the row as it is (`ai/pornolab_upload.md` §5).
///
/// What the section shows depends on things outside it: whether a message
/// exists, which the Message section changes, the cookie, which the Settings
/// page changes, and the file, which the Torrent feature's run writes. The
/// message and the file are reported to the editor and reach this section as a
/// rebuild, because a change made outside this widget is not something it can
/// see without building again (rule 3); the cookie is read from
/// `SettingsController`, which is the widget that holds it. The three are read
/// again on that rebuild, as the file is read by the Torrent section.
///
/// A link the release already has is shown even when the box has been reset: a
/// stored link is not something a reset takes away, the same rule as the
/// Torrent section's path. Its text is the link itself, because a link is data,
/// and the label above it is what says what it is — the words of the field this
/// section owns, taken from `fieldLabel` as the StashDB section's input does.
class DraftSection extends StatefulWidget {
  const DraftSection({
    required this.release,
    required this.onApply,
    required this.subscribeMessageChanged,
    required this.subscribeFileWritten,
    super.key,
  });

  final Release release;

  /// Writes the field and the stored links through the editor's single write
  /// path.
  final void Function(Map<String, String> values) onApply;

  /// Registers this section's rebuild with the editor, which calls it when the
  /// Message section writes or clears the two files. Whether there is something
  /// to send is state that section changes, so this one cannot read it on its
  /// own (rule 3).
  final void Function(void Function() rebuild) subscribeMessageChanged;

  /// Registers this section's rebuild with the editor, which calls it when a
  /// Torrent run writes the file. The publish action is gated on the file being
  /// there, and the run is another section's, so a file that appears is not
  /// something this widget can see without building again (rule 3).
  final void Function(void Function() rebuild) subscribeFileWritten;

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

  /// The name the page gave for the forum the value names. Widget state,
  /// because it is what a page said and nothing the release stores
  /// (`ai/pornolab_upload.md` §5).
  String? _name;

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
    widget.subscribeFileWritten(_rebuild);

    // A value that already passes the shape rule is the one the row would name,
    // so the name is asked for as the section is opened. An empty value is not
    // asked for: the field is not required, so a problem for it is nothing, and
    // there is nothing to name.
    if (_input.text.trim().isNotEmpty && _controller.forumProblem() == null) {
      _readName();
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
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

  /// A post, after the popup. The popup is the whole of the difference between
  /// this and an ordinary run: the result of a post cannot be taken back, so
  /// the section asks first and a dismissed popup is not an answer
  /// (`ai/pornolab_upload.md` §5).
  Future<void> _publish() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => _PublishPopup(
        forum: _name ?? _input.text.trim(),
        title: _controller.subject(),
      ),
    );

    if (agreed != true || !mounted) return;

    setState(() => _busy = true);

    final result = await _controller.post();

    if (!mounted) return;

    setState(() {
      _busy = false;
      _result = result;
    });

    if (result case Posted(topicUrl: final url, filePath: final path)) {
      // The link is what a run read and the path is what a run wrote, so both
      // go through the editor's single write path. A path is recorded only for
      // a run that wrote a file, as the notice says only what a run wrote
      // (`ai/pornolab_upload.md` §8).
      final values = {'topicUrl': url};

      if (path != null) {
        values['trackerTorrentFile'] = path;
      }

      widget.onApply(values);
    }
  }

  Future<void> _readName() async {
    final result = await _controller.readName(_input.text.trim());

    if (!mounted) return;

    // A name is shown when the page gave one and not otherwise; the result of
    // that read is not said, because the row is already showing the value the
    // run uses.
    setState(() => _name = result is ForumNameRead ? result.name : null);
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
      // Written through the editor's single write path, which updates the
      // model, so the problem read after it is the problem with what was just
      // typed.
      widget.onApply({'parentForum': value});

      // The name is asked for only for a value the rule accepts, and not for an
      // empty one, which has no problem because the field is not required.
      if (value.trim().isNotEmpty && _controller.forumProblem() == null) {
        _readName();
      } else {
        setState(() => _name = null);
      }

      setState(() {});
    },
  );

  /// The link the release has, with the label that says what it is and the copy
  /// button next to it. The two links are the same shape, because both are what
  /// a run wrote and both are data rather than text.
  Widget _link(
    AppLocalizations l10n,
    String label,
    String url,
    String copyKey,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: TextButton(onPressed: () => _open(url), child: Text(url)),
          ),
          IconButton(
            key: ValueKey(copyKey),
            tooltip: l10n.copyToClipboard,
            icon: const Icon(Icons.copy),
            onPressed: () => _copy(url),
          ),
        ],
      ),
    ],
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
    final hasFile = _controller.hasFile();

    // What the buttons need before either can run, in the order the section can
    // be missing them. The field's shape is said by its own row, so the tooltip
    // names an empty field rather than repeating the rule. The login is one of
    // these because the app does not make one by itself (`ai/pornolab_login.md`
    // §7), and the file is the last one because only a post needs it
    // (`ai/pornolab_upload.md` §7).
    final needs = !hasMessage
        ? null
        : !hasCookie
        ? l10n.draftNeedsLoginFirst
        : !hasForum
        ? l10n.draftNeedsForumFirst
        : null;

    // The same list with the file added, which is what the publish button is
    // gated on. The word for the file names the action that makes it, as the
    // word for the login names the page that makes it.
    final needsPublish = needs == null && !hasFile
        ? l10n.publishNeedsFileFirst
        : needs;

    final draftUrl = widget.release.fields.value('draftUrl');
    final topicUrl = widget.release.fields.value('topicUrl');

    final upload = FilledButton(
      key: const ValueKey('draftUploadButton'),
      onPressed: _busy || needs != null ? null : () => _run(),
      child: Text(l10n.draftUploadButton),
    );

    // The publish button is drawn only when there is a draft to post, and not
    // for a release that already has a topic: the second post would be a second
    // topic for the same text (`ai/pornolab_upload.md` §5).
    final publish = draftUrl.isEmpty || topicUrl.isNotEmpty
        ? null
        : FilledButton(
            key: const ValueKey('publishButton'),
            onPressed: _busy || needsPublish != null ? null : () => _publish(),
            child: Text(l10n.publishButton),
          );

    return Column(
      key: const ValueKey('draftSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Both buttons are in the title row because both are actions of the
        // whole section. Neither is there when there is nothing to send, and
        // each is disabled while something it reads is missing.
        SectionTitle(
          title: l10n.draftSectionTitle,
          action: hasMessage
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (needs != null)
                      Tooltip(message: needs, child: upload)
                    else
                      upload,
                    if (publish != null) ...[
                      const SizedBox(width: 8),
                      if (needsPublish != null)
                        Tooltip(message: needsPublish, child: publish)
                      else
                        publish,
                    ],
                  ],
                )
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

          // The name the page gave for the forum the value names, drawn only
          // when there is a name to draw, as the label above a link is.
          if (_name != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.parentForumName(_name!),
              style: theme.textTheme.bodySmall,
            ),
          ],

          // What a run ended with. A run that had to make a new draft says so,
          // because the link the release holds changed and the user cannot see
          // why otherwise (`ai/uploading_draft.md` §6). A post says the file,
          // because that is the part of a run the user cannot see from the
          // link: the topic exists whether the file was written or not
          // (`ai/pornolab_upload.md` §8).
          if (_result case DraftSaved(recreated: true)) ...[
            const SizedBox(height: 8),
            Text(l10n.draftRecreated, style: theme.textTheme.bodySmall),
          ] else if (_result case Posted posted) ...[
            const SizedBox(height: 8),
            Text(postFileText(posted, l10n), style: theme.textTheme.bodySmall),
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
        if (draftUrl.isNotEmpty)
          _link(
            l10n,
            fieldLabel('draftUrl', l10n, widget.release.releaseType),
            draftUrl,
            'copyDraftLink',
          ),
        if (topicUrl.isNotEmpty)
          _link(
            l10n,
            fieldLabel('topicUrl', l10n, widget.release.releaseType),
            topicUrl,
            'copyTopicLink',
          ),
      ],
    );
  }
}

/// The popup a post is asked for (`ai/pornolab_upload.md` §5). It names the
/// forum the post goes to and the title it carries, because the result cannot
/// be taken back and the user decides about values they may have changed since
/// the last run. It is capped at 1000 px, as the Stash popup is: a dialog with
/// no constraints of its own is limited only by the screen, and the title it
/// names can be as long as a title gets.
///
/// The checkbox is what makes the answer an agreement, and it is the user's own
/// statement: that the draft is verified and is to be uploaded as it is, and
/// that the result is permanent. The confirm button is disabled until it is
/// checked, and a dismissed popup is not an answer. The app does not post
/// twice, so this is asked once per release.
class _PublishPopup extends StatefulWidget {
  const _PublishPopup({required this.forum, required this.title});

  final String forum;
  final String title;

  @override
  State<_PublishPopup> createState() => _PublishPopupState();
}

class _PublishPopupState extends State<_PublishPopup> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      // Capped as the class docstring says, so a long title is shown as lines
      // rather than as a popup as wide as the window.
      constraints: const BoxConstraints(maxWidth: 1000),
      title: Text(l10n.publishTitle),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.publishNames(widget.forum, widget.title)),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                key: const ValueKey('publishCheck'),
                value: _checked,
                onChanged: (value) => setState(() => _checked = value ?? false),
              ),
              Expanded(child: Text(l10n.publishCheck)),
            ],
          ),
        ],
      ),
      actions: [
        // The confirm is what makes the answer an agreement, so it is only
        // there once the box is checked (`ai/pornolab_upload.md` §5).
        TextButton(
          key: const ValueKey('publishConfirmButton'),
          onPressed: _checked ? () => Navigator.of(context).pop(true) : null,
          child: Text(l10n.publishConfirm),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
