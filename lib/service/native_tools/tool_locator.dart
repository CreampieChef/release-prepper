import 'dart:io';

import 'package:path/path.dart' as p;

/// A native tool the app calls. [name] is the tool's name without an extension,
/// as the user names it on either platform; the resolver adds the extension
/// Windows expects (`ToolLocator._names`). [bundleDirectory] is the directory
/// the app looks in first, relative to the directory it runs from: the one the
/// install step puts the tool in when the app ships it, or the one a user puts
/// a tool in when the app does not (`ai/bundled_native_tools.md`).
///
/// The three cases are: no bundle directory, so the tool is the user's and is
/// read from PATH; a bundle directory with [pathFallback] false, so the app's
/// copy is the only one, because a system install is not an acceptable
/// substitute; and a bundle directory with [pathFallback] true, so the app
/// prefers its own copy and uses the user's when it has none.
class NativeTool {
  const NativeTool({
    required this.name,
    this.bundleDirectory,
    this.pathFallback = false,
  });

  final String name;

  /// The directory the app looks in first, or null when the app never looks in
  /// the bundle.
  final String? bundleDirectory;

  /// Whether PATH is still searched when the bundle does not have the tool.
  /// Only a tool with a bundle directory can be asked this.
  final bool pathFallback;
}

sealed class ToolLocation {
  const ToolLocation();
}

final class ToolFound extends ToolLocation {
  const ToolFound({required this.path, required this.source});

  final String path;
  final ToolSource source;
}

enum ToolSource {
  /// Found in the app bundle.
  bundled,

  /// Found on PATH.
  system,
}

final class ToolNotFound extends ToolLocation {
  const ToolNotFound();
}

/// Decides where a tool comes from: the app bundle first, then PATH.
///
/// A tool with a bundle directory and no `pathFallback` is never read from
/// PATH. A system install of uptooda has the unmodified upload scripts, so it
/// is not an acceptable substitute; that is the reason the app ships it. A tool
/// with `pathFallback` is preferred from the bundle and read from PATH when
/// the bundle has nothing there, because the app can use either copy — ffmpeg
/// is the same tool whichever one it runs.
///
/// A file in the bundle is accepted on the same terms as one on PATH: the
/// execute bits. A copy without them is not something `Process.start` can run,
/// so it is not found, and a tool with a fallback uses the system copy instead.
///
/// PATH is searched in Dart rather than with `which`, so `ToolRunner` stays the
/// only code that runs an external process.
///
/// The platform is a parameter for the same reason PATH is: it decides how PATH
/// is split and whether an executable is named with its extension, and a rule
/// that reads `Platform.isWindows` can only be tested on the platform it reads.
class ToolLocator {
  ToolLocator({
    required this.bundleDirectory,
    required this.pathVariable,
    required this.isWindows,
  });

  /// The directory the app runs from. A tool the app ships is installed in a
  /// directory of its own next to it, with the tool's data beside it; a tool
  /// the app takes from either place is in a directory the user puts there
  /// (`ai/bundled_native_tools.md`).
  final Directory bundleDirectory;

  /// The PATH the app was started with. It is a parameter rather than read from
  /// the environment here, so the rule can be tested.
  final String pathVariable;

  /// Whether the app runs on Windows.
  final bool isWindows;

  ToolLocation resolve(NativeTool tool) {
    final directory = tool.bundleDirectory;

    if (directory != null) {
      for (final name in _names(tool.name)) {
        final bundled = File(p.join(bundleDirectory.path, directory, name));

        if (bundled.existsSync() && _isExecutable(bundled.statSync())) {
          return ToolFound(path: bundled.path, source: ToolSource.bundled);
        }
      }

      if (!tool.pathFallback) {
        return const ToolNotFound();
      }
    }

    return _fromPath(tool.name) ?? const ToolNotFound();
  }

  /// The names a tool can be found under. On Windows an executable is named with
  /// its extension, so that is the name tried first: a file there without one is
  /// not something `Process.start` can run, even when it is on PATH. The bare
  /// name is still tried, because a tool installed without an extension is the
  /// same file as on the other platforms.
  List<String> _names(String name) => isWindows ? ['$name.exe', name] : [name];

  ToolLocation? _fromPath(String name) {
    for (final entry in pathVariable.split(isWindows ? ';' : ':')) {
      if (entry.isEmpty) {
        continue;
      }

      for (final candidateName in _names(name)) {
        final candidate = File(p.join(entry, candidateName));

        if (candidate.existsSync() && _isExecutable(candidate.statSync())) {
          return ToolFound(path: candidate.path, source: ToolSource.system);
        }
      }
    }

    return null;
  }

  bool _isExecutable(FileStat stat) {
    // The permission bits are what decides on Linux: the owner, group and other
    // execute bits. Windows does not use them, so a file there is taken as an
    // executable, on PATH or in the bundle.
    return stat.type == FileSystemEntityType.file &&
        (isWindows || (stat.mode & (0x40 | 0x8 | 0x1)) != 0);
  }
}
