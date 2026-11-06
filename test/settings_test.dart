import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/settings/secret_store.dart';
import 'package:release_prepper/feature/settings/settings.dart';
import 'package:release_prepper/feature/settings/settings_controller.dart';
import 'package:release_prepper/feature/settings/settings_page.dart';
import 'package:release_prepper/feature/settings/settings_store.dart';
import 'package:release_prepper/feature/tab/tab_manager.dart';
import 'package:release_prepper/l10n/app_localizations.dart';
import 'package:release_prepper/service/network/pornolab_client.dart';

import 'fake_pornolab_client.dart';
import 'fake_secret_store.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('settings_test');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  SettingsStore store(String path) =>
      SettingsStore(appDirectory: () async => Directory(path));

  SettingsController controller(
    String path,
    SecretStore secrets, {
    String home = '/home/test',
    FakePornolabClient? client,
  }) => SettingsController(
    store: store(path),
    secretStore: secrets,
    homeDirectory: home,
    pathContext: p.context,
    client: client ?? FakePornolabClient(),
    appDirectory: () async => Directory(path),
  );

  Map<String, dynamic> readFile() => jsonDecode(
    File(p.join(directory.path, 'settings.json')).readAsStringSync(),
  ) as Map<String, dynamic>;

  // The page is built inside the provider so a test can remove the page while
  // the provider stays: that is what closing the tab does, and it is the point
  // the dispose-time commit is for.
  Widget app(SettingsController settings, {bool showPage = true}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>(create: (_) => settings),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: showPage ? SettingsPage() : const SizedBox()),
        ),
      );

  Future<void> pumpPage(
    WidgetTester tester,
    SettingsController settings,
  ) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    // The startup read is real IO, so it runs in runAsync, and the page is
    // built after it the way the app builds it after the read completes.
    await tester.runAsync(() async {
      await settings.load();
    });

    await tester.pumpWidget(app(settings));
  }

  // A store with the two credentials already in it, so the fields are seeded
  // with text before the page is built.
  FakeSecretStore credentialsStore() {
    final secrets = FakeSecretStore(available: true);

    secrets.values['pornolabUsername'] = 'the-user';
    secrets.values['pornolabPassword'] = 'the-password';

    return secrets;
  }

  // `TextFormField` keeps the flags it is given on the text field it builds, so
  // a test reads the field the widget renders rather than the form field.
  TextField field(WidgetTester tester, String key) => tester.widget<TextField>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(TextField),
    ),
  );

  // Closing the tab is what runs the last commit point, and the controller is
  // still there for it because the provider outlives the page. A test that has
  // typed into a field and not committed it has to close the page before it
  // ends, or that commit reaches a controller the provider has already disposed.
  Future<void> closePage(
    WidgetTester tester,
    SettingsController settings,
  ) async {
    await tester.pumpWidget(app(settings, showPage: false));
    await tester.pump();
  }

  Future<void> integration(
    WidgetTester tester,
    SettingsController settings,
  ) async {
    await pumpPage(tester, settings);

    await tester.tap(
      find.byKey(const ValueKey('settings-section-integration')),
    );
    await tester.pump();
  }

  Future<void> releases(
    WidgetTester tester,
    SettingsController settings,
  ) async {
    await pumpPage(tester, settings);

    await tester.tap(find.byKey(const ValueKey('settings-section-releases')));
    await tester.pump();
  }

  test('settings.json is written in the shape the format describes', () async {
    await store(directory.path).save(
      Settings(
        language: AppLanguage.ru,
        defaultReleaseDirectory: '~/Documents/Releases',
        defaultTorrentPrivate: false,
        defaultIncludeAppSignature: false,
        allowPlainSecrets: true,
        plainSecrets: {'stashdb': 'plain-value'},
      ),
    );

    expect(readFile(), {
      'schema': schemaVersion,
      'language': 'ru',
      'defaultReleaseDirectory': '~/Documents/Releases',
      'defaultTorrentPrivate': false,
      'defaultIncludeAppSignature': false,
      'allowPlainSecrets': true,
      'plainSecrets': {'stashdb': 'plain-value'},
    });
  });

  // A settings file that is not there is the same as a new one: the app follows
  // the system locale, the default release directory, the two release defaults,
  // and does not store secrets plainly.
  test('a missing settings file reads as the defaults', () async {
    final settings = await store(directory.path).load();

    expect(settings.language, AppLanguage.system);
    expect(settings.defaultReleaseDirectory, fallbackReleaseDirectory);
    expect(settings.defaultTorrentPrivate, isTrue);
    expect(settings.defaultIncludeAppSignature, isTrue);
    expect(settings.allowPlainSecrets, isFalse);
    expect(settings.plainSecrets, isEmpty);
  });

  // A language this version does not know has no translation to show, so it is
  // read as the system locale rather than guessed at. A value of the wrong type
  // is not kept either — a flag that is not a flag is read as the state a file
  // written before the choice existed was written with.
  test(
    'a file with values this version does not read falls back to the defaults',
    () async {
      await File(p.join(directory.path, 'settings.json')).writeAsString(
        '{"schema": 1, "language": "de", "defaultReleaseDirectory": "",'
        ' "defaultTorrentPrivate": "yes", "defaultIncludeAppSignature": 1,'
        ' "allowPlainSecrets": "yes", "plainSecrets": {"stashdb": 1}}',
      );

      final settings = await store(directory.path).load();

      expect(settings.language, AppLanguage.system);
      expect(settings.defaultReleaseDirectory, fallbackReleaseDirectory);
      expect(settings.defaultTorrentPrivate, isTrue);
      expect(settings.defaultIncludeAppSignature, isTrue);
      expect(settings.allowPlainSecrets, isFalse);
      expect(settings.plainSecrets, isEmpty);
    },
  );

  test('a settings file that cannot be read reads as the defaults', () async {
    await File(p.join(directory.path, 'settings.json'))
        .writeAsString('not json');

    expect((await store(directory.path).load()).language, AppLanguage.system);
  });

  // Settings are written as they change, so there is no save step and no dirty
  // flag.
  test('changing a setting writes the file immediately', () async {
    final settings = controller(
      directory.path,
      FakeSecretStore(available: true),
    );
    final changes = <int>[];

    settings.addListener(() => changes.add(1));

    // The read notifies, because that is how the app applies what was stored.
    await settings.load();

    expect(changes, hasLength(1));

    expect(
      await settings.setLanguage(AppLanguage.ru),
      isA<SettingsSaveSuccess>(),
    );
    expect(changes, hasLength(2));

    expect(
      await settings.setDefaultReleaseDirectory('/home/test/Releases'),
      isA<SettingsSaveSuccess>(),
    );
    expect(changes, hasLength(3));

    // The two release defaults are written the same way: a change notifies and
    // writes, and the same value again is not a write.
    expect(
      await settings.setDefaultTorrentPrivate(false),
      isA<SettingsSaveSuccess>(),
    );
    expect(changes, hasLength(4));

    expect(
      await settings.setDefaultIncludeAppSignature(false),
      isA<SettingsSaveSuccess>(),
    );
    expect(changes, hasLength(5));

    expect(readFile(), {
      'schema': schemaVersion,
      'language': 'ru',
      'defaultReleaseDirectory': '/home/test/Releases',
      'defaultTorrentPrivate': false,
      'defaultIncludeAppSignature': false,
      'allowPlainSecrets': false,
      'plainSecrets': {},
    });

    // The same value again is not a write, so it does not notify again.
    await settings.setLanguage(AppLanguage.ru);
    await settings.setDefaultReleaseDirectory('/home/test/Releases');
    await settings.setDefaultTorrentPrivate(false);
    await settings.setDefaultIncludeAppSignature(false);

    expect(changes, hasLength(5));

    settings.dispose();
  });

  // A settings file that cannot be written is reported.
  test('a settings file that cannot be written is reported', () async {
    File(p.join(directory.path, 'blocked'))
        .writeAsStringSync('a file, not a directory');

    final settings = controller(
      p.join(directory.path, 'blocked'),
      FakeSecretStore(available: true),
    );

    expect(
      await settings.setDefaultReleaseDirectory('/home/test/Releases'),
      isA<SettingsSaveFailure>().having(
        (failure) => failure.kind,
        'kind',
        SettingsFailureKind.writeFailed,
      ),
    );

    settings.dispose();
  });

  // The path is stored as the user wrote it, so `~` is expanded when the app
  // uses it rather than when it is stored. The expected path is built with the
  // context, so the test is right on a machine that is not POSIX.
  test('a stored path starting with ~ is expanded when the app uses it', () {
    final settings = controller(
      directory.path,
      FakeSecretStore(available: true),
      home: '/home/test',
    );

    expect(
      settings.defaultReleaseDirectory,
      p.join('/home/test', 'Documents', 'Releases'),
    );

    settings.settings.defaultReleaseDirectory = '/other/place';

    expect(settings.defaultReleaseDirectory, '/other/place');

    settings.dispose();
  });

  // The expanded path is built from segments with the context's separator rather
  // than by appending what the user wrote to the home: the `~` form is written
  // with `/` on every machine, and on Windows that leaves a `/` inside a path
  // whose other separators are `\`. The Windows context is named here because a
  // rule that reads the platform can only be tested on the platform it reads,
  // and this machine is not Windows.
  test('the expanded path is built with the context separator', () {
    expect(
      resolveUserPath(
        '~/Documents/Releases',
        home: r'C:\Users\test',
        context: p.windows,
      ),
      r'C:\Users\test\Documents\Releases',
    );
  });

  // The locale is what the app is given: null means the system locale, which is
  // what the `system` option asks for.
  test('the system language asks for no locale', () {
    final settings = controller(
      directory.path,
      FakeSecretStore(available: true),
    );

    expect(settings.locale, isNull);

    settings.settings.language = AppLanguage.ru;

    expect(settings.locale?.toLanguageTag(), 'ru');

    settings.dispose();
  });

  // A value goes to the credential store, not to settings.json: the point of
  // the store is that the values are not in a plain-text file.
  test('a value is written to the credential store and not to settings.json', () async {
    final secrets = FakeSecretStore(available: true);
    final settings = controller(directory.path, secrets);

    await settings.load();

    expect(settings.secretStoreAvailable, isTrue);

    expect(
      await settings.setSecret(SettingsField.stashdb.name, 'the-key'),
      isA<SettingsSaveSuccess>(),
    );

    expect(secrets.values, {'stashdb': 'the-key'});
    expect(settings.secretValues, {'stashdb': 'the-key'});
    expect(settings.settings.plainSecrets, isEmpty);

    // Clearing the field removes the entry rather than storing an empty string.
    await settings.setSecret(SettingsField.stashdb.name, '');

    expect(secrets.values, isEmpty);

    settings.dispose();
  });

  // When the store cannot be reached, a value is stored plainly only if the
  // user allowed it; otherwise there is nothing to write and the app says why.
  test(
    'a value is stored plainly only when plain storage is allowed',
    () async {
      final secrets = FakeSecretStore(available: false);
      final settings = controller(directory.path, secrets);

      await settings.load();

      expect(settings.secretStoreAvailable, isFalse);

      expect(
        await settings.setSecret(SettingsField.stashdb.name, 'the-key'),
        isA<SettingsSaveFailure>().having(
          (failure) => failure.kind,
          'kind',
          SettingsFailureKind.secretStoreUnavailable,
        ),
      );

      expect(settings.secretValues, isEmpty);

      expect(
        await settings.setAllowPlainSecrets(true),
        isA<SettingsSaveSuccess>(),
      );

      expect(
        await settings.setSecret(SettingsField.stashdb.name, 'the-key'),
        isA<SettingsSaveSuccess>(),
      );

      expect(settings.settings.plainSecrets, {'stashdb': 'the-key'});
      expect(settings.secretValues, {'stashdb': 'the-key'});
      expect(readFile()['plainSecrets'], {'stashdb': 'the-key'});

      settings.dispose();
    },
  );

  // The values that were stored plainly are still shown when the store is not
  // reachable, so the section works on a machine without one.
  test('plain values are read back when the store is not reachable', () async {
    await File(p.join(directory.path, 'settings.json')).writeAsString(
      jsonEncode({
        'schema': schemaVersion,
        'language': 'en',
        'defaultReleaseDirectory': '~/Documents/Releases',
        'allowPlainSecrets': true,
        'plainSecrets': {'stashdb': 'the-key'},
      }),
    );

    final settings = controller(
      directory.path,
      FakeSecretStore(available: false),
    );

    await settings.load();

    expect(settings.secretStoreAvailable, isFalse);
    expect(settings.secretValues, {'stashdb': 'the-key'});

    settings.dispose();
  });

  // Settings are app-level, so a second Settings tab would show the same thing
  // twice: the menu item selects the one that is already open.
  test('the settings tab is opened once', () {
    final tabManager = TabManager();

    final first = tabManager.addSettings();

    expect(tabManager.tabs.single.kind, AppTabKind.settings);

    expect(tabManager.addSettings(), first);
    expect(tabManager.tabs, hasLength(1));

    // A settings tab opened alongside another tab does not replace it.
    tabManager.addNewReleaseWizard();

    expect(tabManager.tabs, hasLength(2));
    expect(tabManager.addSettings(), first);
    expect(tabManager.selectedIndex, 0);

    tabManager.dispose();
  });

  testWidgets('the section list selects a section', (tester) async {
    final settings = controller(
      directory.path,
      FakeSecretStore(available: true),
    );

    await pumpPage(tester, settings);

    expect(find.byKey(const ValueKey('settingsSections')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-section-general')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-section-integration')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-section-releases')),
      findsOneWidget,
    );

    // General is the section shown at first, and it no longer holds the
    // directory: the directory belongs to the section about what the app does
    // with a release it has not made yet.
    expect(find.text('App language'), findsOneWidget);
    expect(find.byKey(const ValueKey('defaultReleaseDirectory')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-section-releases')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('defaultReleaseDirectory')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('settings-section-integration')),
    );
    await tester.pump();

    expect(find.text('StashDB API key'), findsOneWidget);
    expect(find.byKey(const ValueKey('appLanguage')), findsNothing);
  });

  testWidgets('choosing a language writes the settings file', (tester) async {
    final settings = controller(
      directory.path,
      FakeSecretStore(available: true),
    );

    await pumpPage(tester, settings);

    // Real IO, so the selection and the write run in runAsync.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('appLanguage')));
      await tester.pump();

      await tester.tap(find.text('Russian'));
      await tester.pump();

      await Future.delayed(const Duration(milliseconds: 100));
    });

    expect(readFile()['language'], 'ru');
    expect(settings.settings.language, AppLanguage.ru);
  });

  // The field shows the model, so it starts with the default the settings
  // carry.
  testWidgets(
    'the default release directory field shows the setting and writes it',
    (tester) async {
      final settings = controller(
        directory.path,
        FakeSecretStore(available: true),
      );

      await releases(tester, settings);

      final field = find.byKey(const ValueKey('defaultReleaseDirectory'));

      expect(field, findsOneWidget);
      expect(find.text(fallbackReleaseDirectory), findsOneWidget);

      await tester.runAsync(() async {
        await tester.enterText(field, '/home/test/Releases');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        await Future.delayed(const Duration(milliseconds: 100));
      });

      expect(readFile()['defaultReleaseDirectory'], '/home/test/Releases');
      expect(settings.settings.defaultReleaseDirectory, '/home/test/Releases');
    },
  );

  // The field and the folder button are one row, in the order the row builds
  // them: the field capped at the same width as every other field on the page,
  // the button to its right.
  testWidgets('the folder button is on the same line as the field', (
    tester,
  ) async {
    final settings = controller(
      directory.path,
      FakeSecretStore(available: true),
    );

    await releases(tester, settings);

    final fieldRect = tester.getRect(
      find.byKey(const ValueKey('defaultReleaseDirectory')),
    );
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('chooseReleaseDirectory')),
    );

    expect(buttonRect.left, greaterThan(fieldRect.right));

    // The row centres its children, so the two sit on one line.
    expect(buttonRect.center.dy, equals(fieldRect.center.dy));

    // The row does not make the field wider than the rest of the page: at a
    // wide window the cap is what decides its width.
    expect(fieldRect.width, equals(400.0));
  });

  // Below the width the two controls need, each is its own line, in the same
  // order. The width is not a page breakpoint: it is what the field needs to
  // show its label and what the button's label needs, so it moves with a longer
  // word in the other language.
  testWidgets('the directory row stacks when the two controls do not fit', (
    tester,
  ) async {
    final settings = controller(
      directory.path,
      FakeSecretStore(available: true),
    );

    await releases(tester, settings);

    tester.view.physicalSize = const Size(300, 800);
    await tester.pumpAndSettle();

    final fieldRect = tester.getRect(
      find.byKey(const ValueKey('defaultReleaseDirectory')),
    );
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('chooseReleaseDirectory')),
    );

    expect(buttonRect.top, greaterThan(fieldRect.bottom));
  });

  // The two defaults show the state the settings hold. A click is a write, the
  // same as a field's commit: they decide what a release the app has not made
  // yet is built from, so nothing here changes a release that exists.
  testWidgets(
    'a default is shown as the settings hold it and written when it is clicked',
    (tester) async {
      final settings = controller(
        directory.path,
        FakeSecretStore(available: true),
      );

      await releases(tester, settings);

      // On by default, which is the state a settings file that does not exist
      // has.
      for (final key in [
        'defaultTorrentPrivate',
        'defaultIncludeAppSignature',
      ]) {
        expect(
          tester.widget<Checkbox>(find.byKey(ValueKey(key))).value,
          isTrue,
        );
      }

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('defaultTorrentPrivate')));
        await tester.pump();

        await Future.delayed(const Duration(milliseconds: 100));
      });

      expect(readFile()['defaultTorrentPrivate'], false);
      expect(settings.settings.defaultTorrentPrivate, isFalse);

      // The page shows the model, so a change made through the controller is
      // what the page shows, as the login row is.
      await tester.runAsync(() async {
        await settings.setDefaultIncludeAppSignature(false);

        await Future.delayed(const Duration(milliseconds: 100));
      });

      await tester.pump();

      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('defaultIncludeAppSignature')),
            )
            .value,
        isFalse,
      );
    },
  );

  // When the store is not reachable the page says what to enable and offers the
  // plain fallback; turning it on is a write, and only then can a value be
  // stored.
  testWidgets(
    'the Integration section shows the store state and the plain option',
    (tester) async {
      final settings = controller(
        directory.path,
        FakeSecretStore(available: false),
      );

      await pumpPage(tester, settings);

      await tester.tap(
        find.byKey(const ValueKey('settings-section-integration')),
      );
      await tester.pump();

      expect(
        find.textContaining(
          'The credential store is not available on this machine',
        ),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('allowPlainSecrets')));
        await tester.pump();

        await Future.delayed(const Duration(milliseconds: 100));
      });

      expect(readFile()['allowPlainSecrets'], true);

      // The field is shown in both states; only where the value goes changes.
      await tester.runAsync(() async {
        await tester.enterText(
          find.byKey(const ValueKey('secret-stashdb')),
          'the-key',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        await Future.delayed(const Duration(milliseconds: 100));
      });

      expect(readFile()['plainSecrets'], {'stashdb': 'the-key'});
    },
  );

  // With a reachable store the value goes to it and settings.json keeps no
  // copy.
  testWidgets('a key typed into the field is written to the credential store', (
    tester,
  ) async {
    final secrets = FakeSecretStore(available: true);
    final settings = controller(directory.path, secrets);

    await pumpPage(tester, settings);

    await tester.tap(
      find.byKey(const ValueKey('settings-section-integration')),
    );
    await tester.pump();

    await tester.runAsync(() async {
      await tester.enterText(
        find.byKey(const ValueKey('secret-stashdb')),
        'the-key',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      await Future.delayed(const Duration(milliseconds: 100));
    });

    expect(secrets.values, {'stashdb': 'the-key'});

    // Nothing in settings.json changes here: the value went to the store, so
    // the file is not written at all and the model is what shows nothing is
    // stored plainly.
    expect(settings.settings.plainSecrets, isEmpty);
  });

  // A field commits when it loses focus, not only when it is submitted: a
  // settings tab has no save step, so text left in a field has to reach the
  // model when the user leaves the field.
  testWidgets('a settings field writes when it loses focus', (tester) async {
    final settings = controller(
      directory.path,
      FakeSecretStore(available: true),
    );

    await releases(tester, settings);

    final field = find.byKey(const ValueKey('defaultReleaseDirectory'));

    await tester.runAsync(() async {
      await tester.tap(field);
      await tester.pump();

      await tester.enterText(field, '/home/test/Releases');

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      await Future.delayed(const Duration(milliseconds: 100));
    });

    expect(readFile()['defaultReleaseDirectory'], '/home/test/Releases');
  });

  // Closing the tab is the third commit point. Nothing was submitted and focus
  // was not lost: the text was still in the field when the page was removed.
  testWidgets('text still in a field is written when the tab closes', (
    tester,
  ) async {
    final secrets = FakeSecretStore(available: true);
    final settings = controller(directory.path, secrets);

    await pumpPage(tester, settings);

    await tester.tap(
      find.byKey(const ValueKey('settings-section-integration')),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('secret-stashdb')),
      'the-key',
    );

    await tester.pumpWidget(app(settings, showPage: false));

    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 100));
    });

    expect(secrets.values, {'stashdb': 'the-key'});
  });

  // The field list is the record the app reads back, and the mask flag is a
  // display rule rather than a storage rule: every entry here is stored the same
  // way, and the username is the one shown plainly (`ai/pornolab_login.md` §2).
  test('the field list holds the keys and the mask flag', () {
    expect(SettingsField.values.map((field) => field.name).toList(), [
      'stashdb',
      'postimages',
      'pornolabUsername',
      'pornolabPassword',
    ]);

    expect(SettingsField.pornolabUsername.masked, isFalse);

    for (final field in [
      SettingsField.stashdb,
      SettingsField.postimages,
      SettingsField.pornolabPassword,
    ]) {
      expect(field.masked, isTrue);
    }

    // The cookie is not a field the page draws, so it is a key rather than an
    // entry in the list.
    expect(pornolabCookieKey, 'pornolabCookie');
  });

  // The three controls are one row, and the flag is what decides which field is
  // obscured rather than the loop masking every field. With a credential empty
  // the button cannot be pressed, and typing is what makes it pressable — the
  // row is not a field's own state, so the page has to rebuild on a character.
  testWidgets('the row shows the username plainly and the password masked', (
    tester,
  ) async {
    final settings = controller(
      directory.path,
      FakeSecretStore(available: true),
    );

    await integration(tester, settings);

    // `TextFormField` keeps the flag on the text field it builds, so the test
    // reads the field the widget renders rather than the form field.
    for (final entry in {
      'secret-pornolabUsername': false,
      'secret-pornolabPassword': true,
    }.entries) {
      expect(field(tester, entry.key).obscureText, entry.value);
    }

    // The three controls are one row rather than three lines: they are on the
    // same horizontal line, in the order the row builds them.
    final username = tester.getRect(
      find.byKey(const ValueKey('secret-pornolabUsername')),
    );
    final password = tester.getRect(
      find.byKey(const ValueKey('secret-pornolabPassword')),
    );
    final button = find.byKey(const ValueKey('pornolabLogin'));
    final buttonRect = tester.getRect(button);

    expect(password.left, greaterThan(username.right));
    expect(buttonRect.left, greaterThan(password.right));

    // The row centres its children, so the three sit on one line.
    expect(password.center.dy, equals(username.center.dy));
    expect(buttonRect.center.dy, equals(username.center.dy));

    expect(find.text('Log in'), findsOneWidget);
    expect(tester.widget<TextButton>(button).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('secret-pornolabUsername')),
      'the-user',
    );
    await tester.enterText(
      find.byKey(const ValueKey('secret-pornolabPassword')),
      'the-password',
    );
    await tester.pump();

    expect(tester.widget<TextButton>(button).onPressed, isNotNull);

    // The text is still in the fields here, so the test ends the way closing
    // the tab does.
    await closePage(tester, settings);
  });

  // Below the width where the three controls fit, each is its own row. The width
  // is not a page breakpoint: it is what the three controls need, so it moves
  // with a longer word in the other language.
  testWidgets('the row stacks when the three controls do not fit', (
    tester,
  ) async {
    final settings = controller(
      directory.path,
      FakeSecretStore(available: true),
    );

    await integration(tester, settings);

    // Narrower than the two fields and the button together need, so the row is
    // three lines in the same order.
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();

    final username = tester.getRect(
      find.byKey(const ValueKey('secret-pornolabUsername')),
    );
    final password = tester.getRect(
      find.byKey(const ValueKey('secret-pornolabPassword')),
    );
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('pornolabLogin')),
    );

    expect(password.top, greaterThan(username.bottom));
    expect(buttonRect.top, greaterThan(password.bottom));

    // Below the cap, so each control takes the width the row has rather than a
    // share of it, and the two fields are the same width as each other and as
    // the row.
    expect(password.width, equals(username.width));
  });

  // The row's fields are capped at the same width as every other field on the
  // page, so the row is not the place where a field can be wider than the rest
  // of it. At a wide window the cap is what decides their width.
  testWidgets('the row caps its fields at the same width as the other fields', (
    tester,
  ) async {
    final settings = controller(
      directory.path,
      FakeSecretStore(available: true),
    );

    await integration(tester, settings);

    final key = tester.getRect(find.byKey(const ValueKey('secret-stashdb')));
    final username = tester.getRect(
      find.byKey(const ValueKey('secret-pornolabUsername')),
    );
    final password = tester.getRect(
      find.byKey(const ValueKey('secret-pornolabPassword')),
    );

    expect(username.width, equals(key.width));
    expect(password.width, equals(key.width));
  });

  // A field commits when it loses focus or when the page closes; the button is a
  // third commit point, so a request is never built from values the model does
  // not hold. A login that worked says nothing, because the row itself shows the
  // change, and a credential cannot change while a session exists.
  testWidgets('the button commits the fields before it calls the site', (
    tester,
  ) async {
    final secrets = FakeSecretStore(available: true);
    final client = FakePornolabClient(
      loginResult: const LoggedIn('session=abc'),
    );
    final settings = controller(directory.path, secrets, client: client);

    await integration(tester, settings);

    await tester.enterText(
      find.byKey(const ValueKey('secret-pornolabUsername')),
      'the-user',
    );
    await tester.enterText(
      find.byKey(const ValueKey('secret-pornolabPassword')),
      'the-password',
    );

    // The character is what makes the button pressable, so the frame that reads
    // it has to be built before the button is pressed.
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('pornolabLogin')));
    await tester.pump();

    // The values the call was made with are the ones the model holds.
    expect(client.loginCalls, [
      [directory.path, 'the-user', 'the-password', '', ''],
    ]);

    expect(secrets.values, {
      'pornolabUsername': 'the-user',
      'pornolabPassword': 'the-password',
      'pornolabCookie': 'session=abc',
    });

    expect(
      find.text('The site did not accept the username and the password.'),
      findsNothing,
    );

    for (final key in ['secret-pornolabUsername', 'secret-pornolabPassword']) {
      expect(field(tester, key).enabled, isFalse);
    }

    final button = find.byKey(const ValueKey('pornolabLogin'));

    expect(find.text('Log out'), findsOneWidget);
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);

    // The red the page already uses for a failed write, on a button for the
    // first time.
    expect(
      tester
          .widget<TextButton>(button)
          .style
          ?.foregroundColor
          ?.resolve(const <WidgetState>{}),
      Theme.of(tester.element(button)).colorScheme.error,
    );
  });

  // The button cannot be pressed twice while a call is running.
  testWidgets('the button is disabled while a call runs', (tester) async {
    final client = FakePornolabClient();
    client.loginPending = Completer<PornolabResult>();

    final settings = controller(
      directory.path,
      credentialsStore(),
      client: client,
    );

    await integration(tester, settings);

    await tester.tap(find.byKey(const ValueKey('pornolabLogin')));
    await tester.pump();

    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('pornolabLogin')))
          .onPressed,
      isNull,
    );
  });

  // The outcome of a login is said in the section, next to the row, in the
  // colour that says which it was; the page's snackbar stays for what it is for
  // now, a value that was not written.
  testWidgets('a login that did not work is said in the section', (
    tester,
  ) async {
    final settings = controller(directory.path, credentialsStore());

    await integration(tester, settings);

    await tester.tap(find.byKey(const ValueKey('pornolabLogin')));
    await tester.pump();

    const word = 'The site did not accept the username and the password.';

    expect(find.text(word), findsOneWidget);

    expect(
      tester.widget<Text>(find.text(word)).style?.color,
      Theme.of(tester.element(find.text(word))).colorScheme.error,
    );
  });

  // A login that worked is said in the same space, in the colour that says it
  // worked. The word is the page's own rather than part of the set the two
  // features share, because a run has nothing to show for a login that worked —
  // its success is the link it was given (`ai/pornolab_login.md` §3, §8).
  testWidgets('a login that worked is said in the section, in green', (
    tester,
  ) async {
    final client = FakePornolabClient(
      loginResult: const LoggedIn('session=abc'),
    );

    final settings = controller(
      directory.path,
      credentialsStore(),
      client: client,
    );

    await integration(tester, settings);

    await tester.tap(find.byKey(const ValueKey('pornolabLogin')));
    await tester.pump();

    expect(find.text('Login accepted.'), findsOneWidget);

    expect(
      tester.widget<Text>(find.text('Login accepted.')).style?.color,
      Colors.green,
    );
  });

  // The row reads the controller rather than holding its own state, so a login
  // made through the controller changes what it shows.
  testWidgets('the row changes when a login made elsewhere stores a cookie', (
    tester,
  ) async {
    final client = FakePornolabClient(
      loginResult: const LoggedIn('session=abc'),
    );
    final settings = controller(
      directory.path,
      credentialsStore(),
      client: client,
    );

    await integration(tester, settings);

    expect(find.text('Log in'), findsOneWidget);

    await settings.login();
    await tester.pump();

    expect(find.text('Log out'), findsOneWidget);
  });

  // Logging out does not call the site: the app has no session of its own beyond
  // the value it stored, so removing the value is what logging out means for it,
  // and the next login is a new call.
  testWidgets('logging out removes the value and makes no request', (
    tester,
  ) async {
    final secrets = credentialsStore();
    final client = FakePornolabClient(
      loginResult: const LoggedIn('session=abc'),
    );
    final settings = controller(directory.path, secrets, client: client);

    await integration(tester, settings);

    await tester.tap(find.byKey(const ValueKey('pornolabLogin')));
    await tester.pump();

    expect(client.loginCalls, hasLength(1));

    // The word for the login that made the session goes with the session: the
    // space says the outcome of the last action, and a logout that works says
    // nothing.
    expect(find.text('Login accepted.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pornolabLogin')));
    await tester.pump();

    expect(find.text('Login accepted.'), findsNothing);

    expect(secrets.values['pornolabCookie'], isNull);
    expect(client.loginCalls, hasLength(1));

    // The fields can be edited again, because there is no session to change.
    expect(field(tester, 'secret-pornolabUsername').enabled, isTrue);

    await tester.tap(find.byKey(const ValueKey('pornolabLogin')));
    await tester.pump();

    expect(client.loginCalls, hasLength(2));
  });

  // The captcha is what the answer asked for, so the word comes first and the
  // image and the field after it. The image is not stored anywhere: each captcha
  // is a different URL, so the widget resolves it from the page that asked for it
  // (`ai/pornolab_login.md` §3, §6).
  testWidgets('the page shows the captcha the answer asked for', (
    tester,
  ) async {
    final captcha = LoginCaptcha(
      imageUrl: 'https://static.pornolab.net/captcha/0/25/abc.jpg',
      sessionId: 'BsbMQsHd2NoihtWqHS0V',
      fieldName: 'cap_code_f8d8fa25d65dc2f22824bce923bb5c3a',
      cookie: 'plm=1',
    );

    final client = FakePornolabClient(
      loginResult: PornolabFailure(
        PornolabFailureKind.captchaRequired,
        captcha: captcha,
      ),
    );

    final settings = controller(
      directory.path,
      credentialsStore(),
      client: client,
    );

    await integration(tester, settings);

    await tester.tap(find.byKey(const ValueKey('pornolabLogin')));
    await tester.pump();

    expect(find.text('The site is asking for a code.'), findsOneWidget);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
    expect((image.image as NetworkImage).url, captcha.imageUrl);

    expect(find.byKey(const ValueKey('captchaCode')), findsOneWidget);
  });

  // A login with an empty code is the same answer again, so there is nothing to
  // send and the button waits for the code. The request it then makes is the
  // second half of the login: the captcha the page gave and what was typed into
  // it (§6).
  testWidgets('the second login carries the captcha and the code', (
    tester,
  ) async {
    final captcha = LoginCaptcha(
      imageUrl: 'https://static.pornolab.net/captcha/0/25/abc.jpg',
      sessionId: 'BsbMQsHd2NoihtWqHS0V',
      fieldName: 'cap_code_f8d8fa25d65dc2f22824bce923bb5c3a',
      cookie: 'plm=1',
    );

    final client = FakePornolabClient(
      loginResult: PornolabFailure(
        PornolabFailureKind.captchaRequired,
        captcha: captcha,
      ),
    );

    final settings = controller(
      directory.path,
      credentialsStore(),
      client: client,
    );

    await integration(tester, settings);

    final button = find.byKey(const ValueKey('pornolabLogin'));

    await tester.tap(button);
    await tester.pump();

    // The first half of the login is the form as it stands, with no captcha.
    expect(client.loginCalls, [
      [directory.path, 'the-user', 'the-password', '', ''],
    ]);

    expect(tester.widget<TextButton>(button).onPressed, isNull);

    await tester.enterText(find.byKey(const ValueKey('captchaCode')), 'AB12');
    await tester.pump();

    expect(tester.widget<TextButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await tester.pump();

    expect(client.loginCalls, [
      [directory.path, 'the-user', 'the-password', '', ''],
      [directory.path, 'the-user', 'the-password', captcha.fieldName, 'AB12'],
    ]);
  });

  // A captcha is kept only for the answer that asked for it: the code belongs to
  // the page that asked, so a new captcha is a new code and an answer that does
  // not ask for one clears it.
  testWidgets('a captcha is kept only for the answer that asked for it', (
    tester,
  ) async {
    final captcha = LoginCaptcha(
      imageUrl: 'https://static.pornolab.net/captcha/0/25/abc.jpg',
      sessionId: 'BsbMQsHd2NoihtWqHS0V',
      fieldName: 'cap_code_f8d8fa25d65dc2f22824bce923bb5c3a',
      cookie: 'plm=1',
    );

    final client = FakePornolabClient(
      loginResult: PornolabFailure(
        PornolabFailureKind.captchaRequired,
        captcha: captcha,
      ),
    );

    final settings = controller(
      directory.path,
      credentialsStore(),
      client: client,
    );

    await integration(tester, settings);

    final button = find.byKey(const ValueKey('pornolabLogin'));

    await tester.tap(button);
    await tester.pump();

    await tester.enterText(find.byKey(const ValueKey('captchaCode')), 'AB12');
    await tester.pump();

    // The answer that does not ask for a code takes the image and the field
    // away, and the code typed for the page before it is not kept.
    client.loginResult = const LoggedIn('session=abc');

    await tester.tap(button);
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.byKey(const ValueKey('captchaCode')), findsNothing);
    expect(client.loginCalls, hasLength(2));
  });
}
