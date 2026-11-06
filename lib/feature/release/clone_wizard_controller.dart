import 'dart:io';

import 'package:path/path.dart' as p;

import '../message/message_controller.dart';
import '../recent_releases/recent_releases_controller.dart';
import '../screenshots/images.dart';
import '../screenshots/images_store.dart';
import 'release.dart';
import 'release_fields.dart';
import 'release_store.dart';
import 'release_wizard_controller.dart';

/// The name the clone is created under. The folder-name rules are the wizard's
/// (`validateReleaseName`); the clone adds one: the name must differ from the
/// source's, because two releases with the same name are two rows of the recent
/// list that cannot be told apart.
enum CloneNameValidationError { required, invalid, sameAsSource }

CloneNameValidationError? validateCloneName(String? value, String sourceName) {
  final problem = validateReleaseName(value);

  if (problem != null) {
    return switch (problem) {
      ReleaseNameValidationError.required => CloneNameValidationError.required,
      ReleaseNameValidationError.invalid => CloneNameValidationError.invalid,
    };
  }

  if (value!.trim() == sourceName) {
    return CloneNameValidationError.sameAsSource;
  }

  return null;
}

/// What the clone can copy from the source's poster. The widget maps these to
/// its warnings (rule 13); the controller shows nothing.
enum ClonePosterStatus { noPoster, notUploaded, uploaded }

sealed class CloneCreationResult {
  const CloneCreationResult();
}

final class CloneCreationSuccess extends CloneCreationResult {
  const CloneCreationSuccess(this.release);

  final Release release;
}

final class CloneCreationFailure extends CloneCreationResult {
  const CloneCreationFailure(this.kind);

  /// The same failure vocabulary as the wizard's create, so the widget maps it
  /// to the same messages.
  final ReleaseCreationFailure kind;
}

/// Clone wizard state: the copy rules and the create. It owns no `Listenable`
/// (rule 3); the widget keeps its own busy flag and maps a failure to localized
/// text.
class CloneWizardController {
  CloneWizardController({
    required this.source,
    required this.store,
    required this.images,
    required this.recentReleases,
  });

  /// The release being cloned. The clone is a Single video release, because the
  /// menu item is only enabled for that type.
  final Release source;

  final ReleaseStore store;

  /// `images.json`, for the poster record the copy takes.
  final ImagesStore images;

  /// Recording the created release is its own feature's side effect, so it is
  /// called here rather than owned here (`ai/recent_releases.md` §3).
  final RecentReleasesController recentReleases;

  /// The directory the form is prefilled with and the folder picker falls back
  /// to: the folder the source release is in, so the clone is its neighbour
  /// unless the user picks another one.
  String get defaultSavePath => p.dirname(source.directoryPath);

  /// The source poster's state, read from its manifest. A synchronous check,
  /// because the widget asks while it builds, the same way the Message section
  /// asks (`ai/description_template.md`).
  ClonePosterStatus posterStatus() {
    final record = images.loadSync(source.directoryPath).primaryPoster();

    if (record == null) {
      return ClonePosterStatus.noPoster;
    }

    if ((record.urls[posterHoster] ?? const <String, String>{}).isEmpty) {
      return ClonePosterStatus.notUploaded;
    }

    return ClonePosterStatus.uploaded;
  }

  /// Creates the clone: the folder and the manifest as `ReleaseStore.create`
  /// does them, then what the copy takes.
  ///
  /// The fields the user writes are copied. The fields the app fills from the
  /// movie file are not: the clone is a different video, so those are its own
  /// probe's to write. Neither is a value a run wrote (`copiedByClone`): the
  /// draft link names the source's draft, so the clone starts without one and
  /// gets its own when it runs the feature there.
  ///
  /// The two flags are the source's, not the settings' defaults: the clone is
  /// the same scene at another resolution, so the post it writes and the
  /// torrent it builds are expected to be like the source's. What the settings
  /// say about new releases is what a release made from the wizard gets.
  ///
  /// The poster is copied as it is recorded — the record with its URLs, and the
  /// file when it is on disk. No other record is copied: the clone generates
  /// and uploads its own images.
  ///
  /// A copy that cannot be written is a failed create, and the folder the
  /// create made is removed, so a half-copied release is not left behind.
  Future<CloneCreationResult> create({
    required String savePath,
    required String name,
  }) async {
    Release release;

    try {
      release = await store.create(
        savePath: savePath,
        name: name,
        tracker: source.tracker,
        releaseType: source.releaseType,
        torrentPrivate: source.torrentPrivate,
        includeAppSignature: source.includeAppSignature,
      );
    } on ReleaseAlreadyExistsException {
      return const CloneCreationFailure(ReleaseCreationFailure.alreadyExists);
    } catch (_) {
      return const CloneCreationFailure(ReleaseCreationFailure.failed);
    }

    try {
      for (final field in fieldListFor(source.releaseType).fields) {
        if (!field.filledByApp && field.copiedByClone) {
          release.fields.setValue(field.name, source.fields.value(field.name));
        }
      }

      await store.save(release);

      final poster = images.loadSync(source.directoryPath).primaryPoster();

      if (poster != null) {
        final sourceFile = File(p.join(source.directoryPath, poster.file));

        if (sourceFile.existsSync()) {
          await sourceFile.copy(p.join(release.directoryPath, poster.file));
        }

        // The record is copied as a new object rather than the source's, so the
        // Upload section of either release cannot write through the same map.
        await images.save(
          release.directoryPath,
          ImagesManifest(
            images: [
              ImageRecord(
                item: poster.item,
                kind: poster.kind,
                file: poster.file,
                urls: Map.from(poster.urls),
              ),
            ],
          ),
        );
      }

      // A release the app created is an entry in the recent list, the same as
      // one it opened (`ai/recent_releases.md` §3). Only a successful create is
      // recorded.
      await recentReleases.record(release);

      return CloneCreationSuccess(release);
    } catch (_) {
      try {
        await Directory(release.directoryPath).delete(recursive: true);
      } catch (_) {
        // Keep the original error.
      }

      return const CloneCreationFailure(ReleaseCreationFailure.failed);
    }
  }
}
