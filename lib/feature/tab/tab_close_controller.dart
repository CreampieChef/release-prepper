import '../recent_releases/recent_releases_controller.dart';
import '../release/release_store.dart';
import 'tab_manager.dart';

/// Side effects for closing a tab: show it, save its release, or close it. It
/// owns no `Listenable` (rule 3) and takes no `BuildContext` (rule 13); the
/// shared close flow in `tab_close.dart` shows the popup and decides which of
/// these to call.
class TabCloseController {
  TabCloseController({
    required this.store,
    required this.tabManager,
    required this.recentReleases,
  });

  final ReleaseStore store;
  final TabManager tabManager;
  final RecentReleasesController recentReleases;

  /// Makes `tab` the selected one, so a popup that names a tab names the tab
  /// the user is looking at. Which tab is selected belongs to `TabManager`
  /// (rule 7).
  void selectTab(AppTab tab) {
    final index = tabManager.tabs.indexOf(tab);

    if (index == -1) {
      return;
    }

    tabManager.selectTab(index);
  }

  /// Writes the tab's release to `release.json` and clears the dirty flag.
  /// Returns false when the manifest could not be written; the flow turns that
  /// into a localized message. Only editor tabs have a release, so a wizard tab
  /// returns false.
  Future<bool> saveTab(AppTab tab) async {
    final release = tab.release;

    if (release == null) {
      return false;
    }

    try {
      await store.save(release);
    } catch (_) {
      return false;
    }

    // The manifest now has the date this write stamped, so the recent entry is
    // refreshed with it (`ai/recent_releases.md` §3). A failed write is not
    // recorded: the date the file does not have is not a date the list should
    // claim.
    await recentReleases.record(release);

    tabManager.setUnsavedChanges(tab.id, false);

    return true;
  }

  /// Removes the tab from the collection through `TabManager`, the only owner
  /// of tab state (rule 7).
  void closeTab(AppTab tab) {
    final index = tabManager.tabs.indexOf(tab);

    if (index == -1) {
      return;
    }

    tabManager.closeTabAt(index);
  }
}
