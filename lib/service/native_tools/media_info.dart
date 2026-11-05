/// The metadata the editor shows for a movie file: items 8, 9, 11, 12, 13 and
/// 16 of `ai/release_editor.md`. Plain strings, formatted exactly as that
/// document specifies, parsed from the JSON
/// `ffprobe -of json -show_format -show_streams` writes for one file.
///
/// A part that ffprobe does not report is left out rather than guessed, so a
/// stream line may be shorter than the example in the document.
class MediaInfo {
  const MediaInfo({
    required this.fileSize,
    required this.duration,
    required this.durationSeconds,
    required this.videoType,
    required this.videoFormat,
    required this.videoStream,
    required this.audioStream,
  });

  /// Item 16 — the file size as the byte count, which is what the model stores.
  /// Showing it in a human-friendly form is display, not parsing, so it is not
  /// done here.
  final String fileSize;

  /// Item 8 — `hh:mm:ss`.
  final String duration;

  /// The same duration as ffprobe reports it, in seconds. The editor shows the
  /// formatted text; this is the number the thumbnail seeks to.
  final double? durationSeconds;

  /// Item 9 — `2160p`, from the video height.
  final String videoType;

  /// Item 11 — `MP4`, the container.
  final String videoFormat;

  /// Item 12 — `AVC, 3840x2160, 29.970 (30000/1001) FPS, 15.0 Mb/s`.
  final String videoStream;

  /// Item 13 — `AAC LC, 48.0 kHz, 2 channels, 128 kb/s`.
  final String audioStream;

  static MediaInfo parse(Map<String, dynamic> json) {
    final format = json['format'] is Map<String, dynamic>
        ? json['format'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final video = _stream(json, 'video');
    final audio = _stream(json, 'audio');

    final durationSeconds =
        _asDouble(format['duration']) ?? _asDouble(video?['duration']);

    return MediaInfo(
      fileSize: _fileSize(format['size']),
      duration: _formatDuration(durationSeconds),
      durationSeconds: durationSeconds,
      videoType: _videoType(video),
      videoFormat: _formatName(_asString(format['format_name'])),
      videoStream: _videoStream(video),
      audioStream: _audioStream(audio),
    );
  }

  /// The first stream of a type. A file can hold several; the editor shows one
  /// line per type, so the first is the one it shows.
  static Map<String, dynamic>? _stream(Map<String, dynamic> json, String type) {
    final streams = json['streams'];

    if (streams is! List) {
      return null;
    }

    for (final stream in streams) {
      if (stream is Map<String, dynamic> && stream['codec_type'] == type) {
        return stream;
      }
    }

    return null;
  }

  /// Item 16. `format.size` is the file size in bytes; the model stores the
  /// number as text, so this is the digits, not a formatted form.
  static String _fileSize(Object? size) {
    final bytes = _asInt(size);

    return bytes == null ? '' : bytes.toString();
  }

  static String _formatDuration(double? seconds) {
    if (seconds == null) {
      return '';
    }

    final total = seconds.round();

    return [
      total ~/ 3600,
      (total % 3600) ~/ 60,
      total % 60,
    ].map((part) => part.toString().padLeft(2, '0')).join(':');
  }

  static String _videoType(Map<String, dynamic>? stream) {
    final height = _asInt(stream?['height']);

    return height == null ? '' : '${height}p';
  }

  /// `format_name` is a list of the containers one demuxer reads —
  /// `mov,mp4,...` for an MP4 file — so the name is the one that list is known
  /// for, not its first token.
  static const _formatNames = {
    'mp4': 'MP4',
    'matroska': 'MKV',
    'webm': 'WEBM',
    'avi': 'AVI',
    'mov': 'MOV',
  };

  static String _formatName(String? formatName) {
    if (formatName == null) {
      return '';
    }

    final tokens = formatName.split(',');

    for (final entry in _formatNames.entries) {
      if (tokens.contains(entry.key)) {
        return entry.value;
      }
    }

    return tokens.first.toUpperCase();
  }

  /// Display names as the document writes them, not ffprobe's codec ids.
  static const _videoCodecNames = {
    'h264': 'AVC',
    'hevc': 'HEVC',
    'av1': 'AV1',
    'vp9': 'VP9',
    'vp8': 'VP8',
    'mpeg2video': 'MPEG-2',
    'mpeg4': 'MPEG-4',
    'h263': 'H.263',
  };

  static const _audioCodecNames = {
    'aac': 'AAC',
    'ac3': 'AC-3',
    'eac3': 'E-AC-3',
    'dts': 'DTS',
    'truehd': 'TrueHD',
    'flac': 'FLAC',
    'opus': 'Opus',
    'vorbis': 'Vorbis',
    'mp3': 'MP3',
  };

  static String _videoStream(Map<String, dynamic>? stream) {
    if (stream == null) {
      return '';
    }

    final width = _asInt(stream['width']);
    final height = _asInt(stream['height']);
    final bitRate = _asDouble(stream['bit_rate']);

    return [
      _videoCodecNames[stream['codec_name']] ??
          _asString(stream['codec_name']) ??
          '',
      width == null || height == null ? '' : '${width}x$height',
      _frameRate(stream['r_frame_rate']),
      bitRate == null ? '' : '${(bitRate / 1000000).toStringAsFixed(1)} Mb/s',
    ].where((part) => part.isNotEmpty).join(', ');
  }

  static String _audioStream(Map<String, dynamic>? stream) {
    if (stream == null) {
      return '';
    }

    final name =
        _audioCodecNames[stream['codec_name']] ??
        _asString(stream['codec_name']) ??
        '';
    final profile = _asString(stream['profile']) ?? '';
    final sampleRate = _asDouble(stream['sample_rate']);
    final channels = _asInt(stream['channels']);
    final bitRate = _asDouble(stream['bit_rate']);

    // The document writes the audio profile ("AAC LC") but not the video one.
    return [
      [name, profile].where((part) => part.isNotEmpty).join(' '),
      sampleRate == null ? '' : '${(sampleRate / 1000).toStringAsFixed(1)} kHz',
      channels == null ? '' : '$channels channel${channels == 1 ? '' : 's'}',
      bitRate == null ? '' : '${(bitRate / 1000).round()} kb/s',
    ].where((part) => part.isNotEmpty).join(', ');
  }

  /// `30000/1001` is what the document asks for; ffmpeg's own output only shows
  /// the rounded 29.97.
  static String _frameRate(Object? value) {
    if (value is! String) {
      return '';
    }

    final parts = value.split('/');

    if (parts.length != 2) {
      return '';
    }

    final numerator = int.tryParse(parts[0]);
    final denominator = int.tryParse(parts[1]);

    if (numerator == null || denominator == null || denominator == 0) {
      return '';
    }

    final fps = numerator / denominator;

    if (fps == 0) {
      return '';
    }

    return '${fps.toStringAsFixed(3)} ($numerator/$denominator) FPS';
  }

  static String? _asString(Object? value) => value is String ? value : null;

  static int? _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }

    return value is String ? int.tryParse(value) : null;
  }

  static double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    return value is String ? double.tryParse(value) : null;
  }
}
