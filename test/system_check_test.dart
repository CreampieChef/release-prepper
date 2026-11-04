import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:release_prepper/feature/system_check/system_check_controller.dart';
import 'package:release_prepper/feature/system_check/system_check_page.dart';
import 'package:release_prepper/feature/tab/tab_manager.dart';
import 'package:release_prepper/l10n/app_localizations.dart';
import 'package:release_prepper/service/logging/tool_log.dart';
import 'package:release_prepper/service/native_tools/ffprobe.dart';
import 'package:release_prepper/service/native_tools/ffmpeg.dart';
import 'package:release_prepper/service/native_tools/mkbrr.dart';
import 'package:release_prepper/service/native_tools/mtn.dart';
import 'package:release_prepper/service/native_tools/tool_locator.dart';
import 'package:release_prepper/service/native_tools/tool_runner.dart';
import 'package:release_prepper/service/native_tools/uptooda.dart';

import 'test_runner.dart';

// A wrapper that answers with the result the test gives instead of running the
// tool. Only `version()` is overridden, because that is the only call the check
// makes, so the names and the arguments stay the ones the app uses.
class FakeFfmpeg extends Ffmpeg {
  FakeFfmpeg(this.result) : super(runner: testRunner());

  final ToolRunResult result;

  @override
  Future<ToolRunResult> version({required String releaseDirectory}) async =>
      result;
}

class FakeFfprobe extends Ffprobe {
  FakeFfprobe(this.result) : super(runner: testRunner());

  final ToolRunResult result;

  @override
  Future<ToolRunResult> version({required String releaseDirectory}) async =>
      result;
}

class FakeMtn extends Mtn {
  FakeMtn(this.result) : super(runner: testRunner());

  final ToolRunResult result;

  @override
  Future<ToolRunResult> version({required String releaseDirectory}) async =>
      result;
}

class FakeUptooda extends Uptooda {
  FakeUptooda(this.result) : super(runner: testRunner());

  final ToolRunResult result;

  @override
  Future<ToolRunResult> version({required String releaseDirectory}) async =>
      result;
}

class FakeMkbrr extends Mkbrr {
  FakeMkbrr(this.result) : super(runner: testRunner());

  final ToolRunResult result;

  @override
  Future<ToolRunResult> version({required String releaseDirectory}) async =>
      result;
}

// A wrapper that does not answer until the test lets it, which is what a tool
// that hangs looks like from the page's side: its row keeps the spinner while
// the rows that answered show what they reported.
class HangingFfprobe extends Ffprobe {
  HangingFfprobe(this.completer) : super(runner: testRunner());

  final Completer<ToolRunResult> completer;

  @override
  Future<ToolRunResult> version({required String releaseDirectory}) async =>
      completer.future;
}

