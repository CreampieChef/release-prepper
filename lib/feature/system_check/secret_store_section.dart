import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../section_title.dart';
import 'status_mark.dart';
import 'system_check_controller.dart';

/// The credential store section of the System Check page (`ai/doc.md` §2): its
/// title row, then the state the check ended with.
///
/// It is its own section rather than a row of the tool table because the
/// credential store is not a tool. The table's rows are the tools the app calls,
/// and every result in it is what a tool printed or the reason its run could not
/// be read; this check has neither — the store answered or it did not — so it has
/// its own title row and its own result type.
///
/// It is drawn only on Linux, the platform the app is primarily built for
/// (`ai/doc.md` §1). The settings page says the same thing on every platform, so
/// this section repeats the check only there. The flag the page draws on is the
/// one given to the controller rather than one read from `Platform` here, so the
/// decision can be tested on a machine that is not Linux.
///
/// The check is made when the section is built, which is the same moment the page
/// starts its calls, so it runs with them rather than after them, and its result
/// reaches this section as it arrives. Until then the row is the mark as a
/// spinner with nothing beside it, and it keeps that shape when the answer comes.
///
/// The result is this section's widget state; the controller owns the call and the
/// log entry, and the section maps the result to localized text and to a status
/// icon (rule 13). It holds nothing the user edits, so it is not part of Ctrl+S
/// and closes without the unsaved-changes popup.
class SecretStoreSection extends StatefulWidget {
  const SecretStoreSection({super.key});

  @override
  State<SecretStoreSection> createState() => _SecretStoreSectionState();
}

class _SecretStoreSectionState extends State<SecretStoreSection> {
  late final SystemCheckController _controller;

  /// What the check ended with. Null until it comes back, which is the row's
  /// spinner.
  SecretStoreCheck? _result;

  @override
  void initState() {
    super.initState();

    _controller = context.read<SystemCheckController>();

    unawaited(_run());
  }

  Future<void> _run() async {
    final result = await _controller.checkSecretStore();

    if (!mounted) return;

    setState(() => _result = result);
  }

  String _value(SecretStoreCheck result, AppLocalizations l10n) =>
      switch (result) {
        SecretStoreWorks() => l10n.systemCheckSecretStoreWorks,
        SecretStoreNotAvailable() => l10n.systemCheckSecretStoreNotAvailable,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      key: const ValueKey('secretStoreSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The title row has no action, because nothing here runs on a button: the
        // check is made once, when the section is built.
        SectionTitle(title: l10n.systemCheckSecretStoreTitle),
        const SizedBox(height: 12),
        // The row is the mark and the text, the same shape the table's rows have.
        // A failure is drawn with the error colour, as an error row is.
        Row(
          key: const ValueKey('secretStoreRow'),
          children: [
            StatusMark(
              isError: _result is SecretStoreNotAvailable,
              pending: _result == null,
            ),
            Expanded(
              child: _result == null
                  ? const SizedBox.shrink()
                  : Text(
                      _value(_result!, l10n),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _result is SecretStoreNotAvailable
                            ? theme.colorScheme.error
                            : null,
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
