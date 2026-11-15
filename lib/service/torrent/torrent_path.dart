import 'dart:io';

import 'package:path/path.dart' as p;

/// The name the app writes a release's torrent under (`ai/torrents.md`): the
/// release name with the extension, in the release directory. The name is the
/// release's rather than the source basename, so a torrent made from a picked
/// folder is named after the release.
///
/// It is a function rather than a method of one feature because two features
/// need the same name: the Torrent feature writes the file, and the Upload
/// draft feature sends it (`ai/pornolab_upload.md` §7). A second copy would be
/// a second rule.
String torrentPath(String directoryPath, String releaseName) =>
    p.join(directoryPath, '$releaseName.torrent');

/// The same file when it is already there, which is what a release opened again
/// can have: the app records nothing for a run, so the file is the only thing
/// that says one happened. A synchronous read, because a widget asks while it
/// builds.
///
/// It is the path the app would write, not any `.torrent` in the folder: a file
/// left under an older release name is not the one this release would write,
/// and a run would write over it.
String? existingTorrentFile(String directoryPath, String releaseName) {
  final path = torrentPath(directoryPath, releaseName);

  return File(path).existsSync() ? path : null;
}

/// The folder the app writes the tracker's copy in, inside the release. It is
/// the app's own folder, like the log's is, so it carries the app's prefix, as
/// the app's files do. A release that has been posted holds two `.torrent`
/// files: the one its own run wrote under the release name, and this one.
const trackerDirectory = '_rp_torrent';

/// The path the served file is written at (`ai/pornolab_upload.md` §6),
/// relative to the release directory, which is the shape a path inside a
/// release is recorded as (`ai/release_structure.md` §2). It is the path the
/// run wrote, so the record says which file the post wrote even when the file
/// is later named something else. The name inside the folder is the topic id,
/// as the site names the file it serves.
String trackerTorrentPath(int topicId) =>
    p.join(trackerDirectory, '[pornolab.net].t$topicId.torrent');
