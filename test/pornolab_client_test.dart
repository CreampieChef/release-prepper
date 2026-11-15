import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/app/app_info.dart';
import 'package:release_prepper/service/logging/tool_log.dart';
import 'package:release_prepper/service/logging/debug_text_log.dart';
import 'package:release_prepper/service/logging/tool_log_entry.dart';
import 'package:release_prepper/service/network/pornolab_client.dart';
import 'package:release_prepper/service/torrent/torrent_path.dart';

// `HttpClient` has only a factory constructor, so it cannot be extended; the
// fake implements the interface and forwards what the test does not call. It
// answers with an error instead of a connection, so the test does not reach the
// network.
class _FailingHttpClient implements HttpClient {
  _FailingHttpClient(this.error);

  final Object error;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => throw error;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// An answer the test gives instead of a connection. Only what the client reads
// is here — the status, the headers, the body as bytes — and `noSuchMethod`
// answers the members the code does not touch.
class _FakeResponse implements HttpClientResponse {
  // [bytes] is what the answer serves when it is a file rather than a page: the
  // bytes must reach the client as they are, so they cannot be written as text.
  _FakeResponse(this.statusCode, this.headers, {this.body = '', this.bytes});

  @override
  final int statusCode;

  @override
  final HttpHeaders headers;

  final String body;

  final List<int>? bytes;

  @override
  Future<void> forEach(void Function(List<int>) action) async =>
      action(bytes ?? utf8.encode(body));

  @override
  Future<E> drain<E>([E? error]) async => error as E;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// The headers as a plain map, so a test can read what the request was given and
// what the answer carried.
class _FakeHeaders implements HttpHeaders {
  final _values = <String, List<String>>{};

  ContentType? _contentType;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values[name.toLowerCase()] = [value.toString()];

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      (_values[name.toLowerCase()] ??= []).add(value.toString());

  @override
  String? value(String name) => _values[name.toLowerCase()]?.first;

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(Object? value) =>
      _contentType = value is ContentType ? value : null;

  // The length the request declares is what a test reads, because the body is
  // what the length is the length of.
  @override
  int contentLength = 0;

  @override
  void forEach(void Function(String, List<String>) action) =>
      _values.forEach(action);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.response);

  final HttpClientResponse response;

  final body = <String>[];

  @override
  bool followRedirects = true;

  @override
  HttpHeaders headers = _FakeHeaders();

  @override
  void write(Object? data) => body.add(data.toString());

  // A multipart body is bytes, so the file part is recorded as bytes rather
  // than as text: the test that says a value is the codepage's bytes cannot
  // read them back through a String.
  @override
  void add(List<int> data) => bytes.addAll(data);

  final bytes = <int>[];

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// The answers in the order the calls are made, and the calls themselves, so a
// test can see what the client sent and whether it read the page again.
class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.responses);

  final List<HttpClientResponse> responses;

  final calls = <Uri>[];

  final requests = <HttpClientRequest>[];

  int _next = 0;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    calls.add(url);

    final request = _FakeRequest(responses[_next++]);
    requests.add(request);

    return request;
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    calls.add(url);

    final request = _FakeRequest(responses[_next++]);
    requests.add(request);

    return request;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // The part of the posting page the parser reads. The page this feature was
  // worked from is not in the repo because it carries an account name, so this
  // is the trimmed shape of it: the page builds its form with JavaScript, so the
  // token is in the assignment rather than in an input the form would have.
  const page = """
<script>
var form_token = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
</script>""";

  const token = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';

  // The answer a post gets: the block with its two links, trimmed the way the
  // example page is. The ids are the ones `ai/pornolab_upload.md` uses for its
  // examples, not the ones the recording has.
  const block = """
<table class="forumline message">
<tr><td class="row1">Информация</td></tr>
<tr><td><a href="dl.php?t=3000111">download</a>
<a href="viewtopic.php?t=3000111">topic</a></td></tr>
</table>""";

  // The breadcrumb a forum page writes, as a real page was seen to write it
  // (`ai/uploading_draft.md` §4): the table cell with the `nav` class, which
  // the page writes twice and the fixture is the first. The entity the name is
  // written with is kept, because the name is read back from it. The pagination
  // is the other element with that class and its links name the same forum as
  // page numbers, so the fixture carries it: the rule reads the cell, not it.
  const nav = """
<table>
<tr>
<td class="nav nav-top" width="100%">
&nbsp;<a href="./index.php">Список форумов</a>
<em>&raquo;</em> <a href="viewforum.php?f=1857">SiteRip&#039;s 2022 (HD Video)</a>
</td>
</tr>
</table>
<div class="nav" id="pagination">
<p><a class="pg" href="viewforum.php?f=1857&amp;start=50">2</a></p>
</div>""";

  // The login form as the site writes it when it asks for a code, in the order
  // the form declares its fields. The page this was worked from is not in the
  // repo because it carries an account name, so this is the trimmed shape of it
  // (`ai/pornolab_login.md` §6).
  const captchaPage = """
<form action="login.php" method="post">
<input type="hidden" name="redirect" value="index.php" />
<input type="text" name="login_username" value="the-user" />
<input type="password" name="login_password" value="the-password" />
<input type="hidden" name="cap_sid" value="BsbMQsHd2NoihtWqHS0V" />
<input type="text" name="cap_code_f8d8fa25d65dc2f22824bce923bb5c3a" value="" />
<img src="//static.pornolab.net/captcha/0/25/82d2598a6af21cb51960e56f92e104e4.jpg?671714846" />
<input type="submit" name="login" value="Вход" />
</form>""";

  // The entries the client wrote, in the order it wrote them. Only the app's
  // own log files, because the client writes the plain text copy into the same
  // folder too.
  List<File> logFiles(Directory directory) =>
      Directory(p.join(directory.path, ToolLog.directoryName))
          .listSync()
          .whereType<File>()
          .where((file) => p.basename(file.path).startsWith(ToolLog.filePrefix))
          .toList();

  List<Map<String, dynamic>> logEntries(Directory directory) =>
      logFiles(directory)
          .expand((file) => File(file.path).readAsLinesSync())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();

  test(
    'the token is read from the assignment the page builds its form with',
    () {
      expect(PornolabClient.formTokenFromPage(page), token);
    },
  );

  // A page that writes the token as a hidden input is the other form the same
  // page can have, so both are read.
  test('the token is read from the input when the page writes one', () {
    expect(
      PornolabClient.formTokenFromPage(
        '<input type="hidden" name="form_token" value="$token">',
      ),
      token,
    );
  });

  // A page served to a cookie the site does not accept is the login page, and it
  // has no token. That is what `noToken` means.
  test('a page with no token answers with nothing', () {
    expect(PornolabClient.formTokenFromPage('<h1>Login</h1>'), isNull);
  });

  // A token is 32 hex characters; anything else is not one, so a value that only
  // looks like the shape is not read as a token.
  test('a value that is not a token is not read as one', () {
    for (final html in [
      "var form_token = 'abc';",
      "var form_token = '${'z' * 32}';",
    ]) {
      expect(PornolabClient.formTokenFromPage(html), isNull);
    }
  });

