/// The trackers the app knows. The enum value is the technical name: it is the
/// ID `release.json` writes and the folder the templates are read from.
/// [displayName] is what the app shows, in every language: a tracker is a
/// proper noun the user writes the same way whatever the language, so it is not
/// an `AppLocalizations` key — the same reasoning as `SiteRip`
/// (`release_fields.dart`).
///
/// The two are spelled differently on purpose. The value is a Dart identifier,
/// so it is lowercase; [displayName] is the name as its owner writes it, and
/// that capitalisation is part of the name.
///
/// A web address is not here. It is added when something needs it.
enum Tracker {
  pornolab('PornoLab');

  const Tracker(this.displayName);

  final String displayName;
}

/// The name a manifest holds, or null for a tracker this version does not know.
/// As with a release type, a manifest naming a tracker the app has no field
/// lists, templates or icons for is reported rather than guessed at.
Tracker? trackerFromName(String name) {
  for (final value in Tracker.values) {
    if (value.name == name) {
      return value;
    }
  }

  return null;
}
