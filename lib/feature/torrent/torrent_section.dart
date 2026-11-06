import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../service/launcher/folder_opener.dart';
import '../../service/native_tools/mkbrr.dart';
import '../../service/torrent/torrent_file.dart';
import '../release/release.dart';
import '../release/release_fields.dart';
import '../section_title.dart';
import 'torrent_controller.dart';

/// The Torrent section (`ai/torrents.md`): its title row with the Create button
/// at the right, the Private flag row under it, the progress bar with what the
/// tool reports while it works, and what the run ended with.
///
/// With no source picked there is nothing to hash, so the title row has no action
/// and the section says what has to happen first instead, like the Screenshots
/// section does when it has no item. Which of the two wordings is right is the
/// release type's rule (`release_fields.dart`), not a string this section can
/// know on its own. What a file that is already there says is still shown,
/// because picking a source would not change it.
///
/// The flag row is the first thing under the title, because the flag is what
/// the section's run is asked for, and it is drawn only when there is
/// something it applies to (rule 14): a source a run would hash, or a file
/// whose flag it is. With neither the value belongs to no run and no file, so
/// the row is not drawn rather than shown inactive — the section says what has
/// to happen first instead. What it shows is the file when there is one,
/// because the file is the thing the flag describes; the value in
/// `release.json` is only what a row shows when there is no file, since that
/// is what a run would write. Reading the flag is not a change, so opening a
/// release writes nothing. A file that is already there is something the flag
/// describes on its own, so the row is drawn for it even when no source has
/// been picked, and hiding the row does not change what is stored: the row
/// shows the same value again when it is drawn.
///
/// Changing it while a file is there is a run, not a value, so the section asks
/// first: the row shows what the user picked while the popup is open, and goes
/// back to what the file states when the change is not made. A dismissed popup is
/// not an agreement, the same rule as the close popup. The row is inactive while a
/// run is going, and when the file cannot be read, because a row cannot show a
/// flag it has not read.
///
/// The flag is part of `release.json`, so the write is the editor's: this section
/// builds the row and reports the change to it, as the Message section does with
/// the two flags it owns. The flag is not something a render reads, so nothing is
/// noticed back.
///
/// Which of the editor's two write paths is the right one is which case the section
/// is in. With no file the value is only what a run would be asked for, so it is a
/// change and the tab becomes dirty. With a file the run has already changed the
/// thing the flag describes, so the record has to agree with it at once: the value
/// is written there and then, and the tab does not become dirty, because there is
/// nothing left to save.
///
/// The source is the model, not state this section holds, and typing in the
/// source row does not rebuild the editor, so this section registers its rebuild
/// with the editor — the widget that owns that row — and the editor calls it when
/// the row is written to. A plain callback, not a listener (rule 3).
///
/// The run is one job, so there is one bar rather than a row per thing, and the
/// bar is drawn only once a run has started: before a run there is nothing to
/// show. The percentage, the rate and the remaining time are what the tool
/// reports as it works, so they change during the run; a run that finishes at
/// once reports only the final 100, and the bar shows that. The tool does not say
/// which file it is on, so there is no file to show.
///
/// A release opened again can already have the file. The app records nothing for
/// it, so the section asks the controller whether it is on disk and says what it
/// finds before any run.
///
/// The outcome is said here rather than in a snackbar, because this section is
/// already the thing that shows the run, and a message that disappears is worse
/// than one that stays next to the bar it belongs to.
///
/// The widget owns the progress, the outcomes and the flag being asked about as
/// widget state; the controller owns the side effects. It resolves its
/// dependencies from the provider scope and builds its own per-widget controller,
/// as the other sections do.
class TorrentSection extends StatefulWidget {
  const TorrentSection({
    required this.release,
    required this.subscribeSourceChanged,
    required this.onPrivateChanged,
    required this.onPrivateSaved,
    super.key,
  });

  final Release release;

  /// Registers this section's rebuild with the editor, which calls it when the
  /// source row is written to. The source is not state this section holds, so a
  /// change to it is only seen by building again.
  final void Function(void Function() rebuild) subscribeSourceChanged;

  /// Reports the chosen flag to the editor, which is the widget with the write
  /// path for what `release.json` stores. A plain callback, not a listener
  /// (rule 3), the same shape as the one above.
  ///
  /// This is the path for the case where there is no file: the value is only what
  /// the next run would be asked for, so the write is a change and the tab becomes
  /// dirty.
  final void Function(bool private) onPrivateChanged;

