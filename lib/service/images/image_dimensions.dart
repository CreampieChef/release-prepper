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

  /// Whether the photo is wider than it is tall. This is the shape its
  /// dimensions give, which is what a resolution field states. The 1.2 line in
  /// `masonry.dart` answers a different question — which zone a tile is in in
  /// the grid — and a photo just past square is not a landscape there
  /// (`ai/picking.md` §7).
  bool get isLandscape => width > height;

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
/// archive. `read` answers with up to [length] bytes from where the previous
/// read ended, so the bytes a photo has already given are not read again.
typedef HeaderBytes = Future<List<int>> Function(int length);

/// What a header read answered: the dimensions, or why there are none. A photo
/// whose header cannot be read is still counted — the extension list is what
/// decides what a photo is — so the answer is kept as part of the photo, and
/// the reason is what the log records (`ai/photoset_pack.md` §4).
final class HeaderRead {
  const HeaderRead(this.dimensions) : error = null;

  const HeaderRead.failed(this.error) : dimensions = null;

  final ImageDimensions? dimensions;

  /// Why the header could not be read. This is not text for the page: the page
  /// names the photo, as rule 13 gives it, and the log is where the reason is
  /// read back. It is the exception as the exception reported it when the read
  /// itself could not happen, and one of the phrases below for a case the reader
  /// can name without an exception.
  final String? error;
}

// The cases a header read ends on, as the log records them. A read that threw is
// not one of these, because what it threw with is the reason, and that is what
// the log keeps (`ai/photoset_pack.md` §4).
const headerIsEmpty = 'the header is empty';

const headerIsNotAFormat =
    'the header is not one of the formats this reader understands';

const headerIsIncomplete =
    'the header is a known format, but its fields are not complete in the '
    'bytes it was given';

const photoEndedBeforeItsFrame = 'the photo ended before its frame marker';

/// The dimensions a photo reports from the bytes its header is made of, or the
/// reason it cannot.
Future<HeaderRead> readImageDimensionsFrom(HeaderBytes read) async {
  // The first bytes say which format the photo is. Only JPEG needs more than a
  // fixed header, because its dimensions are in a marker that can be preceded
  // by metadata segments.
  final start = await read(_identifyBytes);

  if (start.isEmpty) {
    return const HeaderRead.failed(headerIsEmpty);
  }

  if (_startsWith(start, _jpegMagic)) {
    return await _walkJpeg(read, start);
  }

  return _otherDimensions(start);
}

/// The same header read synchronously, so a widget can lay a grid out while it
/// builds — the same reason `ImagesStore.loadSync` exists. The same parsers and
/// the same rule, including the walk reading on rather than from the start
/// again. The walk cannot be shared between the two, since one of them cannot
/// await, so it is written twice and the parsers are not. The caller lays a tile
/// it cannot measure out as a square; the reason is for the log, not for the
/// grid.
HeaderRead readImageDimensionsSync(String path) {
  RandomAccessFile? file;

  try {
    file = File(path).openSync();
    final start = file.readSync(_identifyBytes);

    if (start.isEmpty) {
      return const HeaderRead.failed(headerIsEmpty);
    }

    if (_startsWith(start, _jpegMagic)) {
      return _walkJpegSync(file, start);
    }

    return _otherDimensions(start);
  } catch (error) {
    // A file that cannot be read is not measured, and what it failed with is the
    // reason the log records.
    return HeaderRead.failed('$error');
  } finally {
    file?.closeSync();
  }
}

/// The dimensions a file reports, through one handle, so the walk reads on from
/// where the last read ended rather than from the beginning of the file again.
Future<HeaderRead> readImageDimensions(String path) async {
  RandomAccessFile? file;

  try {
    file = await File(path).open();

    return await readImageDimensionsFrom((length) => file!.read(length));
  } catch (error) {
    // A file that cannot be read is not measured. The caller reports it.
    return HeaderRead.failed('$error');
  } finally {
    await file?.close();
  }
}

// The walk reads forward, a step at a time, and stops at the frame. It asks for
// a whole step because a metadata segment can be longer than the bytes it has,
// and a walk that runs out of bytes cannot tell a segment that is not there yet
// from one that is not a frame — only the bytes it is given are an answer.
//
// There is no bound, because a bound decides what is read from a size rather
// than from the photo: a photo whose header is larger than any fixed size is
// still a photo that can be measured. What a bound would do is turn a readable
// photo into an unread one, which is what happened on a real pack to photos
// whose metadata block is split because a segment length is 16-bit. So the walk
// reads until the frame or until the source ends, and the only photo it cannot
// measure is one with no frame marker at all — a broken photo, not a partial
// read. Reading the whole photo for its header is what this exists to avoid
// (`ai/photoset_pack.md` §4), and a photo that is not broken is never read
// whole: the frame is the first thing after a small metadata segment for the
// photos that are not the exception.
//
// The walk ends on one thing only: the source running out. A header that is not
// walkable does not end it, because the walk cannot know that a segment it has
// not read is not a frame, so it reads on; if no frame is ever reached, the
// answer is that the photo ended before its frame marker. That is the only reason
// a header read can give, and it is a statement about the photo rather than about
// the bytes it was given — which is why the phrase is worth keeping. Only the
// bytes the walk is given are an answer, so it cannot tell a segment it has not
// read from one that is not a frame until it runs out of them.
Future<HeaderRead> _walkJpeg(HeaderBytes read, List<int> have) async {
  final bytes = [...have];

  while (true) {
    final dimensions = _jpegDimensions(bytes);

    if (dimensions != null) {
      return HeaderRead(dimensions);
    }

    final more = await read(_jpegStep);

    if (more.isEmpty) {
      return const HeaderRead.failed(photoEndedBeforeItsFrame);
    }

    bytes.addAll(more);
  }
}

