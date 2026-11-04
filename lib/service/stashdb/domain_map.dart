import 'dart:convert';

import 'package:flutter/services.dart';

/// The domains the app writes in a form of its own, read from
/// `assets/stashdb/domain_map.json`.
///
/// The domain rule (`StashController._domain`) writes a domain as the host
/// gives it, and a host is lowercase, so a studio that writes its own domain
/// with capitals — `JacquieEtMichelTV.net` — comes out of the rule in
/// lowercase. The asset is the list of the domains the app writes differently
/// from what the rule gives, one entry per domain, so the field gets the form
/// the studio uses.
///
/// The asset bundle is a constructor parameter rather than `rootBundle`, so the
/// service reads no static (rule 10) and a test can substitute it, as
/// `TemplateStore` does.
class DomainMap {
  DomainMap({required this.bundle});

  final AssetBundle bundle;

  /// The asset, declared under `flutter: assets:` in `pubspec.yaml`.
  static const assetPath = 'assets/stashdb/domain_map.json';

  /// The mapping, keyed by the domain as the app computes it: lowercase,
  /// without `www.`. Keys are read that way so the file can be written as a
  /// person sees the domain rather than as the rule would produce it; a value
  /// is used exactly as it is written, because the point of the file is the
  /// capitals.
  ///
  /// An asset that is not in the bundle, or that is not an object, gives an
  /// empty map, and an entry whose value is not a string is not a mapping, so
  /// it is not read. The mapping is optional data, and a file that does not
  /// parse is a bug in the repository, not something the app can show the user.
  Future<Map<String, String>> load() async {
    final text = await _read();

    if (text == null) return {};

    final Object? decoded;

    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return {};
    }

    if (decoded is! Map<String, dynamic>) return {};

    return {
      for (final entry in decoded.entries)
        if (entry.value is String) _key(entry.key): entry.value,
    };
  }

  /// The key a domain is stored under. It is the same shape `_host()` gives
  /// the controller, so a file written with capitals or with `www.` still
  /// matches the domain the app read from the URL.
  static String _key(String domain) {
    final text = domain.trim().toLowerCase();

    return text.startsWith('www.') ? text.substring(4) : text;
  }

  /// The asset, or null when it is not in the bundle. The bundle reports a key
  /// it does not have with `FlutterError`, which is an `Error` and not an
  /// `Exception`, so `on Exception` alone would let a missing file escape as an
  /// unhandled exception in the running app; the test fakes throw the same
  /// shape.
  Future<String?> _read() async {
    try {
      return await bundle.loadString(assetPath);
    } catch (_) {
      return null;
    }
  }
}
