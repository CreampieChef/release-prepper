import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/service/videos/image_generator.dart';

void main() {
  // The screenlist rows formula, on its own (`ai/doc.md` §2): one frame per
  // minute of video, at least 16 and at most 96 frames, 4
  // per row. The formula is the service's, so this is the service's test.
  test('screenlist rows: one frame per minute, 16 to 96 frames, 4 per row', () {
    // Below the minimum: 16 frames, so 4 rows.
    expect(ImageGenerator.screenlistRows(30), 4);
    expect(ImageGenerator.screenlistRows(60), 4);
    expect(ImageGenerator.screenlistRows(15 * 60), 4);

    // One frame per minute, rounded up to a whole row.
    expect(ImageGenerator.screenlistRows(16 * 60), 4);
    expect(ImageGenerator.screenlistRows(17 * 60), 5);
    expect(ImageGenerator.screenlistRows(20 * 60), 5);
    expect(ImageGenerator.screenlistRows(21 * 60), 6);

    // Above the maximum: 96 frames, so 24 rows.
    expect(ImageGenerator.screenlistRows(95 * 60), 24);
    expect(ImageGenerator.screenlistRows(96 * 60), 24);
    expect(ImageGenerator.screenlistRows(120 * 60), 24);
  });
}
