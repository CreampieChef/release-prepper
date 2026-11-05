import 'style.dart';

/// The template engine (`ai/description_template.md`). Six constructs and no
/// others: variables, conditional sections, inverted sections, style slots,
/// `{{blank}}`, and block variables.
///
/// The template is read line by line and each line produces one output line. A
/// line that produces nothing is dropped, which is what keeps a skipped field
/// from leaving a blank line in the post. Consecutive blank lines collapse to
/// one, because an optional field can be empty and two `{{blank}}` become
/// adjacent when it is. Leading and trailing blank lines are trimmed, and the
/// result has no trailing newline.
///
/// It is written by hand rather than taken from a package, because rule 12
/// allows no third-party packages and the subset needed is small.
class TemplateRenderer {
  const TemplateRenderer();

  RenderResult render({
    required String template,
    required Style style,
    required Map<String, String> values,
  }) {
    final out = <String>[];

    for (final line in template.split('\n')) {
      final parsed = _parseLine(line);

      if (parsed == null) {
        return const RenderFailure(RenderFailureKind.unbalancedSection);
      }

      for (final produced in _evalLine(parsed, style, values)) {
        // Consecutive blank lines collapse to one.
        if (produced.isEmpty && out.isNotEmpty && out.last.isEmpty) {
          continue;
        }

        out.add(produced);
      }
    }

    while (out.isNotEmpty && out.first.isEmpty) {
      out.removeAt(0);
    }

    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }

    return RenderSuccess(out.join('\n'));
  }

  /// One line of the template. A `{{blank}}` closes the current line and starts
  /// an empty one; a line that renders to nothing produces no output line at
  /// all.
  List<String> _evalLine(
    List<_Node> nodes,
    Style style,
    Map<String, String> values,
  ) {
    final lines = <String>[];
    var current = '';

    for (final node in nodes) {
      if (node is _Blank) {
        lines.add(current);
        current = '';
        continue;
      }

      final value = _evalString(node, style, values);

      // A block variable expands to as many lines as the block has, and each of
      // those lines is subject to the same rules as a line of the template.
      if (value.contains('\n')) {
        final parts = value.split('\n');
        current += parts.first;

        for (final part in parts.skip(1)) {
          lines.add(current);
          current = part;
        }

        continue;
      }

      current += value;
    }

    if (current.isNotEmpty) {
      lines.add(current);
    }

    return lines;
  }

  String _evalString(_Node node, Style style, Map<String, String> values) {
    switch (node) {
      case _Text(text: final text):
        return text;
      case _Variable(name: final name):
        return values[name] ?? '';
      case _Blank():
        return '\n';
      case _Section(
        name: final name,
        inverted: final inverted,
        children: final children,
      ):
        final content = [
          for (final child in children) _evalString(child, style, values),
        ].join();

        if (name.startsWith('style.')) {
          return style.render(name.substring(6), content);
        }

        final value = values[name] ?? '';

        if (inverted) {
          return value.isEmpty ? content : '';
        }

        return value.isEmpty ? '' : content;
    }
  }

  /// One line of the template, or null when a section is not closed on the same
  /// line.
  List<_Node>? _parseLine(String line) {
    final root = _Section('', false, []);
    final stack = <_Section>[root];
    var position = 0;

    while (position < line.length) {
      final open = line.indexOf('{{', position);

      if (open < 0) {
        stack.last.children.add(_Text(line.substring(position)));
        break;
      }

      if (open > position) {
        stack.last.children.add(_Text(line.substring(position, open)));
      }

      final close = line.indexOf('}}', open + 2);

      if (close < 0) {
        return null;
      }

      final tag = line.substring(open + 2, close);
      position = close + 2;

      if (tag.startsWith('#')) {
        final section = _Section(tag.substring(1), false, []);
        stack.last.children.add(section);
        stack.add(section);
      } else if (tag.startsWith('^')) {
        final section = _Section(tag.substring(1), true, []);
        stack.last.children.add(section);
        stack.add(section);
      } else if (tag.startsWith('/')) {
        if (stack.length < 2 || stack.last.name != tag.substring(1)) {
          return null;
        }

        stack.removeLast();
      } else if (tag == 'blank') {
        stack.last.children.add(const _Blank());
      } else {
        stack.last.children.add(_Variable(tag));
      }
    }

    if (stack.length > 1) {
      return null;
    }

    return root.children;
  }
}

sealed class _Node {
  const _Node();
}

final class _Text extends _Node {
  const _Text(this.text);

  final String text;
}

final class _Variable extends _Node {
  const _Variable(this.name);

  final String name;
}

final class _Blank extends _Node {
  const _Blank();
}

final class _Section extends _Node {
  const _Section(this.name, this.inverted, this.children);

  final String name;
  final bool inverted;
  final List<_Node> children;
}

sealed class RenderResult {
  const RenderResult();
}

final class RenderSuccess extends RenderResult {
  const RenderSuccess(this.text);

  final String text;
}

final class RenderFailure extends RenderResult {
  const RenderFailure(this.kind);

  final RenderFailureKind kind;
}

enum RenderFailureKind {
  /// A section opened on a line is not closed on the same line. The engine
  /// reads one line at a time, so a section cannot span lines.
  unbalancedSection,
}
