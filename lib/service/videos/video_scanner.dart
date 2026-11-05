import 'dart:io';

import 'package:path/path.dart' as p;

import '../native_tools/ffprobe.dart';
import '../native_tools/media_info.dart';

/// The extensions the scan takes as a video file, matched case-insensitively. A
/// file outside the list is not an item and is reported by name, so an
/// accidental file in the picked folder is visible rather than silently
/// included (`ai/video_pack.md` §4).
const videoExtensions = {'mp4', 'mkv', 'webm', 'avi', 'mov', 'wmv'};

bool isVideoFile(String name) {
  final extension = p.extension(name);

  return extension.isNotEmpty &&
      videoExtensions.contains(extension.substring(1).toLowerCase());
}

/// One video the scan found: its path relative to the source, which is the ID
/// the image records link to (`ai/release_structure.md` §2), the size the file
/// has on disk, and what the probe says about it. Null info means the file could
/// not be probed — it is still an item, because the extension list is what
/// decides what a video is, and the scan reports it. Null size means the file
/// could not be stat'ed, which is the case the total does not count.
class ScannedVideo {
  const ScannedVideo({required this.path, required this.size, this.info});

  final String path;

  /// The size on disk, in bytes: the file as the walk sees it, not the container
  /// size the probe reports, which is what the item's `fileSize` field holds. The
  /// two are not the same number for every file, and the total is the size of the
  /// folder rather than a sum of what the probe reported.
  final int? size;

  final MediaInfo? info;

  /// The extension the file name has, lowercased. This is what the format
  /// aggregate is built from, deliberately not the container the probe reports:
  /// the post shows the format as the file name says, the item line shows what
  /// the container actually is, and a mislabelled file makes the two disagree
  /// (`ai/video_pack.md` §4).
  String get extension => p.extension(path).substring(1).toLowerCase();
}

/// One entry in the tree the walk reads. The scan is the only thing that uses
/// it, so it is private to the walk; there is no container format here to put
/// behind a reader interface.
class _Entry {
  const _Entry({required this.name, required this.isDirectory});

  final String name;
  final bool isDirectory;
}

/// What the walk collects as it goes: the items and the four lists the scan
/// reports. Private to the walk, like `_Entry` is. The source and the log
/// directory are the same for every directory the walk reads, so they are held
/// here rather than passed through each call; what a call varies is the
/// directory and the path prefix. Keeping the four lists as one thing is also
/// what keeps them from being passed in the wrong order, which compiles and
/// changes what is reported.
class _Found {
  _Found({required this.sourcePath, required this.releaseDirectory});

  final String sourcePath;
  final String releaseDirectory;

  final videos = <ScannedVideo>[];
  final skipped = <String>[];
  final emptyFolders = <String>[];
  final unreadable = <String>[];
}

/// The scan, called only when the user asks: opening a release is a read and
/// changes nothing (`ai/release_structure.md` §4). It walks the picked folder,
/// decides which files are items, probes each one, and reports what it could
/// not take. It writes nothing and shows no messages (rule 13): the controller
/// writes the items and the widget maps a result to localized text.
class VideoScanner {
  VideoScanner({required this.probe});

  final Ffprobe probe;

  /// `releaseDirectory` is where the tool log goes; the scan itself writes no
  /// files.
  Future<VideoScanResult> scan({
    required String sourcePath,
    required String releaseDirectory,
  }) async {
    final type = await FileSystemEntity.type(sourcePath);

    if (type == FileSystemEntityType.notFound) {
      return const VideoScanFailure(VideoScanFailureKind.sourceNotFound);
    }

    final found = _Found(
      sourcePath: sourcePath,
      releaseDirectory: releaseDirectory,
    );

    if (type == FileSystemEntityType.directory) {
      if (!await _walk(found, sourcePath, '')) {
        return const VideoScanFailure(VideoScanFailureKind.sourceNotReadable);
      }
    } else {
      // A picked file is treated as a directory containing only itself, so one
      // rule covers both (`ai/release_structure.md` §2).
      final name = p.basename(sourcePath);

      if (isVideoFile(name)) {
        found.videos.add(
          ScannedVideo(
            path: name,
            size: await _size(found, name),
            info: await _probe(found, name),
          ),
        );
      } else {
        found.skipped.add(name);
      }
    }

    return VideoScanSuccess(
      videos: found.videos,
      skipped: found.skipped,
      emptyFolders: found.emptyFolders,
      unreadable: found.unreadable,
    );
  }

