import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/service/photosets/directory_reader.dart';
import 'package:release_prepper/service/photosets/photoset_scanner.dart';
import 'package:release_prepper/service/photosets/zip_reader.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('release_prepper_test');
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
  });

  // The bytes a PNG header has. The dimensions are the ones the test declares.
  List<int> pngPhoto(int width, int height) => [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    (width >> 24) & 0xFF,
    (width >> 16) & 0xFF,
    (width >> 8) & 0xFF,
    width & 0xFF,
    (height >> 24) & 0xFF,
    (height >> 16) & 0xFF,
    (height >> 8) & 0xFF,
    height & 0xFF,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
  ];

  // The bytes a JPEG has at the start of it: a metadata segment, then the
  // frame. The dimensions are not at a fixed offset, which is why the markers
  // are walked.
  List<int> jpegPhoto(int width, int height) => [
    0xFF, 0xD8,
    0xFF, 0xE1, 0x00, 0x08, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00,
    // A frame segment is the length, the precision, then the height and the
    // width.
    0xFF, 0xC0, 0x00, 0x07, 0x08,
    (height >> 8) & 0xFF,
    height & 0xFF,
    (width >> 8) & 0xFF,
    width & 0xFF,
    for (var index = 0; index < 200; index++) 0x00,
  ];

  void writePhoto(String setName, String name, int width, int height) {
    File(p.join(directory.path, setName, name))
        .writeAsBytesSync(pngPhoto(width, height));
  }

  PhotosetScanner scanner() =>
      PhotosetScanner(readers: [const DirectoryPhotosetReader()]);

  // The scan with both readers, which is what the app builds.
  PhotosetScanner scanningArchives() => PhotosetScanner(
    readers: [const DirectoryPhotosetReader(), const ZipPhotosetReader()],
  );

  test(
    'a directory under the source is a photoset, and a loose file is reported',
    () async {
      Directory(p.join(directory.path, 'set02')).createSync();
      Directory(p.join(directory.path, 'set01')).createSync();

      writePhoto('set01', 'b.png', 200, 300);
      writePhoto('set01', 'a.png', 100, 100);
      writePhoto('set02', 'a.png', 150, 150);

      // A file at the top level is not an item, and a file inside a set with an
      // extension outside the list is not a photo. Both are reported or ignored
      // as the rules say, not guessed at.
      File(p.join(directory.path, 'cover.png'))
          .writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
      File(p.join(directory.path, 'set01/notes.txt'))
          .writeAsStringSync('not a photo');

      // A subfolder inside a set is not read: whether a photoset may contain
      // subfolders is still open (`ai/photoset_pack.md` §9).
      Directory(p.join(directory.path, 'set01/inner')).createSync();
      writePhoto('set01/inner', 'a.png', 500, 500);

      final result = await scanner().scan(
        directory.path,
        ItemBoundary.entries,
      ) as ScanSuccess;

      expect(result.sets.map((set) => set.path), ['set01', 'set02']);
      expect(result.skipped, ['cover.png']);
      expect(result.sets.first.photoCount, 2);
      expect(result.sets.last.photoCount, 1);
      expect(result.totalPhotoCount, 3);
    },
  );

  test('the whole photo is what copying needs', () async {
    Directory(p.join(directory.path, 'set01')).createSync();
    writePhoto('set01', 'a.png', 100, 100);

    final reader = const DirectoryPhotosetReader();

    expect(
      await reader.photoBytes(p.join(directory.path, 'set01'), 'a.png'),
      pngPhoto(100, 100),
    );

    // A photo that is not there is not copied, and the caller reports it.
    expect(
      await reader.photoBytes(p.join(directory.path, 'set01'), 'b.png'),
      isEmpty,
    );
  });

  test(
    'the minimum and the maximum are decided by pixel area, across all photos',
    () async {
      Directory(p.join(directory.path, 'set01')).createSync();
      Directory(p.join(directory.path, 'set02')).createSync();

      writePhoto('set01', 'a.png', 100, 100); // 10000
      writePhoto('set02', 'a.png', 150, 150); // 22500
      writePhoto('set02', 'b.png', 400, 150); // 60000, the largest by area

      final result = await scanner().scan(
        directory.path,
        ItemBoundary.entries,
      ) as ScanSuccess;

      expect(result.minResolution?.width, 100);
      expect(result.minResolution?.height, 100);
      expect(result.maxResolution?.width, 400);
      expect(result.maxResolution?.height, 150);
      expect(result.maxResolution?.value, '400x150');
    },
  );

  test('a photo whose header cannot be read is counted and reported', () async {
    Directory(p.join(directory.path, 'set01')).createSync();

    File(p.join(directory.path, 'set01/a.png'))
        .writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
    writePhoto('set01', 'b.png', 100, 100);

    final result = await scanner().scan(
      directory.path,
      ItemBoundary.entries,
    ) as ScanSuccess;

    expect(
      result.sets.single.photoCount,
      2,
      reason: 'the extension list decides what a photo is',
    );
    expect(result.unreadPhotos, ['set01/a.png']);

    // The one photo that can be measured is both the minimum and the maximum.
    expect(result.minResolution?.width, 100);
    expect(result.maxResolution?.width, 100);
  });

  // The size a photo has is the bytes the source gives it: the size on disk for
  // a file in a folder. A photo whose header cannot be read is still counted,
  // and its size is still known, so the total is the whole counted set rather
  // than only the photos that could be measured (`ai/photoset_pack.md` §3).
  test('the size is the bytes the source gives the photo', () async {
    Directory(p.join(directory.path, 'set01')).createSync();
    Directory(p.join(directory.path, 'set02')).createSync();

    File(p.join(directory.path, 'set01/a.png'))
        .writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
    writePhoto('set01', 'b.png', 100, 100);
    writePhoto('set02', 'a.png', 150, 150);

    final result = await scanner().scan(
      directory.path,
      ItemBoundary.entries,
    ) as ScanSuccess;

    // In the order the reader lists the folder, which is by name.
    expect(result.sets.first.photos.map((photo) => photo.size).toList(), [
      4,
      pngPhoto(100, 100).length,
    ]);
    expect(result.sets.last.photos.single.size, pngPhoto(150, 150).length);

    // Across all sets, because the field is the release's, not a set's.
    expect(
      result.totalSize,
      4 + pngPhoto(100, 100).length + pngPhoto(150, 150).length,
    );
  });

  // The formats are the extensions the counted photos have, not the formats
  // their headers decode to: a photo whose header cannot be read is still
  // counted, so its extension is in the list too (`ai/single_photoset.md` §6).
  test(
    'the formats are the distinct extensions, lowercased and sorted',
    () async {
      Directory(p.join(directory.path, 'set02')).createSync();
      Directory(p.join(directory.path, 'set01')).createSync();

      writePhoto('set01', 'a.JPG', 100, 100);
      writePhoto('set01', 'b.png', 100, 100);
      writePhoto('set02', 'c.webp', 100, 100);
      File(p.join(directory.path, 'set02/notes.txt'))
          .writeAsStringSync('not a photo');

      final result = await scanner().scan(
        directory.path,
        ItemBoundary.entries,
      ) as ScanSuccess;

      expect(result.imageFormats, ['jpg', 'png', 'webp']);
    },
  );

  test(
    'nothing measurable has no minimum or maximum, so no value is written',
    () async {
      Directory(p.join(directory.path, 'set01')).createSync();

      File(p.join(directory.path, 'set01/a.png'))
          .writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);

      final result = await scanner().scan(
        directory.path,
        ItemBoundary.entries,
      ) as ScanSuccess;

      expect(result.totalPhotoCount, 1);
      expect(result.minResolution, isNull);
      expect(result.maxResolution, isNull);
    },
  );

  test('the scan does not change when a format is added', () async {
    File(p.join(directory.path, 'set01.zip'))
        .writeAsStringSync('not a real archive');

    final result = await PhotosetScanner(
      readers: [_FakeArchiveReader()],
    ).scan(directory.path, ItemBoundary.entries) as ScanSuccess;

    expect(result.sets.single.path, 'set01.zip');
    expect(result.sets.single.photos.map((photo) => photo.name), [
      'p1.jpg',
      'p2.jpg',
    ]);
  });

  test(
    'a picked file is treated as a directory containing only itself',
    () async {
      final file = File(p.join(directory.path, 'set01.zip'));
      file.writeAsStringSync('not a real archive');

      // With only the directory reader nothing can read it, so it is reported
      // rather than counted.
      final result =
          await scanner().scan(file.path, ItemBoundary.entries) as ScanSuccess;

      expect(result.sets, isEmpty);
      expect(result.skipped, ['set01.zip']);
    },
  );

  // A single photoset is the source itself, so the photos directly in it are
  // the item's photos and the item's path is the source's own name
  // (`ai/single_photoset.md` §5).
  test('the source itself is the item when the type says so', () async {
    Directory(p.join(directory.path, 'set01')).createSync();

    writePhoto('set01', 'b.png', 400, 150);
    writePhoto('set01', 'a.jpg', 100, 100);

    final result = await scanner().scan(
      p.join(directory.path, 'set01'),
      ItemBoundary.source,
    ) as ScanSuccess;

    expect(result.sets.single.path, 'set01');
    expect(result.sets.single.photos.map((photo) => photo.name), [
      'a.jpg',
      'b.png',
    ]);
    expect(result.imageFormats, ['jpg', 'png']);
  });

  // A subfolder inside a single set is not read, as it is not read for a pack:
  // the item is the set, and what is inside it is not another item
  // (`ai/single_photoset.md` §5).
  test('a subfolder inside a single set is not read', () async {
    Directory(p.join(directory.path, 'set01')).createSync();
    Directory(p.join(directory.path, 'set01/inner')).createSync();

    writePhoto('set01', 'a.png', 100, 100);
    writePhoto('set01/inner', 'b.png', 100, 100);

    final result = await scanner().scan(
      p.join(directory.path, 'set01'),
      ItemBoundary.source,
    ) as ScanSuccess;

    expect(result.sets.single.photoCount, 1);
    expect(result.sets.single.photos.map((photo) => photo.name), ['a.png']);
  });

  test('a source that is not there is a failure', () async {
    final result = await scanner().scan(
      p.join(directory.path, 'missing'),
      ItemBoundary.entries,
    );

    expect((result as ScanFailure).kind, ScanFailureKind.sourceNotFound);
  });

  // The archive reader. The fixtures are written by hand: the point of the
  // package is the cases a hand-written reader gets wrong, so a fixture made
  // with the package's own encoder would only test the package against itself.
  test(
    'a mixed pack is one release type, because the reader is chosen per entry',
    () async {
      Directory(p.join(directory.path, 'set01')).createSync();
      writePhoto('set01', 'a.png', 100, 100);

      _writeZip(p.join(directory.path, 'set02.zip'), [
        _ZipEntry('a.png', pngPhoto(400, 200)),
      ]);

      final result = await scanningArchives().scan(
        directory.path,
        ItemBoundary.entries,
      ) as ScanSuccess;

      expect(result.sets.map((set) => set.path), ['set01', 'set02.zip']);
      expect(result.totalPhotoCount, 2);
      expect(result.maxResolution?.value, '400x200');
    },
  );

  test('an archive is read in the order its entries are listed', () async {
    // A directory has no order of its own, so the other reader sorts by name;
    // an archive does, and that order is what the records are written in
    // (`ai/photoset_pack.md` §4).
    _writeZip(p.join(directory.path, 'set01.zip'), [
      _ZipEntry('b.png', pngPhoto(150, 150)),
      _ZipEntry('a.png', pngPhoto(100, 100)),
    ]);

    final result = await scanningArchives().scan(
      directory.path,
      ItemBoundary.entries,
    ) as ScanSuccess;

    expect(result.sets.single.photos.map((photo) => photo.name), [
      'b.png',
      'a.png',
    ]);
  });

  test('a deflated entry is read from its header', () async {
    _writeZip(p.join(directory.path, 'set01.zip'), [
      _ZipEntry('a.png', pngPhoto(200, 300), deflate: true),
    ]);

    final result = await scanningArchives().scan(
      directory.path,
      ItemBoundary.entries,
    ) as ScanSuccess;

    expect(result.maxResolution?.value, '200x300');
  });

  test('a JPEG in an archive is read from its frame marker', () async {
    // The header reader asks for the fixed prefix first and then for more,
    // because a JPEG's frame marker can be preceded by metadata. The entry's
    // stream keeps its read position between those two calls, so the second one
    // has to start from the beginning of the entry again.
    _writeZip(p.join(directory.path, 'set01.zip'), [
      _ZipEntry('a.jpg', jpegPhoto(3840, 2160), deflate: true),
      _ZipEntry('b.jpg', jpegPhoto(100, 100)),
    ]);

    final result = await scanningArchives().scan(
      directory.path,
      ItemBoundary.entries,
    ) as ScanSuccess;

    expect(result.unreadPhotos, isEmpty);
    expect(result.minResolution?.value, '100x100');
    expect(result.maxResolution?.value, '3840x2160');
  });

  test('the whole entry is what copying needs', () async {
    // Reading the header takes only the bytes the header is made of; copying a
    // photo needs the entry in full, so it is a separate call
    // (`ai/photoset_pack.md` §5).
    const bytes = [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      1,
      2,
      3,
      4,
      5,
    ];

    _writeZip(p.join(directory.path, 'set01.zip'), [
      _ZipEntry('a.png', bytes, deflate: true),
      _ZipEntry('b.png', [9, 9, 9]),
    ]);

    final reader = const ZipPhotosetReader();
    final path = p.join(directory.path, 'set01.zip');
    final photos = await reader.read(path);

    // A deflated entry is decoded, a stored one is read as it is. The names are
    // the ones the scan reported, so copying asks for those.
    expect(await reader.photoBytes(path, photos.first.name), bytes);
    expect(await reader.photoBytes(path, photos.last.name), [9, 9, 9]);

    // An entry that is not there is not copied, and the caller reports it.
    expect(await reader.photoBytes(path, 'c.png'), isEmpty);
  });

  test('a data descriptor leaves the sizes to the central directory', () async {
    // A streaming writer writes the local header before it knows the sizes, so
    // they are zero there and only the central directory has them.
    _writeZip(p.join(directory.path, 'set01.zip'), [
      _ZipEntry('a.png', pngPhoto(200, 300), descriptor: true),
    ]);

    final result = await scanningArchives().scan(
      directory.path,
      ItemBoundary.entries,
    ) as ScanSuccess;

    expect(result.sets.single.photoCount, 1);
    expect(result.maxResolution?.value, '200x300');

    // The size the field is built from comes from the same place: the local
    // header has zeros there, so reading the size from it would report nothing.
    expect(result.totalSize, pngPhoto(200, 300).length);
  });

  test('zip64 sizes come from the extra field', () async {
    // The header fields hold the placeholders, which is what the reader is
    // testing here; the fixture declares the real sizes in the zip64 extra
    // field, as a real archive does when they do not fit.
    _writeZip(p.join(directory.path, 'set01.zip'), [
      _ZipEntry('a.png', pngPhoto(200, 300), zip64: true),
    ]);

    final result = await scanningArchives().scan(
      directory.path,
      ItemBoundary.entries,
    ) as ScanSuccess;

    expect(result.sets.single.photoCount, 1);
    expect(result.maxResolution?.value, '200x300');
    expect(result.totalSize, pngPhoto(200, 300).length);
  });

  // The size a photo has in an archive is what the archive states for its
  // entry, which is the uncompressed length — the same kind of number as the
  // size on disk for a file in a folder (`ai/photoset_pack.md` §3). A deflated
  // entry is where the stored bytes and the entry's own length differ, so that
  // is the case that says which of the two the field is built from.
  test('the size of an archived photo is its own length', () async {
    final bytes = jpegPhoto(200, 300);

    _writeZip(p.join(directory.path, 'set01.zip'), [
      _ZipEntry('a.png', bytes, deflate: true),
    ]);

    final result = await scanningArchives().scan(
      directory.path,
      ItemBoundary.entries,
    ) as ScanSuccess;

    expect(result.sets.single.photos.single.size, bytes.length);
    expect(result.totalSize, bytes.length);
  });

  test(
    'an encrypted entry is counted and reported, because there is no password',
    () async {
      // The package reads the directory of an encrypted archive, which is what
      // the reader needs. Decrypting an entry needs a password the app does not
      // have, so its header cannot be read, and the photo is counted and
      // reported like any other unread one.
      _writeZip(p.join(directory.path, 'set01.zip'), [
        _ZipEntry('a.png', pngPhoto(200, 300), encrypted: true),
      ]);

      final result = await scanningArchives().scan(
        directory.path,
        ItemBoundary.entries,
      ) as ScanSuccess;

      expect(result.sets.single.photoCount, 1);
      expect(result.unreadPhotos, ['set01.zip/a.png']);
    },
  );

  test(
    'an entry inside an archive that is not a photo is not counted',
    () async {
      _writeZip(p.join(directory.path, 'set01.zip'), [
        _ZipEntry('a.png', pngPhoto(100, 100)),
        _ZipEntry('notes.txt', utf8.encode('not a photo')),
      ]);

      final result = await scanningArchives().scan(
        directory.path,
        ItemBoundary.entries,
      ) as ScanSuccess;

      expect(result.sets.single.photoCount, 1);
      expect(result.skipped, isEmpty);
    },
  );

  test(
    'an archive that cannot be read is an empty set, not a failed source',
    () async {
      File(p.join(directory.path, 'set01.zip'))
          .writeAsStringSync('not a real archive');

      final result = await scanningArchives().scan(
        directory.path,
        ItemBoundary.entries,
      ) as ScanSuccess;

      // The item is still the item the scan found; one entry that cannot be
      // read does not fail the whole source, as a directory that cannot be
      // listed does not.
      expect(result.sets.single.path, 'set01.zip');
      expect(result.sets.single.photoCount, 0);
      expect(result.skipped, isEmpty);
    },
  );

  test('display names that collide are reported, not renamed', () async {
    // `set01` and `set01.zip` are two different IDs, but both read as `set01`
    // for display. With directories only this cannot happen, so the report
    // comes with the archive reader.
    Directory(p.join(directory.path, 'set01')).createSync();
    _writeZip(p.join(directory.path, 'set01.zip'), [
      _ZipEntry('a.png', pngPhoto(100, 100)),
    ]);

    final result = await scanningArchives().scan(
      directory.path,
      ItemBoundary.entries,
    ) as ScanSuccess;

    expect(result.nameCollisions, {
      'set01': ['set01', 'set01.zip'],
    });
  });
}

