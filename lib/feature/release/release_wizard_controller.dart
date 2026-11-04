import 'package:flutter/foundation.dart';

import '../recent_releases/recent_releases_controller.dart';
import 'release.dart';
import 'release_store.dart';
import 'release_type.dart';
import 'tracker.dart';

enum ReleaseNameValidationError { required, invalid }

enum ReleaseCreationFailure { alreadyExists, failed }

final _invalidFilenameCharacters = RegExp(r'[\x00-\x1F<>:"/\\|?*]');

final _reservedWindowsName = RegExp(
  r'^(CON|PRN|AUX|NUL|COM[0-9¹²³]|LPT[0-9¹²³])(?:\s*\..*)?$',
  caseSensitive: false,
);

ReleaseNameValidationError? validateReleaseName(String? value) {
  if (value == null || value.trim().isEmpty) {
    return ReleaseNameValidationError.required;
  }

  if (_invalidFilenameCharacters.hasMatch(value) ||
      value == '.' ||
      value == '..' ||
      RegExp(r'[ .]$').hasMatch(value) ||
      _reservedWindowsName.hasMatch(value)) {
    return ReleaseNameValidationError.invalid;
  }

  return null;
}

class ReleaseWizardController extends ChangeNotifier {
  ReleaseWizardController({
    required this.store,
    required this.defaultReleaseDirectory,
    required this.recentReleases,
  });

  final ReleaseStore store;

  /// The directory the form is prefilled with and the folder picker starts in.
  /// It comes from the settings, which are already loaded, so there is nothing
  /// to wait for here.
  final String defaultReleaseDirectory;

  /// Recording the created release is its own feature's side effect, so it is
  /// called here rather than owned here (`ai/recent_releases.md` §3).
  final RecentReleasesController recentReleases;

  bool _disposed = false;

  bool isCreating = false;
  ReleaseCreationFailure? creationFailure;

  Future<Release?> create({
    required String savePath,
    required String name,
    required Tracker tracker,
    required ReleaseType releaseType,
  }) async {
    creationFailure = null;
    isCreating = true;
    _notifyIfAlive();

    try {
      final release = await store.create(
        savePath: savePath,
        name: name,
        tracker: tracker,
        releaseType: releaseType,
      );

      // A release the app created is an entry in the recent list, the same as
      // one it opened (`ai/recent_releases.md` §3). Only a successful create is
      // recorded.
      await recentReleases.record(release);

      return release;
    } on ReleaseAlreadyExistsException {
      creationFailure = ReleaseCreationFailure.alreadyExists;
      return null;
    } catch (_) {
      creationFailure = ReleaseCreationFailure.failed;
      return null;
    } finally {
      isCreating = false;
      _notifyIfAlive();
    }
  }

  void _notifyIfAlive() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
