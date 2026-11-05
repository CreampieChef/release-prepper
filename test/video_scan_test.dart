import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/service/native_tools/ffprobe.dart';
import 'package:release_prepper/service/native_tools/media_info.dart';
import 'package:release_prepper/service/native_tools/tool_runner.dart';
import 'package:release_prepper/service/videos/video_scanner.dart';

import 'test_runner.dart';

/// What the probe answers for one file, by name. A name the map does not have
/// is a probe failure, which is the case the scan reports rather than fails on.
class _FakeProbe implements Ffprobe {
  _FakeProbe();

  final infos = <String, String>{};
  final types = <String, String>{};
  final formats = <String, String>{};

  /// The paths the probe was called for, in the order the scan called them.
  final calls = <String>[];

  @override
  ToolRunner get runner => testRunner();

  @override
  Future<ToolRunResult> version({required String releaseDirectory}) async =>
      const ToolRunSuccess(stdout: '', stderr: '');

  @override
  Future<MediaProbeResult> probe({
    required String releaseDirectory,
    required String filePath,
  }) async {
    calls.add(filePath);

    final name = p.basename(filePath);

    if (!infos.containsKey(name)) {
      return const MediaProbeFailure(MediaProbeFailureKind.probeFailed);
    }

    return MediaProbeSuccess(
      MediaInfo(
        fileSize: infos[name]!,
        duration: '00:01:00',
        durationSeconds: 60,
        videoType: types[name] ?? '',
        videoFormat: formats[name] ?? 'MP4',
        videoStream: 'AVC',
        audioStream: 'AAC',
      ),
    );
  }
}

