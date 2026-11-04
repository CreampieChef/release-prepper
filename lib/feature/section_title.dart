import 'package:flutter/material.dart';

/// The title row a section begins with: the title at the left, and the action
/// that runs in that section at the right. Shared UI, because every section
/// titles itself the same way and the button that belongs to a section is the
/// same shape in all of them.
///
/// The row is as tall as the action and the title is centred against it: a
/// button is taller than the title text, and the two read as one line only when
/// their centres align. `action` is null where the section has nothing that can
/// run — a section that shows a placeholder instead of its controls shows a
/// title with nothing on the right, which is the same row.
///
/// Presentational only: no state, so no controller. The gap below the row is
/// the caller's, because the widget is the row and not the section.
class SectionTitle extends StatelessWidget {
  const SectionTitle({required this.title, this.action, super.key});

  /// The narrowest the action is drawn at, so a short label ("Scan", "Pick") is
  /// the same shape as a longer one. It is the width of the action, not of each
  /// button inside it: for a section that passes a row of two buttons, a value
  /// above the natural width of the pair leaves the extra space after the last
  /// button rather than widening each one. Change this to see how it reads.
  static const actionMinWidth = 160.0;

  final String title;

  /// The button, or a row of buttons, at the right.
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      if (action != null)
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: actionMinWidth),
          child: action,
        ),
    ],
  );
}