  /// One directory, in name order, depth-first. Order only matters for what the
  /// scan reports, because the two aggregate lists are sorted
  /// (`ai/video_pack.md` §2, §4).
  ///
  /// Returns false when the directory could not be read. A folder inside the
  /// source is reported by name and the walk continues, as an unreadable set is
  /// (`ai/photoset_pack.md` §4); the picked folder itself is a failure, because
  /// there is nothing to report when it cannot be read.
  Future<bool> _walk(_Found found, String directoryPath, String prefix) async {
    final entries = <_Entry>[];

    try {
      await for (final entity in Directory(directoryPath).list()) {
        entries.add(
          _Entry(
            name: p.basename(entity.path),
            isDirectory: entity is Directory,
          ),
        );
      }
    } catch (_) {
      return false;
    }

    entries.sort((a, b) => a.name.compareTo(b.name));

    for (final entry in entries) {
      final relative = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';

      if (entry.isDirectory) {
        final before = found.videos.length;

        if (!await _walk(found, p.join(directoryPath, entry.name), relative)) {
          found.unreadable.add(relative);
          continue;
        }

        // A subfolder with no video anywhere in it is reported, as a set with
        // no photos is. A folder that could not be read is not one of these,
        // because the scan cannot say whether it had a video in it.
        if (found.videos.length == before) {
          found.emptyFolders.add(relative);
        }

        continue;
      }

      if (!isVideoFile(entry.name)) {
        found.skipped.add(relative);
        continue;
      }

      found.videos.add(
        ScannedVideo(
          path: relative,
          size: await _size(found, relative),
          info: await _probe(found, relative),
        ),
      );
    }

    return true;
  }

  /// One call per item, run one at a time with the existing per-call timeout
  /// (`ai/video_pack.md` §4). A file the probe cannot read has no values; the
  /// item is still recorded with its fields empty, and the scan reports it.
  Future<MediaInfo?> _probe(_Found found, String relative) async {
    final result = await probe.probe(
      releaseDirectory: found.releaseDirectory,
      filePath: p.join(found.sourcePath, relative),
    );

    return switch (result) {
      MediaProbeSuccess(info: final info) => info,
      MediaProbeFailure() => null,
    };
  }

  /// The size a file has on disk, as the walk sees it. A file that cannot be
  /// stat'ed — one that is gone by the time the walk reaches it — has no size,
  /// and the total does not count it, so the total is known to be incomplete in
  /// that case rather than presented as a fact. One file does not fail the scan,
  /// the same rule as a file the probe cannot read.
  Future<int?> _size(_Found found, String relative) async {
    try {
      return (await File(p.join(found.sourcePath, relative)).stat()).size;
    } catch (_) {
      return null;
    }
  }
}

sealed class VideoScanResult {
  const VideoScanResult();
}

final class VideoScanSuccess extends VideoScanResult {
  const VideoScanSuccess({
    required this.videos,
    required this.skipped,
    required this.emptyFolders,
    required this.unreadable,
  });

  /// The items, in the order the walk found them.
  final List<ScannedVideo> videos;

  /// Files the extension list does not accept, by their path relative to the
  /// source.
  final List<String> skipped;

  /// Subfolders with no video in them, by their path relative to the source.
  /// The picked folder itself is not one of these, because it is the source
  /// rather than a subfolder.
  final List<String> emptyFolders;

  /// Folders inside the source that could not be read, by their path relative
  /// to the source. They are reported rather than counted as empty, because the
  /// scan cannot say whether a folder it could not read had a video in it — so
  /// the counts are known to be incomplete.
  final List<String> unreadable;

  /// The size of the items as the files on disk, summed. This is what the folder
  /// holds rather than a sum of what the probe reports for the containers, so a
  /// file ffprobe cannot read is still counted. A file whose size the walk could
  /// not read is not, so the total is known to be incomplete in that case.
  int get totalSize =>
      videos.fold(0, (total, video) => total + (video.size ?? 0));

  int get videoCount => videos.length;

  /// The videos the probe could not read, by path. They are items with empty
  /// fields, and the scan reports them rather than guessing at values it does
  /// not have.
  List<String> get unprobed => [
    for (final video in videos)
      if (video.info == null) video.path,
  ];

  /// The distinct resolutions, sorted numerically by height — not as text,
  /// which would put `720p` after `2160p`. A video whose height the probe does
  /// not report is not in the list.
  List<String> get resolutions {
    final values = {
      for (final video in videos)
        if (video.info != null && video.info!.videoType.isNotEmpty)
          video.info!.videoType,
    };

    return values.toList()
      ..sort((left, right) => _height(left).compareTo(_height(right)));
  }

  /// The distinct extensions, lowercased, sorted alphabetically. Built from the
  /// file names, not from the item fields, for the reason given on
  /// `ScannedVideo.extension`.
  List<String> get formats =>
      ([for (final video in videos) video.extension]..sort()).toSet().toList();

  static int _height(String videoType) =>
      int.tryParse(videoType.substring(0, videoType.length - 1)) ?? 0;
}

enum VideoScanFailureKind {
  /// The picked folder is not there.
  sourceNotFound,

  /// The picked folder itself could not be read. A folder inside it is reported
  /// by name and the walk continues; only the source cannot be reported,
  /// because there is nothing to report.
  sourceNotReadable,
}

final class VideoScanFailure extends VideoScanResult {
  const VideoScanFailure(this.kind);

  final VideoScanFailureKind kind;
}
