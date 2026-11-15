import '../../service/network/pornolab_client.dart';
import '../../service/torrent/torrent_path.dart';
import '../message/message_store.dart';
import '../release/field_validation.dart';
import '../release/release.dart';
import '../release/release_fields.dart';
import '../release/release_type.dart';
import '../settings/settings_controller.dart';

/// The Upload draft feature (`ai/uploading_draft.md`): the title and the
/// message as a draft topic on the site, and the post that makes the topic
/// (`ai/pornolab_upload.md`).
///
/// It owns the values the requests are built from and the calls themselves; the
/// widget shows the field, the links and the outcome, and maps a result to
/// localized text (rule 13). It is per-release, so the widget builds it as the
/// other sections do, and it owns no `Listenable` (rule 3).
///
/// The cookie is not held here: it is read from `SettingsController` per call,
/// so this holds nothing that can change while the app is running. That read is
/// the deviation recorded in `ai/doc.md` §4 — the first controller that depends
/// on another controller — and a session controller between the two is the
/// alternative which for one read is the abstraction rule 3 refuses.
///
/// The name of the file a post sends is not decided here either: it is the
/// Torrent feature's rule, so it is read through `torrent_path.dart` rather
/// than written again.
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

  /// Whether there is a file to send — the one the app's own run wrote, because
  /// a post is not made before a run has produced a file to carry
  /// (`ai/pornolab_upload.md` §7). A synchronous read, as the other gates are,
  /// so a file a run made is seen by building again, and the notice the editor
  /// calls is what makes this controller read it again.
  ///
  /// The size and the extensions the form declares are not a gate: the app
  /// sends the file it has, and a file outside what the form declares is an
  /// answer, so that check is the client's and is read as the result it is
  /// (`ai/pornolab_upload.md` §3).
  bool hasFile() =>
      existingTorrentFile(release.directoryPath, release.name) != null;

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
  /// The gate is the cookie rather than the credentials, because the app does
  /// not make a login by itself (`ai/pornolab_login.md` §7), and a run has
  /// nothing to send without one. The app does not retry a run.
  Future<PornolabResult> run() async {
    final problem = _gate(withFile: false);

    if (problem != null) {
      return problem;
    }

    return _save(settings.cookie);
  }

  /// One post: the page the token comes from, the form with the file, and the
  /// file the tracker serves back for the topic the form made
  /// (`ai/pornolab_upload.md` §7). The last two calls cannot be reordered:
  /// there is no id before the form is answered.
  Future<PornolabResult> post() async {
    final problem = _gate(withFile: true);

    if (problem != null) {
      return problem;
    }

    return client.postTopic(
      releaseDirectory: release.directoryPath,
      cookie: settings.cookie,
      forumId: _forumId(),
      draftId: PornolabClient.draftIdFromUrl(release.fields.value('draftUrl')),
      subject: subject(),
      message: store.loadSync(release.directoryPath, MessageStore.messageFile),
      filePath: existingTorrentFile(release.directoryPath, release.name)!,
    );
  }

  /// The name the page gives for the forum the value names, for the label the
  /// row shows (`ai/pornolab_upload.md` §5). It is asked for once for a value
  /// the shape rule accepts, and the client keeps what it read for that value,
  /// so the row being drawn again is not another request.
  ///
  /// A value the rule refuses is not asked for at all, which is the same gate
  /// the run has: the row shows nothing, because the name is a label and the
  /// run works from the id the value names.
  Future<PornolabResult> readName(String url) => client.forumName(
    releaseDirectory: release.directoryPath,
    cookie: settings.cookie,
    url: url,
  );

  /// The checks both actions make before a request, in the order the section
  /// can be missing them: the cookie, then the forum, then — for a post — a
  /// file to send. They are the same rules the widget gates the buttons on, so
  /// a run is not reached with a value they refuse (`ai/pornolab_upload.md`
  /// §7); they are here as well because a run is what a result is read from,
  /// the same way `StashController` checks its input.
  PornolabFailure? _gate({required bool withFile}) {
    if (!hasCookie()) {
      return const PornolabFailure(PornolabFailureKind.noCookie);
    }

    final forumUrl = release.fields.value('parentForum');

    if (forumUrl.trim().isEmpty) {
      return const PornolabFailure(PornolabFailureKind.noForum);
    }

    if (PornolabClient.forumIdFromUrl(forumUrl) == null) {
      return const PornolabFailure(PornolabFailureKind.badForumUrl);
    }

    if (withFile && !hasFile()) {
      return const PornolabFailure(PornolabFailureKind.noFile);
    }

    return null;
  }

  int _forumId() =>
      PornolabClient.forumIdFromUrl(release.fields.value('parentForum'))!;

  /// The subject a run sends, which is what the popup names before a post: the
  /// title as the Message section holds it. A type with no title has no title
  /// file, so there is no subject to send.
  String subject() => hasTitle(release.releaseType)
      ? store.loadSync(release.directoryPath, MessageStore.titleFile)
      : '';

  Future<PornolabResult> _save(String cookie) => client.saveDraft(
    releaseDirectory: release.directoryPath,
    cookie: cookie,
    forumId: _forumId(),
    draftId: PornolabClient.draftIdFromUrl(release.fields.value('draftUrl')),
    subject: subject(),
    message: store.loadSync(release.directoryPath, MessageStore.messageFile),
  );
}
