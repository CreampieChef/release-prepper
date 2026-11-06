import 'dart:convert';

/// The Private flag as a torrent file states it (`ai/torrents.md`).
///
/// The flag is read from the file rather than from the app's record, because the
/// file is the thing the flag describes: a release opened again can have a file
/// the app did not write. Only the two dictionaries the flag can be in are
/// walked — the file's top-level dictionary and its `info` entry — and a value
/// that is not the flag is skipped rather than decoded, because the pieces are
/// the largest part of a real torrent and nothing here needs them.
///
/// It is a pure function over the bytes, like `image_dimensions.dart` is over a
/// file header, so the rule can be tested without a file.
TorrentFlag readPrivateFlag(List<int> bytes) {
  final walk = _Walk(bytes);

  final info = walk.dictionary(0, 'info');

  if (walk.malformed || info == null) {
    return const TorrentFlagUnreadable();
  }

  final flag = walk.dictionary(info, 'private');

  if (walk.malformed) {
    return const TorrentFlagUnreadable();
  }

  // A file whose info dictionary has no `private` key is not private: that is
  // what the format means by the flag being absent.
  if (flag == null) {
    return const TorrentFlagRead(value: false);
  }

  final value = walk.integer(flag);

  // A flag is an integer. A value there that is not one is not a flag, so
  // nothing is guessed at.
  return value == null
      ? const TorrentFlagUnreadable()
      : TorrentFlagRead(value: value != 0);
}

/// The walk. `malformed` is what says the bytes are not a bencoded file, which
/// is a different thing from a file that has no flag.
class _Walk {
  _Walk(this.bytes);

  final List<int> bytes;

  bool malformed = false;

  /// Where the value of [key] begins in the dictionary at [start], or null when
  /// the dictionary has no such key. Sets [malformed] when the bytes at [start]
  /// are not a dictionary, or when a key or a value cannot be read.
  int? dictionary(int start, String key) {
    if (start >= bytes.length || bytes[start] != _dictionaryByte) {
      malformed = true;
      return null;
    }

    int? found;
    var pos = start + 1;

    while (pos < bytes.length) {
      if (bytes[pos] == _endByte) {
        return found;
      }

      // A key is a string, and the value follows it.
      final colon = bytes.indexOf(_colonByte, pos);

      if (colon < 0) {
        malformed = true;
        return null;
      }

      final length = int.tryParse(_text(pos, colon));

      if (length == null) {
        malformed = true;
        return null;
      }

      final valueStart = colon + 1 + length;

      if (valueStart > bytes.length) {
        malformed = true;
        return null;
      }

      if (_text(colon + 1, valueStart) == key) {
        found = valueStart;
      }

      final next = skip(valueStart);

      if (next == null) {
        malformed = true;
        return null;
      }

      pos = next;
    }

    malformed = true;
    return null;
  }

  /// An integer value at [pos], or null when the value there is not one.
  int? integer(int pos) {
    if (pos >= bytes.length || bytes[pos] != _integerByte) {
      return null;
    }

    final end = bytes.indexOf(_endByte, pos + 1);

    if (end < 0) {
      return null;
    }

    return int.tryParse(_text(pos + 1, end));
  }

  /// Where the value at [pos] ends, without reading it. A string is skipped by
  /// its length, a list and a dictionary by walking their entries.
  int? skip(int pos) {
    if (pos >= bytes.length) {
      return null;
    }

    if (bytes[pos] == _integerByte) {
      final end = bytes.indexOf(_endByte, pos + 1);

      return end < 0 ? null : end + 1;
    }

    if (_isString(pos)) {
      final colon = bytes.indexOf(_colonByte, pos);

      if (colon < 0) {
        return null;
      }

      final length = int.tryParse(_text(pos, colon));

      if (length == null) {
        return null;
      }

      final end = colon + 1 + length;

      return end > bytes.length ? null : end;
    }

    if (bytes[pos] == _listByte || bytes[pos] == _dictionaryByte) {
      var at = pos + 1;

      while (at < bytes.length && bytes[at] != _endByte) {
        // A dictionary entry is a key and then a value; a list is values only.
        final next = skip(at);

        if (next == null) {
          return null;
        }

        at = next;
      }

      return at < bytes.length ? at + 1 : null;
    }

    return null;
  }

  /// Whether the value at [pos] is a string, which is the one kind that starts
  /// with its length.
  bool _isString(int pos) => bytes[pos] >= 0x30 && bytes[pos] <= 0x39;

  String _text(int start, int end) =>
      utf8.decode(bytes.sublist(start, end), allowMalformed: true);
}

const _colonByte = 0x3A;
const _integerByte = 0x69;
const _listByte = 0x6C;
const _dictionaryByte = 0x64;
const _endByte = 0x65;

sealed class TorrentFlag {
  const TorrentFlag();
}

/// The flag as the file states it.
final class TorrentFlagRead extends TorrentFlag {
  const TorrentFlagRead({required this.value});

  final bool value;
}

/// The flag is not there to be read: the bytes are not a bencoded torrent, or
/// the value where the flag is written is not a flag.
final class TorrentFlagUnreadable extends TorrentFlag {
  const TorrentFlagUnreadable();
}
