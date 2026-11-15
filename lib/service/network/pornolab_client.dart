import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:enough_convert/windows.dart';
import 'package:path/path.dart' as p;

import '../../app/app_info.dart';
import '../logging/debug_text_log.dart';
import '../logging/tool_log.dart';
import '../logging/tool_log_entry.dart';
import '../torrent/torrent_path.dart';

/// Whether the app was started with `--dev-tracker-stub`, which is what makes
/// the client build its requests and its links from the stub under
/// `testing-tools/pornolab-stub/` rather than from the site
/// (`ai/pornolab_upload.md` §10).
///
/// This is the second of the three top-level variables in the app, and the
/// second exception to rule 10, for the reason rule 10 gives for the first: it
/// is read once by `main()` before the app is built and nothing writes it
/// afterwards, and no part of the app is the place that decides an address, so
/// there is nowhere in the provider scope to put it.
bool devTrackerStub = false;

/// PornoLab, over the requests the app makes to it: the page that gives the
/// form token, the call that saves a draft, the form with the file attached,
/// and the file the tracker serves back for the topic that form made.
///
/// It is an interface, as `SecretStore` is, so the feature can be tested
/// against a fake. The rules it applies — a forum id read from a URL, the form
/// body, a token read from a page, a response read as JSON, the block read for
/// the id it carries — are functions on the interface, so a test exercises them
/// without a request, the way `StashClient.parseResponse` is exercised
/// (`ai/uploading_draft.md` §9, `ai/pornolab_upload.md` §10).
abstract class PornolabClient {
  /// The site the app calls and the link it builds. `Tracker` holds no address;
  /// the address is here because this is the code that needs it. Nothing uses
  /// this directly: the requests and the links read `base()`, which is this
  /// when the app was not started with the flag.
  static const siteBase = 'https://pornolab.net';

  /// The address the stub serves on — the port its `README.md` documents, and
  /// the one the script defaults to.
  static const stubBase = 'http://localhost:40002';

  /// The base the requests and the links are built from: the stub when the app
  /// was started with `--dev-tracker-stub`, the site otherwise. One rule,
  /// because the two have to agree: a link to the site is not the topic the
  /// stub made (`ai/pornolab_upload.md` §10).
  static String base() => devTrackerStub ? stubBase : siteBase;

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

  /// The post (`ai/pornolab_upload.md`): the form with the file attached, and
  /// the file the tracker serves back for the topic that form made.
  ///
  /// [filePath] is the file the app's own run wrote, because a post is not made
  /// before there is a file to carry (`ai/pornolab_upload.md` §7). The file the
  /// answer gives is written into the release under the name the site gives it
  /// (§6); the file the app sent is kept, because nothing in the app deletes a
  /// file — so a release that has been posted has two, and the result names the
  /// one the site gave.
  Future<PornolabResult> postTopic({
    required String releaseDirectory,
    required String cookie,
    required int forumId,
    required int draftId,
    required String subject,
    required String message,
    required String filePath,
  });

