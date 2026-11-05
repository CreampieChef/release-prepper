import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:enough_convert/windows.dart';

import '../../app/app_info.dart';
import '../logging/tool_log.dart';
import '../logging/tool_log_entry.dart';

/// PornoLab, over the two requests `ai/uploading_draft.md` describes: the page
/// that gives the form token, and the call that saves a draft.
///
/// It is an interface, as `SecretStore` is, so the feature can be tested against
/// a fake. The rules it applies — a forum id read from a URL, the form body, a
/// token read from a page, a response read as JSON — are functions on the
/// interface, so a test exercises them without a request, the way
/// `StashClient.parseResponse` is exercised (`ai/uploading_draft.md` §9).
abstract class PornolabClient {
  /// The site the app calls and the link it builds. `Tracker` holds no address;
  /// the address is here because this is the code that needs it.
  static const siteBase = 'https://pornolab.net';

  /// The same limit `ToolRunner` has.
  static const timeout = Duration(seconds: 60);

  /// The name the log records the site as, in the place a tool name is.
  static const logName = 'pornolab';

  /// The header the app sends, so a site can identify the version it is talking
  /// to and block one it finds problems with (`ai/uploading_draft.md` §3). No
  /// `Referer` is sent. A product token is one word, so the name is used here
  /// without the space it has as the app's display name.
  static String userAgent() => '${appName.replaceAll(' ', '')}/$appVersion';

  Future<PornolabResult> saveDraft({
    required String releaseDirectory,
    required String cookie,
    required int forumId,
    required int draftId,
    required String subject,
    required String message,
  });

  /// The login (`ai/pornolab_login.md`). The cookie it gives back is stored by
  /// the settings feature, so the client does not hold it; [logDirectory] is
  /// where the two entries are written, because the settings page has no
  /// release directory.
  ///
  /// [captcha] is the form the answer before it asked for and [code] what the
  /// user typed into it. They are given rather than held: a login that needs a
  /// code is a second request, and the code belongs to the page that asked for
  /// it. Only the settings page makes a login — a run does not, because the
  /// site asks for a captcha after a few logins and the app cannot read one
  /// (`ai/pornolab_login.md` §7).
  Future<PornolabResult> login({
    required String logDirectory,
    required String username,
    required String password,
    LoginCaptcha? captcha,
    String code = '',
  });

  /// The forum id the app asks the site for. A value that is not a full URL on
  /// the site with an `f` parameter answers null, which is the shape rule the
  /// section gates on (`field_validation.dart`).
  static int? forumIdFromUrl(String value) {
    final url = Uri.tryParse(value);

    if (url == null || !url.isAbsolute || url.host != _host) {
      return null;
    }

    final id = int.tryParse(url.queryParameters['f'] ?? '');

    return id == null || id <= 0 ? null : id;
  }

  /// The draft id in a link the app stored. 0 for a link that has none, which is
  /// what a file the user edited can be: a run then makes a new draft.
  static int draftIdFromUrl(String value) {
    final url = Uri.tryParse(value);

    if (url == null) {
      return 0;
    }

    return int.tryParse(url.queryParameters['draft'] ?? '') ?? 0;
  }

  /// The link the app shows and stores. It is built from the site rather than
  /// from what the user pasted, the same rule as the scene link
  /// (`StashClient.siteBase`).
  static String draftUrl({required int forumId, required int draftId}) =>
      '$siteBase/forum/posting.php?mode=newtopic&f=$forumId&draft=$draftId';

  /// The form body, with the values percent-encoded as UTF-8, so the newlines of
  /// a message are `%0A`.
  static String formBody({
    required String token,
    required int forumId,
    required int draftId,
    required String subject,
    required String message,
  }) => [
    'action=topic_draft',
    'mode=save',
    'form_token=${Uri.encodeQueryComponent(token)}',
    'draft_id=$draftId',
    'forum_id=$forumId',
    'subject=${Uri.encodeQueryComponent(subject)}',
    'message=${Uri.encodeQueryComponent(message)}',
  ].join('&');

  /// The value of the login form's submit button. A browser sends a named submit
  /// button as part of the form data, and its value is the button's label, so
  /// this is a field of the form rather than data the app chose
  /// (`ai/pornolab_login.md` §4). The label is the site's own word, in the
  /// charset its pages are in.
  static const loginButtonLabel = 'Вход';

