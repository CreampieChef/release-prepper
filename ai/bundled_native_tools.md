# Bundled native tools

The app ships `uptooda-cli` and `mkbrr`, rather than asking the user to install
them, and it ships the media tools — `ffmpeg`, `ffprobe` and `mtn` — for
Windows. Everything committed under `native/` is installed next to the app
executable. Nothing is committed for the media tools on the other platforms, so
there they remain the user's tools.

The path fallback is what separates the two kinds:

- `uptooda` and `mkbrr` are resolved from the bundle only, because a system
  install is not an acceptable substitute for either.
- `ffmpeg`, `ffprobe` and `mtn` are read from the bundle first and from PATH
  when the bundle has nothing there, because the app can use either copy.

# uptooda

`uptooda-cli` uploads images to photo hosters (`ai/upload_images.md`). The app
bundles it because the upload scripts it relies on are the modified ones in the
tool's `Data/`. A system install has the stock scripts, so it is not an
acceptable substitute and the tool is resolved from the bundle only.

The committed builds have no library dependencies. What the Windows build needs
at runtime is three data files beside the binary, and the Linux build gets the
same from the system or has no equivalent, so nothing is committed for it there.
The tool's own Windows package installs all three; its Linux package installs
none, which is the same asymmetry:

- `curl-ca-bundle.crt` is the CA bundle libcurl is pointed at with
  `CURLOPT_CAINFO`, under a branch that is compiled only for Windows with
  OpenSSL, which the committed Windows build uses. The path is built from the
  directory of the executable, so the file has to be beside the binary. Without
  it every HTTPS request fails with a certificate error, which is what the app's
  uploads did before the file was bundled. The Linux build does not compile that
  branch and uses the system trust store. A committed bundle is a snapshot of
  Mozilla's certdata, so it goes stale over time; the system store does not.
- `Data/mime.cache` is the binary cache of the shared-mime-info database. The
  tool points the MIME library at its own `Data/` only on Windows, so the cache
  is committed only there; on Linux the library reads the system database
  through `XDG_DATA_DIRS` and `/usr/share/mime`. With no database the tool
  guesses from the extension, so every file looks like the wrong type and the
  `Content-Type` it sends is wrong. A minimal Linux system without
  shared-mime-info degrades the same way.
- `WebView2Loader.dll` is the loader for the WebView2 runtime, which the
  scripting API's `CWebBrowser` needs; only the Windows build has a browser at
  all. None of the hosters the app offers uses `CWebBrowser`, so no app call
  needs it today — the scripts that do are the OAuth ones (`dropbox`,
  `onedrive`, `vk`, `bit.ly`). It is committed for parity with the tool's own
  Windows package.

## Resolution

uptooda is resolved from the app bundle only, with no fallback to PATH. A tool
the app ships is declared with a bundle directory and no path fallback, so a
system install of it is never used. The three tools with a path fallback are
`ffmpeg`, `ffprobe` and `mtn`, described below.

## The `Data/` directory

The tool is hardcoded to look for a `Data/` directory in its own location. This
does not depend on the working directory, so the app does not have to set one.

In a system install `Data/` is read-only, because the user cannot write to the
installed files. Some operations of the tool can modify it; the app does not use
those, so it never writes there. Changing it means editing the installed files
with root privileges.

## Layout

The tool is kept in `native/uptooda`. `Data/` is shared between the OSes and is
stored once, copied to the same directory as the binary for each OS. The per-OS
directories are named after the OS, as the other bundled tools name theirs. The
three Windows-only files described above are kept in the Windows directory, and
`mime.cache` is under a `Data/` there because that is where the tool reads it:

```
native/uptooda/
  Data/                        shared, stored once
  linux/uptooda-cli
  windows/
    uptooda-cli.exe
    curl-ca-bundle.crt         Windows only
    WebView2Loader.dll         Windows only
    Data/mime.cache            Windows only
```

The prebuilt binaries are committed with the executable bit, and the install
step preserves it. `install(FILES)` does not: it copies with default
permissions, so the binary is installed with `install(PROGRAMS)`. A binary
without the bit is not a tool, so the resolver does not find it and the app
reports the tool as not being available.

