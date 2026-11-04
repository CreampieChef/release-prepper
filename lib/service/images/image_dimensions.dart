import 'dart:io';

/// The dimensions a photo reports. They are read from the file header rather
/// than by decoding the image: a real pack is hundreds of photos, and one tool
/// call per photo is hundreds of processes (`ai/photoset_pack.md` §4).
class ImageDimensions {
  const ImageDimensions({required this.width, required this.height});

  final int width;
  final int height;

  /// The measure resolution is compared by. A 4000x2000 photo and a 2500x3200
  /// photo are not ordered by any single side, so the minimum and the maximum
  /// are decided by area (`ai/photoset_pack.md` §3).
  int get area => width * height;

  /// The value a resolution field holds.
  String get value => [width, height].join('x');
}

/// The formats the reader understands. The photo extension list is the same
/// list, so a file is never counted as a photo and then left unmeasured
/// (`ai/photoset_pack.md` §4).
const photoExtensions = {'jpg', 'jpeg', 'png', 'webp'};

/// Whether a filename is one of those formats. The comparison is on the
/// extension alone, because the reader is what decides whether the header can
/// be read.
bool isPhotoExtension(String name) =>
    photoExtensions.contains(name.split('.').last.toLowerCase());

/// Where the bytes of a photo header come from: a file, or an entry in an
/// archive. `read` returns up to [length] bytes from the start of the image, so
/// a format whose header is longer than the fixed one asks for more.
typedef HeaderBytes = Future<List<int>> Function(int length);

/// The dimensions a photo reports from the bytes its header is made of, or null
/// when that header is not one this reader understands. A photo whose header
/// cannot be read is still counted — the extension list is what decides what a
/// photo is — and the scan reports it.
Future<ImageDimensions?> readImageDimensionsFrom(HeaderBytes read) async {
  // The first bytes say which format the photo is. Only JPEG needs more than a
  // fixed header, because its dimensions are in a marker that can be preceded
  // by metadata segments.
  final start = await read(_identifyBytes);

  if (start.isEmpty) {
    return null;
  }

  if (_startsWith(start, _jpegMagic)) {
    // The bound is a limit, not a guess: a photo whose frame marker is past it
    // is reported as unread rather than measured from a partial read.
    return _jpegDimensions(await read(_jpegMaxHeader));
  }

  if (_startsWith(start, _pngMagic)) {
    return _pngDimensions(start);
  }

  if (_startsWith(start, _riffMagic) && _startsWithAt(start, 8, _webpMagic)) {
    return _webpDimensions(start);
  }

  return null;
}

/// The dimensions a file reports.
Future<ImageDimensions?> readImageDimensions(String path) =>
    readImageDimensionsFrom((length) => _readPrefix(File(path), length));

/// The same header, read synchronously, so a widget can lay a grid out while it
/// builds — the same reason `ImagesStore.loadSync` exists. The same parsers and
/// the same rule: a header, not the pixels. Null when the header is not one
/// this reader understands, and the caller lays that tile out as a square.
ImageDimensions? readImageDimensionsSync(String path) {
  RandomAccessFile? file;

  try {
    file = File(path).openSync();
    final start = file.readSync(_identifyBytes);

    if (start.isEmpty) {
      return null;
    }

    if (_startsWith(start, _jpegMagic)) {
      // The second read starts from the beginning of the file again, as the
      // archive path does. The sync variant, because a handle cannot have an
      // async operation pending while a sync one is being made on it.
      file.setPositionSync(0);

      return _jpegDimensions(file.readSync(_jpegMaxHeader));
    }

    if (_startsWith(start, _pngMagic)) {
      return _pngDimensions(start);
    }

    if (_startsWithAt(start, 8, _webpMagic)) {
      return _webpDimensions(start);
    }

    return null;
  } catch (_) {
    // A file that cannot be read is not measured.
    return null;
  } finally {
    file?.closeSync();
  }
}

// Enough for the fixed headers: WebP's extended header ends at byte 33, so the
// prefix has to reach past it.
const _identifyBytes = 40;
const _jpegMaxHeader = 1 << 20;
const _jpegMagic = [0xFF, 0xD8];
const _pngMagic = [0x89, 0x50, 0x4E, 0x47];
const _riffMagic = [0x52, 0x49, 0x46, 0x46];
const _webpMagic = [0x57, 0x45, 0x42, 0x50];

