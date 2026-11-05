import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:release_prepper/service/fonts/font_store.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('font_store_test');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  // The bytes are not a font: this is a test about what the store writes, so it
  // is not also about a real font file. The length is what the check compares,
  // so the marker used below has to be a different length.
  final asset = List.filled(200, 1);

  final assets = {'assets/fonts/Roboto-Regular.ttf': asset};

  FontStore store() => FontStore(
    bundle: _FakeBundle(assets),
    appDirectory: () async => directory,
  );

  String fontPath() => p.join(directory.path, 'fonts', FontStore.fontFileName);

  test('the first call writes the font and returns its path', () async {
    final path = await store().fontPath();

    expect(path, fontPath());
    expect(File(path).readAsBytesSync(), asset);
  });

  // A run that generates screenlists calls this for every video, so the second
  // call must not rewrite the font. A file of the same length is left alone, and
  // the marker below is what shows it was not rewritten.
  test('a font that already matches the asset is not rewritten', () async {
    await store().fontPath();

    final font = File(fontPath());
    font.writeAsBytesSync(List.filled(200, 9));

    expect(await store().fontPath(), font.path);
    expect(font.readAsBytesSync(), List.filled(200, 9));
  });

  test('a font that does not match the asset is rewritten', () async {
    await store().fontPath();

    final font = File(fontPath());
    font.writeAsBytesSync([1, 2, 3]);

    await store().fontPath();

    expect(font.readAsBytesSync(), asset);
  });
}

/// An asset bundle that answers from a map of bytes, so the store is tested
/// without the font files on disk.
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
