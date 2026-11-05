import '../l10n/app_localizations.dart';
import '../service/network/pornolab_client.dart';
import 'settings/settings_controller.dart';

/// The words for a result the site gave, in the shape the app reads it.
///
/// Rule 13 keeps localized text in the widget that shows it, and this is the one
/// place the two features that show these results share the mapping: the
/// settings page for its button and the Upload draft section for a run read the
/// same set, so the words are one set rather than a set per feature
/// (`ai/pornolab_login.md` §8). `field_validation.dart` is the same kind of
/// shared mapping.
///
/// The two kinds a field's own rule gives are mapped here too, with the words
/// the field rule gives: `parentForum` has the same label for every release
/// type, so the words do not depend on the type and the settings page — which
/// has no release — can say them as well. They are unreachable there, because a
/// login has no field to fail.
String pornolabResultText(
  PornolabFailureKind kind,
  AppLocalizations l10n,
  SettingsController settings,
) => switch (kind) {
  // The checks before the request. The widgets gate on them, so a result is not
  // reached with a value they refuse; the arms are here because the set is one.
  PornolabFailureKind.noCredentials => l10n.pornolabNeedsCredentials,
  // The gate word and the result word for the login are the same string, as
  // they are for the field: the tooltip says it before the run and the section
  // says it after.
  PornolabFailureKind.noCookie => l10n.draftNeedsLoginFirst,
  PornolabFailureKind.noForum => l10n.fieldNotFilled(l10n.parentForumLabel),
  PornolabFailureKind.badForumUrl => l10n.parentForumInvalid(
    l10n.parentForumLabel,
  ),
  PornolabFailureKind.loginRefused => l10n.pornolabLoginRefused,
  PornolabFailureKind.captchaRequired => l10n.pornolabNeedsCaptcha,
  PornolabFailureKind.loginNoCookie => l10n.pornolabLoginNoCookie,
  // Which of the two words a value that was not written gets depends on whether
  // the credential store is reachable — the same choice the settings page makes
  // for its fields.
  PornolabFailureKind.valueNotStored =>
    settings.secretStoreAvailable
        ? l10n.settingsSaveFailed
        : l10n.secretStoreNotAvailable,
  PornolabFailureKind.cookieRefused => l10n.pornolabCookieRefused,
  PornolabFailureKind.noToken => l10n.pornolabNoToken,
  PornolabFailureKind.tokenRejected => l10n.pornolabTokenRejected,
  // The word for a run that could not make a draft where the stored one was.
  // The client makes the new draft itself, so this is only the answer that
  // refuses it too (`ai/uploading_draft.md` §6).
  PornolabFailureKind.draftGone => l10n.pornolabDraftGone,
  PornolabFailureKind.siteError => l10n.pornolabSiteError,
  PornolabFailureKind.badResponse => l10n.pornolabBadResponse,
  PornolabFailureKind.requestFailed => l10n.pornolabRequestFailed,
  PornolabFailureKind.timedOut => l10n.pornolabTimeout,
};