  test(
    'the forum id is read from a full URL on the site with an f parameter',
    () {
      for (final url in [
        'https://pornolab.net/forum/viewforum.php?f=1013',
        'http://pornolab.net/forum/viewforum.php?f=1013',
        'https://pornolab.net/forum/viewforum.php?f=1013&sid=7f3a',
      ]) {
        expect(PornolabClient.forumIdFromUrl(url), 1013);
      }
    },
  );

  // A forum id on its own is not a URL, and a URL that is not the site's or has
  // no `f` is not the shape a request can be built from. `www.` is a different
  // host, so it is not the site's either.
  test('a value that is not a forum URL on the site answers with nothing', () {
    for (final value in [
      '',
      '1013',
      'viewforum.php?f=1013',
      'https://example.com/forum/viewforum.php?f=1013',
      'https://www.pornolab.net/forum/viewforum.php?f=1013',
      'https://pornolab.net/forum/viewtopic.php?t=1',
      'https://pornolab.net/forum/viewforum.php',
      'https://pornolab.net/forum/viewforum.php?f=abc',
      'https://pornolab.net/forum/viewforum.php?f=0',
    ]) {
      expect(PornolabClient.forumIdFromUrl(value), isNull);
    }
  });

  test('the draft id is read from the link the app stored', () {
    expect(
      PornolabClient.draftIdFromUrl(
        'https://pornolab.net/forum/posting.php?mode=newtopic&f=1013&draft=42',
      ),
      42,
    );
  });

  // A file edited by hand can hold a link with no draft, and a run then makes a
  // new one, which is what `draft_id` 0 means.
  test('a link with no draft is a new draft', () {
    for (final value in [
      '',
      'not a url',
      'https://pornolab.net/forum/posting.php?mode=newtopic&f=1013',
    ]) {
      expect(PornolabClient.draftIdFromUrl(value), 0);
    }
  });

  // The link is built from the site rather than from what the user pasted, the
  // same rule as the scene link.
  test('the link is built from the site, not from what was pasted', () {
    expect(
      PornolabClient.draftUrl(forumId: 1013, draftId: 42),
      'https://pornolab.net/forum/posting.php?mode=newtopic&f=1013&draft=42',
    );
  });

  // The base is what the app was started with, through the flag `main()` reads
  // before the app is built (`ai/pornolab_upload.md` §10). One value, because
  // the requests and the links are built from it: a link to the site for a
  // topic the stub made is not the topic the app made.
  test(
    'the base the app was started with is what the links are built from',
    () {
      devTrackerStub = true;
      addTearDown(() => devTrackerStub = false);

      expect(PornolabClient.base(), 'http://localhost:40002');
      expect(
        PornolabClient.topicUrl(topicId: 3000111),
        'http://localhost:40002/forum/viewtopic.php?t=3000111',
      );
      expect(
        PornolabClient.draftUrl(forumId: 1857, draftId: 11818),
        'http://localhost:40002/forum/posting.php?mode=newtopic&f=1857'
        '&draft=11818',
      );
    },
  );

  // A run against the stub is a run made to the stub, in the three calls the
  // post is made of and in the order it makes them. The base is the same value
  // the links are built from, so a run cannot ask one and link to the other.
  test('a run with the flag is made to the stub, not to the site', () async {
    devTrackerStub = true;
    addTearDown(() => devTrackerStub = false);

    final directory = Directory.systemTemp.createTempSync(
      'pornolab_stub_base_test',
    );

    final sent = File(p.join(directory.path, 'the-release.torrent'))
      ..writeAsBytesSync(utf8.encode('d5:filesdee'));

    final http = _FakeHttpClient([
      _FakeResponse(200, _FakeHeaders(), body: page),
      _FakeResponse(200, _FakeHeaders(), body: block),
      _FakeResponse(200, _FakeHeaders(), bytes: [9, 8, 7]),
    ]);

    final client = HttpPornolabClient(
      client: http,
      log: ToolLog(),
      debug: DebugTextLog(),
    );

    await client.postTopic(
      releaseDirectory: directory.path,
      cookie: 'session=abc',
      forumId: 1857,
      draftId: 11818,
      subject: 'the title',
      message: 'the message',
      filePath: sent.path,
    );

    expect(http.calls, [
      Uri.parse(
        'http://localhost:40002/forum/posting.php?mode=newtopic&f=1857',
      ),
      Uri.parse('http://localhost:40002/forum/posting.php'),
      Uri.parse('http://localhost:40002/forum/dl.php?t=3000111'),
    ]);

    directory.deleteSync(recursive: true);
  });

  test('the form body is the fields the call sends, encoded as UTF-8', () {
    expect(
      PornolabClient.formBody(
        token: token,
        forumId: 1013,
        draftId: 0,
        subject: 'Title here',
        message: 'First line\nSecond line',
      ),
      'action=topic_draft&mode=save&form_token=$token'
      '&draft_id=0&forum_id=1013'
      '&subject=Title+here&message=First+line%0ASecond+line',
    );
  });

  // A value with characters that need encoding is the same value on both sides
  // of the request, which is what encoding a message is for.
  test('a value that needs encoding reads back the same', () {
    final body = PornolabClient.formBody(
      token: token,
      forumId: 1,
      draftId: 0,
      subject: "It's 100%",
      message: 'a & b',
    );

    final fields = {
      for (final part in body.split('&'))
        part.split('=').first: Uri.decodeQueryComponent(part.split('=').last),
    };

    expect(fields['action'], 'topic_draft');
    expect(fields['subject'], "It's 100%");
    expect(fields['message'], 'a & b');
  });

  test('a response with draft_id is the draft the app stores', () {
    final result = PornolabClient.parseResponse(
      jsonDecode('{"draft_id": 42}'),
      1013,
    );

    expect(result, isA<DraftSaved>());

    final saved = result as DraftSaved;

    expect(saved.draftId, 42);
    expect(
      saved.draftUrl,
      'https://pornolab.net/forum/posting.php?mode=newtopic&f=1013&draft=42',
    );

    // A run that saved the draft the link points at is not one that made a new
    // one, so the result does not say it did.
    expect(saved.recreated, isFalse);
  });

  // A draft the app stored can be deleted on the site, and the answer for it is
  // `draft_id` 0 with `gone` 1. That is not a draft to link to, so the shape is
  // read as the draft not being there rather than as a saved one
  // (`ai/uploading_draft.md` §6).
  test('a response with gone is the stored draft not being there', () {
    expect(
      PornolabClient.parseResponse(
        jsonDecode('{"draft_id": 0, "gone": 1, "action": "topic_draft"}'),
        1013,
      ),
      const PornolabFailure(PornolabFailureKind.draftGone),
    );
  });

  test('error_code 1 is the form signature the site did not accept', () {
    expect(
      PornolabClient.parseResponse(jsonDecode('{"error_code": 1}'), 1013),
      const PornolabFailure(PornolabFailureKind.tokenRejected),
    );
  });

  // Only the wrong-token code is known, so the rest are one result until they
  // are seen. The text the site sends with a code is not shown, so it does not
  // reach the parser.
  test('another error code is one result', () {
    for (final code in [2, 3, 10]) {
      expect(
        PornolabClient.parseResponse(jsonDecode('{"error_code": $code}'), 1013),
        const PornolabFailure(PornolabFailureKind.siteError),
      );
    }
  });

