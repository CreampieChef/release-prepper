import 'recent_releases/recent_releases_controller.dart';
import 'release/release_open_controller.dart';
import 'release/release_type.dart';
import 'tab/tab_close_controller.dart';
import 'tab/tab_manager.dart';

/// Menu commands. It does not own the tab collection; it asks `TabManager` to
/// change it, and it delegates the save side effect to `TabCloseController`,
/// which owns it.
class MainMenuController {
  MainMenuController({
    required this.tabManager,
    required this.releaseOpenController,
    required this.tabCloseController,
    required this.recentReleases,
  });

  final TabManager tabManager;
  final ReleaseOpenController releaseOpenController;
  final TabCloseController tabCloseController;
  final RecentReleasesController recentReleases;

  void onNewRelease() {
    tabManager.addNewReleaseWizard();
  }

  /// Opens a clone wizard tab for the release the selected editor tab shows.
  /// Only a single-video release is cloned, so the menu item is disabled for
  /// any other tab; the same check is here so a call from anywhere cannot open
  /// a wizard for a release the feature does not cover. Unlike the app-level
  /// tabs, a second clone tab is a new tab rather than a selection, because the
  /// user clones the same source once per resolution.
  void onCloneRelease() {
    if (!tabManager.hasTabs) {
      return;
    }

    final tab = tabManager.tabs[tabManager.selectedIndex];
    if (tab.kind != AppTabKind.releaseEditor) {
      return;
    }

    final source = tab.release!;
    if (source.releaseType != ReleaseType.singleVideo) {
      return;
    }

    tabManager.addCloneWizard(source);
  }

  /// Opens the Settings tab, or selects it when it is already open.
  void onSettings() {
    tabManager.addSettings();
  }

  /// Opens the Recent releases tab, or selects it when it is already open.
  void onRecentReleases() {
    tabManager.addRecentReleases();
  }

  /// Opens the System Check tab, or selects it when it is already open.
  void onSystemCheck() {
    tabManager.addSystemCheck();
  }

  /// Saves the selected tab's release through the same path the close popup
  /// uses. Returns false when there is nothing to save or the manifest could
  /// not be written; the widget turns that into a localized message. Only
  /// editor tabs have a release, so a wizard tab returns false.
  Future<bool> onSave() async {
    if (!tabManager.hasTabs) {
      return false;
    }

    return tabCloseController.saveTab(
      tabManager.tabs[tabManager.selectedIndex],
    );
  }

  Future<ReleaseOpenResult> onOpenRelease({
    required String dialogTitle,
    required String initialDirectory,
  }) async => _recordAndOpen(
    await releaseOpenController.openRelease(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
    ),
  );

  /// The same for a folder the recent list names: a row click is the same
  /// command as the menu item, with the picker skipped.
  Future<ReleaseOpenResult> onOpenPath(String directoryPath) async =>
      _recordAndOpen(await releaseOpenController.openPath(directoryPath));

  /// A release the app has read is an entry in the recent list, and the tab it
  /// opens is the tab the row names. Recording is the recent controller's side
  /// effect and the tab is `TabManager`'s (rule 7); this only puts them in the
  /// order the user sees: the list first, then the tab.
  Future<ReleaseOpenResult> _recordAndOpen(ReleaseOpenResult result) async {
    if (result is ReleaseOpenSuccess) {
      await recentReleases.record(result.release);
      tabManager.addReleaseEditor(result.release);
    }

    return result;
  }
}
