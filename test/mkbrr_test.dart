import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/service/logging/tool_log.dart';
import 'package:release_prepper/service/native_tools/mkbrr.dart';
import 'package:release_prepper/service/native_tools/tool_locator.dart';
import 'package:release_prepper/service/native_tools/tool_runner.dart';

void main() {
  // A captured run of the committed binary, kept as the fixture, with the bar
  // runs shortened. The progress is one line redrawn with carriage returns, and
  // the ANSI colour codes are present even though stdout was not a terminal. The
  // text before the first carriage return is the header, and the runs of spaces
  // are what the tool writes to clear the line before redrawing it; neither is
  // progress.
  const fixture =
      '\n'
      'Concurrency: Using 32 worker(s)\n\n'
      'Files being hashed:\n└─ .\n  └─ two.bin (1.9 GiB)\n\n'
      '\r\u001B[36m\u001B[1mHashing pieces...\u001B[0m  40% '
      '[\u001B[32m=\u001B[0m\u001B[32m>\u001B[0m            ]  [0s:0s]\u001B[0m'
      '\r'
      '          \r'
      '\u001B[36m\u001B[1mHashing pieces...\u001B[0m [3.7 GiB/s]  40% '
      '[\u001B[32m=\u001B[0m\u001B[32m>\u001B[0m            ]  [0s:0s]\u001B[0m'
      '\r'
      '          \r'
      '\u001B[36m\u001B[1mHashing pieces...\u001B[0m [3.6 GiB/s]  78% '
      '[\u001B[32m=\u001B[0m\u001B[32m=\u001B[0m\u001B[32m=\u001B[0m\u001B[32m>\u001B[0m ]  [0s:0s]\u001B[0m'
      '\r'
      '          \r'
      '\u001B[36m\u001B[1mHashing pieces...\u001B[0m [3.6 GiB/s] 100% '
      '[\u001B[32m=\u001B[0m\u001B[32m=\u001B[0m\u001B[32m=\u001B[0m] \u001B[0m'
      '\n\nWrote out.torrent (elapsed 506ms)\n';

  test(
    'the arguments are the source, --private=true and the output path',
    () async {
      final runner = _FakeRunner(const ToolRunSuccess(stdout: '', stderr: ''));

      await Mkbrr(runner: runner).create(
        releaseDirectory: '/tmp/x',
        sourcePath: '/release/two.bin',
        outputPath: '/release/name.torrent',
        onProgress: (_) {},
      );

      expect(runner.calls.first, [
        'create',
        '/release/two.bin',
        '--private=true',
        '--output',
        '/release/name.torrent',
      ]);
    },
  );

  test('the version call is the version subcommand', () async {
    final runner = _FakeRunner(const ToolRunSuccess(stdout: '', stderr: ''));

    await Mkbrr(runner: runner).version(releaseDirectory: '/tmp/x');

    expect(runner.calls.first, ['version']);
  });

  // The window is the caller's, so a run that hashes a whole release is not
  // stopped at the default. A call that does not ask for one still gets the
  // default, which is what the version call does.
  test('the create call is given the 60 minute window, the version call the '
      'default', () async {
    final runner = _FakeRunner(const ToolRunSuccess(stdout: '', stderr: ''));

    await Mkbrr(runner: runner).create(
      releaseDirectory: '/tmp/x',
      sourcePath: '/release/two.bin',
      outputPath: '/release/name.torrent',
      onProgress: (_) {},
    );

    expect(runner.timeouts.first, const Duration(minutes: 60));

    await Mkbrr(runner: runner).version(releaseDirectory: '/tmp/x');

    expect(runner.timeouts.last, ToolRunner.callTimeout);
  });

  test('the percentage is read from each progress segment', () async {
    final seen = <MkbrrProgress>[];

    final result =
        await Mkbrr(
          runner: _FakeRunner(
            const ToolRunSuccess(stdout: fixture, stderr: ''),
            chunks: [fixture],
          ),
        ).create(
          releaseDirectory: '/tmp/x',
          sourcePath: 'two.bin',
          outputPath: 'out.torrent',
          onProgress: seen.add,
        );

    // The header and the clearing runs have no percentage, so they are not
    // progress. The last segment has no carriage return after it, so it is read
    // after the process ends.
    expect(seen.map((progress) => progress.percent), [40, 40, 78, 100]);
    expect(result, isA<MkbrrCreated>());
    expect((result as MkbrrCreated).path, 'out.torrent');
  });

  test('the rate and the remaining time are read from the brackets around the '
      'percentage', () async {
    final seen = <MkbrrProgress>[];

    await Mkbrr(
      runner: _FakeRunner(
        const ToolRunSuccess(stdout: fixture, stderr: ''),
        chunks: [fixture],
      ),
    ).create(
      releaseDirectory: '/tmp/x',
      sourcePath: 'two.bin',
      outputPath: 'out.torrent',
      onProgress: seen.add,
    );

    // The first segment has no rate: the tool prints one only once it has a
    // measurement. The colour codes are brackets too, but they are never closed,
    // so a rate cannot be read across one.
    expect(seen[0].speed, isNull);
    expect(seen[0].eta, '0s');

    expect(seen[1].speed, '3.7 GiB/s');
    expect(seen[2].speed, '3.6 GiB/s');

    // The last line still reports the rate it measured, but it has no pair after
    // the bar, so it reports no time left.
    expect(seen[3].speed, '3.6 GiB/s');
    expect(seen[3].eta, isNull);
  });

  test('a segment split across two reads is still read', () async {
    final seen = <MkbrrProgress>[];

    // The split is inside a segment, so the part that has not ended yet is kept
    // between the reads, the same way the runner keeps a partial line.
    final split = fixture.indexOf('40%') + 2;

    await Mkbrr(
      runner: _FakeRunner(
        const ToolRunSuccess(stdout: fixture, stderr: ''),
        chunks: [fixture.substring(0, split), fixture.substring(split)],
      ),
    ).create(
      releaseDirectory: '/tmp/x',
      sourcePath: 'two.bin',
      outputPath: 'out.torrent',
      onProgress: seen.add,
    );

    expect(seen.map((progress) => progress.percent), [40, 40, 78, 100]);
  });

  test('output with no progress reports nothing', () async {
    final seen = <MkbrrProgress>[];

    await Mkbrr(
      runner: _FakeRunner(
        const ToolRunSuccess(stdout: '\nWrote out.torrent\n', stderr: ''),
        chunks: ['\nWrote out.torrent\n'],
      ),
    ).create(
      releaseDirectory: '/tmp/x',
      sourcePath: 'two.bin',
      outputPath: 'out.torrent',
      onProgress: seen.add,
    );

    expect(seen, isEmpty);
  });

  test('the results are the typed ones the widget maps', () async {
    final notPresent =
        await Mkbrr(runner: _FakeRunner(const ToolRunNotAvailable())).create(
          releaseDirectory: '/tmp/x',
          sourcePath: 'two.bin',
          outputPath: 'out.torrent',
          onProgress: (_) {},
        );

    expect(notPresent, isA<MkbrrNotPresent>());

    final failed =
        await Mkbrr(
          runner: _FakeRunner(
            const ToolRunFailure(
              exitCode: 1,
              stdout: '',
              stderr:
                  'Error: invalid path "two.bin": no such file or directory',
            ),
          ),
        ).create(
          releaseDirectory: '/tmp/x',
          sourcePath: 'two.bin',
          outputPath: 'out.torrent',
          onProgress: (_) {},
        );

    expect(failed, isA<MkbrrRunFailed>());
    expect((failed as MkbrrRunFailed).exitCode, 1);

    final timedOut =
        await Mkbrr(
          runner: _FakeRunner(const ToolRunTimeout(stdout: '', stderr: '')),
        ).create(
          releaseDirectory: '/tmp/x',
          sourcePath: 'two.bin',
          outputPath: 'out.torrent',
          onProgress: (_) {},
        );

    expect(timedOut, isA<MkbrrRunTimeout>());
  });

  // The name is given as a name and the directory as a directory, because
  // `--output` is a filename without an extension and the runner sets no working
  // directory. Without them the tool writes a prefixed file beside the release's.
  test('the modify call names the file and the directory separately', () async {
    final runner = _FakeRunner(const ToolRunSuccess(stdout: '', stderr: ''));

    await Mkbrr(runner: runner).modify(
      releaseDirectory: '/release',
      torrentPath: '/release/name.torrent',
      outputName: 'name',
      private: false,
    );

    expect(runner.calls.first, [
      'modify',
      '/release/name.torrent',
      '--private=false',
      '--output',
      'name',
      '--output-dir',
      '/release',
    ]);

    // Hashing is not part of a modify, so it is not given the create window.
    expect(runner.timeouts.first, ToolRunner.callTimeout);
  });

  // The tool exits 0 when it cannot process a file, so the line it prints is the
  // only thing that says the run failed.
  test(
    'a modify that prints an error line is a failure, not a success',
    () async {
      final result =
          await Mkbrr(
            runner: _FakeRunner(
              const ToolRunSuccess(
                stdout:
                    '\nInfo: Modifying 1 torrent files...\n'
                    'Error processing name.torrent: could not load torrent: '
                    "bencode: syntax error (offset: 0): invalid value type character 'n'\n",
                stderr: '',
              ),
            ),
          ).modify(
            releaseDirectory: '/release',
            torrentPath: '/release/name.torrent',
            outputName: 'name',
            private: false,
          );

      expect(result, isA<MkbrrModifyFailed>());
      expect(
        (result as MkbrrModifyFailed).reason,
        'could not load torrent: bencode: syntax error (offset: 0): '
        "invalid value type character 'n'",
      );
    },
  );

  test('a modify that writes the file is a success', () async {
    final result =
        await Mkbrr(
          runner: _FakeRunner(
            const ToolRunSuccess(
              stdout:
                  '\nInfo: Modifying 1 torrent files...\n\n'
                  'Wrote /release/name.torrent (elapsed 0ms)\n',
              stderr: '',
            ),
          ),
        ).modify(
          releaseDirectory: '/release',
          torrentPath: '/release/name.torrent',
          outputName: 'name',
          private: true,
        );

    expect(result, isA<MkbrrModified>());
    expect((result as MkbrrModified).path, '/release/name.torrent');
  });
}

class _FakeRunner implements ToolRunner {
  _FakeRunner(this.result, {this.chunks = const []});

  final ToolRunResult result;

  /// What the reader is given as the output arrives, in the order it arrives.
  final List<String> chunks;

  final calls = <List<String>>[];

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
    timeouts.add(timeout);

    for (final chunk in chunks) {
      onOutput?.call(chunk);
    }

    return result;
  }
}
