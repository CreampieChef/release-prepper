import 'dart:io';

import 'package:release_prepper/service/logging/tool_log.dart';
import 'package:release_prepper/service/native_tools/tool_locator.dart';
import 'package:release_prepper/service/native_tools/tool_runner.dart';

/// A `ToolRunner` for tests. Nothing is bundled here, so every tool is read
/// from PATH: one with no bundle directory, and one whose bundle directory has
/// nothing in it. The tests run the real ffmpeg, ffprobe and mtn this way.
/// The log writes to the release directory each call is given.
ToolRunner testRunner() => ToolRunner(
  locator: ToolLocator(
    bundleDirectory: Directory.systemTemp,
    pathVariable: Platform.environment['PATH'] ?? '',
    isWindows: Platform.isWindows,
  ),
  log: ToolLog(),
);