  /// The same flag for the case where a run changed the file it describes: the
  /// record has to agree with the file at once, so the write is a save rather than
  /// a change and the tab does not become dirty. The section is the one that knows
  /// which of the two cases it is in, so the two write paths are two callbacks.
  final Future<void> Function(bool private) onPrivateSaved;

  @override
  State<TorrentSection> createState() => _TorrentSectionState();
}

class _TorrentSectionState extends State<TorrentSection> {
  late final TorrentController _controller;

  /// What the last run answered with — a create or a flag change. Widget state,
  /// for the bar and the message: the app records nothing for the torrent file,
  /// so the section is the only place a run's outcome exists, and it is not read
  /// back from the release.
  MkbrrProgress? _progress;

  MkbrrResult? _result;

  /// The flag the row shows while the popup is open. Widget state, because the
  /// change is not applied until the popup is answered: the row shows what the
  /// user picked, and goes back to what the file states when the change is not
  /// made.
  bool? _pending;

  bool _busy = false;

  /// Whether the last attempt to open the folder failed. Widget state, because
  /// nothing is recorded for it either.
  bool _openFailed = false;

  @override
  void initState() {
    super.initState();

    _controller = TorrentController(
      release: widget.release,
      mkbrr: context.read<Mkbrr>(),
      folderOpener: context.read<FolderOpener>(),
    );

    widget.subscribeSourceChanged(_rebuild);
  }

  /// The section builds again, which is what reads the source row again. The
  /// editor calls this when that row is written to.
  void _rebuild() {
    if (!mounted) return;

    setState(() {});
  }

  Future<void> _create(AppLocalizations l10n) async {
    // A run starts from nothing, so a second run does not show the numbers of
    // the previous one while it works.
    setState(() {
      _busy = true;
      _progress = null;
      _result = null;
      _openFailed = false;
    });

    final result = await _controller.create(
      onProgress: (progress) {
        if (!mounted) return;

        setState(() => _progress = progress);
      },
    );

    if (!mounted) return;

    setState(() {
      _busy = false;
      _result = result;
    });
  }

  /// Change the flag. With no file there is nothing to run, so the value is only
  /// what the next run would be asked for and the write is the editor's, the same
  /// rule as for a field. With a file the change is a run, so the section asks
  /// first and runs only on the answer.
  Future<void> _changePrivate(AppLocalizations l10n, bool value) async {
    final path = _controller.existingTorrent();

    if (path == null) {
      widget.onPrivateChanged(value);
      setState(() {});
      return;
    }

    setState(() => _pending = value);

    if (!await _ask(l10n, value)) {
      if (!mounted) return;

      setState(() => _pending = null);
      return;
    }

    // The change is a run, so it is the same single job as a create: nothing
    // else can use the tool while it is going.
    setState(() => _busy = true);

    final result = await _controller.modify(torrentPath: path, private: value);

    if (!mounted) return;

    if (result is MkbrrModified) {
      // The record has to agree with the file the run changed, so this is the save
      // path rather than the change path: the value is written there and then, and
      // the tab is not marked dirty, because the file is already changed and there
      // is nothing left to save.
      await widget.onPrivateSaved(value);

      if (!mounted) return;
    }

    setState(() {
      _busy = false;
      _pending = null;
      _result = result;
    });
  }

