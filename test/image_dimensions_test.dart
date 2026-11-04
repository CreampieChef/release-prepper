import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/service/images/image_dimensions.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('release_prepper_test');
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
  });

  Future<ImageDimensions?> read(List<int> bytes, String name) async {
    final path = '${directory.path}/$name';
    File(path).writeAsBytesSync(bytes);

    return readImageDimensions(path);
  }

  // The same header read synchronously, which is what the grid needs while it
  // builds.
  ImageDimensions? readSync(List<int> bytes, String name) {
    final path = '${directory.path}/$name';
    File(path).writeAsBytesSync(bytes);

    return readImageDimensionsSync(path);
  }

  // The reader reads headers, not pixels, so the fixtures are the bytes a real
  // file has at the start of it. The expected values are the dimensions those
  // bytes declare.
  test('a JPEG is read from its start-of-frame marker', () async {
    final dimensions = await read([
      0xFF, 0xD8,
      // A metadata segment before the frame, which is why the markers are
      // walked. Its length counts itself, so the walk lands on the next marker.
      0xFF, 0xE1, 0x00, 0x08, 0x45, 0x78, 0x69, 0x66, 0x00, 0x00,
      // SOF0: the length, the precision, then the height and the width.
      0xFF, 0xC0, 0x00, 0x07, 0x08, 0x08, 0x70, 0x0F, 0x00,
      for (var index = 0; index < 31; index++) 0x00,
    ], 'photo.jpg');

    expect(dimensions?.width, 3840);
    expect(dimensions?.height, 2160);
  });

  test('a PNG is read from its IHDR chunk', () async {
    final dimensions = await read([
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
      0x00,
      0x00,
      0x01,
      0x90,
      0x00,
      0x00,
      0x03,
      0x84,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      for (var index = 0; index < 10; index++) 0x00,
    ], 'photo.png');

    expect(dimensions?.width, 400);
    expect(dimensions?.height, 900);
  });

  test('a WebP is read from the chunk it starts with', () async {
    final lossy = await read([
      0x52,
      0x49,
      0x46,
      0x46,
      0x00,
      0x00,
      0x00,
      0x00,
      0x57,
      0x45,
      0x42,
      0x50,
      0x56,
      0x50,
      0x38,
      0x20,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x9D,
      0x01,
      0x2A,
      0xC8,
      0x00,
      0x54,
      0x01,
      for (var index = 0; index < 10; index++) 0x00,
    ], 'lossy.webp');

    expect(lossy?.width, 200);
    expect(lossy?.height, 340);

    // Lossless: the size is packed into four bytes, fourteen bits each, as the
    // value minus one.
    final lossless = await read([
      0x52,
      0x49,
      0x46,
      0x46,
      0x00,
      0x00,
      0x00,
      0x00,
      0x57,
      0x45,
      0x42,
      0x50,
      0x56,
      0x50,
      0x38,
      0x4C,
      0x00,
      0x00,
      0x00,
      0x00,
      0x2F,
      0x63,
      0xC0,
      0x31,
      0x00,
      for (var index = 0; index < 15; index++) 0x00,
    ], 'lossless.webp');

    expect(lossless?.width, 100);
    expect(lossless?.height, 200);

    // Extended: the canvas size is after the flags and the reserved bytes.
    final extended = await read([
      0x52,
      0x49,
      0x46,
      0x46,
      0x00,
      0x00,
      0x00,
      0x00,
      0x57,
      0x45,
      0x42,
      0x50,
      0x56,
      0x50,
      0x38,
      0x58,
      0x00,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0xE7,
      0x03,
      0x00,
      0xBC,
      0x02,
      0x00,
      for (var index = 0; index < 5; index++) 0x00,
    ], 'extended.webp');

    expect(extended?.width, 1000);
    expect(extended?.height, 701);
  });

  test('a header this reader does not understand is not guessed at', () async {
    expect(await read([0x47, 0x49, 0x46, 0x38, 0x39], 'photo.gif'), isNull);

    // A JPEG whose frame marker is past the bound the reader reads.
    final beyond =
        [0xFF, 0xD8, 0xFF, 0xE1, 0x10, 0x00] + List.filled(1 << 20, 0x00);

    expect(await read(beyond, 'big.jpg'), isNull);
  });

  test('the same header is read synchronously for the grid', () async {
    final png = [
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
      0x00,
      0x00,
      0x01,
      0x90,
      0x00,
      0x00,
      0x03,
      0x84,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      for (var index = 0; index < 10; index++) 0x00,
    ];

    // A metadata segment before the frame, so the markers are walked here too.
    final jpeg = [
      0xFF,
      0xD8,
      0xFF,
      0xE1,
      0x00,
      0x08,
      0x45,
      0x78,
      0x69,
      0x66,
      0x00,
      0x00,
      0xFF,
      0xC0,
      0x00,
      0x07,
      0x08,
      0x08,
      0x70,
      0x0F,
      0x00,
      for (var index = 0; index < 31; index++) 0x00,
    ];

    expect(
      readSync(png, 'photo.png')?.value,
      (await read(png, 'photo2.png'))?.value,
    );
    expect(
      readSync(jpeg, 'photo.jpg')?.value,
      (await read(jpeg, 'photo2.jpg'))?.value,
    );

    // A header this reader does not understand, and a file that is not there,
    // are both null, and the grid takes a square tile for them.
    expect(readSync([0x47, 0x49, 0x46, 0x38, 0x39], 'photo.gif'), isNull);
    expect(readImageDimensionsSync('${directory.path}/missing.png'), isNull);
  });

  test('the extension list is the formats the reader understands', () {
    expect(isPhotoExtension('photo.JPG'), isTrue);
    expect(isPhotoExtension('set01/photo.webp'), isTrue);
    expect(isPhotoExtension('notes.txt'), isFalse);
    expect(isPhotoExtension('photo'), isFalse);
  });
}
