import 'package:path/path.dart' as p;

import '../../service/native_tools/uptooda.dart';
import '../release/release.dart';
import '../release/release_store.dart';
import '../release/release_type.dart';
import '../screenshots/images.dart';
import '../screenshots/images_store.dart';
import 'hosters.dart';

/// Upload state and side effects (`ai/upload_images.md`). It owns no
/// `Listenable` (rule 3) and shows no messages (rule 13): the widget owns the
/// hoster selection and the layout, calls `upload()`, and maps a result to
/// localized text. Progress is reported through a plain callback the widget
/// passes in.
///
/// A progress report counts against all the images in the release, not against
/// the items a run happens to pick up, so the state the widget shows when it
/// opens and the state a run reports are the same measure and a bar never moves
/// backwards.
class UploadController {
  UploadController({
    required this.release,
    required this.uptooda,
    required this.store,
    required this.releaseStore,
  });

  final Release release;
  final Uptooda uptooda;
  final ImagesStore store;

  /// `release.json`, for the last-edit stamp a run that uploaded something
  /// writes.
  final ReleaseStore releaseStore;

  /// One image at a time per hoster, several hosters at the same time
  /// (`ai/upload_images.md`). With the limit at 1 a hoster is a sequential
  /// loop, so the limit is what the rule states rather than something the code
  /// has to count.
  static const perHosterLimit = 1;

  /// The state every bar shows, for every hoster in the registry, in the order
  /// the section lists them (`ai/upload_images.md`). It is read synchronously
  /// so the widget can draw the bars when it is opened, before anything has
  /// run: a release whose images are all uploaded to a hoster is a full bar,
  /// and one with no images is an empty one, because the bar is the share of
  /// the release's images that hoster has.
  Map<String, UploadProgress> progress() {
    final manifest = store.loadSync(release.directoryPath);

    return {
      for (final hoster in hosters) hoster.name: _state(manifest, hoster.name),
    };
  }

  /// Whether the release has the images a run here has to do: the poster, and
  /// at least one image of the kind this type produces. A switch, like the
  /// other per-type rules, so a type added to `ReleaseType` has to say.
  ///
  /// A pack can be asked to write only the screenlist, so its run has nothing
  /// to upload until one exists (`ai/video_pack.md` §5). The two photoset types
  /// and the image folder record photos rather than screenshots, so a photo is
  /// what they have. Until both are there the section shows the placeholder
  /// instead of the hoster list, because there is nothing it could upload.
  bool hasUploadableImages() {
    final images = store.loadSync(release.directoryPath).images;

    final kind = switch (release.releaseType) {
      ReleaseType.singleVideo => ImageKind.screenshot,
      ReleaseType.videoPack => ImageKind.screenlist,
      ReleaseType.photosetPack || ReleaseType.singlePhotoset => ImageKind.photo,
      ReleaseType.imageFolderUpload => ImageKind.photo,
    };

    return images.any((record) => record.kind == ImageKind.poster) &&
        images.any((record) => record.kind == kind);
  }

  /// The hosters the widget selected, and the values the widget read from the
  /// settings (rule 13: the widget resolves the settings from the provider
  /// scope, the controller is given what it needs). A hoster is a `Hoster`
  /// rather than a name because the call needs its `service`: that is what
  /// decides whether the credential is passed. The parameter is `selected`, not
  /// `hosters`, so it does not hide the registry the state above is read from.
  Future<UploadResult> upload({
    required List<Hoster> selected,
    required Map<String, String> secrets,
    required void Function(UploadProgress progress) onProgress,
  }) async {
    final manifest = await store.load(release.directoryPath);

    // The skip rule: an image already uploaded to a hoster is skipped, one that
    // failed is tried again, and a hoster that is not selected is never
    // attempted. The work list is in the order `images.json` lists the records,
    // which is the order the file preserves (`ai/release_structure.md` §4).
    final work = {
      for (final hoster in selected)
        hoster.name: [
          for (final record in manifest.images)
            if (!record.urls.containsKey(hoster.name)) record,
        ],
    };

    // The state at the start of the run, so the bar shows what this hoster
    // already has rather than starting from 0, and the run continues from
    // there.
    final start = {
      for (final hoster in selected) hoster.name: _state(manifest, hoster.name),
    };

    for (final state in start.values) {
      onProgress(state);
    }

    final outcomes = await Future.wait([
      for (final hoster in selected)
        _runHoster(
          hoster,
          work[hoster.name]!,
          start[hoster.name]!,
          manifest,
          secrets,
          onProgress,
        ),
    ]);

    if (outcomes.any((outcome) => outcome.toolNotAvailable)) {
      return const UploadFailure(UploadFailureKind.toolNotAvailable);
    }

    if (outcomes.any((outcome) => outcome.manifestFailed)) {
      return const UploadFailure(UploadFailureKind.manifestFailed);
    }

    // A run that uploaded nothing changed no file, so it stamps nothing; a run
    // that wrote a record changed the release, and the timestamp is what
    // records that.
    if (outcomes.any((outcome) => outcome.uploaded > 0)) {
      await releaseStore.touchLastEdit(release);
    }

    return const UploadSuccess();
  }

