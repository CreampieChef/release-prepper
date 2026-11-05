import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../recent_releases/recent_releases_page.dart';
import '../release/clone_wizard.dart';
import '../release/release_editor.dart';
import '../release/release_wizard.dart';
import '../settings/settings_page.dart';
import '../system_check/system_check_page.dart';
import 'tab_manager.dart';

/// The content area: renders the active tab, or the empty state when no tab is
/// open. Keying the content by tab id rebuilds the widget when the tab changes.
class TabView extends StatelessWidget {
  const TabView({super.key});

  Widget _tabPage(AppTab tab, TabManager tabManager) {
    return switch (tab.kind) {
      AppTabKind.releaseWizard => ReleaseWizard(
        onCreated: (release) {
          tabManager.replaceWizardWithEditor(tab.id, release);
        },
      ),
      AppTabKind.cloneWizard => CloneWizard(
        source: tab.release!,
        onCreated: (release) {
          tabManager.replaceWizardWithEditor(tab.id, release);
        },
      ),
      AppTabKind.releaseEditor => ReleaseEditor(
        release: tab.release!,
        tabId: tab.id,
      ),
      AppTabKind.settings => const SettingsPage(),
      AppTabKind.recentReleases => const RecentReleasesPage(),
      AppTabKind.systemCheck => const SystemCheckPage(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tabManager = context.watch<TabManager>();
    final l10n = AppLocalizations.of(context)!;

    if (!tabManager.hasTabs) {
      return Center(child: Text(l10n.allTabsClosed));
    }

    final tab = tabManager.tabs[tabManager.selectedIndex];

    return KeyedSubtree(
      key: ValueKey(tab.id),
      child: _tabPage(tab, tabManager),
    );
  }
}
