import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/app_info.dart';
import 'feature/upload/hosters.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // `--dev` replaces the real hosters with the mock ones, so a development run
  // uploads to the Python test server (`test-hoster/rp_test_hoster.py`) instead
  // of to a real hoster (`ai/upload_images.md`). It is read here, before the
  // app is built, because nothing else in the app takes it as a parameter.
  devMode = args.contains('--dev');

  // The app-close handler needs the window to exist before it can register the
  // close callback.
  await windowManager.ensureInitialized();

  // The native window title. `MaterialApp.title` is not the window title on the
  // desktop runners, so it is set here.
  await windowManager.setTitle(appName);

  runApp(const App());
}
