import 'tool_locator.dart';
import 'tool_runner.dart';

/// The Movie Thumbnailer tool. Only the command the app uses is listed here.
class Mtn {
  Mtn({required this.runner});

  /// The app prefers its own copy and uses the user's when it has none, as
  /// `Ffmpeg` does. The Windows build is committed with the DLLs it loads, in
  /// the same directory as ffmpeg and ffprobe, because the three share one set
  /// (`ai/bundled_native_tools.md`).
  static const tool = NativeTool(
    name: 'mtn',
    bundleDirectory: 'media',
    pathFallback: true,
  );

  final ToolRunner runner;

  /// The version line the tool prints, used by the System Check tab.
  /// `-version` is not an option mtn accepts; `-v` is the one that prints the
  /// version. It prints it to stderr, and it exits with 255 because a run with
  /// no input file is an error to mtn, so the check reads what it printed
  /// rather than the exit code (see `SystemCheckController`).
  ///
  /// `-P` is on every call the app makes, this one included, for the reason the
  /// screenlist call gives: mtn pauses at the end on Windows, so a call without
  /// it runs until the runner stops it. A version call that is stopped is
  /// reported as a timeout rather than as the version it printed.
  Future<ToolRunResult> version({required String releaseDirectory}) =>
      runner.run(tool, const ['-v', '-P'], releaseDirectory: releaseDirectory);

  /// A screenlist: a grid of frames written as a JPEG named
  /// `_rp_screenlist.jpg` in [outputDirectory] (`ai/doc.md` §5). The flags and
  /// what each one is are listed there: 1200 px wide, 4 columns, [rows] rows, a
  /// 1 px gap, background 252525, info text upper left and time lower right, and
  /// the font the app ships (`FontStore`, `ai/bundled_native_tools.md`). `-q`
  /// prints only errors and `-P` stops it pausing at the end.
  ///
  /// [fontPath] is the path of the file `FontStore` writes. libgd resolves a font
  /// name only through fontconfig's own configuration, which names the system
  /// font directories and not anything the app controls, so the font reaches the
  /// tool as a path. A font it cannot open is not a failure — the file is still
  /// written, without the info text.
  ///
  /// `-F` carries the info text colour and size only. Its font field is the
  /// timestamp font, and its fields are split on `:`, so a Windows path with a
  /// drive colon cannot be passed there; the timestamp takes mtn's defaults.
  ///
  /// `-b 2` turns blank skipping off. With the default `-b 0.80` mtn skips a
  /// frame it reads as blank and leaves that cell empty, so the grid can end
  /// with an empty frame that is not a frame of the video; the app wants every
  /// cell filled.
  ///
  /// mtn exits with a non-zero code when it prints a warning, including for a
  /// skipped shot, even though it wrote the file, so the caller decides by the
  /// file rather than by the exit code.
  Future<ToolRunResult> screenlist({
    required String releaseDirectory,
    required String inputPath,
    required String outputDirectory,
    required int rows,
    required String fontPath,
  }) => runner.run(tool, [
    '-w',
    '1200',
    '-c',
    '4',
    '-r',
    rows.toString(),
    '-g',
    '1',
    '-k',
    '252525',
    '-b',
    '2',
    '-L',
    '4:2',
    '-f',
    fontPath,
    '-F',
    'FFFFFF:12',
    '-q',
    '-P',
    '-O',
    outputDirectory,
    '-x',
    screenlistName,
    '-o',
    '.jpg',
    inputPath,
  ], releaseDirectory: releaseDirectory);

  /// `-x` takes the name without the extension; `-o .jpg` adds it, so the file
  /// mtn writes is `_rp_screenlist.jpg`.
  static const screenlistName = '_rp_screenlist';
}
