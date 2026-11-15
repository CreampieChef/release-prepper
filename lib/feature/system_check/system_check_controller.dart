import 'dart:io';

import '../../service/logging/tool_log.dart';
import '../../service/logging/tool_log_entry.dart';
import '../../service/native_tools/ffprobe.dart';
import '../../service/native_tools/ffmpeg.dart';
import '../../service/native_tools/mkbrr.dart';
import '../../service/native_tools/mtn.dart';
import '../../service/native_tools/tool_locator.dart';
import '../../service/native_tools/tool_runner.dart';
import '../../service/native_tools/uptooda.dart';
import '../settings/secret_store.dart';

/// The System Check feature: the tools the app calls, checked at the same time
/// and reported one by one as each call comes back, plus the credential store
/// check the Linux page draws as its own section.
///
/// The controller owns the list of required tools and the calls; the widget
/// shows the results and maps them to localized text (rule 13). It is
/// app-level, so it is a provider entry, and the app data directory is given
/// to it as a function for the same reason `SettingsStore` has one:
/// `ToolRunner` needs a directory to write the tool log to, and outside a
/// release there is no release directory, so the app data directory is what the
/// check's calls are logged under — the store check writes its entry to the same
/// directory, because a check that is not a tool call has no release either.
class SystemCheckController {
  SystemCheckController({
    required this.ffmpeg,
    required this.ffprobe,
    required this.mtn,
    required this.uptooda,
    required this.mkbrr,
    required this.appDirectory,
    required this.secretStore,
    required this.log,
    required this.isLinux,
  });

  final Ffmpeg ffmpeg;
  final Ffprobe ffprobe;
  final Mtn mtn;
  final Uptooda uptooda;
  final Mkbrr mkbrr;

  /// The credential store the check writes to. It is the interface rather than the
  /// plugin for the reason `SecretStore` is an interface: the plugin is a method
  /// channel and cannot be exercised in a test.
  final SecretStore secretStore;

  /// The app's log, for the entry the store check writes. What the check failed
  /// with is not shown on the page, which says only the state, so the log is the
  /// place a user can read the reason back.
  final ToolLog log;

  /// The app data directory, resolved by the function the composition root
  /// gives rather than by the controller (rule 4).
  final Future<Directory> Function() appDirectory;

  /// Whether the app runs on Linux, which is the platform the store check is
  /// asked on and the section is drawn on. It is a parameter rather than read
  /// from `Platform` here for the same reason `ToolLocator.isWindows` is: a rule
  /// that reads the platform can only be tested on the platform it reads.
  final bool isLinux;

  /// The key the store check writes under and deletes again. It is not a settings
  /// field: nothing on the settings page reads it, so it is the key the check
  /// writes for itself and removes with the same call that wrote it, the same
  /// kind of key as `pornolabCookieKey`, which is also not a field.
  static const secretStoreProbeKey = 'systemCheckProbe';

  /// What the check writes under that key. Any value would do, because the point
  /// of the call is that the store answers it.
  static const secretStoreProbeValue = 'check';

  /// The name the log entry records the store check under. It is not a tool, but
  /// the log is the app's log and names what the app called, as its request
  /// entries name the site (`ai/uploading_draft.md` §8).
  static const secretStoreLogName = 'secret-store';

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

  /// The credential store check (`ai/doc.md` §2): write a value under the app's
  /// own key and delete it again. Writing is the only way to know the store can
  /// be reached, because there is no way to ask it whether it is running — every
  /// call to a store that is not there answers with an exception.
  ///
  /// The key is removed by the same check that wrote it, so the check leaves the
  /// store as it found it. A value the check could not remove is left there, and
  /// the settings page does not show it, because it is not one of its fields.
  ///
  /// The outcome is written to the log whatever it was, so the log reads as a
  /// record of what the app checked rather than only of what failed. The page
  /// shows only the state: what the store answered with is an exception's text,
  /// and a user needs it to find out why the store was not reached.
  Future<SecretStoreCheck> checkSecretStore() async {
    final directory = (await appDirectory()).path;

    try {
      await secretStore.write(secretStoreProbeKey, secretStoreProbeValue);
      await secretStore.delete(secretStoreProbeKey);

      await log.write(
        directory,
        ToolLogCheck(
          date: DateTime.now().toUtc(),
          tool: secretStoreLogName,
          input: [secretStoreProbeKey],
          passed: true,
        ),
      );

      return const SecretStoreWorks();
    } catch (error) {
      await log.write(
        directory,
        ToolLogCheck(
          date: DateTime.now().toUtc(),
          tool: secretStoreLogName,
          input: [secretStoreProbeKey],
          passed: false,
          error: error.toString(),
        ),
      );

      return const SecretStoreNotAvailable();
    }
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

/// What the credential store check ended with. It is not part of the tool
/// results, because this is not a tool run: there is no version line, no exit
/// code and no timeout here, only whether the store answered the call.
sealed class SecretStoreCheck {
  const SecretStoreCheck();
}

/// The store answered, and the value the check wrote was removed again.
final class SecretStoreWorks extends SecretStoreCheck {
  const SecretStoreWorks();
}

/// The store could not be reached, or it answered the write and not the delete.
final class SecretStoreNotAvailable extends SecretStoreCheck {
  const SecretStoreNotAvailable();
}
