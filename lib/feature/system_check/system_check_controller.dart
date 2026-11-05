import 'dart:io';

import '../../service/native_tools/ffprobe.dart';
import '../../service/native_tools/ffmpeg.dart';
import '../../service/native_tools/mkbrr.dart';
import '../../service/native_tools/mtn.dart';
import '../../service/native_tools/tool_locator.dart';
import '../../service/native_tools/tool_runner.dart';
import '../../service/native_tools/uptooda.dart';

/// The System Check feature: the tools the app calls, checked at the same time
/// and reported one by one as each call comes back.
///
/// The controller owns the list of required tools and the calls; the widget
/// shows the results and maps them to localized text (rule 13). It is
/// app-level, so it is a provider entry, and the app data directory is given
/// to it as a function for the same reason `SettingsStore` has one:
/// `ToolRunner` needs a directory to write the tool log to, and outside a
/// release there is no release directory, so the app data directory is what the
/// check's calls are logged under.
class SystemCheckController {
  SystemCheckController({
    required this.ffmpeg,
    required this.ffprobe,
    required this.mtn,
    required this.uptooda,
    required this.mkbrr,
    required this.appDirectory,
  });

  final Ffmpeg ffmpeg;
  final Ffprobe ffprobe;
  final Mtn mtn;
  final Uptooda uptooda;
  final Mkbrr mkbrr;

  /// The app data directory, resolved by the function the composition root
  /// gives rather than by the controller (rule 4).
  final Future<Directory> Function() appDirectory;

  /// The tools the app calls, in the order the page lists them, each with the
  /// version call its wrapper names. One list, so the order the page shows and
  /// the order the calls run in cannot disagree. ffmpeg, ffprobe and mtn are
  /// read from the bundle when the app has a copy there and from PATH when it
  /// does not; uptooda and mkbrr are the ones the app ships, so for them
  /// "found" means present in the bundle.
  List<(NativeTool, Future<ToolRunResult> Function(String))> calls() => [
    (Ffmpeg.tool, (directory) => ffmpeg.version(releaseDirectory: directory)),
    (Ffprobe.tool, (directory) => ffprobe.version(releaseDirectory: directory)),
    (Mtn.tool, (directory) => mtn.version(releaseDirectory: directory)),
    (Uptooda.tool, (directory) => uptooda.version(releaseDirectory: directory)),
    (Mkbrr.tool, (directory) => mkbrr.version(releaseDirectory: directory)),
  ];

  /// One version call per tool, all of them at the same time. A tool that
  /// cannot be started is reported as not present; a call that ran is reported
  /// with the first line of its output, which is the version line, as the tool
  /// wrote it.
  ///
  /// [onResult] is called for each result as its call comes back, so a tool
  /// that hangs does not hold up the tools that answered: the page shows a row
  /// as its own result arrives, and the hanging call ends as a timeout at the
  /// window the runner gives it. The calls are made in the order `calls()`
  /// lists them, which is the order the page draws the rows in.
  Future<void> check({
    required void Function(SystemCheckResult result) onResult,
  }) async {
    final directory = (await appDirectory()).path;

    await Future.wait([
      for (final (tool, call) in calls())
        call(directory).then((run) => onResult(_map(tool, run))),
    ]);
  }

  SystemCheckResult _map(
    NativeTool tool,
    ToolRunResult result,
  ) => switch (result) {
    ToolRunNotAvailable() => SystemCheckNotPresent(tool: tool),
    ToolRunFailure(exitCode: final exitCode) =>
      tool == Mtn.tool
          // mtn is the one tool whose version call does not exit 0: `-v` is
          // verbose mode, and a run with no input file is an error to mtn, so
          // it prints the version banner to stderr and exits 255. For this tool
          // the exit code is not a failure of the check, so what it printed is
          // the result, and a run that printed nothing is still no output.
          ? _versionLine(tool, result.stderr)
          : SystemCheckRunFailed(tool: tool, exitCode: exitCode),
    ToolRunTimeout() => SystemCheckRunTimeout(tool: tool),
    ToolRunSuccess(stdout: final stdout) => _versionLine(tool, stdout),
  };

  SystemCheckResult _versionLine(NativeTool tool, String stdout) {
    final line = stdout
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');

    // A call that ran and printed nothing has no version to show; it is
    // reported rather than guessed at.
    return line.isEmpty
        ? SystemCheckNoOutput(tool: tool)
        : SystemCheckFound(tool: tool, version: line.trim());
  }
}

sealed class SystemCheckResult {
  const SystemCheckResult({required this.tool});

  /// The tool the result is about. Its name is what the page shows: a tool
  /// name is the same in every language, like a tracker name, so it is not an
  /// `AppLocalizations` key.
  final NativeTool tool;
}

final class SystemCheckFound extends SystemCheckResult {
  const SystemCheckFound({required super.tool, required this.version});

  /// The first line of the tool's output, as the tool wrote it.
  final String version;
}

final class SystemCheckNotPresent extends SystemCheckResult {
  const SystemCheckNotPresent({required super.tool});
}

final class SystemCheckRunFailed extends SystemCheckResult {
  const SystemCheckRunFailed({required super.tool, required this.exitCode});

  final int exitCode;
}

final class SystemCheckRunTimeout extends SystemCheckResult {
  const SystemCheckRunTimeout({required super.tool});
}

final class SystemCheckNoOutput extends SystemCheckResult {
  const SystemCheckNoOutput({required super.tool});
}