  test('a response that is not the shape the app reads is not a draft', () {
    for (final decoded in [
      null,
      jsonDecode('[]'),
      jsonDecode('{"error_code": "1"}'),
      jsonDecode('{"draft_id": "42"}'),
      jsonDecode('{}'),
    ]) {
      expect(
        PornolabClient.parseResponse(decoded, 1013),
        const PornolabFailure(PornolabFailureKind.badResponse),
      );
    }
  });

  // A body is read as the charset the response declared, not as what the app
  // assumes. The site's pages are not UTF-8, which is what a run failed with.
  test('a body is read as the charset the response declared', () {
    // "Форум" in windows-1251.
    final bytes = [0xD4, 0xEE, 0xF0, 0xF3, 0xEC];

    expect(PornolabClient.decodeBody(bytes, 'windows-1251'), 'Форум');
    expect(PornolabClient.decodeBody(bytes, 'CP1251'), 'Форум');

    // A UTF-8 response is read as UTF-8, as it was before.
    expect(PornolabClient.decodeBody(utf8.encode('Форум'), 'utf-8'), 'Форум');

    // A charset the app has no codec for, or none declared, is read as latin1,
    // which cannot fail: the values the app reads out of a response are ASCII,
    // so an encoding it does not know is not a reason to lose a run.
    expect(PornolabClient.decodeBody(bytes, 'windows-1252'), 'Ôîðóì');
    expect(PornolabClient.decodeBody(bytes, null), 'Ôîðóì');
  });

  // The case that failed: the page is in the site's charset, so the token is
  // read from the text after the bytes are decoded as the response declared.
  // Reading them as UTF-8 is what threw, and the byte that threw is in the page.
  test(
    'the token is read from a page in the charset the response declared',
    () {
      final bytes = [
        ..."""<script>\nvar form_token = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';\n</script>"""
            .runes,
        0xD4,
        0xEE,
        0xF0,
        0xF3,
        0xEC,
      ];

      expect(() => utf8.decode(bytes), throwsFormatException);

      expect(
        PornolabClient.formTokenFromPage(
          PornolabClient.decodeBody(bytes, 'windows-1251'),
        ),
        token,
      );
    },
  );

  // A credential is never recorded as its value, so the headers that carry one
  // are left out of the log; the rest are what a problem is read back from.
  test('the headers the log records are the ones that carry no credential', () {
    final headers = {
      'content-type': ['text/html; charset=windows-1251'],
      'content-length': ['2048'],
      'location': ['https://pornolab.net/forum/index.php'],
      'set-cookie': ['session=abc'],
      'authorization': ['Bearer abc'],
      'www-authenticate': ['Bearer abc'],
    };

    expect(PornolabClient.logHeaders(headers), {
      'content-type': ['text/html; charset=windows-1251'],
      'content-length': ['2048'],
      'location': ['https://pornolab.net/forum/index.php'],
    });

    // The name is matched without case, so a site that writes `Set-Cookie` as it
    // is commonly spelled is left out too.
    expect(
      PornolabClient.logHeaders({
        'Set-Cookie': ['session=abc'],
      }),
      isEmpty,
    );
  });

  // The header is built from the app's name and version rather than written
  // here, so it says the same thing as `pubspec.yaml` does. A product token is
  // one word, so the space the display name has is not in it.
  test('the header names the app and the version it is', () {
    final ua = PornolabClient.userAgent();

    expect(ua, isNot(contains(' ')));
    expect(ua, '${appName.replaceAll(' ', '')}/$appVersion');
  });

  // A request that failed before an answer is the only case where the log has a
  // request and nothing after it, so the failure entry is what records the
  // reason. The result the feature shows is the same as before; the reason goes
  // to the log.
  test('a request that got no answer is recorded with the reason', () async {
    final directory = Directory.systemTemp.createTempSync(
      'pornolab_client_test',
    );

    final client = HttpPornolabClient(
      client: _FailingHttpClient(
        const SocketException("Failed host lookup: 'pornolab.net'"),
      ),
      log: ToolLog(),
      debug: DebugTextLog(),
    );

    final result = await client.saveDraft(
      releaseDirectory: directory.path,
      cookie: 'the-cookie',
      forumId: 1013,
      draftId: 0,
      subject: 'the title',
      message: 'the message',
    );

    expect(result, isA<PornolabFailure>());
    expect((result as PornolabFailure).kind, PornolabFailureKind.requestFailed);

    final entries = logFiles(directory);

    expect(entries, hasLength(1));

    final lines = File(entries.first.path)
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();

    // The request entry is written before the request is made, so a call that
    // fails is recorded as what the app asked for even when nothing answered.
    expect(lines, hasLength(2));
    expect(lines[0]['stream'], 'request');
    expect(lines[0]['method'], 'GET');

    // The failure entry closes a call the way the exit entry closes a tool run,
    // and carries the same input so it stands on its own.
    expect(lines[1]['stream'], 'failure');
    expect(lines[1]['error'], contains('Failed host lookup'));
    expect(lines[1]['input'], lines[0]['input']);
    expect(lines[0]['input'], contains(ToolLogEntry.redacted));

    directory.deleteSync(recursive: true);
  });

  // What the site answers a cookie it does not accept with, on the page the
  // token is read from: the redirect to the login page, with an empty body and
  // the location pointing back at the page asked for
  // (`ai/uploading_draft.md` §6). The client does not follow it, so this is the
  // result a run gets, and the call ends there.
  test(
    'a wrong cookie is answered with the redirect to the login page',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'pornolab_client_test',
      );

      final headers = _FakeHeaders()
        ..add(
          'location',
          'https://pornolab.net/forum/login.php?redirect=posting.php?mode=newtopic&f=1842',
        );

      final http = _FakeHttpClient([_FakeResponse(302, headers)]);

      final client = HttpPornolabClient(
        client: http,
        log: ToolLog(),
        debug: DebugTextLog(),
      );

      final result = await client.saveDraft(
        releaseDirectory: directory.path,
        cookie: 'the-cookie',
        forumId: 1842,
        draftId: 0,
        subject: '',
        message: 'the message',
      );

      expect(
        result,
        isA<PornolabFailure>().having(
          (f) => f.kind,
          'kind',
          PornolabFailureKind.cookieRefused,
        ),
      );

      // Following the redirect is what would turn it into a page with no token,
      // so there is no second request.
      expect(http.requests, hasLength(1));