  /// The login form's hidden field. A browser sends it as part of the form data,
  /// so the body is the form rather than data the app chose, as the button's
  /// value is (`ai/pornolab_login.md` §4).
  static const loginRedirectValue = 'index.php';

  /// The login form body, in the order the form declares its fields: the hidden
  /// one, the two credentials, the captcha's two when the form has them, the
  /// submit button. The whole body is encoded in Windows-1251, not UTF-8, because
  /// here the app is reproducing what the site's own form sends rather than
  /// building a body of its own; this is the one request that does not use the
  /// app's UTF-8 rule (`ai/pornolab_login.md` §4).
  static String loginBody({
    required String username,
    required String password,
    LoginCaptcha? captcha,
    String code = '',
  }) => [
    'redirect=${encodeCp1251(loginRedirectValue)}',
    'login_username=${encodeCp1251(username)}',
    'login_password=${encodeCp1251(password)}',
    if (captcha != null) ...[
      'cap_sid=${encodeCp1251(captcha.sessionId)}',
      '${encodeCp1251(captcha.fieldName)}=${encodeCp1251(code)}',
    ],
    'login=${encodeCp1251(loginButtonLabel)}',
  ].join('&');

  /// A value percent-encoded from its Windows-1251 bytes.
  /// `Uri.encodeQueryComponent` encodes as UTF-8, so the bytes are taken from
  /// the codec and escaped here. The characters a form body leaves as they are
  /// are the unreserved ones; a space becomes `+`, as `Uri.encodeQueryComponent`
  /// does.
  ///
  /// A character the codepage has no byte for is not dropped or replaced: a
  /// browser percent-encodes its UTF-8 bytes when the form's charset cannot
  /// represent it, so the app does the same. The site reads the form as
  /// Windows-1251, so such a value is refused there too — the point is that the
  /// app sends what the browser sends instead of failing before the request.
  static String encodeCp1251(String value) {
    final codec = const Windows1251Codec();
    final out = StringBuffer();

    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);

