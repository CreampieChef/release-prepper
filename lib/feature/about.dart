import 'package:flutter/material.dart';

import '../app/app_info.dart';
import '../l10n/app_localizations.dart';

class AboutPopup extends StatelessWidget {
  const AboutPopup({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.about),
      content: Text('$appName $appVersion'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
