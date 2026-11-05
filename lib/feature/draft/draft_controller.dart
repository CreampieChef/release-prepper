import '../../service/network/pornolab_client.dart';
import '../message/message_store.dart';
import '../release/field_validation.dart';
import '../release/release.dart';
import '../release/release_fields.dart';
import '../release/release_type.dart';
import '../settings/settings_controller.dart';

/// The Upload draft feature (`ai/uploading_draft.md`): the title and the
/// message as a draft topic on the site.
///
/// It owns the values the request is built from and the call itself; the widget
/// shows the field, the link and the outcome, and maps a result to localized
/// text (rule 13). It is per-release, so the widget builds it as the other
/// sections do, and it owns no `Listenable` (rule 3).
///
/// The cookie is not held here: it is read from `SettingsController` per call,
/// so this holds nothing that can change while the app is running. That read is
/// the deviation recorded in `ai/doc.md` §4 — the first controller that depends
/// on another controller — and a session controller between the two is the
/// alternative, which for one read is the abstraction rule 3 refuses.
class DraftController {
  DraftController({
    required this.release,
    required this.store,
    required this.client,
    required this.settings,
  });

  final Release release;

  /// The two text files the Message section owns. The draft sends what they
  /// hold, so the box is not read: the files are what that section shows, and
  /// they always match it.
  final MessageStore store;

  final PornolabClient client;

  /// The feature that owns the cookie. It is asked for the read only: a run
  /// does not log in (`ai/pornolab_login.md` §7).
  final SettingsController settings;

  /// Whether there is something to send. A synchronous read, because the widget
  /// asks while it builds, the same way the Upload section asks whether it has
  /// images to send.
  bool hasMessage() => store
      .loadSync(release.directoryPath, MessageStore.messageFile)
      .isNotEmpty;

  /// Whether a cookie is stored. The widget gates its button on this, and
  /// `run()` checks it too. The app does not log in by itself, because the site
  /// asks for a captcha after a few logins and the app cannot read one
  /// (`ai/pornolab_login.md` §7).
  bool hasCookie() => settings.cookie.isNotEmpty;

  /// The shape rule for the one field this feature owns, asked for that field
  /// rather than for the whole list: the required set of its type is not known,
  /// but the URL shape is the section's gate whatever the type is.
  FieldProblem? forumProblem() => fieldProblem(
    fieldListFor(release.releaseType).field('parentForum'),
    release.fields.value('parentForum'),
  );

  /// One run: the page the token comes from, then the call that saves the
  /// draft.
  ///
  /// The checks before the request are the same rules the widget gates the
  /// button on, so a run is not reached with a value they refuse. They are here
  /// as well because a run is what a result is read from, the same way
  /// `StashController` checks its input.
  ///
  /// The gate is the cookie rather than the credentials, because the app does
  /// not make a login: the login is the settings page's action, and a run that
  /// has nothing stored says where to make it (`ai/pornolab_login.md` §7). The
  /// app does not retry a run.
  Future<PornolabResult> run() async {
    if (!hasCookie()) {
      return const PornolabFailure(PornolabFailureKind.noCookie);
    }

    final forumUrl = release.fields.value('parentForum');

    if (forumUrl.trim().isEmpty) {
      return const PornolabFailure(PornolabFailureKind.noForum);
    }

    final forumId = PornolabClient.forumIdFromUrl(forumUrl);

    if (forumId == null) {
      return const PornolabFailure(PornolabFailureKind.badForumUrl);
    }

    return _save(settings.cookie, forumId);
  }

  Future<PornolabResult> _save(String cookie, int forumId) => client.saveDraft(
    releaseDirectory: release.directoryPath,
    cookie: cookie,
    forumId: forumId,
    draftId: PornolabClient.draftIdFromUrl(release.fields.value('draftUrl')),
    // A type with no title has no title file, so there is no subject to send.
    subject: hasTitle(release.releaseType)
        ? store.loadSync(release.directoryPath, MessageStore.titleFile)
        : '',
    message: store.loadSync(release.directoryPath, MessageStore.messageFile),
  );
}
