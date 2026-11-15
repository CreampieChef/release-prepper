import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/app_info.dart';
import 'feature/upload/hosters.dart';
import 'service/logging/debug_text_log.dart';
import 'service/network/pornolab_client.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // `--dev` replaces the real hosters with the mock ones, so a development run
  // uploads to the Python test server under `testing-tools/test-hoster/`, not
  // to a real hoster (`ai/upload_images.md`). It is read here, before the app
  // is built, because nothing else in the app takes it as a parameter.
  devMode = args.contains('--dev');

  // The same shape for the tracker: `--dev-tracker-stub` makes every request go
  // to the Python stub under `testing-tools/pornolab-stub/` rather than to the
  // site (`ai/pornolab_upload.md` §11). It is a separate flag from the one
  // above because it chooses a different thing — the address the tracker
  // requests are made to, not which hosters the images go to — so a run can use
  // the mock hosters and the real site, or the stub and the real hosters.
  devTrackerStub = args.contains('--dev-tracker-stub');

  // The third flag read here, in the same shape as the two above:
  // `--unsafe-verbose-tracker-logging` decides whether the plain text copy is
  // written at all (`ai/uploading_draft.md` §8). It is called unsafe because
  // the two things that copy records are the two the app's logging rules keep
  // as markers — the cookie as its value and a page in full — and it writes
  // them into the release folder, so a run does it only when asked. The flag is
  // read here and nowhere else, for the reason rule 10 gives.
  verboseTrackerLogging = args.contains('--unsafe-verbose-tracker-logging');

  // The app-close handler needs the window to exist before it can register the
  // close callback.
  await windowManager.ensureInitialized();

  // The native window title. `MaterialApp.title` is not the window title on the
  // desktop runners, so it is set here.
  await windowManager.setTitle(appName);

  runApp(const App());
}
