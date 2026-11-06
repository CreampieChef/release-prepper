import 'dart:ui' show clampDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard navigation for the content area: PageUp and PageDown move by one
/// page, which is the height the page is drawn in, and Home and End go to its
/// top and its bottom.
///
/// The move is animated, which is what a browser's smooth scrolling reads like:
/// a short acceleration and a gentle stop. A press while the page is still
/// moving starts from wherever the page is, so pressing the key several times
/// reads as one continuous move, and the target is clamped to what the page
/// has, so a press near an end stops at the end.
///
/// It owns the `ScrollController` the page resolves to, and it can only move a
/// page that resolves to it. `PrimaryScrollController` is inherited by a scroll
/// view on the mobile platforms by default; this is a desktop app, so the
/// inheritance is asked for on every platform here — without that the pages
/// keep their own controllers and these keys have no page to move. Only the
/// active tab is built, so one position is attached at a time and there is
/// nothing to choose between. A route gives its own scroll view its own
/// controller, so a popup is not moved by these keys.
///
/// The widget declines the keys when a text input is focused, because those
/// keys belong to the field: Home and End move the caret, and PageUp and
/// PageDown scroll the field. Declining is what leaves them to it — nothing
/// here claims them, so the focused field answers them as it does today. Only
/// the keys without modifiers are handled, for the same reason: Ctrl+Home is
/// the field's key, not a page key.
///
/// It is the last handler in the focus chain for its own subtree, so a widget
/// that handles these keys itself is asked first, and a page with its own key
/// handling is not changed by this. A key only reaches a handler through the
/// focus chain, so the content area is the default focus of its subtree: a page
/// with nothing focusable in it — the recent list, whose rows are `InkWell`s,
/// which are not focusable — has no node below this one to be asked from, so
/// without holding focus itself these keys would reach nothing there. It is not
/// a stop for traversal, so Tab still goes to the first field.
class TabNavigation extends StatefulWidget {
  const TabNavigation({required this.child, super.key});

  final Widget child;

  @override
  State<TabNavigation> createState() => _TabNavigationState();
}

class _TabNavigationState extends State<TabNavigation> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // A `LogicalKeyboardKey` cannot be an element of a constant set, so this is
  // the one the check uses.
  static final Set<LogicalKeyboardKey> _pageKeys = {
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
  };

  // What the move a browser's smooth scrolling makes looks like: it covers the
  // distance in a fraction of a second and stops gently rather than all at
  // once.
  static const Duration _moveDuration = Duration(milliseconds: 200);
  static const Curve _moveCurve = Curves.easeOut;

  /// Whether one of these keys belongs to a focused text input rather than to
  /// the page. The focus chain gives this widget its own node, so the focused
  /// node has to be read from the focus manager — the framework's own, read
  /// only to answer this question (`ai/doc.md` §4) — and that node's context is
  /// inside the field that owns it, which is what makes the field findable from
  /// it.
  bool _fieldHasFocus() {
    final context = FocusManager.instance.primaryFocus?.context;

    if (context == null) {
      return false;
    }

    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (!_pageKeys.contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }

    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }

    if (_fieldHasFocus()) {
      return KeyEventResult.ignored;
    }

    // There is no page to move: the empty state draws no scroll view, so
    // nothing has attached a position.
    if (!_controller.hasClients || !_controller.position.hasPixels) {
      return KeyEventResult.ignored;
    }

    final position = _controller.position;
    final target = clampDouble(
      switch (event.logicalKey) {
        LogicalKeyboardKey.home => position.minScrollExtent,
        LogicalKeyboardKey.end => position.maxScrollExtent,
        LogicalKeyboardKey.pageDown =>
          position.pixels + position.viewportDimension,
        // PageUp: the check above leaves only this one.
        _ => position.pixels - position.viewportDimension,
      },
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    // The handler is synchronous, so the animation is started here and not
    // awaited: answering the key is what starting the move means.
    position.animateTo(target, duration: _moveDuration, curve: _moveCurve);

    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: _handleKey,
      child: PrimaryScrollController(
        controller: _controller,
        automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
        child: widget.child,
      ),
    );
  }
}