      for (final byte in _formBytes(codec, character)) {
        if (byte == 0x20) {
          out.write('+');
        } else if (_unreserved(byte)) {
          out.writeCharCode(byte);
        } else {
          out.write('%${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}');
        }
      }
    }

    return out.toString();
  }

  /// The bytes a form body sends one character as: the codepage's byte when it
  /// has one, otherwise the character's UTF-8 bytes.
  static List<int> _formBytes(Windows1251Codec codec, String character) {
    try {
      return codec.encode(character);
    } on FormatException {
      return utf8.encode(character);
    }
  }

  /// The `Cookie` header value built from the `Set-Cookie` headers an answer
  /// gave: the `name=value` pair from each, the attributes dropped, the pairs
  /// joined with `; ` — which is what the app sends on its next call. An answer
  /// with no pairs gives an empty value, and more than one header is more than
  /// one pair (`ai/pornolab_login.md` §5).
  static String cookieFromHeaders(Map<String, List<String>> headers) {
    final pairs = <String>[];

    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != 'set-cookie') {
        continue;
      }

      for (final value in entry.value) {
        final pair = value.split(';').first.trim();

        if (pair.isNotEmpty) {
          pairs.add(pair);
        }
      }
    }

    return pairs.join('; ');
  }

  /// The captcha a login page asks for, read out of the form it writes. The
  /// three parts are what the app needs: the image the code is read from, the
  /// hidden field that says which captcha an answer is for, and the name of the
  /// code field — which is a hash that changes with the page, so it cannot be a
  /// constant (`ai/pornolab_login.md` §6). A page with only some of them is the
  /// refused login, not a captcha: a code the app cannot show is a code the user
  /// cannot type.
  ///
  /// [cookie] is what the answer set, and it travels with the captcha because
  /// the app has no cookie jar: the code is checked against the session the page
  /// that asked for it belongs to, so the second request sends the cookie as a
  /// browser would (`ai/pornolab_login.md` §9).
  static LoginCaptcha? captchaFromPage(String body, {String cookie = ''}) {
    final sid = _capSid.firstMatch(body);
    final field = _capField.firstMatch(body);
    final image = _capImage.firstMatch(body);

    if (sid == null || field == null || image == null) {
      return null;
    }

    return LoginCaptcha(
      imageUrl: _absolute(image.group(1)!),
      sessionId: sid.group(1)!,
      fieldName: 'cap_code_${field.group(1)!}',
      cookie: cookie,
    );
  }

  /// A page link made absolute. The page writes its own links without a scheme,
  /// so the image address has to be one the app can request.
  static String _absolute(String url) =>
      url.startsWith('//') ? 'https:$url' : url;

  /// Whether a redirect's location is the login page. A cookie the site does
  /// not accept is answered with a redirect to it before the page is served, so
  /// the location is what says the cookie was refused, not the status alone
  /// (`ai/uploading_draft.md` §6). The site sends the location as a full URL; a
  /// relative one names the same page, so both are read the same way.
  static bool locationIsLoginPage(String location) {
    final url = Uri.tryParse(location);

    if (url == null) {
      return false;
    }

    if (url.isAbsolute && url.host != _host) {
      return false;
    }

    return url.path == '/forum/login.php';
  }

  /// A login answer read as the shape it is: a redirect is the login accepted,
  /// the login page itself is it refused, and the login page that asks for a
  /// code is a refused login the user can still answer (§6). A `Set-Cookie` on
  /// its own is not proof, because the site sets a session cookie for an
  /// anonymous visitor too, so the cookie is taken only from an answer that shows
  /// the login was accepted.
  static PornolabResult loginResult({
    required int status,
    required Map<String, List<String>> headers,
    required String body,
  }) {
    if (status == 200) {
      final captcha = captchaFromPage(body, cookie: cookieFromHeaders(headers));

      return captcha == null
          ? const PornolabFailure(PornolabFailureKind.loginRefused)
          : PornolabFailure(
              PornolabFailureKind.captchaRequired,
              captcha: captcha,
            );
    }

    if (status < 300 || status >= 400) {
      return const PornolabFailure(PornolabFailureKind.requestFailed);
    }

    final cookie = cookieFromHeaders(headers);

    return cookie.isEmpty
        ? const PornolabFailure(PornolabFailureKind.loginNoCookie)
        : LoggedIn(cookie);
  }

  static bool _unreserved(int byte) =>
      (byte >= 0x30 && byte <= 0x39) ||
      (byte >= 0x41 && byte <= 0x5A) ||
      (byte >= 0x61 && byte <= 0x7A) ||
      byte == 0x2D ||
      byte == 0x2E ||
      byte == 0x5F ||
      byte == 0x7E;

  /// The token, from either form the page writes it in. The example has only the
  /// assignment, because the page builds its form with JavaScript, so both forms
  /// are tried.
  static String? formTokenFromPage(String html) {
    for (final pattern in [_inputValue, _assignment]) {
      final match = pattern.firstMatch(html);

      if (match != null) {
        return match.group(1);
      }
    }

    return null;
  }

  /// One response read as JSON. `error_code` 1 is the form signature the site
  /// did not accept; `gone` 1 is the draft the app asked for not being on the
  /// site any more, which the client answers by making a new one
  /// (`ai/uploading_draft.md` §6); the other codes are one result until they are
  /// seen (§11).
  static PornolabResult parseResponse(Object? decoded, int forumId) {
    if (decoded is! Map<String, dynamic>) {
      return const PornolabFailure(PornolabFailureKind.badResponse);
    }

    if (decoded['error_code'] is int) {
      return decoded['error_code'] == 1
          ? const PornolabFailure(PornolabFailureKind.tokenRejected)
          : const PornolabFailure(PornolabFailureKind.siteError);
    }

    if (decoded['gone'] == 1) {
      return const PornolabFailure(PornolabFailureKind.draftGone);
    }

    final draftId = decoded['draft_id'];

    if (draftId is! int) {
      return const PornolabFailure(PornolabFailureKind.badResponse);
    }

    return DraftSaved(
      draftId,
      draftUrl: draftUrl(forumId: forumId, draftId: draftId),
    );
  }

  /// A response body, read as the charset its Content-Type declares. The site's
  /// pages are not UTF-8, so reading them as UTF-8 is what a run failed with
  /// before.
  ///
  /// A charset the app has no codec for, or none declared, is read as latin1,
  /// which cannot fail: the values the app reads out of a response are ASCII, so
  /// an encoding it does not know is not a reason to lose a run. What the text
  /// looks like is then a matter for the log, where the site's own words go.
  static String decodeBody(List<int> bytes, String? charset) {
    final codec = switch (charset?.toLowerCase()) {
      'utf-8' || 'utf8' => utf8,
      'windows-1251' || 'cp1251' => const Windows1251Codec(),
      _ => latin1,
    };

    return codec.decode(bytes);
  }

  /// The response headers the log records. A credential is never recorded as its
  /// value, so the headers that carry one are left out, as the cookie in the
  /// request is (`ToolLogEntry.redacted`). What is left is what a problem is
  /// read back from: the charset the answer came in, where a redirect would have
  /// gone.
  static Map<String, List<String>> logHeaders(
    Map<String, List<String>> headers,
  ) => {
    for (final entry in headers.entries)
      if (!_credentialHeaders.contains(entry.key.toLowerCase()))
        entry.key: entry.value,
  };

  static const _credentialHeaders = {
    'set-cookie',
    'authorization',
    'www-authenticate',
  };

  static const _host = 'pornolab.net';

  static final _inputValue = RegExp(r'''form_token" value="([0-9a-f]{32})''');

  static final _assignment = RegExp(
    r"""form_token(?:'|\")? = '([0-9a-f]{32})'""",
  );

  static final _capSid = RegExp(r'name="cap_sid" value="([^"]+)"');

  static final _capField = RegExp(r'name="cap_code_([0-9a-f]+)"');

  static final _capImage = RegExp(r'<img src="([^"]*captcha[^"]*)"');
}

