import 'package:release_prepper/feature/release/release_fields.dart';
import 'package:release_prepper/feature/release/release_type.dart';

/// The values a single video generation needs, so a test that is not about the
/// required fields is not also about them (`ai/description_template.md`
/// §Validation). A test that wants a different value sets it on top of this.
/// The date is one of the shapes the field accepts, so a test about another
/// field is not also about the date.
///
/// It is here rather than in one test file because three of them need it: the
/// controller, the Message section, and the editor. A copy in each would be
/// three fixtures that can disagree, and one that does not satisfy the rule
/// makes every test in that file fail for a reason it is not about.
FieldValues completeFields() {
  final fields = FieldValues();

  for (final field in fieldListFor(ReleaseType.singleVideo).fields) {
    if (field.isRequired) {
      fields.setValue(
        field.name,
        field.name == 'productionDate' ? '2024-05-01' : 'a',
      );
    }
  }

  return fields;
}
