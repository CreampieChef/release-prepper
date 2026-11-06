import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:window_manager/window_manager.dart';

import '../feature/main_menu_controller.dart';
import '../feature/message/message_store.dart';
import '../feature/recent_releases/recent_releases_controller.dart';
import '../feature/recent_releases/recent_releases_store.dart';
import '../feature/release/release_open_controller.dart';
import '../feature/release/release_store.dart';
import '../feature/screenshots/images_store.dart';
import '../feature/settings/secret_store.dart';
import '../feature/settings/settings_controller.dart';
import '../feature/settings/settings_store.dart';
import '../feature/system_check/system_check_controller.dart';
import '../feature/tab/tab_close_controller.dart';
import '../feature/tab/tab_manager.dart';
import '../feature/window/window_controller.dart';
import '../feature/window/window_gateway.dart';
import '../feature/window/window_size_store.dart';
import '../service/fonts/font_store.dart';
import '../service/launcher/folder_opener.dart';
import '../service/launcher/url_opener.dart';
import '../service/logging/tool_log.dart';
import '../service/native_tools/ffprobe.dart';
import '../service/native_tools/ffmpeg.dart';
import '../service/native_tools/mkbrr.dart';
import '../service/native_tools/mtn.dart';
import '../service/native_tools/tool_locator.dart';
import '../service/native_tools/tool_runner.dart';
import '../service/native_tools/uptooda.dart';
import '../service/network/image_downloader.dart';
import '../service/network/pornolab_client.dart';
import '../service/network/stash_client.dart';
import '../service/photosets/directory_reader.dart';
import '../service/photosets/photoset_scanner.dart';
import '../service/photosets/zip_reader.dart';
import '../service/stashdb/domain_map.dart';
import '../service/template/template_renderer.dart';
import '../service/template/template_store.dart';
import '../service/videos/image_generator.dart';
import '../service/videos/video_scanner.dart';

