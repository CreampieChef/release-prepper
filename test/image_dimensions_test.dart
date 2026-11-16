import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/service/images/image_dimensions.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('release_prepper_test');
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
  });

  // The header as the reader answers it. The tests about what a header says are
  // about the dimensions, so `read` and `readSync` answer with the dimensions
  // alone; the tests about a header that could not be read are about the reason
  // the log records, and take `header` and `headerSync`.
  Future<HeaderRead> header(List<int> bytes, String name) async {
    final path = p.join(directory.path, name);
    File(path).writeAsBytesSync(bytes);

    return readImageDimensions(path);
  }

  // The same header read synchronously, which is what the grid needs while it
  // builds.
  HeaderRead headerSync(List<int> bytes, String name) {
    final path = p.join(directory.path, name);
    File(path).writeAsBytesSync(bytes);

    return readImageDimensionsSync(path);
  }

  Future<ImageDimensions?> read(List<int> bytes, String name) async =>
      (await header(bytes, name)).dimensions;

  ImageDimensions? readSync(List<int> bytes, String name) =>
      headerSync(bytes, name).dimensions;

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

  // The walk reads forward, so the bytes between the prefix and the frame are
  // read once: a photo with a metadata segment longer than the step the walk
  // reads at is still measured, and nothing after its frame is read. There is no
  // bound, so a header larger than any fixed size is read as well — that is the
  // case a real pack had, and the only photo the walk cannot measure is one with
  // no frame marker at all.
  test('the walk reads only as far as its markers reach', () async {
    // A source that records what the walk asks for, and answers from where the
    // last answer ended, as `HeaderBytes` says it is answered.
    HeaderBytes recording(List<int> photo, List<int> asked) {
      var position = 0;

      return (length) async {
        asked.add(length);

        final end = position + length > photo.length
            ? photo.length
            : position + length;
        final bytes = photo.sublist(position, end);
        position += bytes.length;

        return bytes;
      };
    }

    int total(List<int> asked) => asked.fold(0, (sum, length) => sum + length);

    final asked = <int>[];
    final photo = [
      0xFF,
      0xD8,
      // A metadata segment 6 KB long — the length counts itself, as the test
      // above says — which is past the step the walk reads at, as a photo with
      // an embedded thumbnail is.
      0xFF,
      0xE1,
      0x17,
      0x72,
      for (var index = 0; index < 6000; index++) 0x00,
      0xFF,
      0xC0,
      0x00,
      0x07,
      0x08,
      0x08,
      0x70,
      0x0F,
      0x00,
      for (var index = 0; index < 4000; index++) 0x00,
    ];

    final read = await readImageDimensionsFrom(recording(photo, asked));

    expect(read.dimensions?.value, '3840x2160');
    expect(read.error, isNull);

    // The prefix that says which format the photo is, then the steps the walk
    // reaches the frame inside. Reading the whole photo for a header is what the
    // walk exists to avoid.
    expect(asked.first, 40);
    expect(total(asked), lessThan(1 << 20));

    // Running out of bytes is the only case the walk can end on, and it can only
    // be answered at the end: the bytes it has cannot tell a segment it has not
    // read from one that is not a frame.
    final short = [
      0xFF,
      0xD8,
      0xFF,
      0xE1,
      0x17,
      0x72,
      for (var index = 0; index < 6000; index++) 0x00,
    ];

    asked.clear();

    final ranOut = await readImageDimensionsFrom(recording(short, asked));

    expect(ranOut.dimensions, isNull);
    expect(ranOut.error, photoEndedBeforeItsFrame);
    expect(total(asked), lessThan(1 << 20));

    // The case a bound would have made unread: a metadata block that cannot be
    // one segment because a segment length is 16-bit, so it is split into chunks
    // and the frame marker is past any fixed size. This is what a real pack had.
    // The walk reads through it and stops at the frame.
    //
    // The length counts itself, so a chunk is the marker bytes plus the length:
    // the largest a single segment can be is 65535, and the fixture writes that
    // so the walk's jumps land on the next chunk.
    const chunkLength = 65533;
    const chunks = 20;
    const header = 2 + chunks * (2 + chunkLength);

    final past = [
      0xFF,
      0xD8,
      for (var chunk = 0; chunk < chunks; chunk++) ...[
        0xFF,
        0xE1,
        0xFF,
        0xFD,
        for (var index = 0; index < chunkLength - 2; index++) 0x00,
      ],
      0xFF,
      0xC0,
      0x00,
      0x07,
      0x08,
      0x08,
      0x70,
      0x0F,
      0x00,
      for (var index = 0; index < 4000; index++) 0x00,
    ];

    asked.clear();

    final beyond = await readImageDimensionsFrom(recording(past, asked));

    expect(beyond.dimensions?.value, '3840x2160');
    expect(beyond.error, isNull);

    // The frame's own bytes have to be there for it to be read, so the walk asks
    // for the header plus the step that covers the marker — and not for the image
    // data after it.
    expect(total(asked), greaterThanOrEqualTo(header + 9));
    expect(total(asked), lessThan(header + 9 + 1024));
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
    final gif = await header([0x47, 0x49, 0x46, 0x38, 0x39], 'photo.gif');

    expect(gif.dimensions, isNull);
    expect(gif.error, headerIsNotAFormat);

    // A header whose format is known but whose fields are not all there. The
    // prefix reaches past where the dimensions would be, so this is not an
    // unknown format, and the log says which of the two it was.
    final short = await header([0x89, 0x50, 0x4E, 0x47], 'short.png');

    expect(short.dimensions, isNull);
    expect(short.error, headerIsIncomplete);

    // A file with nothing in it.
    final empty = await header([], 'empty.jpg');

    expect(empty.dimensions, isNull);
    expect(empty.error, headerIsEmpty);

    // A JPEG with no frame marker anywhere in it. With no bound this is the only
    // case the walk can end on, and it is a broken photo rather than a partial
    // read: the photo is read to its end and has no frame. A photo whose header
    // is larger than any fixed size is read and measured, which is the test
    // above.
    final broken = await header([
      0xFF,
      0xD8,
      // Start of scan with no frame before it. What follows is image data, which
      // is not a marker, so the walk reads on to the end of the photo.
      0xFF,
      0xDA,
      0x00,
      0x08,
      0x01,
      0x01,
      0x00,
      for (var index = 0; index < 200; index++) 0x20,
    ], 'broken.jpg');

    expect(broken.dimensions, isNull);
    expect(broken.error, photoEndedBeforeItsFrame);
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

    // A header past the step the walk reads at, which is the case the walk is
    // for, so the two paths have to reach the same answer the same way.
    final long = [
      0xFF,
      0xD8,
      0xFF,
      0xE1,
      0x17,
      0x72,
      for (var index = 0; index < 6000; index++) 0x00,
      0xFF,
      0xC0,
      0x00,
      0x07,
      0x08,
      0x08,
      0x70,
      0x0F,
      0x00,
    ];

    expect(
      readSync(long, 'photo3.jpg')?.value,
      (await read(long, 'photo4.jpg'))?.value,
    );
    expect(readSync(long, 'photo3.jpg')?.value, '3840x2160');

    // A header past the size the reader used to stop at, which is what the change
    // is for: the walk on a handle reaches the same answer, because neither path
    // has a bound.
    final split = [
      0xFF,
      0xD8,
      for (var chunk = 0; chunk < 20; chunk++) ...[
        0xFF,
        0xE1,
        0xFF,
        0xFD,
        for (var index = 0; index < 65531; index++) 0x00,
      ],
      0xFF,
      0xC0,
      0x00,
      0x07,
      0x08,
      0x08,
      0x70,
      0x0F,
      0x00,
    ];

    expect(
      readSync(split, 'photo5.jpg')?.value,
      (await read(split, 'photo6.jpg'))?.value,
    );
    expect(readSync(split, 'photo5.jpg')?.value, '3840x2160');

    // A header this reader does not understand, and a file that is not there,
    // are both no dimensions, and the grid takes a square tile for them. The
    // reason is the same as the path the scan reads through, because it is the
    // same reader: the phrase for a header, and the exception for a file.
    expect(
      headerSync([0x47, 0x49, 0x46, 0x38, 0x39], 'photo2.gif').error,
      headerIsNotAFormat,
    );

    final missing = readImageDimensionsSync(
      p.join(directory.path, 'missing.png'),
    );

    expect(missing.dimensions, isNull);
    expect(missing.error, isNotEmpty);
  });

  test('the extension list is the formats the reader understands', () {
    expect(isPhotoExtension('photo.JPG'), isTrue);
    expect(isPhotoExtension('set01/photo.webp'), isTrue);
    expect(isPhotoExtension('notes.txt'), isFalse);
    expect(isPhotoExtension('photo'), isFalse);
  });
}
