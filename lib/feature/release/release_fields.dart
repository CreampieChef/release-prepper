import '../../l10n/app_localizations.dart';
import '../../service/photosets/photoset_scanner.dart';
import 'release_type.dart';

/// Field values as plain strings, keyed by field name.
///
/// The same shape at both levels — the release and an item
/// (`ai/release_structure.md` §3) — so the editor and the message read one
/// model whatever the release type is. Which names exist is the field list of
/// the type, not this class.
///
/// Mutable: the editor edits it in place and `toJson()` writes it back.
class FieldValues {
  FieldValues();

  String value(String name) => _values[name] ?? '';

  void setValue(String name, String value) {
    _values[name] = value;
  }

  final Map<String, String> _values = {};

  /// The `fields` object of `release.json`, keyed by field name.
  Map<String, String> toJson() => {
    for (final entry in _values.entries) entry.key: entry.value,
  };

  /// A manifest is read into this, so a loaded release shows exactly what its
  /// file contains rather than the defaults of a new one. A key this type's
  /// field list does not know is kept, because the file is what the user may
  /// have edited.
  static FieldValues fromJson(Map<String, dynamic> json) {
    final values = FieldValues();

    for (final entry in json.entries) {
      if (entry.value is String) {
        values.setValue(entry.key, entry.value as String);
      }
    }

    return values;
  }
}

/// One field as a field list describes it: the name `release.json` writes, the
/// value a new release starts with, whether the app fills it, and whether a
/// value is required.
///
/// The label is not here. A field list is data, and a user-visible string comes
/// from `AppLocalizations`, so the label is resolved by the widget that shows
/// the row (`ai/description_template.md` rule 13). The field name is what the
/// widget switches on.
class FieldSpec {
  const FieldSpec({
    required this.name,
    this.defaultValue = '',
    this.filledByApp = false,
    this.hasFormRow = true,
    this.isRequired = true,
    this.isByteCount = false,
    this.readByTemplate = true,
    this.copiedByClone = true,
  });

  /// The name `release.json` writes, and the key the editor's row is found by.
  final String name;

  /// The value a new release starts with. A loaded manifest shows what it
  /// contains instead.
  final String defaultValue;

  /// The app fills this, so the user cannot edit it. For a video it is what
  /// ffprobe reports; for a photoset pack it is what the scan counts. Which
  /// fields the app fills is a property of the field list rather than of the
  /// widget, so the knowledge lives here.
  final bool filledByApp;

  /// Whether the field has a row the form builds itself. `sceneUrl` is the one
  /// name whose row is another widget's: the Stash row, which the editor places
  /// at the top of the left column, so the editor builds no text controller for
  /// it.
  final bool hasFormRow;

  /// Whether a message can be generated with this field empty. A field the app
  /// fills is required as well: the post shows its value, so a value the probe
  /// has not written is a missing value like one the user did not type.
  ///
  /// Only a field list that states its rules is checked (`validatesFields`), so
  /// this is a rule only for the types whose required set is known.
  final bool isRequired;

  /// Whether the value is a byte count, so a row shows it in the human form as
  /// well (`file_size.dart`). Like `filledByApp`, this is a property of the field
  /// rather than of the widget, so the display rule reads it here rather than
  /// switching on the names a widget knows. A place that shows a size in a
  /// fixed-width cell — the Video pack table's size column — uses the human form
  /// directly, because it cannot hold the byte count as well.
  final bool isByteCount;

  /// Whether a message is built from this value. The Message section clears its
  /// box when the values a render reads change, so a value no template reads has
  /// to be marked as not one: writing the parent forum would otherwise clear the
  /// message it is meant to be sent (`ai/uploading_draft.md` §4).
  final bool readByTemplate;

  /// Whether a clone takes this value from its source. A value the user typed is
  /// copied; a value a run wrote is not, because it belongs to that run: the
  /// draft link names the topic the source's draft was saved as, so a clone that
  /// kept it would point at a draft it did not make. The parent forum is what the
  /// user wrote, so a clone keeps it and the next run there is made in the same
  /// forum.
  final bool copiedByClone;
}