A working copy of the binary is kept at the top of `native/uptooda/` so the tool
can be run from the repo, since it looks for `Data/` in its own directory. That
copy is gitignored; the per-OS binaries are not.

In the built app the tool and its data sit together in one directory next to the
app executable, which is what the hardcoded path requires:

```
<app directory>/uptooda/uptooda-cli
<app directory>/uptooda/Data/
```

On Windows the shape is the same and the binary carries the extension it has
there: `<app directory>/uptooda/uptooda-cli.exe`. `ToolLocator` looks for the
name with the extension on Windows, so the tool is found under either name. The
Windows install step copies the same tool and the same `Data/` next to the
executable, plus the three Windows-only files: the two beside the binary, where
the tool looks for them, and `mime.cache` into the same `Data/` the shared files
go to, so the tool's `Data/` in the bundle is the shared files plus the cache.
The execute bit is a Linux rule, so there `install(PROGRAMS)` is the same rule
written the same way, and `install(FILES)` is right for the three files.

### Development

A running app resolves the tool from the directory next to its own executable,
which during a development run is the build output. `Data/` is therefore read
from the copy the install step made at build time, not from `native/uptooda/`.

A script is read when a call starts, so a change to
`native/uptooda/Data/Scripts/*.nut` is picked up by the next call — but only
from that copy, and a hot reload or a hot restart does not run the build again.
Changing a script therefore needs a full restart of the app.

## Hosters

The name passed to `--server` is the `Server Name` from `Data/servers.xml`. The
hosters the app offers are `fastpic.org`, `turboimagehost.com`, `pixhost.to` and
`postimages.org`; started with `--dev` it offers the two test hosters `rptest-a`
and `rptest-b` instead, described below. `fastpic_custom` and
`turboimagehost_custom` are the modified scripts, which is the reason for
bundling; `pixhost.to` uses its stock script, and `postimages.org` is modified
to read its credential from the environment (see Credentials below).

In `servers.xml`, `Authorize="1"` means authentication is optional and
`Authorize="2"` means it is required. A credential is passed only to the hosters
whose script reads one, and only Postimages does.

Development runs and tests call only the `rpstub` host and the two test hosters,
because the app is run with `--dev`, which replaces the real hosters with them
(`ai/upload_images.md`).

## Credentials

A credential is passed to the tool through the environment variable
`UPTOODA_HOSTER_API_KEY`, never as a command-line argument.

* Command-line arguments are readable by every user on the machine while the
  process runs — `/proc/<pid>/cmdline` on Linux, the process list on Windows. A
  process environment is readable only by its owner. Root and anything that can
  trace the process can still read it, so this is the best the app can do, not a
  guarantee.
* `ToolRunner` records the arguments of a call on every log entry, so a key
  passed as an argument is written to the log file once per output line and
  stays there. A key passed through the environment is not part of the recorded
  input, so the log holds no copy of it.

The variable is set per call, only for the calls that need it, and only for that
child process. `ToolRunner.run` takes the entries a call adds, and Dart merges
them with the environment of the app process, so a call that has no use for the
value is not given it. It is not put in the app's own environment, because every
tool call inherits it.

Which hoster needs a credential is data in `lib/feature/upload/hosters.dart`: a
`Hoster` records the settings service whose value its script reads, and only
Postimages has one. A hoster whose value is empty is not offered as selected, so
the app never calls a script with an empty credential.

A script that reads the variable must use it and never write it to the log.
`WriteLog` goes to stderr, which the app records, so a script that prints the
value puts it back in the log file.

`getenv` is present in the script API of both committed builds, so a modified
script can use it under the same rule as the argument list: anything a modified
script uses must be present in every build.

`Data/Scripts/postimages.org.nut` reads the variable. Its `GetServerParamList`
still reports `apiKey` as a server parameter, which is what the tool's own
settings UI and `settings_cli.xml` use; the app does not read that file and does
not pass `--param_list`, so the value reaches the script only through the
environment.

