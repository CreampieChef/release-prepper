import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../service/network/pornolab_client.dart';
import '../pornolab_results.dart';
import 'settings.dart';
import 'settings_controller.dart';

/// The sections the Settings page has. The left side lists them in this order,
/// so a new section is an entry here plus a case in `_content`. Private to this
/// file: nothing outside the page needs it.
enum _SettingsSection { general, integration }

/// The Settings page: the section list on the left, the selected section on the
/// right.
///
/// Which section is shown is widget state, like the hoster selection in the
/// Upload section; the settings themselves belong to `SettingsController`. The
/// sections are private widgets of this page because they share its controller
/// — a section with its own fields and its own state is the point where it
/// would become a file of its own.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// Below this width the section list is too narrow to read next to the
  /// content, so the page becomes one column, the same rule the editor form
  /// follows.
  static const _twoColumnMinWidth = 700;

  /// A settings field is not a page-wide box. Every control on the page is
  /// capped at this width, so a dropdown or a text box reads as a field rather
  /// than as the layout.
  static const _fieldMaxWidth = 400.0;

  /// The gap between the three controls on the login row.
  static const _rowGap = 12.0;

  /// The padding a text button draws its label with, which the app's theme does
  /// not override. It is part of the width the button takes on the row.
  static const _buttonPadding = 16.0;

  /// The narrowest a field on the row is drawn at. A field cannot show its label
  /// at a width the label does not fit in, and below that it cannot show what is
  /// typed into it either, so this is the point where the three controls stop
  /// fitting on one line and each becomes its own row.
  static const _fieldMinWidth = 160.0;

  /// The two fields drawn as one row. The row is drawn once, at the position of
  /// the first of them, and the second is part of it rather than a field on its
  /// own (`ai/pornolab_login.md` §3).
  static const _rowFields = [
    SettingsField.pornolabUsername,
    SettingsField.pornolabPassword,
  ];

  _SettingsSection _section = _SettingsSection.general;

  /// Resolved once, because `dispose()` needs it and by then the element is
  /// gone, so `context` cannot be used.
  late final SettingsController _settings;

  /// The fields show the model, so the widget owns their controllers and their
  /// focus nodes the way the editor does: each is seeded from the settings at
  /// first build, and the directory one is updated when the model changes from
  /// outside the field — which only a folder pick does.
  ///
  /// A settings field commits on submit, when it loses focus, and when the page
  /// is disposed. The last one is what makes closing the tab safe: a settings
  /// tab has no save step and no dirty flag, so text still in a field when the
  /// tab closes would be lost without the app ever saying it held something.
  final TextEditingController _directory = TextEditingController();

  final FocusNode _directoryFocus = FocusNode();

  /// One controller and one focus node per field, keyed by the key the value is
  /// stored under, so the loop over the fields has something to bind to.
  final Map<String, TextEditingController> _secrets = {};

  final Map<String, FocusNode> _secretFocus = {};

  /// The outcome of the last login the page made, shown next to the row in the
  /// colour that says which it was (`ai/pornolab_login.md` §3). It is the
  /// outcome of the last action, so a logout takes it away.
  PornolabResult? _result;

  /// The captcha the last answer asked for, shown below the row. It is what the
  /// next request is built from, so it is widget state rather than a stored
  /// value (`ai/pornolab_login.md` §3).
  LoginCaptcha? _captcha;

  /// The code the user typed. It is not a stored value and is not committed: it
  /// belongs to the page that asked for it, and a login with an empty one is the
  /// same answer again.
  final _captchaCode = TextEditingController();

  /// Whether a login is in progress, so the button cannot be pressed twice while
  /// a call is running.
  bool _busy = false;

  @override
  void initState() {
    super.initState();

    _settings = context.read<SettingsController>();

    // The row reads the controller rather than holding its own state, so a login
    // made through the controller changes what it shows: the fields become
    // disabled and the button becomes Log out.
    _settings.addListener(_rebuild);

    _directory.text = _settings.settings.defaultReleaseDirectory;

    _watchFocus(_directoryFocus, _directory, _commitDirectory);

    for (final field in SettingsField.values) {
      _secrets[field.name] = TextEditingController(
        text: _settings.secretValues[field.name] ?? '',
      );

      final focus = FocusNode();

      _secretFocus[field.name] = focus;

      _watchFocus(
        focus,
        _secrets[field.name]!,
        (value) => _commitSecret(field, value),
      );

      // The button is enabled only when both fields have text, so the page has
      // to rebuild when the user types: a field rebuilds itself, not the row it
      // is in, so without this the button would stay disabled until something
      // else rebuilt the page.
      if (_rowFields.contains(field)) {
        _secrets[field.name]!.addListener(_rebuild);
      }
    }

    // Whether the button can be pressed depends on the code when the page has
    // asked for one, so the code field needs the same notice the row's fields
    // have: a field rebuilds itself, not the row it is in.
    _captchaCode.addListener(_rebuild);
  }

  /// Commits the field's text when the user leaves it. The node also notifies
  /// when focus is gained, and when it is disposed during teardown — by then
  /// the page is gone, and `dispose()` has already committed, so only a lost
  /// focus while the page is there is a commit.
  void _watchFocus(
    FocusNode focus,
    TextEditingController controller,
    Future<void> Function(String) commit,
  ) {
    focus.addListener(() {
      if (!mounted || focus.hasFocus) {
        return;
      }

      unawaited(commit(controller.text));
    });
  }

  /// The page shows what the controller holds, so a change made from outside it
  /// — a login a run made — has to rebuild the row. The same notice is what a
  /// character typed into one of the row's fields rebuilds it through, because
  /// whether the button can be pressed is read from the fields.
  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _settings.removeListener(_rebuild);

    // The last commit point. It is deferred: notifying while the tree is being
    // unmounted marks the provider scope as needing build while the framework
    // is locked, which asserts. A write started here cannot be reported either
    // — there is no widget left to show a message — so a failed write only
    // shows up on the next start.
    final pendingDirectory = _directory.text;

    final pendingSecrets = {
      for (final field in SettingsField.values)
        field: _secrets[field.name]!.text,
    };

    scheduleMicrotask(() {
      unawaited(_commitDirectory(pendingDirectory));

      for (final entry in pendingSecrets.entries) {
        unawaited(_commitSecret(entry.key, entry.value));
      }
    });

    _directory.dispose();
    _directoryFocus.dispose();

    for (final controller in _secrets.values) {
      controller.dispose();
    }

    for (final focus in _secretFocus.values) {
      focus.dispose();
    }

    _captchaCode.dispose();

    super.dispose();
  }

  String _title(_SettingsSection section, AppLocalizations l10n) =>
      switch (section) {
        _SettingsSection.general => l10n.settingsGeneralSectionTitle,
        _SettingsSection.integration => l10n.settingsIntegrationSectionTitle,
      };

  String _fieldLabel(SettingsField field, AppLocalizations l10n) =>
      switch (field) {
        SettingsField.stashdb => l10n.stashdbApiKeyLabel,
        SettingsField.postimages => l10n.postimagesApiKeyLabel,
        SettingsField.pornolabUsername => l10n.pornolabUsernameLabel,
        SettingsField.pornolabPassword => l10n.pornolabPasswordLabel,
      };

  /// The word for the outcome of the last login. The words for a failure are the
  /// set the two features share (`../pornolab_results.dart`); the word for a
  /// login that worked is this page's, because a run has nothing to show for one
  /// — its success is the link it was given (`ai/pornolab_login.md` §8).
  String _resultText(AppLocalizations l10n) {
    final result = _result!;

    return result is PornolabFailure
        ? pornolabResultText(result.kind, l10n, _settings)
        : l10n.pornolabLoginAccepted;
  }

  Widget _sectionRow(_SettingsSection section, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final selected = section == _section;

    return InkWell(
      key: ValueKey('settings-section-${section.name}'),
      onTap: () => setState(() => _section = section),
      // A navigation row is flat and shows its own selected state; it is not a
      // button.
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.secondaryContainer : null,
        ),
        child: Text(
          _title(section, l10n),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: selected ? theme.colorScheme.onSecondaryContainer : null,
          ),
        ),
      ),
    );
  }

  Widget _sectionList(AppLocalizations l10n) {
    return Column(
      key: const ValueKey('settingsSections'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in _SettingsSection.values)
          _sectionRow(section, l10n),
      ],
    );
  }

  Widget _field(Widget control) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _fieldMaxWidth),
      child: control,
    );
  }

  /// The note that says where a value lives. It is a list of widgets so the loop
  /// can put it after the thing it describes — and the row gets one for itself
  /// rather than one for each field in it.
  List<Widget> _storeNote(SettingsController settings, AppLocalizations l10n) {
    if (settings.secretStoreAvailable || !settings.settings.allowPlainSecrets) {
      return const [];
    }

    final theme = Theme.of(context);

    return [
      const SizedBox(height: 8),
      Text(
        l10n.secretStoredPlainly,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  /// The width a string needs at a style. `TextPainter` is the only way to ask,
  /// and the styles are the ones the theme gives the controls on the row, so the
  /// answer is the same as what the widget draws in the language the app is in.
  double _textWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );

    painter.layout();

    return painter.width;
  }

  /// The row: the two fields and the button. The fields are capped at the same
  /// width as every other field on the page; what the row does is put the three
  /// controls on one line when they fit, and one control per line when they do
  /// not, because a field cannot show its label at a width the label does not
  /// fit in (`ai/pornolab_login.md` §3).
  Widget _pornolabRow(SettingsController settings, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final signedIn = settings.cookie.isNotEmpty;

    Widget field(SettingsField field) => TextFormField(
      key: ValueKey('secret-${field.name}'),
      controller: _secrets[field.name],
      focusNode: _secretFocus[field.name],
      // A credential cannot change while a session exists, so the row always
      // shows the account the cookie belongs to: changing one means logging
      // out first.
      enabled: !signedIn,
      obscureText: field.masked,
      decoration: InputDecoration(
        labelText: _fieldLabel(field, l10n),
        border: const OutlineInputBorder(),
      ),
      onFieldSubmitted: (value) => _commitSecret(field, value),
    );

    final button = TextButton(
      key: const ValueKey('pornolabLogin'),
      onPressed: _busy
          ? null
          : signedIn
          ? _logout
          : _canLogin()
          ? _login
          : null,
      // The red the page already uses for a failed write and the tab strip
      // for the unsaved-changes dot, on a button for the first time.
      style: signedIn
          ? TextButton.styleFrom(foregroundColor: theme.colorScheme.error)
          : null,
      child: Text(signedIn ? l10n.logoutButton : l10n.loginButton),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // The button takes its own width and the two fields share what is left,
        // capped the same way every other field on the page is. The button's
        // width is measured rather than assumed, so the point where the three
        // controls stop fitting is that point in the language the app is in:
        // "Выйти" is not the width of "Log out".
        final buttonWidth =
            _textWidth(
              signedIn ? l10n.logoutButton : l10n.loginButton,
              theme.textTheme.labelLarge!,
            ) +
            _buttonPadding * 2;

        final share = (constraints.maxWidth - buttonWidth - _rowGap * 2) / 2;

        if (share < _fieldMinWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(field(_rowFields.first)),
              SizedBox(height: _rowGap),
              _field(field(_rowFields.last)),
              SizedBox(height: _rowGap),
              button,
            ],
          );
        }

        final fieldWidth = share < _fieldMaxWidth ? share : _fieldMaxWidth;

        return Row(
          children: [
            SizedBox(width: fieldWidth, child: field(_rowFields.first)),
            SizedBox(width: _rowGap),
            SizedBox(width: fieldWidth, child: field(_rowFields.last)),
            SizedBox(width: _rowGap),
            button,
          ],
        );
      },
    );
  }

  /// The button is enabled when both fields have text, and when a code the page
  /// asked for has one typed into it — a login with an empty code is the same
  /// answer again, so there is nothing to send. A disabled field cannot commit,
  /// so this is the rule for the fields that can be edited.
  bool _canLogin() =>
      _rowFields.every((field) => _secrets[field.name]!.text.isNotEmpty) &&
      (_captcha == null || _captchaCode.text.isNotEmpty);

  Widget _generalSection(SettingsController settings, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // `DropdownMenu` rather than `DropdownMenuFormField`: there is no form
        // here and nothing to validate, so a form field would only add a Form
        // ancestor. `expandedInsets` is still needed, for the same reason the
        // wizard sets it: without it the menu is not the width of the box it is
        // in.
        _field(
          DropdownMenu<String>(
            key: const ValueKey('appLanguage'),
            initialSelection: settings.settings.language.name,
            label: Text(l10n.appLanguageLabel),
            expandedInsets: EdgeInsets.zero,
            inputDecorationTheme: const InputDecorationTheme(
              border: OutlineInputBorder(),
            ),
            onSelected: (value) => _chooseLanguage(value, l10n),
            // The languages in the order AppLanguage lists them. A language
            // names itself, so the labels are the same in both arb files for
            // the two translations that exist.
            dropdownMenuEntries: [
              for (final language in AppLanguage.values)
                DropdownMenuEntry(
                  value: language.name,
                  label: switch (language) {
                    AppLanguage.system => l10n.languageSystem,
                    AppLanguage.en => l10n.languageEnglish,
                    AppLanguage.ru => l10n.languageRussian,
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _field(
          TextFormField(
            key: const ValueKey('defaultReleaseDirectory'),
            controller: _directory,
            focusNode: _directoryFocus,
            decoration: InputDecoration(
              labelText: l10n.defaultReleaseDirectoryLabel,
              border: const OutlineInputBorder(),
            ),
            onFieldSubmitted: _commitDirectory,
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _pickDirectory(l10n),
          icon: const Icon(Icons.folder_open),
          label: Text(l10n.chooseSavePath),
        ),
      ],
    );
  }

  Widget _integrationSection(
    SettingsController settings,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!settings.secretStoreAvailable) ...[
          Text(l10n.secretStoreUnavailable),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                key: const ValueKey('allowPlainSecrets'),
                value: settings.settings.allowPlainSecrets,
                onChanged: (value) => _commitPlainSecrets(value == true),
              ),
              Expanded(child: Text(l10n.allowPlainSecretsLabel)),
            ],
          ),
          const SizedBox(height: 16),
        ],
        for (final field in SettingsField.values) ...[
          // The two credentials are one row, so the row is drawn once, at the
          // position of the first of its fields; the second is part of the row
          // rather than a field on its own.
          if (field == _rowFields.first) ...[
            _pornolabRow(settings, l10n),
            if (_result != null) ...[
              const SizedBox(height: 8),
              Text(
                _resultText(l10n),
                // The colour says which the outcome was: the red the page already
                // uses for a value that was not written, and a green for a login
                // that worked. `ColorScheme` has no success role, so this is the
                // only colour in the app that is not the theme's.
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _result is LoggedIn
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
              ),
            ],
            // The captcha is what the answer asked for, so the word comes first
            // and the image and the field after it: the code is read from the
            // image, and the same button is pressed again. Each captcha is a
            // different URL, so the key changes on its own and the rule in
            // `ai/doc.md` §5 about an image rewritten under the same name does
            // not apply here.
            if (_captcha != null) ...[
              const SizedBox(height: 12),
              Image.network(
                _captcha!.imageUrl,
                key: ValueKey(_captcha!.imageUrl),
                // The same rule every image widget in the app has: a load that
                // does not work is not an error the framework reports, it is
                // nothing shown. Here that means a code the user cannot read, so
                // the login is tried again.
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              _field(
                TextFormField(
                  key: const ValueKey('captchaCode'),
                  controller: _captchaCode,
                  decoration: InputDecoration(
                    labelText: l10n.captchaCodeLabel,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
            // The note is about the row as a whole, so it is said once for it
            // rather than once for each field in it.
            ..._storeNote(settings, l10n),
          ] else if (!_rowFields.contains(field)) ...[
            _field(
              TextFormField(
                key: ValueKey('secret-${field.name}'),
                controller: _secrets[field.name],
                focusNode: _secretFocus[field.name],
                // The flag is a display rule, not a storage rule: every field
                // here is stored the same way, and the username is the one shown
                // plainly (`ai/pornolab_login.md` §2).
                obscureText: field.masked,
                decoration: InputDecoration(
                  labelText: _fieldLabel(field, l10n),
                  border: const OutlineInputBorder(),
                ),
                onFieldSubmitted: (value) => _commitSecret(field, value),
              ),
            ),
            ..._storeNote(settings, l10n),
          ],
          // The same gap the General section puts between its fields, so the
          // fields read as separate fields rather than as one block.
          if (field != SettingsField.values.last) const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _content(SettingsController settings, AppLocalizations l10n) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title(_section, l10n), style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            switch (_section) {
              _SettingsSection.general => _generalSection(settings, l10n),
              _SettingsSection.integration => _integrationSection(
                settings,
                l10n,
              ),
            },
          ],
        ),
      ),
    );
  }

  Future<void> _chooseLanguage(String? value, AppLocalizations l10n) async {
    if (value == null) {
      return;
    }

    final language = AppLanguage.values.firstWhere(
      (item) => item.name == value,
    );

    _report(await _settings.setLanguage(language));
  }

  Future<void> _commitDirectory(String value) async {
    _report(await _settings.setDefaultReleaseDirectory(value));
  }

  Future<void> _commitSecret(SettingsField field, String value) async {
    _report(await _settings.setSecret(field.name, value));
  }

  /// The button's action. It commits the fields' text first, so a request is
  /// never built from values the model does not hold. When the page has asked for
  /// a code, the same button is the second half of the login: the request it
  /// makes carries the captcha the answer gave and what was typed into it.
  Future<void> _login() async {
    for (final field in _rowFields) {
      await _commitSecret(field, _secrets[field.name]!.text);
    }

    setState(() => _busy = true);

    final result = await _settings.login(
      captcha: _captcha,
      code: _captchaCode.text,
    );

    if (!mounted) return;

    setState(() {
      _busy = false;

      // The space next to the row shows the outcome of the last login, in the
      // colour that says which it was. A captcha is kept only for the answer that
      // asked for it, so any other outcome clears it — and a new captcha means a
      // new code, because the text typed belongs to the page that asked for the
      // previous one.
      _result = result;
      _captcha = result is PornolabFailure ? result.captcha : null;

      if (_captcha != null) {
        _captchaCode.clear();
      }
    });
  }

  /// Logging out does not call the site. The app has no session of its own
  /// beyond the value it stored, so removing the value is what logging out means
  /// for it (`ai/pornolab_login.md` §3). A captcha cannot be showing here: the
  /// button is Log out only when a cookie is stored, and an answer that asks for
  /// a code stores none. The word for the login that made the session goes with
  /// the session, because the space says the outcome of the last action and a
  /// logout that works says nothing, as it does now.
  Future<void> _logout() async {
    setState(() => _result = null);

    _report(await _settings.setSecret(pornolabCookieKey, ''));
  }

  Future<void> _commitPlainSecrets(bool value) async {
    _report(await _settings.setAllowPlainSecrets(value));
  }

  /// A failed write is reported only while the widget is still there. A commit
  /// that happens during `dispose()` has no widget left to show a message, so
  /// it shows up on the next start, when the file is read again.
  void _report(SettingsSaveResult result) {
    if (result is! SettingsSaveFailure || !mounted) {
      return;
    }

    final l10n = AppLocalizations.of(context)!;

    _showMessage(switch (result.kind) {
      SettingsFailureKind.secretStoreUnavailable =>
        l10n.secretStoreNotAvailable,
      SettingsFailureKind.writeFailed => l10n.settingsSaveFailed,
    });
  }

  Future<void> _pickDirectory(AppLocalizations l10n) async {
    final typed = _directory.text.trim();

    try {
      final picked = await FilePicker.getDirectoryPath(
        dialogTitle: l10n.chooseSavePath,
        initialDirectory: typed.isEmpty
            ? _settings.defaultReleaseDirectory
            : typed,
      );

      if (picked == null || !mounted) {
        // Cancelling the picker is not an error.
        return;
      }

      final result = await _settings.setDefaultReleaseDirectory(picked);

      // A pick changes the model from outside the field, so the text has to
      // follow it. A commit from the field itself already shows what the user
      // typed, so nothing is echoed back.
      _directory.text = picked;

      _report(result);
    } catch (_) {
      if (mounted) {
        _showMessage(l10n.folderPickerFailed);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsController>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final list = Padding(
          padding: const EdgeInsets.all(12),
          child: _sectionList(l10n),
        );

        if (constraints.maxWidth < _twoColumnMinWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              list,
              Expanded(child: _content(settings, l10n)),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 200, child: list),
            Expanded(child: _content(settings, l10n)),
          ],
        );
      },
    );
  }
}