/// The fields one release type has. Which names exist is this, not
/// `FieldValues`.
class FieldList {
  const FieldList({
    required this.releaseType,
    required this.sourceKind,
    required this.itemBoundary,
    required this.itemType,
    required this.fields,
    this.itemFields = const [],
    this.validatesFields = false,
  });

  /// The type this field list is for. It is the technical name, so the value
  /// `release.json` writes, the template file name and the label key all come
  /// from the same thing (`release_type.dart`).
  final ReleaseType releaseType;

  /// What the user picks for this type: a file, or a directory that contains
  /// the items.
  final SourceKind sourceKind;

  /// What the scan treats as an item for this type (`ai/release_structure.md`
  /// §9). It is here rather than in the scan because it is a rule of the type,
  /// like `sourceKind` and `itemType`; the scan is given it instead of holding
  /// one (`ai/single_photoset.md` §5).
  final ItemBoundary itemBoundary;

  /// The `type` this type's items are recorded with.
  final String itemType;

  final List<FieldSpec> fields;

  /// The fields an item of this type has. For a Single video release the values
  /// are the release's own, so this is empty; the field list is what decides
  /// which level a value lives at (`ai/release_structure.md` §3).
  final List<FieldSpec> itemFields;

  /// Whether the required set of this type is known, so a generation checks it
  /// (`ai/description_template.md`). It is false for the types whose rules are
  /// not decided yet (`lib/TODO.MD`): a field list that has not stated its
  /// rules cannot be validated against them, so nothing is reported for them.
  final bool validatesFields;

  /// The fields the form shows. A field with no row is edited by another
  /// widget.
  List<FieldSpec> get formRows => [
    for (final field in fields)
      if (field.hasFormRow) field,
  ];

  FieldSpec field(String name) =>
      fields.firstWhere((field) => field.name == name);

  /// Whether this type has the name. The scan counts values for every photoset
  /// type, and a value for a name the type does not have would be stored but
  /// never shown (`ai/single_photoset.md` §3).
  bool hasField(String name) => fields.any((field) => field.name == name);
}

/// What the user picks for a release. A picked file is treated as a directory
/// containing only itself, so one rule covers both (`ai/release_structure.md`
/// §2).
enum SourceKind { file, directory }

/// The `type` an item is recorded with. It is recorded when an item is created,
/// not derived when a manifest is read, because what counts as an item depends
/// on the release type.
const itemTypeVideo = 'video';
const itemTypePhotoset = 'photoset';
const itemTypeImageFolder = 'imageFolder';

/// The two names the Upload draft feature stores (`ai/uploading_draft.md`). They
/// are in the field lists of the four types the feature covers and not in the
/// image folder's, because that type has no title to send.
///
/// Neither has a row the form builds: the parent forum row is the section's, as
/// `sceneUrl`'s is the Stash row's, and the link is shown as a link. Neither is
/// a value a template reads, so writing one does not make a rendered message
/// stale. Neither is required for a message: the requirement is the section's own
/// gate, the button being disabled while the field is empty. The link is not
/// copied by a clone, because it is what a run wrote rather than what the user
/// typed; the forum is what the user typed, so a clone keeps it.
const _parentForum = FieldSpec(
  name: 'parentForum',
  hasFormRow: false,
  isRequired: false,
  readByTemplate: false,
);

const _draftUrl = FieldSpec(
  name: 'draftUrl',
  hasFormRow: false,
  isRequired: false,
  readByTemplate: false,
  copiedByClone: false,
);