## Arguments

The app passes:

```
uptooda-cli --server <hoster> --code_lang json --thumb_width 300 <file>
```

One file per call. The System Check calls the same binary with `--version`.

The argument list may only use flags present in every bundled build. Both
committed builds are the same version, so a flag that version has is present in
both; the flags the app passes are present on each, which was checked on the
Linux build by running it with them and on the Windows build from the help text
the binary holds.

`--code_lang` is always `json`, so the result is read from fields rather than
from prose. `--code_type` is not passed: it only changes the bbcode form, and
the app builds bbcode itself. `--thumb_width` is 300, the width the app uses for
thumbnail links.

## Version

Both committed binaries are the same version, 1.4.8, the latest release of the
tool at the time of writing. `--version` reports it on the Linux binary; the
Windows binary holds the same version string in its help text. The earlier Linux
binary, 1.4.6, is no longer committed.

## Calling

One image to one hoster per call, and one image at a time per hoster
(`perHosterLimit`, `lib/feature/upload/upload_controller.dart`). Several hosters
run at the same time. The shape is deliberate: a call has one result, so a
failure affects one image rather than a batch. Some hosters accept more than one
image at a time, so the per-host limit is a rule that can be raised later.

Passing several files in one call is possible, because the JSON result names
each file. The app does not do it.

The app does not retry; the tool's built-in retries are used with their default
values. A call can therefore take a long time, so the runner stops it at the
window it is given — 60 seconds for an upload call — and reports a timeout, and
the Upload section shows a busy state with a progress bar per hoster. The window
is the caller's, so a call that is long for another reason asks for its own:
`Mkbrr.create()` asks for 60 minutes, because hashing a whole release is not an
upload with retries (`ai/torrents.md`).

## Output

The tool reports `success`, `filename`, `delete_url`, `direct_url`, `thumb_url`
and `view_url` for each file. All four URLs are stored in `images.json`, so
bbcode can be built from them later: bbcode is what the post needs, and the app
builds it from the stored URLs rather than taking it from the tool.

With `--code_lang json` the streams are separated: stdout is the JSON result
only, stderr is the human-readable progress and the tool's messages. Progress
lines use carriage returns as well as newlines, so the app does not assume clean
lines.

A captured sample of the output is kept as a test fixture, as
`test/media_info_test.dart` does for ffprobe.

## Behaviour

The stream separation described above is the same on each build: stdout is the
JSON result only, stderr is the progress and the tool's messages, on a
successful upload and on a failed one. It was checked on the current Linux build
against the `rpstub` host, and the modified scripts run on it, including the
`getenv` call the Postimages script makes. The Windows build was checked by
running the app's command on a Windows machine, but that was the previous build;
the checks have not been re-run on the current one, and the encoding the Windows
build writes in has not been checked at all.

The current Windows build has been run on a Windows machine for uploads, and
they work with the three files beside the binary. Without `curl-ca-bundle.crt`
the uploads failed with a certificate error, which is the failure that file
prevents. The stream separation and the exit codes have not been re-checked on
this build.

The tool makes its own network requests; the app cannot see or control them.
`ImageDownloader` remains the only Dart code in the app that makes a network
request.

## Exit code

Checked on the current Linux build against the `rpstub` host, and on the
previous Windows build on a Windows machine; the codes were the same on each.
The Windows codes have not been re-checked on the current build:

* upload succeeded — exit 0, JSON on stdout with `success: true`
* upload failed after the retry limit — exit 1, JSON on stdout with
  `success: false`
* unknown hoster — **exit 0**, with only `No such server 'x'!` on stderr and no
  JSON on stdout

So the exit code is not enough on its own. Success is decided by the `success`
field in the JSON, and an unknown hoster is recognised by the absence of a
result.

The app records every call in `<release_dir>/logs/`, as `ai/upload_images.md`
describes.

## Test host and test hosters

The `rpstub` host is a fake server added for uptooda. It makes no requests
anywhere, so it is what development runs and tests use; the `invalid` host is
what a test uses to check an incorrect hoster. Its behaviour:

* an image whose name contains `fail` fails the upload;
* `--server_param successful_attempt:2` makes the upload succeed only on the
  second attempt. That counter counts attempts across every image, which is not
  a problem because the app uploads one image at a time.

`test-hoster/rp_test_hoster.py` is a small HTTP server that answers as a photo
hoster, and `rptest-a` and `rptest-b` are the two hosters that call it. It is
run by hand:

```
python3 test-hoster/rp_test_hoster.py --latency 200 --success-rate 0.9
[--port 80]
```

Every upload takes `--latency` milliseconds on average, each one deviating by up
to half either way, and succeeds with probability `--success-rate`. A failed
upload is reported as `success: false` rather than as an error status, because
that is the shape the app reads. Serving is not simulated: a stored file, a
thumbnail, a view page and a delete are answered at once, so a test run is not
slowed by reading the images back. The server is threaded, because several
hosters call it at the same time.

One server answers as several hosters, and the tag that tells them apart is
hardcoded in each script: the script API cannot read the `Server Name`, so there
is one script per test hoster and they differ only by that tag. The tag is also
the folder the images are stored in.

Files are stored next to the script, under `test-hoster/photos/<tag>/`
(gitignored), as the name the upload was given with a random id before the
extension. The thumbnail is the stored name with `_thumb` before its extension,
always a JPEG, made with ffmpeg at the width the script sends as the
`thumb_width` field, which is what `--thumb_width` gives. There is no fallback
when ffmpeg is not on PATH: the upload fails.

Every URL the response reports is `<host>/<tag>/<stored name>`, and the server
serves those paths back: the file, the thumbnail, and a minimal HTML page for
the view URL, which is the stored name with `.html`. The delete URL is the same
path with `?delete=1`, and it really removes the stored file and its thumbnail.

The scripts hardcode `http://127.0.0.1`, the default http port, because the URLs
the server reports must be on it: PornoLab does not render images hosted on
other ports, so a test run whose reported URLs carry a port suffix cannot be
checked on the site. The server therefore reports URLs without a port suffix on
the default port, and a different `--port` needs the scripts changed too. Port
80 needs elevated privileges. The two hosters are the mock hosters in
`lib/feature/upload/hosters.dart`: they replace the real ones when the app is
started with `--dev` (`ai/upload_images.md`), so a development run uploads to
them rather than to a real hoster. They have no icon asset, so the section draws
them with the placeholder `HosterIcon` shows. The test server has to be running
for them to work. Start the app in dev mode with:

```
flutter run --dart-entrypoint-args=--dev
```

which is how `flutter run` passes arguments to `main(List<String> args)`,
desktop only. A built binary takes it directly:
`./build/linux/x64/release/bundle/release_prepper --dev`.

## Open questions

* What encoding the Windows build writes in. `ToolRunner` decodes both streams
  as UTF-8, so a build that writes in the OEM codepage puts replacement
  characters in the log for non-ASCII progress text; the JSON itself is
  ASCII-safe, so parsing is not at risk.
* The tool's license, which is not recorded in the repo.
* Re-running the Windows checks against the current build: the stream separation
  and the exit codes were checked on the previous build. Uploads have been run
  on the current one, but not the checks above. There is no macOS build.
* When to refresh `curl-ca-bundle.crt`. It is a snapshot of Mozilla's certdata,
  so it goes stale, and nothing in the repo records when the committed copy was
  taken.

# mkbrr

`mkbrr` creates torrent files for a release (`ai/torrents.md`). The app bundles
it rather than asking the user to install it, so the version it calls is the one
it ships. The committed binaries are statically linked — the Windows one imports
only `kernel32.dll` — and no runtime dependencies are known for them.

## Resolution

mkbrr is resolved from the app bundle only, like uptooda: a tool declared with a
bundle directory and no path fallback is never read from PATH
(`lib/service/native_tools/tool_locator.dart`).

## Layout

There is no shared data, so only the binary is committed, in `native/mkbrr`,
with the executable bit, and the install step preserves it with
`install(PROGRAMS)`:

