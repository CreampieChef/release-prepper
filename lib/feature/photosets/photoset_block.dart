import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../progress_row.dart';
import '../release/release_type.dart';
import '../section_title.dart';
import '../../service/photosets/photoset_scanner.dart';
import 'photoset_group.dart';
import 'photosets_controller.dart';

/// The Photoset data block (`ai/picking.md` §7, `ai/photoset_pack.md` §4, §6,
/// `ai/single_photoset.md` §7): its heading with the Scan and Pick buttons at
/// the right, the rows the editor gives it, the header naming the list of sets,
/// and the line naming each set the scan found. For a pack the header is drawn,
/// for a single photoset it is not (`ai/picking.md` §7).
///
/// For a pack the block is the page's second column, at the most the width this
/// feature gives it. Its rows are the path the user picked and the counts the
/// scan took from that folder — the rows the other types have as form rows,
/// which for this type belong to the block — and the lines below them. The
/// photos those lines describe are the photo area, which is another grid cell
/// and is drawn by `PhotosetGallery`: one widget cannot be two cells, which is
/// why the block and the gallery are two widgets sharing one `PhotosetState`.
///
/// For a single photoset there are no columns to put the pictures in, so the
/// block is the whole section below the form: it is given no rows, and it draws
/// its photos under the line at the whole width, with the same grid the pack
/// uses (`ai/single_photoset.md` §7). The strings are the only thing branched
/// on the type, as they are for the other sections (`ai/single_photoset.md`
/// §4).
///
/// There is no slider: the number is decided by the rule, and the block shows
/// what it decided rather than letting the user change it. Pick is disabled
/// until a scan has run, because the rule reads the counts.
///
/// A run shows what it has done as it goes, through the callback the controller
/// reports on (`ai/photoset_pack.md` §4): a set is named in the list as the scan
/// reads it, and a photo appears as the run copies it. The row that shows the
/// count of a run is drawn only while that run is going, because before a run
/// there is nothing to show and after it the lines the run produced are what the
/// block shows (`ai/torrents.md`).
///
/// The widget owns the widget state — the busy flag, the counts the runs report,
/// and the last scan it was given — but not the state the pictures read: the
/// controller, the generation and what a run has written live in
/// `PhotosetState`, because the gallery reads them too. It writes no fields
/// itself: the values the scan counts are handed to the editor's single write
/// path through `onApplyValues`, so the tab becomes dirty and Ctrl+S saves them,
/// and they are written at the end of a run because they are what the whole scan
/// counted — a run that has read half the folder cannot state them.
class PhotosetBlock extends StatefulWidget {
  const PhotosetBlock({
    required this.state,
    required this.onApplyValues,
    required this.onRunWritten,
    this.rows = const [],
    super.key,
  });

  /// The controller and the generation the pictures are keyed with. Built by the
  /// editor, which places the block and the gallery (`AGENTS.md` §5).
  final PhotosetState state;

  /// Writes the values the scan counted through the editor's single write path.
  final void Function(Map<String, String> values) onApplyValues;

  /// Tells the editor a run wrote files, so it builds again and the gallery shows
  /// the pictures with the generation this block advanced — the same reason the
  /// sections are given `onImagesChanged` (`ai/upload_images.md`). A run reports
  /// each photo as it writes it, so this is called as each one is written, not
  /// only at the end of the run: the block is the widget that runs, and the area
  /// that draws the pictures is another one.
  final void Function() onRunWritten;

  /// The rows the block draws between its heading and its lines. Only the pack has
  /// any: the path the user picked and the count fields, which the editor builds
  /// because they are form rows (`ai/picking.md` §7).
  final List<Widget> rows;

  @override
  State<PhotosetBlock> createState() => _PhotosetBlockState();
}

class _PhotosetBlockState extends State<PhotosetBlock> {
  /// Which action is running. Widget state, for the progress indicator on the
  /// button that is.
  _Action _action = _Action.none;

  /// What the two runs have reported, for the rows that show them. Widget state.
  ScanProgress? _scanProgress;
  CopyProgress? _pickProgress;

  /// The last scan the block was given. The pick needs the photo names, and those
  /// are what the scan read, so a block that has not scanned cannot pick.
  ScanSuccess? _lastScan;

  // The gap a title row has before its content, and the gap between two rows of a
  // form: the same numbers the editor's columns use, because the block draws rows
  // the editor built.
  static const _titleGap = 12.0;
  static const _rowGap = 16.0;

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scan(AppLocalizations l10n) async {
    setState(() {
      _action = _Action.scan;
      _scanProgress = null;
      _pickProgress = null;
    });

    final result = await widget.state.controller.scan(
      onProgress: (progress) {
        if (!mounted) return;

        // The controller records each item as the scan reads it, so the lines
        // this widget builds name the sets it has read: a set appears as it is
        // scanned rather than when the run ends (`ai/photoset_pack.md` §4).
        setState(() => _scanProgress = progress);
      },
    );

    if (!mounted) return;

    widget.onApplyValues(result.values);

    if (result is PhotosetSuccess) {
      _lastScan = result.scan;
    }

    // What the scan could not take is reported rather than guessed at: entries
    // at the top level that are not photosets, photos whose header could not be
    // read, and display names two items would share.
    if (result.skipped.isNotEmpty) {
      _showMessage(l10n.photosetSkippedEntries(result.skipped.join(', ')));
    }

    if (result.unreadPhotos.isNotEmpty) {
      _showMessage(l10n.photosetUnreadPhotos(result.unreadPhotos.join(', ')));
    }

    // A display name is derived from the path, so `set01.zip` and `set01` both
    // show as `set01`. The two items keep their own paths, which are their IDs.
    if (result.nameCollisions.isNotEmpty) {
      _showMessage(
        l10n.photosetNameCollisions(
          [
            for (final collision in result.nameCollisions.entries)
              '${collision.key} (${collision.value.join(', ')})',
          ].join(', '),
        ),
      );
    }

    if (result case PhotosetFailure failure) {
      _showMessage(switch (failure.kind) {
        PhotosetFailureKind.sourceEmpty => photosetStrings(
          widget.state.controller.release.releaseType,
          l10n,
        ).pickHint,
        PhotosetFailureKind.sourceNotFound => l10n.photosetSourceNotFound,
        PhotosetFailureKind.sourceNotReadable => l10n.photosetSourceNotReadable,
      });
    }

    if (!mounted) return;
    setState(() => _action = _Action.none);
  }

