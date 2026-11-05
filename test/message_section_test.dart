import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:release_prepper/feature/message/message_controller.dart';
import 'package:release_prepper/feature/message/message_section.dart';
import 'package:release_prepper/feature/message/message_store.dart';
import 'package:release_prepper/feature/message/screenshot_layout.dart';
import 'package:release_prepper/feature/release/field_validation.dart';
import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/release/release_store.dart';
import 'package:release_prepper/feature/release/release_type.dart';
import 'package:release_prepper/feature/release/tracker.dart';
import 'package:release_prepper/feature/screenshots/images.dart';
import 'package:release_prepper/feature/screenshots/images_store.dart';
import 'package:release_prepper/feature/section_title.dart';
import 'package:release_prepper/l10n/app_localizations.dart';
import 'package:release_prepper/service/template/template_renderer.dart';
import 'package:release_prepper/service/template/template_store.dart';

import 'test_fields.dart';

// The editor registers this section's rebuild. A test that does not look at the
// gate does not need it, so it ignores it. A default parameter must be a
// constant, so this is a named function rather than a lambda.
void ignoreImagesChanged(void Function() rebuild) {}

// The editor registers this section's reset for a field it writes. A test that is
// not about the reset does not need it, so it ignores it.
void ignoreFieldsChanged(void Function() rebuild) {}

// The editor marks the rows the fields are in; a test that does not look at
// that does not need the callback.
void ignoreFieldsRefused(List<FieldProblem> problems) {}

// The editor writes the block shape through its single write path; a test that is
// not about the write does not need the callback.
void ignoreScreenshotLayoutChanged(ScreenshotLayout layout) {}

