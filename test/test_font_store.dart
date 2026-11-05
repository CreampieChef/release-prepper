import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/service/fonts/font_store.dart';

/// A `FontStore` for tests. The bundle answers with the bytes given and the app
/// data directory is a temp directory of its own, so the store writes there
/// rather than into the app's.
///
/// The bytes are not a font. A test that is not about the font passes this and
/// never reads what the store writes; the font behaviour is in
/// `test/font_store_test.dart`, which builds its own store. A real tool call
/// through this opens a file that is not a font, so the tool reports it cannot
/// open it and still writes the screenlist, without the info text.
FontStore testFontStore() {
  final directory = Directory.systemTemp.createTempSync('test_font_store');

  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  return FontStore(
    bundle: _FakeBundle({
      'assets/fonts/Roboto-Regular.ttf': const [1],
    }),
    appDirectory: () async => directory,
  );
}

class _FakeBundle extends AssetBundle {
  _FakeBundle(this.contents);

  final Map<String, List<int>> contents;

  @override
  Future<ByteData> load(String key) async {
    final bytes = contents[key];

    if (bytes == null) {
      // The shape the real bundle throws, so a missing asset is tested against it
      // rather than against a plain Exception.
      throw FlutterError('Unable to load asset: "$key".');
    }

    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