Future<List<int>> _readPrefix(File file, int length) async {
  final bytes = <int>[];

  try {
    await for (final chunk in file.openRead(0, length)) {
      bytes.addAll(chunk);
    }
  } catch (_) {
    // A file that cannot be read is not measured. The caller reports it.
  }

  return bytes;
}

bool _startsWith(List<int> bytes, List<int> magic) =>
    _startsWithAt(bytes, 0, magic);

bool _startsWithAt(List<int> bytes, int offset, List<int> magic) {
  if (bytes.length < offset + magic.length) {
    return false;
  }

  for (var index = 0; index < magic.length; index++) {
    if (bytes[offset + index] != magic[index]) {
      return false;
    }
  }

  return true;
}

/// JPEG: the dimensions are in a start-of-frame marker. Everything before it is
/// metadata, so the markers are walked until one is found. Markers that carry
/// no length — the image boundaries, the restart markers — are stepped over.
ImageDimensions? _jpegDimensions(List<int> bytes) {
  var offset = 2;

  while (offset + 1 < bytes.length) {
    if (bytes[offset] != 0xFF) {
      return null;
    }

    final marker = bytes[offset + 1];

    if (marker == 0xD8 ||
        marker == 0xD9 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      offset += 2;
      continue;
    }

    if (offset + 3 >= bytes.length) {
      return null;
    }

    final length = (bytes[offset + 2] << 8) | bytes[offset + 3];

    // The markers between 0xC0 and 0xCF that are not a frame: the Huffman table
    // and the arithmetic coding table.
    final isFrame =
        marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8;

    if (!isFrame) {
      offset += 2 + length;
      continue;
    }

    // A frame segment is the length, the precision, then the height and the
    // width.
    if (length < 5 || offset + 8 >= bytes.length) {
      return null;
    }

    final height = (bytes[offset + 5] << 8) | bytes[offset + 6];
    final width = (bytes[offset + 7] << 8) | bytes[offset + 8];

    return width > 0 && height > 0
        ? ImageDimensions(width: width, height: height)
        : null;
  }

  return null;
}

/// PNG: the dimensions are the first two fields of IHDR, which is always the
/// first chunk, so the fixed header is enough. Big-endian.
ImageDimensions? _pngDimensions(List<int> bytes) {
  if (bytes.length < 24) {
    return null;
  }

  final width = _bigEndian(bytes, 16);
  final height = _bigEndian(bytes, 20);

  return width > 0 && height > 0
      ? ImageDimensions(width: width, height: height)
      : null;
}

/// WebP: the dimensions depend on which chunk the file starts with, so all
/// three are read. Little-endian.
ImageDimensions? _webpDimensions(List<int> bytes) {
  if (bytes.length < 20) {
    return null;
  }

  final data = bytes.sublist(20);

  if (_startsWithAt(bytes, 12, _vp8Chunk)) {
    // Lossy: the frame header is three bytes, then a three-byte start code,
    // then the size as two 14-bit values.
    if (data.length < 10 ||
        data[3] != 0x9D ||
        data[4] != 0x01 ||
        data[5] != 0x2A) {
      return null;
    }

    final width = (data[6] | (data[7] << 8)) & 0x3FFF;
    final height = (data[8] | (data[9] << 8)) & 0x3FFF;

    return width > 0 && height > 0
        ? ImageDimensions(width: width, height: height)
        : null;
  }

  if (_startsWithAt(bytes, 12, _vp8lChunk)) {
    // Lossless: the size is packed into the four bytes after the signature,
    // fourteen bits each.
    if (data.isEmpty || data[0] != 0x2F || data.length < 5) {
      return null;
    }

    final packed = data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24);
    final width = (packed & 0x3FFF) + 1;
    final height = ((packed >> 14) & 0x3FFF) + 1;

    return ImageDimensions(width: width, height: height);
  }

  if (_startsWithAt(bytes, 12, _vp8xChunk)) {
    // Extended: the canvas size is three bytes each, stored as the value minus
    // one, after the four flag bytes and three reserved bytes.
    if (data.length < 13) {
      return null;
    }

    final width = (data[7] | (data[8] << 8) | (data[9] << 16)) + 1;
    final height = (data[10] | (data[11] << 8) | (data[12] << 16)) + 1;

    return ImageDimensions(width: width, height: height);
  }

  return null;
}

const _vp8Chunk = [0x56, 0x50, 0x38, 0x20];
const _vp8lChunk = [0x56, 0x50, 0x38, 0x4C];
const _vp8xChunk = [0x56, 0x50, 0x38, 0x58];

int _bigEndian(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];