  Future<void> _pick(AppLocalizations l10n) async {
    final scan = _lastScan;

    if (scan == null) {
      return;
    }

    setState(() => _action = _Action.pick);

    final result = await widget.state.controller.pick(
      scan,
      onProgress: (progress) {
        if (!mounted) return;

        setState(() {
          _pickProgress = progress;

          // Whatever the run has written is shown as it is written, because a
          // photo that could not be copied must not hide the ones that were. The
          // block records what the run wrote — the cache is emptied for the path
          // it wrote and the generation the pictures are keyed with moves
          // (`AGENTS.md` §5) — and tells the editor, because the area that draws
          // them is another widget and builds only when the editor does.
          if (progress.record != null) {
            widget.state.recordCopy(progress.record!);
            widget.onRunWritten();
          }
        });
      },
    );

    if (!mounted) return;

    // The run is over, so what the two widgets read is the manifest again.
    widget.state.endRun();

    if (result.notCopied.isNotEmpty) {
      _showMessage(l10n.photosetNotCopied(result.notCopied.join(', ')));
    }

    // A set with no photos contributes nothing to the pick, so it is reported
    // rather than left out.
    if (result.emptySets.isNotEmpty) {
      _showMessage(l10n.photosetEmptySets(result.emptySets.join(', ')));
    }

    if (!mounted) return;

    widget.onRunWritten();

    setState(() => _action = _Action.none);
  }

  Widget _button(
    String keyName,
    String label,
    bool enabled,
    _Action running,
    void Function() onPressed,
  ) {
    final theme = Theme.of(context);

    return FilledButton(
      key: ValueKey(keyName),
      onPressed: enabled && _action == _Action.none ? onPressed : null,
      child: _action == running
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onPrimary,
              ),
            )
          : Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final state = widget.state;
    final strings = photosetStrings(state.controller.release.releaseType, l10n);
    final groups = photosetGroups(state, state.controller.photosets());
    // Only the pack puts its pictures in another widget, because only the pack has
    // columns to put them in (`ai/picking.md` §7).
    final isPack =
        state.controller.release.releaseType == ReleaseType.photosetPack;

    // The rows for the runs going now. A type whose item is the folder it picked
    // has one item, so a row counting items says nothing there and the strings
    // resolve to null for it: only the pick's row is drawn for that type
    // (`ai/picking.md` §7).
    final progressRows = <Widget>[
      if (_action == _Action.scan && _scanProgress != null)
        ProgressRow(
          key: const ValueKey('photosetScanProgress'),
          done: _scanProgress!.scanned,
          total: _scanProgress!.total,
          count: strings.scanProgress!(
            _scanProgress!.scanned,
            _scanProgress!.total,
          ),
        ),
      if (_action == _Action.pick && _pickProgress != null)
        ProgressRow(
          key: const ValueKey('photosetPickProgress'),
          done: _pickProgress!.done,
          total: _pickProgress!.total,
          count: strings.pickProgress(
            _pickProgress!.done,
            _pickProgress!.total,
          ),
        ),
    ];

    return Column(
      key: const ValueKey('photosetBlock'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The buttons are in the title row because they are the actions of the
        // whole block, not of a row inside it. The folder they read is one of the
        // rows the editor gave the block for the pack, and for a single photoset it
        // is the form row above the form: the block does not repeat it.
        SectionTitle(
          title: strings.blockTitle,
          action: Row(
            children: [
              _button(
                'photosetScanButton',
                l10n.scanPhotosets,
                true,
                _Action.scan,
                () => _scan(l10n),
              ),
              const SizedBox(width: 8),
              // The rule reads the counts, so it cannot run before the scan has.
              _button(
                'photosetPickButton',
                l10n.pickPhotosets,
                _lastScan != null,
                _Action.pick,
                () => _pick(l10n),
              ),
            ],
          ),
        ),
        const SizedBox(height: _titleGap),
        for (final row in progressRows) ...[
          row,
          const SizedBox(height: _rowGap),
        ],
        for (final row in widget.rows) ...[
          const SizedBox(height: _rowGap),
          row,
        ],
        if (groups.isEmpty) ...[
          Text(strings.emptyText, style: theme.textTheme.bodyMedium),
        ] else ...[
          // The header naming the list, drawn only when the list is drawn: a
          // header for a list is not drawn above an empty one. Only a pack has one,
          // because only a pack has a list (`ai/picking.md` §7). The gap above it is
          // the one between the block's parts, the one below it is the one after a
          // title row.
          if (strings.listTitle != null) ...[
            const SizedBox(height: _rowGap),
            SectionTitle(title: strings.listTitle!),
            const SizedBox(height: _titleGap),
          ],
          for (final (index, group) in groups.indexed) ...[
            photosetLine(context, l10n, state, group, index),
            // For a pack the photos of this set are in the photo area, so the
            // block shows the line only.
            if (!isPack) ...[
              const SizedBox(height: _rowGap),
              photosetPhotoGrid(state, [group]),
            ],
          ],
        ],
      ],
    );
  }
}

enum _Action { none, scan, pick }
