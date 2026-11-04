import 'dart:io';

import 'package:path/path.dart' as p;

import '../images/image_dimensions.dart';

/// What the scan treats as an item (`ai/release_structure.md` §9,
/// `ai/single_photoset.md` §5). A type decides this, so the scan is given the
/// rule rather than holding one: a pack is the entries under the source, a
/// single photoset is the source itself.
enum ItemBoundary {
  /// The items are the entries under the source, not the source itself. How
  /// deep the scan looks is the scan's own rule: the photoset scan takes the
  /// top level, the video scan walks the tree.
  entries,

  /// The source itself is the item. A picked file is a container containing
  /// only itself, so a file source is always this.
  source,
}

/// One top-level entry in the source, as the scan sees it before deciding what
/// it is.
class SourceEntry {
  const SourceEntry({
    required this.name,
    required this.isDirectory,
    required this.readPath,
  });

  final String name;
  final bool isDirectory;

  /// The path the reader reads this entry from. It is the source itself when
  /// the source is the item, and the entry inside the source otherwise, so the
  /// scan does not join the two again for a picked file
  /// (`ai/single_photoset.md` §5).
  final String readPath;
}

/// One photo the scan found: its name inside the set, and what its header says
/// the dimensions are. Null dimensions means the header could not be read — the
/// photo is still counted, because the extension list is what decides what a
/// photo is, and the scan reports it.
class ScannedPhoto {
  const ScannedPhoto({required this.name, this.dimensions});

  final String name;
  final ImageDimensions? dimensions;

  /// The extension the photo name has, lowercased. This is what the format
  /// aggregate is built from, and every counted photo has one because the
  /// extension list is what decided it is a photo.
  String get extension => p.extension(name).substring(1).toLowerCase();
}

/// One photoset the scan found. Its path is the real path relative to the
/// source, because that is the ID the image records link to; the name without
/// the extension is derived for display somewhere else (`ai/photoset_pack.md`
/// §2).
///
/// The entry is kept because the scan is what decides which reader reads which
/// entry, and the photo that is copied into the release has to go back through
/// that same reader.
class ScannedSet {
  const ScannedSet({required this.entry, required this.photos});

  final SourceEntry entry;

  String get path => entry.name;

  /// The photos, in the order the source gives them.
  final List<ScannedPhoto> photos;

  int get photoCount => photos.length;
}

/// A container the scan reads as one photoset. The readers are the
/// implementations behind this interface (`directory_reader.dart`,
/// `zip_reader.dart`), so adding a format does not change the scan
/// (`ai/photoset_pack.md` §5).
abstract class PhotosetReader {
  /// Whether this entry is a container this reader reads.
  bool canRead(SourceEntry entry);

  /// The photos it holds, in the order the source gives them.
  Future<List<ScannedPhoto>> read(String path);

  /// The whole photo, for the photo that is copied into the release. Reading
  /// the header takes only the bytes the header needs; copying needs the entry
  /// in full, so this is a separate call (`ai/photoset_pack.md` §5). Empty when
  /// the photo is not there or cannot be read, and the caller reports it.
  Future<List<int>> photoBytes(String path, String name);
}

/// The scan, called only when the user asks: opening a release is a read and
/// changes nothing (`ai/release_structure.md` §4). It reads the source, decides
/// which entries are items, and counts and measures the photos in each. It
/// writes nothing and shows no messages (rule 13): the controller writes the
/// items and the widget maps a result to localized text.
class PhotosetScanner {
  PhotosetScanner({required this.readers});

  final List<PhotosetReader> readers;

