import 'package:release_prepper/service/logging/tool_log.dart';
import 'package:release_prepper/service/logging/tool_log_entry.dart';

/// The log for tests. `ToolLog` writes to the filesystem, and a widget test runs
/// in a fake async where a real file write never completes, so a test that shows
/// what a check reported cannot be given the real one. This keeps the entries it
/// is given instead; a test that needs them as they would be written reads them
/// through `toJson()`, the way the log file holds them.
class FakeToolLog extends ToolLog {
  final entries = <ToolLogEntry>[];

  @override
  Future<void> write(String releaseDirectory, ToolLogEntry entry) async {
    entries.add(entry);
  }
}