```
native/mkbrr/
  linux/mkbrr
  windows/mkbrr.exe
```

In the built app the binary is installed in its own directory next to the app
executable:

```
<app directory>/mkbrr/mkbrr
```

A Linux and a Windows binary are committed; macOS is not, so there the resolver
reports the tool as not present.

## Arguments

```
mkbrr create <path to file or folder> --private=true --output <output file>
```

`--output` is given explicitly rather than left to the default, because the
default is `<source basename>.torrent` written in the working directory and
`ToolRunner` does not set one; the default name is also the source basename
rather than the release name. The app passes no tracker, comment, or piece
length.

## Version

The bare command prints its banner and its usage and exits 0, with no version in
the output, so the System Check uses the `version` subcommand: its first line is
the version and it exits 0, which is what the existing rule needs.

## Output and progress

Everything goes to stdout; stderr was empty in every run checked. The progress
line is redrawn with carriage returns, and the ANSI colour codes are present
even when stdout is not a terminal, so the app does not assume clean lines: it
reads one carriage-return-separated segment at a time and takes the percentage
from it.

A run that finishes in a few milliseconds prints the progress line once, at
100%, so the app cannot assume the numbers arrive in steps.

A captured sample of the output is kept as a test fixture, as
`test/media_info_test.dart` does for ffprobe.

## Exit code

Checked against the committed Linux binary:

* create succeeded — exit 0, the file is written
* the source does not exist — exit 1, with the message on stderr

So the exit code is enough here, unlike mtn's.

## Open questions

* The version the committed binary was built from (1.27.0 at the time of
  writing) and the tool's license. Neither is recorded in the repo.

# ffmpeg and ffprobe

The app calls ffmpeg for the video thumbnail, the poster image and the
screenshots, and ffprobe for a file's metadata. The Windows build is committed;
on the other platforms these are the user's tools, and nothing in the build step
installs them.

## Resolution

The app looks in the bundle first and reads from PATH when the bundle has
nothing there. Either copy is the same tool, so a system install is an
acceptable substitute for the media tools — which is why the fallback is a flag
on `NativeTool` rather than the rule for every tool with a bundle directory, and
why the two tools resolved from the bundle only have none.

The resolver checks the directory when a call starts, not when the app starts,
so a copy added while the app is running is used by the next call. The System
Check tab runs its check when the tab opens and not again after that, so
reopening the tab is what shows a copy added by hand.

## Layout

One directory holds all three media tools, because they load one shared set of
DLLs, and the loader looks in the executable's own directory first: the DLLs
have to be beside the binaries. A directory with only the executables runs only
while the libraries are on PATH, which is not a bundle.

```
native/media/windows/
  ffmpeg.exe
  ffprobe.exe
  mtn.exe
  <the DLLs the three load>
```

In the built app:

```
<app directory>/media/
```

The committed set is the whole closure, not only the direct imports: a DLL
needed by a DLL is still needed, and the MinGW runtime DLLs
(`libgcc_s_seh-1.dll`, `libwinpthread-1.dll`, `libstdc++-6.dll`) are part of it
and are not in System32. A missing one is silent, because the failure happens
in the loader before the program's own code runs, so nothing can print which
one; the app reports it as the tool not being available. What shows whether a
directory is complete is running it with PATH stripped to the system
directories.

No installable runtime dependency is needed on Windows 10 or later. The only
imports the three executables have outside the directory are `msvcrt.dll` and
`KERNEL32.dll`, both in System32; everything else they import is in the
directory. The Visual C++ Redistributable is not a dependency here, because
it is a packaged set of DLLs and the bundle supplies its own.

The font the screenlist draws with is not part of this directory: the tool finds
it as a file, not through the libraries, so a directory that is complete for the
libraries is not complete for the text. A font that cannot be opened is a wrong
result rather than a failure: the screenlist is still written, without the info
text. The font the app ships, and how the tool is given it, is the `mtn`
section's Font section.

