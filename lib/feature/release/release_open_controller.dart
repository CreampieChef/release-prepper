import 'package:file_picker/file_picker.dart';

import 'release.dart';
import 'release_store.dart';

enum ReleaseOpenFailureKind { folderPicker, manifestNotFound, loadFailed }

sealed class ReleaseOpenResult {
  const ReleaseOpenResult();
}

final class ReleaseOpenSuccess extends ReleaseOpenResult {
  const ReleaseOpenSuccess(this.release);

  final Release release;
}

/// The user closed the picker without choosing a folder. Not an error.
final class ReleaseOpenCancelled extends ReleaseOpenResult {
  const ReleaseOpenCancelled();
}

final class ReleaseOpenFailure extends ReleaseOpenResult {
  const ReleaseOpenFailure(this.kind);

  final ReleaseOpenFailureKind kind;
}

/// Opens a release folder from disk. It does not show messages: the widget maps
/// the result to localized text.
class ReleaseOpenController {
  ReleaseOpenController({required this.store});

  final ReleaseStore store;

  Future<ReleaseOpenResult> openRelease({
    required String dialogTitle,
    required String initialDirectory,
  }) async {
    String? directoryPath;

    try {
      // The picker opens at the default release directory from the settings,
      // the same way the wizard's folder button does. The widget reads the
      // value from `SettingsController` and passes it here, so the controller
      // builds no dependency of its own (rule 4).
      directoryPath = await FilePicker.getDirectoryPath(
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory.isEmpty ? null : initialDirectory,
      );
    } catch (_) {
      return const ReleaseOpenFailure(ReleaseOpenFailureKind.folderPicker);
    }

    if (directoryPath == null) {
      return const ReleaseOpenCancelled();
    }

    return _load(directoryPath);
  }

  /// Reads a folder the recent list names, without picking one. The same load
  /// and the same failures as the picked path, so a row click reports a failure
  /// the same way the menu item does.
  Future<ReleaseOpenResult> openPath(String directoryPath) =>
      _load(directoryPath);

  Future<ReleaseOpenResult> _load(String directoryPath) async {
    try {
      return ReleaseOpenSuccess(await store.load(directoryPath));
    } on ReleaseManifestNotFoundException {
      return const ReleaseOpenFailure(ReleaseOpenFailureKind.manifestNotFound);
    } catch (_) {
      return const ReleaseOpenFailure(ReleaseOpenFailureKind.loadFailed);
    }
  }
}