/// The requests, over the `HttpClient` the app already has.
class HttpPornolabClient implements PornolabClient {
  HttpPornolabClient({required this.client, required this.log});

  final HttpClient client;

  /// Writing the log is one of the side effects of making a request, so it is a
  /// required parameter, as it is for `ToolRunner`.
  final ToolLog log;

  /// The token for the app's session on the site. The site ties it to the
  /// session rather than to a release, and this is one instance for the whole
  /// app, so the cache is here rather than in a feature
  /// (`ai/uploading_draft.md` §6). A run told the token was wrong drops it, so
  /// the next run reads the page again.
  String? _token;

  @override
  Future<PornolabResult> saveDraft({
    required String releaseDirectory,
    required String cookie,
    required int forumId,
    required int draftId,
    required String subject,
    required String message,
  }) async {
    try {
      String? token = _token;

      if (token == null) {
        final page = await _get(
          releaseDirectory,
          cookie,
          Uri.parse('${PornolabClient.siteBase}/forum/posting.php')
              .replace(queryParameters: {'mode': 'newtopic', 'f': '$forumId'}),
        );

        if (page.status != 200) {
          // A cookie the site does not accept is answered with the redirect to
          // the login page before the page is served; any other answer is the
          // request failing (`ai/uploading_draft.md` §6).
          return PornolabFailure(
            PornolabClient.locationIsLoginPage(page.location)
                ? PornolabFailureKind.cookieRefused
                : PornolabFailureKind.requestFailed,
          );
        }

        token = PornolabClient.formTokenFromPage(page.body);

        if (token == null) {
          return const PornolabFailure(PornolabFailureKind.noToken);
        }

        _token = token;
      }

      final result = await _save(
        releaseDirectory,
        cookie,
        token,
        forumId,
        draftId,
        subject,
        message,
      );

      // An answer that says the stored draft is gone is not a draft to link to,
      // so the run makes one: the same form with `draft_id` 0 is the call that
      // creates a draft (`ai/uploading_draft.md` §6). One new draft, not a loop
      // — the second call asks for a new one, so an answer that still says gone
      // is what the run ends with.
      if (result case PornolabFailure(kind: PornolabFailureKind.draftGone)) {
        final created = await _save(
          releaseDirectory,
          cookie,
          token,
          forumId,
          0,
          subject,
          message,
        );

        // The link the release holds is the new draft's, so the result says
        // which of the two the run made, and the section says that too.
        if (created case DraftSaved(draftId: final id, draftUrl: final url)) {
          return DraftSaved(id, draftUrl: url, recreated: true);
        }

        return created;
      }

      return result;
    } on TimeoutException {
      return const PornolabFailure(PornolabFailureKind.timedOut);
    } catch (_) {
      return const PornolabFailure(PornolabFailureKind.requestFailed);
    }
  }

