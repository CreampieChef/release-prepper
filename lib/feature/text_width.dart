import 'package:flutter/material.dart';

/// The width a string needs at a style. `TextPainter` is the only way to ask,
/// and the styles are the ones the theme gives the widgets, so the answer is
/// the same as what the widget draws in the language the app is in.
///
/// A row decides where it stops fitting from what its controls need rather than
/// from a page breakpoint (`ai/doc.md` §3), and the two widgets that make that
/// decision — the settings page's login row and the editor's heading — measure
/// with this, so the answer is one function rather than a copy in each.
double measuredTextWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  );

  painter.layout();

  return painter.width;
}
