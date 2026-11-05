import '../../l10n/app_localizations.dart';
import '../../service/network/pornolab_client.dart';
import 'release_fields.dart';
import 'release_type.dart';

/// The value rules a field list states (`ai/description_template.md`
/// §Validation).
///
/// The rule is pure: it reads the values and says what is wrong, writes nothing
/// and changes no state. It answers with field names rather than text,
/// because a field list is data and a user-visible string comes from
/// `AppLocalizations`.
/// `fieldProblemText` is the other half of it: the words for a problem,
/// chosen by the name the same way `fieldLabel` chooses the words for a
/// name (rule 13). Both widgets that report a problem use it, so the
/// sentence is written once — the Message section joins the lines into the
/// message it shows, the editor puts one line under the row the field has.
///
/// A field list that has not stated its rules is not checked: the required set
/// is known only for the single video type (`lib/TODO.MD`), so for the other
/// types this answers with nothing.
List<FieldProblem> validateFields(FieldList fieldList, FieldValues fields) {
  if (!fieldList.validatesFields) {
    return const [];
  }

  final problems = <FieldProblem>[];

  // The problems are in the order the field list lists the fields, so the
  // message reads in the order the form shows them.
  for (final field in fieldList.fields) {
    final problem = fieldProblem(field, fields.value(field.name));

    if (problem != null) {
      problems.add(problem);
    }
  }

  return problems;
}

/// One field as the rules of that name see it: an empty value where one is
/// required, and the shape a value has to have. The name is what the rule is
/// chosen by, the same way `fieldLabel` chooses the words for a name.
///
/// A section that owns a row asks for the one field it has, because the shape
/// rule for the parent forum is its gate and the required set of its type is not
/// known (`ai/uploading_draft.md` §4).
FieldProblem? fieldProblem(FieldSpec field, String raw) {
  final value = raw.trim();

  if (value.isEmpty) {
    return field.isRequired
        ? FieldProblem(field: field.name, kind: FieldProblemKind.notFilled)
        : null;
  }

  switch (field.name) {
    case 'productionDate':
      if (!_dateValue.hasMatch(value)) {
        return FieldProblem(
          field: field.name,
          kind: FieldProblemKind.invalidDate,
        );
      }
    case 'parentForum':
      if (PornolabClient.forumIdFromUrl(value) == null) {
        return FieldProblem(
          field: field.name,
          kind: FieldProblemKind.invalidForumUrl,
        );
      }
  }

  return null;
}

/// `YYYY`, `YYYY-MM` or `YYYY`: the three shapes the date field accepts, the
/// whole value, so a value with anything around it is not one of them.
///
/// The shape only. A date the calendar does not have — a month of 13, a day of
/// 30 in February — is not reported, because the app does not decide what a
/// production date can be; a release may show a year, or a month, when the site
/// does not know the day.
final _dateValue = RegExp(r'^\d{4}(-\d{2})?(-\d{2})?$');

/// What is wrong with one field: the name and the kind, so the widget can say
/// it in the words that belong to that name.
final class FieldProblem {
  const FieldProblem({required this.field, required this.kind});

  final String field;
  final FieldProblemKind kind;
}

enum FieldProblemKind {
  /// A field the message cannot be generated without, with no value in it.
  notFilled,

  /// A value that is not the shape the field's rule accepts.
  invalidDate,

  /// A parent forum that is not a full URL on the site with an `f` parameter
  /// (`ai/uploading_draft.md` §4).
  invalidForumUrl,
}

/// The words for one problem: the sentence the kind has, with the words the
/// name has (`fieldLabel`, rule 13). It is here rather than in either widget
/// because both report the same problem — the Message section joins these
/// lines into the message it shows, the editor puts one of them under the row
/// the field has — and a line written twice is two lines that can disagree.
String fieldProblemText(
  FieldProblem problem,
  AppLocalizations l10n,
  ReleaseType releaseType,
) => switch (problem.kind) {
  FieldProblemKind.notFilled => l10n.fieldNotFilled(
    fieldLabel(problem.field, l10n, releaseType),
  ),
  FieldProblemKind.invalidDate => l10n.productionDateInvalid(
    fieldLabel(problem.field, l10n, releaseType),
  ),
  FieldProblemKind.invalidForumUrl => l10n.parentForumInvalid(
    fieldLabel(problem.field, l10n, releaseType),
  ),
};
