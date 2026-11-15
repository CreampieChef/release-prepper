import 'dart:io';

import 'package:path/path.dart' as p;

import 'tool_log.dart';

/// Whether the app was started with `--unsafe-verbose-tracker-logging`, which
/// is what makes the plain text copy of the tracker's calls be written at all
/// (`ai/uploading_draft.md` §8).
///
/// This is the third top-level variable in the app, and the third exception to
/// rule 10, for the reason rule 10 gives for the other two: it is read once by
/// `main()` before the app is built and nothing writes it afterwards, and no
/// part of the app is the place that decides whether a service writes.
bool verboseTrackerLogging = false;

/// What the app asked the site for and what the site answered, written as plain
/// text so a run can be read by hand. It writes only when the app was started
/// with `--unsafe-verbose-tracker-logging`: a normal run writes nothing, so the
/// file is there only when a run is being read.
///
/// This is not the app's log (`ai/uploading_draft.md` §8). The flag is called
/// unsafe for the reason those rules are the way they are: this writes the
/// cookie as its value rather than as the marker, and a page in full rather
/// than the value the app read out of it, into the release folder. Those two
/// are what a problem with an encoding, or with a field the site wants, is read
/// back from, and the app's log keeps them as markers for a reason that applies
/// to a run a user makes, not to a run someone is reading.
///
/// It is a service of its own so that its call sites stay with the client that
/// makes the calls, and so that whether anything is written is decided in one
/// place rather than at each of them. The entries are still written one per
/// request and one per response, in the order the calls were made, and the
/// folder is the one the app's log uses.
///
/// The shape of a block is this service's, so a call site says only which side
/// of the exchange it is and what the call was: four lines, then a blank line,
/// then the headers as `name: value` and what was sent or answered. The first
/// and the fourth lines are the marker 80 times; the second and the third are
/// the marker 10 times, a space, and then the date or the line the block is
/// about. The marker is the direction: `<` is what the app sent, `>` is what
/// the site answered, and `#` is a request that got no answer, which is neither
/// of the other two.
class DebugTextLog {
  static const fileName = 'debug_log.txt';

  static const ruleWidth = 80;
  static const gutterWidth = 10;

  static const sentMarker = '<';
  static const receivedMarker = '>';
  static const failedMarker = '#';

  Future<void> _writes = Future<void>.value();

  /// [request] is the method and the address, [headers] the headers the app
  /// sets itself, [body] what was sent with the request.
  Future<void> sent(
    String releaseDirectory,
    String request,
    List<String> headers, [
    String body = '',
  ]) => _block(releaseDirectory, sentMarker, request, headers, body);

  /// [answer] is the status, then the method and the address: the status first,
  /// because an answer is read by its status. [headers] are the ones the answer
  /// carried, [body] what it served.
  Future<void> received(
    String releaseDirectory,
    String answer,
    List<String> headers, [
    String body = '',
  ]) => _block(releaseDirectory, receivedMarker, answer, headers, body);

  /// A request that got no answer, so it is not a received block: [request] is
  /// the method and the address, [reason] what went wrong.
  Future<void> failed(String releaseDirectory, String request, String reason) =>
      _block(releaseDirectory, failedMarker, request, const [], reason);

  /// One block, in the shape the class docstring gives. Writing is serialised,
  /// as it is for the app's log, because two sections can ask at the same time.
  /// The client calls this for every request, and a run without the flag leaves
  /// the block built here: the call is what the flag decides, not the call
  /// site.
  Future<void> _block(
    String releaseDirectory,
    String marker,
    String line,
    List<String> headers,
    String body,
  ) {
    if (!verboseTrackerLogging) {
      return Future<void>.value();
    }

    final rule = marker * ruleWidth;
    final gutter = marker * gutterWidth;

    final text = [
      rule,
      '$gutter ${_now()}',
      '$gutter $line',
      rule,
      '',
      ...headers,
      if (body.isNotEmpty) body,
    ].join('\n');

    final next = _writes.then((_) => _append(releaseDirectory, text));

    // A failed write must not stop the blocks after it.
    _writes = next.catchError((_) {});

    return next;
  }

  String _now() => DateTime.now().toUtc().toIso8601String();

  Future<void> _append(String releaseDirectory, String text) async {
    final directory = Directory(
      p.join(releaseDirectory, ToolLog.directoryName),
    );

    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    await File(p.join(directory.path, fileName))
        .writeAsString('$text\n', mode: FileMode.append, flush: true);
  }
}
