import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:release_prepper/feature/draft/draft_section.dart';
import 'package:release_prepper/feature/message/message_store.dart';
import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/tracker.dart';
import 'package:release_prepper/feature/settings/settings.dart';
import 'package:release_prepper/feature/settings/settings_controller.dart';
import 'package:release_prepper/feature/settings/settings_store.dart';
import 'package:release_prepper/l10n/app_localizations.dart';
import 'package:release_prepper/service/launcher/url_opener.dart';
import 'package:release_prepper/service/network/pornolab_client.dart';

import 'fake_pornolab_client.dart';
import 'fake_secret_store.dart';

// The launcher answers with the result the test gives instead of asking the OS.
class _FakeUrlOpener extends UrlOpener {
  _FakeUrlOpener(this.result);

  final OpenUrlResult result;

  /// The links each call asked for.
  final calls = <String>[];

  @override
  Future<OpenUrlResult> open(String url) async {
    calls.add(url);

    return result;
  }
}

// The editor registers this section's rebuild. A test that does not look at what
// the Message section changes does not need it, so it ignores it. A default
// parameter must be a constant, so this is a named function rather than a
// lambda.
void ignoreMessageChanged(void Function() rebuild) {}

void main() {
  late Directory directory;
  late SettingsController settings;
  late FakePornolabClient client;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('draft_section_test');

    // One client, given to both the section and the settings feature: both take
    // it as a constructor parameter (rule 4), and the same fake is what a test
    // reads the calls back from.
    client = FakePornolabClient();

    settings = SettingsController(
      store: SettingsStore(appDirectory: () async => directory),
      secretStore: FakeSecretStore(available: true),
      homeDirectory: '/home/test',
      pathContext: p.context,
      client: client,
      appDirectory: () async => directory,
    );

    await settings.load();
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  void write(String fileName, String text) =>
      File(MessageStore().filePath(directory.path, fileName))
          .writeAsStringSync(text);

  // The gate is the cookie, because the app does not make a login by itself
  // (`ai/pornolab_login.md` §7). So a test that wants a run to be possible has
  // to give it. Reading the value from the credential store is what
  // `test/settings_test.dart` covers, so this sets it directly.
  Future<void> cookie() async =>
      await settings.setSecret(pornolabCookieKey, 'the-cookie');

  FieldValues values(Map<String, String> entries) {
    final fields = FieldValues();

    for (final entry in entries.entries) {
      fields.setValue(entry.key, entry.value);
    }

    return fields;
  }

  Release release({Map<String, String> fields = const {}}) => Release(
    name: directory.path,
    directoryPath: directory.path,
    tracker: Tracker.pornolab,
    releaseType: ReleaseType.singleVideo,
    source: '/home/user/videos/movie.mp4',
    fields: values(fields),
    items: [],
  );

  const saved = DraftSaved(
    42,
    draftUrl:
        'https://pornolab.net/forum/posting.php?mode=newtopic&f=1013&draft=42',
  );

  const forumUrl = 'https://pornolab.net/forum/viewforum.php?f=1013';

  Future<void> section(
    WidgetTester tester, {
    required Release release,
    required PornolabResult result,
    required List<Map<String, String>> applied,
    UrlOpener opener = const UrlOpener(),
    void Function(void Function()) subscribeMessageChanged =
        ignoreMessageChanged,
  }) async {
    client.saveResult = result;

    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<MessageStore>(create: (_) => MessageStore()),
          Provider<PornolabClient>(create: (_) => client),
          Provider<UrlOpener>(create: (_) => opener),
          ChangeNotifierProvider<SettingsController>(create: (_) => settings),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DraftSection(
                release: release,
                onApply: (values) {
                  applied.add(values);

                  // The editor is the widget with the write path, and this test
                  // is not the editor, so this is the part of it the section
                  // reads back: the model is what the row's problem is computed
                  // from.
                  for (final entry in values.entries) {
                    release.fields.setValue(entry.key, entry.value);
                  }
                },
                subscribeMessageChanged: subscribeMessageChanged,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
  }

  FilledButton button(WidgetTester tester) => tester.widget<FilledButton>(
    find.byKey(const ValueKey('draftUploadButton')),
  );

  // The clipboard is a platform channel, so a test records what the app writes
  // to it, the same way the Message section's test does.
  List<String> recordClipboard(WidgetTester tester) {
    final copied = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }

      return null;
    });

    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    return copied;
  }

  // The section is the one that sends what the Message section shows, so with
  // nothing generated there is nothing it can send, and it says that instead of
  // offering an action.
  testWidgets('a section with nothing to send says what has to happen first', (
    tester,
  ) async {
    await section(tester, release: release(), result: saved, applied: []);

    expect(find.text('Generate a message first'), findsOneWidget);
    expect(find.byKey(const ValueKey('draftUploadButton')), findsNothing);
  });

  // The row is drawn only when there is something to send, so a section with no
  // message shows what has to happen first and nothing else.
  testWidgets(
    'the parent forum row is not drawn while there is nothing to send',
    (tester) async {
      await section(tester, release: release(), result: saved, applied: []);

      expect(find.byKey(const ValueKey('draftForumInput')), findsNothing);
    },
  );

  // The button is there when there is something to send, and it is disabled
  // while one of the things a run reads is missing. The tooltip says which, in
  // the order a run needs them: the message, then the login the app does not
  // make by itself, then the field.
  testWidgets(
    'the button names what a run is missing, in the order it needs it',
    (tester) async {
      write(MessageStore.messageFile, 'the message');

      await section(tester, release: release(), result: saved, applied: []);

      expect(find.text('Generate a message first'), findsNothing);

      final button = find.byKey(const ValueKey('draftUploadButton'));
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'Log in in Settings → Integration',
      );

      await cookie();
      await tester.pump();

      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'Set the parent forum',
      );

      await tester.enterText(
        find.byKey(const ValueKey('draftForumInput')),
        forumUrl,
      );
      await tester.pump();

      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      expect(find.byType(Tooltip), findsNothing);
    },
  );

  testWidgets('the row shows the shape the field does not have', (
    tester,
  ) async {
    write(MessageStore.messageFile, 'the message');
    await cookie();

    await section(tester, release: release(), result: saved, applied: []);

    await tester.enterText(
      find.byKey(const ValueKey('draftForumInput')),
      '1013',
    );
    await tester.pump();

    // The row shows the problem with the words the rule has, the same ones the
    // editor puts under a row it marks (rule 13).
    expect(
      find.text('Parent forum must be a full forum URL with an f parameter.'),
      findsOneWidget,
    );
    expect(button(tester).onPressed, isNull);
  });

  // The field is written through the editor's single write path, as the Stash
  // row writes what it applies, so the tab becomes dirty and Ctrl+S saves it.
  testWidgets('typing the parent forum writes it through the write path', (
    tester,
  ) async {
    write(MessageStore.messageFile, 'the message');
    await cookie();

    final applied = <Map<String, String>>[];

    await section(tester, release: release(), result: saved, applied: applied);

    await tester.enterText(
      find.byKey(const ValueKey('draftForumInput')),
      forumUrl,
    );
    await tester.pump();

    expect(applied, [
      {'parentForum': forumUrl},
    ]);
    expect(button(tester).onPressed, isNotNull);
  });

  // A run is the call the client makes, and the values it is built from are the
  // two files the Message section owns rather than the box.
  testWidgets('a run sends what the two files hold', (tester) async {
    write(MessageStore.titleFile, 'the title');
    write(MessageStore.messageFile, 'the message');
    await cookie();

    final applied = <Map<String, String>>[];

    await section(
      tester,
      release: release(fields: {'parentForum': forumUrl}),
      result: saved,
      applied: applied,
    );

    await tester.tap(find.byKey(const ValueKey('draftUploadButton')));
    await tester.pump();

    expect(client.saveCalls, [
      ['the-cookie', 1013, 0, 'the title', 'the message'],
    ]);
  });

  // The link is a value the release stores, so it is written through the same
  // path a field is written through.
  testWidgets(
    'a run that saved the draft writes the link through the write path',
    (tester) async {
      write(MessageStore.messageFile, 'the message');
      await cookie();

      final applied = <Map<String, String>>[];

      await section(
        tester,
        release: release(fields: {'parentForum': forumUrl}),
        result: saved,
        applied: applied,
      );

      await tester.tap(find.byKey(const ValueKey('draftUploadButton')));
      await tester.pump();

      expect(applied, [
        {'draftUrl': saved.draftUrl},
      ]);
      expect(find.text(saved.draftUrl), findsOneWidget);
    },
  );

  // A run that had to make a new draft says so, because the link the release
  // holds changed and the user cannot see why otherwise
  // (`ai/uploading_draft.md` §6).
  testWidgets('a run that made a new draft says the stored one was gone', (
    tester,
  ) async {
    write(MessageStore.messageFile, 'the message');
    await cookie();

    const recreated = DraftSaved(
      43,
      draftUrl: 'https://pornolab.net/forum/posting.php?mode=newtopic&f=1013&draft=43',
      recreated: true,
    );

    final applied = <Map<String, String>>[];

    await section(
      tester,
      release: release(fields: {'parentForum': forumUrl}),
      result: recreated,
      applied: applied,
    );

    await tester.tap(find.byKey(const ValueKey('draftUploadButton')));
    await tester.pump();

    expect(
      find.text(
        'The draft the stored link pointed to is no longer on the site, '
        'so a new one was created.',
      ),
      findsOneWidget,
    );

    // The new link is what the release keeps: the one that pointed at the
    // deleted draft is replaced through the same write path.
    expect(applied, [
      {'draftUrl': recreated.draftUrl},
    ]);
  });

  // A run that updated the draft the stored link points at says nothing, as the
  // other runs do, because the link is the result.
  testWidgets('a run that updated the stored draft says nothing', (
    tester,
  ) async {
    write(MessageStore.messageFile, 'the message');
    await cookie();

    await section(
      tester,
      release: release(fields: {'parentForum': forumUrl}),
      result: saved,
      applied: [],
    );

    await tester.tap(find.byKey(const ValueKey('draftUploadButton')));
    await tester.pump();

    expect(find.textContaining('no longer on the site'), findsNothing);
  });

  // A draft id already stored is the draft the run updates, so it is read from
  // the link rather than assumed to be new.
  testWidgets('a run on a stored link updates that draft', (tester) async {
    write(MessageStore.messageFile, 'the message');
    await cookie();

    await section(
      tester,
      release: release(
        fields: {'parentForum': forumUrl, 'draftUrl': saved.draftUrl},
      ),
      result: saved,
      applied: [],
    );

    await tester.tap(find.byKey(const ValueKey('draftUploadButton')));
    await tester.pump();

    expect(client.saveCalls.first[2], 42);
  });

  // The app does not make a login by itself, because the site asks for a
  // captcha after a few logins and the app cannot read one
  // (`ai/pornolab_login.md` §7). So a run with nothing stored is not made, and
  // the section says where to make it.
  testWidgets('a run with no cookie stored says where to log in', (
    tester,
  ) async {
    write(MessageStore.messageFile, 'the message');

    await section(
      tester,
      release: release(fields: {'parentForum': forumUrl}),
      result: saved,
      applied: [],
    );

    expect(button(tester).onPressed, isNull);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      'Log in in Settings → Integration',
    );

    expect(client.saveCalls, isEmpty);
  });

  // A cookie the site does not accept is said as the result it is, and the run
  // is not made again: the app does not log in by itself, so the login stays
  // the settings page's action (§7). The value is not cleared either — the app
  // does not decide a cookie is wrong, the site's answer says it is, and the
  // user is what logs in again.
  testWidgets('a cookie the site does not accept is said, and not retried', (
    tester,
  ) async {
    write(MessageStore.messageFile, 'the message');
    await cookie();

    await section(
      tester,
      release: release(fields: {'parentForum': forumUrl}),
      result: const PornolabFailure(PornolabFailureKind.cookieRefused),
      applied: [],
    );

    await tester.tap(find.byKey(const ValueKey('draftUploadButton')));
    await tester.pump();

    expect(client.saveCalls, hasLength(1));
    expect(client.loginCalls, isEmpty);
    expect(settings.secretValues[pornolabCookieKey], 'the-cookie');

    expect(
      find.text(
        'The site did not accept the cookie. Log in again in Settings → Integration.',
      ),
      findsOneWidget,
    );
  });

  // A run that fails is not run again, whatever the reason was.
  testWidgets('a run that fails is not made again', (tester) async {
    write(MessageStore.messageFile, 'the message');
    await cookie();

    await section(
      tester,
      release: release(fields: {'parentForum': forumUrl}),
      result: const PornolabFailure(PornolabFailureKind.badResponse),
      applied: [],
    );

    await tester.tap(find.byKey(const ValueKey('draftUploadButton')));
    await tester.pump();

    expect(client.saveCalls, hasLength(1));
    expect(client.loginCalls, isEmpty);

    expect(
      find.text('The answer from the site could not be read.'),
      findsOneWidget,
    );
  });

  // What a run said is what the section shows. The words for a field problem are
  // the same ones the row uses, so the two cannot disagree.
  testWidgets('a run the site refused says what it said', (tester) async {
    write(MessageStore.messageFile, 'the message');
    await cookie();

    await section(
      tester,
      release: release(fields: {'parentForum': forumUrl}),
      result: const PornolabFailure(PornolabFailureKind.tokenRejected),
      applied: [],
    );

    await tester.tap(find.byKey(const ValueKey('draftUploadButton')));
    await tester.pump();

    expect(
      find.text('The site did not accept the form token. Try again.'),
      findsOneWidget,
    );
  });

  // The link is shown whenever the release has one, even when the box was reset:
  // a stored link is not something a reset takes away. The row is not drawn
  // there, because there is nothing to send, but the link is the result a run
  // already made, so it stays.
  testWidgets('the stored link opens the browser', (tester) async {
    final opener = _FakeUrlOpener(const UrlOpened());

    await section(
      tester,
      release: release(fields: {'draftUrl': saved.draftUrl}),
      result: saved,
      applied: [],
      opener: opener,
    );

    expect(find.byKey(const ValueKey('draftForumInput')), findsNothing);
    expect(find.widgetWithText(TextButton, saved.draftUrl), findsOneWidget);

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(opener.calls, [saved.draftUrl]);
    expect(find.text('Could not open the link in the browser.'), findsNothing);
  });

  // The title says which tracker the draft goes to, and the label says what the
  // link is. The label is drawn only when there is a link, because with nothing
  // there is nothing to label.
  testWidgets('the title says which tracker, and the link says what it is', (
    tester,
  ) async {
    await section(
      tester,
      release: release(fields: {'draftUrl': saved.draftUrl}),
      result: saved,
      applied: [],
      opener: _FakeUrlOpener(const UrlOpened()),
    );

    expect(find.text('Upload draft to tracker'), findsOneWidget);
    expect(find.text('Draft link on tracker'), findsOneWidget);
  });

  testWidgets('with no link there is nothing to label', (tester) async {
    await section(tester, release: release(), result: saved, applied: []);

    expect(find.text('Draft link on tracker'), findsNothing);
  });

  // The copy button is the same call the Message section's copy buttons make, so
  // the test reads what the app writes to the clipboard channel. A left click on
  // the link still opens the browser; the button is what copies it.
  testWidgets('the copy button copies the link', (tester) async {
    final copied = recordClipboard(tester);

    await section(
      tester,
      release: release(fields: {'draftUrl': saved.draftUrl}),
      result: saved,
      applied: [],
      opener: _FakeUrlOpener(const UrlOpened()),
    );

    await tester.tap(find.byKey(const ValueKey('copyDraftLink')));
    await tester.pumpAndSettle();

    expect(copied, [saved.draftUrl]);
  });

  testWidgets('a link that could not be opened says so', (tester) async {
    final opener = _FakeUrlOpener(const UrlOpenFailed());

    await section(
      tester,
      release: release(fields: {'draftUrl': saved.draftUrl}),
      result: saved,
      applied: [],
      opener: opener,
    );

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not open the link in the browser.'),
      findsOneWidget,
    );
  });

  // Whether there is something to send is state the Message section changes, so
  // the section sees it only through the rebuild the editor registered.
  testWidgets('the section is rebuilt when the message changes', (
    tester,
  ) async {
    final rebuilds = <void Function()>[];

    await section(
      tester,
      release: release(),
      result: saved,
      applied: [],
      subscribeMessageChanged: rebuilds.add,
    );

    expect(find.text('Generate a message first'), findsOneWidget);

    write(MessageStore.messageFile, 'the message');
    rebuilds.first();
    await tester.pump();

    expect(find.text('Generate a message first'), findsNothing);
    expect(find.byKey(const ValueKey('draftForumInput')), findsOneWidget);
    expect(find.byKey(const ValueKey('draftUploadButton')), findsOneWidget);
  });
}
