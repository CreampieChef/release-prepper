// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get file => 'Файл';

  @override
  String get newRelease => 'Новый релиз';

  @override
  String get newReleaseShortcut => 'Ctrl+N';

  @override
  String get help => 'Справка';

  @override
  String get about => 'О программе';

  @override
  String get close => 'Закрыть';

  @override
  String get allTabsClosed => 'Все вкладки закрыты.';

  @override
  String get releaseDetails => 'Здесь будут сведения о релизе.';

  @override
  String closeTab(String title) {
    return 'Закрыть вкладку «$title»';
  }

  @override
  String get closeTabItem => 'Закрыть вкладку';

  @override
  String get closeTabShortcut => 'Ctrl+W';

  @override
  String get releaseNameLabel => 'Название';

  @override
  String get savePathLabel => 'Путь для сохранения';

  @override
  String get chooseSavePath => 'Выбрать папку';

  @override
  String get trackerLabel => 'Трекер';

  @override
  String get releaseTypeLabel => 'Тип релиза';

  @override
  String get releaseTypeSingleVideo => 'Одиночное видео';

  @override
  String get releaseTypeVideoPack => 'Пак видео (Beta)';

  @override
  String get releaseTypeSinglePhotoset => 'Одиночный фотосет (Beta)';

  @override
  String get releaseTypePhotosetPack => 'Пак фотосетов (Beta)';

  @override
  String get releaseTypeImageFolderUpload =>
      'Загрузка папки с изображениями (Beta)';

  @override
  String get createButton => 'Создать';

  @override
  String get releaseNameRequired => 'Введите название релиза.';

  @override
  String get releaseNameInvalid =>
      'Укажите допустимое имя папки. Не используйте / \\ : * ? \" < > |, управляющие символы, зарезервированные имена Windows, а также пробел или точку в конце.';

  @override
  String get savePathRequired => 'Выберите путь для сохранения.';

  @override
  String get releaseAlreadyExists => 'Папка с таким названием уже существует.';

  @override
  String get releaseCreated => 'Папка релиза создана.';

  @override
  String get releaseCreationFailed =>
      'Не удалось создать релиз. Проверьте путь и права доступа.';

  @override
  String get folderPickerFailed => 'Не удалось открыть окно выбора папки.';

  @override
  String get cloneRelease => 'Копия релиза';

  @override
  String cloneSourceLabel(String name) {
    return 'Исходный релиз: $name';
  }

  @override
  String get cloneNameMustDiffer =>
      'Название копии должно отличаться от названия исходного релиза.';

  @override
  String get cloneNoPosterWarning =>
      'В исходном релизе нет постера, поэтому в копии его не будет. Лучше сначала загрузить постер, чтобы один и тот же постер не загружать несколько раз.';

  @override
  String get clonePosterNotUploadedWarning =>
      'Постер не был загружен, поэтому его ссылки не будут скопированы. Лучше сначала загрузить постер, чтобы один и тот же постер не загружать несколько раз.';

  @override
  String get openRelease => 'Открыть релиз';

  @override
  String get openReleaseShortcut => 'Ctrl+O';

  @override
  String get chooseReleaseFolder => 'Выберите папку релиза';

  @override
  String get releaseManifestNotFound =>
      'В выбранной папке отсутствует файл release.json.';

  @override
  String get releaseMetadataInvalid => 'Файл release.json недействителен.';

  @override
  String get openReleaseError => 'Не удалось открыть релиз.';

  @override
  String get chooseAnotherFolder => 'Выбрать другую папку';

  @override
  String get save => 'Сохранить';

  @override
  String get saveShortcut => 'Ctrl+S';

  @override
  String get movieFilePathLabel => 'Путь к видео';

  @override
  String get chooseFile => 'Выбрать файл';

  @override
  String get filePickerFailed => 'Не удалось открыть окно выбора файла.';

  @override
  String get movieFileNotFound => 'Файл фильма не найден.';

  @override
  String get probeToolNotAvailable =>
      'ffprobe не установлен. Установите его, чтобы читать метаданные файлов.';

  @override
  String get probeFailed => 'Не удалось прочитать метаданные файла.';

  @override
  String get ffmpegNotAvailable =>
      'ffmpeg не установлен. Установите его, чтобы работать с изображениями.';

  @override
  String get thumbnailFailed => 'Не удалось создать миниатюру.';

  @override
  String get castLabel => 'В ролях';

  @override
  String get videoTitleLabel => 'Название ролика';

  @override
  String get modelLabel => 'Модель';

  @override
  String get setNameLabel => 'Название сета';

  @override
  String get siteNumberLabel => 'Номер на сайте (необязательно)';

  @override
  String get subsiteAndSiteLabel => 'Подсайт и сайт';

  @override
  String get productionDateLabel => 'Дата производства';

  @override
  String get chooseDate => 'Выбрать дату';

  @override
  String get genreTagsLabel => 'Жанр (теги)';

  @override
  String get fileSizeLabel => 'Размер файла';

  @override
  String fileSizeDisplay(String human, String bytes) {
    return '$human ($bytes байт)';
  }

  @override
  String get durationLabel => 'Продолжительность';

  @override
  String get durationHint => 'hh:mm:ss';

  @override
  String get videoTypeLabel => 'Тип видео';

  @override
  String get videoQualityLabel => 'Качество видео';

  @override
  String get videoFormatLabel => 'Формат видео';

  @override
  String get videoStreamLabel => 'Видео';

  @override
  String get audioStreamLabel => 'Аудио';

  @override
  String get descriptionLabel => 'Описание';

  @override
  String get additionalInfoLabel => 'Доп. информация (необязательно)';

  @override
  String get photosetPackFolderLabel => 'Папка с фотосетами';

  @override
  String get singlePhotosetFolderLabel => 'Папка с фото';

  @override
  String get imageFolderFolderLabel => 'Папка с изображениями';

  @override
  String get chooseFolder => 'Выбрать папку';

  @override
  String get siteOrJournalLabel => 'Сайт или журнал';

  @override
  String get periodLabel => 'Период';

  @override
  String get photosetCountLabel => 'Фотосеты';

  @override
  String get totalPhotoCountLabel => 'Фотографии (всего)';

  @override
  String get minResolutionLabel => 'Минимальное разрешение фото';

  @override
  String get maxResolutionLabel => 'Максимальное разрешение фото';

  @override
  String get imageFormatsLabel => 'Форматы изображений';

  @override
  String get imageCountLabel => 'Изображения (всего)';

  @override
  String get minImageResolutionLabel => 'Минимальное разрешение изображения';

  @override
  String get maxImageResolutionLabel => 'Максимальное разрешение изображения';

  @override
  String get columnTitleReleaseInfo => 'Информация о релизе';

  @override
  String get columnTitleVideo => 'Видео';

  @override
  String get columnTitleSourceFolder => 'Исходная папка';

  @override
  String get columnTitlePhotosets => 'Фотосеты';

  @override
  String get columnTitleImages => 'Изображения';

  @override
  String get photosetPackSectionTitle => 'Фотосеты';

  @override
  String get singlePhotosetSectionTitle => 'Фотосет';

  @override
  String get scanPhotosets => 'Сканировать';

  @override
  String get pickPhotosets => 'Выбрать';

  @override
  String photosetPhotoCount(int count) {
    return '$count фото';
  }

  @override
  String photosetPickedCount(int count) {
    return '$count выбрано';
  }

  @override
  String get photosetPackNoPhotosets =>
      'Фотосетов нет. Выберите папку и сканируйте её.';

  @override
  String get singlePhotosetNoPhotosets =>
      'Фото нет. Выберите папку и сканируйте её.';

  @override
  String photosetSkippedEntries(String entries) {
    return 'Не фотосеты: $entries';
  }

  @override
  String photosetUnreadPhotos(String names) {
    return 'Не удалось прочитать разрешение: $names';
  }

  @override
  String photosetNameCollisions(String names) {
    return 'Совпадающие имена: $names';
  }

  @override
  String photosetNotCopied(String names) {
    return 'Не удалось скопировать: $names';
  }

  @override
  String photosetEmptySets(String names) {
    return 'Фотосеты без фотографий: $names';
  }

  @override
  String get photosetPackSourceEmpty => 'Сначала выберите папку с фотосетами.';

  @override
  String get singlePhotosetSourceEmpty => 'Сначала выберите папку с фото.';

  @override
  String get photosetSourceNotFound => 'Выбранная папка не найдена.';

  @override
  String get photosetSourceNotReadable =>
      'Не удалось прочитать выбранную папку.';

  @override
  String get imageFolderSectionTitle => 'Изображения';

  @override
  String imageFolderCount(int count) {
    return '$count изображений';
  }

  @override
  String get imageFolderNoImages =>
      'Изображений нет. Выберите папку и сканируйте её.';

  @override
  String imageFolderNotImages(String names) {
    return 'Не изображения: $names';
  }

  @override
  String get imageFolderSourceEmpty =>
      'Сначала выберите папку с изображениями.';

  @override
  String get videoFolderLabel => 'Папка с видео';

  @override
  String get totalSizeLabel => 'Общий размер';

  @override
  String get videoCountLabel => 'Видео';

  @override
  String get videoResolutionsLabel => 'Разрешения';

  @override
  String get videoFormatsLabel => 'Форматы';

  @override
  String get videoPackSectionTitle => 'Видео и скриншоты';

  @override
  String get fileNameLabel => 'Имя файла';

  @override
  String get scanVideos => 'Сканировать';

  @override
  String get noVideos => 'Видео нет. Выберите папку и сканируйте её.';

  @override
  String videoSkippedFiles(String names) {
    return 'Не видео: $names';
  }

  @override
  String videoUnprobedFiles(String names) {
    return 'Не удалось прочитать: $names';
  }

  @override
  String videoEmptyFolders(String names) {
    return 'Папки без видео: $names';
  }

  @override
  String videoUnreadableFolders(String names) {
    return 'Папки, которые не удалось прочитать: $names';
  }

  @override
  String get videoSourceEmpty => 'Сначала выберите папку с видео.';

  @override
  String get videoSourceNotFound => 'Выбранная папка не найдена.';

  @override
  String get videoSourceNotReadable => 'Не удалось прочитать выбранную папку.';

  @override
  String get generatePackImages => 'Создать';

  @override
  String get screenlistLabel => 'Скринлист';

  @override
  String get screenshotsLabel => 'Скриншоты';

  @override
  String imagesFailedFiles(String names) {
    return 'Не удалось создать изображения для: $names';
  }

  @override
  String get posterImageLabel => 'Изображение постера';

  @override
  String get videoThumbnailLabel => 'Миниатюра видео';

  @override
  String get noImageSelected => 'Изображение не выбрано';

  @override
  String get noVideoSelected => 'Видео не выбрано';

  @override
  String get posterHint => 'Нажмите, чтобы выбрать изображение.';

  @override
  String get videoHint => 'Нажмите, чтобы выбрать видео.';

  @override
  String get chooseImage => 'Выбрать изображение';

  @override
  String get pasteFromUrl => 'Вставить из ссылки';

  @override
  String get nothingToPaste => 'В буфере обмена ничего нет.';

  @override
  String get removeImage => 'Удалить изображение';

  @override
  String get posterFileNotFound => 'Файл постера не найден.';

  @override
  String get posterWrongFormat => 'Постер должен быть файлом JPG или WebP.';

  @override
  String get posterUrlInvalid => 'В буфере обмена нет ссылки на файл.';

  @override
  String get posterDownloadFailed => 'Не удалось скачать изображение.';

  @override
  String get posterWriteFailed => 'Не удалось записать постер.';

  @override
  String get posterRemoveFailed => 'Не удалось удалить постер.';

  @override
  String get screenshotsSectionTitle => 'Скриншоты';

  @override
  String get screenshotCountLabel => 'Количество скриншотов';

  @override
  String get generateScreenshots => 'Создать';

  @override
  String get regenerateScreenshots => 'Пересоздать';

  @override
  String get noScreenshots => 'Скриншоты не созданы.';

  @override
  String get selectVideoFirst => 'Сначала выберите видео';

  @override
  String get screenshotFailed => 'Не удалось создать скриншоты.';

  @override
  String get mtnNotAvailable =>
      'mtn не установлен. Установите его, чтобы создавать скринлисты.';

  @override
  String get screenlistFailed => 'Не удалось создать скринлист.';

  @override
  String get uploadSectionTitle => 'Загрузка изображений';

  @override
  String get uploadNeedsImagesFirst =>
      'Сначала добавьте постер и создайте скриншоты';

  @override
  String get uploadNeedsScreenlistsFirst =>
      'Сначала добавьте постер и создайте скринлисты';

  @override
  String get uploadButton => 'Загрузить';

  @override
  String uploadProgress(int done, int total) {
    return '$done / $total';
  }

  @override
  String get uptoodaNotAvailable =>
      'uptooda недоступен. Он входит в состав приложения, поэтому установка неполная.';

  @override
  String get imagesManifestFailed =>
      'Не удалось записать images.json. Проверьте путь и права доступа.';

  @override
  String get hosterApiKeyRequired =>
      'Укажите API-ключ в разделе «Настройки → Интеграции»';

  @override
  String get messageSectionTitle => 'Сообщение';

  @override
  String get generateMessage => 'Сгенерировать';

  @override
  String get messageNeedsImagesFirst => 'Сначала загрузите изображения';

  @override
  String get noMessage => 'Ничего не создано.';

  @override
  String get includeAppSignature =>
      'Добавить заметку «Оформлено с помощью Release Prepper»';

  @override
  String get screenshotLayoutLabel => 'Вид блока скриншотов';

  @override
  String get screenshotLayoutByHoster => 'Сначала по хостеру, затем по видео';

  @override
  String get screenshotLayoutByItem => 'Сначала по видео, затем по хостеру';

  @override
  String get templateNotFound => 'Нет шаблона для этого трекера и типа релиза.';

  @override
  String get styleNotFound => 'Нет стиля для этого трекера.';

  @override
  String get templateInvalid =>
      'Шаблон некорректен: секция не закрыта на той же строке.';

  @override
  String get messageSaveFailed =>
      'Не удалось записать message.txt. Проверьте путь и права доступа.';

  @override
  String fieldNotFilled(String label) {
    return 'Поле «$label» обязательно.';
  }

  @override
  String productionDateInvalid(String label) {
    return 'Поле «$label» должно быть в формате YYYY-MM-DD, YYYY-MM или YYYY.';
  }

  @override
  String messageValidationFailed(String problems) {
    return 'Сообщение не создано:\n$problems';
  }

  @override
  String get copyToClipboard => 'Скопировать в буфер обмена';

  @override
  String get unsavedChanges => 'Несохранённые изменения';

  @override
  String get releaseSaveFailed =>
      'Не удалось сохранить релиз. Проверьте путь и права доступа.';

  @override
  String get closeUnsavedTitle => 'Несохранённые изменения';

  @override
  String closeUnsavedMessage(String title) {
    return 'У вас есть несохранённые изменения в «$title». Закрыть без сохранения?';
  }

  @override
  String get closeWithoutSaving => 'Закрыть без сохранения';

  @override
  String get saveAndClose => 'Сохранить и закрыть';

  @override
  String get cancel => 'Отмена';

  @override
  String get settings => 'Настройки';

  @override
  String get settingsGeneralSectionTitle => 'Основные';

  @override
  String get settingsIntegrationSectionTitle => 'Интеграции';

  @override
  String get appLanguageLabel => 'Язык приложения';

  @override
  String get defaultReleaseDirectoryLabel => 'Каталог релизов по умолчанию';

  @override
  String get languageSystem => 'Язык системы';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageRussian => 'Русский';

  @override
  String get stashdbApiKeyLabel => 'API-ключ StashDB';

  @override
  String get postimagesApiKeyLabel => 'API-ключ Postimages';

  @override
  String get pornolabUsernameLabel => 'Имя пользователя PornoLab';

  @override
  String get pornolabPasswordLabel => 'Пароль PornoLab';

  @override
  String get loginButton => 'Войти';

  @override
  String get logoutButton => 'Выйти';

  @override
  String get captchaCodeLabel => 'Код';

  @override
  String get secretStoreUnavailable =>
      'Хранилище ключей на этом компьютере недоступно. Включите его — Secret Service на Linux, Keychain на macOS, Диспетчер учётных данных на Windows — или разрешите хранить эти значения открытым текстом, что не рекомендуется.';

  @override
  String get secretStoreNotAvailable =>
      'Хранилище ключей недоступно, и хранение открытым текстом не разрешено.';

  @override
  String get allowPlainSecretsLabel =>
      'Хранить значения открытым текстом в settings.json (не рекомендуется)';

  @override
  String get secretStoredPlainly =>
      'Это значение хранится открытым текстом в settings.json.';

  @override
  String get settingsSaveFailed => 'Не удалось сохранить настройки.';

  @override
  String get stashImportTitle => 'Импорт из StashDB';

  @override
  String get stashSceneInputLabel => 'URL или ID ролика в StashDB';

  @override
  String get stashFetchButton => 'Загрузить';

  @override
  String get stashApplyButton => 'Применить выбранное';

  @override
  String get stashInputInvalid =>
      'Это не ID ролика в StashDB и не ссылка, которая им заканчивается.';

  @override
  String get stashNoApiKey =>
      'Введите API-ключ StashDB в настройках, чтобы загрузить ролик.';

  @override
  String get stashRequestFailed => 'Не удалось обратиться к StashDB.';

  @override
  String get stashBadResponse => 'Ответ StashDB не удалось прочитать.';

  @override
  String get stashGraphqlError => 'StashDB сообщил об ошибке.';

  @override
  String get stashSceneNotFound => 'В StashDB нет ролика с таким ID.';

  @override
  String get stashImportNotesTitle => 'Заметки импорта';

  @override
  String stashNoteSiteNumberStripped(String label) {
    return '$label в StashDB содержит номер сайта, поэтому он удалён из названия:';
  }

  @override
  String stashNoteDomainFromOtherUrl(String label) {
    return '$label: в StashDB нет ссылки в категории «Primary sources», поэтому домен взят из этой ссылки:';
  }

  @override
  String get recentReleases => 'Недавние релизы';

  @override
  String get noRecentReleases => 'Ни один релиз ещё не был открыт.';

  @override
  String get recentPathLabel => 'Путь';

  @override
  String get recentSourceLabel => 'Источник';

  @override
  String get recentCreatedDateLabel => 'Дата создания';

  @override
  String get recentLastEditDateLabel => 'Дата последнего изменения';

  @override
  String get recentFolderUnavailable => 'Папка не найдена.';

  @override
  String get recentWriteFailed =>
      'Не удалось сохранить список недавних релизов. Проверьте путь и права доступа.';

  @override
  String get systemCheck => 'Проверка системы';

  @override
  String get systemCheckToolLabel => 'Инструмент';

  @override
  String get systemCheckResultLabel => 'Результат';

  @override
  String systemCheckToolNotFound(String tool) {
    return '$tool не найден.';
  }

  @override
  String systemCheckRunFailed(String tool, int code) {
    return '$tool завершился с кодом $code.';
  }

  @override
  String systemCheckRunTimeout(Object tool) {
    return '$tool превысил время ожидания.';
  }

  @override
  String systemCheckNoOutput(Object tool) {
    return '$tool выполнил команду, но ничего не сообщил.';
  }

  @override
  String get torrentSectionTitle => 'Торрент';

  @override
  String get torrentPickFileFirst => 'Сначала выберите файл';

  @override
  String get torrentPickFolderFirst => 'Сначала выберите папку';

  @override
  String get torrentButton => 'Создать';

  @override
  String torrentProgress(int percent) {
    return '$percent%';
  }

  @override
  String torrentSpeed(String speed) {
    return 'Скорость: $speed';
  }

  @override
  String torrentEta(String eta) {
    return 'Осталось: $eta';
  }

  @override
  String torrentCreated(String path) {
    return 'Создан $path';
  }

  @override
  String torrentAlreadyCreated(String path) {
    return 'Уже создан: $path';
  }

  @override
  String get torrentPrivateLabel => 'Приватный';

  @override
  String get torrentPrivateTitle => 'Изменить флаг Private?';

  @override
  String torrentPrivateMessage(String value) {
    return 'Файл торрента уже существует. Изменить его флаг Private на «$value»?';
  }

  @override
  String get torrentPrivateValuePrivate => 'приватный';

  @override
  String get torrentPrivateValueNotPrivate => 'не приватный';

  @override
  String get torrentPrivateConfirm => 'Изменить';

  @override
  String get torrentPrivateNotReadable =>
      'Файл не читается как торрент, поэтому его флаг прочитать нельзя.';

  @override
  String get mkbrrNotAvailable =>
      'mkbrr недоступен. Он входит в состав приложения, поэтому установка неполная.';

  @override
  String mkbrrRunFailed(int code) {
    return 'mkbrr завершился с кодом $code.';
  }

  @override
  String get mkbrrRunTimeout => 'mkbrr превысил время ожидания.';

  @override
  String mkbrrModifyFailed(String reason) {
    return 'mkbrr не смог изменить флаг: $reason.';
  }

  @override
  String get folderOpenFailed => 'Не удалось открыть папку.';

  @override
  String get draftSectionTitle => 'Загрузка черновика на трекер';

  @override
  String get draftUploadButton => 'Загрузить';

  @override
  String get parentForumLabel => 'Родительский форум';

  @override
  String parentForumInvalid(String label) {
    return '$label должен быть полным URL форума с параметром f.';
  }

  @override
  String get draftLinkLabel => 'Ссылка на черновик на трекере';

  @override
  String get draftNeedsMessageFirst => 'Сначала создайте сообщение';

  @override
  String get draftNeedsLoginFirst =>
      'Войдите на сайт в разделе «Настройки → Интеграции»';

  @override
  String get draftNeedsForumFirst => 'Укажите родительский форум';

  @override
  String get draftRecreated =>
      'Черновика, на который указывала сохранённая ссылка, на сайте больше нет, поэтому создан новый.';

  @override
  String get pornolabNeedsCredentials => 'Введите имя пользователя и пароль';

  @override
  String get pornolabLoginAccepted => 'Вход принят.';

  @override
  String get pornolabLoginRefused =>
      'Сайт не принял имя пользователя и пароль.';

  @override
  String get pornolabNeedsCaptcha => 'Сайт просит код подтверждения.';

  @override
  String get pornolabLoginNoCookie => 'Вход принят, но ответ не дал cookie.';

  @override
  String get pornolabCookieRefused =>
      'Сайт не принял cookie. Войдите на сайт снова в разделе «Настройки → Интеграции».';

  @override
  String get pornolabNoToken =>
      'Страница не дала form_token. Попробуйте ещё раз.';

  @override
  String get pornolabTokenRejected =>
      'Сайт не принял form_token. Попробуйте ещё раз.';

  @override
  String get pornolabDraftGone =>
      'На сайте нет черновика с этим id, и новый не создан.';

  @override
  String get pornolabSiteError => 'Сайт сообщил об ошибке.';

  @override
  String get pornolabBadResponse => 'Ответ сайта не удалось прочитать.';

  @override
  String get pornolabRequestFailed => 'Не удалось обратиться к сайту.';

  @override
  String get pornolabTimeout => 'Запрос к сайту длился слишком долго.';

  @override
  String get linkOpenFailed => 'Не удалось открыть ссылку в браузере.';
}
