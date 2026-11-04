/// One entry of the tool log (`ai/upload_images.md`): one output the tool
/// wrote, or the end of a call. The input is repeated on every entry so an
/// entry stands on its own when several calls are written at the same time.
sealed class ToolLogEntry {
  const ToolLogEntry({
    required this.date,
    required this.tool,
    required this.input,
  });

  /// When the line was received, in UTC.
  final DateTime date;

  /// The tool name, as the app declared it.
  final String tool;

  /// The arguments of the call that produced this entry. For a request to a
  /// site these are the cookie and the form fields, as name and value pairs.
  final List<String> input;

  /// A credential is never recorded as its value (`ai/uploading_draft.md` §8).
  /// The arguments of a call are recorded so a problem can be read back, and a
  /// credential in a log file is a copy of something the user keeps private.
  static const redacted = 'redacted';

  Map<String, Object?> toJson();
}

/// One line the tool wrote to one of its streams.
final class ToolLogLine extends ToolLogEntry {
  const ToolLogLine({
    required super.date,
    required super.tool,
    required super.input,
    required this.stream,
    required this.line,
  });

  static const stdoutStream = 'stdout';
  static const stderrStream = 'stderr';

  /// Which stream the line came from.
  final String stream;

  /// The line as the tool wrote it. Progress lines use carriage returns as well
  /// as newlines; entries are split on newlines and the carriage returns are
  /// kept inside the recorded text.
  final String line;

  @override
  Map<String, Object?> toJson() => {
    'date': date.toIso8601String(),
    'tool': tool,
    'input': input,
    'stream': stream,
    'line': line,
  };
}

/// The end of a call. An exit code is not an output line, so it is its own
/// entry.
final class ToolLogExit extends ToolLogEntry {
  const ToolLogExit({
    required super.date,
    required super.tool,
    required super.input,
    required this.exitCode,
    required this.timedOut,
  });

  static const exitStream = 'exit';

  /// The code the process exited with, or null when the call was stopped by the
  /// timeout instead of finishing.
  final int? exitCode;

  /// Whether the call was stopped for running longer than the window it was
  /// given.
  final bool timedOut;

  @override
  Map<String, Object?> toJson() => {
    'date': date.toIso8601String(),
    'tool': tool,
    'input': input,
    'stream': exitStream,
    'exitCode': exitCode,
    'timedOut': timedOut,
  };
}

/// One request the app made to a site (`ai/uploading_draft.md` §8). The log is
/// the app's log, so the `tool` field of these entries names the site rather
/// than a tool the app ran — the same place the app declares what it called.
///
/// `input` is the request as the app made it. The cookie is the marker, never
/// the string.
final class ToolLogRequest extends ToolLogEntry {
  const ToolLogRequest({
    required super.date,
    required super.tool,
    required super.input,
    required this.method,
    required this.url,
  });

  static const requestStream = 'request';

  final String method;

  final String url;

  @override
  Map<String, Object?> toJson() => {
    'date': date.toIso8601String(),
    'tool': tool,
    'input': input,
    'stream': requestStream,
    'method': method,
    'url': url,
  };
}

/// The answer to one of those requests.
///
/// A page is not recorded in full: the entry records the status, the headers, and
/// what the app read from it — the token, or the JSON body as it came. A page is
/// not a result the log is for, and its header carries the account name the cookie
/// belongs to.
final class ToolLogResponse extends ToolLogEntry {
  const ToolLogResponse({
    required super.date,
    required super.tool,
    required super.input,
    required this.status,
    required this.read,
    required this.headers,
  });

  static const responseStream = 'response';

  final int status;

  /// What the app read out of the response: the token it came for, or the body
  /// as it came when the body is what the app reads.
  final String read;

  /// The response headers, as the rule that says which of them belong in a log
  /// file left them (`PornolabClient.logHeaders`). A header with more than one
  /// value is recorded with the values the response gave, not as one joined line.
  final Map<String, List<String>> headers;

  @override
  Map<String, Object?> toJson() => {
    'date': date.toIso8601String(),
    'tool': tool,
    'input': input,
    'stream': responseStream,
    'status': status,
    'read': read,
    'headers': headers,
  };
}

/// A request that got no answer. It closes a call the way the exit entry closes a
/// tool run: the request entry says what the app asked for, and this says why
/// there is no answer to record — without it a request that failed before a
/// response leaves the log with a request and nothing after it.
final class ToolLogFailure extends ToolLogEntry {
  const ToolLogFailure({
    required super.date,
    required super.tool,
    required super.input,
    required this.error,
  });

  static const failureStream = 'failure';

  /// What the request failed with, as the exception reported it.
  final String error;

  @override
  Map<String, Object?> toJson() => {
    'date': date.toIso8601String(),
    'tool': tool,
    'input': input,
    'stream': failureStream,
    'error': error,
  };
}
