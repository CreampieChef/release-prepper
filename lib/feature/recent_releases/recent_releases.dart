import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../release/release.dart';
import '../release/release_type.dart';
import '../release/tracker.dart';

/// The most the list holds (`ai/recent_releases.md` §2). It is a convenience,
/// not an archive, so it needs a limit, and the entry that leaves is the one
/// opened least recently — the only order a list of recents has.
const maxRecentEntries = 50;

/// One row of the recent list: what the app read the last time it touched a
/// release.
///
/// The values are stored rather than read from `release.json` when the table
/// draws, because a row whose folder is gone still has to show something, and a
/// table that reads fifty manifests to draw itself is fifty file reads for one
/// screen.
class RecentRelease {
  RecentRelease({
    required this.directoryPath,
    required this.tracker,
    required this.releaseType,
    required this.source,
    required this.createdDate,
    required this.lastEditDate,
    required this.lastOpenedDate,
  });

  /// A folder the scan found in the default release directory. Nothing was
  /// read, so there is nothing to show but the name and the path
  /// (`ai/recent_releases.md` §5). It is not an entry and is never written to
  /// the file.
  RecentRelease.discovered(String directoryPath)
    : this(
        directoryPath: directoryPath,
        tracker: '',
        releaseType: '',
        source: '',
        createdDate: null,
        lastEditDate: null,
        lastOpenedDate: null,
      );

  /// The key: what identifies a release on disk, and the only absolute path in
  /// the file.
  final String directoryPath;

  /// The technical names, the ones `release.json` writes. The display names are
  /// resolved when the row is drawn (`release_type.dart`, `tracker.dart`), so a
  /// name this version does not know is shown as the string the file holds —
  /// there is no label for something the app does not have.
  final String tracker;
  final String releaseType;

  /// What the user picked, as the manifest holds it. A video pack depends on
  /// this folder staying where it is, so the row shows it.
  final String source;

  final DateTime? createdDate;
  final DateTime? lastEditDate;

  /// Not a column. It is what the cap decides with, because the only thing a
  /// list of recents can order by is when it was opened.
  final DateTime? lastOpenedDate;

  /// The name is not stored: it is derived from the directory basename, as it
  /// is everywhere else.
  String get name => p.basename(directoryPath);

  Map<String, Object?> toJson() => {
    'directoryPath': directoryPath,
    'tracker': tracker,
    'releaseType': releaseType,
    'source': source,
    if (createdDate != null) 'createdDate': createdDate!.toIso8601String(),
    if (lastEditDate != null) 'lastEditDate': lastEditDate!.toIso8601String(),
    if (lastOpenedDate != null)
      'lastOpenedDate': lastOpenedDate!.toIso8601String(),
  };

  /// A value that is not a date is read as none rather than reported, because
  /// this is a file the user may have edited. A name this version does not know
  /// is kept as the string, for the same reason.
  static RecentRelease fromJson(Map<String, dynamic> json) => RecentRelease(
    directoryPath: json['directoryPath'] is String
        ? json['directoryPath'] as String
        : '',
    tracker: json['tracker'] is String ? json['tracker'] as String : '',
    releaseType: json['releaseType'] is String
        ? json['releaseType'] as String
        : '',
    source: json['source'] is String ? json['source'] as String : '',
    createdDate: _date(json['createdDate']),
    lastEditDate: _date(json['lastEditDate']),
    lastOpenedDate: _date(json['lastOpenedDate']),
  );
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// The contents of `recent_releases.json` as one entry list, in the order the
/// file lists them.
class RecentReleases {
  RecentReleases([List<RecentRelease> entries = const []])
    : entries = List.of(entries);

  final List<RecentRelease> entries;

  RecentRelease? entryFor(String directoryPath) {
    for (final entry in entries) {
      if (entry.directoryPath == directoryPath) {
        return entry;
      }
    }

    return null;
  }

  /// Records one release. The entry for its directory is updated, or added —
  /// re-opening does not add a second row (`ai/recent_releases.md` §3). The
  /// dates are the values the release has now, and the opened date is the
  /// moment of this record.
  ///
  /// The cap is applied here, because it is a rule about the list rather than a
  /// side effect: the entry that leaves is the one opened least recently, and a
  /// date the file does not have is none, so an entry with no opened date is
  /// the first one to go.
  void record(Release release, {required DateTime now}) {
    final entry = RecentRelease(
      directoryPath: release.directoryPath,
      tracker: release.tracker.name,
      releaseType: release.releaseType.name,
      source: release.source,
      createdDate: release.createdDate,
      lastEditDate: release.lastEditDate,
      lastOpenedDate: now,
    );

    final existing = entryFor(release.directoryPath);

    if (existing == null) {
      entries.add(entry);
    } else {
      entries[entries.indexOf(existing)] = entry;
    }

    while (entries.length > maxRecentEntries) {
      entries.remove(_leastRecentlyOpened);
    }
  }

  RecentRelease get _leastRecentlyOpened {
    var oldest = entries.first;

    for (final entry in entries) {
      if (compareDates(entry.lastOpenedDate, oldest.lastOpenedDate) < 0) {
        oldest = entry;
      }
    }

    return oldest;
  }

  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'entries': [for (final entry in entries) entry.toJson()],
  };

  /// A missing `entries` list or one that is not a list reads as empty, and an
  /// entry that is not an object is not kept: this is a file the app writes,
  /// and a row it cannot read is not a row it can show.
  static RecentReleases fromJson(Map<String, dynamic> json) {
    final entries = json['entries'];

    return RecentReleases([
      if (entries is List)
        for (final entry in entries)
          if (entry is Map<String, dynamic>) RecentRelease.fromJson(entry),
    ]);
  }
}

/// A date the file does not have is none, and none is the earliest, so a row
/// without a date is at the end of a newest-first order rather than in the
/// middle of it.
int compareDates(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;

  return a.compareTo(b);
}

/// The order the table shows. The comparator is what the widget builds, because
/// a column shows a display name and a display name is localized (rule 13);
/// this stays pure.
///
/// A tie is broken by the key, so the same data gives the same order. The order
/// the file lists is data (`ai/release_structure.md` §4) and a sort does not
/// rewrite it.
List<RecentRelease> sortEntries(
  List<RecentRelease> entries, {
  required int Function(RecentRelease, RecentRelease) compare,
  required bool descending,
}) {
  final sorted = List.of(entries);

  sorted.sort((a, b) {
    var order = compare(a, b);

    // A tie is broken by the key, so the same data gives the same order for a
    // given direction, and reversing the direction reverses the whole table
    // rather than leaving ties where they were.
    if (order == 0) {
      order = a.directoryPath.compareTo(b.directoryPath);
    }

    return descending ? -order : order;
  });

  return sorted;
}

/// The display name a stored tracker name has, or the name as the file holds it
/// when the app does not know it.
String trackerDisplay(String name) =>
    trackerFromName(name)?.displayName ?? name;

/// The same for a release type. The label is localized, so this is the one
/// place a stored name becomes an `AppLocalizations` key, as `releaseTypeLabel`
/// is for a `ReleaseType`.
String releaseTypeDisplay(String name, AppLocalizations l10n) {
  final type = releaseTypeFromName(name);

  return type == null ? name : releaseTypeLabel(type, l10n);
}
