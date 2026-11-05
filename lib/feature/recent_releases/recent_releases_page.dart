import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../main_menu_controller.dart';
import '../release/release_open_flow.dart';
import '../settings/settings_controller.dart';
import 'recent_releases.dart';
import 'recent_releases_controller.dart';

/// The columns the table has. The order here is the order they are drawn in;
/// the order the rows come in is the sort, which is separate.
enum _RecentColumn {
  name,
  path,
  source,
  createdDate,
  lastEditDate,
  tracker,
  releaseType,
}

/// The Recent releases tab: the table of the releases the app has opened
/// (`ai/recent_releases.md` §4).
///
/// The widget owns the layout and the widget state — which column the table is
/// ordered by and in which direction; the controller owns the list and the side
/// effects. The order the file lists is data (`ai/release_structure.md` §4), so
/// a sort changes what this page shows and nothing on disk.
///
/// The rows are the index plus the folders in the default release directory
/// (`ai/recent_releases.md` §5). A folder the scan found shows the name and the
/// path and nothing else, because nothing about it was read, and it is never
/// marked as unavailable: the scan only lists folders that have the manifest.
///
/// Clicking a row opens the release through the shared open flow, so the error
/// popup is the same one the menu item and Ctrl+O show.
class RecentReleasesPage extends StatefulWidget {
  const RecentReleasesPage({super.key});

  @override
  State<RecentReleasesPage> createState() => _RecentReleasesPageState();
}

class _RecentReleasesPageState extends State<RecentReleasesPage> {
  late final RecentReleasesController _controller;

  /// Which column the table is ordered by. Default: last edit date, newest
  /// first.
  _RecentColumn _column = _RecentColumn.lastEditDate;

  bool _descending = true;

  static const _columns = [
    _RecentColumn.name,
    _RecentColumn.path,
    _RecentColumn.source,
    _RecentColumn.createdDate,
    _RecentColumn.lastEditDate,
    _RecentColumn.tracker,
    _RecentColumn.releaseType,
  ];

  // The paths are the long values in the table, so they get the widest cells; a
  // date is a fixed width and a name is shorter than the path it came from.
  int _flex(_RecentColumn column) => switch (column) {
    _RecentColumn.path => 4,
    _RecentColumn.source => 4,
    _RecentColumn.name => 3,
    _ => 2,
  };

  @override
  void initState() {
    super.initState();

    _controller = context.read<RecentReleasesController>();

    // Both are asked for once when the page opens: the marker for a row whose
    // folder is gone, and the folders in the default release directory
    // (`ai/recent_releases.md` §5). The directory is read here and passed to
    // the call, because a controller builds no dependency of its own (rule 4),
    // the same way the open flow and the wizard get it.
    //
    // Deferred to a microtask, because a controller that notifies while the
    // frame that created it is still building marks the provider scope as
    // needing build while the framework is locked — which is what happens when
    // the list is empty and the check finishes without an await.
    scheduleMicrotask(() {
      unawaited(_controller.checkAvailability());
      unawaited(
        _controller.scanDefaultDirectory(
          context.read<SettingsController>().defaultReleaseDirectory,
        ),
      );
    });
  }

  /// Clicking a header sorts by that column; clicking it again reverses the
  /// direction. A column that was not the sorted one starts in its natural
  /// direction: newest first for a date, A to Z for a name.
  void _sortBy(_RecentColumn column) {
    setState(() {
      if (_column == column) {
        _descending = !_descending;
        return;
      }

      _column = column;
      _descending = switch (column) {
        _RecentColumn.createdDate || _RecentColumn.lastEditDate => true,
        _ => false,
      };
    });
  }

  /// The comparator for a column. It compares what the column shows, so the
  /// order the user sees is the order the app sorted by — a tracker column
  /// ordered by the display name, not by the technical name behind it.
  int Function(RecentRelease, RecentRelease) _compare(
    _RecentColumn column,
    AppLocalizations l10n,
  ) {
    return switch (column) {
      _RecentColumn.createdDate => (a, b) => compareDates(
        a.createdDate,
        b.createdDate,
      ),
      _RecentColumn.lastEditDate => (a, b) => compareDates(
        a.lastEditDate,
        b.lastEditDate,
      ),
      _ => (a, b) => _cellText(
        a,
        column,
        l10n,
      ).compareTo(_cellText(b, column, l10n)),
    };
  }

  /// What a column shows for one entry. The name is not stored: it is the
  /// directory basename, as it is everywhere else. A date the file does not
  /// have is shown as nothing, because the app writes what the file contains
  /// rather than a date it invented.
  String _cellText(
    RecentRelease entry,
    _RecentColumn column,
    AppLocalizations l10n,
  ) {
    switch (column) {
      case _RecentColumn.name:
        return entry.name;
      case _RecentColumn.path:
        return entry.directoryPath;
      case _RecentColumn.source:
        return entry.source;
      case _RecentColumn.tracker:
        return trackerDisplay(entry.tracker);
      case _RecentColumn.releaseType:
        return releaseTypeDisplay(entry.releaseType, l10n);
      case _RecentColumn.createdDate:
        return entry.createdDate == null
            ? ''
            : _formatDate(entry.createdDate!, l10n);
      case _RecentColumn.lastEditDate:
        return entry.lastEditDate == null
            ? ''
            : _formatDate(entry.lastEditDate!, l10n);
    }
  }

