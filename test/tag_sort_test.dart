import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/feature/release/tag_sort.dart';

void main() {
  test('the parts are put in alphabetical order', () {
    expect(sortedTagLine('solo, anal, battle'), 'anal, battle, solo');
  });

  // The spaces around a part are not part of a tag, and a part with nothing in
  // it says nothing, so a line with a double or a trailing comma is the same
  // line without them.
  test('the spaces around a part are not part of it', () {
    expect(sortedTagLine(' solo ,anal,, ,'), 'anal, solo');
  });

  // One tag is one tag whatever the user capitalized it, so the order does not
  // depend on case.
  test('the order does not depend on case', () {
    expect(sortedTagLine('Battle, anal'), 'anal, Battle');
  });

  // A tag the line already has is not written twice, and the first spelling is
  // the one kept, because that is the one the user typed.
  test('a tag is written once, with the first spelling', () {
    expect(sortedTagLine('Anal, anal, solo'), 'Anal, solo');
  });

  // A line with nothing in it answers with nothing, as the field shows nothing
  // when the user typed nothing.
  test('a line with nothing in it answers with nothing', () {
    expect(sortedTagLine(''), '');
    expect(sortedTagLine(' , '), '');
  });

  // The parts are joined as the app writes a tag line elsewhere: the Stash
  // section joins the tags it fetched with a comma and a space, so sorting does
  // not change the shape, only the order.
  test('the parts are joined as the app writes a tag line', () {
    expect(sortedTagLine('solo,anal'), 'anal, solo');
  });
}