  Future<bool> _ask(AppLocalizations l10n, bool value) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.torrentPrivateTitle),
        content: Text(
          l10n.torrentPrivateMessage(
            value
                ? l10n.torrentPrivateValuePrivate
                : l10n.torrentPrivateValueNotPrivate,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.torrentPrivateConfirm),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );

    return agreed ?? false;
  }

  Future<void> _open() async {
    final result = await _controller.openDirectory();

    if (!mounted) return;

    setState(() => _openFailed = result is FolderOpenFailed);
  }

  /// What the section says about the file: what a run wrote, what a flag change
  /// answered with, or what was already there when the release was opened. The
  /// tool name is in the strings, as the other tool messages are, and the reason a
  /// flag change gives is what the tool printed, because a modify that cannot
  /// process the file still exits 0.
  ///
  /// A flag change that worked has nothing to say for itself: the row showing the
  /// new flag is the answer, and the line naming the file is the same as before
  /// it.
  String? _message(AppLocalizations l10n, String? path) {
    final outcome = switch (_result) {
      MkbrrCreated(path: final created) => l10n.torrentCreated(created),
      MkbrrModifyFailed(reason: final reason) => l10n.mkbrrModifyFailed(reason),
      MkbrrNotPresent() => l10n.mkbrrNotAvailable,
      MkbrrRunFailed(exitCode: final exitCode) => l10n.mkbrrRunFailed(exitCode),
      MkbrrRunTimeout() => l10n.mkbrrRunTimeout,
      MkbrrModified() => null,
      null => null,
    };

    return outcome ?? (path == null ? null : l10n.torrentAlreadyCreated(path));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // The file the section is about: what a run wrote, what a flag change
    // answered with, or what was already there when the release was opened.
    // Nothing is recorded for it, so the section asks the controller while it
    // builds, the same way the poster box asks for its file. It is also what the
    // link points at, so the link is shown only when there is a path to be next
    // to.
    final path = switch (_result) {
      MkbrrCreated(path: final created) => created,
      MkbrrModified(path: final modified) => modified,
      null => _controller.existingTorrent(),
      _ => null,
    };

    // The flag the row shows. The file on disk is what the flag describes, so a
    // row shows what it states when there is one; the value in `release.json` is
    // what a run would write, so it is what the row shows when there is no file.
    final diskPath = _controller.existingTorrent();
    final flag = diskPath == null ? null : _controller.privateFlag(diskPath);

    final shown =
        _pending ??
        (flag is TorrentFlagRead ? flag.value : widget.release.torrentPrivate);

    final message = _message(l10n, path);

    // Whether a run can start at all: there is nothing to hash until the user
    // picks the source. Which of the two wordings is right is the release type's
    // rule (`release_fields.dart`), not something this section can know on its
    // own.
    final hasSource = widget.release.source.trim().isNotEmpty;

    // The row is drawn only when there is something the flag applies to
    // (rule 14): a source a run would hash, or a file whose flag it is. With
    // neither there is no run the value could be asked for and no file it
    // describes, so the row would show a value nothing uses. A file that is
    // already there is such a thing on its own, so the row is drawn for it
    // whatever else the section can do.
    final applies = hasSource || diskPath != null;

    final placeholder =
        fieldListFor(widget.release.releaseType).sourceKind ==
            SourceKind.directory
        ? l10n.torrentPickFolderFirst
        : l10n.torrentPickFileFirst;

    return Column(
      key: const ValueKey('torrentSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The button is in the title row because it is the action of the whole
        // section. It is not there when there is nothing it can run on. It is
        // disabled while a run is going: the tool cannot be run twice on the same
        // output at the same time.
        SectionTitle(
          title: l10n.torrentSectionTitle,
          action: hasSource
              ? FilledButton(
                  onPressed: _busy ? null : () => _create(l10n),
                  child: Text(l10n.torrentButton),
                )
              : null,
        ),
        const SizedBox(height: 12),
        // The flag is what a run is asked for, so the row is the first
        // thing under the title, and only when there is something it applies
        // to. It is inactive while a run is going, and when the file cannot
        // be read, because a row cannot show a flag it has not read.
        if (applies) ...[
          Row(
            key: const ValueKey('torrentPrivate'),
            children: [
              Checkbox(
                value: shown,
                onChanged: _busy || flag is TorrentFlagUnreadable
                    ? null
                    : (value) => _changePrivate(l10n, value ?? shown),
              ),
              Expanded(child: Text(l10n.torrentPrivateLabel)),
            ],
          ),
          if (flag is TorrentFlagUnreadable) ...[
            const SizedBox(height: 4),
            Text(
              l10n.torrentPrivateNotReadable,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
        if (_progress != null) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _progress!.percent / 100),
          const SizedBox(height: 4),
          Text(
            l10n.torrentProgress(_progress!.percent),
            style: theme.textTheme.bodySmall,
          ),
          if (_progress!.speed != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.torrentSpeed(_progress!.speed!),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (_progress!.eta != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.torrentEta(_progress!.eta!),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
        // What has to happen first, shown only when there is nothing else to
        // say: a file that is already there is not something picking a source
        // would change, so the section still reports it.
        if (!hasSource && message == null) ...[
          const SizedBox(height: 8),
          Text(placeholder, style: theme.textTheme.bodySmall),
        ] else if (message != null) ...[
          const SizedBox(height: 8),
          Text(message, style: theme.textTheme.bodySmall),
        ],
        if (_openFailed) ...[
          const SizedBox(height: 4),
          Text(l10n.folderOpenFailed, style: theme.textTheme.bodySmall),
        ],
        if (path != null) ...[
          // The link is the directory the file is in, and its text is the path
          // itself: a path is data, not a string, so it needs no key of its own.
          const SizedBox(height: 4),
          TextButton(
            onPressed: _open,
            child: Text(widget.release.directoryPath),
          ),
        ],
      ],
    );
  }
}
