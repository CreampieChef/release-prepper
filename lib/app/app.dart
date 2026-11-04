import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../feature/main_menu.dart';
import '../feature/settings/settings_controller.dart';
import '../feature/tab/app_close.dart';
import '../feature/tab/tab_shortcuts.dart';
import '../feature/tab/tab_strip.dart';
import '../feature/tab/tab_view.dart';
import '../l10n/app_localizations.dart';
import 'app_info.dart';
import 'app_providers.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(providers: appProviders(), child: const AppRoot());
  }
}

/// The app language is app-level state the settings feature owns, so the locale
/// is read from the provider scope here. It has to be read inside the scope,
/// which is why this is its own widget: `App.build` runs above the providers it
/// installs. This is the one thing `app.dart` reads from the provider scope,
/// and it is recorded as a deviation from rule 8 in `ai/doc.md` §4.
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        // `Typography` picks the font family by platform — Segoe UI on Windows,
        // SF Pro on macOS — so a font declared in pubspec.yaml is only used
        // where the theme asks for that family. Asking for it here is what
        // makes the app draw its own text with the font it ships, on every
        // platform (`ai/bundled_native_tools.md`). Only Regular and Bold are
        // declared, so a style that asks for a weight between them, such as
        // `labelLarge` at w500, resolves to Regular.
        fontFamily: 'Roboto',
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // Null asks for the system locale, which is what the settings' `system`
      // option means.
      locale: settings.locale,
      home: const TabsPage(),
    );
  }
}

/// Composition point: it places the feature widgets. It implements nothing and
/// builds no dependencies — those come from `appProviders()`.
class TabsPage extends StatelessWidget {
  const TabsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // TabShortcuts is inside the Scaffold, not around it: the save flow shows a
    // message through ScaffoldMessenger, which the Scaffold provides.
    return AppCloseHandler(
      child: Scaffold(
        body: TabShortcuts(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const MainMenu(),
              const TabStrip(),
              Expanded(child: const TabView()),
            ],
          ),
        ),
      ),
    );
  }
}