/// Field list of a Single video release.
///
/// The path the user picked is not a field: the item is the file, and its path
/// is the record ID (`ai/release_structure.md` §2).
///
/// The order of the values is the order a new release writes them in. The order
/// the editor shows them in is the two column lists in `release_editor.dart`.
///
/// This is the one type whose required set is known: only the site number, the
/// description, the additional information and the scene link are optional
/// (`ai/description_template.md`), so the other fields are required, including
/// the ones the app fills.
const singleVideoFieldList = FieldList(
  releaseType: ReleaseType.singleVideo,
  sourceKind: SourceKind.file,
  itemBoundary: ItemBoundary.source,
  itemType: itemTypeVideo,
  validatesFields: true,
  fields: [
    // The link to the scene this release is from. It is a field because a video
    // pack has a different one for each video, and `fields` is the name →
    // string map at both levels — so storing it is data, not a format change.
    // Its row is the Stash row, the widget that shows and edits it, because
    // that is where the link is read from the clipboard and fetched; the form
    // places that row at the top of its left column, under the poster box.
    // It is optional: no template reads it, so it is only there to help fill
    // the other fields.
    FieldSpec(name: 'sceneUrl', hasFormRow: false, isRequired: false),
    FieldSpec(name: 'cast'),
    FieldSpec(name: 'videoTitle'),
    FieldSpec(name: 'siteNumber', isRequired: false),
    FieldSpec(name: 'subsiteAndSite'),
    FieldSpec(name: 'productionDate'),
    FieldSpec(name: 'genreTags'),
    FieldSpec(name: 'fileSize', filledByApp: true, isByteCount: true),
    FieldSpec(name: 'duration', filledByApp: true),
    FieldSpec(name: 'videoType', filledByApp: true),
    // `SiteRip` is the app's default video quality: it is a value the user
    // writes the same way in every language, so it is not an AppLocalizations
    // key.
    FieldSpec(name: 'videoQuality', defaultValue: 'SiteRip'),
    FieldSpec(name: 'videoFormat', filledByApp: true),
    FieldSpec(name: 'videoStream', filledByApp: true),
    FieldSpec(name: 'audioStream', filledByApp: true),
    FieldSpec(name: 'description', isRequired: false),
    FieldSpec(name: 'additionalInfo', isRequired: false),
    _parentForum,
    _draftUrl,
  ],
);

/// Field list of a photoset pack (`ai/photoset_pack.md`).
///
/// The user provides the site or journal, the period and the tags; the rest is
/// what the scan counts. A photoset has no values read from a file, so nothing
/// here is filled by a probe — these are filled by the scan, which is the same
/// marker under a different producer.
const photosetPackFieldList = FieldList(
  releaseType: ReleaseType.photosetPack,
  sourceKind: SourceKind.directory,
  itemBoundary: ItemBoundary.entries,
  itemType: itemTypePhotoset,
  fields: [
    FieldSpec(name: 'siteOrJournal'),
    FieldSpec(name: 'period'),
    FieldSpec(name: 'genreTags'),
    FieldSpec(name: 'photosetCount', filledByApp: true),
    FieldSpec(name: 'totalPhotoCount', filledByApp: true),
    FieldSpec(name: 'totalSize', filledByApp: true, isByteCount: true),
    FieldSpec(name: 'minResolution', filledByApp: true),
    FieldSpec(name: 'maxResolution', filledByApp: true),
    _parentForum,
    _draftUrl,
  ],
  itemFields: [
    // The count of the photos in one set. It is a field because it is a value
    // the message reads and the user may want to correct, and `fields` is the
    // name → string map at both levels.
    FieldSpec(name: 'photoCount', filledByApp: true),
  ],
);

/// Field list of a video pack (`ai/video_pack.md`).
///
/// The names are the ones Single video and the photoset pack already have: a
/// credit is the same value as an actress name, and a period is the same value,
/// so nothing here is a new label. The four aggregates are the only names this
/// type has of its own, because a pack is the only type whose derived values
/// come from several items.
///
/// `siteNumber`, `videoTitle` and `sceneUrl` are not here: they belong to the
/// per-item form, which does not exist yet, and a field with no widget would be
/// stored but never written (`ai/video_pack.md` §3).
const videoPackFieldList = FieldList(
  releaseType: ReleaseType.videoPack,
  sourceKind: SourceKind.directory,
  itemBoundary: ItemBoundary.entries,
  itemType: itemTypeVideo,
  fields: [
    FieldSpec(name: 'subsiteAndSite'),
    FieldSpec(name: 'cast'),
    FieldSpec(name: 'period'),
    FieldSpec(name: 'genreTags'),
    FieldSpec(name: 'description'),
    FieldSpec(name: 'additionalInfo'),
    FieldSpec(name: 'totalSize', filledByApp: true, isByteCount: true),
    FieldSpec(name: 'videoCount', filledByApp: true),
    FieldSpec(name: 'videoResolutions', filledByApp: true),
    FieldSpec(name: 'videoFormats', filledByApp: true),
    _parentForum,
    _draftUrl,
  ],
  itemFields: [
    // The same names Single video has, because the per-item data is what
    // ffprobe reports for one file whatever the release type is
    // (`ai/video_pack.md` §1).
    FieldSpec(name: 'fileSize', filledByApp: true, isByteCount: true),
    FieldSpec(name: 'duration', filledByApp: true),
    FieldSpec(name: 'videoType', filledByApp: true),
    FieldSpec(name: 'videoFormat', filledByApp: true),
    FieldSpec(name: 'videoStream', filledByApp: true),
    FieldSpec(name: 'audioStream', filledByApp: true),
  ],
);

