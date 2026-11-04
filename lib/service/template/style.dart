/// A style file (`ai/description_template.md`): `key = value`, one rule per
/// line.
///
/// A value that contains `{content}` is a wrapper for the slot body. A value
/// without it is emitted as it is, which is how a standalone tag such as `[hr]`
/// is written. An empty value means no wrapper.
///
/// `{token}` in a value is another key of the same file, so a colour is written
/// once. There is no inheritance: a style defines every slot the template uses.
class Style {
  const Style(this._rules);

  const Style.empty() : _rules = const {};

  final Map<String, String> _rules;

  /// Reads the text of a style file. A comment starts at the start of a line,
  /// because `#` inside a value is part of the value. A line with no `=` is
  /// skipped.
  ///
  /// Tokens are resolved here rather than at render time, so a value that
  /// refers to another key is read once. A key that refers to itself through
  /// another key is left as it is rather than resolved forever.
  static Style parse(String text) {
    final raw = <String, String>{};

    for (final line in text.split('\n')) {
      final rule = line.trim();

      if (rule.isEmpty || rule.startsWith('#')) {
        continue;
      }

      final separator = rule.indexOf('=');

      if (separator < 0) {
        continue;
      }

      final key = rule.substring(0, separator).trim();

      if (key.isEmpty) {
        continue;
      }

      raw[key] = rule.substring(separator + 1).trim();
    }

    return Style({
      for (final key in raw.keys) key: _resolve(raw, key, const {}),
    });
  }

  static String _resolve(
    Map<String, String> raw,
    String key,
    Set<String> seen,
  ) {
    if (seen.contains(key)) {
      return raw[key] ?? '';
    }

    final value = raw[key] ?? '';
    final next = seen.union({key});

    var resolved = value;

    for (final entry in raw.entries) {
      resolved = resolved.replaceAll(
        '{${entry.key}}',
        entry.key == key ? '{${entry.key}}' : _resolve(raw, entry.key, next),
      );
    }

    return resolved;
  }

  /// The text a slot produces.
  ///
  /// A slot the style does not define returns its content unchanged. Validation
  /// is not implemented yet (`lib/TODO.MD`), so an incomplete style renders
  /// rather than reports.
  String render(String slot, String content) {
    final rule = _rules[slot];

    if (rule == null || rule.isEmpty) {
      return content;
    }

    return rule.contains('{content}')
        ? rule.replaceAll('{content}', content)
        : rule;
  }
}
