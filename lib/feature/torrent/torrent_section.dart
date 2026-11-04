import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../service/launcher/folder_opener.dart';
import '../../service/native_tools/mkbrr.dart';
import '../release/release.dart';
import '../release/release_fields.dart';
import '../section_title.dart';
import 'torrent_controller.dart';

/// The Torrent section (`ai/torrents.md`): its title row with the Create button
/// at the right, the progress bar with what the tool reports while it works, and
/// what the run ended with.
///
/// With no source picked there is nothing to hash, so the title row has no action
/// and the section says what has to happen first instead, like the Screenshots
/// section does when it has no item. Which of the two wordings is right is the
/// release type's rule (`release_fields.dart`), not a string this section can
/// know on its own. What a file that is already there says is still shown,
/// because picking a source would not change it.
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
/// The widget owns the progress and the outcome as widget state; the controller
/// owns the side effects. It resolves its dependencies from the provider scope and
/// builds its own per-widget controller, as the other sections do.
class TorrentSection extends StatefulWidget {
  const TorrentSection({
    required this.release,
    required this.subscribeSourceChanged,
    super.key,
  });

  final Release release;

  /// Registers this section's rebuild with the editor, which calls it when the
  /// source row is written to. The source is not state this section holds, so a
  /// change to it is only seen by building again.
  final void Function(void Function() rebuild) subscribeSourceChanged;

  @override
  State<TorrentSection> createState() => _TorrentSectionState();
}

class _TorrentSectionState extends State<TorrentSection> {
  late final TorrentController _controller;

  /// What the last run reported. Widget state, for the bar and the message: the
  /// app records nothing for the torrent file, so the section is the only place
  /// the run's outcome exists, and it is not read back from the release.
  MkbrrProgress? _progress;

  MkbrrResult? _result;

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

  Future<void> _open() async {
    final result = await _controller.openDirectory();

    if (!mounted) return;

    setState(() => _openFailed = result is FolderOpenFailed);
  }

  /// What the section says about the file: what a run wrote, or what was already
  /// there when the release was opened. The tool name is in the strings, as the
  /// other tool messages are.
  String? _message(AppLocalizations l10n, String? path) => switch (_result) {
    MkbrrCreated(path: final created) => l10n.torrentCreated(created),
    MkbrrNotPresent() => l10n.mkbrrNotAvailable,
    MkbrrRunFailed(exitCode: final exitCode) => l10n.mkbrrRunFailed(exitCode),
    MkbrrRunTimeout() => l10n.mkbrrRunTimeout,
    null => path == null ? null : l10n.torrentAlreadyCreated(path),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // The file the section is about: what a run wrote, or what was already there
    // when the release was opened. Nothing is recorded for it, so the section
    // asks the controller while it builds, the same way the poster box asks for
    // its file. It is also what the link points at, so the link is shown only
    // when there is a path to be next to.
    final path = _result == null
        ? _controller.existingTorrent()
        : switch (_result!) {
            MkbrrCreated(path: final created) => created,
            _ => null,
          };

    final message = _message(l10n, path);

    // Whether a run can start at all: there is nothing to hash until the user
    // picks the source. Which of the two wordings is right is the release type's
    // rule (`release_fields.dart`), not something this section can know on its
    // own.
    final hasSource = widget.release.source.trim().isNotEmpty;
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
        if (_progress != null) ...[
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
        if (!hasSource && message == null)
          Text(placeholder, style: theme.textTheme.bodySmall)
        else if (message != null) ...[
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
