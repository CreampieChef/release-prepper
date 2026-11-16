/// The order the tags a field holds are written in.
///
/// The rule is pure: it reads the line a field holds and answers with the same
/// tags in alphabetical order, writes nothing and changes no state. It is here
/// rather than in the widget that offers the button, because it is a rule about
/// a value and not a shape of a row (rule 2); the widget reads the answer and
/// writes it through the editor's single write path, so the tab becomes dirty
/// and the sections that read the values are told, exactly as for a keystroke.
///
/// A part of the line is what sits between two commas: the spaces around it are
/// not part of a tag, and a part with nothing in it says nothing, so an empty
/// one is dropped. A tag the line already has is not written twice, and the
/// first spelling is the one kept, because that is the one the user typed.
///
/// The order does not depend on case, because one tag is one tag whatever the
/// user capitalized it — the values are the tag names the site holds, which are
/// English and come already in lowercase, so a capitalized one is what the user
/// typed (`ai/release_editor.md` §7).
///
/// The joined line is the shape the app writes these values in everywhere else:
/// the Stash section joins the tags it fetched with a comma and a space, so
/// sorting a line changes its order and not its shape.
String sortedTagLine(String line) {
  final tags = <String>[];
  final seen = <String>{};

  for (final part in line.split(',')) {
    final tag = part.trim();

    if (tag.isEmpty) {
      continue;
    }

    // A duplicate is the same tag written twice, so the first spelling stays.
    if (seen.add(tag.toLowerCase())) {
      tags.add(tag);
    }
  }

  tags.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  return tags.join(', ');
}
