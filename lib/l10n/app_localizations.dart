import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// No description provided for @newRelease.
  ///
  /// In en, this message translates to:
  /// **'New Release'**
  String get newRelease;

  /// No description provided for @newReleaseShortcut.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+N'**
  String get newReleaseShortcut;

  /// No description provided for @help.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get help;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @allTabsClosed.
  ///
  /// In en, this message translates to:
  /// **'All tabs are closed.'**
  String get allTabsClosed;

  /// No description provided for @releaseDetails.
  ///
  /// In en, this message translates to:
  /// **'Release details go here.'**
  String get releaseDetails;

  /// No description provided for @closeTab.
  ///
  /// In en, this message translates to:
  /// **'Close {title} tab'**
  String closeTab(String title);

  /// No description provided for @closeTabItem.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get closeTabItem;

  /// No description provided for @closeTabShortcut.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+W'**
  String get closeTabShortcut;

  /// No description provided for @releaseNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get releaseNameLabel;

  /// No description provided for @savePathLabel.
  ///
  /// In en, this message translates to:
  /// **'Save path'**
  String get savePathLabel;

  /// No description provided for @chooseSavePath.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get chooseSavePath;

  /// No description provided for @trackerLabel.
  ///
  /// In en, this message translates to:
  /// **'Tracker'**
  String get trackerLabel;

  /// No description provided for @releaseTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Release type'**
  String get releaseTypeLabel;

  /// No description provided for @releaseTypeSingleVideo.
  ///
  /// In en, this message translates to:
  /// **'Single video'**
  String get releaseTypeSingleVideo;

  /// No description provided for @releaseTypeVideoPack.
  ///
  /// In en, this message translates to:
  /// **'Video pack (Beta)'**
  String get releaseTypeVideoPack;

  /// No description provided for @releaseTypeSinglePhotoset.
  ///
  /// In en, this message translates to:
  /// **'Single photoset (Beta)'**
  String get releaseTypeSinglePhotoset;

  /// No description provided for @releaseTypePhotosetPack.
  ///
  /// In en, this message translates to:
  /// **'Photoset pack (Beta)'**
  String get releaseTypePhotosetPack;

  /// No description provided for @releaseTypeImageFolderUpload.
  ///
  /// In en, this message translates to:
  /// **'Image folder upload (Beta)'**
  String get releaseTypeImageFolderUpload;

  /// No description provided for @createButton.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createButton;

  /// No description provided for @releaseNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a release name.'**
  String get releaseNameRequired;

  /// No description provided for @releaseNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use a valid folder name. Avoid / \\ : * ? \" < > |, control characters, reserved Windows names, and a trailing space or period.'**
  String get releaseNameInvalid;

  /// No description provided for @savePathRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a save path.'**
  String get savePathRequired;

  /// No description provided for @releaseAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'A folder with this release name already exists.'**
  String get releaseAlreadyExists;

  /// No description provided for @releaseCreated.
  ///
  /// In en, this message translates to:
  /// **'Release folder created.'**
  String get releaseCreated;

  /// No description provided for @releaseCreationFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the release. Check the path and permissions.'**
  String get releaseCreationFailed;

  /// No description provided for @folderPickerFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the folder picker.'**
  String get folderPickerFailed;

  /// No description provided for @cloneRelease.
  ///
  /// In en, this message translates to:
  /// **'Clone Release'**
  String get cloneRelease;

  /// No description provided for @cloneSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source release: {name}'**
  String cloneSourceLabel(String name);

  /// No description provided for @cloneNameMustDiffer.
  ///
  /// In en, this message translates to:
  /// **'The clone name must be different from the source release name.'**
  String get cloneNameMustDiffer;

  /// No description provided for @cloneNoPosterWarning.
  ///
  /// In en, this message translates to:
  /// **'The source release has no poster, so the clone will have none. It is best to upload the poster first, so the same poster does not have to be uploaded more than once.'**
  String get cloneNoPosterWarning;

  /// No description provided for @clonePosterNotUploadedWarning.
  ///
  /// In en, this message translates to:
  /// **'The poster has not been uploaded, so its links cannot be copied. It is best to upload the poster first, so the same poster does not have to be uploaded more than once.'**
  String get clonePosterNotUploadedWarning;

  /// No description provided for @openRelease.
  ///
  /// In en, this message translates to:
  /// **'Open Release'**
  String get openRelease;

  /// No description provided for @openReleaseShortcut.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+O'**
  String get openReleaseShortcut;

  /// No description provided for @chooseReleaseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose a release folder'**
  String get chooseReleaseFolder;

  /// No description provided for @releaseManifestNotFound.
  ///
  /// In en, this message translates to:
  /// **'The selected folder does not contain release.json.'**
  String get releaseManifestNotFound;

  /// No description provided for @releaseMetadataInvalid.
  ///
  /// In en, this message translates to:
  /// **'The release.json file is not valid.'**
  String get releaseMetadataInvalid;

  /// No description provided for @openReleaseError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the release.'**
  String get openReleaseError;

  /// No description provided for @chooseAnotherFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose another folder'**
  String get chooseAnotherFolder;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveShortcut.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+S'**
  String get saveShortcut;

  /// No description provided for @movieFilePathLabel.
  ///
  /// In en, this message translates to:
  /// **'Path to video'**
  String get movieFilePathLabel;

  /// No description provided for @chooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get chooseFile;

  /// No description provided for @filePickerFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the file picker.'**
  String get filePickerFailed;

  /// No description provided for @movieFileNotFound.
  ///
  /// In en, this message translates to:
  /// **'The movie file was not found.'**
  String get movieFileNotFound;

  /// No description provided for @probeToolNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'ffprobe is not installed. Install it to read file metadata.'**
  String get probeToolNotAvailable;

  /// No description provided for @probeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the file metadata.'**
  String get probeFailed;

  /// No description provided for @ffmpegNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'ffmpeg is not installed. Install it to work with images.'**
  String get ffmpegNotAvailable;

  /// No description provided for @thumbnailFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the thumbnail.'**
  String get thumbnailFailed;

  /// No description provided for @castLabel.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get castLabel;

  /// No description provided for @videoTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Video title'**
  String get videoTitleLabel;

  /// No description provided for @modelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get modelLabel;

  /// No description provided for @setNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Set name'**
  String get setNameLabel;

  /// No description provided for @siteNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Site number (optional)'**
  String get siteNumberLabel;

  /// No description provided for @subsiteAndSiteLabel.
  ///
  /// In en, this message translates to:
  /// **'Subsite and site'**
  String get subsiteAndSiteLabel;

  /// No description provided for @productionDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Production date'**
  String get productionDateLabel;

  /// No description provided for @chooseDate.
  ///
  /// In en, this message translates to:
  /// **'Choose date'**
  String get chooseDate;

  /// No description provided for @genreTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Genre (tags)'**
  String get genreTagsLabel;

  /// No description provided for @fileSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'File size'**
  String get fileSizeLabel;

  /// No description provided for @fileSizeDisplay.
  ///
  /// In en, this message translates to:
  /// **'{human} ({bytes} bytes)'**
  String fileSizeDisplay(String human, String bytes);

  /// No description provided for @durationLabel.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get durationLabel;

  /// No description provided for @durationHint.
  ///
  /// In en, this message translates to:
  /// **'hh:mm:ss'**
  String get durationHint;

  /// No description provided for @videoTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Video type'**
  String get videoTypeLabel;

  /// No description provided for @videoQualityLabel.
  ///
  /// In en, this message translates to:
  /// **'Video quality'**
  String get videoQualityLabel;

  /// No description provided for @videoFormatLabel.
  ///
  /// In en, this message translates to:
  /// **'Video format'**
  String get videoFormatLabel;

  /// No description provided for @videoStreamLabel.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get videoStreamLabel;

  /// No description provided for @audioStreamLabel.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audioStreamLabel;

  /// No description provided for @descriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionLabel;

  /// No description provided for @additionalInfoLabel.
  ///
  /// In en, this message translates to:
  /// **'Additional information (optional)'**
  String get additionalInfoLabel;

  /// No description provided for @photosetPackFolderLabel.
  ///
  /// In en, this message translates to:
  /// **'Folder with the photosets'**
  String get photosetPackFolderLabel;

  /// No description provided for @singlePhotosetFolderLabel.
  ///
  /// In en, this message translates to:
  /// **'Folder with the photos'**
  String get singlePhotosetFolderLabel;

  /// No description provided for @imageFolderFolderLabel.
  ///
  /// In en, this message translates to:
  /// **'Folder with the images'**
  String get imageFolderFolderLabel;

  /// No description provided for @chooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get chooseFolder;

  /// No description provided for @siteOrJournalLabel.
  ///
  /// In en, this message translates to:
  /// **'Site or journal'**
  String get siteOrJournalLabel;

  /// No description provided for @periodLabel.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get periodLabel;

  /// No description provided for @photosetCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Photosets'**
  String get photosetCountLabel;

  /// No description provided for @totalPhotoCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Photos (total)'**
  String get totalPhotoCountLabel;

  /// No description provided for @minResolutionLabel.
  ///
  /// In en, this message translates to:
  /// **'Minimum photo resolution'**
  String get minResolutionLabel;

  /// No description provided for @maxResolutionLabel.
  ///
  /// In en, this message translates to:
  /// **'Maximum photo resolution'**
  String get maxResolutionLabel;

  /// No description provided for @imageFormatsLabel.
  ///
  /// In en, this message translates to:
  /// **'Image formats'**
  String get imageFormatsLabel;

  /// No description provided for @imageCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Images (total)'**
  String get imageCountLabel;

  /// No description provided for @minImageResolutionLabel.
  ///
  /// In en, this message translates to:
  /// **'Minimum image resolution'**
  String get minImageResolutionLabel;

  /// No description provided for @maxImageResolutionLabel.
  ///
  /// In en, this message translates to:
  /// **'Maximum image resolution'**
  String get maxImageResolutionLabel;

  /// No description provided for @columnTitleReleaseInfo.
  ///
  /// In en, this message translates to:
  /// **'Release Info'**
  String get columnTitleReleaseInfo;

  /// No description provided for @columnTitleVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get columnTitleVideo;

  /// No description provided for @columnTitleSourceFolder.
  ///
  /// In en, this message translates to:
  /// **'Source folder'**
  String get columnTitleSourceFolder;

  /// No description provided for @columnTitlePhotosets.
  ///
  /// In en, this message translates to:
  /// **'Photosets'**
  String get columnTitlePhotosets;

  /// No description provided for @columnTitleImages.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get columnTitleImages;

  /// No description provided for @photosetPackSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Photosets'**
  String get photosetPackSectionTitle;

  /// No description provided for @photosetListSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Photoset List'**
  String get photosetListSectionTitle;

  /// No description provided for @photosetListNameHeader.
  ///
  /// In en, this message translates to:
  /// **'Set name'**
  String get photosetListNameHeader;

  /// No description provided for @photosetListCountHeader.
  ///
  /// In en, this message translates to:
  /// **'Photos (picked / total)'**
  String get photosetListCountHeader;

  /// No description provided for @singlePhotosetSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Photoset'**
  String get singlePhotosetSectionTitle;

  /// No description provided for @scanPhotosets.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scanPhotosets;

  /// No description provided for @pickPhotosets.
  ///
  /// In en, this message translates to:
  /// **'Pick'**
  String get pickPhotosets;

  /// No description provided for @photosetPickedOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{picked} / {total}'**
  String photosetPickedOfTotal(int picked, String total);

  /// No description provided for @photosetScanProgress.
  ///
  /// In en, this message translates to:
  /// **'Photosets scanned: {done} / {total}'**
  String photosetScanProgress(int done, int total);

  /// No description provided for @photosetPickProgress.
  ///
  /// In en, this message translates to:
  /// **'Photos picked: {done} / {total}'**
  String photosetPickProgress(int done, int total);

  /// No description provided for @pickOptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Pick photos'**
  String get pickOptionsTitle;

  /// No description provided for @pickExtremesLabel.
  ///
  /// In en, this message translates to:
  /// **'Make sure highest and lowest resolution photos are included'**
  String get pickExtremesLabel;

  /// No description provided for @pickCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Number of photos'**
  String get pickCountLabel;

  /// No description provided for @pickStrategyPerSet.
  ///
  /// In en, this message translates to:
  /// **'In proportion to each set\'s size'**
  String get pickStrategyPerSet;

  /// No description provided for @pickStrategyWholePack.
  ///
  /// In en, this message translates to:
  /// **'Evenly across all the photos as one set'**
  String get pickStrategyWholePack;

  /// No description provided for @photosetPackNoPhotosets.
  ///
  /// In en, this message translates to:
  /// **'There are no photosets. Pick the folder and scan it.'**
  String get photosetPackNoPhotosets;

  /// No description provided for @singlePhotosetNoPhotosets.
  ///
  /// In en, this message translates to:
  /// **'There are no photos. Pick the folder and scan it.'**
  String get singlePhotosetNoPhotosets;

  /// No description provided for @photosetSkippedEntries.
  ///
  /// In en, this message translates to:
  /// **'Not photosets: {entries}'**
  String photosetSkippedEntries(String entries);

  /// No description provided for @photosetUnreadPhotos.
  ///
  /// In en, this message translates to:
  /// **'Could not read the dimensions of: {names}'**
  String photosetUnreadPhotos(String names);

  /// No description provided for @photosetNameCollisions.
  ///
  /// In en, this message translates to:
  /// **'Names that collide: {names}'**
  String photosetNameCollisions(String names);

  /// No description provided for @photosetNotCopied.
  ///
  /// In en, this message translates to:
  /// **'Could not copy: {names}'**
  String photosetNotCopied(String names);

  /// No description provided for @photosetEmptySets.
  ///
  /// In en, this message translates to:
  /// **'Sets with no photos: {names}'**
  String photosetEmptySets(String names);

  /// No description provided for @photosetPackSourceEmpty.
  ///
  /// In en, this message translates to:
  /// **'Pick the folder with the photosets first.'**
  String get photosetPackSourceEmpty;

  /// No description provided for @singlePhotosetSourceEmpty.
  ///
  /// In en, this message translates to:
  /// **'Pick the folder with the photos first.'**
  String get singlePhotosetSourceEmpty;

  /// No description provided for @photosetSourceNotFound.
  ///
  /// In en, this message translates to:
  /// **'The picked folder was not found.'**
  String get photosetSourceNotFound;

  /// No description provided for @photosetSourceNotReadable.
  ///
  /// In en, this message translates to:
  /// **'Could not read the picked folder.'**
  String get photosetSourceNotReadable;

  /// No description provided for @imageFolderSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get imageFolderSectionTitle;

  /// No description provided for @imageFolderCount.
  ///
  /// In en, this message translates to:
  /// **'{count} images'**
  String imageFolderCount(int count);

  /// No description provided for @imageFolderNoImages.
  ///
  /// In en, this message translates to:
  /// **'There are no images. Pick the folder and scan it.'**
  String get imageFolderNoImages;

  /// No description provided for @imageFolderNotImages.
  ///
  /// In en, this message translates to:
  /// **'Not images: {names}'**
  String imageFolderNotImages(String names);

  /// No description provided for @imageFolderCopyProgress.
  ///
  /// In en, this message translates to:
  /// **'Images copied: {done} / {total}'**
  String imageFolderCopyProgress(int done, int total);

  /// No description provided for @imageFolderSourceEmpty.
  ///
  /// In en, this message translates to:
  /// **'Pick the folder with the images first.'**
  String get imageFolderSourceEmpty;

  /// No description provided for @videoFolderLabel.
  ///
  /// In en, this message translates to:
  /// **'Folder with the videos'**
  String get videoFolderLabel;

  /// No description provided for @totalSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Total size'**
  String get totalSizeLabel;

  /// No description provided for @videoCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videoCountLabel;

  /// No description provided for @videoResolutionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Resolutions'**
  String get videoResolutionsLabel;

  /// No description provided for @videoFormatsLabel.
  ///
  /// In en, this message translates to:
  /// **'Formats'**
  String get videoFormatsLabel;

  /// No description provided for @videoPackSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Videos and screenshots'**
  String get videoPackSectionTitle;

  /// No description provided for @fileNameLabel.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get fileNameLabel;

  /// No description provided for @scanVideos.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scanVideos;

  /// No description provided for @noVideos.
  ///
  /// In en, this message translates to:
  /// **'There are no videos. Pick the folder and scan it.'**
  String get noVideos;

  /// No description provided for @videoSkippedFiles.
  ///
  /// In en, this message translates to:
  /// **'Not videos: {names}'**
  String videoSkippedFiles(String names);

  /// No description provided for @videoUnprobedFiles.
  ///
  /// In en, this message translates to:
  /// **'Could not probe: {names}'**
  String videoUnprobedFiles(String names);

  /// No description provided for @videoEmptyFolders.
  ///
  /// In en, this message translates to:
  /// **'Folders with no videos: {names}'**
  String videoEmptyFolders(String names);

  /// No description provided for @videoUnreadableFolders.
  ///
  /// In en, this message translates to:
  /// **'Folders that could not be read: {names}'**
  String videoUnreadableFolders(String names);

  /// No description provided for @videoSourceEmpty.
  ///
  /// In en, this message translates to:
  /// **'Pick the folder with the videos first.'**
  String get videoSourceEmpty;

  /// No description provided for @videoSourceNotFound.
  ///
  /// In en, this message translates to:
  /// **'The picked folder was not found.'**
  String get videoSourceNotFound;

  /// No description provided for @videoSourceNotReadable.
  ///
  /// In en, this message translates to:
  /// **'Could not read the picked folder.'**
  String get videoSourceNotReadable;

  /// No description provided for @generatePackImages.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generatePackImages;

  /// No description provided for @screenlistLabel.
  ///
  /// In en, this message translates to:
  /// **'Screenlist'**
  String get screenlistLabel;

  /// No description provided for @screenshotsLabel.
  ///
  /// In en, this message translates to:
  /// **'Screenshots'**
  String get screenshotsLabel;

  /// No description provided for @imagesFailedFiles.
  ///
  /// In en, this message translates to:
  /// **'Could not create images for: {names}'**
  String imagesFailedFiles(String names);

  /// No description provided for @posterImageLabel.
  ///
  /// In en, this message translates to:
  /// **'Poster image'**
  String get posterImageLabel;

  /// No description provided for @videoThumbnailLabel.
  ///
  /// In en, this message translates to:
  /// **'Video thumbnail'**
  String get videoThumbnailLabel;

  /// No description provided for @noImageSelected.
  ///
  /// In en, this message translates to:
  /// **'No image selected'**
  String get noImageSelected;

  /// No description provided for @noVideoSelected.
  ///
  /// In en, this message translates to:
  /// **'No video selected'**
  String get noVideoSelected;

  /// No description provided for @posterHint.
  ///
  /// In en, this message translates to:
  /// **'Click to choose an image.'**
  String get posterHint;

  /// No description provided for @videoHint.
  ///
  /// In en, this message translates to:
  /// **'Click to choose a video.'**
  String get videoHint;

  /// No description provided for @chooseImage.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get chooseImage;

  /// No description provided for @pasteFromUrl.
  ///
  /// In en, this message translates to:
  /// **'Paste from URL'**
  String get pasteFromUrl;

  /// No description provided for @nothingToPaste.
  ///
  /// In en, this message translates to:
  /// **'There is nothing in the clipboard.'**
  String get nothingToPaste;

  /// No description provided for @removeImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get removeImage;

  /// No description provided for @posterFileNotFound.
  ///
  /// In en, this message translates to:
  /// **'The poster file was not found.'**
  String get posterFileNotFound;

  /// No description provided for @posterWrongFormat.
  ///
  /// In en, this message translates to:
  /// **'The poster must be a JPG or WebP file.'**
  String get posterWrongFormat;

  /// No description provided for @posterUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'The clipboard text is not an http or https link.'**
  String get posterUrlInvalid;

  /// No description provided for @posterDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not download the image.'**
  String get posterDownloadFailed;

  /// No description provided for @posterWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not write the poster.'**
  String get posterWriteFailed;

  /// No description provided for @posterRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove the poster.'**
  String get posterRemoveFailed;

  /// No description provided for @screenshotsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Screenshots'**
  String get screenshotsSectionTitle;

  /// No description provided for @screenshotCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Number of screenshots'**
  String get screenshotCountLabel;

  /// No description provided for @generateScreenshots.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generateScreenshots;

  /// No description provided for @regenerateScreenshots.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get regenerateScreenshots;

  /// No description provided for @noScreenshots.
  ///
  /// In en, this message translates to:
  /// **'No screenshots generated.'**
  String get noScreenshots;

  /// No description provided for @selectVideoFirst.
  ///
  /// In en, this message translates to:
  /// **'Select a video first'**
  String get selectVideoFirst;

  /// No description provided for @screenshotFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the screenshots.'**
  String get screenshotFailed;

  /// No description provided for @mtnNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'mtn is not installed. Install it to create screenlists.'**
  String get mtnNotAvailable;

  /// No description provided for @screenlistFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the screenlist.'**
  String get screenlistFailed;

  /// No description provided for @uploadSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Upload images'**
  String get uploadSectionTitle;

  /// No description provided for @uploadNeedsImagesFirst.
  ///
  /// In en, this message translates to:
  /// **'Add a poster and generate screenshots first'**
  String get uploadNeedsImagesFirst;

  /// No description provided for @uploadNeedsScreenlistsFirst.
  ///
  /// In en, this message translates to:
  /// **'Add a poster and generate screenlists first'**
  String get uploadNeedsScreenlistsFirst;

  /// No description provided for @uploadButton.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get uploadButton;

  /// No description provided for @uploadProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total}'**
  String uploadProgress(int done, int total);

  /// No description provided for @uptoodaNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'uptooda is not available. It is part of the app, so the installation is incomplete.'**
  String get uptoodaNotAvailable;

  /// No description provided for @imagesManifestFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not write images.json. Check the path and permissions.'**
  String get imagesManifestFailed;

  /// No description provided for @hosterApiKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'Set up the API key in Settings → Integration'**
  String get hosterApiKeyRequired;

  /// No description provided for @messageSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get messageSectionTitle;

  /// No description provided for @generateMessage.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generateMessage;

  /// No description provided for @messageNeedsImagesFirst.
  ///
  /// In en, this message translates to:
  /// **'Upload the images first'**
  String get messageNeedsImagesFirst;

  /// No description provided for @noMessage.
  ///
  /// In en, this message translates to:
  /// **'Nothing generated yet.'**
  String get noMessage;

  /// No description provided for @includeAppSignature.
  ///
  /// In en, this message translates to:
  /// **'Include the \"Made with Release Prepper\" line'**
  String get includeAppSignature;

  /// No description provided for @screenshotLayoutLabel.
  ///
  /// In en, this message translates to:
  /// **'Screenshot block layout'**
  String get screenshotLayoutLabel;

  /// No description provided for @screenshotLayoutByHoster.
  ///
  /// In en, this message translates to:
  /// **'By hoster, then by video'**
  String get screenshotLayoutByHoster;

  /// No description provided for @screenshotLayoutByItem.
  ///
  /// In en, this message translates to:
  /// **'By video, then by hoster'**
  String get screenshotLayoutByItem;

  /// No description provided for @templateNotFound.
  ///
  /// In en, this message translates to:
  /// **'There is no template for this tracker and release type.'**
  String get templateNotFound;

  /// No description provided for @styleNotFound.
  ///
  /// In en, this message translates to:
  /// **'There is no style for this tracker.'**
  String get styleNotFound;

  /// No description provided for @templateInvalid.
  ///
  /// In en, this message translates to:
  /// **'The template is not valid: a section is not closed on the same line.'**
  String get templateInvalid;

  /// No description provided for @messageSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not write message.txt. Check the path and permissions.'**
  String get messageSaveFailed;

  /// No description provided for @fieldNotFilled.
  ///
  /// In en, this message translates to:
  /// **'{label} is required.'**
  String fieldNotFilled(String label);

  /// No description provided for @productionDateInvalid.
  ///
  /// In en, this message translates to:
  /// **'{label} must be YYYY-MM-DD, YYYY-MM or YYYY.'**
  String productionDateInvalid(String label);

  /// No description provided for @messageValidationFailed.
  ///
  /// In en, this message translates to:
  /// **'Cannot generate the message:\n{problems}'**
  String messageValidationFailed(String problems);

  /// No description provided for @copyToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy to clipboard'**
  String get copyToClipboard;

  /// No description provided for @unsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get unsavedChanges;

  /// No description provided for @releaseSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the release. Check the path and permissions.'**
  String get releaseSaveFailed;

  /// No description provided for @closeUnsavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get closeUnsavedTitle;

  /// No description provided for @closeUnsavedMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes in {title}. Close without saving?'**
  String closeUnsavedMessage(String title);

  /// No description provided for @closeWithoutSaving.
  ///
  /// In en, this message translates to:
  /// **'Close without saving'**
  String get closeWithoutSaving;

  /// No description provided for @saveAndClose.
  ///
  /// In en, this message translates to:
  /// **'Save and close'**
  String get saveAndClose;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @settingsGeneralSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneralSectionTitle;

  /// No description provided for @settingsReleasesSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Releases'**
  String get settingsReleasesSectionTitle;

  /// No description provided for @settingsIntegrationSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Integration'**
  String get settingsIntegrationSectionTitle;

  /// No description provided for @appLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get appLanguageLabel;

  /// No description provided for @defaultReleaseDirectoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Default release directory'**
  String get defaultReleaseDirectoryLabel;

  /// No description provided for @defaultTorrentPrivateLabel.
  ///
  /// In en, this message translates to:
  /// **'New releases produce private torrents by default'**
  String get defaultTorrentPrivateLabel;

  /// No description provided for @defaultIncludeAppSignatureLabel.
  ///
  /// In en, this message translates to:
  /// **'New releases include the \"Made with Release Prepper\" line'**
  String get defaultIncludeAppSignatureLabel;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System language'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageRussian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get languageRussian;

  /// No description provided for @stashdbApiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'StashDB API key'**
  String get stashdbApiKeyLabel;

  /// No description provided for @postimagesApiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Postimages API key'**
  String get postimagesApiKeyLabel;

  /// No description provided for @pornolabUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Pornolab username'**
  String get pornolabUsernameLabel;

  /// No description provided for @pornolabPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Pornolab password'**
  String get pornolabPasswordLabel;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get loginButton;

  /// No description provided for @logoutButton.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logoutButton;

  /// No description provided for @captchaCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get captchaCodeLabel;

  /// No description provided for @secretStoreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The credential store is not available on this machine. Enable it — the Secret Service on Linux, the Keychain on macOS, Credential Manager on Windows — or allow storing these values plainly, which is not recommended.'**
  String get secretStoreUnavailable;

  /// No description provided for @secretStoreNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'The credential store is not available, and storing values plainly is not allowed.'**
  String get secretStoreNotAvailable;

  /// No description provided for @allowPlainSecretsLabel.
  ///
  /// In en, this message translates to:
  /// **'Store values plainly in settings.json (not recommended)'**
  String get allowPlainSecretsLabel;

  /// No description provided for @secretStoredPlainly.
  ///
  /// In en, this message translates to:
  /// **'This value is stored plainly in settings.json.'**
  String get secretStoredPlainly;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the settings.'**
  String get settingsSaveFailed;

  /// No description provided for @stashImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import from Stash DB'**
  String get stashImportTitle;

  /// No description provided for @stashSceneInputLabel.
  ///
  /// In en, this message translates to:
  /// **'StashDB scene URL or ID'**
  String get stashSceneInputLabel;

  /// No description provided for @stashFetchButton.
  ///
  /// In en, this message translates to:
  /// **'Fetch'**
  String get stashFetchButton;

  /// No description provided for @stashApplyButton.
  ///
  /// In en, this message translates to:
  /// **'Apply the selected values'**
  String get stashApplyButton;

  /// No description provided for @stashInputInvalid.
  ///
  /// In en, this message translates to:
  /// **'That is neither a StashDB scene ID nor a link that ends with one.'**
  String get stashInputInvalid;

  /// No description provided for @stashNoApiKey.
  ///
  /// In en, this message translates to:
  /// **'Enter the StashDB API key in Settings to fetch a scene.'**
  String get stashNoApiKey;

  /// No description provided for @stashRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not reach StashDB.'**
  String get stashRequestFailed;

  /// No description provided for @stashBadResponse.
  ///
  /// In en, this message translates to:
  /// **'The answer from StashDB could not be read.'**
  String get stashBadResponse;

  /// No description provided for @stashGraphqlError.
  ///
  /// In en, this message translates to:
  /// **'StashDB reported an error.'**
  String get stashGraphqlError;

  /// No description provided for @stashSceneNotFound.
  ///
  /// In en, this message translates to:
  /// **'StashDB has no scene with that ID.'**
  String get stashSceneNotFound;

  /// No description provided for @stashImportNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Import notes'**
  String get stashImportNotesTitle;

  /// No description provided for @stashNoteSiteNumberStripped.
  ///
  /// In en, this message translates to:
  /// **'{label} in StashDB contains its site number, so it has been stripped from the title:'**
  String stashNoteSiteNumberStripped(String label);

  /// No description provided for @stashNoteDomainFromOtherUrl.
  ///
  /// In en, this message translates to:
  /// **'{label}: StashDB has no link in the Primary sources category, so the domain was read from this link:'**
  String stashNoteDomainFromOtherUrl(String label);

  /// No description provided for @recentReleases.
  ///
  /// In en, this message translates to:
  /// **'Recent releases'**
  String get recentReleases;

  /// No description provided for @noRecentReleases.
  ///
  /// In en, this message translates to:
  /// **'No releases have been opened yet.'**
  String get noRecentReleases;

  /// No description provided for @recentPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get recentPathLabel;

  /// No description provided for @recentSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get recentSourceLabel;

  /// No description provided for @recentCreatedDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Creation date'**
  String get recentCreatedDateLabel;

  /// No description provided for @recentLastEditDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Last edit date'**
  String get recentLastEditDateLabel;

  /// No description provided for @recentFolderUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The folder is not there.'**
  String get recentFolderUnavailable;

  /// No description provided for @recentWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the recent releases list. Check the path and permissions.'**
  String get recentWriteFailed;

  /// No description provided for @systemCheck.
  ///
  /// In en, this message translates to:
  /// **'System Check'**
  String get systemCheck;

  /// No description provided for @systemCheckToolLabel.
  ///
  /// In en, this message translates to:
  /// **'Tool'**
  String get systemCheckToolLabel;

  /// No description provided for @systemCheckResultLabel.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get systemCheckResultLabel;

  /// No description provided for @systemCheckToolNotFound.
  ///
  /// In en, this message translates to:
  /// **'{tool} not found.'**
  String systemCheckToolNotFound(String tool);

  /// No description provided for @systemCheckRunFailed.
  ///
  /// In en, this message translates to:
  /// **'{tool} exited with code {code}.'**
  String systemCheckRunFailed(String tool, int code);

  /// No description provided for @systemCheckRunTimeout.
  ///
  /// In en, this message translates to:
  /// **'{tool} timed out.'**
  String systemCheckRunTimeout(Object tool);

  /// No description provided for @systemCheckNoOutput.
  ///
  /// In en, this message translates to:
  /// **'{tool} ran but printed nothing.'**
  String systemCheckNoOutput(Object tool);

  /// No description provided for @torrentSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Torrent'**
  String get torrentSectionTitle;

  /// No description provided for @torrentPickFileFirst.
  ///
  /// In en, this message translates to:
  /// **'Pick a file first'**
  String get torrentPickFileFirst;

  /// No description provided for @torrentPickFolderFirst.
  ///
  /// In en, this message translates to:
  /// **'Pick a folder first'**
  String get torrentPickFolderFirst;

  /// No description provided for @torrentButton.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get torrentButton;

  /// No description provided for @torrentProgress.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String torrentProgress(int percent);

  /// No description provided for @torrentSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed: {speed}'**
  String torrentSpeed(String speed);

  /// No description provided for @torrentEta.
  ///
  /// In en, this message translates to:
  /// **'ETA: {eta}'**
  String torrentEta(String eta);

  /// No description provided for @torrentCreated.
  ///
  /// In en, this message translates to:
  /// **'Created {path}'**
  String torrentCreated(String path);

  /// No description provided for @torrentAlreadyCreated.
  ///
  /// In en, this message translates to:
  /// **'Already created: {path}'**
  String torrentAlreadyCreated(String path);

  /// No description provided for @torrentPrivateLabel.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get torrentPrivateLabel;

  /// No description provided for @torrentPrivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Change the Private flag?'**
  String get torrentPrivateTitle;

  /// No description provided for @torrentPrivateMessage.
  ///
  /// In en, this message translates to:
  /// **'The torrent file already exists. Do you want to change its Private flag to {value}?'**
  String torrentPrivateMessage(String value);

  /// No description provided for @torrentPrivateValuePrivate.
  ///
  /// In en, this message translates to:
  /// **'private'**
  String get torrentPrivateValuePrivate;

  /// No description provided for @torrentPrivateValueNotPrivate.
  ///
  /// In en, this message translates to:
  /// **'not private'**
  String get torrentPrivateValueNotPrivate;

  /// No description provided for @torrentPrivateConfirm.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get torrentPrivateConfirm;

  /// No description provided for @torrentPrivateNotReadable.
  ///
  /// In en, this message translates to:
  /// **'The file is not a readable torrent, so its flag cannot be read.'**
  String get torrentPrivateNotReadable;

  /// No description provided for @mkbrrNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'mkbrr is not available. It is part of the app, so the installation is incomplete.'**
  String get mkbrrNotAvailable;

  /// No description provided for @mkbrrRunFailed.
  ///
  /// In en, this message translates to:
  /// **'mkbrr exited with code {code}.'**
  String mkbrrRunFailed(int code);

  /// No description provided for @mkbrrRunTimeout.
  ///
  /// In en, this message translates to:
  /// **'mkbrr timed out.'**
  String get mkbrrRunTimeout;

  /// No description provided for @mkbrrModifyFailed.
  ///
  /// In en, this message translates to:
  /// **'mkbrr could not change the flag: {reason}.'**
  String mkbrrModifyFailed(String reason);

  /// No description provided for @folderOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the folder.'**
  String get folderOpenFailed;

  /// No description provided for @draftSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Upload draft to tracker'**
  String get draftSectionTitle;

  /// No description provided for @draftUploadButton.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get draftUploadButton;

  /// No description provided for @parentForumLabel.
  ///
  /// In en, this message translates to:
  /// **'Parent forum'**
  String get parentForumLabel;

  /// No description provided for @parentForumInvalid.
  ///
  /// In en, this message translates to:
  /// **'{label} must be a full forum URL with an f parameter.'**
  String parentForumInvalid(String label);

  /// No description provided for @draftLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Draft link on tracker'**
  String get draftLinkLabel;

  /// No description provided for @draftNeedsMessageFirst.
  ///
  /// In en, this message translates to:
  /// **'Generate a message first'**
  String get draftNeedsMessageFirst;

  /// No description provided for @draftNeedsLoginFirst.
  ///
  /// In en, this message translates to:
  /// **'Log in in Settings → Integration'**
  String get draftNeedsLoginFirst;

  /// No description provided for @draftNeedsForumFirst.
  ///
  /// In en, this message translates to:
  /// **'Set the parent forum'**
  String get draftNeedsForumFirst;

  /// No description provided for @draftRecreated.
  ///
  /// In en, this message translates to:
  /// **'The draft the stored link pointed to is no longer on the site, so a new one was created.'**
  String get draftRecreated;

  /// No description provided for @pornolabNeedsCredentials.
  ///
  /// In en, this message translates to:
  /// **'Enter the username and the password'**
  String get pornolabNeedsCredentials;

  /// No description provided for @pornolabLoginAccepted.
  ///
  /// In en, this message translates to:
  /// **'Login accepted.'**
  String get pornolabLoginAccepted;

  /// No description provided for @pornolabLoginRefused.
  ///
  /// In en, this message translates to:
  /// **'The site did not accept the username and the password.'**
  String get pornolabLoginRefused;

  /// No description provided for @pornolabNeedsCaptcha.
  ///
  /// In en, this message translates to:
  /// **'The site is asking for a code.'**
  String get pornolabNeedsCaptcha;

  /// No description provided for @pornolabLoginNoCookie.
  ///
  /// In en, this message translates to:
  /// **'The login was accepted and the answer gave no cookie.'**
  String get pornolabLoginNoCookie;

  /// No description provided for @pornolabCookieRefused.
  ///
  /// In en, this message translates to:
  /// **'The site did not accept the cookie. Log in again in Settings → Integration.'**
  String get pornolabCookieRefused;

  /// No description provided for @pornolabNoToken.
  ///
  /// In en, this message translates to:
  /// **'The page did not give a form token. Try again.'**
  String get pornolabNoToken;

  /// No description provided for @pornolabTokenRejected.
  ///
  /// In en, this message translates to:
  /// **'The site did not accept the form token. Try again.'**
  String get pornolabTokenRejected;

  /// No description provided for @pornolabDraftGone.
  ///
  /// In en, this message translates to:
  /// **'The site has no draft with that id, and it did not create a new one.'**
  String get pornolabDraftGone;

  /// No description provided for @pornolabSiteError.
  ///
  /// In en, this message translates to:
  /// **'The site reported an error.'**
  String get pornolabSiteError;

  /// No description provided for @pornolabBadResponse.
  ///
  /// In en, this message translates to:
  /// **'The answer from the site could not be read.'**
  String get pornolabBadResponse;

  /// No description provided for @pornolabRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the site.'**
  String get pornolabRequestFailed;

  /// No description provided for @pornolabTimeout.
  ///
  /// In en, this message translates to:
  /// **'The request to the site took too long.'**
  String get pornolabTimeout;

  /// No description provided for @linkOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the link in the browser.'**
  String get linkOpenFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
