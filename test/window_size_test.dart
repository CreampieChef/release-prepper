import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/window/window_controller.dart';
import 'package:release_prepper/feature/window/window_size.dart';
import 'package:release_prepper/feature/window/window_size_store.dart';

import 'fake_window_gateway.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('window_size_test');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  WindowSizeStore store(String path) =>
      WindowSizeStore(appDirectory: () async => Directory(path));

  FakeWindowGateway fakeWindow(int width, int height) => FakeWindowGateway(
    current: WindowSize(width: width, height: height),
  );

  WindowController windowController(String path, FakeWindowGateway window) =>
      WindowController(store: store(path), gateway: window);

  String readFile() =>
      File(p.join(directory.path, 'window_size.txt')).readAsStringSync();

  Future<WindowSize?> readRecorded() => store(directory.path).load();

  test(
    'window_size.txt is written in the shape the format describes',
    () async {
      await store(directory.path).save(WindowSize(width: 1440, height: 900));

      expect(readFile(), '$schemaVersion 1440 900\n');
    },
  );

  // A line that is not three whole numbers is not the format, a version this
  // app does not write is not read, and a size that is not positive is not a
  // size: all read as nothing rather than being guessed at, because this is a
  // file the app writes. The runners follow the same rules (`ai/doc.md` §7), so
  // a line one reader rejects is rejected by the other — which is what the
  // cases below are.
  test('a line this version does not read reads as nothing', () async {
    for (final line in [
      '2 1440 900',
      '1 1440.5 900',
      '1 1440 -900',
      '1 1440',
      'not a size line',
    ]) {
      await File(p.join(directory.path, 'window_size.txt')).writeAsString(line);

      expect(
        await readRecorded(),
        isNull,
        reason: 'the line "$line" is not read as a size',
      );
    }
  });

  // A file that is not there is the same as a new one: the window has never had
  // a size the app recorded, so the runners start it at their default.
  test('a missing file reads as nothing', () async {
    expect(await readRecorded(), isNull);
  });

  test('a line this version does read reads as the size it states', () async {
    await File(p.join(directory.path, 'window_size.txt'))
        .writeAsString('$schemaVersion 1440 900\n');

    expect(await readRecorded(), WindowSize(width: 1440, height: 900));
  });

  test('recording the size the window has writes the file', () async {
    final window = fakeWindow(1024, 640);

    expect(
      await windowController(directory.path, window).recordSize(),
      isA<WindowSizeRecorded>(),
    );

    expect(readFile(), '$schemaVersion 1024 640\n');
  });

  // The same size again is not a write, the same rule as the settings
  // feature's.
  test('the same size as the one recorded is not written again', () async {
    await store(directory.path).save(WindowSize(width: 1440, height: 900));

    final window = fakeWindow(1440, 900);

    expect(
      await windowController(directory.path, window).recordSize(),
      isA<WindowNothingToRecord>(),
    );

    expect(readFile(), '$schemaVersion 1440 900\n');
  });

  // A window that is not mapped reports nothing, and a size that is not
  // positive is not a size. Neither is recorded, and what was recorded stays as
  // it was.
  test('a size the app cannot store is not recorded', () async {
    final window = fakeWindow(0, 0);

    expect(
      await windowController(directory.path, window).recordSize(),
      isA<WindowNothingToRecord>(),
    );

    expect(
      File(p.join(directory.path, 'window_size.txt')).existsSync(),
      isFalse,
    );
  });

  // A write that fails is reported, because the close flow cannot show it and
  // must not depend on it: the file is left as it is, and the next run reads it
  // — which is also what the runners would have read.
  test('a file that cannot be written is reported', () async {
    File(p.join(directory.path, 'blocked'))
        .writeAsStringSync('a file, not a directory');

    final window = fakeWindow(1024, 640);

    expect(
      await windowController(
        p.join(directory.path, 'blocked'),
        window,
      ).recordSize(),
      isA<WindowWriteFailed>(),
    );
  });
}
