import 'package:flutter/material.dart';

/// The mark a System Check row begins with: the status icon for a result that has
/// come back, or the spinner for one that has not. The tool rows and the
/// credential store section draw it, so the mark is one shape rather than the
/// same numbers written out in two files.
///
/// Which result is an error is decided by the caller, because the two kinds of
/// check have different results: a tool row knows the ways a tool run can end,
/// and the section knows whether the store answered. The mark shows only the
/// state, so it is given the flag rather than the result, which is the part rule
/// 13 leaves with the widget.
class StatusMark extends StatelessWidget {
  const StatusMark({required this.isError, required this.pending, super.key});

  /// The cell the mark is drawn in, which is the icon plus the gap to the name.
  /// The header and the rows share it, so the names start at the same line, and
  /// the section starts at that line too.
  static const cellWidth = 22.0;

  /// The height of one line of the tool name (`labelMedium`), so the mark sits on
  /// the same line as the name rather than above it.
  static const cellHeight = 16.0;

  static const iconSize = 16.0;

  final bool isError;

  /// Whether the check has not answered yet. A row with no result has nothing to
  /// colour, so the spinner is what says so, and it is drawn in the same cell as
  /// the icon so the row keeps its shape while it waits.
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: cellWidth,
      height: cellHeight,
      child: Center(
        child: pending
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                size: iconSize,
                color: isError
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
      ),
    );
  }
}
