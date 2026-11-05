import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/feature/release/field_validation.dart';
import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/release/release_type.dart';

void main() {
  FieldValues values(Map<String, String> entries) {
    final fields = FieldValues();

    for (final entry in entries.entries) {
      fields.setValue(entry.key, entry.value);
    }

    return fields;
  }

  /// The values a single video generation needs, so a test about one rule is
  /// not also about the others. The date is one of the shapes the field
  /// accepts, so a test about another field is not also about the date.
  Map<String, String> complete() => {
    for (final field in fieldListFor(ReleaseType.singleVideo).fields)
      if (field.isRequired)
        field.name: field.name == 'productionDate' ? '2024-05-01' : 'a',
  };

  List<FieldProblem> validate(
    Map<String, String> entries, {
    ReleaseType releaseType = ReleaseType.singleVideo,
  }) => validateFields(fieldListFor(releaseType), values(entries));

  List<String> problems(Map<String, String> entries) =>
      validate(entries).map((problem) => problem.field).toList();

  test('a required field with no value is the problem named by that field', () {
    final entries = complete();
    entries['cast'] = '';

    expect(problems(entries), ['cast']);
  });

  // A field the app fills is required as well: the post shows its value, so a
  // value the probe has not written is a missing value like one the user did
  // not type.
  test('a field the app fills is required as well', () {
    final entries = complete();
    entries['fileSize'] = '';

    expect(problems(entries), ['fileSize']);
  });

  // The names that may be empty: the three the template wraps as conditional
  // sections, the scene link, which is only there to help fill the other fields
  // (`ai/description_template.md`), and the two the Upload draft section stores,
  // which nothing requires — an empty parent forum is only a field the section
  // cannot run with (`ai/uploading_draft.md` §4). An empty one is not a problem.
  test('the optional fields can be empty', () {
    final entries = complete();

    for (final name in [
      'siteNumber',
      'description',
      'additionalInfo',
      'sceneUrl',
      'parentForum',
      'draftUrl',
    ]) {
      entries[name] = '';
    }

    expect(problems(entries), isEmpty);
  });

  test('the date field accepts the three shapes it is allowed to hold', () {
    for (final value in ['2024-05-01', '2024-05', '2024']) {
      expect(problems({...complete(), 'productionDate': value}), isEmpty);
    }
  });

  // The shape is the whole value, so anything around it or inside it is not one
  // of the three.
  test('a date that is not one of the three shapes is a problem', () {
    for (final value in [
      '2024/05/01',
      '2024-5-1',
      '24-05-01',
      '2024-05-01T00:00:00',
      '05-01',
      'May 2024',
    ]) {
      final found = validate({...complete(), 'productionDate': value});

      expect(found, hasLength(1));
      expect(found.first.field, 'productionDate');
      expect(found.first.kind, FieldProblemKind.invalidDate);
    }
  });

  // The app does not decide what a production date can be, so a date the
  // calendar does not have is still the shape the field accepts.
  test(
    'a date the calendar does not have is still the shape the field accepts',
    () {
      expect(
        problems({...complete(), 'productionDate': '2024-02-30'}),
        isEmpty,
      );
    },
  );

  // The value is read as the field holds it, so the spaces a user leaves
  // around a date do not make it a different shape.
  test('the spaces around a value are not part of it', () {
    expect(problems({...complete(), 'productionDate': ' 2024-05 '}), isEmpty);
  });

  // The parent forum is accepted only as a full URL on the site with an `f`
  // parameter, because the request is built from the id in it
  // (`ai/uploading_draft.md` §4).
  test('the parent forum accepts a full forum URL on the site', () {
    for (final value in [
      'https://pornolab.net/forum/viewforum.php?f=1013',
      'http://pornolab.net/forum/viewforum.php?f=1013',
      'https://pornolab.net/forum/viewforum.php?f=1013&sid=7f3a',
    ]) {
      expect(problems({...complete(), 'parentForum': value}), isEmpty);
    }
  });

  // A forum id on its own is not a URL, and a URL that is not the site's or has
  // no `f` is not the shape a request can be built from.
  test('a parent forum that is not a forum URL on the site is a problem', () {
    for (final value in [
      '1013',
      'viewforum.php?f=1013',
      'https://example.com/forum/viewforum.php?f=1013',
      'https://www.pornolab.net/forum/viewforum.php?f=1013',
      'https://pornolab.net/forum/viewtopic.php?t=1',
      'https://pornolab.net/forum/viewforum.php?f=abc',
    ]) {
      final found = validate({...complete(), 'parentForum': value});

      expect(found, hasLength(1));
      expect(found.first.field, 'parentForum');
      expect(found.first.kind, FieldProblemKind.invalidForumUrl);
    }
  });

  // The rule the section gates its button on is the same rule, asked for one
  // field rather than for the whole list (`ai/uploading_draft.md` §4).
  test('the rule asked for one field is the rule in the list', () {
    final field = fieldListFor(ReleaseType.singleVideo).field('parentForum');

    expect(
      fieldProblem(field, 'https://pornolab.net/forum/viewforum.php?f=1013'),
      isNull,
    );
    expect(fieldProblem(field, '1013')?.kind, FieldProblemKind.invalidForumUrl);
  });

  // A field list that has not stated its rules cannot be validated against
  // them, so the types whose required set is not known are not checked
  // (`lib/TODO.MD`).
  test('a field list that has not stated its rules is not checked', () {
    expect(validate({}, releaseType: ReleaseType.singlePhotoset), isEmpty);
  });

  // The order the message reads is the order the form shows the fields in,
  // which is the order the field list lists them.
  test('the problems are in the order the field list lists the fields', () {
    final entries = complete();

    for (final name in ['videoTitle', 'cast']) {
      entries[name] = '';
    }

    expect(problems(entries), ['cast', 'videoTitle']);
  });
}