/// The same walk on a handle, for the synchronous path.
HeaderRead _walkJpegSync(RandomAccessFile file, List<int> have) {
  final bytes = [...have];

  while (true) {
    final dimensions = _jpegDimensions(bytes);

    if (dimensions != null) {
      return HeaderRead(dimensions);
    }

    final more = file.readSync(_jpegStep);

    if (more.isEmpty) {
      return const HeaderRead.failed(photoEndedBeforeItsFrame);
    }

    bytes.addAll(more);
  }
}

// Enough for the fixed headers: WebP's extended header ends at byte 33, so the
// prefix has to reach past it.
const _identifyBytes = 40;

// How far the JPEG walk reads at a time. The frame is normally the first thing
// after a small metadata segment, so the walk reaches it in one or two steps, and
// a step is what keeps the bytes it asks for the bytes its markers reach rather
// than the whole photo.
const _jpegStep = 1 << 10;
const _jpegMagic = [0xFF, 0xD8];
const _pngMagic = [0x89, 0x50, 0x4E, 0x47];
const _riffMagic = [0x52, 0x49, 0x46, 0x46];
const _webpMagic = [0x57, 0x45, 0x42, 0x50];

/// The formats whose header is inside the prefix: the dimensions are at a known
/// offset, so the walk is not needed.
HeaderRead _otherDimensions(List<int> bytes) {
  if (_startsWith(bytes, _pngMagic)) {
    return _pngDimensions(bytes);
  }

  if (_startsWith(bytes, _riffMagic) && _startsWithAt(bytes, 8, _webpMagic)) {
    return _webpDimensions(bytes);
  }

  return const HeaderRead.failed(headerIsNotAFormat);
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
///
/// This answers for one set of bytes, not for the photo, so null here is not a
/// final answer: it is the walk being given less than a segment and asking for
/// more. What the walk ends on is named by the walk, not here.
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
HeaderRead _pngDimensions(List<int> bytes) {
  if (bytes.length < 24) {
    return const HeaderRead.failed(headerIsIncomplete);
  }

  final width = _bigEndian(bytes, 16);
  final height = _bigEndian(bytes, 20);

  return width > 0 && height > 0
      ? HeaderRead(ImageDimensions(width: width, height: height))
      : const HeaderRead.failed(headerIsIncomplete);
}

/// WebP: the dimensions depend on which chunk the file starts with, so all
/// three are read. Little-endian.
HeaderRead _webpDimensions(List<int> bytes) {
  if (bytes.length < 20) {
    return const HeaderRead.failed(headerIsIncomplete);
  }

  final data = bytes.sublist(20);

  if (_startsWithAt(bytes, 12, _vp8Chunk)) {
    // Lossy: the frame header is three bytes, then a three-byte start code,
    // then the size as two 14-bit values.
    if (data.length < 10 ||
        data[3] != 0x9D ||
        data[4] != 0x01 ||
        data[5] != 0x2A) {
      return const HeaderRead.failed(headerIsIncomplete);
    }

    final width = (data[6] | (data[7] << 8)) & 0x3FFF;
    final height = (data[8] | (data[9] << 8)) & 0x3FFF;

    return width > 0 && height > 0
        ? HeaderRead(ImageDimensions(width: width, height: height))
        : const HeaderRead.failed(headerIsIncomplete);
  }

  if (_startsWithAt(bytes, 12, _vp8lChunk)) {
    // Lossless: the size is packed into the four bytes after the signature,
    // fourteen bits each.
    if (data.isEmpty || data[0] != 0x2F || data.length < 5) {
      return const HeaderRead.failed(headerIsIncomplete);
    }

    final packed = data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24);
    final width = (packed & 0x3FFF) + 1;
    final height = ((packed >> 14) & 0x3FFF) + 1;

    return HeaderRead(ImageDimensions(width: width, height: height));
  }

  if (_startsWithAt(bytes, 12, _vp8xChunk)) {
    // Extended: the canvas size is three bytes each, stored as the value minus
    // one, after the four flag bytes and three reserved bytes.
    if (data.length < 13) {
      return const HeaderRead.failed(headerIsIncomplete);
    }

    final width = (data[7] | (data[8] << 8) | (data[9] << 16)) + 1;
    final height = (data[10] | (data[11] << 8) | (data[12] << 16)) + 1;

    return HeaderRead(ImageDimensions(width: width, height: height));
  }

  return const HeaderRead.failed(headerIsIncomplete);
}

const _vp8Chunk = [0x56, 0x50, 0x38, 0x20];
const _vp8lChunk = [0x56, 0x50, 0x38, 0x4C];
const _vp8xChunk = [0x56, 0x50, 0x38, 0x58];

int _bigEndian(List<int> bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];
