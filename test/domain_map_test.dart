import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/service/stashdb/domain_map.dart';

void main() {
  DomainMap withAsset(String contents) =>
      DomainMap(bundle: _FakeBundle({DomainMap.assetPath: contents}));

  test('the asset maps a domain to the form the app writes for it', () async {
    final map = await withAsset(
      '{"jacquieetmicheltv.net": "JacquieEtMichelTV.net"}',
    ).load();

    expect(map, {'jacquieetmicheltv.net': 'JacquieEtMichelTV.net'});
  });

  // A key is read as the app computes the domain, so the file can be written
  // as a person sees the domain rather than as the rule would produce it. The
  // value is used exactly as it is written, because the capitals are the point
  // of the file.
  test('a key is read as the app computes the domain', () async {
    final map = await withAsset('{"www.JacquieEtMichelTV.net": "X"}').load();

    expect(map, {'jacquieetmicheltv.net': 'X'});
    expect(map['jacquieetmicheltv.net'], 'X');
  });

  // A JSON object's keys are strings, so the only thing that can be wrong with
  // an entry is its value; an entry whose value is not a string is not a
  // mapping, so it is not read.
  test('an entry whose value is not a string is not read', () async {
    final map = await withAsset('{"a": 1, "c": "d"}').load();

    expect(map, {'c': 'd'});
  });

  // The mapping is optional data, so nothing about the file is something the
  // app can show the user: an asset that is not in the bundle, or that does
  // not parse, or that is not an object, gives an empty map.
  test(
    'an asset that is not there or does not parse gives an empty map',
    () async {
      expect(await DomainMap(bundle: _FakeBundle({})).load(), isEmpty);
      expect(await withAsset('not json').load(), isEmpty);
      expect(await withAsset('["a", "b"]').load(), isEmpty);
    },
  );

  // The file the app ships is the one the app reads, so it is checked here: it
  // is an object of strings, and the entry it holds is the domain the mapping
  // exists for.
  test('the asset in the repository is an object of strings', () async {
    final contents = File('assets/stashdb/domain_map.json').readAsStringSync();

    expect(jsonDecode(contents), isA<Map<String, dynamic>>());
    expect(
      await DomainMap(bundle: _FakeBundle({DomainMap.assetPath: contents}))
          .load(),
      {'jacquieetmicheltv.net': 'JacquieEtMichelTV.net'},
    );
  });
}

/// An asset bundle that answers from a map, so the parse is tested without the
/// bundle on disk, except where a test is about the file itself.
class _FakeBundle extends AssetBundle {
  _FakeBundle(this.contents);

  final Map<String, String> contents;

  @override
  Future<ByteData> load(String key) async {
    final text = contents[key];

    if (text == null) {
      // The shape the real bundle throws, so the service's guard is tested
      // against it rather than against a plain Exception, which `on Exception`
      // would catch and the app would not.
      throw FlutterError('Unable to load asset: "$key".');
    }

    return ByteData.sublistView(utf8.encode(text));
  }
}
