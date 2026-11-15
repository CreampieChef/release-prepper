import 'dart:io';

import '../../service/launcher/path_opener.dart';
import '../../service/native_tools/mkbrr.dart';
import '../../service/torrent/torrent_file.dart';
import '../../service/torrent/torrent_path.dart';
import '../release/release.dart';

/// The Torrent feature: a torrent for what the release is made of
/// (`ai/torrents.md`).
///
/// The controller owns the call, the paths, and the check for what is already on
/// disk; the widget shows the progress and maps the results to localized text
/// (rule 13). It is per-release, so the widget builds it, as the Upload section
/// does.
class TorrentController {
  TorrentController({
    required this.release,
    required this.mkbrr,
    required this.pathOpener,
  });

  final Release release;
  final Mkbrr mkbrr;
  final PathOpener pathOpener;

  /// The file the app writes: `<release name>.torrent` in the release
  /// directory. The name is the release name rather than the source basename,
  /// so a torrent made from a picked folder is named after the release.
  ///
  /// The file is an output, not a record: nothing is written to `release.json`
  /// or `images.json` about whether a run happened, so the file is the only
  /// thing that says one did, and a run writes over whatever is there. The
  /// Private flag is the one thing the app does record for this feature,
  /// because it is a choice the user makes rather than a result of a run
  /// (`ai/torrents.md`).
  ///
  /// After a post the release also has the file the tracker served, under the
  /// name the site gives it (`ai/pornolab_upload.md` §6). This is still the
  /// name this feature writes and shows, because the file it made is not taken
  /// away by a post.
  String outputPath() => torrentPath(release.directoryPath, release.name);

  /// The same file when it is already there, which is what a release opened
  /// again can have: the app records nothing for it, so the file is the only
  /// thing that says a run happened. A synchronous check, because the widget
  /// asks while it builds, the same way the poster box asks for its file.
  ///
  /// It is the path the app would write, not any `.torrent` in the folder: a
  /// file left under an older release name is not the one this release would
  /// write, and a run would write over it.
  String? existingTorrent() =>
      existingTorrentFile(release.directoryPath, release.name);

  /// The folder the file is in, for the link the section shows next to the path.
  Future<OpenPathResult> openDirectory() =>
      pathOpener.open(release.directoryPath);

  /// The Private flag as the file on disk states it (`ai/torrents.md`).
  ///
  /// A read, not a change: nothing is written, so a release opened again shows
  /// the flag its file has rather than the one the record holds. A synchronous
  /// read, because the widget asks while it builds, the same way the check above
  /// does. A file that is not a bencoded torrent is reported as such rather than
  /// guessed at.
  TorrentFlag privateFlag(String path) {
    try {
      return readPrivateFlag(File(path).readAsBytesSync());
    } catch (_) {
      // The file was there when the widget asked, but it may have gone or been
      // left unreadable between the two.
      return const TorrentFlagUnreadable();
    }
  }

  /// Change the flag of the file that is already there. The tool is asked for the
  /// name the app writes, so the file the run changes is the one the section
  /// shows.
  Future<MkbrrResult> modify({
    required String torrentPath,
    required bool private,
  }) => mkbrr.modify(
    releaseDirectory: release.directoryPath,
    torrentPath: torrentPath,
    outputName: release.name,
    private: private,
  );

  /// The source is whatever the user picked — a file or a directory, which is
  /// what the tool accepts. A source that no longer exists is not checked here:
  /// the tool reports it as a failed run, and the widget shows that.
  Future<MkbrrResult> create({
    required void Function(MkbrrProgress progress) onProgress,
  }) => mkbrr.create(
    releaseDirectory: release.directoryPath,
    sourcePath: release.source,
    outputPath: outputPath(),
    onProgress: onProgress,
  );
}