      directory.deleteSync(recursive: true);
    },
  );

  // A draft the app stored can be deleted on the site, and the answer for the
  // update says so. `draft_id` 0 is not a draft to link to, so the run asks
  // again with 0 — the call that makes a new draft — and the link it returns is
  // the new one's (`ai/uploading_draft.md` §6).
  test('a run on a draft that is gone makes a new one', () async {
    final directory = Directory.systemTemp.createTempSync(
      'pornolab_client_test',
    );

    final http = _FakeHttpClient([
      _FakeResponse(200, _FakeHeaders(), body: page),
      _FakeResponse(200, _FakeHeaders(), body: '{"draft_id": 0, "gone": 1}'),
      _FakeResponse(200, _FakeHeaders(), body: '{"draft_id": 43}'),
    ]);

    final client = HttpPornolabClient(
      client: http,
      log: ToolLog(),
      debug: DebugTextLog(),
    );

    final result = await client.saveDraft(
      releaseDirectory: directory.path,
      cookie: 'the-cookie',
      forumId: 1013,
      draftId: 42,
      subject: 'the title',
      message: 'the message',
    );

    expect(result, isA<DraftSaved>());

    final saved = result as DraftSaved;

    expect(saved.recreated, isTrue);
    expect(
      saved.draftUrl,
      'https://pornolab.net/forum/posting.php?mode=newtopic&f=1013&draft=43',
    );

    // The first call is the update the stored link asks for, the second the new
    // draft.
    final bodies = http.requests
        .map((request) => (request as _FakeRequest).body.join())
        .toList();

    expect(bodies, hasLength(3));
    expect(bodies[1], contains('draft_id=42'));
    expect(bodies[2], contains('draft_id=0'));

    // The page the token comes from is read once, for both calls.
    expect(
      http.calls.where((url) => url.path.contains('posting.php')),
      hasLength(1),
    );

    directory.deleteSync(recursive: true);
  });

  // The call that asks for a new draft is the one that can be told gone, so a
  // second such answer is what the run ends with rather than a loop.
  test('a run does not ask for a new draft more than once', () async {
    final directory = Directory.systemTemp.createTempSync(
      'pornolab_client_test',
    );

    final gone = '{"draft_id": 0, "gone": 1}';

    final http = _FakeHttpClient([
      _FakeResponse(200, _FakeHeaders(), body: page),
      _FakeResponse(200, _FakeHeaders(), body: gone),
      _FakeResponse(200, _FakeHeaders(), body: gone),
    ]);

    final client = HttpPornolabClient(
      client: http,
      log: ToolLog(),
      debug: DebugTextLog(),
    );

    final result = await client.saveDraft(
      releaseDirectory: directory.path,
      cookie: 'the-cookie',
      forumId: 1013,
      draftId: 42,
      subject: 'the title',
      message: 'the message',
    );

    expect(
      result,
      isA<PornolabFailure>().having(
        (f) => f.kind,
        'kind',
        PornolabFailureKind.draftGone,
      ),
    );

    expect(http.requests, hasLength(3));

    directory.deleteSync(recursive: true);
  });

  // The login form is what a browser sends: the fields in the order the form
  // declares them, the button's label as its value, and the whole body encoded
  // from the charset the page is in rather than UTF-8 (`ai/pornolab_login.md` §4).
  test('the login body is the form fields encoded in Windows-1251', () {
    expect(
      PornolabClient.loginBody(username: 'user', password: 'pass'),
      'redirect=index.php&login_username=user&login_password=pass'
      '&login=%C2%F5%EE%E4',
    );
  });

  // The captcha's two fields go between the credentials and the button, in the
  // order the form declares them (§4). The field name is the one the page gave,
  // not one the app knows.
  test('the captcha fields are sent in the order the form declares them', () {
    final captcha = PornolabClient.captchaFromPage(captchaPage)!;

    expect(
      PornolabClient.loginBody(
        username: 'user',
        password: 'pass',
        captcha: captcha,
        code: 'AB12',
      ),
      'redirect=index.php&login_username=user&login_password=pass'
      '&cap_sid=BsbMQsHd2NoihtWqHS0V'
      '&cap_code_f8d8fa25d65dc2f22824bce923bb5c3a=AB12'
      '&login=%C2%F5%EE%E4',
    );
  });

  test('a login value is encoded from its Windows-1251 bytes', () {
    // "Привет" in windows-1251: П is 0xCF there, not 0xD0 as in UTF-8.
    expect(PornolabClient.encodeCp1251('Привет'), '%CF%F0%E8%E2%E5%F2');

    // A space becomes `+`, as a form body does; the characters a form body
    // leaves as they are stay.
    expect(PornolabClient.encodeCp1251('a b-c_~.'), 'a+b-c_~.');

    // A character the codepage has no byte for is not dropped: it is sent as its
    // UTF-8 bytes, as a browser sends it when the form's charset cannot
    // represent it.
    expect(PornolabClient.encodeCp1251('é'), '%C3%A9');

    // A percent escape is two hex digits, so a byte under 0x10 is padded.
    expect(PornolabClient.encodeCp1251('\t'), '%09');

    // The same value through the app's UTF-8 rule is a different body.
    expect(
      PornolabClient.encodeCp1251('Привет'),
      isNot(Uri.encodeQueryComponent('Привет')),
    );
  });

  // The `Cookie` header value is the pairs from the answer with the attributes
  // dropped and the pairs joined; an answer with no pairs gives nothing
  // (`ai/pornolab_login.md` §5).
  test('the cookie is the pairs the Set-Cookie headers give', () {
    expect(
      PornolabClient.cookieFromHeaders({
        'set-cookie': ['session=abc; path=/forum; HttpOnly'],
      }),
      'session=abc',
    );

    // More than one header is more than one pair.
    expect(
      PornolabClient.cookieFromHeaders({
        'Set-Cookie': ['session=abc; path=/', 'sid=def; domain=pornolab.net'],
      }),
      'session=abc; sid=def',
    );

    // Nothing to store: no such header, or a header with only attributes.
    expect(
      PornolabClient.cookieFromHeaders({
        'content-type': ['text/html'],
      }),
      '',
    );
    expect(
      PornolabClient.cookieFromHeaders({
        'set-cookie': ['; path=/'],
      }),
      '',
    );
  });

  // The captcha is the shape a login page has after failed logins from the same
  // address. The code field's name is a hash that changes with the page, so it is
  // read from the page rather than assumed, and the image address is written
  // without a scheme (`ai/pornolab_login.md` §6).
  test('the captcha is the three parts the form carries', () {
    final captcha = PornolabClient.captchaFromPage(captchaPage);

    expect(captcha, isNotNull);
    expect(captcha!.sessionId, 'BsbMQsHd2NoihtWqHS0V');
    expect(captcha.fieldName, 'cap_code_f8d8fa25d65dc2f22824bce923bb5c3a');
    expect(
      captcha.imageUrl,
      'https://static.pornolab.net/captcha/'
      '0/25/82d2598a6af21cb51960e56f92e104e4.jpg?671714846',
    );

    // A login page with no captcha is the refused login, not a captcha.
    expect(PornolabClient.captchaFromPage('<h1>Login</h1>'), isNull);

    // Some of the parts is not a captcha the user can answer, so it is not read
    // as one.
    expect(
      PornolabClient.captchaFromPage(
        '<input type="hidden" name="cap_sid" value="BsbMQsHd2NoihtWqHS0V" />',
      ),
      isNull,
    );
  });

  // A `Set-Cookie` on its own is not proof, because the site sets one for an
  // anonymous visitor too, so the judgement is the shape of the answer
  // (`ai/pornolab_login.md` §6). These are the shapes the login handler has, not
  // shapes observed on the live site.
  test('a login answer is read as the shape it is', () {
    final accepted = PornolabClient.loginResult(
      status: 302,
      headers: {
        'set-cookie': ['session=abc; path=/forum'],
      },
      body: '',
    );

    expect(accepted, isA<LoggedIn>());
    expect((accepted as LoggedIn).cookie, 'session=abc');

    // Accepted, and nothing to store.
    expect(
      PornolabClient.loginResult(status: 302, headers: {}, body: ''),
      const PornolabFailure(PornolabFailureKind.loginNoCookie),
    );

    // The login page itself, with a cookie: not proof.
    expect(
      PornolabClient.loginResult(
        status: 200,
        headers: {
          'set-cookie': ['session=abc'],
        },
        body: '<h1>Login</h1>',
      ),
      const PornolabFailure(PornolabFailureKind.loginRefused),
    );

    // The login page asking for a code is a refused login the user can still
    // answer, so the result carries what the page gave and the cookie the same
    // answer set (§6).
    final needsCode = PornolabClient.loginResult(
      status: 200,
      headers: {
        'set-cookie': ['plm=1; Path=/'],
      },
      body: captchaPage,
    );

    expect(needsCode, isA<PornolabFailure>());
    expect(
      (needsCode as PornolabFailure).kind,
      PornolabFailureKind.captchaRequired,
    );
    expect(needsCode.captcha!.sessionId, 'BsbMQsHd2NoihtWqHS0V');
    expect(needsCode.captcha!.cookie, 'plm=1');

    // An answer that is neither 200 nor a redirect is not a login.
    expect(
      PornolabClient.loginResult(
        status: 500,
        headers: {
          'set-cookie': ['session=abc'],
        },
        body: '',
      ),
      const PornolabFailure(PornolabFailureKind.requestFailed),
    );
  });

  // A cookie the site does not accept is answered with the redirect to the
  // login page, so the location is what says the cookie was refused rather than
  // the status alone (`ai/uploading_draft.md` §6). The site sends it as a full
  // URL; a relative one names the same page.
  test('the location that is the login page is the cookie refused', () {
    expect(
      PornolabClient.locationIsLoginPage(
        'https://pornolab.net/forum/login.php?redirect=posting.php?mode=newtopic&f=1842',
      ),
      isTrue,
    );

    expect(
      PornolabClient.locationIsLoginPage('/forum/login.php?redirect=index.php'),
      isTrue,
    );

    // The page the token is read from, and the login page on another host, are
    // not the same answer.
    for (final location in [
      '/forum/posting.php?mode=newtopic&f=1842',
      'https://example.com/forum/login.php',
      '',
    ]) {
      expect(PornolabClient.locationIsLoginPage(location), isFalse);
    }
  });

  // A login entry: the two credentials are the marker, the form's two constants
  // are recorded as themselves, `read` is the cookie — which is never recorded as
  // its value even though the body is now read for the judgement — and
  // `Set-Cookie` is not recorded at all (§9).
  test('a login entry holds the marker, not the credentials or the cookie', () async {
    final directory = Directory.systemTemp.createTempSync(
      'pornolab_login_test',
    );

    final client = HttpPornolabClient(
      client: _FakeHttpClient([
        _FakeResponse(
          302,
          _FakeHeaders()
            ..add('location', 'https://pornolab.net/forum/index.php')
            ..add('set-cookie', 'session=abc; path=/forum'),
        ),
      ]),
      log: ToolLog(),
      debug: DebugTextLog(),
    );

    final result = await client.login(
      logDirectory: directory.path,
      username: 'the-user',
      password: 'the-password',
    );

    expect(result, isA<LoggedIn>());
    expect((result as LoggedIn).cookie, 'session=abc');

    final lines = logEntries(directory);

    expect(lines, hasLength(2));

    expect(lines[0]['stream'], 'request');
    expect(lines[0]['method'], 'POST');
    expect(lines[0]['url'], 'https://pornolab.net/forum/login.php');

    // No Cookie line at all: the app logs in because it has no cookie to send.
    expect(lines[0]['input'], [
      'redirect',
      PornolabClient.loginRedirectValue,
      'login_username',
      ToolLogEntry.redacted,
      'login_password',
      ToolLogEntry.redacted,
      'login',
      PornolabClient.loginButtonLabel,
      'User-Agent',
      PornolabClient.userAgent(),
    ]);

    // What the response records is what a problem is read back from: the status
    // and where the redirect would have gone. The header that carries the
    // credential is left out.
    expect(lines[1]['stream'], 'response');
    expect(lines[1]['status'], 302);
    expect(lines[1]['read'], ToolLogEntry.redacted);
    expect(lines[1]['headers'], {
      'location': ['https://pornolab.net/forum/index.php'],
    });

    for (final line in lines) {
      expect(line['input'], isNot(contains('the-user')));
      expect(line['input'], isNot(contains('the-password')));
      expect(line['input'], isNot(contains('session=abc')));
    }

    directory.deleteSync(recursive: true);
  });

  // A captcha entry: the two form fields the page gave are recorded as their
  // values — `cap_sid` is a value read out of a page, as a form token is, and the
  // code is not a credential but something the user read from an image — while the
  // cookie the same answer set is the marker, as every cookie is (§9).
  test('a captcha entry records the code and the sid, not the cookie', () async {
    final directory = Directory.systemTemp.createTempSync(
      'pornolab_login_test',
    );

    final captcha = PornolabClient.captchaFromPage(
      captchaPage,
      cookie: 'plm=1',
    )!;

    final client = HttpPornolabClient(
      client: _FakeHttpClient([
        _FakeResponse(
          200,
          _FakeHeaders()..add('set-cookie', 'plm=1; Path=/'),
          body: captchaPage,
        ),
      ]),
      log: ToolLog(),
      debug: DebugTextLog(),
    );

    final result = await client.login(
      logDirectory: directory.path,
      username: 'the-user',
      password: 'the-password',
      captcha: captcha,
      code: 'AB12',
    );

    expect(result, isA<PornolabFailure>());
    expect(
      (result as PornolabFailure).kind,
      PornolabFailureKind.captchaRequired,
    );

    final lines = logEntries(directory);

    expect(lines, hasLength(2));

    // The Cookie line is there because the app has something to send, which is
    // the one case a login has one.
    expect(lines[0]['input'], [
      'Cookie',
      ToolLogEntry.redacted,
      'redirect',
      PornolabClient.loginRedirectValue,
      'login_username',
      ToolLogEntry.redacted,
      'login_password',
      ToolLogEntry.redacted,
      'cap_sid',
      'BsbMQsHd2NoihtWqHS0V',
      'cap_code_f8d8fa25d65dc2f22824bce923bb5c3a',
      'AB12',
      'login',
      PornolabClient.loginButtonLabel,
      'User-Agent',
      PornolabClient.userAgent(),
    ]);

    expect(lines[1]['status'], 200);
    expect(lines[1]['read'], ToolLogEntry.redacted);

    for (final line in lines) {
      expect(line['input'], isNot(contains('the-user')));
      expect(line['input'], isNot(contains('the-password')));
      expect(line['input'], isNot(contains('plm=1')));
    }

    directory.deleteSync(recursive: true);
  });

  // The first login request carries the User-Agent and no Cookie header, and its
  // Content-Type names no charset, as a browser's does not (§4, §9).
  test('the first login request sends no Cookie header', () async {
    final directory = Directory.systemTemp.createTempSync(
      'pornolab_login_test',
    );

    final http = _FakeHttpClient([_FakeResponse(302, _FakeHeaders())]);

    final client = HttpPornolabClient(
      client: http,
      log: ToolLog(),
      debug: DebugTextLog(),
    );

    await client.login(
      logDirectory: directory.path,
      username: 'the-user',
      password: 'the-password',
    );

    final request = http.requests.first as _FakeRequest;

    expect(request.headers.value('Cookie'), isNull);
    expect(request.headers.value('User-Agent'), PornolabClient.userAgent());
    expect(request.headers.contentType!.charset, isNull);

    // The body is already percent-encoded from the Windows-1251 bytes, so every
    // character in it is ASCII and writing it as text writes the same bytes.
    expect(
      request.body.join(),
      PornolabClient.loginBody(username: 'the-user', password: 'the-password'),
    );

    directory.deleteSync(recursive: true);
  });

  // The app has no cookie jar, so the request with a code is the one place a
  // login sends a Cookie header: the cookie the page that asked for the code set,
  // as a browser would send it (§9).
  test(
    'the request with a code sends the cookie the captcha page gave',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'pornolab_login_test',
      );

      final captcha = PornolabClient.captchaFromPage(
        captchaPage,
        cookie: 'plm=1',
      )!;

      final http = _FakeHttpClient([
        _FakeResponse(302, _FakeHeaders()..add('set-cookie', 'session=abc')),
      ]);

      final client = HttpPornolabClient(
        client: http,
        log: ToolLog(),
        debug: DebugTextLog(),
      );

      await client.login(
        logDirectory: directory.path,
        username: 'the-user',
        password: 'the-password',
        captcha: captcha,
        code: 'AB12',
      );

      final request = http.requests.first as _FakeRequest;

      expect(request.headers.value('Cookie'), 'plm=1');

      expect(
        request.body.join(),
        PornolabClient.loginBody(
          username: 'the-user',
          password: 'the-password',
          captcha: captcha,
          code: 'AB12',
        ),
      );

      directory.deleteSync(recursive: true);
    },
  );

  // The form token belongs to the session the cookie is for, so a login is a new
  // session and the cached token is dropped (§7): the next run reads the page
  // again.
  test('a login drops the cached form token', () async {
    final directory = Directory.systemTemp.createTempSync(
      'pornolab_login_test',
    );

    final http = _FakeHttpClient([
      _FakeResponse(200, _FakeHeaders(), body: page),
      _FakeResponse(200, _FakeHeaders(), body: '{"draft_id": 42}'),
      _FakeResponse(302, _FakeHeaders()..add('set-cookie', 'session=abc')),
      _FakeResponse(200, _FakeHeaders(), body: page),
      _FakeResponse(200, _FakeHeaders(), body: '{"draft_id": 43}'),
    ]);

    final client = HttpPornolabClient(
      client: http,
      log: ToolLog(),
      debug: DebugTextLog(),
    );

    int pageReads() =>
        http.calls.where((url) => url.path.contains('posting.php')).length;

    Future<void> run() => client.saveDraft(
      releaseDirectory: directory.path,
      cookie: 'session=abc',
      forumId: 1013,
      draftId: 0,
      subject: 'the title',
      message: 'the message',
    );

    await run();

    expect(pageReads(), 1);

    // The second run used the token the first one read.
    await run();

    expect(pageReads(), 1);

    await client.login(
      logDirectory: directory.path,
      username: 'the-user',
      password: 'the-password',
    );

    // A new session, so the page is read again.
    await run();

    expect(pageReads(), 2);

    directory.deleteSync(recursive: true);
  });

  // The form the app fills, in the order the page lays it out
  // (`ai/pornolab_upload.md` §3). The parts the page has for its controls are
  // not sent, because the app has none of them.
  test(
    'the form is the parts the app has, in the order the page puts them',
    () {
      final parts = PornolabClient.formParts(
        token: token,
        forumId: 1857,
        draftId: 11818,
        subject: 'the title',
        message: 'the message',
        fileName: 'the-release.torrent',
        fileBytes: [1, 2, 3],
      );

      expect(parts.map((part) => part.name).toList(), [
        'mode',
        'f',
        't',
        'p',
        'draft_id',
        'subject',
        'message',
        'MAX_FILE_SIZE',
        'attach',
        'post',
        'form_token',
      ]);

      // The file part is between the message and the button, because that is
      // where the page's own form has it.
      expect(parts.indexWhere((part) => part.isFile), 8);
    },
  );

  // A file part is not a field, so it carries the name the sender gives the
  // file with and the type a browser writes for it (§3). The name is the one
  // the app's own run wrote the file under.
  test('the file part carries the name it was given with and its type', () {
    final parts = PornolabClient.formParts(
      token: token,
      forumId: 1857,
      draftId: 11818,
      subject: 'the title',
      message: 'the message',
      fileName: 'the-release.torrent',
      fileBytes: [1, 2, 3],
    );

    final file = parts.firstWhere((part) => part.isFile);

    expect(file.name, 'attach');
    expect(file.fileName, 'the-release.torrent');
    expect(file.contentType, 'application/x-bittorrent');
    expect(file.bytes, [1, 2, 3]);
  });

  // The body as the form writes it: the parts between the delimiter and the
  // value, the last closed with the two dashes RFC 2046 asks for (§3).
  test(
    'the body is the parts, with the file part carrying its content type',
    () {
      final parts = PornolabClient.formParts(
        token: token,
        forumId: 1857,
        draftId: 11818,
        subject: 'the title',
        message: 'the message',
        fileName: 'the-release.torrent',
        fileBytes: utf8.encode('d5:filesdee'),
      );

      final body = latin1.decode(
        PornolabClient.postBody(boundary: '----rpformboundary0', parts: parts),
      );

      // The delimiter is the two dashes RFC 2046 asks for plus the boundary,
      // which is what the recording shows a browser writing — so a boundary
      // that already begins with dashes is not a mistake.
      expect(
        body,
        startsWith(
          '------rpformboundary0\r\n'
          'Content-Disposition: form-data; name="mode"\r\n\r\nnewtopic\r\n',
        ),
      );
      expect(
        body,
        contains(
          'name="attach"; filename="the-release.torrent"\r\n'
          'Content-Type: application/x-bittorrent\r\n\r\nd5:filesdee\r\n',
        ),
      );
      expect(body, endsWith('------rpformboundary0--\r\n'));

      // The parts the page has for its controls are not in it, because the app
      // has no value for them.
      expect(body, isNot(contains('topic_tags')));
    },
  );

  // A part is the value itself rather than a percent-encoded field, so nothing
  // is escaped, and the bytes are still the page's codepage (§4).
  test('a value is written as the codepage bytes, with nothing escaped', () {
    expect(PornolabClient.cp1251Bytes('Привет'), [
      0xCF,
      0xF0,
      0xE8,
      0xE2,
      0xE5,
      0xF2,
    ]);

    // A space stays a space, which is what separates this from `encodeCp1251`.
    expect(PornolabClient.cp1251Bytes('a b'), utf8.encode('a b'));

    // A character the codepage has no byte for is the character's UTF-8 bytes,
    // the same rule `encodeCp1251` follows.
    expect(PornolabClient.cp1251Bytes('é'), utf8.encode('é'));
  });

  // The id the block carries is the same in both of its links, so either is
  // read (§5). A page that is not the block gives nothing: it cannot say which
  // of the two it refused, so it is one result until such an answer is seen
  // (§12).
  test('the id is read from either link the block carries', () {
    expect(PornolabClient.topicIdFromBlock(block), 3000111);

    expect(
      PornolabClient.topicIdFromBlock(
        block.replaceFirst('dl.php?t=', 'viewtopic.php?t='),
      ),
      3000111,
    );

    expect(PornolabClient.topicIdFromBlock(page), isNull);
  });

  // The path the served file is written at is the app's folder with the name
  // the site gives it, in the shape the record holds a path inside a release as
  // (§6, `ai/release_structure.md` §2). The link is built from the base the app
  // is talking to, as `draftUrl` is, because the id is what the answer gave.
  test('the served file and the link are named by the id the answer gave', () {
    expect(
      trackerTorrentPath(3000111),
      '_rp_torrent/[pornolab.net].t3000111.torrent',
    );

    expect(
      PornolabClient.topicUrl(topicId: 3000111),
      'https://pornolab.net/forum/viewtopic.php?t=3000111',
    );
  });

  // The name for the row is the link the breadcrumb cell writes for the forum
  // the value names. A name with an apostrophe comes as an entity, so it is
  // read back (§4). The fixture's pagination carries the same class and a link
  // for the same forum, so the expectation here is also that the cell is what
  // is read: a name read from the pagination would be a page number.
  test(
    'the name is read from the breadcrumb link for the forum the value names',
    () {
      expect(
        PornolabClient.forumNameFromPage(nav, 1857),
        "SiteRip's 2022 (HD Video)",
      );

      // A breadcrumb for another forum is not the name of this one, and a page
      // with no breadcrumb gives nothing: the name is a label, not something a
      // run needs.
      expect(PornolabClient.forumNameFromPage(nav, 1013), isNull);
      expect(PornolabClient.forumNameFromPage(page, 1857), isNull);
    },
  );

  // The page the name is read from is asked for at the base the app was started
  // with, as every other request on this interface is, so a run against the
  // stub reads the name from the page the stub writes (`ai/pornolab_upload.md`
  // §10). The value is not an address here: it is where the id comes from.
  test('the page the name is read from is asked for at the base', () async {
    devTrackerStub = true;
    addTearDown(() => devTrackerStub = false);

    final directory = Directory.systemTemp.createTempSync(
      'pornolab_name_base_test',
    );

    final http = _FakeHttpClient([
      _FakeResponse(200, _FakeHeaders(), body: nav),
    ]);

    final client = HttpPornolabClient(
      client: http,
      log: ToolLog(),
      debug: DebugTextLog(),
    );

    final result = await client.forumName(
      releaseDirectory: directory.path,
      cookie: 'session=abc',
      url: 'https://pornolab.net/forum/viewforum.php?f=1857',
    );

    expect(http.calls, [
      Uri.parse('http://localhost:40002/forum/viewforum.php?f=1857'),
    ]);

    expect(result, isA<ForumNameRead>());
    expect((result as ForumNameRead).name, "SiteRip's 2022 (HD Video)");

    // Without the flag the same call is made to the site, because the base is
    // the site's address then. One value, so the call and the links cannot
    // disagree.
    devTrackerStub = false;

    final site = _FakeHttpClient([
      _FakeResponse(200, _FakeHeaders(), body: nav),
    ]);

    final other = HttpPornolabClient(
      client: site,
      log: ToolLog(),
      debug: DebugTextLog(),
    );

    await other.forumName(
      releaseDirectory: directory.path,
      cookie: 'session=abc',
      url: 'https://pornolab.net/forum/viewforum.php?f=1857',
    );

    expect(site.calls, [
      Uri.parse('https://pornolab.net/forum/viewforum.php?f=1857'),
    ]);

    directory.deleteSync(recursive: true);
  });

  // A post is three calls: the page the token comes from, the form with the
  // file, and the file the tracker serves for the topic the form made (§7). The
  // test reads what was sent and what was written, because the file is the part
  // of the run the user cannot see.
  test(
    'a post sends the form and writes the file the tracker serves',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'pornolab_post_test',
      );

      final sent = File(p.join(directory.path, 'the-release.torrent'))
        ..writeAsBytesSync(utf8.encode('d5:filesdee'));

      final fileHeaders = _FakeHeaders()
        ..set(
          'content-disposition',
          'attachment; filename="[pornolab.net].t3000111.torrent"',
        );

      final http = _FakeHttpClient([
        _FakeResponse(200, _FakeHeaders(), body: page),
        _FakeResponse(200, _FakeHeaders(), body: block),
        _FakeResponse(200, fileHeaders, bytes: [9, 8, 7]),
      ]);

      final client = HttpPornolabClient(
        client: http,
        log: ToolLog(),
        debug: DebugTextLog(),
      );

      final result = await client.postTopic(
        releaseDirectory: directory.path,
        cookie: 'the-cookie',
        forumId: 1857,
        draftId: 11818,
        subject: 'the title',
        message: 'the message',
        filePath: sent.path,
      );

      expect(result, isA<Posted>());

      final posted = result as Posted;

      expect(posted.topicId, 3000111);
      expect(
        posted.topicUrl,
        'https://pornolab.net/forum/viewtopic.php?t=3000111',
      );

      // The tracker's copy is written in the app's folder, under the name the
      // site gives it, and the file the app sent stays: nothing in the app
      // deletes a file, so a posted release has both (§6). The path the result
      // carries is the recorded one, relative to the release directory.
      expect(posted.filePath, '_rp_torrent/[pornolab.net].t3000111.torrent');
      expect(File(p.join(directory.path, posted.filePath!)).readAsBytesSync(), [
        9,
        8,
        7,
      ]);

      // The form is sent as a browser sends it, so the boundary in the
      // Content-Type is the one the body is built from.
      final request = http.requests[1] as _FakeRequest;
      final header = request.headers.value('Content-Type')!;

      expect(header, startsWith('multipart/form-data; boundary='));

      final boundary = header.split('boundary=').last;

      expect(
        latin1.decode(request.bytes),
        startsWith(
          '--$boundary\r\nContent-Disposition: form-data; name="mode"',
        ),
      );
      expect(
        latin1.decode(request.bytes),
        contains('filename="the-release.torrent"'),
      );

      // The length is declared as a browser declares it, because a server
      // that is not a browser reads that header rather than the body. Without
      // it the form is a chunked body, which is a shape nothing here has a rule
      // for (§3).
      expect(request.headers.contentLength, request.bytes.length);
      expect(request.headers.contentLength, greaterThan(0));

      // The log records a file part as the name it was given with and its size,
      // never its bytes (§9). The cookie is still the marker, as the app's log
      // keeps it. The entries are one per request and one per answer in the
      // order the calls were made, so the form is the third entry.
      final lines = logEntries(directory);

      expect(lines[0]['input'], contains(ToolLogEntry.redacted));
      expect(
        lines[2]['input'],
        containsAll(['attach', 'the-release.torrent', 'size']),
      );
      expect(lines[2]['input'], isNot(contains('d5:filesdee')));

      directory.deleteSync(recursive: true);
    },
  );

  // The plain text copy (`ai/uploading_draft.md` §8) is the same calls read
  // by hand: the cookie as its value and a page in full, which are the two
  // things an encoding or a field the site wants is read back from, and
  // which the app's log keeps as markers for a reason that applies to a run a
  // user makes. The flag is turned on here because the file is what the test
  // reads; the test for the flag itself is `test/debug_text_log_test.dart`.
  test(
    'the text log records the cookie as its value and the page in full',
    () async {
      verboseTrackerLogging = true;
      addTearDown(() => verboseTrackerLogging = false);

      final directory = Directory.systemTemp.createTempSync(
        'pornolab_debug_test',
      );

      final sent = File(p.join(directory.path, 'the-release.torrent'))
        ..writeAsBytesSync(utf8.encode('d5:filesdee'));

      final http = _FakeHttpClient([
        _FakeResponse(200, _FakeHeaders(), body: page),
        _FakeResponse(200, _FakeHeaders(), body: block),
        _FakeResponse(200, _FakeHeaders(), bytes: [9, 8, 7]),
      ]);

      final client = HttpPornolabClient(
        client: http,
        log: ToolLog(),
        debug: DebugTextLog(),
      );

      await client.postTopic(
        releaseDirectory: directory.path,
        cookie: 'session=abc',
        forumId: 1857,
        draftId: 11818,
        subject: 'the title',
        message: 'the message',
        filePath: sent.path,
      );

      final text = File(
        p.join(directory.path, ToolLog.directoryName, DebugTextLog.fileName),
      ).readAsStringSync();

      // The cookie as its value, and the user agent, each as one header line.
      expect(text, contains('Cookie: session=abc'));
      expect(text, contains('User-Agent: ReleasePrepper/0.1.0'));
      expect(text, contains(page));

      // A file is not text, so its part is recorded as its name and its size,
      // as the app's log records it.
      expect(text, contains('the-release.torrent, 11 bytes'));
      expect(text, isNot(contains('d5:filesdee')));

      // The lines are the headers the app sets itself, which is the length the
      // form declares as well (§8).
      expect(text, matches(RegExp(r'Content-Length: \d+')));

      // Every request the client makes writes its block, which is the one for
      // the file as well, and the block for a request comes before its answer
      // (§8).
      final download = http.calls.last;
      final requestBlock = text.indexOf(
        '${'<' * DebugTextLog.gutterWidth} GET $download',
      );
      final answerBlock = text.indexOf(
        '${'>' * DebugTextLog.gutterWidth} 200 GET $download',
      );

      expect(requestBlock, greaterThan(-1));
      expect(answerBlock, greaterThan(requestBlock));

      directory.deleteSync(recursive: true);
    },
  );

  // A post is not made for a release with no file to send, because for a
  // tracker whose releases are torrents a topic with no file is not a release
  // (§7). The gate is before the request, so nothing is asked for.
  test('a post is not made when there is no file to send', () async {
    final directory = Directory.systemTemp.createTempSync(
      'pornolab_no_file_test',
    );

    final http = _FakeHttpClient([
      _FakeResponse(200, _FakeHeaders(), body: page),
    ]);

    final client = HttpPornolabClient(
      client: http,
      log: ToolLog(),
      debug: DebugTextLog(),
    );

    final result = await client.postTopic(
      releaseDirectory: directory.path,
      cookie: 'the-cookie',
      forumId: 1857,
      draftId: 11818,
      subject: 'the title',
      message: 'the message',
      filePath: p.join(directory.path, 'the-release.torrent'),
    );

    expect(
      result,
      isA<PornolabFailure>().having(
        (f) => f.kind,
        'kind',
        PornolabFailureKind.noFile,
      ),
    );

    expect(http.requests, isEmpty);

    directory.deleteSync(recursive: true);
  });

  // What the form declares for the file is the rule the app works inside, so a
  // file outside it is refused before the request: the answer for one is a
  // shape the recording does not have (§3, §12).
  test(
    'a file outside what the form declares is refused before the request',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'pornolab_refused_test',
      );

      final http = _FakeHttpClient([
        _FakeResponse(200, _FakeHeaders(), body: page),
      ]);

      final client = HttpPornolabClient(
        client: http,
        log: ToolLog(),
        debug: DebugTextLog(),
      );

      final tooSmall = File(p.join(directory.path, 'the-release.txt'))
        ..writeAsBytesSync([1]);

      final result = await client.postTopic(
        releaseDirectory: directory.path,
        cookie: 'the-cookie',
        forumId: 1857,
        draftId: 11818,
        subject: 'the title',
        message: 'the message',
        filePath: tooSmall.path,
      );

      expect(
        result,
        isA<PornolabFailure>().having(
          (f) => f.kind,
          'kind',
          PornolabFailureKind.fileRefused,
        ),
      );

      expect(http.requests, isEmpty);

      // The same for a file over the size the form declares.
      final tooLarge = File(p.join(directory.path, 'the-release.torrent'))
        ..writeAsBytesSync(List.filled(PornolabClient.maxFileSize + 1, 0));

      final tooLargeResult = await client.postTopic(
        releaseDirectory: directory.path,
        cookie: 'the-cookie',
        forumId: 1857,
        draftId: 11818,
        subject: 'the title',
        message: 'the message',
        filePath: tooLarge.path,
      );

      expect(
        tooLargeResult,
        isA<PornolabFailure>().having(
          (f) => f.kind,
          'kind',
          PornolabFailureKind.fileRefused,
        ),
      );

      expect(http.requests, isEmpty);

      directory.deleteSync(recursive: true);
    },
  );

  // The topic exists whatever the download gives, so a download that fails is
  // the file not being written rather than the run failing: the section says
  // the two apart because the user needs to know which of them the release has
  // (§6, §8).
  test('a post whose download fails is the file not being written', () async {
    final directory = Directory.systemTemp.createTempSync(
      'pornolab_download_test',
    );

    final sent = File(p.join(directory.path, 'the-release.torrent'))
      ..writeAsBytesSync([1]);

    final http = _FakeHttpClient([
      _FakeResponse(200, _FakeHeaders(), body: page),
      _FakeResponse(200, _FakeHeaders(), body: block),
      _FakeResponse(404, _FakeHeaders(), body: ''),
    ]);

    final client = HttpPornolabClient(
      client: http,
      log: ToolLog(),
      debug: DebugTextLog(),
    );

    final result = await client.postTopic(
      releaseDirectory: directory.path,
      cookie: 'the-cookie',
      forumId: 1857,
      draftId: 11818,
      subject: 'the title',
      message: 'the message',
      filePath: sent.path,
    );

    expect(result, isA<Posted>());

    final posted = result as Posted;

    expect(posted.topicId, 3000111);
    expect(posted.filePath, isNull);
    expect(
      File(p.join(directory.path, '[pornolab.net].t3000111.torrent'))
          .existsSync(),
      isFalse,
    );

    directory.deleteSync(recursive: true);
  });

  // A write that fails is the same result as a download that fails. The path
  // the run writes to is held by a directory here, which is the shape a write
  // cannot succeed against.
  test(
    'a post whose write fails says the topic was made and the file not written',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'pornolab_write_test',
      );

      final sent = File(p.join(directory.path, 'the-release.torrent'))
        ..writeAsBytesSync([1]);

      final http = _FakeHttpClient([
        _FakeResponse(200, _FakeHeaders(), body: page),
        _FakeResponse(200, _FakeHeaders(), body: block),
        _FakeResponse(200, _FakeHeaders(), bytes: [9, 8, 7]),
      ]);

      final client = HttpPornolabClient(
        client: http,
        log: ToolLog(),
        debug: DebugTextLog(),
      );

      Directory(p.join(directory.path, trackerTorrentPath(3000111)))
          .createSync(recursive: true);

      final result = await client.postTopic(
        releaseDirectory: directory.path,
        cookie: 'the-cookie',
        forumId: 1857,
        draftId: 11818,
        subject: 'the title',
        message: 'the message',
        filePath: sent.path,
      );

      expect(result, isA<Posted>());
      expect((result as Posted).filePath, isNull);

      directory.deleteSync(recursive: true);
    },
  );
}
