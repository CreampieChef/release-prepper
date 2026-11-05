import 'tool_locator.dart';
import 'tool_runner.dart';

/// mkbrr. Only the commands the app uses are listed here.
///
/// The app ships this tool, so it is resolved from the bundle only
/// (`ai/bundled_native_tools.md`).
class Mkbrr {
  Mkbrr({required this.runner});

  static const tool = NativeTool(name: 'mkbrr', bundleDirectory: 'mkbrr');

  final ToolRunner runner;

  /// The window a create call is given. Hashing a release is not an upload with
  /// retries: it is one call that reads every file, and a large release takes
  /// longer than the runner's default, so this is the wrapper's own. The version
  /// call is not given one and uses the default.
  static const createTimeout = Duration(minutes: 60);

  /// The version line the tool prints, used by the System Check tab.
  /// The bare command prints its banner and its usage without a version, so the
  /// check uses the `version` subcommand: its first line is the version and it
  /// exits 0, which is what the existing rule needs.
  Future<ToolRunResult> version({required String releaseDirectory}) =>
      runner.run(tool, const ['version'], releaseDirectory: releaseDirectory);

  /// Create a torrent from [sourcePath] and write it to [outputPath].
  ///
  /// `--private=true` is what the app always asks for. `--output` is given
  /// explicitly rather than left to the default, because the default is
  /// `<source basename>.torrent` written in the working directory, and the runner
  /// does not set one.
  ///
  /// [onProgress] is called with what each progress segment says. The tool writes
  /// progress as segments separated by carriage returns, with ANSI colour codes
  /// even when its output is not a terminal, so the reader takes one segment at a
  /// time and reads the fields in it; a segment with no percentage is not
  /// progress. A run that finishes in a few milliseconds reports only the final
  /// 100, so a caller cannot assume the numbers arrive in steps.
  ///
  /// The tool does not say which file it is on: it hashes pieces from every file
  /// at once, and the names it prints are the list before the first segment. So
  /// there is no current file to read here.
  Future<MkbrrResult> create({
    required String releaseDirectory,
    required String sourcePath,
    required String outputPath,
    required void Function(MkbrrProgress progress) onProgress,
  }) async {
    // A segment can arrive in two reads, so the part that has not ended yet is
    // kept between them, the same way the runner keeps a partial line.
    final pending = StringBuffer();

    void read(String chunk) {
      pending.write(chunk);

      var text = pending.toString();
      var end = text.indexOf('\r');

      while (end >= 0) {
        final progress = _progress(text.substring(0, end));
        if (progress != null) onProgress(progress);

        text = text.substring(end + 1);
        end = text.indexOf('\r');
      }

      pending.clear();
      pending.write(text);
    }

    final result = await runner.run(
      tool,
      ['create', sourcePath, '--private=true', '--output', outputPath],
      releaseDirectory: releaseDirectory,
      onOutput: read,
      timeout: createTimeout,
    );

    // The last segment has no carriage return after it, so it is read after the
    // process has gone.
    final progress = _progress(pending.toString());
    if (progress != null) onProgress(progress);

    return switch (result) {
      ToolRunNotAvailable() => const MkbrrNotPresent(),
      ToolRunFailure(exitCode: final exitCode) => MkbrrRunFailed(
        exitCode: exitCode,
      ),
      ToolRunTimeout() => const MkbrrRunTimeout(),
      ToolRunSuccess() => MkbrrCreated(path: outputPath),
    };
  }

  /// What one segment says, or null when the segment is not a progress line. The
  /// escape codes are not removed: the fields are read from the text as the tool
  /// wrote them, and only a progress segment has a percentage in it.
  ///
  /// The segment is the redrawn line: the description, then the percentage, then
  /// the bar, then the elapsed and remaining pair. The rate is in a bracket
  /// before the percentage and only appears once the tool has one; the pair is
  /// the first bracket with a colon after it. A segment that is only the spaces
  /// the tool writes to clear the line has neither.
  static MkbrrProgress? _progress(String segment) {
    final percent = RegExp(r'(\d+)%').firstMatch(segment);

    if (percent == null) {
      return null;
    }

    final value = int.tryParse(percent.group(1)!);

    if (value == null) {
      return null;
    }

    return MkbrrProgress(
      percent: value,
      speed: _first(_speedPattern, segment.substring(0, percent.start)),
      eta: _pair(segment.substring(percent.end)),
    );
  }

  /// A bracket whose content has a slash: the rate. A colour code is an opening
  /// bracket that nothing closes, so the content cannot cross one — that is what
  /// keeps the pattern from reading one as a rate.
  static final _speedPattern = RegExp(r'\[([^\[\]]+/[^\[\]]*)\]');

  /// The elapsed and remaining pair, which is the first bracket with a colon.
  static final _pairPattern = RegExp(r'\[([^\[\]]+):([^\[\]]+)\]');

  static String? _first(RegExp pattern, String text) =>
      pattern.firstMatch(text)?.group(1);

  /// The remaining time, which is the second half of the pair. The first half is
  /// what the run has already taken, and the app does not show it.
  static String? _pair(String text) => _pairPattern.firstMatch(text)?.group(2);
}

/// One progress segment, as the tool wrote it. A field is null when the segment
/// did not have it, so a caller cannot assume all three arrive together.
final class MkbrrProgress {
  const MkbrrProgress({required this.percent, this.speed, this.eta});

  final int percent;

  /// The rate, in the tool's own units (`3.7 GiB/s`), or null before it has one.
  final String? speed;

  /// The time the tool thinks is left, as it wrote it (`0s`, `2m 3s`), or null
  /// when the segment had no pair.
  final String? eta;
}

sealed class MkbrrResult {
  const MkbrrResult();
}

/// Ran and wrote the file. [path] is where the app asked for it to be written.
final class MkbrrCreated extends MkbrrResult {
  const MkbrrCreated({required this.path});

  final String path;
}

/// Could not be started: not in the bundle.
final class MkbrrNotPresent extends MkbrrResult {
  const MkbrrNotPresent();
}

/// Ran and exited with a non-zero code.
final class MkbrrRunFailed extends MkbrrResult {
  const MkbrrRunFailed({required this.exitCode});

  final int exitCode;
}

/// Ran for longer than the runner's timeout and was stopped.
final class MkbrrRunTimeout extends MkbrrResult {
  const MkbrrRunTimeout();
}
