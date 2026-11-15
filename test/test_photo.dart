/// The bytes a PNG header has, with the dimensions the test declares in it. The
/// reader takes dimensions from the file header rather than by decoding the
/// image, so a header alone is a photo it can read.
///
/// It is here rather than in one test file because three of them need it: the
/// scan, the photoset feature, and the editor. A copy in each would be three
/// fixtures that can disagree, and one with a header the reader does not
/// understand makes every test in that file fail for a reason it is not about.
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
