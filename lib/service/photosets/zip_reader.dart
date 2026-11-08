import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../images/image_dimensions.dart';
import 'photoset_scanner.dart';

/// The formats this reader reads: ZIP only (`ai/photoset_pack.md` §5). RAR and
/// 7z need a real decoder, not a container parser, so they would mean an
/// external tool as a new required native tool and are not in scope.
const _zipExtensions = {'zip'};

/// A photoset that is a ZIP archive.
///
/// This is the one place rule 12 in `ai/doc.md` is set aside, and the reason is
/// not convenience: the parts a hand-written reader gets wrong are the ones
/// real archives have — zip64 sizes when the plain end-of-central-directory
/// record holds placeholders, data descriptors from a streaming writer,
/// encrypted entries.
///
/// The order is the order the archive lists its entries, which is what
/// `ai/photoset_pack.md` §4 says for an archive; a directory has no order of
/// its own, so the other reader sorts by name.
class ZipPhotosetReader implements PhotosetReader {
  const ZipPhotosetReader();

  @override
  bool canRead(SourceEntry entry) =>
      _zipExtensions.contains(entry.name.split('.').last.toLowerCase());

  @override
  Future<List<ScannedPhoto>> read(String path) async {
    final stream = InputFileStream(path);

    try {
      // The archive is read through a stream over the file, so the entries are
      // windows into it rather than copies of it: a pack is not held in memory.
      final archive = ZipDecoder().decodeStream(stream);
      final photos = <ScannedPhoto>[];

      for (final entry in archive) {
        if (!entry.isFile || !isPhotoExtension(entry.name)) {
          continue;
        }

        photos.add(
          ScannedPhoto(
            name: p.basename(entry.name),
            // The entry's size as the archive states it, uncompressed, which is
            // the size the file has there: the same kind of number as the size
            // on disk for a file in a folder (`ai/photoset_pack.md` §3).
            size: entry.size,
            dimensions: await readImageDimensionsFrom(
              (length) => _readHeader(entry, length),
            ),
          ),
        );
      }

      return photos;
    } catch (_) {
      // An archive that cannot be read is an empty set, as a directory that
      // cannot be listed is: one entry does not fail the whole source.
      return const [];
    } finally {
      stream.closeSync();
    }
  }

  /// The whole entry, for the photo that is copied into the release. The
  /// central directory is read again here, because `read` closes the archive
  /// when it returns; the cost is one lookup per picked photo, and the rule
  /// picks at most [maximumPicks] plus one per set, so it is bounded by the
  /// picks rather than by the pack.
  @override
  Future<List<int>> photoBytes(String path, String name) async {
    final stream = InputFileStream(path);

    try {
      final archive = ZipDecoder().decodeStream(stream);

      for (final entry in archive) {
        // The name `read` reported is the basename of the entry, so this
        // matches what it produced.
        if (entry.isFile && p.basename(entry.name) == name) {
          // The whole entry, decompressed: copying needs the photo in full,
          // which is what reading only the header exists to avoid.
          return entry.readBytes() ?? const [];
        }
      }

      return const [];
    } on ArchiveException {
      // An encrypted entry has no password here, and a truncated one gives what
      // decoded. Either way the photo is not copied and the caller reports it.
      return const [];
    } finally {
      stream.closeSync();
    }
  }

  /// The bytes of an entry's header, without reading the entry. A stored entry
  /// is read as it is; a deflated one is decoded lazily, so only the bytes the
  /// header is made of are decoded. The package's own decode path would
  /// materialise the whole entry, which is what reading headers exists to
  /// avoid.
  ///
  /// The header reader asks for a fixed prefix first and then for more, because
  /// a JPEG's frame marker can be preceded by metadata, so this is called more
  /// than once for one entry. The stream is the entry's own and keeps its read
  /// position between calls, so each read starts from the beginning of the
  /// entry again.
  ///
  /// The lazy path does decrypt, so an encrypted entry is read as well — but
  /// only with a password, which the app does not have. Entries stored with
  /// another method are not decoded here, because a ZIP of photos is stored or
  /// deflated: JPEG, PNG and WebP are already compressed. Both cases give the
  /// header reader bytes it cannot read, and the photo is counted and reported,
  /// as `ai/photoset_pack.md` §4 says.
  Future<List<int>> _readHeader(ArchiveFile entry, int length) async {
    try {
      final stored = entry.rawContent?.getStream(decompress: false);

      if (stored == null) {
        return const [];
      }

      stored.setPosition(0);

      final bytes = entry.compression == CompressionType.deflate
          ? const ZLibDecoder().decodeLazy(stored, raw: true)
          : stored;

      return bytes.readBytes(length).toUint8List();
    } on ArchiveException {
      // A truncated entry gives what decoded, which is not a header, and an
      // encrypted one throws because there is no password. Either way the
      // caller reports the photo, and one entry does not fail the set.
      return const [];
    }
  }
}