  /// The name the page gives for the forum the field's value names
  /// (`ai/pornolab_upload.md` §5). The page is asked for at `base()`, as every
  /// other request here is, and the answer is cached under the value the row
  /// holds. The name is what the row shows; it is not stored, and a post is
  /// made from the id in the URL whatever the page says, so a page with no name
  /// is reported as the answer it is rather than as a result the section has
  /// words for.
  Future<PornolabResult> forumName({
    required String releaseDirectory,
    required String cookie,
    required String url,
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

  /// The link the app shows and stores. It is built from the base the app is
  /// talking to rather than from what the user pasted, the same rule as the
  /// scene link (`StashClient.siteBase`) — so a link made while the app is
  /// pointed at the stub is the stub's link.
  static String draftUrl({required int forumId, required int draftId}) =>
      '${base()}/forum/posting.php?mode=newtopic&f=$forumId&draft=$draftId';

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

  /// What the page declares for the file part: the size and the extensions
  /// (`ai/pornolab_upload.md` §3). The app does not gate on them — it sends the
  /// file it has and a refusal is an answer, not a check — so this is the one
  /// place the rule is, and the result that names a refused file is read from
  /// the same values.
  static const maxFileSize = 1048576;

  static const acceptedExtensions = ['.torrent', '.zip', '.rar'];

  /// The link a post makes. Built from the base the app is talking to rather
  /// than from what the user pasted, the same rule as `draftUrl`, because the
  /// id is what the answer gave (`ai/pornolab_upload.md` §5).
  static String topicUrl({required int topicId}) =>
      '${base()}/forum/viewtopic.php?t=$topicId';

  /// The parts of the form, in the order the page lays it out (§3), with the
  /// file part between the message and `post` because that is where the page's
  /// own form has it. The parts the page has for its controls are not here,
  /// because the app has none of them, and whether the site wants a value for
  /// one is an open question (§12) — nothing is invented for it.
  ///
  /// One rule for the order, because the same parts are what the body is built
  /// from and what the log records.
  static List<FormPart> formParts({
    required String token,
    required int forumId,
    required int draftId,
    required String subject,
    required String message,
    required String fileName,
    required List<int> fileBytes,
  }) => [
    FormPart('mode', value: 'newtopic'),
    FormPart('f', value: '$forumId'),
    FormPart('t', value: '0'),
    FormPart('p', value: '0'),
    FormPart('draft_id', value: '$draftId'),
    FormPart('subject', value: subject),
    FormPart('message', value: message),
    FormPart('MAX_FILE_SIZE', value: '$maxFileSize'),
    FormPart(
      'attach',
      fileName: fileName,
      contentType: 'application/x-bittorrent',
      bytes: fileBytes,
    ),
    FormPart('post', value: '1'),
    FormPart('form_token', value: token),
  ];

  /// The parts written as a multipart body. The values are written as the
  /// page's charset, not as UTF-8: a post is a form the app is filling, and the
  /// recording of one is Windows-1251 (§4). A part is the value itself rather
  /// than a percent-encoded field, so nothing is escaped.
  static List<int> postBody({
    required String boundary,
    required List<FormPart> parts,
  }) {
    final delimiter = '--$boundary';

    return [
      for (final part in parts) ...[
        ...utf8.encode(
          '$delimiter\r\nContent-Disposition: form-data; name="${part.name}"',
        ),
        if (part.isFile) ...[
          ...utf8.encode('; filename="${part.fileName}"'),
          ...utf8.encode('\r\nContent-Type: ${part.contentType}'),
        ],
        ...utf8.encode('\r\n\r\n'),
        ...(part.isFile ? part.bytes : cp1251Bytes(part.value)),
        ...utf8.encode('\r\n'),
      ],
      ...utf8.encode('$delimiter--\r\n'),
    ];
  }

  /// The id the block carries, as §5 reads it: the first `t` inside the block,
  /// which both of its links have. A page with no block is an answer the app
  /// cannot name, and that is one result until such an answer is seen (§12) —
  /// it is not read as the form being refused, because a page like this cannot
  /// say which of the two it refused.
  static int? topicIdFromBlock(String html) {
    final block = _block.firstMatch(html);

    if (block == null) {
      return null;
    }

    final id = _blockId.firstMatch(block.group(1)!);

    return id == null ? null : int.tryParse(id.group(1)!);
  }

  /// The name the page gives for the forum the field's value names: the link the
  /// breadcrumb cell writes for that forum id, which is the shape a real page was
  /// seen to write. A page that writes no breadcrumb, or a breadcrumb for
  /// another forum, gives no name — the row shows nothing, because the name is
  /// a label and the run works from the id the value names.
  static String? forumNameFromPage(String html, int forumId) {
    final nav = _nav.firstMatch(html);

    if (nav == null) {
      return null;
    }

    for (final link in _navLink.allMatches(nav.group(1)!)) {
      if (int.tryParse(link.group(1)!) == forumId) {
        return unescape(link.group(2)!);
      }
    }

    return null;
  }

  /// A name as the page writes it: HTML entities are read back as the
  /// characters they stand for, because a name with an apostrophe comes as
  /// `&#039;`. Only the five the page was seen to write; anything else is left
  /// as it came.
  static String unescape(String text) => text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'");

  /// The bytes a part of a multipart form writes a value as: the codepage's
  /// bytes when it has one, otherwise the character's UTF-8 bytes — the same
  /// rule as `encodeCp1251`, without the escaping, because a part is the value
  /// itself and not a percent-encoded field.
  static List<int> cp1251Bytes(String value) {
    final codec = const Windows1251Codec();
    final out = <int>[];

    for (final rune in value.runes) {
      out.addAll(_formBytes(codec, String.fromCharCode(rune)));
    }

    return out;
  }

  /// A boundary the app makes up. It only has to be a string the body cannot
  /// contain, so it is not the shape a browser's is; the parts are separated by
  /// the two dashes RFC 2046 asks for, which is what the recording shows a
  /// browser writing.
  static String formBoundary() =>
      '----rpformboundary${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

  static final _block = RegExp(
    r'(<table class="forumline message">.*?</table>)',
    dotAll: true,
  );

  static final _blockId = RegExp(r'[?&]t=(\d+)');

  /// The breadcrumb as the page writes it: the table cell with the `nav` class,
  /// which a real page was seen to write twice — as `nav nav-top` at the top and
  /// as `nav` at the bottom — and the first is read. The cell is what is looked
  /// for, not any element with that class: the same page writes its pagination as
  /// a `div` with it, and the links there name the same forum as page numbers, so
  /// a name read from there would be a number.
  static final _nav = RegExp(
    r'<td class="nav[^"]*"[^>]*>(.*?)</td>',
    dotAll: true,
  );

  static final _navLink = RegExp(
    r'<a href="[^"]*viewforum\.php\?f=(\d+)">([^<]+)',
  );

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
  HttpPornolabClient({
    required this.client,
    required this.log,
    required this.debug,
  });

  final HttpClient client;

  /// Writing the log is one of the side effects of making a request, so it is a
  /// required parameter, as it is for `ToolRunner`.
  final ToolLog log;

  /// The plain text copy of the same calls (`ai/uploading_draft.md` §8),
  /// written only for a run started with `--unsafe-verbose-tracker-logging`. It
  /// is a required parameter for the same reason, and the calls that write it
  /// stay with the client: whether anything is written is the service's
  /// decision, and the shape of a block is its shape as well, so a call says
  /// only which side of the exchange it is and what the call was.
  final DebugTextLog debug;

  /// The token for the app's session on the site. The site ties it to the
  /// session rather than to a release, and this is one instance for the whole
  /// app, so the cache is here rather than in a feature
  /// (`ai/uploading_draft.md` §6). A run told the token was wrong drops it, so
  /// the next run reads the page again.
  String? _token;

  /// The names read for the value the parent forum row holds, by URL. The same
  /// reason as the token: a name belongs to the site, not to a release, and the
  /// row asks for it while it is being typed, so a redraw must not be a
  /// request.
  final _names = <String, String>{};

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
      final answer = await _tokenFor(releaseDirectory, cookie, forumId);

      if (answer.failure != null) {
        return answer.failure!;
      }

      final token = answer.token!;

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

  @override
  Future<PornolabResult> postTopic({
    required String releaseDirectory,
    required String cookie,
    required int forumId,
    required int draftId,
    required String subject,
    required String message,
    required String filePath,
  }) async {
    try {
      final file = File(filePath);

      if (!file.existsSync()) {
        return const PornolabFailure(PornolabFailureKind.noFile);
      }

      // What the page declares for the file part is the rule the app works
      // inside, so a file outside it is refused before the request: the answer
      // for one is a shape the recording does not have (`ai/pornolab_upload.md`
      // §3, §12).
      final bytes = file.readAsBytesSync();

      if (!PornolabClient.acceptedExtensions.contains(
        p.extension(filePath).toLowerCase(),
      )) {
        return const PornolabFailure(PornolabFailureKind.fileRefused);
      }

      if (bytes.length > PornolabClient.maxFileSize) {
        return const PornolabFailure(PornolabFailureKind.fileRefused);
      }

      final answer = await _tokenFor(releaseDirectory, cookie, forumId);

      if (answer.failure != null) {
        return answer.failure!;
      }

      final parts = PornolabClient.formParts(
        token: answer.token!,
        forumId: forumId,
        draftId: draftId,
        subject: subject,
        message: message,
        fileName: p.basename(filePath),
        fileBytes: bytes,
      );

      final boundary = PornolabClient.formBoundary();

      final response = await _postForm(
        releaseDirectory,
        cookie,
        Uri.parse('${PornolabClient.base()}/forum/posting.php'),
        boundary,
        parts,
      );

      if (response.status != 200) {
        return PornolabFailure(
          PornolabClient.locationIsLoginPage(response.location)
              ? PornolabFailureKind.cookieRefused
              : PornolabFailureKind.requestFailed,
        );
      }

      final made = PornolabClient.topicIdFromBlock(response.body);

      // A page that is not the block is one result with the form not being
      // accepted, because an answer like this cannot name which of the two it
      // refused (`ai/pornolab_upload.md` §5). The token is not dropped for it:
      // the app was not told the token was wrong, and the shape that says so
      // belongs to the draft call.
      if (made == null) {
        return const PornolabFailure(PornolabFailureKind.badResponse);
      }

      // The run cannot be read as finished at the answer: the file the account
      // is told to seed is the one the tracker serves, and that is what the
      // release gets (`ai/pornolab_upload.md` §6). The topic exists whatever
      // the download gives, so a download that fails is the file not being
      // written, not the run failing.
      final served = await _getFile(
        releaseDirectory,
        cookie,
        Uri.parse('${PornolabClient.base()}/forum/dl.php'),
        {'t': '$made'},
      );

      // The path is what the record holds, so the result carries it in the
      // shape the format records a path inside a release as: relative to the
      // release directory. The file goes under the app's folder, because a
      // posted release keeps two `.torrent` files (`ai/pornolab_upload.md` §6).
      final path = trackerTorrentPath(made);
      final written = p.join(releaseDirectory, path);

      if (served.status != 200) {
        return Posted(made, topicUrl: PornolabClient.topicUrl(topicId: made));
      }

      try {
        // The folder is the app's own, like the log's, so it is created the
        // same way before the first file goes into it.
        final folder = Directory(p.dirname(written));

        if (!folder.existsSync()) {
          folder.createSync(recursive: true);
        }

        await File(written).writeAsBytes(served.bytes);
      } catch (_) {
        return Posted(made, topicUrl: PornolabClient.topicUrl(topicId: made));
      }

      return Posted(
        made,
        topicUrl: PornolabClient.topicUrl(topicId: made),
        filePath: path,
      );
    } on TimeoutException {
      return const PornolabFailure(PornolabFailureKind.timedOut);
    } catch (_) {
      return const PornolabFailure(PornolabFailureKind.requestFailed);
    }
  }

  @override
  Future<PornolabResult> forumName({
    required String releaseDirectory,
    required String cookie,
    required String url,
  }) async {
    // The shape rule is the row's gate, so a name is asked for only for a value
    // the row accepts (`field_validation.dart`).
    final forumId = PornolabClient.forumIdFromUrl(url);

    if (forumId == null) {
      return const PornolabFailure(PornolabFailureKind.badForumUrl);
    }

    final cached = _names[url];

    if (cached != null) {
      return ForumNameRead(cached);
    }

    try {
      // The page is asked for at the base the app was started with, as every
      // other request on this interface is, so a run against the stub reads the
      // name from the page the stub writes (`ai/pornolab_upload.md` §10). The
      // value stays the key the answer is cached under, because that is what
      // the row asked for and what a redraw must not ask again.
      final page = await _get(
        releaseDirectory,
        cookie,
        Uri.parse('${PornolabClient.base()}/forum/viewforum.php')
            .replace(queryParameters: {'f': '$forumId'}),
        read: (body) => PornolabClient.forumNameFromPage(body, forumId) ?? '',
      );

      if (page.status != 200) {
        return PornolabFailure(
          PornolabClient.locationIsLoginPage(page.location)
              ? PornolabFailureKind.cookieRefused
              : PornolabFailureKind.requestFailed,
        );
      }

      final name = PornolabClient.forumNameFromPage(page.body, forumId);

      // A page with no breadcrumb is an answer the app cannot read; the row
      // shows nothing for it, because the name is a label and not something a
      // run needs (`ai/pornolab_upload.md` §5).
      if (name == null) {
        return const PornolabFailure(PornolabFailureKind.badResponse);
      }

      _names[url] = name;

      return ForumNameRead(name);
    } on TimeoutException {
      return const PornolabFailure(PornolabFailureKind.timedOut);
    } catch (_) {
      return const PornolabFailure(PornolabFailureKind.requestFailed);
    }
  }

  /// The token, the cached one when there is one. The page is asked for without
  /// the draft: the token belongs to the session, so the recording's `draft`
  /// parameter is not what the rule needs, and the same page gives the same
  /// token for both features.
  Future<_TokenAnswer> _tokenFor(
    String releaseDirectory,
    String cookie,
    int forumId,
  ) async {
    if (_token != null) {
      return _TokenAnswer(token: _token);
    }

    final page = await _get(
      releaseDirectory,
      cookie,
      Uri.parse('${PornolabClient.base()}/forum/posting.php')
          .replace(queryParameters: {'mode': 'newtopic', 'f': '$forumId'}),
      read: (body) => PornolabClient.formTokenFromPage(body) ?? '',
    );

    if (page.status != 200) {
      // A cookie the site does not accept is answered with the redirect to the
      // login page before the page is served; any other answer is the request
      // failing (`ai/uploading_draft.md` §6).
      return _TokenAnswer(
        failure: PornolabFailure(
          PornolabClient.locationIsLoginPage(page.location)
              ? PornolabFailureKind.cookieRefused
              : PornolabFailureKind.requestFailed,
        ),
      );
    }

    final token = PornolabClient.formTokenFromPage(page.body);

    if (token == null) {
      return _TokenAnswer(
        failure: const PornolabFailure(PornolabFailureKind.noToken),
      );
    }

    _token = token;

    return _TokenAnswer(token: token);
  }

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
      Uri.parse('${PornolabClient.base()}/forum/ajax.php'),
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
      final url = Uri.parse('${PornolabClient.base()}/forum/login.php');

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

      await debug.sent(logDirectory, 'POST $url', _ownHeaders(cookie), body);

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

        await debug.received(
          logDirectory,
          '${response.statusCode} POST $url',
          _headerLines(headers),
          text,
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

        await debug.failed(logDirectory, 'POST $url', error.toString());

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
    Uri url, {
    required String Function(String body) read,
  }) async {
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

    await debug.sent(releaseDirectory, 'GET $url', _ownHeaders(cookie));

    try {
      final request = await client.getUrl(url);

      // A redirect to the login page is the cookie not being accepted, and
      // following it would turn that into a page with no token.
      request.followRedirects = false;
      _headers(request, cookie);

      final response = await request.close().timeout(PornolabClient.timeout);
      final bytes = await _bytes(response);
      final body = PornolabClient.decodeBody(
        bytes,
        response.headers.contentType?.charset,
      );
      final received = _headersMap(response.headers);

      await log.write(
        releaseDirectory,
        ToolLogResponse(
          date: DateTime.now().toUtc(),
          tool: PornolabClient.logName,
          input: input,
          status: response.statusCode,
          read: read(body),
          headers: PornolabClient.logHeaders(received),
        ),
      );

      await debug.received(
        releaseDirectory,
        '${response.statusCode} GET $url',
        _headerLines(received),
        body,
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

      await debug.failed(releaseDirectory, 'GET $url', error.toString());

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

    await debug.sent(releaseDirectory, 'POST $url', _ownHeaders(cookie), body);

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

      await debug.received(
        releaseDirectory,
        '${response.statusCode} POST $url',
        _headerLines(received),
        text,
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

      await debug.failed(releaseDirectory, 'POST $url', error.toString());

      rethrow;
    }
  }

  /// A form the app is filling rather than a body it invents: the parts as
  /// `formParts` orders them, sent as a browser sends a form, and the answer
  /// read as the block the site writes for a post.
  Future<_Exchange> _postForm(
    String releaseDirectory,
    String cookie,
    Uri url,
    String boundary,
    List<FormPart> parts,
  ) async {
    // A file part is not a field, so the entry holds the name it was given with
    // and its size, never its bytes (`ai/pornolab_upload.md` §9).
    final input = [
      ..._input(cookie),
      for (final part in parts)
        if (part.isFile) ...[
          part.name,
          part.fileName,
          'size',
          '${part.bytes.length}',
        ] else ...[
          part.name,
          part.value,
        ],
    ];

    final body = PornolabClient.postBody(boundary: boundary, parts: parts);

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

    await debug.sent(
      releaseDirectory,
      'POST $url',
      [
        ..._ownHeaders(cookie),
        'Content-Type: multipart/form-data; boundary=$boundary',
        'Content-Length: ${body.length}',
      ],
      [
        for (final part in parts)
          part.isFile
              ? '${part.name} = ${part.fileName}, ${part.bytes.length} bytes'
              : '${part.name} = ${part.value}',
      ].join('\n'),
    );

    try {
      final request = await client.postUrl(url);

      request.followRedirects = false;
      _headers(request, cookie);

      // The boundary is written as the browser writes it, in the header itself:
      // `ContentType` has no field for one, so the value is set as the string
      // the form sends.
      request.headers.set(
        'Content-Type',
        'multipart/form-data; boundary=$boundary',
      );

      // The length is declared, as a browser declares it. A server that is not
      // a browser reads this header rather than the body, so a form without it
      // is sent as a chunked body, which is a shape nothing here has a rule for
      // (`ai/pornolab_upload.md` §3).
      request.headers.contentLength = body.length;

      request.add(body);

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

      await debug.received(
        releaseDirectory,
        '${response.statusCode} POST $url',
        _headerLines(received),
        text,
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

      await debug.failed(releaseDirectory, 'POST $url', error.toString());

      rethrow;
    }
  }

  /// A file the site serves. The bytes are kept as they came: the charset rule
  /// is for a page, and the pieces of a bencoded file are bytes, so reading
  /// them as text would change what the app writes. The text log records the
  /// size rather than the bytes, as the app's log does.
  Future<_FileExchange> _getFile(
    String releaseDirectory,
    String cookie,
    Uri url,
    Map<String, String> query,
  ) async {
    final full = url.replace(queryParameters: query);
    final input = [..._input(cookie), 't', query['t'] ?? ''];

    await log.write(
      releaseDirectory,
      ToolLogRequest(
        date: DateTime.now().toUtc(),
        tool: PornolabClient.logName,
        input: input,
        method: 'GET',
        url: full.toString(),
      ),
    );

    await debug.sent(releaseDirectory, 'GET $full', _ownHeaders(cookie));

    try {
      final request = await client.getUrl(full);

      request.followRedirects = false;
      _headers(request, cookie);

      final response = await request.close().timeout(PornolabClient.timeout);
      final bytes = await _bytes(response);
      final received = _headersMap(response.headers);
      final name =
          _dispositionName(response.headers.value('content-disposition')) ?? '';

      // The name the answer gave the file is the id it is for, and the headers
      // the entry records carry the size, which is what says the file is there
      // (§9).
      await log.write(
        releaseDirectory,
        ToolLogResponse(
          date: DateTime.now().toUtc(),
          tool: PornolabClient.logName,
          input: input,
          status: response.statusCode,
          read: name,
          headers: PornolabClient.logHeaders(received),
        ),
      );

      await debug.received(
        releaseDirectory,
        '${response.statusCode} GET $full',
        _headerLines(received),
        '${bytes.length} bytes, not text',
      );

      return _FileExchange(
        response.statusCode,
        bytes,
        name,
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

      await debug.failed(releaseDirectory, 'GET $full', error.toString());

      rethrow;
    }
  }

  /// The headers the app sets itself, as the text log writes a header: the
  /// cookie as its value, which the app's log keeps as the marker, and the user
  /// agent as the app sends it. They go through the same helper the answer's
  /// headers go through, so a header is `name: value` in both
  /// (`ai/uploading_draft.md` §8).
  List<String> _ownHeaders(String cookie) => _headerLines({
    if (cookie.isNotEmpty) 'Cookie': [cookie],
    'User-Agent': [PornolabClient.userAgent()],
  });

  List<String> _headerLines(Map<String, List<String>> headers) => [
    for (final entry in headers.entries)
      '${entry.key}: ${entry.value.join(', ')}',
  ];

  /// The file name an answer's `Content-Disposition` carries, or nothing when
  /// the answer served a file without naming it.
  String? _dispositionName(String? disposition) {
    if (disposition == null) {
      return null;
    }

    final match = RegExp(r'filename="([^"]*)"').firstMatch(disposition);

    return match?.group(1);
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
    final bytes = await _bytes(response);

    return PornolabClient.decodeBody(
      bytes,
      response.headers.contentType?.charset,
    );
  }

  Future<List<int>> _bytes(HttpClientResponse response) async {
    final bytes = <int>[];

    await response.forEach(bytes.addAll).timeout(PornolabClient.timeout);

    return bytes;
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

/// An answer that is a file. The bytes are what the answer gave, because a file
/// is not text: decoding the pieces of a bencoded file as a charset would
/// change them. The name is the one the answer carried, which is the id it is
/// for (`ai/pornolab_upload.md` §9).
final class _FileExchange {
  const _FileExchange(this.status, this.bytes, this.name, {this.location = ''});

  final int status;
  final List<int> bytes;
  final String name;
  final String location;
}

/// The token, or the reason there is none. Both are one type because a call
/// cannot be made without a token, and the code that reads the page for one
/// does not know which of the two it has until the page is read.
final class _TokenAnswer {
  const _TokenAnswer({this.token, this.failure});

  final String? token;
  final PornolabFailure? failure;
}

/// One part of the form the app is filling (`ai/pornolab_upload.md` §3): the
/// name, and either the value or the file. A file part is not a field, which is
/// why it is its own shape rather than a value, and why the log records it as a
/// name and a size.
final class FormPart {
  const FormPart(
    this.name, {
    this.value = '',
    this.fileName = '',
    this.contentType = '',
    this.bytes = const [],
  });

  final String name;
  final String value;

  /// The name the sender gives the file with: the name the app's own run wrote
  /// it under, not the name the site will give it later. Whether the name
  /// matters to the site is an open question (§12).
  final String fileName;

  /// The type a browser writes for a part it did not choose: the form's file
  /// field carries `application/x-bittorrent` for a .torrent.
  final String contentType;

  final List<int> bytes;

  bool get isFile => fileName.isNotEmpty;
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

final class Posted extends PornolabResult {
  const Posted(this.topicId, {required this.topicUrl, this.filePath});

  final int topicId;

  /// The link the section shows and the release stores, built from the id the
  /// answer carried (`ai/pornolab_upload.md` §5).
  final String topicUrl;

  /// The path the file the site serves was written at, relative to the release
  /// directory, which is the shape a path inside a release is recorded as
  /// (`ai/release_structure.md` §2, `lib/service/torrent/torrent_path.dart`).
  /// Null when the file was not written — the download failed or the write
  /// failed — which the section says apart from the file being written, because
  /// the topic exists either way (`ai/pornolab_upload.md` §6, §8).
  final String? filePath;
}

/// The name the page gives for the forum the field's value names. It is shown
/// on the row and not stored: a run works from the id the value names, so a
/// name is a label (`ai/pornolab_upload.md` §5).
final class ForumNameRead extends PornolabResult {
  const ForumNameRead(this.name);

  final String name;
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

  /// No file to send. Checked before the request, and the same rule the section
  /// gates its publish button on: the file is the point of this feature, so a
  /// post is not made for a release that has none (`ai/pornolab_upload.md` §7).
  noFile,

  /// A file outside what the form declares: over the size, or not one of the
  /// extensions. The app checks it before the request because it has the file,
  /// and the answer for such a file is a shape the recording does not have, so
  /// it is one result until one is seen (`ai/pornolab_upload.md` §3, §8).
  fileRefused,

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
