import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/service/native_tools/media_info.dart';

Map<String, dynamic> decode(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

void main() {
  // A real ffprobe output, trimmed to the fields the parser reads. The expected
  // values are the examples in ai/release_editor.md.
  test('the six values are formatted as the document specifies', () {
    final info = MediaInfo.parse(
      decode('''
      {
        "streams": [
          {
            "codec_type": "video",
            "codec_name": "h264",
            "profile": "High",
            "width": 3840,
            "height": 2160,
            "r_frame_rate": "30000/1001",
            "bit_rate": "15000000"
          },
          {
            "codec_type": "audio",
            "codec_name": "aac",
            "profile": "LC",
            "sample_rate": "48000",
            "channels": 2,
            "bit_rate": "128000"
          }
        ],
        "format": {
          "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
          "size": "10200000000",
          "duration": "83.450000"
        }
      }
    '''),
    );

    expect(info.fileSize, '10200000000');
    expect(info.duration, '00:01:23');
    expect(
      info.durationSeconds,
      83.45,
      reason: 'the number the thumbnail seeks to',
    );
    expect(info.videoType, '2160p');
    expect(info.videoFormat, 'MP4');
    expect(
      info.videoStream,
      'AVC, 3840x2160, 29.970 (30000/1001) FPS, 15.0 Mb/s',
    );
    expect(info.audioStream, 'AAC LC, 48.0 kHz, 2 channels, 128 kb/s');
  });

  test('a part ffprobe does not report is left out, not guessed', () {
    final info = MediaInfo.parse(
      decode('''
      {
        "streams": [
          {
            "codec_type": "video",
            "codec_name": "hevc",
            "width": 1920,
            "height": 1080,
            "r_frame_rate": "25/1"
          },
          {
            "codec_type": "audio",
            "codec_name": "opus",
            "sample_rate": "48000",
            "channels": 1
          }
        ],
        "format": {
          "format_name": "matroska,webm",
          "duration": "3661.9"
        }
      }
    '''),
    );

    expect(info.fileSize, '');
    expect(info.duration, '01:01:02');
    expect(info.videoType, '1080p');
    expect(info.videoFormat, 'MKV');
    expect(info.videoStream, 'HEVC, 1920x1080, 25.000 (25/1) FPS');
    expect(info.audioStream, 'Opus, 48.0 kHz, 1 channel');
  });

  test('the first stream of each type is the one shown', () {
    final info = MediaInfo.parse(
      decode('''
      {
        "streams": [
          {"codec_type": "audio", "codec_name": "aac", "channels": 2},
          {"codec_type": "video", "codec_name": "h264", "height": 720},
          {"codec_type": "video", "codec_name": "hevc", "height": 1080},
          {"codec_type": "audio", "codec_name": "ac3", "channels": 6}
        ],
        "format": {"format_name": "avi", "duration": "59.6"}
      }
    '''),
    );

    expect(info.duration, '00:01:00');
    expect(info.videoType, '720p');
    expect(info.videoFormat, 'AVI');
    expect(info.videoStream, 'AVC');
    expect(info.audioStream, 'AAC, 2 channels');
  });

  test('a file with no streams still parses', () {
    final info = MediaInfo.parse(decode('{"format": {"format_name": "mp4"}}'));

    expect(info.duration, '');
    expect(info.videoType, '');
    expect(info.videoFormat, 'MP4');
    expect(info.videoStream, '');
    expect(info.audioStream, '');
  });
}
