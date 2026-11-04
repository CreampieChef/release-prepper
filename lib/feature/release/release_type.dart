import '../../l10n/app_localizations.dart';

/// The release types the app knows. The enum value is the technical name: it is
/// the ID `release.json` writes, the name the template file is chosen by, and
/// the key the field lists are looked up by. What the user sees is a display
/// name, which is localized, so it cannot be a field on the enum — it is
/// resolved by [releaseTypeLabel], the same reasoning as a field label
/// (`release_fields.dart`).
///
/// `imageFolderUpload` is the catch-all type of `ai/release_structure.md` §6:
/// it is what a type the app did not design for looks like when it is added as
/// knowledge rather than as a format change — a field list with nothing the
/// user writes, a template that emits the default block, and a label.
///
/// The order is the order the wizard lists the types, because its option
/// list is `ReleaseType.values`. Nothing else reads the order: the manifest,
/// the template file name and the field list key are the value's name, not its
/// position.
enum ReleaseType {
  singleVideo,
  videoPack,
  singlePhotoset,
  photosetPack,
  imageFolderUpload,
}

/// The name a manifest holds, or null for a type this version does not know. A
/// manifest written by a later version is not opened, because there is no field
/// list, no template and no label for a type the app does not have — the app
/// cannot show or write what it cannot understand, so it reports the manifest
/// rather than guessing at a type for it.
ReleaseType? releaseTypeFromName(String name) {
  for (final value in ReleaseType.values) {
    if (value.name == name) {
      return value;
    }
  }

  return null;
}

/// Whether a type has a post title. A title is normally the tracker's rule for
/// how one is written, so a type has one; the image folder has no field the
/// user writes, so there is nothing a title could say and the type has no title
/// at all — no title file is read, nothing is written to `title.txt`, and the
/// Message section does not draw the title row for it
/// (`ai/image_folder_upload.md` §6). The controller and the section read the
/// same rule, so they cannot disagree. Exhaustive over the enum, as
/// `releaseTypeLabel` is.
bool hasTitle(ReleaseType type) => switch (type) {
  ReleaseType.singleVideo => true,
  ReleaseType.photosetPack => true,
  ReleaseType.videoPack => true,
  ReleaseType.singlePhotoset => true,
  ReleaseType.imageFolderUpload => false,
};

/// The display name of a release type. An enum value is data and cannot hold a
/// localized string, so this is the one place a type becomes an
/// `AppLocalizations` key, as `fieldLabel` is for a field name. It is
/// exhaustive over the enum, so a type added to it has to be given a label
/// here.
String releaseTypeLabel(ReleaseType type, AppLocalizations l10n) =>
    switch (type) {
      ReleaseType.singleVideo => l10n.releaseTypeSingleVideo,
      ReleaseType.photosetPack => l10n.releaseTypePhotosetPack,
      ReleaseType.videoPack => l10n.releaseTypeVideoPack,
      ReleaseType.singlePhotoset => l10n.releaseTypeSinglePhotoset,
      ReleaseType.imageFolderUpload => l10n.releaseTypeImageFolderUpload,
    };