// The editor tells the Upload draft section what this section wrote. A test that is
// not about that does not need the callback.
void ignoreMessageChanged() {}

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('message_section_test');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  String storePath(String fileName) =>
      MessageStore().filePath(directory.path, fileName);

  Release release({
    FieldValues? fields,
    ReleaseType releaseType = ReleaseType.singleVideo,
    ScreenshotLayout screenshotLayout = ScreenshotLayout.byHoster,
  }) => Release(
    name: directory.path,
    directoryPath: directory.path,
    tracker: Tracker.pornolab,
    releaseType: releaseType,
    source: '/home/user/videos',
    fields: fields ?? completeFields(),
    screenshotLayout: screenshotLayout,
    items: [
      ReleaseItem(
        path: 'movie.mp4',
        type: itemTypeVideo,
        fields: FieldValues(),
      ),
    ],
  );

  // A manifest with one image uploaded to the poster hoster, which is what the
  // generation gate needs, so the tests that do not look at the gate get it by
  // default. A test that wants the other state passes its own.
  ImagesManifest uploadedToPosterHoster() => ImagesManifest(
    images: [
      ImageRecord(
        item: null,
        kind: ImageKind.poster,
        file: '_rp_poster.jpg',
        urls: {
          posterHoster: {'direct_url': 'https://example.test/poster.jpg'},
        },
      ),
    ],
  );

  Future<_FakeImagesStore> pump(
    WidgetTester tester, {
    required String template,
    String title = '',
    ReleaseType releaseType = ReleaseType.singleVideo,
    // What the images store answers with. The default is the state the generation
    // gate needs, so the tests that do not look at the gate are not about it.
    ImagesManifest? images,
    // The values the release holds. The default is the set a generation needs,
    // so a test that is not about validation is not also about it.
    FieldValues? fields,
    // The shape the block has. Only the pack can choose one, so a test that is
    // not about the row is not also about it.
    ScreenshotLayout screenshotLayout = ScreenshotLayout.byHoster,
    // The editor registers this section's rebuild; a test that does not look at
    // the gate does not need it, so the default is the no-op above.
    void Function(void Function()) subscribeImagesChanged = ignoreImagesChanged,
    // The editor registers this section's reset for a field it writes; a test
    // that is not about the reset does not need it.
    void Function(void Function()) subscribeFieldsChanged = ignoreFieldsChanged,
    // The editor marks the rows the fields are in; a test that does not look at
    // that does not need the callback.
    void Function(List<FieldProblem>) onFieldsRefused = ignoreFieldsRefused,
    // The editor writes the choice through its single write path; a test that is
    // not about the write does not need the callback.
    void Function(ScreenshotLayout) onScreenshotLayoutChanged =
        ignoreScreenshotLayoutChanged,
    // The editor passes this to the Upload draft section; a test that is not about
    // what the section shows does not need the callback.
    void Function() onMessageChanged = ignoreMessageChanged,
  }) async {
    tester.view.physicalSize = const Size(2000, 2000);
    tester.view.devicePixelRatio = 1.0;

    final store = _FakeImagesStore(images ?? uploadedToPosterHoster());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<TemplateStore>(
            create: (_) => TemplateStore(bundle: _FakeBundle(template, title)),
          ),
          Provider<TemplateRenderer>(create: (_) => const TemplateRenderer()),
          Provider<ImagesStore>(create: (_) => store),
          Provider<ReleaseStore>(create: (_) => ReleaseStore()),
          Provider<MessageStore>(create: (_) => MessageStore()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessageSection(
                release: release(
                  fields: fields,
                  releaseType: releaseType,
                  screenshotLayout: screenshotLayout,
                ),
                subscribeImagesChanged: subscribeImagesChanged,
                subscribeFieldsChanged: subscribeFieldsChanged,
                onFieldsRefused: onFieldsRefused,
                onScreenshotLayoutChanged: onScreenshotLayoutChanged,
                onMessageChanged: onMessageChanged,
              ),
            ),
          ),
        ),
      ),
    );

    // The store is what a test that looks at the gate has to change, so it is
    // what `pump` gives back.
    return store;
  }

  /// The clipboard is a platform channel, so a test records what the app writes
  /// to it.
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

  testWidgets('the section shows its title and the Generate button', (
    tester,
  ) async {
    await pump(tester, template: '{{videoTitle}}');

    expect(find.text('Message'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Generate'), findsOneWidget);
  });

  testWidgets('the box shows what message.txt contains', (tester) async {
    // Real file IO has to go through runAsync: the test body runs in a
    // fake-async zone.
    await tester.runAsync(() async {
      await MessageStore().save(
        directory.path,
        MessageStore.messageFile,
        'read from the file',
      );
    });

    await pump(tester, template: '{{videoTitle}}');

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('messageText')))
          .controller!
          .text,
      'read from the file',
    );
  });

  testWidgets('the title line shows what title.txt contains', (tester) async {
    await tester.runAsync(() async {
      await MessageStore().save(
        directory.path,
        MessageStore.titleFile,
        'a saved title',
      );
    });

    await pump(tester, template: '{{videoTitle}}');

    expect(find.text('a saved title'), findsOneWidget);
  });

  testWidgets('clicking Generate replaces the box and writes the file', (
    tester,
  ) async {
    await pump(tester, template: 'a\n{{blank}}\nb');

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Generate'));

      // The write is real file IO, so the chain needs a real turn of the event
      // loop rather than a zero-length delay.
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    const expected = 'a\n\nb';

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('messageText')))
          .controller!
          .text,
      expected,
    );
    expect(
      File(storePath(MessageStore.messageFile)).readAsStringSync(),
      expected,
    );
  });

  testWidgets('clicking Generate writes the title too', (tester) async {
    await pump(
      tester,
      template: '{{videoTitle}}',
      title: 'the generated title',
    );

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(find.text('the generated title'), findsOneWidget);
    expect(
      File(storePath(MessageStore.titleFile)).readAsStringSync(),
      'the generated title',
    );
  });

  // A type with no title has no title file, so the section draws no title line
  // for it and writes only the message (`hasTitle`, `ai/image_folder_upload.md`
  // §6).
  testWidgets(
    'a type with no title shows no title line and writes no title file',
    (tester) async {
      await pump(
        tester,
        template: 'the post text',
        title: 'a title this type does not have',
        releaseType: ReleaseType.imageFolderUpload,
      );

      expect(find.byKey(const ValueKey('copyTitle')), findsNothing);
      expect(find.text('a title this type does not have'), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(
        File(storePath(MessageStore.messageFile)).readAsStringSync(),
        'the post text',
      );
      expect(File(storePath(MessageStore.titleFile)).existsSync(), isFalse);
    },
  );

  testWidgets('an edit in the box writes the file immediately', (tester) async {
    // The box is only drawn when there is something in it, so the test puts
    // something there first.
    await tester.runAsync(() async {
      await MessageStore().save(
        directory.path,
        MessageStore.messageFile,
        'a generated message',
      );
    });

    await pump(tester, template: '{{videoTitle}}');

    await tester.runAsync(() async {
      await tester.enterText(
        find.byKey(const ValueKey('messageText')),
        'typed by hand',
      );
      await Future.delayed(Duration.zero);
    });
    await tester.pump();

    expect(
      File(storePath(MessageStore.messageFile)).readAsStringSync(),
      'typed by hand',
    );
  });

  testWidgets('the copy button puts the title on the clipboard', (
    tester,
  ) async {
    final copied = recordClipboard(tester);

    // The line shows what the file holds, so the test writes the file before it
    // builds.
    await tester.runAsync(() async {
      await MessageStore().save(
        directory.path,
        MessageStore.titleFile,
        'the title',
      );
    });

    await pump(tester, template: '{{videoTitle}}');

    // The platform channel is real async work, so the tap needs a real turn of
    // the event loop.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('copyTitle')));
      await Future.delayed(Duration.zero);
    });
    await tester.pump();

    expect(copied, ['the title']);
  });

  testWidgets('the copy button puts the message on the clipboard', (
    tester,
  ) async {
    final copied = recordClipboard(tester);

    // The button is part of the box, and the box is only drawn when there is
    // something in it.
    await tester.runAsync(() async {
      await MessageStore().save(
        directory.path,
        MessageStore.messageFile,
        'the message',
      );
    });

    await pump(tester, template: '{{videoTitle}}');

    // The platform channel is real async work, so the tap needs a real turn of
    // the event loop.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('copyMessage')));
      await Future.delayed(Duration.zero);
    });
    await tester.pump();

    expect(copied, ['the message']);
  });

  // While nothing has been generated there is nothing to show, so the section
  // is its title row with the Generate button and the placeholder: no title
  // line, no box, and no copy button, because a row that holds nothing is not
  // part of the section. The button is there because the images the message reads
  // are already uploaded, which is the state `pump` gives by default; the
  // placeholder is the one that says what has been generated, not the one that
  // says what has to happen first.
  testWidgets(
    'with nothing generated the section shows the placeholder and no copy buttons',
    (tester) async {
      await pump(tester, template: '{{videoTitle}}');

      expect(find.text('Nothing generated yet.'), findsOneWidget);

      expect(find.byKey(const ValueKey('messageText')), findsNothing);
      expect(find.byKey(const ValueKey('copyTitle')), findsNothing);
      expect(find.byKey(const ValueKey('copyMessage')), findsNothing);

      expect(find.widgetWithText(FilledButton, 'Generate'), findsOneWidget);

      // The button is in the title row, at the right of the section's title,
      // because it is the action of the whole section. It is the part that
      // stays when there is nothing else to show, so in this case the title row
      // is the whole section.
      expect(
        find.ancestor(
          of: find.widgetWithText(FilledButton, 'Generate'),
          matching: find.byType(SectionTitle),
        ),
        findsOneWidget,
      );
    },
  );

  // The message is made of the URLs an upload run writes, so while nothing has
  // been uploaded to the poster hoster there is nothing it could say: the title
  // row has no action, and the placeholder says what has to happen first.
  testWidgets(
    'with nothing uploaded to the poster hoster there is no Generate button',
    (tester) async {
      await pump(
        tester,
        template: '{{videoTitle}}',
        images: const ImagesManifest.empty(),
      );

      expect(find.widgetWithText(FilledButton, 'Generate'), findsNothing);
      expect(find.text('Upload the images first'), findsOneWidget);
      expect(find.text('Nothing generated yet.'), findsNothing);
    },
  );

  // The gate is per record, not per kind: a record with no entry for the poster
  // hoster is an upload that did not happen, so a manifest that has images but
  // none of them uploaded does not open it either.
  testWidgets(
    'a record with no entry for the poster hoster does not open the gate',
    (tester) async {
      await pump(
        tester,
        template: '{{videoTitle}}',
        images: ImagesManifest(
          images: [
            ImageRecord(
              item: null,
              kind: ImageKind.poster,
              file: '_rp_poster.jpg',
              urls: {},
            ),
          ],
        ),
      );

      expect(find.widgetWithText(FilledButton, 'Generate'), findsNothing);
      expect(find.text('Upload the images first'), findsOneWidget);
    },
  );

  // The run that writes `images.json` is another section, so this one is only
  // updated through the rebuild it registered with the editor.
  testWidgets('the button appears when the editor says an upload run ended', (
    tester,
  ) async {
    void Function()? rebuild;

    final store = await pump(
      tester,
      template: '{{videoTitle}}',
      images: const ImagesManifest.empty(),
      subscribeImagesChanged: (callback) => rebuild = callback,
    );

    expect(find.widgetWithText(FilledButton, 'Generate'), findsNothing);

    // The run wrote the URL for the poster hoster, and the editor tells this
    // section.
    store.manifest = uploadedToPosterHoster();

    rebuild!();
    await tester.pump();

    expect(find.widgetWithText(FilledButton, 'Generate'), findsOneWidget);
    expect(find.text('Nothing generated yet.'), findsOneWidget);
  });

  // What the box shows is a render of the values the template reads, so a field
  // the editor writes makes it stale: the section goes back to its placeholder,
  // and the files go with the box, because the files always match what the
  // section shows. The field is any field, including one the app fills.
  testWidgets(
    'a field written through the editor clears the box and the files',
    (tester) async {
      final fields = completeFields();

      await tester.runAsync(() async {
        await MessageStore().save(
          directory.path,
          MessageStore.messageFile,
          'a generated message',
        );
        await MessageStore().save(
          directory.path,
          MessageStore.titleFile,
          'a generated title',
        );
      });

      void Function()? rebuild;

      await pump(
        tester,
        template: '{{videoTitle}}',
        fields: fields,
        subscribeFieldsChanged: (callback) => rebuild = callback,
      );

      await tester.runAsync(() async {
        fields.setValue('cast', 'changed');
        rebuild!();
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(find.text('a generated title'), findsNothing);
      expect(find.text('Nothing generated yet.'), findsOneWidget);

      expect(File(storePath(MessageStore.messageFile)).existsSync(), isFalse);
      expect(File(storePath(MessageStore.titleFile)).existsSync(), isFalse);
    },
  );

  // The image half of the same rule: a run that added a URL the message reads
  // changes what a render would produce, so the content is cleared with the gate.
  testWidgets('an upload that adds a url clears the box and the files', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await MessageStore().save(
        directory.path,
        MessageStore.messageFile,
        'a generated message',
      );
    });

    void Function()? rebuild;

    final store = await pump(
      tester,
      template: '{{videoTitle}}',
      images: const ImagesManifest.empty(),
      subscribeImagesChanged: (callback) => rebuild = callback,
    );

    store.manifest = uploadedToPosterHoster();

    await tester.runAsync(() async {
      rebuild!();
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(find.text('Nothing generated yet.'), findsOneWidget);
    expect(File(storePath(MessageStore.messageFile)).existsSync(), isFalse);
  });

  // A run that wrote nothing is not a change to what the render reads, and a
  // generation run that wrote files without URLs is not either, so the notice
  // alone does not clear the box.
  testWidgets(
    'a run that changed nothing the render reads does not clear the box',
    (tester) async {
      await tester.runAsync(() async {
        await MessageStore().save(
          directory.path,
          MessageStore.messageFile,
          'a generated message',
        );
      });

      void Function()? rebuild;

      await pump(
        tester,
        template: '{{videoTitle}}',
        subscribeImagesChanged: (callback) => rebuild = callback,
      );

      await tester.runAsync(() async {
        rebuild!();
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('messageText')))
            .controller!
            .text,
        'a generated message',
      );
      expect(File(storePath(MessageStore.messageFile)).existsSync(), isTrue);
    },
  );

  // The row of shapes is what the block is built with, so it is drawn only for
  // the type that can group per item (`ai/video_pack.md` §7).
  testWidgets('the row of shapes is drawn only for the type that can choose', (
    tester,
  ) async {
    await pump(tester, template: '{{videoTitle}}');

    expect(find.byKey(const ValueKey('screenshotLayout')), findsNothing);

    await pump(
      tester,
      template: '{{videoTitle}}',
      releaseType: ReleaseType.videoPack,
    );

    expect(find.byKey(const ValueKey('screenshotLayout')), findsOneWidget);
  });

  testWidgets('the row selects the shape the release has', (tester) async {
    await pump(
      tester,
      template: '{{videoTitle}}',
      releaseType: ReleaseType.videoPack,
      screenshotLayout: ScreenshotLayout.byItem,
    );

    expect(
      tester
          .widget<RadioGroup<ScreenshotLayout>>(
            find.byKey(const ValueKey('screenshotLayout')),
          )
          .groupValue,
      ScreenshotLayout.byItem,
    );
  });

  // The choice is part of `release.json`, so the write is the editor's: the
  // section reports it through the callback the editor gave it.
  testWidgets('choosing a shape reports it to the write path', (tester) async {
    final chosen = <ScreenshotLayout>[];

    await pump(
      tester,
      template: '{{videoTitle}}',
      releaseType: ReleaseType.videoPack,
      onScreenshotLayoutChanged: (layout) => chosen.add(layout),
    );

    await tester.tap(find.byKey(const ValueKey('screenshotLayout-byItem')));
    await tester.pump();

    expect(chosen, [ScreenshotLayout.byItem]);
  });

  // Choosing a shape changes what a render would produce, so the same reset as a
  // field runs: the write is the editor's, and the notice it sends clears the box
  // and the files with it.
  testWidgets('choosing a shape clears the box and the files', (tester) async {
    await tester.runAsync(() async {
      await MessageStore().save(
        directory.path,
        MessageStore.messageFile,
        'a generated message',
      );
    });

    void Function()? rebuild;

    await pump(
      tester,
      template: '{{videoTitle}}',
      releaseType: ReleaseType.videoPack,
      subscribeFieldsChanged: (callback) => rebuild = callback,
      onScreenshotLayoutChanged: (layout) => rebuild!(),
    );

    await tester.tap(find.byKey(const ValueKey('screenshotLayout-byItem')));

    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(find.text('Nothing generated yet.'), findsOneWidget);
    expect(File(storePath(MessageStore.messageFile)).existsSync(), isFalse);
  });

  // The parts appear with what they hold. A type that has a title draws the
  // title line only once there is one, so a message with no title is its title
  // row and the placeholder, and the title line appears when a generation
  // writes a title.
  testWidgets('the title line appears only when there is a title', (
    tester,
  ) async {
    await pump(tester, template: 'the post text', title: 'a title');

    expect(find.byKey(const ValueKey('copyTitle')), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(find.text('a title'), findsOneWidget);
    expect(find.byKey(const ValueKey('copyTitle')), findsOneWidget);
    expect(find.byKey(const ValueKey('copyMessage')), findsOneWidget);
  });

  // The copy button for the message is at the top of the box, level with the
  // first line, not in its middle. `InputDecorator` centres a suffix icon in
  // the input area whatever the decoration takes, so the field uses the suffix
  // slot with the text aligned to the top instead.
  testWidgets('the copy button for the message is at the top of the field', (
    tester,
  ) async {
    // The box is only drawn when there is something in it, so the test puts
    // something there first.
    await tester.runAsync(() async {
      await MessageStore().save(
        directory.path,
        MessageStore.messageFile,
        'the post text',
      );
    });

    await pump(tester, template: '{{videoTitle}}');

    final field = tester.getRect(find.byKey(const ValueKey('messageText')));
    final button = tester.getRect(find.byKey(const ValueKey('copyMessage')));

    expect(button.top - field.top, lessThan(20));
    expect(button.top, lessThan(field.top + field.height / 2));
  });

  // A generation is refused before the template is read, so a release with a
  // required field empty is told which field it is, and the box and the files
  // stay as they were. The problems are one line each, in the order the field
  // list lists them, which is the order the form shows them in, with the
  // words the name has — the controller answers with names, not text.
  testWidgets('clicking Generate with fields missing says what is wrong', (
    tester,
  ) async {
    final fields = completeFields();
    fields.setValue('cast', '');
    fields.setValue('productionDate', '2024-5-1');

    await pump(tester, template: '{{videoTitle}}', fields: fields);

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(
      find.text(
        'Cannot generate the message:\n'
        'Cast is required.\n'
        'Production date must be YYYY-MM-DD, YYYY-MM or YYYY.',
      ),
      findsOneWidget,
    );

    // Nothing was generated, so nothing was written.
    expect(File(storePath(MessageStore.messageFile)).existsSync(), isFalse);
  });

  // The section shows the message, and the editor marks the rows, because the
  // rows are not this widget's. So the same problems go to both: the words
  // are the same ones, from `fieldProblemText`.
  testWidgets('the problems are given to the editor, which marks the rows', (
    tester,
  ) async {
    final fields = completeFields();
    fields.setValue('cast', '');

    final refused = <FieldProblem>[];

    await pump(
      tester,
      template: '{{videoTitle}}',
      fields: fields,
      onFieldsRefused: (problems) => refused.addAll(problems),
    );

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(refused.map((problem) => problem.field), ['cast']);
  });
}

class _FakeBundle extends AssetBundle {
  _FakeBundle(this.template, this.title);

  final String template;
  final String title;

  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('.style')) {
      return ByteData.sublistView(utf8.encode('text = {content}'));
    }

    if (key.endsWith('title.txt')) {
      return ByteData.sublistView(utf8.encode(title));
    }

    return ByteData.sublistView(utf8.encode(template));
  }
}

class _FakeImagesStore implements ImagesStore {
  _FakeImagesStore(this.manifest);

  /// Set when a test wants the section to read a different state.
  ImagesManifest manifest;

  @override
  String filePath(String directoryPath) => directoryPath;

  @override
  Future<ImagesManifest> load(String directoryPath) async => manifest;

  @override
  ImagesManifest loadSync(String directoryPath) => manifest;

  @override
  Future<void> save(String directoryPath, ImagesManifest manifest) async {}
}
