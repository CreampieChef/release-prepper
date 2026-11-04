import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/feature/release/file_size.dart';
import 'package:release_prepper/l10n/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('the byte count is shown in a human-friendly form as well', () {
    expect(formatFileSize('10200000000', l10n), '9.5 GiB (10200000000 bytes)');
    expect(formatFileSize('1500', l10n), '1.5 KiB (1500 bytes)');
    expect(
      formatFileSize('1234567890123', l10n),
      '1.1 TiB (1234567890123 bytes)',
    );
  });

  // Below 1 KiB there is no shorter form than the byte count, so the display
  // would only repeat it.
  test('a byte count with no shorter form is shown as the number', () {
    expect(formatFileSize('512', l10n), '512');
  });

  // A manifest edited by hand can hold anything.
  test('a value that is not a number is shown as it is', () {
    expect(formatFileSize('unknown', l10n), 'unknown');
  });

  // The human form alone is what a fixed-width cell shows, as the Video pack
  // table's size column.
  test('the human form alone is what a fixed-width cell shows', () {
    expect(humanFileSize('10200000000'), '9.5 GiB');
    expect(humanFileSize('1500'), '1.5 KiB');

    // A value with no shorter form is the byte count, so a caller does not
    // handle that case separately.
    expect(humanFileSize('512'), '512');
    expect(humanFileSize('unknown'), 'unknown');
  });
}
