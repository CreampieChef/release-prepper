import 'package:path/path.dart' as p;

import '../release/release.dart';

/// The languages the app has translations for. `system` is not a translation:
/// it means the system locale, so the value is what the user chose, not what
/// the app shows right now.
///
/// This is `AppLocalizations.supportedLocales` plus the `system` option, so
/// adding a language means adding it here and to the arb files.
enum AppLanguage { system, en, ru }

/// The sections the Settings page has. The page lists them on the left in this
/// order, so a new section is an entry here plus a case in the page's
/// `_content`.
///
/// It is not private to the page, because which section a settings tab shows is
/// the tab's state rather than the page's: `AppTab` holds it, so the selection
/// is still there when the user comes back to the tab from another one. The tab
/// view builds only the active tab, so the page is rebuilt on every switch.
/// This is not a setting: nothing is stored, and a settings tab that was closed
/// shows the first section, because the record the choice was kept on is gone.
enum SettingsSection { general, releases, integration }

/// The fields the Integration section has. The name is the key the credential
/// store uses, so it is the record the app reads back.
///
/// A field the app never uses stores a value for nothing, so an entry is added
/// when the app has a use for it. StashDB is read by the Stash section, and
/// Postimages by the Upload section, which passes it to the tool through the
/// environment. The two PornoLab credentials are read by the Upload draft
/// section, which uses them to obtain the cookie (`ai/pornolab_login.md`).
///
/// [masked] is a display rule, not a storage rule: every entry here is stored in
/// the credential store, and the page reads the flag instead of masking every
/// field in its loop. The username is the one shown plainly, because a username
/// is not confidential; storing it and displaying it are two different things.
enum SettingsField {
  stashdb(masked: true),
  postimages(masked: true),
  pornolabUsername(masked: false),
  pornolabPassword(masked: true);

  const SettingsField({required this.masked});

  final bool masked;
}

/// The key the app writes the cookie it obtains from a login under. It is not a
/// field: nothing on the page writes it, so it is a key rather than an entry in
/// the list the page draws (`ai/pornolab_login.md` §2).
const pornolabCookieKey = 'pornolabCookie';

/// The directory the app offers when none has been set: the user's Documents,
/// written with `~` so the same string is right on every machine.
/// `resolveUserPath` is what turns it into a path.
const fallbackReleaseDirectory = '~/Documents/Releases';

/// A path that starts with `~` means the user's home. The settings store what
/// the user wrote, so the expansion happens when the app uses the path, not
/// when it is stored. `~` is the app's own convention, not the shell's: it is
/// the home the composition root resolves, and only the `~/` form means it.
///
/// The path is rebuilt from segments rather than by appending what the user
/// wrote to the home. The `~` form is written with `/` on every machine, so
/// appending it as one string puts the separator only between the home and the
/// rest, and on Windows the result mixes `\` with the `/` the user wrote. The
/// context decides the separator, so it is a parameter: a rule that reads the
/// platform can only be tested on the platform it reads, the same reason
/// `ToolLocator` takes `isWindows`.
String resolveUserPath(
  String path, {
  required String home,
  required p.Context context,
}) {
  if (path == '~') {
    return home;
  }

  if (path.startsWith('~/')) {
    return context.joinAll([home, ...context.split(path.substring(2))]);
  }

  return path;
}

/// The app's own settings — the first app-level state (`ai/doc.md` §7).
class Settings {
  Settings({
    required this.language,
    required this.defaultReleaseDirectory,
    required this.defaultTorrentPrivate,
    required this.defaultIncludeAppSignature,
    required this.allowPlainSecrets,
    required this.plainSecrets,
  });

  /// A settings file that does not exist or cannot be read is the same as a new
  /// one: the app follows the system locale and the default release directory,
  /// and does not store secrets plainly. The two release defaults are the state
  /// a new release has always been created with, so a file written before they
  /// were settings reads as them.
  Settings.defaults()
    : language = AppLanguage.system,
      defaultReleaseDirectory = fallbackReleaseDirectory,
      defaultTorrentPrivate = true,
      defaultIncludeAppSignature = true,
      allowPlainSecrets = false,
      plainSecrets = {};

  AppLanguage language;

  /// What the user wrote, which may start with `~`. It is stored as written;
  /// the app expands it when it uses it.
  String defaultReleaseDirectory;

  /// The Private flag a new release is created with (`ai/torrents.md`). It is a
  /// default, not a rule: a release keeps the flag its own manifest holds, and
  /// changing this does not change a release that exists.
  bool defaultTorrentPrivate;

  /// Whether a new release's post ends with the app's signature
  /// (`ai/description_template.md` §App signature). The same kind of default:
  /// the flag on a release is what the Message section renders with, so a
  /// release keeps the value its manifest holds.
  bool defaultIncludeAppSignature;

  /// The fallback for a machine with no credential store. Off by default,
  /// because settings.json is plain text and the point of the store is that the
  /// values are not in it.
  bool allowPlainSecrets;

  /// Only the values stored plainly, keyed by the service name. Values that
  /// live in the credential store are not in this file.
  Map<String, String> plainSecrets;

  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'language': language.name,
    'defaultReleaseDirectory': defaultReleaseDirectory,
    'defaultTorrentPrivate': defaultTorrentPrivate,
    'defaultIncludeAppSignature': defaultIncludeAppSignature,
    'allowPlainSecrets': allowPlainSecrets,
    'plainSecrets': plainSecrets,
  };

  /// A language this version does not know is read as `system`, because there
  /// is no translation to show for it. A missing or empty directory is read as
  /// the default. Other keys are not kept: this is a file the app writes, not
  /// one the user edits.
  static Settings fromJson(Map<String, dynamic> json) {
    final language = json['language'];
    final directory = json['defaultReleaseDirectory'];
    final plainSecrets = json['plainSecrets'];

    return Settings(
      language: AppLanguage.values.firstWhere(
        (value) => value.name == language,
        orElse: () => AppLanguage.system,
      ),
      defaultReleaseDirectory: directory is String && directory.isNotEmpty
          ? directory
          : fallbackReleaseDirectory,
      defaultTorrentPrivate: _flag(json['defaultTorrentPrivate'], true),
      defaultIncludeAppSignature: _flag(
        json['defaultIncludeAppSignature'],
        true,
      ),
      allowPlainSecrets: _flag(json['allowPlainSecrets'], false),
      plainSecrets: {
        if (plainSecrets is Map)
          for (final entry in plainSecrets.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
      },
    );
  }

  /// A flag, or [defaultValue] when the key is absent or is not a flag. The
  /// same rule as the release format's flags: a file written before the choice
  /// existed is not an error, and the default is the state those files were
  /// written with.
  static bool _flag(Object? value, bool defaultValue) =>
      value is bool ? value : defaultValue;
}
