import 'dart:async';

import 'package:release_prepper/service/network/pornolab_client.dart';

/// The client answers with the results the test gives instead of making a
/// request, so no test that uses it reaches the network.
///
/// The results are fields a test sets, because one test may need the login to
/// answer one way and the save another. The defaults are failures, so a test
/// that builds a controller needing this dependency but does not exercise it is
/// not given a client that pretends to have worked.
class FakePornolabClient implements PornolabClient {
  FakePornolabClient({
    this.loginResult = const PornolabFailure(PornolabFailureKind.loginRefused),
    this.saveResult = const PornolabFailure(PornolabFailureKind.noCredentials),
  });

  PornolabResult loginResult;
  PornolabResult saveResult;

  /// A test that wants a call not to finish gives a completer instead of a
  /// result, so what a widget holds while a call is running is observable.
  Completer<PornolabResult>? loginPending;

  /// What each login was given, as the log directory, the username, the password,
  /// the captcha's field name and the code. The last two are empty for the login
  /// that asks for neither, which is the shape a run makes.
  final loginCalls = <List<String>>[];

  /// What each save was given, as the cookie, the forum id, the draft id, the
  /// subject and the message.
  final saveCalls = <List<Object>>[];

  @override
  Future<PornolabResult> login({
    required String logDirectory,
    required String username,
    required String password,
    LoginCaptcha? captcha,
    String code = '',
  }) async {
    loginCalls.add([
      logDirectory,
      username,
      password,
      captcha?.fieldName ?? '',
      code,
    ]);

    return loginPending != null ? loginPending!.future : loginResult;
  }

  @override
  Future<PornolabResult> saveDraft({
    required String releaseDirectory,
    required String cookie,
    required int forumId,
    required int draftId,
    required String subject,
    required String message,
  }) async {
    saveCalls.add([cookie, forumId, draftId, subject, message]);

    return saveResult;
  }
}
