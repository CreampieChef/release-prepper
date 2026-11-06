// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get file => 'File';

  @override
  String get newRelease => 'New Release';

  @override
  String get newReleaseShortcut => 'Ctrl+N';

  @override
  String get help => 'Help';

  @override
  String get about => 'About';

  @override
  String get close => 'Close';

  @override
  String get allTabsClosed => 'All tabs are closed.';

  @override
  String get releaseDetails => 'Release details go here.';

  @override
  String closeTab(String title) {
    return 'Close $title tab';
  }

  @override
  String get closeTabItem => 'Close tab';

  @override
  String get closeTabShortcut => 'Ctrl+W';

  @override
  String get releaseNameLabel => 'Name';

  @override
  String get savePathLabel => 'Save path';

  @override
  String get chooseSavePath => 'Choose folder';

  @override
  String get trackerLabel => 'Tracker';

  @override
  String get releaseTypeLabel => 'Release type';

  @override
  String get releaseTypeSingleVideo => 'Single video';

  @override
  String get releaseTypeVideoPack => 'Video pack (Beta)';

  @override
  String get releaseTypeSinglePhotoset => 'Single photoset (Beta)';

  @override
  String get releaseTypePhotosetPack => 'Photoset pack (Beta)';

  @override
  String get releaseTypeImageFolderUpload => 'Image folder upload (Beta)';

  @override
  String get createButton => 'Create';

  @override
  String get releaseNameRequired => 'Enter a release name.';

  @override
  String get releaseNameInvalid =>
      'Use a valid folder name. Avoid / \\ : * ? \" < > |, control characters, reserved Windows names, and a trailing space or period.';

  @override
  String get savePathRequired => 'Choose a save path.';

  @override
  String get releaseAlreadyExists =>
      'A folder with this release name already exists.';

  @override
  String get releaseCreated => 'Release folder created.';

  @override
  String get releaseCreationFailed =>
      'Could not create the release. Check the path and permissions.';

  @override
  String get folderPickerFailed => 'Could not open the folder picker.';

  @override
  String get cloneRelease => 'Clone Release';

  @override
  String cloneSourceLabel(String name) {
    return 'Source release: $name';
  }

  @override
  String get cloneNameMustDiffer =>
      'The clone name must be different from the source release name.';

  @override
  String get cloneNoPosterWarning =>
      'The source release has no poster, so the clone will have none. It is best to upload the poster first, so the same poster does not have to be uploaded more than once.';

  @override
  String get clonePosterNotUploadedWarning =>
      'The poster has not been uploaded, so its links cannot be copied. It is best to upload the poster first, so the same poster does not have to be uploaded more than once.';

  @override
  String get openRelease => 'Open Release';

  @override
  String get openReleaseShortcut => 'Ctrl+O';

  @override
  String get chooseReleaseFolder => 'Choose a release folder';

  @override
  String get releaseManifestNotFound =>
      'The selected folder does not contain release.json.';

  @override
  String get releaseMetadataInvalid => 'The release.json file is not valid.';

  @override
  String get openReleaseError => 'Could not open the release.';

  @override
  String get chooseAnotherFolder => 'Choose another folder';

  @override
  String get save => 'Save';

  @override
  String get saveShortcut => 'Ctrl+S';

  @override
  String get movieFilePathLabel => 'Path to video';

  @override
  String get chooseFile => 'Choose file';

  @override
  String get filePickerFailed => 'Could not open the file picker.';

  @override
  String get movieFileNotFound => 'The movie file was not found.';

  @override
  String get probeToolNotAvailable =>
      'ffprobe is not installed. Install it to read file metadata.';

  @override
  String get probeFailed => 'Could not read the file metadata.';

  @override
  String get ffmpegNotAvailable =>
      'ffmpeg is not installed. Install it to work with images.';

  @override
  String get thumbnailFailed => 'Could not create the thumbnail.';

  @override
  String get castLabel => 'Cast';

  @override
  String get videoTitleLabel => 'Video title';

  @override
  String get modelLabel => 'Model';

  @override
  String get setNameLabel => 'Set name';

  @override
  String get siteNumberLabel => 'Site number (optional)';

  @override
  String get subsiteAndSiteLabel => 'Subsite and site';

  @override
  String get productionDateLabel => 'Production date';

  @override
  String get chooseDate => 'Choose date';

  @override
  String get genreTagsLabel => 'Genre (tags)';

  @override
  String get fileSizeLabel => 'File size';

  @override
  String fileSizeDisplay(String human, String bytes) {
    return '$human ($bytes bytes)';
  }

  @override
  String get durationLabel => 'Duration';

  @override
  String get durationHint => 'hh:mm:ss';

  @override
  String get videoTypeLabel => 'Video type';

  @override
  String get videoQualityLabel => 'Video quality';

  @override
  String get videoFormatLabel => 'Video format';

  @override
  String get videoStreamLabel => 'Video';

  @override
  String get audioStreamLabel => 'Audio';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get additionalInfoLabel => 'Additional information (optional)';

  @override
  String get photosetPackFolderLabel => 'Folder with the photosets';

  @override
  String get singlePhotosetFolderLabel => 'Folder with the photos';

  @override
  String get imageFolderFolderLabel => 'Folder with the images';

  @override
  String get chooseFolder => 'Choose folder';

  @override
  String get siteOrJournalLabel => 'Site or journal';

  @override
  String get periodLabel => 'Period';

  @override
  String get photosetCountLabel => 'Photosets';

  @override
  String get totalPhotoCountLabel => 'Photos (total)';

  @override
  String get minResolutionLabel => 'Minimum photo resolution';

  @override
  String get maxResolutionLabel => 'Maximum photo resolution';

  @override
  String get imageFormatsLabel => 'Image formats';

  @override
  String get imageCountLabel => 'Images (total)';

  @override
  String get minImageResolutionLabel => 'Minimum image resolution';

  @override
  String get maxImageResolutionLabel => 'Maximum image resolution';

  @override
  String get columnTitleReleaseInfo => 'Release Info';

  @override
  String get columnTitleVideo => 'Video';

  @override
  String get columnTitleSourceFolder => 'Source folder';

  @override
  String get columnTitlePhotosets => 'Photosets';

  @override
  String get columnTitleImages => 'Images';

  @override
  String get photosetPackSectionTitle => 'Photosets';

  @override
  String get singlePhotosetSectionTitle => 'Photoset';

  @override
  String get scanPhotosets => 'Scan';

  @override
  String get pickPhotosets => 'Pick';

  @override
  String photosetPhotoCount(int count) {
    return '$count photos';
  }

  @override
  String photosetPickedCount(int count) {
    return '$count picked';
  }

  @override
  String get photosetPackNoPhotosets =>
      'There are no photosets. Pick the folder and scan it.';

  @override
  String get singlePhotosetNoPhotosets =>
      'There are no photos. Pick the folder and scan it.';

  @override
  String photosetSkippedEntries(String entries) {
    return 'Not photosets: $entries';
  }

  @override
  String photosetUnreadPhotos(String names) {
    return 'Could not read the dimensions of: $names';
  }

  @override
  String photosetNameCollisions(String names) {
    return 'Names that collide: $names';
  }

  @override
  String photosetNotCopied(String names) {
    return 'Could not copy: $names';
  }

  @override
  String photosetEmptySets(String names) {
    return 'Sets with no photos: $names';
  }

  @override
  String get photosetPackSourceEmpty =>
      'Pick the folder with the photosets first.';

  @override
  String get singlePhotosetSourceEmpty =>
      'Pick the folder with the photos first.';

  @override
  String get photosetSourceNotFound => 'The picked folder was not found.';

  @override
  String get photosetSourceNotReadable => 'Could not read the picked folder.';

  @override
  String get imageFolderSectionTitle => 'Images';

  @override
  String imageFolderCount(int count) {
    return '$count images';
  }

  @override
  String get imageFolderNoImages =>
      'There are no images. Pick the folder and scan it.';

  @override
  String imageFolderNotImages(String names) {
    return 'Not images: $names';
  }

  @override
  String get imageFolderSourceEmpty => 'Pick the folder with the images first.';

  @override
  String get videoFolderLabel => 'Folder with the videos';

  @override
  String get totalSizeLabel => 'Total size';

  @override
  String get videoCountLabel => 'Videos';

  @override
  String get videoResolutionsLabel => 'Resolutions';

  @override
  String get videoFormatsLabel => 'Formats';

  @override
  String get videoPackSectionTitle => 'Videos and screenshots';

  @override
  String get fileNameLabel => 'File name';

  @override
  String get scanVideos => 'Scan';

  @override
  String get noVideos => 'There are no videos. Pick the folder and scan it.';

  @override
  String videoSkippedFiles(String names) {
    return 'Not videos: $names';
  }

  @override
  String videoUnprobedFiles(String names) {
    return 'Could not probe: $names';
  }

  @override
  String videoEmptyFolders(String names) {
    return 'Folders with no videos: $names';
  }

  @override
  String videoUnreadableFolders(String names) {
    return 'Folders that could not be read: $names';
  }

  @override
  String get videoSourceEmpty => 'Pick the folder with the videos first.';

  @override
  String get videoSourceNotFound => 'The picked folder was not found.';

  @override
  String get videoSourceNotReadable => 'Could not read the picked folder.';

  @override
  String get generatePackImages => 'Generate';

  @override
  String get screenlistLabel => 'Screenlist';

  @override
  String get screenshotsLabel => 'Screenshots';

  @override
  String imagesFailedFiles(String names) {
    return 'Could not create images for: $names';
  }

  @override
  String get posterImageLabel => 'Poster image';

  @override
  String get videoThumbnailLabel => 'Video thumbnail';

  @override
  String get noImageSelected => 'No image selected';

  @override
  String get noVideoSelected => 'No video selected';

  @override
  String get posterHint => 'Click to choose an image.';

  @override
  String get videoHint => 'Click to choose a video.';

  @override
  String get chooseImage => 'Choose image';

  @override
  String get pasteFromUrl => 'Paste from URL';

  @override
  String get nothingToPaste => 'There is nothing in the clipboard.';

  @override
  String get removeImage => 'Remove image';

  @override
  String get posterFileNotFound => 'The poster file was not found.';

  @override
  String get posterWrongFormat => 'The poster must be a JPG or WebP file.';

  @override
  String get posterUrlInvalid =>
      'The clipboard text is not an http or https link.';

  @override
  String get posterDownloadFailed => 'Could not download the image.';

  @override
  String get posterWriteFailed => 'Could not write the poster.';

  @override
  String get posterRemoveFailed => 'Could not remove the poster.';

  @override
  String get screenshotsSectionTitle => 'Screenshots';

  @override
  String get screenshotCountLabel => 'Number of screenshots';

  @override
  String get generateScreenshots => 'Generate';

  @override
  String get regenerateScreenshots => 'Regenerate';

  @override
  String get noScreenshots => 'No screenshots generated.';

  @override
  String get selectVideoFirst => 'Select a video first';

  @override
  String get screenshotFailed => 'Could not create the screenshots.';

  @override
  String get mtnNotAvailable =>
      'mtn is not installed. Install it to create screenlists.';

  @override
  String get screenlistFailed => 'Could not create the screenlist.';

  @override
  String get uploadSectionTitle => 'Upload images';

  @override
  String get uploadNeedsImagesFirst =>
      'Add a poster and generate screenshots first';

  @override
  String get uploadNeedsScreenlistsFirst =>
      'Add a poster and generate screenlists first';

  @override
  String get uploadButton => 'Upload';

  @override
  String uploadProgress(int done, int total) {
    return '$done / $total';
  }

  @override
  String get uptoodaNotAvailable =>
      'uptooda is not available. It is part of the app, so the installation is incomplete.';

  @override
  String get imagesManifestFailed =>
      'Could not write images.json. Check the path and permissions.';

  @override
  String get hosterApiKeyRequired =>
      'Set up the API key in Settings → Integration';

  @override
  String get messageSectionTitle => 'Message';

  @override
  String get generateMessage => 'Generate';

  @override
  String get messageNeedsImagesFirst => 'Upload the images first';

  @override
  String get noMessage => 'Nothing generated yet.';

  @override
  String get includeAppSignature =>
      'Include the \"Made with Release Prepper\" line';

  @override
  String get screenshotLayoutLabel => 'Screenshot block layout';

  @override
  String get screenshotLayoutByHoster => 'By hoster, then by video';

  @override
  String get screenshotLayoutByItem => 'By video, then by hoster';

  @override
  String get templateNotFound =>
      'There is no template for this tracker and release type.';

  @override
  String get styleNotFound => 'There is no style for this tracker.';

  @override
  String get templateInvalid =>
      'The template is not valid: a section is not closed on the same line.';

  @override
  String get messageSaveFailed =>
      'Could not write message.txt. Check the path and permissions.';

  @override
  String fieldNotFilled(String label) {
    return '$label is required.';
  }

  @override
  String productionDateInvalid(String label) {
    return '$label must be YYYY-MM-DD, YYYY-MM or YYYY.';
  }

  @override
  String messageValidationFailed(String problems) {
    return 'Cannot generate the message:\n$problems';
  }

  @override
  String get copyToClipboard => 'Copy to clipboard';

  @override
  String get unsavedChanges => 'Unsaved changes';

  @override
  String get releaseSaveFailed =>
      'Could not save the release. Check the path and permissions.';

  @override
  String get closeUnsavedTitle => 'Unsaved changes';

  @override
  String closeUnsavedMessage(String title) {
    return 'You have unsaved changes in $title. Close without saving?';
  }

  @override
  String get closeWithoutSaving => 'Close without saving';

  @override
  String get saveAndClose => 'Save and close';

  @override
  String get cancel => 'Cancel';

  @override
  String get settings => 'Settings';

  @override
  String get settingsGeneralSectionTitle => 'General';

  @override
  String get settingsIntegrationSectionTitle => 'Integration';

  @override
  String get appLanguageLabel => 'App language';

  @override
  String get defaultReleaseDirectoryLabel => 'Default release directory';

  @override
  String get languageSystem => 'System language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageRussian => 'Russian';

  @override
  String get stashdbApiKeyLabel => 'StashDB API key';

  @override
  String get postimagesApiKeyLabel => 'Postimages API key';

  @override
  String get pornolabUsernameLabel => 'Pornolab username';

  @override
  String get pornolabPasswordLabel => 'Pornolab password';

  @override
  String get loginButton => 'Log in';

  @override
  String get logoutButton => 'Log out';

  @override
  String get captchaCodeLabel => 'Code';

  @override
  String get secretStoreUnavailable =>
      'The credential store is not available on this machine. Enable it — the Secret Service on Linux, the Keychain on macOS, Credential Manager on Windows — or allow storing these values plainly, which is not recommended.';

  @override
  String get secretStoreNotAvailable =>
      'The credential store is not available, and storing values plainly is not allowed.';

  @override
  String get allowPlainSecretsLabel =>
      'Store values plainly in settings.json (not recommended)';

  @override
  String get secretStoredPlainly =>
      'This value is stored plainly in settings.json.';

  @override
  String get settingsSaveFailed => 'Could not save the settings.';

  @override
  String get stashImportTitle => 'Import from Stash DB';

  @override
  String get stashSceneInputLabel => 'StashDB scene URL or ID';

  @override
  String get stashFetchButton => 'Fetch';

  @override
  String get stashApplyButton => 'Apply the selected values';

  @override
  String get stashInputInvalid =>
      'That is neither a StashDB scene ID nor a link that ends with one.';

  @override
  String get stashNoApiKey =>
      'Enter the StashDB API key in Settings to fetch a scene.';

  @override
  String get stashRequestFailed => 'Could not reach StashDB.';

  @override
  String get stashBadResponse => 'The answer from StashDB could not be read.';

  @override
  String get stashGraphqlError => 'StashDB reported an error.';

  @override
  String get stashSceneNotFound => 'StashDB has no scene with that ID.';

  @override
  String get stashImportNotesTitle => 'Import notes';

  @override
  String stashNoteSiteNumberStripped(String label) {
    return '$label in StashDB contains its site number, so it has been stripped from the title:';
  }

  @override
  String stashNoteDomainFromOtherUrl(String label) {
    return '$label: StashDB has no link in the Primary sources category, so the domain was read from this link:';
  }

  @override
  String get recentReleases => 'Recent releases';

  @override
  String get noRecentReleases => 'No releases have been opened yet.';

  @override
  String get recentPathLabel => 'Path';

  @override
  String get recentSourceLabel => 'Source';

  @override
  String get recentCreatedDateLabel => 'Creation date';

  @override
  String get recentLastEditDateLabel => 'Last edit date';

  @override
  String get recentFolderUnavailable => 'The folder is not there.';

  @override
  String get recentWriteFailed =>
      'Could not save the recent releases list. Check the path and permissions.';

  @override
  String get systemCheck => 'System Check';

  @override
  String get systemCheckToolLabel => 'Tool';

  @override
  String get systemCheckResultLabel => 'Result';

  @override
  String systemCheckToolNotFound(String tool) {
    return '$tool not found.';
  }

  @override
  String systemCheckRunFailed(String tool, int code) {
    return '$tool exited with code $code.';
  }

  @override
  String systemCheckRunTimeout(Object tool) {
    return '$tool timed out.';
  }

  @override
  String systemCheckNoOutput(Object tool) {
    return '$tool ran but printed nothing.';
  }

  @override
  String get torrentSectionTitle => 'Torrent';

  @override
  String get torrentPickFileFirst => 'Pick a file first';

  @override
  String get torrentPickFolderFirst => 'Pick a folder first';

  @override
  String get torrentButton => 'Create';

  @override
  String torrentProgress(int percent) {
    return '$percent%';
  }

  @override
  String torrentSpeed(String speed) {
    return 'Speed: $speed';
  }

  @override
  String torrentEta(String eta) {
    return 'ETA: $eta';
  }

  @override
  String torrentCreated(String path) {
    return 'Created $path';
  }

  @override
  String torrentAlreadyCreated(String path) {
    return 'Already created: $path';
  }

  @override
  String get mkbrrNotAvailable =>
      'mkbrr is not available. It is part of the app, so the installation is incomplete.';

  @override
  String mkbrrRunFailed(int code) {
    return 'mkbrr exited with code $code.';
  }

  @override
  String get mkbrrRunTimeout => 'mkbrr timed out.';

  @override
  String get folderOpenFailed => 'Could not open the folder.';

  @override
  String get draftSectionTitle => 'Upload draft to tracker';

  @override
  String get draftUploadButton => 'Upload';

  @override
  String get parentForumLabel => 'Parent forum';

  @override
  String parentForumInvalid(String label) {
    return '$label must be a full forum URL with an f parameter.';
  }

  @override
  String get draftLinkLabel => 'Draft link on tracker';

  @override
  String get draftNeedsMessageFirst => 'Generate a message first';

  @override
  String get draftNeedsLoginFirst => 'Log in in Settings → Integration';

  @override
  String get draftNeedsForumFirst => 'Set the parent forum';

  @override
  String get draftRecreated =>
      'The draft the stored link pointed to is no longer on the site, so a new one was created.';

  @override
  String get pornolabNeedsCredentials => 'Enter the username and the password';

  @override
  String get pornolabLoginAccepted => 'Login accepted.';

  @override
  String get pornolabLoginRefused =>
      'The site did not accept the username and the password.';

  @override
  String get pornolabNeedsCaptcha => 'The site is asking for a code.';

  @override
  String get pornolabLoginNoCookie =>
      'The login was accepted and the answer gave no cookie.';

  @override
  String get pornolabCookieRefused =>
      'The site did not accept the cookie. Log in again in Settings → Integration.';

  @override
  String get pornolabNoToken =>
      'The page did not give a form token. Try again.';

  @override
  String get pornolabTokenRejected =>
      'The site did not accept the form token. Try again.';

  @override
  String get pornolabDraftGone =>
      'The site has no draft with that id, and it did not create a new one.';

  @override
  String get pornolabSiteError => 'The site reported an error.';

  @override
  String get pornolabBadResponse =>
      'The answer from the site could not be read.';

  @override
  String get pornolabRequestFailed => 'Could not reach the site.';

  @override
  String get pornolabTimeout => 'The request to the site took too long.';

  @override
  String get linkOpenFailed => 'Could not open the link in the browser.';
}
