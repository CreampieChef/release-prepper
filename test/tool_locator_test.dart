import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/service/native_tools/tool_locator.dart';

/// A file the resolver is meant to accept as a tool: written, and made
/// executable where the resolver's rule is the permission bits. On Windows any
/// file on PATH is one, so writing it is enough. `dart:io` has no chmod, so
/// this is the only place these tests run a process.
void makeTool(File file) {
  file.writeAsStringSync('');

  if (!Platform.isWindows) {
    Process.runSync('chmod', ['u+x', file.path]);
  }
}

void main() {
  // A tool the app bundles is never read from PATH: a system install of uptooda
  // has the unmodified upload scripts, so it is not an acceptable substitute.
  test('a bundled tool is read from the bundle', () {
    final bundle = Directory.systemTemp.createTempSync('release_prepper_test');
    final directory = Directory(p.join(bundle.path, 'uptooda'));

    directory.createSync(recursive: true);
    makeTool(File(p.join(directory.path, 'release_prepper_tool')));

    final location =
        ToolLocator(
          bundleDirectory: bundle,
          pathVariable: '',
          isWindows: Platform.isWindows,
        ).resolve(
          NativeTool(name: 'release_prepper_tool', bundleDirectory: 'uptooda'),
        );

    expect(location, isA<ToolFound>());
    expect((location as ToolFound).source, ToolSource.bundled);
    expect(location.path, p.join(directory.path, 'release_prepper_tool'));

    bundle.deleteSync(recursive: true);
  });

  test('a bundled tool that is not in the bundle is not found, even when PATH has it', () {
    final bundle = Directory.systemTemp.createTempSync('release_prepper_test');
    final path = Directory.systemTemp.createTempSync('release_prepper_test');

    File(p.join(path.path, 'release_prepper_tool')).writeAsStringSync('');

    final location =
        ToolLocator(
          bundleDirectory: bundle,
          pathVariable: path.path,
          isWindows: Platform.isWindows,
        ).resolve(
          NativeTool(name: 'release_prepper_tool', bundleDirectory: 'uptooda'),
        );

    expect(location, isA<ToolNotFound>());

    bundle.deleteSync(recursive: true);
    path.deleteSync(recursive: true);
  });

  // The committed Windows binary is `uptooda-cli.exe` while the tool's name is
  // `uptooda-cli`, which is what the resolver could not find before.
  test('a bundled tool is found under the extension Windows expects', () {
    final bundle = Directory.systemTemp.createTempSync('release_prepper_test');
    final directory = Directory(p.join(bundle.path, 'uptooda'));

    directory.createSync(recursive: true);
    final exe = File(p.join(directory.path, 'uptooda-cli.exe'));
    makeTool(exe);

    final location = ToolLocator(
      bundleDirectory: bundle,
      pathVariable: '',
      isWindows: true,
    ).resolve(NativeTool(name: 'uptooda-cli', bundleDirectory: 'uptooda'));

    expect(location, isA<ToolFound>());
    expect((location as ToolFound).path, exe.path);

    bundle.deleteSync(recursive: true);
  });

  // A file in the bundle is accepted on the same terms as one on PATH. This is
  // what a copy the user puts there by hand can fail: written without the
  // execute bits, it is not something `Process.start` can run.
  test('a bundled file without an execute bit is not found', () {
    final bundle = Directory.systemTemp.createTempSync('release_prepper_test');
    final directory = Directory(p.join(bundle.path, 'uptooda'));

    directory.createSync(recursive: true);
    File(p.join(directory.path, 'release_prepper_tool')).writeAsStringSync('');

    final location =
        ToolLocator(
          bundleDirectory: bundle,
          pathVariable: '',
          isWindows: Platform.isWindows,
        ).resolve(
          NativeTool(name: 'release_prepper_tool', bundleDirectory: 'uptooda'),
        );

    expect(location, isA<ToolNotFound>());

    bundle.deleteSync(recursive: true);
  }, skip: Platform.isWindows ? 'Windows has no execute bits' : false);

  // ffmpeg is the same tool whichever copy it runs, so the app prefers its own
  // and uses the user's when the bundle has nothing there.
  test(
    'a tool with a path fallback is read from the bundle when it is there',
    () {
      final bundle = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );
      final path = Directory.systemTemp.createTempSync('release_prepper_test');
      final directory = Directory(p.join(bundle.path, 'media'));

      directory.createSync(recursive: true);
      final bundled = File(p.join(directory.path, 'ffmpeg'));
      makeTool(bundled);
      makeTool(File(p.join(path.path, 'ffmpeg')));

      final location =
          ToolLocator(
            bundleDirectory: bundle,
            pathVariable: path.path,
            isWindows: Platform.isWindows,
          ).resolve(
            NativeTool(
              name: 'ffmpeg',
              bundleDirectory: 'media',
              pathFallback: true,
            ),
          );

      expect(location, isA<ToolFound>());
      expect((location as ToolFound).source, ToolSource.bundled);
      expect(location.path, bundled.path);

      bundle.deleteSync(recursive: true);
      path.deleteSync(recursive: true);
    },
  );

  test(
    'a tool with a path fallback is read from PATH when the bundle has nothing',
    () {
      final bundle = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );
      final path = Directory.systemTemp.createTempSync('release_prepper_test');

      Directory(p.join(bundle.path, 'media')).createSync(recursive: true);
      final system = File(p.join(path.path, 'ffmpeg'));
      makeTool(system);

      final location =
          ToolLocator(
            bundleDirectory: bundle,
            pathVariable: path.path,
            isWindows: Platform.isWindows,
          ).resolve(
            NativeTool(
              name: 'ffmpeg',
              bundleDirectory: 'media',
              pathFallback: true,
            ),
          );

      expect(location, isA<ToolFound>());
      expect((location as ToolFound).source, ToolSource.system);
      expect(location.path, system.path);

      bundle.deleteSync(recursive: true);
      path.deleteSync(recursive: true);
    },
  );

  // A copy in the bundle without the execute bits is not a tool, so the
  // fallback is what the app uses rather than a copy it cannot start.
  test('a tool with a path fallback does not use a bundle file without an execute bit', () {
    final bundle = Directory.systemTemp.createTempSync('release_prepper_test');
    final path = Directory.systemTemp.createTempSync('release_prepper_test');

    Directory(p.join(bundle.path, 'media')).createSync(recursive: true);
    File(p.join(bundle.path, 'media', 'ffmpeg')).writeAsStringSync('');
    final system = File(p.join(path.path, 'ffmpeg'));
    makeTool(system);

    final location =
        ToolLocator(
          bundleDirectory: bundle,
          pathVariable: path.path,
          isWindows: Platform.isWindows,
        ).resolve(
          NativeTool(
            name: 'ffmpeg',
            bundleDirectory: 'media',
            pathFallback: true,
          ),
        );

    expect(location, isA<ToolFound>());
    expect((location as ToolFound).source, ToolSource.system);
    expect(location.path, system.path);

    bundle.deleteSync(recursive: true);
    path.deleteSync(recursive: true);
  }, skip: Platform.isWindows ? 'Windows has no execute bits' : false);

  // A Windows build of ffmpeg is named with the extension, so that is the name
  // tried first in the bundle as well as on PATH.
  test(
    'a tool with a path fallback is found under the extension Windows expects',
    () {
      final bundle = Directory.systemTemp.createTempSync(
        'release_prepper_test',
      );
      final directory = Directory(p.join(bundle.path, 'media'));

      directory.createSync(recursive: true);
      final exe = File(p.join(directory.path, 'ffmpeg.exe'));
      makeTool(exe);

      final location =
          ToolLocator(
            bundleDirectory: bundle,
            pathVariable: '',
            isWindows: true,
          ).resolve(
            NativeTool(
              name: 'ffmpeg',
              bundleDirectory: 'media',
              pathFallback: true,
            ),
          );

      expect(location, isA<ToolFound>());
      expect((location as ToolFound).source, ToolSource.bundled);
      expect(location.path, exe.path);

      bundle.deleteSync(recursive: true);
    },
  );

  // A tool with no bundle directory is the user's, so it is read from PATH.
  test('a tool the app does not bundle is read from PATH', () {
    final path = Directory.systemTemp.createTempSync('release_prepper_test');
    final tool = File(p.join(path.path, 'release_prepper_tool'));

    makeTool(tool);

    final location = ToolLocator(
      bundleDirectory: Directory.systemTemp,
      pathVariable: path.path,
      isWindows: Platform.isWindows,
    ).resolve(NativeTool(name: 'release_prepper_tool'));

    expect(location, isA<ToolFound>());
    expect((location as ToolFound).source, ToolSource.system);

    path.deleteSync(recursive: true);
  });

  // On Windows an executable is named with its extension, so that is the name
  // tried first: a file there without one is not something `Process.start` can
  // run, even when it is on PATH.
  test('on Windows the name with the extension is the one found on PATH', () {
    final path = Directory.systemTemp.createTempSync('release_prepper_test');

    File(p.join(path.path, 'release_prepper_tool')).writeAsStringSync('');
    final exe = File(p.join(path.path, 'release_prepper_tool.exe'));
    exe.writeAsStringSync('');

    final location = ToolLocator(
      bundleDirectory: Directory.systemTemp,
      pathVariable: path.path,
      isWindows: true,
    ).resolve(NativeTool(name: 'release_prepper_tool'));

    expect(location, isA<ToolFound>());
    expect((location as ToolFound).path, exe.path);

    path.deleteSync(recursive: true);
  });

  test('a tool that is neither bundled nor on PATH is not found', () {
    final bundle = Directory.systemTemp.createTempSync('release_prepper_test');

    final location = ToolLocator(
      bundleDirectory: bundle,
      pathVariable: '',
      isWindows: Platform.isWindows,
    ).resolve(NativeTool(name: 'release-prepper-no-such-tool'));

    expect(location, isA<ToolNotFound>());

    bundle.deleteSync(recursive: true);
  });

  // A file on PATH without an execute bit is not a tool. A file the test writes
  // has the default mode, so it is what shows the check. Windows has no execute
  // bits, so there the check is the extension instead, which the test above
  // covers.
  test('a file on PATH without an execute bit is not found', () {
    final path = Directory.systemTemp.createTempSync('release_prepper_test');

    File(p.join(path.path, 'release_prepper_tool')).writeAsStringSync('');

    final location = ToolLocator(
      bundleDirectory: Directory.systemTemp,
      pathVariable: path.path,
      isWindows: Platform.isWindows,
    ).resolve(NativeTool(name: 'release_prepper_tool'));

    expect(location, isA<ToolNotFound>());

    path.deleteSync(recursive: true);
  }, skip: Platform.isWindows ? 'Windows has no execute bits' : false);
}