  /// One call that saves the draft, and the answer read as the result it is.
  Future<PornolabResult> _save(
    String releaseDirectory,
    String cookie,
    String token,
    int forumId,
    int draftId,
    String subject,
    String message,
  ) async {
    final body = PornolabClient.formBody(
      token: token,
      forumId: forumId,
      draftId: draftId,
      subject: subject,
      message: message,
    );

    final response = await _post(
      releaseDirectory,
      cookie,
      Uri.parse('${PornolabClient.siteBase}/forum/ajax.php'),
      body,
    );

    if (response.status != 200) {
      return const PornolabFailure(PornolabFailureKind.requestFailed);
    }

    final result = PornolabClient.parseResponse(_json(response.body), forumId);

    // The token the site did not accept is not the token to keep.
    if (result case PornolabFailure(kind: PornolabFailureKind.tokenRejected)) {
      _token = null;
    }

    return result;
  }

  @override
  Future<PornolabResult> login({
    required String logDirectory,
    required String username,
    required String password,
    LoginCaptcha? captcha,
    String code = '',
  }) async {
    try {
      final url = Uri.parse('${PornolabClient.siteBase}/forum/login.php');

      // The first request has no cookie to send, because the app logs in for the
      // reason it has none. The request with a code sends the cookie the captcha
      // page set, as a browser would (`ai/pornolab_login.md` §9).
      final cookie = captcha?.cookie ?? '';

      // The credentials are never recorded as their values, so the two form
      // fields are the marker. The hidden field and the button's value are
      // constants, so they are recorded as themselves, and so are the captcha's
      // two: `cap_sid` is a value read out of a page, as a form token is, and
      // the code is not a credential but something the user read from an image
      // (`ai/pornolab_login.md` §9).
      final input = [
        if (cookie.isNotEmpty) ...['Cookie', ToolLogEntry.redacted],
        'redirect',
        PornolabClient.loginRedirectValue,
        'login_username',
        ToolLogEntry.redacted,
        'login_password',
        ToolLogEntry.redacted,
        if (captcha != null) ...[
          'cap_sid',
          captcha.sessionId,
          captcha.fieldName,
          code,
        ],
        'login',
        PornolabClient.loginButtonLabel,
        'User-Agent',
        PornolabClient.userAgent(),
      ];

      final body = PornolabClient.loginBody(
        username: username,
        password: password,
        captcha: captcha,
        code: code,
      );

      await log.write(
        logDirectory,
        ToolLogRequest(
          date: DateTime.now().toUtc(),
          tool: PornolabClient.logName,
          input: input,
          method: 'POST',
          url: url.toString(),
        ),
      );

      try {
        final request = await client.postUrl(url);

        // The answer is judged by whether it is a redirect, so the redirect is
        // not followed.
        request.followRedirects = false;

        _headers(request, cookie);

        // The Content-Type names no charset, as a browser's does not. The body is
        // already percent-encoded from the Windows-1251 bytes, so every character
        // in it is ASCII and writing it as text writes the same bytes
        // (`ai/pornolab_login.md` §4).
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
        );

        request.write(body);

        final response = await request.close().timeout(PornolabClient.timeout);
        final headers = _headersMap(response.headers);

        // The body is read because the judgement has a third shape: the page that
        // asks for a code. What the entry records as what was read is the cookie,
        // which is never recorded as its value.
        final text = await _read(response);

        await log.write(
          logDirectory,
          ToolLogResponse(
            date: DateTime.now().toUtc(),
            tool: PornolabClient.logName,
            input: input,
            status: response.statusCode,
            read: ToolLogEntry.redacted,
            headers: PornolabClient.logHeaders(headers),
          ),
        );

        // A login is a new session on the site, so the token that belonged to
        // the one before it is not kept (`ai/pornolab_login.md` §7).
        _token = null;

        return PornolabClient.loginResult(
          status: response.statusCode,
          headers: headers,
          body: text,
        );
      } catch (error) {
        await log.write(
          logDirectory,
          ToolLogFailure(
            date: DateTime.now().toUtc(),
            tool: PornolabClient.logName,
            input: input,
            error: error.toString(),
          ),
        );

        rethrow;
      }
    } on TimeoutException {
      return const PornolabFailure(PornolabFailureKind.timedOut);
    } catch (_) {
      return const PornolabFailure(PornolabFailureKind.requestFailed);
    }
  }

  Future<_Exchange> _get(
    String releaseDirectory,
    String cookie,
    Uri url,
  ) async {
    final input = _input(cookie);

    await log.write(
      releaseDirectory,
      ToolLogRequest(
        date: DateTime.now().toUtc(),
        tool: PornolabClient.logName,
        input: input,
        method: 'GET',
        url: url.toString(),
      ),
    );

    try {
      final request = await client.getUrl(url);

      // A redirect to the login page is the cookie not being accepted, and
      // following it would turn that into a page with no token.
      request.followRedirects = false;
      _headers(request, cookie);

      final response = await request.close().timeout(PornolabClient.timeout);
      final body = await _read(response);
      final received = _headersMap(response.headers);

      await log.write(
        releaseDirectory,
        ToolLogResponse(
          date: DateTime.now().toUtc(),
          tool: PornolabClient.logName,
          input: input,
          status: response.statusCode,
          read: PornolabClient.formTokenFromPage(body) ?? '',
          headers: PornolabClient.logHeaders(received),
        ),
      );

      return _Exchange(
        response.statusCode,
        body,
        location: response.headers.value('location') ?? '',
      );
    } catch (error) {
      await log.write(
        releaseDirectory,
        ToolLogFailure(
          date: DateTime.now().toUtc(),
          tool: PornolabClient.logName,
          input: input,
          error: error.toString(),
        ),
      );

      rethrow;
    }
  }

  Future<_Exchange> _post(
    String releaseDirectory,
    String cookie,
    Uri url,
    String body,
  ) async {
    final input = [
      ..._input(cookie),
      for (final part in body.split('&')) ...part.split('='),
    ];

    await log.write(
      releaseDirectory,
      ToolLogRequest(
        date: DateTime.now().toUtc(),
        tool: PornolabClient.logName,
        input: input,
        method: 'POST',
        url: url.toString(),
      ),
    );

    try {
      final request = await client.postUrl(url);

      request.followRedirects = false;
      _headers(request, cookie);
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(body);

      final response = await request.close().timeout(PornolabClient.timeout);
      final text = await _read(response);
      final received = _headersMap(response.headers);

      await log.write(
        releaseDirectory,
        ToolLogResponse(
          date: DateTime.now().toUtc(),
          tool: PornolabClient.logName,
          input: input,
          status: response.statusCode,
          read: text,
          headers: PornolabClient.logHeaders(received),
        ),
      );

      return _Exchange(response.statusCode, text);
    } catch (error) {
      await log.write(
        releaseDirectory,
        ToolLogFailure(
          date: DateTime.now().toUtc(),
          tool: PornolabClient.logName,
          input: input,
          error: error.toString(),
        ),
      );

      rethrow;
    }
  }

  void _headers(HttpClientRequest request, String cookie) {
    // A login has no cookie to send, because the app makes it for the reason it
    // has none (`ai/pornolab_login.md` §9).
    if (cookie.isNotEmpty) {
      request.headers.set('Cookie', cookie);
    }

    request.headers.set('User-Agent', PornolabClient.userAgent());
  }

  /// The answer as text. The bytes are collected before being decoded because
  /// the charset is the response's, not what the app assumes.
  Future<String> _read(HttpClientResponse response) async {
    final bytes = <int>[];

    await response.forEach(bytes.addAll).timeout(PornolabClient.timeout);

    return PornolabClient.decodeBody(
      bytes,
      response.headers.contentType?.charset,
    );
  }

  /// The response headers as a map, so the rule on the interface is what decides
  /// which of them the log records. The map is the whole set, because the login
  /// reads the cookie out of the ones the log does not record.
  Map<String, List<String>> _headersMap(HttpHeaders headers) {
    final values = <String, List<String>>{};

    headers.forEach((name, value) => values[name] = value);

    return values;
  }

  /// The cookie as the log records it: the name and the marker, never the value.
  List<String> _input(String cookie) => [
    'Cookie',
    ToolLogEntry.redacted,
    'User-Agent',
    PornolabClient.userAgent(),
  ];

  Object? _json(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}