/// Field list of a single photoset (`ai/single_photoset.md`).
///
/// The names are the ones the other types already have: a model is the same
/// value as a cast, a set name is the same value as a title, a site or journal
/// is the same value. `imageFormats` is the only name this type has of its own.
///
/// `photosetCount` is not here: with one item it is always 1, and a field the
/// app cannot answer differently from its own definition is not a field.
/// `additionalInfo` is not here either, because this type's fields are the ones
/// above (`ai/single_photoset.md` §3).
const singlePhotosetFieldList = FieldList(
  releaseType: ReleaseType.singlePhotoset,
  sourceKind: SourceKind.directory,
  itemBoundary: ItemBoundary.source,
  itemType: itemTypePhotoset,
  fields: [
    FieldSpec(name: 'siteOrJournal'),
    FieldSpec(name: 'cast'),
    FieldSpec(name: 'videoTitle'),
    FieldSpec(name: 'productionDate'),
    FieldSpec(name: 'genreTags'),
    FieldSpec(name: 'description'),
    FieldSpec(name: 'totalPhotoCount', filledByApp: true),
    FieldSpec(name: 'totalSize', filledByApp: true, isByteCount: true),
    FieldSpec(name: 'minResolution', filledByApp: true),
    FieldSpec(name: 'maxResolution', filledByApp: true),
    FieldSpec(name: 'imageFormats', filledByApp: true),
    _parentForum,
    _draftUrl,
  ],
  itemFields: [
    // The same name the photoset pack has, because the count of the photos in
    // one set is the same value whatever the release type is.
    FieldSpec(name: 'photoCount', filledByApp: true),
  ],
);

/// Field list of an image folder upload (`ai/image_folder_upload.md`), the
/// catch-all type of `ai/release_structure.md` §6.
///
/// Nothing here is a field the user writes: the type is a folder of images, and
/// what a post shows is the image block, so the only values are the ones the
/// scan counts. The names are the ones the photoset types already have — a
/// count of images is the same value as a count of photos, a resolution is the
/// same value, a format list is the same value — so nothing here is a new name.
/// Only the words differ, and those are resolved per type by `fieldLabel`.
///
/// There are no item fields: the item is the picked folder and the counts
/// describe it as a whole, so an item-level count would be the release-level
/// count under another name.
const imageFolderUploadFieldList = FieldList(
  releaseType: ReleaseType.imageFolderUpload,
  sourceKind: SourceKind.directory,
  itemBoundary: ItemBoundary.source,
  itemType: itemTypeImageFolder,
  fields: [
    FieldSpec(name: 'totalPhotoCount', filledByApp: true),
    FieldSpec(name: 'minResolution', filledByApp: true),
    FieldSpec(name: 'maxResolution', filledByApp: true),
    FieldSpec(name: 'imageFormats', filledByApp: true),
  ],
);

/// The field list a release type has. A switch rather than a map, so a type
/// added to [ReleaseType] has to be given a field list here: the app cannot
/// have a type without one, and the compiler says so. The wizard's option list
/// is `ReleaseType.values` read through this, so a type cannot be chosen
/// without a field list behind it.
FieldList fieldListFor(ReleaseType releaseType) => switch (releaseType) {
  ReleaseType.singleVideo => singleVideoFieldList,
  ReleaseType.photosetPack => photosetPackFieldList,
  ReleaseType.videoPack => videoPackFieldList,
  ReleaseType.singlePhotoset => singlePhotosetFieldList,
  ReleaseType.imageFolderUpload => imageFolderUploadFieldList,
};

