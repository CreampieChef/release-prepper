import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/feature/release/release.dart';
import 'package:release_prepper/feature/window/window_controller.dart';
import 'package:release_prepper/feature/window/window_gateway.dart';
import 'package:release_prepper/feature/window/window_record.dart';
import 'package:release_prepper/feature/window/window_record_store.dart';
import 'package:release_prepper/feature/window/window_size.dart';

import 'fake_window_gateway.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('window_record_test');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  WindowRecordStore store(String path) =>
      WindowRecordStore(appDirectory: () async => Directory(path));

  WindowRecord record(int width, int height, {bool maximized = false}) =>
      WindowRecord(
        size: WindowSize(width: width, height: height),
        maximized: maximized,
      );

  // The composition root is what registers the controller's method for the
  // window's events, because the controller has no widget to do it in. The test
  // registers the same method, so a test that fires an event goes through the
  // same path as the app. A test that records at the close is the same path as
  // `app_close.dart`, which is the only place that knows the app is closing.
  WindowController windowController(String path, FakeWindowGateway window) {
    final controller = WindowController(store: store(path), gateway: window);

    window.addEventListener(controller.record);

    return controller;
  }

  String readFile() =>
      File(p.join(directory.path, 'window_size.txt')).readAsStringSync();

  Future<WindowRecord?> readRecorded() => store(directory.path).load();

  test(
    'window_size.txt is written in the shape the format describes',
    () async {
      await store(directory.path).save(record(1440, 900, maximized: true));

      expect(readFile(), '$schemaVersion 1440 900 1\n');
    },
  );

  // A line that is not four whole numbers is not the format, a version this app
  // does not write is not read, a size that is not positive is not a size, and
  // a state that is not one of the two this app writes is not a state: all read
  // as nothing rather than being guessed at, because this is a file the app
  // writes. The runners follow the same rules (`ai/doc.md` §7), so a line one
  // reader rejects is rejected by the other — which is what the cases below
  // are.
  //
  // A line of three numbers is read as nothing too, which is what a file the
  // version before the state was added wrote: the format was not published with
  // that shape, so nothing here is expected to hold one.
  test('a line this version does not read reads as nothing', () async {
    for (final line in [
      '2 1440 900 1',
      '1 1440.5 900 1',
      '1 1440 -900 1',
      '1 1440 900',
      '1 1440 900 2',
      '1 1440 900 true',
      'not a record line',
    ]) {
      await File(p.join(directory.path, 'window_size.txt')).writeAsString(line);

      expect(
        await readRecorded(),
        isNull,
        reason: 'the line "$line" is not read as a record',
      );
    }
  });

  // A file that is not there is the same as a new one: the window has never had
  // a record the app wrote, so the runners start it at their default.
  test('a missing file reads as nothing', () async {
    expect(await readRecorded(), isNull);
  });

  test('a line this version does read reads as the record it states', () async {
    await File(p.join(directory.path, 'window_size.txt'))
        .writeAsString('$schemaVersion 1440 900 1\n');

    expect(await readRecorded(), record(1440, 900, maximized: true));
  });

  test('recording the record the window has writes the file', () async {
    final window = FakeWindowGateway(current: record(1024, 640));

    expect(
      await windowController(directory.path, window).record(WindowEvent.closed),
      isA<WindowRecordWritten>(),
    );

    expect(readFile(), '$schemaVersion 1024 640 0\n');
  });

  // The same record again is not a write, the same rule as the settings
  // feature's. The whole record is compared, so a record that differs only in
  // its state is a write — that is the state being remembered.
  test('the same record as the one recorded is not written again', () async {
    await store(directory.path).save(record(1440, 900, maximized: true));

    final window = FakeWindowGateway(
      current: record(1440, 900, maximized: true),
    );

    expect(
      await windowController(directory.path, window).record(WindowEvent.closed),
      isA<WindowNothingToRecord>(),
    );

    expect(readFile(), '$schemaVersion 1440 900 1\n');
  });

  test('a record that differs only in its state is written', () async {
    await store(directory.path).save(record(1440, 900));

    final window = FakeWindowGateway(
      current: record(1440, 900, maximized: true),
    );

    expect(
      await windowController(
        directory.path,
        window,
      ).record(WindowEvent.maximized),
      isA<WindowRecordWritten>(),
    );

    expect(readFile(), '$schemaVersion 1440 900 1\n');
  });

  // A window that is not mapped reports nothing, and a size that is not
  // positive is not a size. Neither is recorded, and what was recorded stays as
  // it was.
  test('a record the app cannot store is not recorded', () async {
    final window = FakeWindowGateway(current: record(0, 0));

    expect(
      await windowController(directory.path, window).record(WindowEvent.closed),
      isA<WindowNothingToRecord>(),
    );

    expect(
      File(p.join(directory.path, 'window_size.txt')).existsSync(),
      isFalse,
    );
  });

  // A maximized window reports the size the desktop gave it, which is not a
  // size the user chose, so the size in the record stays the one already
  // recorded and only the state changes.
  test('a window closed maximized keeps the size that was recorded', () async {
    await store(directory.path).save(record(1440, 900));

    final window = FakeWindowGateway(
      current: record(1920, 1080, maximized: true),
    );

    expect(
      await windowController(directory.path, window).record(WindowEvent.closed),
      isA<WindowRecordWritten>(),
    );

    expect(readFile(), '$schemaVersion 1440 900 1\n');
  });

  // The size the user chose is the size the window has while it is not
  // maximized, so a size change is recorded as it happens — and that is the
  // size the record keeps through the next maximize, which is the size the
  // window had before the first maximize.
  test(
    'the size recorded at a size change is the size a later maximize keeps',
    () async {
      final window = FakeWindowGateway(current: record(1024, 640));

      final controller = windowController(directory.path, window);

      await controller.record(WindowEvent.resized);

      expect(readFile(), '$schemaVersion 1024 640 0\n');

      window.current = record(1920, 1080, maximized: true);

      await controller.record(WindowEvent.maximized);

      expect(readFile(), '$schemaVersion 1024 640 1\n');
    },
  );

  // At the un-maximize the size the window has is the one the desktop chose to
  // restore it to, so the record keeps the size it had, and the window is asked
  // for it: on Windows the window is already at it, on Linux the desktop may
  // have put it elsewhere (`ai/doc.md` §7).
  test(
    'the size a window was restored to at an un-maximize is not recorded',
    () async {
      await store(directory.path).save(record(1440, 900, maximized: true));

      final window = FakeWindowGateway(current: record(1920, 1080));

      expect(
        await windowController(
          directory.path,
          window,
        ).record(WindowEvent.unmaximized),
        isA<WindowRecordWritten>(),
      );

      expect(readFile(), '$schemaVersion 1440 900 0\n');

      expect(window.requested, [WindowSize(width: 1440, height: 900)]);
    },
  );

  // Nothing is asked for when the window is at the size the record holds, which
  // is the case on Windows: the size the record holds is the size the window
  // was created with, so un-maximizing returns to it without the app asking.
  test(
    'a window already at the recorded size is not asked for a size',
    () async {
      await store(directory.path).save(record(1440, 900, maximized: true));

      final window = FakeWindowGateway(current: record(1440, 900));

      expect(
        await windowController(
          directory.path,
          window,
        ).record(WindowEvent.unmaximized),
        isA<WindowRecordWritten>(),
      );

      expect(window.requested, isEmpty);
    },
  );

  // A record with nothing in it yet cannot keep a size, because there is none,
  // so the size the window has is the first one and nothing is asked for: the
  // record and the window agree.
  test(
    'a record with nothing recorded yet uses the size the window has',
    () async {
      final window = FakeWindowGateway(
        current: record(1920, 1080, maximized: true),
      );

      expect(
        await windowController(
          directory.path,
          window,
        ).record(WindowEvent.maximized),
        isA<WindowRecordWritten>(),
      );

      expect(readFile(), '$schemaVersion 1920 1080 1\n');
    },
  );

  // An event is written through the callback the feature registers, the same
  // path the plugin's event takes.
  test('a window event a listener is told about writes the record', () async {
    await store(directory.path).save(record(1440, 900));

    final window = FakeWindowGateway(
      current: record(1920, 1080, maximized: true),
    );

    windowController(directory.path, window);

    await window.event(WindowEvent.maximized);

    expect(readFile(), '$schemaVersion 1440 900 1\n');
  });

  // A size change through the same callback records the size the window has,
  // the path an interactive resize takes.
  test('a size change a listener is told about records the size', () async {
    await store(directory.path).save(record(1440, 900, maximized: true));

    final window = FakeWindowGateway(current: record(1024, 640));

    windowController(directory.path, window);

    await window.event(WindowEvent.resized);

    expect(readFile(), '$schemaVersion 1024 640 0\n');

    expect(window.requested, isEmpty);
  });

  // A write that fails is reported, because the close flow cannot show it and
  // must not depend on it: the file is left as it is, and the next run reads it
  // — which is also what the runners would have read.
  test('a file that cannot be written is reported', () async {
    File(p.join(directory.path, 'blocked'))
        .writeAsStringSync('a file, not a directory');

    final window = FakeWindowGateway(current: record(1024, 640));

    expect(
      await windowController(
        p.join(directory.path, 'blocked'),
        window,
      ).record(WindowEvent.closed),
      isA<WindowWriteFailed>(),
    );
  });
}
