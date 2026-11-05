import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../logging/tool_log.dart';
import '../logging/tool_log_entry.dart';
import 'tool_locator.dart';

/// The app's only seam to external command-line tools: anything that calls a
/// native tool goes through `ToolRunner`, never through `Process` directly.
///
/// It returns typed results and shows no messages — the widget maps them to
/// localized text.
///
/// It reads the streams as the tool writes, so the log records when the tool
/// said something, not only what it said at the end; `Process.run` would buffer
/// everything until the process exits. Writing the log is a side effect the
/// runner did not have before, so both the locator and the log are required
/// constructor parameters. Reading as it writes is also what makes the optional
/// `onOutput` callback possible: a caller that wants to show progress during a
/// long run is given the chunks, and the runner still does not interpret them.
class ToolRunner {
  ToolRunner({required this.locator, required this.log});

  /// The window a call is given when it does not ask for its own: a call that
  /// runs longer than this is stopped and reported as a timeout. The tool has
  /// its own retries, so a call can take a long time
  /// (`ai/bundled_native_tools.md`).
  static const callTimeout = Duration(seconds: 60);

  final ToolLocator locator;
  final ToolLog log;

  /// `environment` is what a call adds to the environment the child inherits.
  /// Dart merges the map with the environment of the app process, so a caller
  /// passes only the entries it adds and nothing else.
  ///
  /// A credential goes here rather than in `arguments` for two reasons
  /// (`ai/bundled_native_tools.md`): the arguments of a running process are
  /// readable by every user on the machine, and they are recorded on every log
  /// entry, so a key passed as an argument is written to the log once per
  /// output line and stays there. The environment is not part of the recorded
  /// input, so the log holds no copy of it.
  /// [onOutput] is called with each chunk as the tool writes it, before the
  /// process ends. It is what lets a caller show progress while a call works:
  /// the result is only known at the end, so without it nothing can be shown
  /// during a long run. A plain callback the caller passes, not a listener
  /// (rule 3). Without it the call behaves exactly as it did before.
  ///
  /// [timeout] is how long the call may run before it is stopped. It defaults to
  /// `callTimeout`, and a caller that knows its call can legitimately run longer
  /// than that passes its own: hashing a whole release is not the same kind of
  /// long run as an upload with retries, so `Mkbrr.create()` asks for 60 minutes
  /// (`ai/torrents.md`). The window is the whole call, from the process being
  /// started to it exiting, not a period of silence — a call that keeps writing
  /// output is still stopped when it runs past its window.
  Future<ToolRunResult> run(
    NativeTool tool,
    List<String> arguments, {
    required String releaseDirectory,
    Map<String, String> environment = const {},
    void Function(String chunk)? onOutput,
    Duration timeout = callTimeout,
  }) async {
    final location = locator.resolve(tool);

    if (location is! ToolFound) {
      return const ToolRunNotAvailable();
    }

    final input = [location.path, ...arguments];

    final Process process;

    try {
      process = await Process.start(
        location.path,
        arguments,
        environment: environment,
      );
    } on ProcessException {
      // The executable is missing, is not executable, or the OS refused to
      // start it. This is what the "check installed required tools" item needs.
      return const ToolRunNotAvailable();
    }

    final stdout = StringBuffer();
    final stderr = StringBuffer();

    final reading = Future.wait([
      _read(
        process.stdout,
        ToolLogLine.stdoutStream,
        tool,
        input,
        releaseDirectory,
        stdout,
        onOutput,
      ),
      _read(
        process.stderr,
        ToolLogLine.stderrStream,
        tool,
        input,
        releaseDirectory,
        stderr,
        onOutput,
      ),
    ]);

    var timedOut = false;
    var exitCode = 0;

    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
    }

    // After the process is gone the streams close, so the readers finish and
    // the last partial line is recorded.
    await reading;

    await log.write(
      releaseDirectory,
      ToolLogExit(
        date: DateTime.now().toUtc(),
        tool: tool.name,
        input: input,
        exitCode: timedOut ? null : exitCode,
        timedOut: timedOut,
      ),
    );

    if (timedOut) {
      return ToolRunTimeout(
        stdout: stdout.toString(),
        stderr: stderr.toString(),
      );
    }

    if (exitCode == 0) {
      return ToolRunSuccess(
        stdout: stdout.toString(),
        stderr: stderr.toString(),
      );
    }

    return ToolRunFailure(
      exitCode: exitCode,
      stdout: stdout.toString(),
      stderr: stderr.toString(),
    );
  }

  /// One stream, read as it is written. Lines are split on newlines and the
  /// carriage returns a tool uses to redraw a progress line are kept inside the
  /// recorded text.
  Future<void> _read(
    Stream<List<int>> stream,
    String streamName,
    NativeTool tool,
    List<String> input,
    String releaseDirectory,
    StringBuffer sink,
    void Function(String chunk)? onOutput,
  ) async {
    // The part of a line that has not ended yet. A line can arrive in two
    // reads.
    final pending = StringBuffer();

    await for (final chunk in utf8.decoder.bind(stream)) {
      // The result the caller gets is the output exactly as it came, so the
      // whole chunk is kept; `pending` is only for splitting it into lines.
      sink.write(chunk);
      pending.write(chunk);

      // The caller that asked for it sees the chunk as it arrives, in the same
      // form the tool wrote it, so it can read a progress line before the run
      // ends.
      onOutput?.call(chunk);

      var text = pending.toString();
      var end = text.indexOf('\n');

      while (end >= 0) {
        await log.write(
          releaseDirectory,
          ToolLogLine(
            date: DateTime.now().toUtc(),
            tool: tool.name,
            input: input,
            stream: streamName,
            line: text.substring(0, end),
          ),
        );

        text = text.substring(end + 1);
        end = text.indexOf('\n');
      }

      pending.clear();
      pending.write(text);
    }

    final rest = pending.toString();

    if (rest.isNotEmpty) {
      await log.write(
        releaseDirectory,
        ToolLogLine(
          date: DateTime.now().toUtc(),
          tool: tool.name,
          input: input,
          stream: streamName,
          line: rest,
        ),
      );
    }
  }
}

sealed class ToolRunResult {
  const ToolRunResult();
}

/// Ran and exited 0.
final class ToolRunSuccess extends ToolRunResult {
  const ToolRunSuccess({required this.stdout, required this.stderr});

  final String stdout;
  final String stderr;
}

/// Ran and exited with a non-zero code.
final class ToolRunFailure extends ToolRunResult {
  const ToolRunFailure({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Could not be started: not installed, not executable, or refused by the OS.
final class ToolRunNotAvailable extends ToolRunResult {
  const ToolRunNotAvailable();
}

/// Ran for longer than the window the call was given and was stopped.
final class ToolRunTimeout extends ToolRunResult {
  const ToolRunTimeout({required this.stdout, required this.stderr});

  final String stdout;
  final String stderr;
}