class _ZipEntry {
  const _ZipEntry(
    this.name,
    this.bytes, {
    this.deflate = false,
    this.descriptor = false,
    this.zip64 = false,
    this.encrypted = false,
  });

  final String name;
  final List<int> bytes;
  final bool deflate;
  final bool descriptor;
  final bool zip64;
  final bool encrypted;
}

void _writeZip(String path, List<_ZipEntry> entries) {
  final file = <int>[];
  final directoryRecords = <List<int>>[];

  for (final entry in entries) {
    final content = entry.deflate
        ? ZLibCodec(raw: true).encode(entry.bytes)
        : entry.bytes;
    final crc = _crc32(entry.bytes);
    final name = utf8.encode(entry.name);
    final flags = (entry.descriptor ? 0x08 : 0) | (entry.encrypted ? 0x1 : 0);
    final method = entry.deflate ? 8 : 0;

    // A zip64 entry writes the placeholders in the header fields and the real
    // sizes in the extra field, which is the case a hand-written reader gets
    // wrong.
    final placeholder = entry.zip64;
    final extra = entry.zip64
        ? [1, 0, 16, 0, ..._le64(entry.bytes.length), ..._le64(content.length)]
        : const <int>[];

    final localOffset = file.length;

    file.addAll([
      0x50,
      0x4B,
      0x03,
      0x04,
      ..._le16(20),
      ..._le16(flags),
      ..._le16(method),
      ..._le16(0),
      ..._le16(0),
      ..._le32(crc),
      ..._le32(placeholder ? 0xFFFFFFFF : content.length),
      ..._le32(placeholder ? 0xFFFFFFFF : entry.bytes.length),
      ..._le16(name.length),
      ..._le16(extra.length),
      ...name,
      ...extra,
      ...content,
    ]);

    if (entry.descriptor) {
      file.addAll([
        0x50,
        0x4B,
        0x07,
        0x08,
        ..._le32(crc),
        ..._le32(content.length),
        ..._le32(entry.bytes.length),
      ]);
    }

    directoryRecords.add([
      0x50,
      0x4B,
      0x01,
      0x02,
      ..._le16(20),
      ..._le16(20),
      ..._le16(flags),
      ..._le16(method),
      ..._le16(0),
      ..._le16(0),
      ..._le32(crc),
      ..._le32(placeholder ? 0xFFFFFFFF : content.length),
      ..._le32(placeholder ? 0xFFFFFFFF : entry.bytes.length),
      ..._le16(name.length),
      ..._le16(extra.length),
      ..._le16(0),
      ..._le16(0),
      ..._le16(0),
      ..._le32(0x81A4),
      ..._le32(localOffset),
      ...name,
      ...extra,
    ]);
  }

  final directoryOffset = file.length;
  final directorySize = directoryRecords.fold(
    0,
    (total, record) => total + record.length,
  );

  for (final record in directoryRecords) {
    file.addAll(record);
  }

  final zip64 = entries.any((entry) => entry.zip64);

  if (zip64) {
    final zip64Offset = file.length;

    // The size field counts the fields after it, so the record is 44 of them
    // plus its own signature and the size field.
    file.addAll([
      0x50,
      0x4B,
      0x06,
      0x06,
      ..._le64(44),
      ..._le16(45),
      ..._le16(45),
      ..._le32(0),
      ..._le32(0),
      ..._le64(entries.length),
      ..._le64(entries.length),
      ..._le64(directorySize),
      ..._le64(directoryOffset),
    ]);

    file.addAll([
      0x50,
      0x4B,
      0x06,
      0x07,
      ..._le32(0),
      ..._le64(zip64Offset),
      ..._le32(1),
    ]);
  }

  file.addAll([
    0x50,
    0x4B,
    0x05,
    0x06,
    ..._le16(0),
    ..._le16(0),
    ..._le16(zip64 ? 0xFFFF : entries.length),
    ..._le16(zip64 ? 0xFFFF : entries.length),
    ..._le32(zip64 ? 0xFFFFFFFF : directorySize),
    ..._le32(zip64 ? 0xFFFFFFFF : directoryOffset),
    ..._le16(0),
  ]);

  File(path).writeAsBytesSync(file);
}

List<int> _le16(int value) => [value & 0xFF, (value >> 8) & 0xFF];

List<int> _le32(int value) => [
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

List<int> _le64(int value) => [
  ..._le32(value & 0xFFFFFFFF),
  ..._le32((value >> 32) & 0xFFFFFFFF),
];

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;

  for (final byte in bytes) {
    crc ^= byte;

    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }

  return crc ^ 0xFFFFFFFF;
}

/// A reader for a format the scan has no reader for yet, to show that the scan
/// reads through the interface rather than through one format
/// (`ai/photoset_pack.md` §5).
class _FakeArchiveReader implements PhotosetReader {
  @override
  bool canRead(SourceEntry entry) => entry.name.endsWith('.zip');

  @override
  Future<List<ScannedPhoto>> read(String path) async => [
    const ScannedPhoto(name: 'p1.jpg', size: 0),
    const ScannedPhoto(name: 'p2.jpg', size: 0),
  ];

  @override
  Future<List<int>> photoBytes(String path, String name) async {
    try {
      return await File(p.join(path, name)).readAsBytes();
    } catch (_) {
      return const [];
    }
  }
}
