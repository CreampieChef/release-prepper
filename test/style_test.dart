import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/service/template/style.dart';

void main() {
  test('a value with {content} is a wrapper for the slot body', () {
    final style = Style.parse('label = [b]{content}[/b]');

    expect(style.render('label', 'Cast'), '[b]Cast[/b]');
  });

  test('a value with no {content} is emitted as it is', () {
    final style = Style.parse('rule = [hr]');

    expect(style.render('rule', ''), '[hr]');
  });

  test('an empty value means no wrapper', () {
    final style = Style.parse('text =');

    expect(style.render('text', 'plain text'), 'plain text');
  });

  test('a comment starts at the start of a line, not inside a value', () {
    final style = Style.parse('''
# a comment
accent = #1a1a1a
label  = [b][color={accent}]{content}[/color][/b]
''');

    expect(style.render('label', 'Cast'), '[b][color=#1a1a1a]Cast[/color][/b]');
  });

  test('a token is another key of the same file', () {
    final style = Style.parse('''
accent = #1a1a1a
heading = [color={accent}]{content}[/color]
''');

    expect(style.render('heading', 'Title'), '[color=#1a1a1a]Title[/color]');
  });

  // A key that refers to itself through another key would otherwise never
  // finish.
  test('a token cycle is left as it is rather than resolved forever', () {
    final style = Style.parse('''
a = {b}
b = {a}
''');

    expect(style.render('a', 'x'), '{b}');
  });

  // Validation is not implemented yet (lib/TODO.MD), so an incomplete style
  // renders rather than reports.
  test('a slot the style does not define returns its content unchanged', () {
    expect(Style.empty().render('label', 'Cast'), 'Cast');
  });
}
