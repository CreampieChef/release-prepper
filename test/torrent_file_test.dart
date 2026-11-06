import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/service/torrent/torrent_file.dart';

import 'test_bencode.dart';

// The flag as the rule answers with it, or null when the bytes are not readable.
bool? flag(String bencode) => switch (readPrivateFlag(utf8.encode(bencode))) {
  TorrentFlagRead(value: final value) => value,
  TorrentFlagUnreadable() => null,
};

void main() {
  test('the flag is read from the info dictionary', () {
    final info = bencodeDict(bencodeEntry('private', bencodeInteger(1)));

    expect(flag(bencodeDict(bencodeEntry('info', info))), isTrue);
  });

  test('a flag of 0 is read as false', () {
    final info = bencodeDict(bencodeEntry('private', bencodeInteger(0)));

    expect(flag(bencodeDict(bencodeEntry('info', info))), isFalse);
  });

  // The format means the absence of the flag as not private, so a file without
  // the key is read as false rather than as nothing.
  test('a file with no flag is read as not private', () {
    final info = bencodeDict(
      bencodeEntry('length', bencodeInteger(12)) +
          bencodeEntry('name', '5:a.txt'),
    );

    expect(flag(bencodeDict(bencodeEntry('info', info))), isFalse);
  });

  // The pieces are the largest part of a real file and are skipped rather than
  // read, so a file with a long string is still read.
  test('a value that is not the flag is skipped', () {
    final info = bencodeDict(
      bencodeEntry('length', bencodeInteger(12)) +
          bencodeEntry('name', '5:a.txt') +
          bencodeEntry('piece length', bencodeInteger(32768)) +
          bencodeEntry('pieces', '20:${'X' * 20}') +
          bencodeEntry('private', bencodeInteger(1)),
    );

    expect(flag(bencodeDict(bencodeEntry('info', info))), isTrue);
  });

  // Only the flag inside info is the flag. A key with the same name anywhere
  // else is part of the file, not the flag.
  test('a key outside the info dictionary is not the flag', () {
    final info = bencodeDict(bencodeEntry('private', bencodeInteger(0)));
    final file = bencodeDict(
      bencodeEntry('private', bencodeInteger(1)) + bencodeEntry('info', info),
    );

    expect(flag(file), isFalse);
  });

  test('a key inside a nested dictionary is not the flag', () {
    final mode = bencodeDict(bencodeEntry('private', bencodeInteger(1)));
    final info = bencodeDict(
      bencodeEntry('private', bencodeInteger(0)) + bencodeEntry('mode', mode),
    );

    expect(flag(bencodeDict(bencodeEntry('info', info))), isFalse);
  });

  test('a key inside a list is not the flag', () {
    final list = 'l${bencodeEntry('private', bencodeInteger(1))}e';
    final info = bencodeDict(
      bencodeEntry('private', bencodeInteger(0)) + bencodeEntry('flags', list),
    );

    expect(flag(bencodeDict(bencodeEntry('info', info))), isFalse);
  });

  test('bytes that are not a bencoded torrent are reported as such', () {
    expect(flag('not a torrent'), isNull);
  });

  test('a file with no info dictionary is reported as such', () {
    expect(flag(bencodeDict(bencodeEntry('comment', '2:hi'))), isNull);
  });

  // A flag is an integer. A value where the flag is written that is not one is
  // not a flag, so nothing is guessed at.
  test('a value that is not an integer is reported as unreadable', () {
    final info = bencodeDict(bencodeEntry('private', '5:true'));

    expect(flag(bencodeDict(bencodeEntry('info', info))), isNull);
  });

  test('a dictionary that is not closed is not read', () {
    expect(flag('d4:infod7:privatei1e'), isNull);
  });
}
