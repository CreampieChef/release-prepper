import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/service/images/image_dimensions.dart';
import 'package:release_prepper/service/logging/tool_log.dart';
import 'package:release_prepper/service/native_tools/ffprobe.dart';
import 'package:release_prepper/service/native_tools/ffmpeg.dart';
import 'package:release_prepper/service/native_tools/mtn.dart';
import 'package:release_prepper/service/native_tools/tool_locator.dart';
import 'package:release_prepper/service/native_tools/tool_runner.dart';
import 'package:release_prepper/service/native_tools/uptooda.dart';

import 'test_font_store.dart';
import 'test_runner.dart';

void main() {
  // Plain tests, not widget tests: the body does not run in a fake-async zone,
  // so a real process call completes normally. The precondition is ffmpeg on
  // PATH (`ai/environment.md`).
  test('ffmpeg -version runs through the tool runner', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final result = await Ffmpeg(runner: testRunner())
        .version(releaseDirectory: directory.path);

    expect(result, isA<ToolRunSuccess>());
    expect((result as ToolRunSuccess).stdout, startsWith('ffmpeg version'));

    directory.deleteSync(recursive: true);
  });

  test('a tool that is not installed is reported as not available', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final result = await testRunner().run(
      NativeTool(name: 'release-prepper-no-such-tool'),
      const ['-version'],
      releaseDirectory: directory.path,
    );

    expect(result, isA<ToolRunNotAvailable>());

    directory.deleteSync(recursive: true);
  });

  test(
    'a non-zero exit code is a failure with the code and the output',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );

      final result = await testRunner().run(Ffmpeg.tool, const [
        '-not-a-real-option',
      ], releaseDirectory: directory.path);

      expect(result, isA<ToolRunFailure>());

      final failure = result as ToolRunFailure;
      expect(failure.exitCode, isNot(0));
      expect(failure.stderr, contains('Unrecognized option'));

      directory.deleteSync(recursive: true);
    },
  );

  // The window a call is stopped at is the one it was given, not the default, so
  // a caller that asks for a shorter one is stopped at it. The precondition is
  // `sleep` on PATH, the shortest tool that runs past a window without waiting
  // for the default one. The exit entry is the timeout's own: no code, because the
  // process was killed rather than finishing.
  test('a call is stopped at the window it was given', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final result = await testRunner().run(
      NativeTool(name: 'sleep'),
      const ['2'],
      releaseDirectory: directory.path,
      timeout: const Duration(seconds: 1),
    );

    expect(result, isA<ToolRunTimeout>());

    final entries = Directory(p.join(directory.path, ToolLog.directoryName))
        .listSync();

    final lines = File(entries.first.path)
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();

    expect(lines, hasLength(1));
    expect(lines[0]['stream'], 'exit');
    expect(lines[0]['exitCode'], isNull);
    expect(lines[0]['timedOut'], true);

    directory.deleteSync(recursive: true);
  });

  // The log is what the runner writes as the tool speaks, so a call that
  // produced no output at all still has an entry, and the exit code is its own
  // entry. The precondition is `echo` on PATH, the shortest tool the locator can
  // resolve.
  test('the log records each line as it arrives, then the exit code', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final runner = testRunner();

    final result = await runner.run(NativeTool(name: 'echo'), [
      'hello',
    ], releaseDirectory: directory.path);

    expect(result, isA<ToolRunSuccess>());

    final entries = Directory(p.join(directory.path, ToolLog.directoryName))
        .listSync();

    expect(entries, hasLength(1));

    final lines = File(entries.first.path)
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();

    expect(lines, hasLength(2));

    // The input is repeated on every entry, so an entry stands on its own.
    expect(lines[0]['tool'], 'echo');
    expect(lines[0]['input'], lines[1]['input']);
    expect(lines[0]['stream'], 'stdout');
    expect(lines[0]['line'], 'hello');

    expect(lines[1]['stream'], 'exit');
    expect(lines[1]['exitCode'], 0);
    expect(lines[1]['timedOut'], false);

    directory.deleteSync(recursive: true);
  });

  // A credential goes through the environment rather than the arguments
  // (`ai/bundled_native_tools.md`). The precondition is `sh` on PATH, the
  // shortest tool that can show what the child actually received. The recorded
  // input is the arguments, so the value is not in it — which is the point of
  // passing it this way. The value does appear in the recorded line, because the
  // tool echoed it: that is why a script that reads the variable must not print
  // it.
  test('the environment reaches the child, and the recorded input holds no copy of it', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final result = await testRunner().run(
      NativeTool(name: 'sh'),
      ['-c', 'echo "\$UPTOODA_HOSTER_API_KEY"'],
      releaseDirectory: directory.path,
      environment: {Uptooda.apiKeyVariable: 'the-key'},
    );

    expect(result, isA<ToolRunSuccess>());
    expect((result as ToolRunSuccess).stdout.trim(), 'the-key');

    final entries = Directory(p.join(directory.path, ToolLog.directoryName))
        .listSync();

    final lines = File(entries.first.path)
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();

    for (final line in lines) {
      expect(line['input'], isNot(contains('the-key')));
    }

    directory.deleteSync(recursive: true);
  });

  // A line the tool wrote without a newline at the end is still recorded,
  // because the stream closes when the process is gone.
  test('a last line with no newline is recorded', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );

    final result = await testRunner().run(NativeTool(name: 'printf'), [
      'no-newline',
    ], releaseDirectory: directory.path);

    expect(result, isA<ToolRunSuccess>());

    final entries = Directory(p.join(directory.path, ToolLog.directoryName))
        .listSync();

    final lines = File(entries.first.path)
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();

    expect(lines, hasLength(2));
    expect(lines[0]['line'], 'no-newline');
    expect(lines[1]['stream'], 'exit');

    directory.deleteSync(recursive: true);
  });

  // The whole feature against the real binary: one call, then the values the
  // editor shows. Bitrates depend on the encoder, so the test asserts the parts
  // that follow from the parameters it passes.
  test('one probe call gives the values the editor shows', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final path = '${directory.path}/movie.mp4';

    final runner = testRunner();

    final generated = await runner.run(Ffmpeg.tool, [
      '-hide_banner',
      '-y',
      '-f',
      'lavfi',
      '-i',
      'testsrc=duration=2:size=3840x2160:rate=30000/1001',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=1000:duration=2',
      '-c:v',
      'libx264',
      '-ar',
      '48000',
      '-ac',
      '2',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      path,
    ], releaseDirectory: directory.path);

    expect(generated, isA<ToolRunSuccess>());

    final result = await Ffprobe(runner: runner)
        .probe(releaseDirectory: directory.path, filePath: path);

    expect(
      result,
      isA<MediaProbeSuccess>(),
      reason: 'the file was just written',
    );

    final info = (result as MediaProbeSuccess).info;

    expect(info.duration, '00:00:02');
    expect(info.videoType, '2160p');
    expect(info.videoFormat, 'MP4');
    expect(
      info.videoStream,
      startsWith('AVC, 3840x2160, 29.970 (30000/1001) FPS'),
    );
    expect(info.audioStream, startsWith('AAC LC, 48.0 kHz, 2 channels'));

    directory.deleteSync(recursive: true);
  });

  // The frame feature against the real binary: one key frame written at the
  // source resolution, which is what both the Screenshots section and the video
  // thumbnail write. `-g 1` makes every frame a key frame, so the seek lands on
  // one. The dimensions are read from the JPEG header with the same reader the
  // scans use, so the test asserts the picture is not scaled down.
  test('one screenshot call writes a full-resolution JPEG', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final runner = testRunner();

    final videoPath = '${directory.path}/movie.mp4';
    final outputPath =
        '${directory.path}/images/movie.mp4/_rp_screenshot01.jpg';

    Directory(p.dirname(outputPath)).createSync(recursive: true);

    final generated = await runner.run(Ffmpeg.tool, [
      '-hide_banner',
      '-y',
      '-f',
      'lavfi',
      '-i',
      'testsrc=duration=4:size=3840x2160:rate=30',
      '-g',
      '1',
      videoPath,
    ], releaseDirectory: directory.path);

    expect(generated, isA<ToolRunSuccess>());

    final result = await Ffmpeg(runner: runner).screenshot(
      releaseDirectory: directory.path,
      inputPath: videoPath,
      outputPath: outputPath,
      seekSeconds: 2,
    );

    expect(result, isA<ToolRunSuccess>(), reason: 'the file was just written');

    final bytes = File(outputPath).readAsBytesSync();

    expect(bytes.length, greaterThan(0));
    // A JPEG starts with the SOI marker.
    expect(bytes.sublist(0, 2), [0xFF, 0xD8]);

    // The picture is the size the source is, not a scaled-down copy of it.
    final dimensions = await readImageDimensions(outputPath);

    expect(dimensions?.width, 3840);
    expect(dimensions?.height, 2160);

    directory.deleteSync(recursive: true);
  });

  // The screenlist feature against the real binary: one call writes the grid.
  // The duration is long enough that mtn does not warn about the step, and
  // `-g 1` makes every frame a key frame so the seek lands on one — mtn exits
  // with a non-zero code when it prints a warning even though it wrote the
  // file, so a run that warns would be reported as a failure here.
  //
  // The font path is the font store's, as the app passes it. The bytes the test
  // bundle gives are not a font, so the tool cannot open it and draws without the
  // info text; that is not a failure, and these tests are not about the font.
  test('one screenlist call writes the screenlist JPEG', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final runner = testRunner();

    final videoPath = '${directory.path}/movie.mp4';
    final outputDirectory = '${directory.path}/images/movie.mp4';

    Directory(outputDirectory).createSync(recursive: true);

    final generated = await runner.run(Ffmpeg.tool, [
      '-hide_banner',
      '-y',
      '-f',
      'lavfi',
      '-i',
      'testsrc=duration=300:size=320x180:rate=30',
      '-g',
      '1',
      videoPath,
    ], releaseDirectory: directory.path);

    expect(generated, isA<ToolRunSuccess>());

    final result = await Mtn(runner: runner).screenlist(
      releaseDirectory: directory.path,
      inputPath: videoPath,
      outputDirectory: outputDirectory,
      rows: 4,
      fontPath: await testFontStore().fontPath(),
    );

    expect(result, isA<ToolRunSuccess>(), reason: 'the file was just written');

    final bytes = File('$outputDirectory/${Mtn.screenlistName}.jpg')
        .readAsBytesSync();

    expect(bytes.length, greaterThan(0));
    expect(bytes.sublist(0, 2), [0xFF, 0xD8]);

    directory.deleteSync(recursive: true);
  });

  // mtn skips a frame it reads as blank and leaves that cell empty, so the grid
  // can end with an empty frame that is not a frame of the video; the app wants
  // every cell filled, which is what `-b 2` does. A skipped shot makes mtn exit
  // non-zero, so a video that ends with a black section is what shows the flag
  // is passed: with the default `-b 0.80` this run would be a failure.
  test('the screenlist flags keep blank frames in the grid, so no cell is left empty', () async {
    final directory = Directory.systemTemp.createTempSync(
      'release_prepper_test',
    );
    final runner = testRunner();

    final videoPath = '${directory.path}/movie.mp4';
    final outputDirectory = '${directory.path}/images/movie.mp4';

    Directory(outputDirectory).createSync(recursive: true);

    final generated = await runner.run(Ffmpeg.tool, [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-f',
      'lavfi',
      '-i',
      'testsrc=duration=200:size=320x180:rate=30',
      '-f',
      'lavfi',
      '-i',
      'color=black:size=320x180:rate=30:duration=100',
      '-filter_complex',
      '[0:v][1:v]concat=n=2:v=1:a=0',
      '-g',
      '1',
      videoPath,
    ], releaseDirectory: directory.path);

    expect(generated, isA<ToolRunSuccess>());

    final result = await Mtn(runner: runner).screenlist(
      releaseDirectory: directory.path,
      inputPath: videoPath,
      outputDirectory: outputDirectory,
      rows: 4,
      fontPath: await testFontStore().fontPath(),
    );

    expect(
      result,
      isA<ToolRunSuccess>(),
      reason: 'a shot in the black part would have been skipped',
    );

    directory.deleteSync(recursive: true);
  });
}
