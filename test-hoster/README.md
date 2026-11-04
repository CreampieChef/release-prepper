# Test photo hoster

A small HTTP server that answers as a photo hoster, for development runs and
tests. It is not part of the app and not part of the bundled native tools, so it
is run by hand:

    python3 test-hoster/rp_test_hoster.py --latency 200 --success-rate 0.9
    [--port 80]

Every upload takes `--latency` milliseconds on average, each one deviating by up
to half either way, and succeeds with probability `--success-rate`. Serving is
not simulated: a stored file, a thumbnail, a view page and a delete are answered
at once, so reading the images back is not throttled. The server is threaded,
because several hosters call it at the same time.

The `rptest-a` and `rptest-b` hosters in `native/uptooda/Data/servers.xml` call
this server with their own tag, so one server answers as several hosters; the
tag is also the folder the images are stored in. The scripts hardcode the
default http port, because the URLs the server reports must be on it — PornoLab does not
render images hosted on other ports — so a reported URL carries no port suffix,
and a different `--port` needs the scripts changed too. Port 80 needs elevated
privileges.

What is stored is the name the upload was given with a random id before the
extension, under `photos/<tag>/` next to this script (gitignored). Needs ffmpeg
on PATH to make the thumbnail; without it an upload fails.

The full rules are in `ai/bundled_native_tools.md`; the app's dev-mode hosters
are the mock list in `lib/feature/upload/hosters.dart`, chosen by the `--dev`
flag. Start the app in dev mode with:

    flutter run --dart-entrypoint-args=--dev