/// One request and the answer to it, so the flow can decide what the answer
/// means. The log entries are written by the code that made the request.
final class _Exchange {
  const _Exchange(this.status, this.body, {this.location = ''});

  final int status;
  final String body;

  /// Where a redirect would have gone. The login page is what a cookie the site
  /// does not accept gets, so the location is what says the cookie was refused
  /// (`ai/uploading_draft.md` §6).
  final String location;
}

/// What a call to the site can end with: a saved draft, the cookie a login
/// gives, or a failure. Both features read this one set, so the words for the
/// failures are one set shared by them rather than a set per feature
/// (`ai/pornolab_login.md` §8).
sealed class PornolabResult {
  const PornolabResult();
}

final class DraftSaved extends PornolabResult {
  const DraftSaved(
    this.draftId, {
    required this.draftUrl,
    this.recreated = false,
  });

  final int draftId;

  /// The link the section shows and the release stores.
  final String draftUrl;

  /// Whether the run made a new draft rather than updating the one the stored
  /// link pointed at. The link the release holds changes, so the section says
  /// which of the two happened (`ai/uploading_draft.md` §6).
  final bool recreated;
}

final class LoggedIn extends PornolabResult {
  const LoggedIn(this.cookie);

  /// The `Cookie` header value the answer's `Set-Cookie` headers give, as
  /// `cookieFromHeaders` builds it.
  final String cookie;
}