void main() {
  late Directory directory;
  late _FakeProbe probe;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('release_prepper_test');
    probe = _FakeProbe();
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
  });

  // The placeholder contents, or `bytes` bytes of them when a test needs a size
  // it can assert.
  void writeContents(File file, int? bytes) {
    if (bytes == null) {
      file.writeAsStringSync('not really a video');
    } else {
      file.writeAsBytesSync(List.filled(bytes, 0));
    }
  }

  // A video file. The contents do not matter: the extension list is what
  // decides what a video is, and the probe answers from the maps, not from the
  // bytes. `probed: false` is a file the probe cannot read, which is the case
  // the scan reports rather than fails on. `bytes` is the size the file has on
  // disk, which is what the total sums; the probe's answer is a different
  // number, so a test can tell the two apart.
  void writeVideo(
    String path, {
    String videoType = '',
    String videoFormat = 'MP4',
    int? bytes,
    bool probed = true,
  }) {
    final file = File(p.join(directory.path, path));
    file.parent.createSync(recursive: true);
    writeContents(file, bytes);

    final name = p.basename(path);

    if (!probed) {
      return;
    }

    probe.infos[name] = '1000';
    probe.types[name] = videoType;
    probe.formats[name] = videoFormat;
  }

  // A file the extension list does not accept.
  void writeOther(String path, {int? bytes}) {
    final file = File(p.join(directory.path, path));
    file.parent.createSync(recursive: true);
    writeContents(file, bytes);
  }

  VideoScanner testScanner() => VideoScanner(probe: probe);

  Future<VideoScanResult> scan(String sourcePath) => testScanner().scan(
    sourcePath: sourcePath,
    releaseDirectory: directory.path,
  );

  // An item is a video file, wherever it is: the walk goes into the subfolders,
  // and the item path is the real relative path, because that is the ID the
  // image records link to (`ai/video_pack.md` §2).
  test(
    'the walk records every video file, including the ones in subfolders',
    () async {
      writeVideo('first.mp4');
      writeVideo('videos/second.mkv');
      writeVideo('videos/deep/third.webm');

      final result = await scan(directory.path) as VideoScanSuccess;

      expect(result.videos.map((video) => video.path), [
        'first.mp4',
        'videos/deep/third.webm',
        'videos/second.mkv',
      ]);
      expect(result.videoCount, 3);
    },
  );

  // A file outside the extension list is not an item and is reported by name,
  // so an accidental file in the picked folder is visible rather than silently
  // included.
  test(
    'a file the extension list does not accept is reported, not included',
    () async {
      writeVideo('first.mp4');
      writeOther('cover.txt');
      writeOther('poster.jpg');

      final result = await scan(directory.path) as VideoScanSuccess;

      expect(result.videos.map((video) => video.path), ['first.mp4']);
      expect(result.skipped, ['cover.txt', 'poster.jpg']);
    },
  );

  // The list is matched case-insensitively, so a file named `.MP4` is an item.
  test('the extension list is matched case-insensitively', () async {
    writeVideo('First.MP4');

    final result = await scan(directory.path) as VideoScanSuccess;

    expect(result.videos.single.path, 'First.MP4');
    expect(result.formats, ['mp4']);
  });

  // A file that cannot be probed is still an item, with its fields left empty,
  // and it is reported by name. One file does not fail the whole scan
  // (`ai/video_pack.md` §4).
  test(
    'a file that cannot be probed is still an item and is reported',
    () async {
      writeVideo('first.mp4', videoType: '1080p');
      writeVideo('second.mkv', probed: false);

      final result = await scan(directory.path) as VideoScanSuccess;

      expect(result.videos.map((video) => video.path), [
        'first.mp4',
        'second.mkv',
      ]);
      expect(result.videos.first.info, isNotNull);
      expect(result.videos.last.info, isNull);
      expect(result.unprobed, ['second.mkv']);
    },
  );

  // An empty subfolder is reported, as a set with no photos is: a folder with
  // no video anywhere in it, whatever else it holds. A folder that has one is
  // not.
  test('a subfolder with no video in it is reported', () async {
    writeVideo('first.mp4');
    Directory(p.join(directory.path, 'empty')).createSync();
    writeOther('nested/cover.txt');
    writeVideo('videos/second.mkv');

    final result = await scan(directory.path) as VideoScanSuccess;

    expect(result.emptyFolders, ['empty', 'nested']);
  });

  // The resolutions are the distinct values, sorted numerically by height: as
  // text, 720p would come after 2160p. A video whose height the probe does not
  // report is not in the list.
  test(
    'the resolutions are distinct and sorted numerically by height',
    () async {
      writeVideo('a.mp4', videoType: '2160p');
      writeVideo('b.mkv', videoType: '720p');
      writeVideo('c.mkv', videoType: '1080p');
      writeVideo('d.mkv', videoType: '1080p');
      writeVideo('e.mkv');

      final result = await scan(directory.path) as VideoScanSuccess;

      expect(result.resolutions, ['720p', '1080p', '2160p']);
    },
  );

  // The formats are the distinct extensions, lowercased, sorted alphabetically.
  // This is what the file name says, not what the probe reports as the
  // container: a mislabelled file makes the two disagree, and that is accepted
  // (`ai/video_pack.md` §4).
  test(
    'the formats are the distinct extensions, lowercased and sorted',
    () async {
      writeVideo('a.MKV', videoFormat: 'AVI');
      writeVideo('b.mkv');
      writeVideo('c.mp4');

      final result = await scan(directory.path) as VideoScanSuccess;

      expect(result.formats, ['mkv', 'mp4']);

      // The item line keeps what the probe reported.
      expect(result.videos.first.info!.videoFormat, 'AVI');
    },
  );

  // The total is the size the files have on disk, summed over the items. The
  // probe's answer for the same file is a different number, a file the probe
  // cannot read still has a size, and a file outside the extension list is not
  // an item, so it is not counted (`ai/video_pack.md` §4).
  test(
    'the total is the size of the files on disk, not what the probe reports',
    () async {
      writeVideo('first.mp4', bytes: 2048);
      writeVideo('videos/second.mkv', bytes: 1024, probed: false);
      writeOther('cover.txt', bytes: 4096);

      final result = await scan(directory.path) as VideoScanSuccess;

      expect(result.totalSize, 3072);
    },
  );

  // The calls are one per item, in the order the walk found them, so the tool
  // log is in that order (`ai/video_pack.md` §4).
  test(
    'the probe is called once per item, in the order the walk found them',
    () async {
      writeVideo('first.mp4');
      writeVideo('videos/second.mkv');

      await scan(directory.path);

      expect(probe.calls, [
        p.join(directory.path, 'first.mp4'),
        p.join(directory.path, 'videos/second.mkv'),
      ]);
    },
  );

  // A picked file is treated as a directory containing only itself, so one rule
  // covers both (`ai/release_structure.md` §2).
  test(
    'a picked file is treated as a directory containing only itself',
    () async {
      writeVideo('first.mp4', videoType: '1080p');

      final result =
          await scan(p.join(directory.path, 'first.mp4')) as VideoScanSuccess;

      expect(result.videos.single.path, 'first.mp4');
    },
  );

  test('a source that is not there is reported', () async {
    final result = await scan(p.join(directory.path, 'missing'));

    expect(result, isA<VideoScanFailure>());
    expect(
      (result as VideoScanFailure).kind,
      VideoScanFailureKind.sourceNotFound,
    );
  });
}