/// Composition root: the whole object graph is built here. A new feature adds
/// one entry to this list; `app.dart` does not change.
List<SingleChildWidget> appProviders() => [
  // Where a tool comes from: the app bundle first, then PATH. The install step
  // puts each bundled tool in a directory of its own next to the app
  // executable, so the directory the app runs from is the bundle.
  Provider<ToolLocator>(
    create: (_) => ToolLocator(
      bundleDirectory: Directory(p.dirname(Platform.resolvedExecutable)),
      pathVariable: Platform.environment['PATH'] ?? '',
      isWindows: Platform.isWindows,
    ),
  ),

  // The tool log, `<release_dir>/logs/`. `ToolRunner` writes it.
  Provider<ToolLog>(create: (_) => ToolLog()),

  Provider<ToolRunner>(
    create: (context) => ToolRunner(
      locator: context.read<ToolLocator>(),
      log: context.read<ToolLog>(),
    ),
  ),

  Provider<Ffmpeg>(
    create: (context) => Ffmpeg(runner: context.read<ToolRunner>()),
  ),

  Provider<Ffprobe>(
    create: (context) => Ffprobe(runner: context.read<ToolRunner>()),
  ),

  Provider<Mtn>(create: (context) => Mtn(runner: context.read<ToolRunner>())),

  // The tool the app ships, because its upload scripts are the modified ones.
  Provider<Uptooda>(
    create: (context) => Uptooda(runner: context.read<ToolRunner>()),
  ),

  // The other tool the app ships. It is not on PATH, so it is resolved from the
  // bundle only (`ai/bundled_native_tools.md`).
  Provider<Mkbrr>(
    create: (context) => Mkbrr(runner: context.read<ToolRunner>()),
  ),

  // The System Check tab. It is app-level, so it is a provider entry like the
  // recent list. `ToolRunner` needs a directory to write the tool log to, and
  // outside a release there is no release directory, so the check's calls are
  // logged under the app data directory; the function is given here, the same
  // reason `SettingsStore` is given one.
  Provider<SystemCheckController>(
    create: (context) => SystemCheckController(
      ffmpeg: context.read<Ffmpeg>(),
      ffprobe: context.read<Ffprobe>(),
      mtn: context.read<Mtn>(),
      uptooda: context.read<Uptooda>(),
      mkbrr: context.read<Mkbrr>(),
      appDirectory: getApplicationSupportDirectory,
    ),
  ),

  // The only network user. Provider closes the client when the scope ends.
  Provider<HttpClient>(
    create: (_) => HttpClient(),
    dispose: (_, client) => client.close(),
  ),

  Provider<ImageDownloader>(
    create: (context) => ImageDownloader(client: context.read<HttpClient>()),
  ),

  // StashDB, over the same client. The API key is not a dependency of the
  // client: the widget reads it from the settings and passes it to the call, so
  // the client does not hold a value that can change while the app is open.
  Provider<StashClient>(
    create: (context) => StashClient(client: context.read<HttpClient>()),
  ),

  // The domains the StashDB import writes in a form of its own, from the
  // bundled asset. The asset bundle is passed in rather than read as
  // `rootBundle` inside the service, for the same reason `TemplateStore` is
  // given it.
  Provider<DomainMap>(create: (_) => DomainMap(bundle: rootBundle)),

  // PornoLab, over the same client, for the Upload draft section
  // (`ai/uploading_draft.md`). The cookie is not a dependency of the client for
  // the same reason the API key is not one. This is the first stateful service
  // in the app: the form token it caches is the app's session on the site rather
  // than something a release owns, so it is one instance for the whole app.
  Provider<PornolabClient>(
    create: (context) => HttpPornolabClient(
      client: context.read<HttpClient>(),
      log: context.read<ToolLog>(),
    ),
  ),

  // Opening a folder in the file manager the OS uses, for the link the Torrent
  // section shows next to the path (`ai/torrents.md`).
  Provider<FolderOpener>(create: (_) => const FolderOpener()),

  // Opening a link in the browser the OS uses, for the draft link the Upload
  // draft section shows (`ai/uploading_draft.md` §5). The second use of
  // url_launcher, after `FolderOpener`.
  Provider<UrlOpener>(create: (_) => const UrlOpener()),

  Provider<ReleaseStore>(create: (_) => ReleaseStore()),

  // The images.json tracking file for the Screenshots section.
  Provider<ImagesStore>(create: (_) => ImagesStore()),

  // The scan that reads the picked folder (`ai/photoset_pack.md` §4). The
  // readers are the containers it can read; the archive reader is the second
  // one, so the scan does not change when a format is added.
  Provider<PhotosetScanner>(
    create: (_) => PhotosetScanner(
      readers: [const DirectoryPhotosetReader(), const ZipPhotosetReader()],
    ),
  ),

  // The scan that reads the picked folder for a video pack (`ai/video_pack.md`
  // §4). It is the filesystem walk plus the probe the app already has; there is
  // no container format here to put behind a reader interface.
  Provider<VideoScanner>(
    create: (context) => VideoScanner(probe: context.read<Ffprobe>()),
  ),

  // The font the app ships, materialised into the app data directory so the tool
  // can open it by path (`ai/bundled_native_tools.md`). The asset bundle and the
  // directory are passed in for the same reason `TemplateStore` and
  // `SettingsStore` are.
  Provider<FontStore>(
    create: (_) => FontStore(
      bundle: rootBundle,
      appDirectory: getApplicationSupportDirectory,
    ),
  ),

  // The rules that write the images (`ai/doc.md` §2). It is the
  // three tools the app already provides; the feature controllers call it per
  // item and record what it wrote.
  Provider<ImageGenerator>(
    create: (context) => ImageGenerator(
      ffmpeg: context.read<Ffmpeg>(),
      ffprobe: context.read<Ffprobe>(),
      mtn: context.read<Mtn>(),
      fonts: context.read<FontStore>(),
    ),
  ),

  // The description templates and styles (`ai/description_template.md`). The
  // asset bundle is passed in rather than read as `rootBundle` inside the
  // service, so the service reads no static. It is the framework's own bundle,
  // so it is not disposed.
  Provider<TemplateStore>(create: (_) => TemplateStore(bundle: rootBundle)),

  Provider<TemplateRenderer>(create: (_) => const TemplateRenderer()),

  // The message.txt file the Message section writes.
  Provider<MessageStore>(create: (_) => MessageStore()),

  // The app settings, `settings.json` in the app data directory (`ai/doc.md`
  // §7): the app's first app-level state. `path_provider` is async, so the
  // store is given the function that resolves the directory instead of
  // resolving it itself.
  Provider<SettingsStore>(
    create: (_) => SettingsStore(appDirectory: getApplicationSupportDirectory),
  ),

  // The recent releases list, `recent_releases.json` in the same app data
  // directory. It is not a field inside settings.json: settings are the user's
  // choices, this is a record of what happened (`ai/recent_releases.md` §2).
  Provider<RecentReleasesStore>(
    create: (_) =>
        RecentReleasesStore(appDirectory: getApplicationSupportDirectory),
  ),

  // The credential store. The plugin instance is built here rather than inside
  // the store, so the store builds no dependency of its own (rule 4).
  Provider<SecretStore>(
    create: (_) => PluginSecretStore(storage: FlutterSecureStorage()),
  ),

  // The second Listenable in the app, recorded as a deviation in `ai/doc.md`
  // §4: the app language is read by `AppRoot`, and what the app shows cannot
  // change unless something notifies.
  ChangeNotifierProvider<SettingsController>(
    create: (context) {
      final controller = SettingsController(
        store: context.read<SettingsStore>(),
        secretStore: context.read<SecretStore>(),
        homeDirectory: _homeDirectory(),
        pathContext: p.context,
        client: context.read<PornolabClient>(),
        appDirectory: getApplicationSupportDirectory,
      );

      // The first frames use the defaults, and the stored values apply when the
      // read completes.
      unawaited(controller.load());

      return controller;
    },
  ),

  // The tab state. It was the only Listenable in the app; `SettingsController`
  // is the second and `RecentReleasesController` the third, both recorded as
  // deviations in `ai/doc.md` §4.
  ChangeNotifierProvider<TabManager>(create: (_) => TabManager()),

  // The recent list. It is app-level state shown in a table, so it notifies —
  // the same reason `SettingsController` does (`ai/recent_releases.md` §7).
  ChangeNotifierProvider<RecentReleasesController>(
    create: (context) {
      final controller = RecentReleasesController(
        store: context.read<RecentReleasesStore>(),
        tabManager: context.read<TabManager>(),
      );

      // The startup read, then the tab the app opens at startup as the first
      // tab. Opening a tab is a side effect, so it is the controller's, not
      // `app.dart`'s (rule 8).
      unawaited(controller.start());

      return controller;
    },
  ),

  // The window. It has no widget and shows nothing, so the entries here are
  // the whole feature (`ai/doc.md` §4): the size is recorded at the point the
  // close flow decides the app is closing for real, and the app never asks the
  // window for a size — the runners apply the recorded one before the window is
  // created.
  //
  // The gateway is the plugin seam, the same reason `SecretStore` is one, and
  // the plugin instance is read here for the same reason its instance is.
  Provider<WindowGateway>(
    create: (_) => PluginWindowGateway(windowManager: windowManager),
  ),

  // `window_size.txt` in the same app data directory. It is not a field inside
  // settings.json, because settings are the user's choices and this is a record
  // of what the window was (`ai/doc.md` §7). The Linux and Windows runners read
  // the same file before they create the window.
  Provider<WindowSizeStore>(
    create: (_) =>
        WindowSizeStore(appDirectory: getApplicationSupportDirectory),
  ),

  // Nothing is read here at startup, because the app does not apply a size. This
  // entry is the shape of the other controllers': the close flow is what calls
  // it.
  Provider<WindowController>(
    create: (context) => WindowController(
      store: context.read<WindowSizeStore>(),
      gateway: context.read<WindowGateway>(),
    ),
  ),

  Provider<TabCloseController>(
    create: (context) => TabCloseController(
      store: context.read<ReleaseStore>(),
      tabManager: context.read<TabManager>(),
      recentReleases: context.read<RecentReleasesController>(),
    ),
  ),

  Provider<ReleaseOpenController>(
    create: (context) =>
        ReleaseOpenController(store: context.read<ReleaseStore>()),
  ),

  Provider<MainMenuController>(
    create: (context) => MainMenuController(
      tabManager: context.read<TabManager>(),
      releaseOpenController: context.read<ReleaseOpenController>(),
      tabCloseController: context.read<TabCloseController>(),
      recentReleases: context.read<RecentReleasesController>(),
    ),
  ),
];

/// The user's home, for expanding a `~` in a stored path. This is the one place
/// that reads the environment — the same kind of exception as `rootBundle`: a
/// top-level the OS owns, read here so the controller does not build a
/// dependency of its own.
String _homeDirectory() =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
