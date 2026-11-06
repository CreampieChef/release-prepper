import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../service/network/pornolab_client.dart';
import 'secret_store.dart';
import 'settings.dart';
import 'settings_store.dart';

enum SettingsFailureKind {
  /// settings.json could not be written.
  writeFailed,

  /// The credential store could not be reached, and plain storage is not
  /// allowed.
  secretStoreUnavailable,
}

sealed class SettingsSaveResult {
  const SettingsSaveResult();
}

final class SettingsSaveSuccess extends SettingsSaveResult {
  const SettingsSaveSuccess();
}

final class SettingsSaveFailure extends SettingsSaveResult {
  const SettingsSaveFailure(this.kind);

  final SettingsFailureKind kind;
}

/// Owns the app settings and writes them.
///
/// It also owns the login and the cookie the login gives
/// (`ai/pornolab_login.md`), because it is the feature that owns the credential
/// store: the login is a call, and the value it obtains is a stored value, so
/// both belong to the code that already stores them. `DraftController` asks it
/// for the cookie and for a login when a run needs one, which is the first
/// controller that depends on another controller — recorded in `ai/doc.md` §4.
///
/// It is a `ChangeNotifier`, which is a deviation from rules 3 and 7: the app
/// language is read by `AppRoot` in `app.dart`, and what the app shows cannot
/// change unless something notifies. It is the second Listenable in the app, and
/// the deviation is recorded in `ai/doc.md` §4.
///
/// Settings are written as they change, the way `MessageStore` writes
/// message.txt: there is no dirty flag and no save step, so a settings tab is
/// not part of Ctrl+S and closes without the unsaved-changes popup. The model is
/// written first and the widget shows it, the same order as the editor's write
/// path; when the write fails the app still shows what was chosen, and the
/// widget says the file was not written.
class SettingsController extends ChangeNotifier {
  SettingsController({
    required this.store,
    required this.secretStore,
    required this.homeDirectory,
    required this.pathContext,
    required this.client,
    required this.appDirectory,
  });

  final SettingsStore store;

  /// The credential store the secret values belong to.
  final SecretStore secretStore;

  /// The site the login is made to. It is given here rather than built, as rule
  /// 4 requires, so a test can answer with the two shapes §6 describes.
  final PornolabClient client;

  /// The app data directory, for the tool log of a login made from the settings
  /// page: outside a release there is no release directory, so the app data
  /// directory is what such a call is recorded under — the same rule
  /// `SystemCheckController` follows. It is a function for the same reason
  /// `SettingsStore` has one: `path_provider` is async.
  final Future<Directory> Function() appDirectory;

  /// The user's home, for expanding a `~` in a stored path. It is read at the
  /// composition root rather than inside the controller, so the controller
  /// builds no dependency of its own (rule 4).
  final String homeDirectory;

  /// The path context `resolveUserPath` builds the expanded path with, which is
  /// what decides the separator. It is given rather than taken from the package
  /// here, so the Windows rule can be tested on a machine that is not Windows.
  final p.Context pathContext;

  Settings settings = Settings.defaults();

  /// Whether the credential store can be reached. False until the first read,
  /// and false after a read that failed; the Integration section shows this as
  /// what the user needs to enable.
  bool secretStoreAvailable = false;

  /// The values the Integration section shows. They come from the store when it
  /// is reachable, and from `settings.plainSecrets` when it is not, so the page
  /// reads one map rather than two.
  Map<String, String> secretValues = {};

  /// The locale the app uses. Null asks for the system locale, which is what
  /// `AppLanguage.system` means, and `MaterialApp` falls back to the system
  /// locale when no locale is given.
  Locale? get locale => settings.language == AppLanguage.system
      ? null
      : Locale(settings.language.name);

  /// The default release directory as a path the app can use: what the user
  /// wrote, with a leading `~` expanded and the result built with the context's
  /// separator.
  String get defaultReleaseDirectory => resolveUserPath(
    settings.defaultReleaseDirectory,
    home: homeDirectory,
    context: pathContext,
  );

  /// Reads settings.json once, at startup, then the credential store. The first
  /// frames use the defaults, and the stored values apply when the reads
  /// complete.
  Future<void> load() async {
    settings = await store.load();

    try {
      secretValues.addAll(await secretStore.readAll());
      secretStoreAvailable = true;
    } catch (_) {
      // The store is not reachable on this machine. The values that are in
      // settings.json are still shown, so the section works, and the page says
      // where they are stored.
      secretValues.addAll(settings.plainSecrets);
      secretStoreAvailable = false;
    }

    notifyListeners();
  }

  /// Chooses a language and writes the file immediately. The same value again
  /// is not a write.
  Future<SettingsSaveResult> setLanguage(AppLanguage language) async {
    if (settings.language == language) {
      return const SettingsSaveSuccess();
    }

    settings.language = language;

    notifyListeners();

    return await _write();
  }

  /// Sets the default release directory and writes the file immediately. The
  /// value is stored as the user wrote it, `~` and all. The same value again is
  /// not a write.
  Future<SettingsSaveResult> setDefaultReleaseDirectory(String value) async {
    if (settings.defaultReleaseDirectory == value) {
      return const SettingsSaveSuccess();
    }

    settings.defaultReleaseDirectory = value;

    notifyListeners();

    return await _write();
  }