/// What a login page that asks for a code gave the app: the three parts of the
/// form it writes, and the cookie the same answer set. The code itself is not
/// here, because it is what the user types — it is given to the next request
/// rather than carried in a result.
final class LoginCaptcha {
  const LoginCaptcha({
    required this.imageUrl,
    required this.sessionId,
    required this.fieldName,
    required this.cookie,
  });

  /// The image the code is read from, as the page gives it, made absolute.
  final String imageUrl;

  /// The hidden `cap_sid`, which is what the answer identifies the captcha by.
  final String sessionId;

  /// The name of the code field, `cap_code_<hash>`. The hash changes with the
  /// page, so the name is read from it rather than a constant.
  final String fieldName;

  /// The cookie the answer set. The app has no cookie jar, so this is what the
  /// request with the code sends (`ai/pornolab_login.md` §9).
  final String cookie;
}

final class PornolabFailure extends PornolabResult {
  const PornolabFailure(this.kind, {this.captcha});

  final PornolabFailureKind kind;

  /// The captcha, for the one kind that asks for one. The widget shows the image
  /// and the field, so the result has to carry what the page gave; it is a field
  /// of the failure rather than a result case of its own because the words for a
  /// result are one set the two features share (`ai/pornolab_login.md` §8).
  final LoginCaptcha? captcha;
}

enum PornolabFailureKind {
  /// No username, or no password. Checked before the request, and the same rule
  /// the settings page gates its button on.
  noCredentials,

  /// No cookie stored. Checked before the request, and the same rule the draft
  /// section gates its button on: the app does not log in by itself, because
  /// the site asks for a captcha after a few logins and the app cannot read one
  /// (`ai/pornolab_login.md` §7).
  noCookie,

  /// The parent forum field is empty.
  noForum,

  /// A value that is not a full URL on the site with an `f` parameter.
  badForumUrl,

  /// The answer was the login page: the credentials were not accepted.
  loginRefused,

  /// The answer was the login page asking for a code. The credentials were
  /// accepted — the page echoes them back — but the form cannot be completed
  /// without a code the app cannot read, so this is the one result that carries
  /// what the page gave (`ai/pornolab_login.md` §6).
  captchaRequired,

  /// The login was accepted and the answer carried no cookie.
  loginNoCookie,

  /// A login was accepted and its cookie was not written. The login itself
  /// succeeded; this is the settings feature's own write path failing, so it is
  /// said with the words the other fields use. It is here rather than in a
  /// settings type because a run can reach it too.
  valueNotStored,

  /// The page the token is read from answered with the redirect to the login
  /// page, which is what a cookie the site does not accept gets
  /// (`ai/uploading_draft.md` §6).
  cookieRefused,

  /// The page was served and had no form token. A cookie the site does not
  /// accept is answered with the redirect before the page is served, so this is
  /// a page that answered 200 without one (`ai/uploading_draft.md` §6).
  noToken,

  /// `error_code` 1: the form signature the site did not accept. A cookie the
  /// site does not accept is answered before this check is reached, on the page
  /// the token is read from, so this is the form check's own result
  /// (`ai/uploading_draft.md` §11).
  tokenRejected,

  /// `gone` 1: the draft the app asked for is not on the site any more. The
  /// client answers the first such answer by making a new draft, so this is what
  /// a run ends with when the new one is refused too
  /// (`ai/uploading_draft.md` §6).
  draftGone,

  /// Any other error the site reports. Only the wrong-token one is known, so the
  /// rest are one result until they are seen.
  siteError,

  /// A response that is not JSON, or not the shape the app reads.
  badResponse,

  /// No connection, or a response that is not 200.
  requestFailed,

  /// Stopped for running longer than the client's timeout.
  timedOut,
}
