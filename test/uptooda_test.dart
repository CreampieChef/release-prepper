import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/service/logging/tool_log.dart';
import 'package:release_prepper/service/native_tools/tool_locator.dart';
import 'package:release_prepper/service/native_tools/tool_runner.dart';
import 'package:release_prepper/service/native_tools/uptooda.dart';

void main() {
  // A real `rpstub` output, kept as the fixture: the field names and the shape
  // are what the parser reads. `rpstub` is the stub hoster in
  // Data/Scripts/_rp_stub.nut; a file with "fail" in its name makes it report
  // success false. The JSON is pretty-printed over several lines, so the parser
  // reads the whole output, not one line.
  const successJson = '''
[
   {
      "delete_url" : "",
      "direct_url" : "https://example.com/images/test_image.jpg",
      "filename" : "test_image.jpg",
      "success" : true,
      "thumb_url" : "https://example.com/thumb/test_image.jpg",
      "view_url" : "https://example.com/images/test_image.jpg.html"
   }
]''';

  const failedJson = '''
[
   {
      "delete_url" : "",
      "direct_url" : "",
      "filename" : "fail.jpg",
      "success" : false,
      "thumb_url" : "",
      "view_url" : ""
   }
]''';

  test('the four URLs are read from the fields the tool reports', () async {
    final result =
        await Uptooda(
          runner: _FakeRunner(
            const ToolRunSuccess(stdout: successJson, stderr: ''),
          ),
        ).upload(
          releaseDirectory: '/tmp/x',
          hoster: 'rpstub',
          filePath: 'test_image.jpg',
          environment: const {},
        );

    expect(result, isA<UptoodaUploadSuccess>());

    final urls = (result as UptoodaUploadSuccess).urls;

    expect(urls['delete_url'], '');
    expect(urls['direct_url'], 'https://example.com/images/test_image.jpg');
    expect(urls['thumb_url'], 'https://example.com/thumb/test_image.jpg');
    expect(urls['view_url'], 'https://example.com/images/test_image.jpg.html');
  });

  // Success is decided by the field, not by the exit code: the tool exits 1 for
  // a failed upload, and the parser reads the same output either way.
  test('success false is an upload failure', () async {
    for (final result in [
      const ToolRunSuccess(stdout: failedJson, stderr: ''),
      const ToolRunFailure(exitCode: 1, stdout: failedJson, stderr: ''),
    ]) {
      expect(
        await Uptooda(runner: _FakeRunner(result)).upload(
          releaseDirectory: '/tmp/x',
          hoster: 'rpstub',
          filePath: 'fail.jpg',
          environment: const {},
        ),
        isA<UptoodaUploadFailure>().having(
          (failure) => failure.kind,
          'kind',
          UptoodaUploadFailureKind.uploadFailed,
        ),
        reason: 'the same output through a zero and a non-zero exit',
      );
    }
  });

  // An unknown hoster writes nothing on stdout and exits 0, so there is no
  // result to read. That is the case the exit code cannot tell apart from a
  // success.
  test('no JSON on stdout is no result', () async {
    final result =
        await Uptooda(
          runner: _FakeRunner(
            const ToolRunSuccess(
              stdout: '',
              stderr: "No such server 'invalid'!",
            ),
          ),
        ).upload(
          releaseDirectory: '/tmp/x',
          hoster: 'invalid',
          filePath: 'test_image.jpg',
          environment: const {},
        );

    expect(
      result,
      isA<UptoodaUploadFailure>().having(
        (failure) => failure.kind,
        'kind',
        UptoodaUploadFailureKind.noResult,
      ),
    );
  });

  test('output that is not JSON is no result', () async {
    final result =
        await Uptooda(
          runner: _FakeRunner(
            const ToolRunSuccess(stdout: 'not json', stderr: ''),
          ),
        ).upload(
          releaseDirectory: '/tmp/x',
          hoster: 'rpstub',
          filePath: 'test_image.jpg',
          environment: const {},
        );

    expect(
      result,
      isA<UptoodaUploadFailure>().having(
        (failure) => failure.kind,
        'kind',
        UptoodaUploadFailureKind.noResult,
      ),
    );
  });

  test(
    'a tool that is not in the bundle is reported as not available',
    () async {
      final result =
          await Uptooda(runner: _FakeRunner(const ToolRunNotAvailable()))
              .upload(
                releaseDirectory: '/tmp/x',
                hoster: 'rpstub',
                filePath: 'test_image.jpg',
                environment: const {},
              );

      expect(
        result,
        isA<UptoodaUploadFailure>().having(
          (failure) => failure.kind,
          'kind',
          UptoodaUploadFailureKind.toolNotAvailable,
        ),
      );
    },
  );

  test('a call stopped by the timeout is reported as a timeout', () async {
    final result =
        await Uptooda(
          runner: _FakeRunner(const ToolRunTimeout(stdout: '', stderr: '')),
        ).upload(
          releaseDirectory: '/tmp/x',
          hoster: 'rpstub',
          filePath: 'test_image.jpg',
          environment: const {},
        );

    expect(
      result,
      isA<UptoodaUploadFailure>().having(
        (failure) => failure.kind,
        'kind',
        UptoodaUploadFailureKind.timeout,
      ),
    );
  });

  // The arguments the app always passes (`ai/bundled_native_tools.md`).
  // `--code_type` is not passed: it only changes the bbcode form, and the app
  // builds bbcode from the stored URLs.
  test('the call is one image to one hoster, with JSON output', () async {
    final runner = _FakeRunner(
      const ToolRunSuccess(stdout: successJson, stderr: ''),
    );

    await Uptooda(runner: runner).upload(
      releaseDirectory: '/tmp/x',
      hoster: 'fastpic.org',
      filePath: '/tmp/x/test_image.jpg',
      environment: const {},
    );

    expect(runner.calls, [
      [
        '--server',
        'fastpic.org',
        '--code_lang',
        'json',
        '--thumb_width',
        '300',
        '/tmp/x/test_image.jpg',
      ],
    ]);
  });

  // The credential reaches the tool through the environment, not through the
  // arguments (`ai/bundled_native_tools.md`): the arguments are recorded on
  // every log entry, so a key passed as one would be written to the log once
  // per output line. What the runner is given is what the child gets,
  // unchanged.
  test('the environment is passed to the runner as it was given', () async {
    final runner = _FakeRunner(
      const ToolRunSuccess(stdout: successJson, stderr: ''),
    );

    await Uptooda(runner: runner).upload(
      releaseDirectory: '/tmp/x',
      hoster: 'postimages.org',
      filePath: '/tmp/x/test_image.jpg',
      environment: {Uptooda.apiKeyVariable: 'the-key'},
    );

    expect(runner.environments, [
      {Uptooda.apiKeyVariable: 'the-key'},
    ]);
    expect(runner.calls.first, isNot(contains('the-key')));
  });
}

class _FakeRunner implements ToolRunner {
  _FakeRunner(this.result);

  final ToolRunResult result;

  final calls = <List<String>>[];

  /// What each call was given as its environment, in the order the calls were
  /// made.
  final environments = <Map<String, String>>[];

  /// What each call was given as its window, in the order the calls were made.
  final timeouts = <Duration>[];

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
    environments.add(environment);
    timeouts.add(timeout);

    return result;
  }
}
