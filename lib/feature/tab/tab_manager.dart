import 'package:flutter/foundation.dart';

import '../release/release.dart';

enum AppTabKind {
  releaseWizard,
  cloneWizard,
  releaseEditor,
  settings,
  recentReleases,
  systemCheck,
}

class AppTab {
  AppTab._({required this.id, required this.kind, this.release});

  factory AppTab.releaseWizard({required String id}) {
    return AppTab._(id: id, kind: AppTabKind.releaseWizard);
  }

  factory AppTab.cloneWizard({required String id, required Release source}) {
    return AppTab._(id: id, kind: AppTabKind.cloneWizard, release: source);
  }

  factory AppTab.releaseEditor({required String id, required Release release}) {
    return AppTab._(id: id, kind: AppTabKind.releaseEditor, release: release);
  }

  factory AppTab.settings({required String id}) {
    return AppTab._(id: id, kind: AppTabKind.settings);
  }

  factory AppTab.recentReleases({required String id}) {
    return AppTab._(id: id, kind: AppTabKind.recentReleases);
  }

  factory AppTab.systemCheck({required String id}) {
    return AppTab._(id: id, kind: AppTabKind.systemCheck);
  }

  final String id;
  final AppTabKind kind;

  /// Non-null for release editor tabs.
  final Release? release;

  /// Set by the editor when a field changes and cleared when it saves. The tab
  /// strip shows a dot for it.
  bool hasUnsavedChanges = false;
}

class TabManager extends ChangeNotifier {
  final List<AppTab> _tabs = [];
  int _selectedIndex = -1;
  int _tabCounter = 0;

  List<AppTab> get tabs => List.unmodifiable(_tabs);
  int get selectedIndex => _selectedIndex;
  bool get hasTabs => _tabs.isNotEmpty;

  String _nextTabId() => 'tab-${++_tabCounter}';

  String addNewReleaseWizard() {
    final id = _nextTabId();

    _tabs.add(AppTab.releaseWizard(id: id));
    _selectedIndex = _tabs.length - 1;
    notifyListeners();

    return id;
  }

  /// Adds the Settings tab, or selects it when it is already open. Settings are
  /// app-level, so a second tab would show the same thing twice; this is the
  /// one place that decides it.
  String addSettings() {
    final index = _tabs.indexWhere((tab) => tab.kind == AppTabKind.settings);

    if (index != -1) {
      selectTab(index);
      return _tabs[index].id;
    }

    final id = _nextTabId();

    _tabs.add(AppTab.settings(id: id));
    _selectedIndex = _tabs.length - 1;
    notifyListeners();

    return id;
  }

  /// Adds the Recent releases tab, or selects it when it is already open. The
  /// list is app-level, so a second tab would show the same table twice; this
  /// is the one place that decides it, as with the settings tab
  /// (`ai/recent_releases.md` §1).
  String addRecentReleases() {
    final index = _tabs.indexWhere(
      (tab) => tab.kind == AppTabKind.recentReleases,
    );

    if (index != -1) {
      selectTab(index);
      return _tabs[index].id;
    }

    final id = _nextTabId();

    _tabs.add(AppTab.recentReleases(id: id));
    _selectedIndex = _tabs.length - 1;
    notifyListeners();

    return id;
  }

  /// Adds the System Check tab, or selects it when it is already open. The
  /// check is app-level, so a second tab would show the same list twice; this
  /// is the one place that decides it, as with the settings tab.
  String addSystemCheck() {
    final index = _tabs.indexWhere((tab) => tab.kind == AppTabKind.systemCheck);

    if (index != -1) {
      selectTab(index);
      return _tabs[index].id;
    }

    final id = _nextTabId();

    _tabs.add(AppTab.systemCheck(id: id));
    _selectedIndex = _tabs.length - 1;
    notifyListeners();

    return id;
  }

  /// Adds a clone wizard tab for a source release. Unlike the app-level tabs,
  /// several clone tabs may be open at once, and two of them may clone the
  /// same release: the user is making one release per resolution, so the same
  /// source is cloned more than once.
  String addCloneWizard(Release source) {
    final id = _nextTabId();

    _tabs.add(AppTab.cloneWizard(id: id, source: source));
    _selectedIndex = _tabs.length - 1;
    notifyListeners();

    return id;
  }

  /// Replaces a wizard tab with its editor after successful creation, for both
  /// the new-release wizard and the clone wizard.
  void replaceWizardWithEditor(String tabId, Release release) {
    final index = _tabs.indexWhere((tab) => tab.id == tabId);

    // The wizard may have been closed while creation was in progress.
    if (index == -1) {
      return;
    }

    final kind = _tabs[index].kind;
    if (kind != AppTabKind.releaseWizard && kind != AppTabKind.cloneWizard) {
      return;
    }

    _tabs[index] = AppTab.releaseEditor(id: tabId, release: release);
    _selectedIndex = index;
    notifyListeners();
  }

  /// Adds an editor tab, for example after opening a release from disk, or
  /// selects the one already open for that release. One tab per release
  /// directory: two tabs for the same folder would show the same release twice,
  /// and the recent list has one row for it (`ai/recent_releases.md` §6).
  String addReleaseEditor(Release release) {
    final index = _tabs.indexWhere(
      (tab) =>
          tab.kind == AppTabKind.releaseEditor &&
          tab.release!.directoryPath == release.directoryPath,
    );

    if (index != -1) {
      selectTab(index);
      return _tabs[index].id;
    }

    final id = _nextTabId();

    _tabs.add(AppTab.releaseEditor(id: id, release: release));
    _selectedIndex = _tabs.length - 1;
    notifyListeners();

    return id;
  }

  /// Marks a tab as having unsaved editor changes. The tab is the only place
  /// that state lives, so the editor reports to it instead of holding its own.
  void setUnsavedChanges(String tabId, bool value) {
    final index = _tabs.indexWhere((tab) => tab.id == tabId);

    if (index == -1 || _tabs[index].hasUnsavedChanges == value) {
      return;
    }

    _tabs[index].hasUnsavedChanges = value;
    notifyListeners();
  }

  void selectTab(int index) {
    if (index < 0 || index >= _tabs.length || index == _selectedIndex) {
      return;
    }

    _selectedIndex = index;
    notifyListeners();
  }

  void closeTabAt(int index) {
    if (index < 0 || index >= _tabs.length) return;

    _tabs.removeAt(index);

    if (_tabs.isEmpty) {
      _selectedIndex = -1;
    } else if (index < _selectedIndex) {
      _selectedIndex--;
    } else if (index == _selectedIndex) {
      _selectedIndex = index.clamp(0, _tabs.length - 1).toInt();
    }

    notifyListeners();
  }
}
