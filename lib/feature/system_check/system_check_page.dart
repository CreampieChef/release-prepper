import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../service/native_tools/tool_locator.dart';
import 'system_check_controller.dart';

/// The System Check tab: its title, then one row per tool the app calls,
/// showing the version the tool reported or the reason it could not be run.
///
/// The check runs once when the tab opens, because a tool does not become
/// installed while the app is open (`ai/doc.md` §2); reopening the tab runs it
/// again. The calls are made at the same time and each result reaches the page
/// as it arrives, so a tool that hangs does not hold up the rows that already
/// have an answer. The results are widget state; the controller owns the tool
/// list and the calls, and the widget maps a result to localized text and to a
/// status icon (rule 13). The page holds nothing the user edits, so it has no
/// dirty flag, is not part of Ctrl+S, and closes without the unsaved-changes
/// popup.
class SystemCheckPage extends StatefulWidget {
  const SystemCheckPage({super.key});

  @override
  State<SystemCheckPage> createState() => _SystemCheckPageState();
}

class _SystemCheckPageState extends State<SystemCheckPage> {
  /// The block the page draws is capped at this width and centred in the tab,
  /// so a wide window does not stretch the table across the whole screen. Only
  /// the block is centred: the text inside it is left-aligned, as the text of
  /// every other page is.
  static const _maxWidth = 1200.0;

  /// The page is a two-column list: the tool name, then what it reported. The
  /// name column is a fixed width rather than a share of the page, because the
  /// names are short and the same in every row; a flex column would make them
  /// take a quarter of a wide window and push the values away from the names.
  static const _toolColumnWidth = 120.0;

  /// The column the status icon is drawn in: the icon plus the gap to the name.
  /// The header and the rows share it, so the names start at the same line.
  static const _iconColumnWidth = 22.0;

  static const _iconSize = 16.0;

  /// The height of one line of the tool name (`labelMedium`), so the mark in
  /// the icon column sits on the same line as the name rather than above it.
  static const _markCellHeight = 16.0;

  late final SystemCheckController _controller;

  /// What has come back so far, keyed by the tool name the row shows. A tool
  /// with no entry is a tool whose call has not come back, which is the row's
  /// spinner. Keyed by name rather than by position, because the results arrive
  /// in the order the calls finish in, not the order the rows are drawn in.
  final Map<String, SystemCheckResult> _results = {};

  @override
  void initState() {
    super.initState();

    _controller = context.read<SystemCheckController>();

    unawaited(_run());
  }

  Future<void> _run() async {
    await _controller.check(
      onResult: (result) {
        if (!mounted) return;

        setState(() => _results[result.tool.name] = result);
      },
    );
  }

  /// A row with no result yet has nothing to colour.
  bool _isError(SystemCheckResult? result) =>
      result != null &&
      (result is SystemCheckNotPresent ||
          result is SystemCheckRunFailed ||
          result is SystemCheckRunTimeout ||
          result is SystemCheckNoOutput);

  /// The state the row is in, as an icon: a tool that reported a version is a
  /// check, and every reason is the same mark. The text already says which
  /// reason it was, so the icon is only there to make the state readable down
  /// the column. A row whose check has not come back yet has no state to show,
  /// and the spinner in the same column is what says so.
  IconData? _icon(SystemCheckResult? result) => result == null
      ? null
      : _isError(result)
      ? Icons.error_outline
      : Icons.check_circle_outline;

  /// The mark the icon column holds: the status icon, or the spinner while the
  /// check is still running. Both are drawn in the same cell, so a row keeps
  /// its shape while it is waiting and the mark stays on the line of the tool
  /// name.
  Widget _mark(SystemCheckResult? result, ThemeData theme) => SizedBox(
    width: _iconColumnWidth,
    height: _markCellHeight,
    child: result == null
        ? const Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : Center(
            child: Icon(
              _icon(result)!,
              size: _iconSize,
              color: _isError(result)
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          ),
  );

  String _value(SystemCheckResult result, AppLocalizations l10n) =>
      switch (result) {
        SystemCheckFound(version: final version) => version,
        SystemCheckNotPresent(tool: final tool) => l10n.systemCheckToolNotFound(
          tool.name,
        ),
        SystemCheckRunFailed(tool: final tool, exitCode: final exitCode) =>
          l10n.systemCheckRunFailed(tool.name, exitCode),
        SystemCheckRunTimeout(tool: final tool) => l10n.systemCheckRunTimeout(
          tool.name,
        ),
        SystemCheckNoOutput(tool: final tool) => l10n.systemCheckNoOutput(
          tool.name,
        ),
      };

  /// The title, drawn like the release name in the editor (`headlineMedium`)
  /// rather than through `SectionTitle`: `SectionTitle` is the row every
  /// section titles itself with, and its style is `titleMedium`. This is a page
  /// title, the same kind of thing the release name is, so the page owns it,
  /// and it is centred because the block it belongs to is centred.
  Widget _title(AppLocalizations l10n) => Text(
    l10n.systemCheck,
    style: Theme.of(context).textTheme.headlineMedium,
    textAlign: TextAlign.center,
  );

  /// The header of the two columns. The icon column has no label, because the
  /// icons are not a column of information; the two labels are the columns the
  /// rows have.
  Widget _header(AppLocalizations l10n) {
    final theme = Theme.of(context);

    return Padding(
      key: const ValueKey('systemCheckHeader'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: _iconColumnWidth),
          SizedBox(
            width: _toolColumnWidth,
            child: Text(
              l10n.systemCheckToolLabel,
              style: theme.textTheme.labelMedium,
            ),
          ),
          Expanded(
            child: Text(
              l10n.systemCheckResultLabel,
              style: theme.textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    NativeTool tool,
    SystemCheckResult? result,
    int index,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);

    // A row is drawn as a row of a list, the same way the recent table is: the
    // odd rows take the container colour so the list reads as one block rather
    // than as separate lines. Nothing here is clickable, so there is no
    // InkWell.
    return Material(
      color: index.isOdd
          ? theme.colorScheme.surfaceContainerHigh
          : Colors.transparent,
      child: Padding(
        key: ValueKey('systemCheckRow-${tool.name}'),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _mark(result, theme),
            SizedBox(
              width: _toolColumnWidth,
              child: Text(tool.name, style: theme.textTheme.labelMedium),
            ),
            Expanded(
              child: result == null
                  ? const SizedBox.shrink()
                  : Text(
                      _value(result, l10n),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _isError(result)
                            ? theme.colorScheme.error
                            : null,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // The page is the content of a tab, so it keeps a margin from the edges,
    // as the other pages do. The list is the tools the app calls, so it is
    // short and does not scroll. `topCenter` rather than `center`: the block is
    // centred across the width, but it still starts at the top of the tab,
    // because a four-row table floating in the middle of a tall window is not
    // what a page looks like.
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 12, right: 12),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(l10n),
              const SizedBox(height: 12),
              _header(l10n),
              for (final (index, (tool, _)) in _controller.calls().indexed)
                _row(tool, _results[tool.name], index, l10n),
            ],
          ),
        ),
      ),
    );
  }
}