/// The label a field is shown with. A field list is data and cannot hold a
/// localized string, so this is the one place the names are turned into
/// `AppLocalizations` keys. It is called by the editor's form, by the Stash
/// section, and by the Video pack section, which shows the values as text
/// rather than as form rows — the table's column headers and the lines under an
/// opened row — which is why it is here rather than in either widget.
///
/// It takes the release type because some names mean different words for some
/// types: the model is the same value as a cast, and the set name is the same
/// value as a title (`ai/single_photoset.md` §4); the three photo names read as
/// image names for a folder of images, which is not a set of photos
/// (`ai/image_folder_upload.md` §4). Every other name reads the same for every
/// type.
///
/// The arm at the end is reached only for a name no widget shows: `photoCount`,
/// because the photoset section shows the count through its own key rather than
/// through a label. Every name that has an arm here comes from a field list. It
/// is here because a switch on strings needs one.
String fieldLabel(
  String name,
  AppLocalizations l10n,
  ReleaseType releaseType,
) => switch (name) {
  // Never reached in the form: the scene link has no row, its widget is the
  // StashDB section's input.
  'sceneUrl' => l10n.stashSceneInputLabel,
  // A model is the same value as a cast, and a set name the same value as a
  // title, so the names are shared and only the words differ
  // (`ai/single_photoset.md` §4).
  'cast' =>
    releaseType == ReleaseType.singlePhotoset
        ? l10n.modelLabel
        : l10n.castLabel,
  'videoTitle' =>
    releaseType == ReleaseType.singlePhotoset
        ? l10n.setNameLabel
        : l10n.videoTitleLabel,
  'siteNumber' => l10n.siteNumberLabel,
  'subsiteAndSite' => l10n.subsiteAndSiteLabel,
  'productionDate' => l10n.productionDateLabel,
  'genreTags' => l10n.genreTagsLabel,
  'fileSize' => l10n.fileSizeLabel,
  'duration' => l10n.durationLabel,
  'videoType' => l10n.videoTypeLabel,
  'videoQuality' => l10n.videoQualityLabel,
  'videoFormat' => l10n.videoFormatLabel,
  'videoStream' => l10n.videoStreamLabel,
  'audioStream' => l10n.audioStreamLabel,
  'description' => l10n.descriptionLabel,
  'additionalInfo' => l10n.additionalInfoLabel,
  'siteOrJournal' => l10n.siteOrJournalLabel,
  'period' => l10n.periodLabel,
  'photosetCount' => l10n.photosetCountLabel,
  // The three names are the same values whatever the type, but a folder of
  // images is not a set of photos, so the words differ for that type
  // (`ai/image_folder_upload.md` §4).
  'totalPhotoCount' =>
    releaseType == ReleaseType.imageFolderUpload
        ? l10n.imageCountLabel
        : l10n.totalPhotoCountLabel,
  'minResolution' =>
    releaseType == ReleaseType.imageFolderUpload
        ? l10n.minImageResolutionLabel
        : l10n.minResolutionLabel,
  'maxResolution' =>
    releaseType == ReleaseType.imageFolderUpload
        ? l10n.maxImageResolutionLabel
        : l10n.maxResolutionLabel,
  'imageFormats' => l10n.imageFormatsLabel,
  // A key of its own rather than `fileSizeLabel`: the value is the sizes the
  // counted files added together, not the size of one file, so the words
  // differ.
  'totalSize' => l10n.totalSizeLabel,
  'videoCount' => l10n.videoCountLabel,
  'videoResolutions' => l10n.videoResolutionsLabel,
  'videoFormats' => l10n.videoFormatsLabel,
  // The two names of the Upload draft section are not rows the form builds: the
  // row is the section's own input, and the link is shown as itself, so the
  // section asks for the words here, as the StashDB section does for its input
  // (`ai/uploading_draft.md` §4).
  'parentForum' => l10n.parentForumLabel,
  'draftUrl' => l10n.draftLinkLabel,
  _ => name,
};