  /// Sets the Private flag a new release is created with and writes the file
  /// immediately. The same value again is not a write. This does not change a
  /// release that exists: the flag on a release is its own, and the editor and
  /// the Torrent section still write it per release.
  Future<SettingsSaveResult> setDefaultTorrentPrivate(bool value) async {
    if (settings.defaultTorrentPrivate == value) {
      return const SettingsSaveSuccess();
    }

    settings.defaultTorrentPrivate = value;

    notifyListeners();

    return await _write();
  }

  /// Sets whether a new release's post ends with the app's signature and writes
  /// the file immediately. The same value again is not a write, and a release
  /// that exists keeps the value its manifest holds.
  Future<SettingsSaveResult> setDefaultIncludeAppSignature(bool value) async {
    if (settings.defaultIncludeAppSignature == value) {
      return const SettingsSaveSuccess();
    }

    settings.defaultIncludeAppSignature = value;

    notifyListeners();

    return await _write();
  }

  /// Allows or forbids storing values plainly in settings.json. It does not
  /// move what is already in the credential store: it decides where a value
  /// goes from now on, because moving a value without asking is a surprise.
  Future<SettingsSaveResult> setAllowPlainSecrets(bool value) async {
    if (settings.allowPlainSecrets == value) {
      return const SettingsSaveSuccess();
    }

    settings.allowPlainSecrets = value;

    notifyListeners();

    return await _write();
  }

  /// Stores a value under one key. It goes to the credential store when that is
  /// reachable; otherwise it goes to settings.json only when plain storage is
  /// allowed, and an empty value removes the entry rather than storing an empty
  /// string.
  ///
  /// It takes a key rather than a field, because a field is what the page draws
  /// and a key is what the store holds: the cookie is a key with no field
  /// (`ai/pornolab_login.md` §2), so the same write path serves both.
  Future<SettingsSaveResult> setSecret(String key, String value) async {
    if ((secretValues[key] ?? '') == value) {
      return const SettingsSaveSuccess();
    }

    if (secretStoreAvailable) {
      secretValues[key] = value;

      notifyListeners();

      try {
        if (value.isEmpty) {
          await secretStore.delete(key);
        } else {
          await secretStore.write(key, value);
        }

        return const SettingsSaveSuccess();
      } catch (_) {
        return const SettingsSaveFailure(
          SettingsFailureKind.secretStoreUnavailable,
        );
      }
    }

    if (!settings.allowPlainSecrets) {
      return const SettingsSaveFailure(
        SettingsFailureKind.secretStoreUnavailable,
      );
    }

    // The model first, then the file, the same order as the editor's write
    // path.
    if (value.isEmpty) {
      settings.plainSecrets.remove(key);
      secretValues.remove(key);
    } else {
      settings.plainSecrets[key] = value;
      secretValues[key] = value;
    }

    notifyListeners();

    return await _write();
  }

  /// The login (`ai/pornolab_login.md`): the form the client sends, and the
  /// cookie the answer gives stored under `pornolabCookie`.
  ///
  /// The credentials are read from the values the model holds, which are the
  /// same values the page gates its button on, so a login is not reached with
  /// an empty one. The two entries are recorded in the app data directory: the
  /// settings page is the only place a login is made, and outside a release
  /// there is no release directory.
  ///
  /// A login is a new session, so the form token that belonged to the previous
  /// one is dropped — by the client, which is what holds the cache.
  ///
  /// [captcha] and [code] are the second half of a login the site asked for:
  /// the form its page gave and what the user typed into it. A run does not
  /// make a login, so this is called only with what the page has.
  Future<PornolabResult> login({
    LoginCaptcha? captcha,
    String code = '',
  }) async {
    final username = secretValues[SettingsField.pornolabUsername.name] ?? '';
    final password = secretValues[SettingsField.pornolabPassword.name] ?? '';

    if (username.isEmpty || password.isEmpty) {
      return const PornolabFailure(PornolabFailureKind.noCredentials);
    }

    final result = await client.login(
      logDirectory: (await appDirectory()).path,
      username: username,
      password: password,
      captcha: captcha,
      code: code,
    );

    if (result is! LoggedIn) {
      return result;
    }

    // The value is written the way every other field is written, so a login that
    // was accepted but whose cookie could not be written is reported as the same
    // failure the other fields report.
    final stored = await setSecret(pornolabCookieKey, result.cookie);

    if (stored is SettingsSaveFailure) {
      return const PornolabFailure(PornolabFailureKind.valueNotStored);
    }

    return result;
  }

  /// The cookie the app sends, or an empty string when there is none. Reading it
  /// is the only thing the Upload draft section needs from here, and the login
  /// is the only thing it needs when there is none.
  String get cookie => secretValues[pornolabCookieKey] ?? '';

  Future<SettingsSaveResult> _write() async {
    try {
      await store.save(settings);
      return const SettingsSaveSuccess();
    } catch (_) {
      return const SettingsSaveFailure(SettingsFailureKind.writeFailed);
    }
  }
}
