import 'dart:io';

import 'package:path/path.dart' as p;

import '../images/image_dimensions.dart';
import 'photoset_scanner.dart';

/// A photoset that is a directory.
///
/// A set is the files directly inside it. A subfolder inside a set is not read:
/// the question of whether a photoset may contain subfolders is still open
/// (`ai/photoset_pack.md` §9), so the reader does not decide it by accident.
class DirectoryPhotosetReader implements PhotosetReader {
  const DirectoryPhotosetReader();

  @override
  bool canRead(SourceEntry entry) => entry.isDirectory;

  @override
  Future<List<ScannedPhoto>> read(String path) async {
    final photos = <ScannedPhoto>[];

    try {
      await for (final entity in Directory(path).list()) {
        if (entity is! File || !isPhotoExtension(entity.path)) {
          continue;
        }

        photos.add(
          ScannedPhoto(
            name: p.basename(entity.path),
            size: (await entity.stat()).size,
            dimensions: await readImageDimensions(entity.path),
          ),
        );
      }
    } catch (_) {
      // A set whose contents cannot be listed is an empty set. The scan reports
      // the set as it found it rather than failing the whole source for one
      // entry.
      return const [];
    }

    // A directory has no order of its own, so the order is the one a file
    // manager shows: by name (`ai/photoset_pack.md` §4).
    photos.sort((a, b) => a.name.compareTo(b.name));

    return photos;
  }

  @override
  Future<List<int>> photoBytes(String path, String name) async {
    try {
      return await File(p.join(path, name)).readAsBytes();
    } catch (_) {
      // A photo that cannot be read is not copied, and the caller reports it.
      return const [];
    }
  }
}