void main() {
  late Directory appDirectory;

  setUp(() {
    appDirectory = Directory.systemTemp.createTempSync('system_check_test');
  });

  tearDown(() {
    if (appDirectory.existsSync()) {
      appDirectory.deleteSync(recursive: true);
    }
  });

  SystemCheckController controller({
    required ToolRunResult ffmpeg,
    required ToolRunResult ffprobe,
    required ToolRunResult mtn,
    required ToolRunResult uptooda,
    required ToolRunResult mkbrr,
  }) => SystemCheckController(
    ffmpeg: FakeFfmpeg(ffmpeg),
    ffprobe: FakeFfprobe(ffprobe),
    mtn: FakeMtn(mtn),
    uptooda: FakeUptooda(uptooda),
    mkbrr: FakeMkbrr(mkbrr),
    appDirectory: () async => appDirectory,
  );

  // The check as the page uses it: the results as they are reported, keyed by
  // the tool name the rows show. Keyed rather than in order, because the
  // results arrive in the order the calls finish in, not the order the rows are
  // drawn.
  Future<Map<String, SystemCheckResult>> check({
    required ToolRunResult ffmpeg,
    required ToolRunResult ffprobe,
    required ToolRunResult mtn,
    required ToolRunResult uptooda,
    required ToolRunResult mkbrr,
  }) async {
    final results = <String, SystemCheckResult>{};

    await controller(
      ffmpeg: ffmpeg,
      ffprobe: ffprobe,
      mtn: mtn,
      uptooda: uptooda,
      mkbrr: mkbrr,
    ).check(onResult: (result) => results[result.tool.name] = result);

    return results;
  }

  test('a tool that cannot be started is reported as not present', () async {
    final results = await check(
      ffmpeg: const ToolRunSuccess(stdout: 'ffmpeg version 6.1', stderr: ''),
      ffprobe: const ToolRunNotAvailable(),
      mtn: const ToolRunSuccess(
        stdout: 'Movie Thumbnailer (mtn) 3.5.0',
        stderr: '',
      ),
      uptooda: const ToolRunSuccess(stdout: '1.4.6', stderr: ''),
      mkbrr: const ToolRunSuccess(stdout: 'mkbrr version: 1.27.0', stderr: ''),
    );

    expect(results, hasLength(5));

    expect(results['ffmpeg'], isA<SystemCheckFound>());
    expect(
      (results['ffmpeg'] as SystemCheckFound).version,
      'ffmpeg version 6.1',
    );
    expect(results['ffprobe'], isA<SystemCheckNotPresent>());
    expect(
      (results['mtn'] as SystemCheckFound).version,
      'Movie Thumbnailer (mtn) 3.5.0',
    );
    expect((results['uptooda-cli'] as SystemCheckFound).version, '1.4.6');
    expect(
      (results['mkbrr'] as SystemCheckFound).version,
      'mkbrr version: 1.27.0',
    );
  });

  // The page draws one row per entry of `calls()`, so that list is the order
  // the check runs the tools in and the order the rows appear in.
  test('the tools are listed in the order the page shows them', () {
    expect(
      controller(
        ffmpeg: const ToolRunSuccess(stdout: '', stderr: ''),
        ffprobe: const ToolRunSuccess(stdout: '', stderr: ''),
        mtn: const ToolRunSuccess(stdout: '', stderr: ''),
        uptooda: const ToolRunSuccess(stdout: '', stderr: ''),
        mkbrr: const ToolRunSuccess(stdout: '', stderr: ''),
      ).calls().map((entry) => entry.$1.name),
      ['ffmpeg', 'ffprobe', 'mtn', 'uptooda-cli', 'mkbrr'],
    );
  });

  test(
    'the first line with text is the version, as the tool wrote it',
    () async {
      final results = await check(
        ffmpeg: const ToolRunSuccess(
          stdout: '\nffmpeg version 6.1\nlibavcodec 60.31.102\n',
          stderr: '',
        ),
        ffprobe: const ToolRunSuccess(stdout: '', stderr: ''),
        mtn: const ToolRunSuccess(stdout: 'mtn 3.5.0', stderr: ''),
        uptooda: const ToolRunSuccess(stdout: '1.4.6', stderr: ''),
        mkbrr: const ToolRunSuccess(
          stdout: 'mkbrr version: 1.27.0',
          stderr: '',
        ),
      );

      // A leading blank line is not a version, so the first line with text is,
      // and the rest of the output is not shown.
      expect(
        (results['ffmpeg'] as SystemCheckFound).version,
        'ffmpeg version 6.1',
      );

      // A call that ran and printed nothing is reported rather than guessed at.
      expect(results['ffprobe'], isA<SystemCheckNoOutput>());
    },
  );

  test('a run that exits with a non-zero code keeps the exit code', () async {
    final results = await check(
      ffmpeg: const ToolRunSuccess(stdout: 'ffmpeg version 6.1', stderr: ''),
      ffprobe: const ToolRunFailure(
        exitCode: 127,
        stdout: '',
        stderr: 'Unrecognized option "--version"',
      ),
      mtn: const ToolRunFailure(exitCode: 255, stdout: '', stderr: ''),
      uptooda: const ToolRunSuccess(stdout: '1.4.6', stderr: ''),
      mkbrr: const ToolRunSuccess(stdout: 'mkbrr version: 1.27.0', stderr: ''),
    );

    final failed = results['ffprobe'] as SystemCheckRunFailed;

    expect(failed.exitCode, 127);
    expect(failed.tool.name, 'ffprobe');

    // mtn printed nothing, so it is reported as no output rather than as a
    // failure, because its exit code is not a failure of the check.
    expect(results['mtn'], isA<SystemCheckNoOutput>());
  });

  test(
    'mtn prints its version to stderr and exits 255, and the version is shown',
    () async {
      final results = await check(
        ffmpeg: const ToolRunSuccess(stdout: 'ffmpeg version 6.1', stderr: ''),
        ffprobe: const ToolRunSuccess(
          stdout: 'ffprobe version 6.1',
          stderr: '',
        ),
        mtn: const ToolRunFailure(
          exitCode: 255,
          stdout: '',
          stderr:
              '\nMovie Thumbnailer (mtn) 3.5.0\nUsage:\n  mtn [options] file\n',
        ),
        uptooda: const ToolRunSuccess(stdout: '1.4.6', stderr: ''),
        mkbrr: const ToolRunSuccess(
          stdout: 'mkbrr version: 1.27.0',
          stderr: '',
        ),
      );

      // The exit code is not a failure of the check for this tool, because a
      // run with no input file is an error to mtn whatever it prints, so the
      // line it printed is the version.
      expect(
        (results['mtn'] as SystemCheckFound).version,
        'Movie Thumbnailer (mtn) 3.5.0',
      );
    },
  );

  test('a run stopped by the timeout is reported as a timeout', () async {
    final results = await check(
      ffmpeg: const ToolRunSuccess(stdout: 'ffmpeg version 6.1', stderr: ''),
      ffprobe: const ToolRunSuccess(stdout: 'ffprobe version 6.1', stderr: ''),
      mtn: const ToolRunSuccess(stdout: 'mtn 3.5.0', stderr: ''),
      uptooda: const ToolRunTimeout(stdout: '', stderr: ''),
      mkbrr: const ToolRunSuccess(stdout: 'mkbrr version: 1.27.0', stderr: ''),
    );

    expect(results['uptooda-cli'], isA<SystemCheckRunTimeout>());
    expect(
      (results['uptooda-cli'] as SystemCheckRunTimeout).tool.name,
      'uptooda-cli',
    );
  });

  // The version call is the one that can hang on Windows, where mtn pauses at
  // the end, so `-P` is on it as it is on the screenlist call.
  test(
    'the mtn version call is the version flag with the pause turned off',
    () async {
      final runner = _FakeRunner(const ToolRunSuccess(stdout: '', stderr: ''));

      await Mtn(runner: runner).version(releaseDirectory: '/tmp/x');

      expect(runner.calls.first, ['-v', '-P']);
    },
  );

  // The check is not inside a release, so there is no release directory to log
  // to; the app data directory is what the calls are written under. The
  // precondition is ffmpeg on PATH, as in the other native tool tests.
  test('the calls are logged in the app data directory', () async {
    final runner = testRunner();

    final results = <String, SystemCheckResult>{};

    await SystemCheckController(
      ffmpeg: Ffmpeg(runner: runner),
      ffprobe: FakeFfprobe(const ToolRunNotAvailable()),
      mtn: FakeMtn(const ToolRunSuccess(stdout: 'mtn 3.5.0', stderr: '')),
      uptooda: FakeUptooda(const ToolRunSuccess(stdout: '1.4.6', stderr: '')),
      mkbrr: FakeMkbrr(
        const ToolRunSuccess(stdout: 'mkbrr version: 1.27.0', stderr: ''),
      ),
      appDirectory: () async => appDirectory,
    ).check(onResult: (result) => results[result.tool.name] = result);

    expect(
      results['ffmpeg'],
      isA<SystemCheckFound>(),
      reason: 'the precondition is ffmpeg on PATH',
    );

    final entries = Directory(p.join(appDirectory.path, ToolLog.directoryName))
        .listSync();

    expect(entries, hasLength(1));

    final lines = File(entries.first.path)
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();

    expect(lines.first['tool'], 'ffmpeg');

    // The recorded input is the resolved path and the arguments, so this is the
    // version call the wrapper makes.
    expect((lines.first['input'] as List).last, '-version');
  });

  // The calls are made at the same time, so a tool that hangs is not what the
  // other rows are waiting for: each result reaches the page as its own call
  // comes back.
  test('a tool that hangs does not hold up the tools that answered', () async {
    final hang = Completer<ToolRunResult>();

    final results = <String, SystemCheckResult>{};

    final running = SystemCheckController(
      ffmpeg: FakeFfmpeg(
        const ToolRunSuccess(stdout: 'ffmpeg version 6.1', stderr: ''),
      ),
      ffprobe: HangingFfprobe(hang),
      mtn: FakeMtn(const ToolRunSuccess(stdout: 'mtn 3.5.0', stderr: '')),
      uptooda: FakeUptooda(const ToolRunSuccess(stdout: '1.4.6', stderr: '')),
      mkbrr: FakeMkbrr(
        const ToolRunSuccess(stdout: 'mkbrr version: 1.27.0', stderr: ''),
      ),
      appDirectory: () async => appDirectory,
    ).check(onResult: (result) => results[result.tool.name] = result);

    // The calls that answer are reported while the hanging one is still
    // running, so the page has something to show for them.
    await Future(() {});

    expect(results['ffmpeg'], isA<SystemCheckFound>());
    expect(results['mtn'], isA<SystemCheckFound>());
    expect(results, isNot(contains('ffprobe')));

    hang.complete(
      const ToolRunSuccess(stdout: 'ffprobe version 6.1', stderr: ''),
    );

    await running;

    expect(results['ffprobe'], isA<SystemCheckFound>());
  });

  Widget app(SystemCheckController controller) => MultiProvider(
    providers: [Provider<SystemCheckController>(create: (_) => controller)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SystemCheckPage()),
    ),
  );

  testWidgets('the page shows each tool with what it reported', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    final controller = SystemCheckController(
      ffmpeg: FakeFfmpeg(
        const ToolRunFailure(exitCode: 1, stdout: '', stderr: 'ffmpeg: error'),
      ),
      ffprobe: FakeFfprobe(const ToolRunNotAvailable()),
      // mtn is the tool whose version call exits 255 and prints to stderr, so
      // its row is the version it printed rather than the exit code.
      mtn: FakeMtn(
        const ToolRunFailure(
          exitCode: 255,
          stdout: '',
          stderr:
              '\nMovie Thumbnailer (mtn) 3.5.0\nUsage:\n  mtn [options] file\n',
        ),
      ),
      uptooda: FakeUptooda(const ToolRunTimeout(stdout: '', stderr: '')),
      mkbrr: FakeMkbrr(
        const ToolRunSuccess(stdout: 'mkbrr version: 1.27.0', stderr: ''),
      ),
      appDirectory: () async => appDirectory,
    );

    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();

    for (final name in ['ffmpeg', 'ffprobe', 'mtn', 'uptooda-cli', 'mkbrr']) {
      expect(find.text(name), findsOneWidget);
    }

    // The page titles itself with the page title style, and the header is the
    // two columns the rows have.
    expect(find.text(l10n.systemCheck), findsOneWidget);
    expect(find.text(l10n.systemCheckToolLabel), findsOneWidget);
    expect(find.text(l10n.systemCheckResultLabel), findsOneWidget);

    // The version is shown as the tool wrote it, and the reasons are the
    // localized text the widget maps the results to.
    expect(find.text('Movie Thumbnailer (mtn) 3.5.0'), findsOneWidget);
    expect(find.text(l10n.systemCheckToolNotFound('ffprobe')), findsOneWidget);
    expect(find.text(l10n.systemCheckRunFailed('ffmpeg', 1)), findsOneWidget);
    expect(
      find.text(l10n.systemCheckRunTimeout('uptooda-cli')),
      findsOneWidget,
    );
    expect(find.text('mkbrr version: 1.27.0'), findsOneWidget);

    // The state is the icon the widget maps the result to: a check for each
    // tool that reported a version, and the same mark for each reason.
    expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(2));
    expect(find.byIcon(Icons.error_outline), findsNWidgets(3));
  });

  testWidgets(
    'the block is capped and centred, the title with it, the text not',
    (tester) async {
      // A window wider than the cap, so the cap is what decides the width.
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1.0;

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      final controller = SystemCheckController(
        ffmpeg: FakeFfmpeg(
          const ToolRunSuccess(stdout: 'ffmpeg version 6.1', stderr: ''),
        ),
        ffprobe: FakeFfprobe(
          const ToolRunSuccess(stdout: 'ffprobe version 6.1', stderr: ''),
        ),
        mtn: FakeMtn(const ToolRunSuccess(stdout: 'mtn 3.5.0', stderr: '')),
        uptooda: FakeUptooda(const ToolRunSuccess(stdout: '1.4.6', stderr: '')),
        mkbrr: FakeMkbrr(
          const ToolRunSuccess(stdout: 'mkbrr version: 1.27.0', stderr: ''),
        ),
        appDirectory: () async => appDirectory,
      );

      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();

      // The capped width, not the width the window gives.
      expect(
        tester
            .getSize(
              find.byWidgetPredicate(
                (widget) =>
                    widget is ConstrainedBox &&
                    widget.constraints.maxWidth == 1200,
              ),
            )
            .width,
        1200,
      );

      // The title is the page title style the release name uses, and it follows
      // the centred block. The text inside the table has no alignment of its
      // own, so it stays at the start, as the text of every other page does.
      final finder = find.text(l10n.systemCheck);
      final title = tester.widget<Text>(finder);

      expect(
        title.style?.fontSize,
        Theme.of(tester.element(finder)).textTheme.headlineMedium!.fontSize,
      );
      expect(title.textAlign, TextAlign.center);

      expect(
        tester.widget<Text>(find.text('ffmpeg version 6.1')).textAlign,
        null,
      );
    },
  );

  testWidgets(
    'a row shows the spinner in the icon column until its own result arrives',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;

      final hang = Completer<ToolRunResult>();

      final controller = SystemCheckController(
        ffmpeg: FakeFfmpeg(
          const ToolRunSuccess(stdout: 'ffmpeg version 6.1', stderr: ''),
        ),
        // The one tool that does not answer, so the page is in the state where
        // some rows have an answer and one does not.
        ffprobe: HangingFfprobe(hang),
        mtn: FakeMtn(const ToolRunSuccess(stdout: 'mtn 3.5.0', stderr: '')),
        uptooda: FakeUptooda(const ToolRunSuccess(stdout: '1.4.6', stderr: '')),
        mkbrr: FakeMkbrr(
          const ToolRunSuccess(stdout: 'mkbrr version: 1.27.0', stderr: ''),
        ),
        appDirectory: () async => appDirectory,
      );

      // One frame, not a settled one: no call has come back, so this is the
      // state the page is in as the check starts.
      await tester.pumpWidget(app(controller));

      expect(find.byType(CircularProgressIndicator), findsNWidgets(5));

      // Nothing has come back yet, so the value columns are empty.
      expect(find.text('ffmpeg version 6.1'), findsNothing);

      // A frame later the calls that answered are shown, and the row that has
      // not answered is still the only one waiting.
      await tester.pump();

      expect(find.text('ffmpeg version 6.1'), findsOneWidget);
      expect(find.text('mtn 3.5.0'), findsOneWidget);
      expect(find.text('1.4.6'), findsOneWidget);
      expect(find.text('mkbrr version: 1.27.0'), findsOneWidget);
      expect(find.text('ffprobe version 6.1'), findsNothing);

      // The answered rows have the status icon the result maps to; the waiting
      // row still has the spinner in the same column, so it keeps the shape it
      // has once its result arrives.
      expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(4));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      final spinner = tester
          .getRect(find.byType(CircularProgressIndicator).first)
          .right;
      final name = tester.getRect(find.text('ffprobe')).left;

      expect(spinner, lessThanOrEqualTo(name));

      // The hanging call coming back updates only its own row.
      hang.complete(
        const ToolRunSuccess(stdout: 'ffprobe version 6.1', stderr: ''),
      );

      await tester.pump();

      expect(find.text('ffprobe version 6.1'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(5));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  test('the check tab is opened once, and a second open selects it', () {
    final tabManager = TabManager();

    final first = tabManager.addSystemCheck();
    final second = tabManager.addSystemCheck();

    expect(second, first);
    expect(tabManager.tabs, hasLength(1));
    expect(tabManager.tabs.first.kind, AppTabKind.systemCheck);
    expect(tabManager.selectedIndex, 0);
  });
}

// A runner that records the arguments a call was given instead of running the
// tool, so a test can see what a wrapper passes.
class _FakeRunner implements ToolRunner {
  _FakeRunner(this.result);

  final ToolRunResult result;

  final calls = <List<String>>[];

  @override
  ToolLocator get locator => ToolLocator(
    bundleDirectory: Directory.systemTemp,
    pathVariable: '',
    isWindows: Platform.isWindows,
  );

  @override
  ToolLog get log => ToolLog();

  @override
  Future<ToolRunResult> run(
    NativeTool tool,
    List<String> arguments, {
    required String releaseDirectory,
    Map<String, String> environment = const {},
    void Function(String chunk)? onOutput,
    Duration timeout = ToolRunner.callTimeout,
  }) async {
    calls.add(arguments);

    return result;
  }
}