  /// One hoster, one image at a time. The bar counts against all the images in
  /// the release, so it starts from what this hoster already has
  /// (`ai/upload_images.md`).
  Future<_HosterOutcome> _runHoster(
    Hoster hoster,
    List<ImageRecord> records,
    UploadProgress start,
    ImagesManifest manifest,
    Map<String, String> secrets,
    void Function(UploadProgress progress) onProgress,
  ) async {
    final environment = _environment(hoster, secrets);

    var done = start.done;
    var uploaded = 0;
    var toolNotAvailable = false;
    var manifestFailed = false;

    for (final record in records) {
      switch (await uptooda.upload(
        releaseDirectory: release.directoryPath,
        hoster: hoster.name,
        filePath: p.join(release.directoryPath, record.file),
        environment: environment,
      )) {
        case UptoodaUploadSuccess(urls: final urls):
          // Only successful URLs are recorded. The record is shared with the
          // other hosters, so this is what a successful upload changes.
          record.urls[hoster.name] = urls;

          if (await _save(manifest)) {
            done += 1;
            uploaded += 1;
          } else {
            manifestFailed = true;
          }
        case UptoodaUploadFailure(kind: final kind):
          if (kind == UptoodaUploadFailureKind.toolNotAvailable) {
            toolNotAvailable = true;
          }
      }

      // A failed upload does not increase `done`, so the bar shows what was
      // uploaded and stays below full when some failed (`ai/upload_images.md`).
      onProgress(
        UploadProgress(hoster: hoster.name, done: done, total: start.total),
      );
    }

    return _HosterOutcome(
      uploaded: uploaded,
      toolNotAvailable: toolNotAvailable,
      manifestFailed: manifestFailed,
    );
  }

  /// The state for one hoster: the records with a URL for it over all the
  /// records. Only successful uploads are stored, so a record with no entry for
  /// a hoster is one that has not been uploaded to it (`ai/upload_images.md`).
  UploadProgress _state(ImagesManifest manifest, String hoster) =>
      UploadProgress(
        hoster: hoster,
        done: manifest.images
            .where((record) => record.urls.containsKey(hoster))
            .length,
        total: manifest.images.length,
      );

  /// The environment for one hoster's calls: nothing for a hoster whose script
  /// does not read a credential, and the value only when there is one to pass
  /// (`ai/bundled_native_tools.md`). The widget does not let a hoster that
  /// needs a credential be selected while its value is empty, so this is the
  /// same rule from the other side: an empty value never reaches the tool as a
  /// variable.
  Map<String, String> _environment(Hoster hoster, Map<String, String> secrets) {
    final field = hoster.field;

    if (field == null) {
      return const {};
    }

    final value = secrets[field.name] ?? '';

    return value.isEmpty ? const {} : {Uptooda.apiKeyVariable: value};
  }

  /// `images.json` is one file and several hosters write to it at the same
  /// time, so the writes are serialised here. Returns whether the file was
  /// written.
  Future<void> _writes = Future<void>.value();

  Future<bool> _save(ImagesManifest manifest) {
    final next = _writes
        .then((_) => store.save(release.directoryPath, manifest))
        .then((_) => true);

    _writes = next.catchError((_) => false);

    return next;
  }
}

/// What one hoster's run ended with. Per-image upload failures are not here:
/// the bar shows them, and the log is what the developer reads
/// (`ai/upload_images.md`).
class _HosterOutcome {
  const _HosterOutcome({
    required this.uploaded,
    required this.toolNotAvailable,
    required this.manifestFailed,
  });

  /// How many images this hoster wrote. It is what decides whether the run
  /// changed the release, and so whether the last-edit stamp is written.
  final int uploaded;

  final bool toolNotAvailable;
  final bool manifestFailed;
}

/// One progress report (`ai/upload_images.md`): the images uploaded to one
/// hoster over the images in the release. The same shape is what the state read
/// at open returns and what a run reports, so a bar shows one measure.
class UploadProgress {
  const UploadProgress({
    required this.hoster,
    required this.done,
    required this.total,
  });

  final String hoster;
  final int done;
  final int total;
}

enum UploadFailureKind {
  /// The tool is not in the app bundle, so nothing can be uploaded.
  toolNotAvailable,

  /// A URL was uploaded but `images.json` could not be written.
  manifestFailed,
}

sealed class UploadResult {
  const UploadResult();
}

final class UploadSuccess extends UploadResult {
  const UploadSuccess();
}

final class UploadFailure extends UploadResult {
  const UploadFailure(this.kind);

  final UploadFailureKind kind;
}