  /// The dates are stored as UTC, and shown in the local time, in the shape the
  /// locale the app is using writes them.
  String _formatDate(DateTime date, AppLocalizations l10n) =>
      DateFormat.yMd(l10n.localeName).add_Hm().format(date.toLocal());

  /// What a column is called. The header names it by the label the app already
  /// uses for that value, so the table and the form above it use the same
  /// words; the path, the source and the two dates are not fields, so those
  /// come from their own keys.
  String _headerText(_RecentColumn column, AppLocalizations l10n) =>
      switch (column) {
        _RecentColumn.name => l10n.releaseNameLabel,
        _RecentColumn.tracker => l10n.trackerLabel,
        _RecentColumn.releaseType => l10n.releaseTypeLabel,
        _RecentColumn.path => l10n.recentPathLabel,
        _RecentColumn.source => l10n.recentSourceLabel,
        _RecentColumn.createdDate => l10n.recentCreatedDateLabel,
        _RecentColumn.lastEditDate => l10n.recentLastEditDateLabel,
      };

  Widget _cell(_RecentColumn column, Widget content) =>
      Expanded(flex: _flex(column), child: content);

  Widget _header(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final heading = theme.textTheme.labelMedium;

    return Column(
      key: const ValueKey('recentReleasesHeader'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final column in _columns)
              Expanded(
                flex: _flex(column),
                child: InkWell(
                  key: ValueKey('recentSort-${column.name}'),
                  onTap: () => _sortBy(column),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(_headerText(column, l10n), style: heading),
                        if (column == _column) ...[
                          const SizedBox(width: 4),
                          Icon(
                            _descending
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            size: 14,
                            color: heading?.color,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  /// One entry as a row. Clicking it opens the release, or shows the error
  /// popup when the folder is not there any more.
  ///
  /// Every other row is tinted, because a table read as bands of text is
  /// followed with the eye, and the tint is on a `Material` for the same reason
  /// the Video pack table's is: the hover highlight is painted on the canvas of
  /// the nearest `Material` ancestor. The parity is the position in the order
  /// the table shows, so a row keeps its band with the rows around it.
  Widget _row(
    RecentRelease entry,
    int index,
    AppLocalizations l10n,
    MainMenuController menu,
  ) {
    final theme = Theme.of(context);
    final unavailable = _controller.unavailablePaths.contains(
      entry.directoryPath,
    );

    // A row whose folder is gone is drawn with the values the index holds, in
    // the dimmed colour, with the reason next to the name: the folder may come
    // back, and a row that disappears because of one failed read is a row the
    // user did not ask to lose.
    final style = unavailable
        ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)
        : theme.textTheme.bodyMedium;

    return Material(
      color: index.isOdd
          ? theme.colorScheme.surfaceContainerHigh
          : Colors.transparent,
      child: InkWell(
        key: ValueKey('recentRow-${entry.directoryPath}'),
        onTap: () => openReleaseFromPathWithErrors(
          context,
          menu,
          l10n,
          entry.directoryPath,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final column in _columns)
                _cell(
                  column,
                  _cellContent(column, entry, l10n, style, unavailable),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cellContent(
    _RecentColumn column,
    RecentRelease entry,
    AppLocalizations l10n,
    TextStyle? style,
    bool unavailable,
  ) {
    final text = Text(_cellText(entry, column, l10n), style: style);

    if (column != _RecentColumn.name || !unavailable) {
      return text;
    }

    return Row(
      children: [
        text,
        const SizedBox(width: 4),
        Tooltip(
          key: ValueKey('recentUnavailable-${entry.directoryPath}'),
          message: l10n.recentFolderUnavailable,
          child: Icon(
            Icons.error_outline,
            size: 16,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RecentReleasesController>();
    final l10n = AppLocalizations.of(context)!;
    final menu = context.read<MainMenuController>();

    final entries = sortEntries(
      controller.rows,
      compare: _compare(_column, l10n),
      descending: _descending,
    );

    // The page is the content of a tab, so it keeps a margin from the edges.
    // The rows are the part that can outgrow the tab — the list has no cap for
    // the scanned folders — so they scroll, and only the rows scroll: the
    // header is the sort control, so it stays fixed above them. The write
    // failure is a page-level message, so it stays outside the scroll and is
    // always visible.
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(l10n),
          Expanded(
            child: ListView(
              children: [
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(l10n.noRecentReleases),
                  )
                else
                  for (final (index, entry) in entries.indexed)
                    _row(entry, index, l10n, menu),
              ],
            ),
          ),
          if (controller.writeFailed) ...[
            const SizedBox(height: 8),
            Text(
              l10n.recentWriteFailed,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
