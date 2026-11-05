import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/service/template/style.dart';
import 'package:release_prepper/service/template/template_renderer.dart';

void main() {
  const renderer = TemplateRenderer();

  String render(String template, Map<String, String> values, {Style? style}) {
    final result = renderer.render(
      template: template,
      style: style ?? Style.empty(),
      values: values,
    );

    return (result as RenderSuccess).text;
  }

  test('a variable produces its value', () {
    expect(
      render('{{videoTitle}}', {'videoTitle': 'Example title'}),
      'Example title',
    );
  });

  test('a conditional section renders when the value is not empty', () {
    const template =
        '{{#siteNumber}}Site number: {{siteNumber}}{{/siteNumber}}';

    expect(render(template, {'siteNumber': '123'}), 'Site number: 123');
  });

  // A line that is only a section produces nothing when the section is skipped,
  // so a skipped optional field does not leave a blank line in the post.
  test('a skipped section produces no line at all', () {
    const template = '''
first
{{#siteNumber}}Site number: {{siteNumber}}{{/siteNumber}}
last''';

    expect(render(template, {'siteNumber': ''}), 'first\nlast');
  });

  test('an inverted section renders when the value is empty', () {
    const template = '{{^cast}}no cast{{/cast}}';

    expect(render(template, {'cast': ''}), 'no cast');
    expect(render(template, {'cast': 'Someone'}), '');
  });

  test('a style slot wraps its content', () {
    final style = Style.parse('label = [b]{content}[/b]');

    expect(
      render('{{#style.label}}Cast{{/style.label}}', {}, style: style),
      '[b]Cast[/b]',
    );
  });

  test('{{blank}} produces an empty line in the output', () {
    expect(render('a\n{{blank}}\nb', {}), 'a\n\nb');
  });

  // An empty line in the template is breathing room in the source, not output.
  test('an empty line in the template produces nothing', () {
    expect(render('a\n\nb', {}), 'a\nb');
  });

  // Two blanks become adjacent when the optional section between them is
  // skipped.
  test('consecutive blank lines collapse to one', () {
    const template = '''
a
{{blank}}
{{#description}}desc{{/description}}
{{blank}}
b''';

    expect(render(template, {'description': ''}), 'a\n\nb');
    expect(render(template, {'description': 'desc'}), 'a\n\ndesc\n\nb');
  });

  test('leading and trailing blank lines are trimmed', () {
    expect(render('{{blank}}\na\n{{blank}}', {}), 'a');
  });

  test('the result has no trailing newline', () {
    expect(render('a\n', {}), 'a');
  });

  test('a block variable is inserted as it is, with its own lines', () {
    expect(
      render('{{screenshotSection}}', {
        'screenshotSection': '[spoiler][url=x][img]y[/img][/url][/spoiler]',
      }),
      '[spoiler][url=x][img]y[/img][/url][/spoiler]',
    );
  });

  // The block is built by the app, so its lines are the lines the post shows.
  // Each of them is subject to the same rules as a line of the template.
  test('a multi-line block produces one output line per block line', () {
    const block =
        '[spoiler="Скриншоты"]\n[url=a][img]b[/img][/url][url=c][img]d[/img][/url]\n[/spoiler]';

    expect(
      render('title\n{{blank}}\n{{screenshotSection}}', {
        'screenshotSection': block,
      }),
      'title\n\n$block',
    );
  });

  test('an empty block produces no line, so the blank before it collapses', () {
    expect(
      render('a\n{{blank}}\n{{screenshotSection}}', {'screenshotSection': ''}),
      'a',
    );
  });

  test('a section not closed on the same line is reported', () {
    final result = renderer.render(
      template: '{{#cast}}unclosed',
      style: Style.empty(),
      values: {'cast': 'Someone'},
    );

    expect(result, isA<RenderFailure>());
    expect((result as RenderFailure).kind, RenderFailureKind.unbalancedSection);
  });
}
