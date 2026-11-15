import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/service/logging/debug_text_log.dart';
import 'package:release_prepper/service/logging/tool_log.dart';

void main() {
  // A block is what a run is read by, so its shape is what these tests hold:
  // the four frame lines, a blank line, then the headers as `name: value` and
  // what was sent or answered (`ai/uploading_draft.md` §8).
  String gutter(String marker) => marker * DebugTextLog.gutterWidth;

  String rule(String marker) => marker * DebugTextLog.ruleWidth;

  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('debug_log_test');
    verboseTrackerLogging = true;
  });

  tearDown(() {
    verboseTrackerLogging = false;

    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  List<String> written() =>
      File(p.join(directory.path, ToolLog.directoryName, DebugTextLog.fileName))
          .readAsStringSync()
          .split('\n');

  test('a run that was not started with the flag writes nothing', () async {
    verboseTrackerLogging = false;

    // Off is what a normal run is, so the folder the app's log uses is not
    // created for a copy that is not written.
    await DebugTextLog().sent(directory.path, 'GET http://localhost:40002/', [
      'Cookie: session=abc',
    ]);

    expect(
      Directory(p.join(directory.path, ToolLog.directoryName)).existsSync(),
      isFalse,
    );
  });

  test('a sent block is the frame, the headers, and the body', () async {
    await DebugTextLog().sent(directory.path, 'GET http://localhost:40002/', [
      'Cookie: session=abc',
      'User-Agent: ReleasePrepper/0.1.0',
      'Content-Length: 12',
    ], 'the body');

    final lines = written();

    expect(lines[0], rule('<'));
    expect(
      lines[1],
      matches(RegExp(r'^<{10} \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$')),
    );
    expect(lines[2], '${gutter('<')} GET http://localhost:40002/');
    expect(lines[3], rule('<'));
    expect(lines[4], '');

    // A header is one line, `name: value`, as the answer's headers are written.
    expect(lines[5], 'Cookie: session=abc');
    expect(lines[6], 'User-Agent: ReleasePrepper/0.1.0');
    expect(lines[7], 'Content-Length: 12');
    expect(lines[8], 'the body');
  });

  test(
    'the block for what the site answered carries its status and its marker',
    () async {
      await DebugTextLog().received(
        directory.path,
        '200 GET http://localhost:40002/',
        ['content-type: text/html'],
        'the page',
      );

      final lines = written();

      expect(lines[0], rule('>'));
      expect(
        lines[1],
        matches(
          RegExp(r'^>{10} \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$'),
        ),
      );
      expect(lines[2], '${gutter('>')} 200 GET http://localhost:40002/');
      expect(lines[3], rule('>'));
      expect(lines[5], 'content-type: text/html');
      expect(lines[6], 'the page');
    },
  );

  // A request that fails has no answer, so it is neither of the other two and
  // has a marker of its own.
  test('a request that got no answer is the third kind of block', () async {
    await DebugTextLog().failed(
      directory.path,
      'GET http://localhost:40002/',
      'Connection closed before full header was received',
    );

    final lines = written();

    expect(lines[0], rule('#'));
    expect(
      lines[1],
      matches(RegExp(r'^#{10} \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$')),
    );
    expect(lines[2], '${gutter('#')} GET http://localhost:40002/');
    expect(lines[3], rule('#'));

    // There is no header for a request that answered with nothing.
    expect(lines[5], 'Connection closed before full header was received');
  });

  test('the blocks are appended in the order the calls were made', () async {
    final log = DebugTextLog();

    await log.sent(directory.path, 'GET a', []);
    await log.received(directory.path, '200 GET a', [], 'the answer');

    final text = File(
      p.join(directory.path, ToolLog.directoryName, DebugTextLog.fileName),
    ).readAsStringSync();

    expect(text.indexOf(rule('<')), 0);
    expect(text.indexOf(rule('>')), greaterThan(text.indexOf(rule('<'))));
  });
}
