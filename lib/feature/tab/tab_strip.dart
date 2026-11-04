import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../tracker_icon.dart';
import 'tab_close.dart';
import 'tab_close_controller.dart';
import 'tab_manager.dart';

/// The browser-style tab strip. It renders `TabManager` state and dispatches
/// selection and close; it owns no tab state of its own.
class TabStrip extends StatelessWidget {
  const TabStrip({super.key});

  Widget _tabIcon(AppTab tab) {
    // A wizard tab has no release yet — the clone wizard has a source, but the
    // release it will make does not exist — so there is no tracker to draw.
    return switch (tab.kind) {
      AppTabKind.releaseWizard => const Icon(Icons.new_releases, size: 16),
      AppTabKind.cloneWizard => const Icon(Icons.content_copy, size: 16),
      AppTabKind.releaseEditor => TrackerIcon(
        tracker: tab.release!.tracker,
        size: 16,
      ),
      AppTabKind.settings => const Icon(Icons.settings, size: 16),
      AppTabKind.recentReleases => const Icon(Icons.schedule, size: 16),
      AppTabKind.systemCheck => const Icon(Icons.monitor_heart, size: 16),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tabManager = context.watch<TabManager>();

    if (!tabManager.hasTabs) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final controller = context.read<TabCloseController>();
    final tabs = tabManager.tabs;
    final selectedIndex = tabManager.selectedIndex;

    return Container(
      height: 44,
      color: const Color(0xFFDEE1E6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final tab = tabs[index];

          return Align(
            alignment: Alignment.bottomCenter,
            child: _TabCard(
              title: tabTitle(tab, l10n),
              icon: _tabIcon(tab),
              hasUnsavedChanges: tab.hasUnsavedChanges,
              isSelected: index == selectedIndex,
              onTap: () => tabManager.selectTab(index),
              onClose: () =>
                  closeTabWithConfirmation(context, controller, tab, l10n),
            ),
          );
        },
      ),
    );
  }
}

/// One tab in the strip. Like a browser tab: the primary button selects it, the
/// middle button closes it.
class _TabCard extends StatefulWidget {
  const _TabCard({
    required this.title,
    required this.icon,
    required this.hasUnsavedChanges,
    required this.isSelected,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final Widget icon;
  final bool hasUnsavedChanges;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_TabCard> createState() => _TabCardState();
}

class _TabCardState extends State<_TabCard> {
  /// The unselected card color.
  static const _cardColor = Color(0xFFE8EAED);

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // The hover tint is painted from this state rather than by `InkWell`,
    // because `InkWell` resolves `hoverColor` once — when the highlight is
    // created on hover-enter — and keeps that color until the pointer leaves. A
    // card that is hovered and then clicked would keep the tint it had before
    // the click, which is the state the user sees as the highlight not going
    // away. Painting it from the current state is what makes it disappear on
    // the click.
    final base = widget.isSelected ? Colors.white : _cardColor;
    final color = _hovered && !widget.isSelected
        ? Color.alphaBlend(theme.hoverColor, base)
        : base;

    return Listener(
      // Gesture callbacks never report which button was used: a tap recognizer
      // routes the middle button to its own tertiary callbacks, which `InkWell`
      // does not have. So the middle click comes from the pointer event, read
      // on the press, where `buttons` reports the button that was pressed.
      onPointerDown: (event) {
        if (event.buttons == kMiddleMouseButton) {
          widget.onClose();
        }
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Padding(
          padding: const EdgeInsets.only(right: 2),
          child: SizedBox(
            width: 190,
            height: widget.isSelected ? 44 : 38,
            child: Material(
              color: color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
              child: InkWell(
                onTap: widget.onTap,
                // No press ripple: a browser-style tab should not animate on
                // press. No hover highlight either: the tint is painted above,
                // from the state, so that it follows the selection instead of
                // the color resolved when the pointer first entered.
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 6),
                  child: Row(
                    children: [
                      widget.icon,
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          widget.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      if (widget.hasUnsavedChanges) ...[
                        Tooltip(
                          message: l10n.unsavedChanges,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      IconButton(
                        tooltip: l10n.closeTab(widget.title),
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.close),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