A file in the bundle is accepted as a tool on the same terms as one on PATH: the
execute bits. A copy without them is not something `Process.start` can run, so
it is not found and the tool is read from PATH instead. On Windows there are no
execute bits, so the check there is the extension, and the name with the
extension is the one tried first, there as on PATH.

The Linux build step empties the bundle directory on every build, so a copy put
there by hand is gone at the next one. The Windows install step does not empty
it, but it installs the committed directory, so a rebuild replaces what is in
it. During a development run the directory the app runs from is the build
output for that run, so a copy has to be put in the one the app is actually
running from.

# mtn

`mtn` (Movie Thumbnailer) writes the frame grid the preview shows, the
screenlist (`ai/video_pack.md`). The Windows build is committed; on the other
platforms it is the user's tool, and nothing in the build step installs it.

## Resolution

The same rule as ffmpeg and ffprobe: the bundle first, then PATH, and the same
terms for what counts as a tool there — the execute bits.

## Layout

mtn is in the same directory as ffmpeg and ffprobe, because the three load one
shared set of DLLs, as that section describes.

The app resolves the binary, not the libraries it needs, so a copy has to be
able to run from the directory it is put in. The Windows download is the `.exe`
with the DLLs it loads beside it, so the whole of it goes in that directory. A
Linux binary from a package manager keeps the library paths it was built with,
so it runs against the libraries installed elsewhere rather than against
anything in the bundle.

## Font

The app ships the font, and the app's own UI text is made to use it. Flutter
resolves a font declared under `flutter: fonts:` in `pubspec.yaml` before the
platform font manager, but `Typography` picks the family by platform — Segoe UI
on Windows, SF Pro on macOS, Roboto on Linux — so the declaration only takes
effect where the theme happens to ask for that family. The app's theme asks for
`Roboto` itself (`lib/app/app.dart`), which is what makes the UI draw with the
same font on all three platforms. Regular and Bold are committed, about 350 KB,
with `Roboto_LICENSE.txt` (Apache 2.0). The committed files are the Google Fonts
release, taken from the Flutter SDK's cached material fonts. Only those two
weights exist, so a style that asks for a weight between them — `labelLarge` at
w500, which is what the menu uses — resolves to the nearer one, Regular.

The font is written into the app data directory on first use and the call is
given the path of the file (`lib/service/fonts/font_store.dart`). A file whose
length already matches the asset is left alone, so a run that generates
screenlists does not rewrite 170 KB for every video. Only the weight the tool
draws with is written there: the app's own text gets the same font from the
asset bundle, so the other weight is never read from that directory.

The tool is given a path rather than a name because libgd, which is what draws
the text, resolves a font name only through fontconfig's own configuration — the
one that names the system font directories — and does not read `FONTCONFIG_FILE`
or `FONTCONFIG_PATH`, so a configuration the app writes is not something it
sees. What it does resolve is a path. Verified on Linux: with a configuration
naming only the app's font directory, `fc-match` resolves the font and mtn does
not, while mtn still resolves the system font under that same configuration; and
mtn draws with a font given as an absolute path even with an empty
configuration. The Windows side has not been checked.

`-F` carries the info text colour and size only. Its font field is the timestamp
font and its fields are split on `:`, so a path with a drive colon cannot be
passed there, and an empty field is not accepted. The timestamp therefore takes
the tool's defaults. A path can be passed there on Linux, but the same argument
cannot work on both platforms, so it is not passed at all.

The font is not on the System Check, because a font that cannot be opened is not
a tool that is missing.

Two properties were checked before the font was chosen. Its digits are tabular —
the same advance for every digit, 1150/2048 em in Regular and 1175/2048 in
Bold, read from `cmap` and `hmtx` and confirmed through FreeType — which is what
the time text in the screenlist needs in order to line up. Its coverage is 896
codepoints, with Cyrillic complete and Greek partial, and no CJK, Hangul or
Arabic; a glyph outside the coverage draws as `.notdef`, a box, because libgd
resolves one font through fontconfig and does no per-glyph fallback, and
FreeType does not apply GSUB features, so the advances the tool uses are the
default ones. Whether CJK is in scope is not decided; a CJK font is about 18 MB
per weight.