  Future<ScanResult> scan(String sourcePath, ItemBoundary boundary) async {
    final type = await FileSystemEntity.type(sourcePath);

    if (type == FileSystemEntityType.notFound) {
      return const ScanFailure(ScanFailureKind.sourceNotFound);
    }

    final entries = <SourceEntry>[];

    if (boundary == ItemBoundary.source ||
        type != FileSystemEntityType.directory) {
      // The source is the item: either the type says so, or the source is a
      // file, which is treated as a directory containing only itself so one
      // rule covers both (`ai/release_structure.md` §2).
      entries.add(
        SourceEntry(
          name: p.basename(sourcePath),
          isDirectory: type == FileSystemEntityType.directory,
          readPath: sourcePath,
        ),
      );
    } else {
      try {
        await for (final entity in Directory(sourcePath).list()) {
          entries.add(
            SourceEntry(
              name: p.basename(entity.path),
              isDirectory: entity is Directory,
              readPath: entity.path,
            ),
          );
        }
      } catch (_) {
        return const ScanFailure(ScanFailureKind.sourceNotReadable);
      }
    }

    // The order the source gives is the order the records are written in, so
    // the entries are put in that order before anything is read.
    entries.sort((a, b) => a.name.compareTo(b.name));

    final sets = <ScannedSet>[];
    final skipped = <String>[];

    for (final entry in entries) {
      final reader = _readerFor(entry);

      if (reader == null) {
        // A loose image at the top level is not an item. It is reported, not
        // guessed at.
        skipped.add(entry.name);
        continue;
      }

      sets.add(
        ScannedSet(entry: entry, photos: await reader.read(entry.readPath)),
      );
    }

    return ScanSuccess(sets: sets, skipped: skipped);
  }

  /// The whole photo, for the photo the picker copies into the release. The
  /// reader that read the set is the one that reads its bytes, so the dispatch
  /// here is the same as the scan's.
  Future<List<int>> photoBytes(ScannedSet set, ScannedPhoto photo) async {
    final reader = _readerFor(set.entry);

    if (reader == null) {
      return const [];
    }

    return reader.photoBytes(set.entry.readPath, photo.name);
  }

  PhotosetReader? _readerFor(SourceEntry entry) {
    for (final reader in readers) {
      if (reader.canRead(entry)) {
        return reader;
      }
    }

    return null;
  }
}

sealed class ScanResult {
  const ScanResult();
}

final class ScanSuccess extends ScanResult {
  const ScanSuccess({required this.sets, required this.skipped});

  final List<ScannedSet> sets;

  /// Top-level entries that are not photosets, in the order the source gives
  /// them.
  final List<String> skipped;

  int get totalPhotoCount =>
      [for (final set in sets) set.photoCount]
          .fold(0, (total, count) => total + count);

  /// The smallest and the largest photo by pixel area, across all photos. There
  /// is no per-set minimum or maximum (`ai/photoset_pack.md` §3). Null when no
  /// photo could be measured, because a field is not written with a value the
  /// app does not have.
  ImageDimensions? get minResolution =>
      _extreme((left, right) => left.area < right.area);

  ImageDimensions? get maxResolution =>
      _extreme((left, right) => left.area > right.area);

  /// The distinct extensions among the counted photos, lowercased and sorted
  /// alphabetically — the same rule as the video formats
  /// (`ai/single_photoset.md` §6). Every counted photo has an extension,
  /// because the extension list is what decided it is a photo, so none is
  /// empty.
  List<String> get imageFormats => ([
    for (final set in sets)
      for (final photo in set.photos) photo.extension,
  ]..sort()).toSet().toList();

  ImageDimensions? _extreme(
    bool Function(ImageDimensions, ImageDimensions) isMore,
  ) {
    ImageDimensions? best;

    for (final set in sets) {
      for (final photo in set.photos) {
        final dimensions = photo.dimensions;

        if (dimensions == null) {
          continue;
        }

        if (best == null || isMore(dimensions, best)) {
          best = dimensions;
        }
      }
    }

    return best;
  }

  /// The photos whose header could not be read, as the path of the set and the
  /// photo name.
  List<String> get unreadPhotos => [
    for (final set in sets)
      for (final photo in set.photos)
        if (photo.dimensions == null) '${set.path}/${photo.name}',
  ];

  /// Display names more than one item would share, because `set01.zip` and
  /// `set01/` both read as `set01`. The scan reports it and renames nothing
  /// (`ai/photoset_pack.md` §4); with directories only this cannot happen, so
  /// the report comes with the archive reader.
  Map<String, List<String>> get nameCollisions {
    final names = <String, List<String>>{};

    for (final set in sets) {
      final name = p.basenameWithoutExtension(set.path);
      (names[name] ??= <String>[]).add(set.path);
    }

    return {
      for (final entry in names.entries)
        if (entry.value.length > 1) entry.key: entry.value,
    };
  }
}

enum ScanFailureKind {
  /// The picked folder is not there.
  sourceNotFound,

  /// The picked folder is there but could not be read.
  sourceNotReadable,
}

final class ScanFailure extends ScanResult {
  const ScanFailure(this.kind);

  final ScanFailureKind kind;
}
