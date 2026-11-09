import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../service/images/masonry.dart';
import '../../service/photosets/photoset_scanner.dart';
import '../image_tile.dart';
import '../photosets/photosets_controller.dart';
import '../progress_row.dart';
import '../release/release.dart';
import '../release/release_store.dart';
import '../screenshots/images.dart';
import '../screenshots/images_store.dart';
import '../section_title.dart';
import '../tab/tab_manager.dart';
import 'image_folder_controller.dart';

/// The Image folder section, in place of the Screenshots and Photosets sections
/// for this type (`ai/image_folder_upload.md`): its title row with the Scan
/// button at the right, the images it found shown as a masonry, and what the
/// run could not take reported as a message. The images shown are the ones the
/// run has copied so far, so a tile appears when its file is written rather than
/// when the run ends, and while a run is going its title row is followed by the
/// progress row the Upload section uses for each hoster.
///
/// There is no Pick button, because for this type the scan and the copy are the
/// same action: what the rule copies is every image in the folder, so there is
/// nothing to choose after the scan. There is no slider either, for the same
/// reason the Photoset section has none — the number is what the folder
/// contains, not a choice.
///
/// The widget owns the layout and the widget state — the busy flag, the progress
/// row, the records the run has written, and the generation counter; the
/// controller owns the side effects and reports what it copies through the
/// callback this widget passes. It resolves its dependencies from the provider
/// scope and builds its own per-widget controller, as the other sections do.
///
/// The section does not write fields itself: the values the scan counts are
/// handed to the editor's single write path through `onApplyValues`, so the tab
/// becomes dirty and Ctrl+S saves them.
class ImageFolderSection extends StatefulWidget {
  const ImageFolderSection({
    required this.release,
    required this.tabId,
    required this.onApplyValues,
    super.key,
  });

  final Release release;
  final String tabId;

  /// Writes the values the scan counted through the editor's single write path.
  final void Function(Map<String, String> values) onApplyValues;

  @override
  State<ImageFolderSection> createState() => _ImageFolderSectionState();
}

class _ImageFolderSectionState extends State<ImageFolderSection> {
  late final ImageFolderController _controller;

  /// Which action is running. Widget state, for the progress indicator on the
  /// button that is.
  _Action _action = _Action.none;

  /// What the run going now has copied, as the controller reports it. Widget
  /// state, for the progress row: it is drawn only while a run is going, so it
  /// is cleared when one ends, as the Upload section's rows are.
  CopyProgress? _progress;

  /// The records the run going now has written, as the controller reports them.
  /// Widget state: the section shows them as they arrive, so a tile appears when
  /// its file is copied rather than when the run ends. It is cleared when the run
  /// ends, because from then on the manifest is what the section reads, and the
  /// run's records are in it.
  final List<ImageRecord> _running = [];

  /// Changes on each run, so an image written under the same name is
  /// re-resolved against the emptied cache — see the note on the generation
  /// counter in `AGENTS.md` §5. Re-scanning writes the same names, which is the
  /// case the poster does not have.
  ///
  /// It changes on each file the run copies rather than once per run, because a
  /// file is shown as it is copied and the tile for it must re-resolve at that
  /// moment, not at the end of the run.
  int _generation = 0;

  // The narrowest a column may be: the grid takes as many columns of this width
  // as the space allows. Each tile is as wide as its column, or two columns
  // when the image is clearly landscape, and keeps the image's own ratio, so
  // nothing is cropped (`ai/picking.md` §7).
  static const _tileWidth = 160.0;

  // The name line under a tile, with the gap above it. The packing counts it
  // because a tile is the image and the name together, and it is a fixed height
  // rather than a share of the column width.
  static const _labelHeight = 20.0;

  // The space between two tiles, which is the padding inside each one.
  static const _gap = 8.0;

  @override
  void initState() {
    super.initState();

    _controller = ImageFolderController(
      release: widget.release,
      scanner: context.read<PhotosetScanner>(),
      store: context.read<ImagesStore>(),
      releaseStore: context.read<ReleaseStore>(),
      tabManager: context.read<TabManager>(),
      tabId: widget.tabId,
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scan(AppLocalizations l10n) async {
    setState(() {
      _action = _Action.scan;
      _progress = null;
      _running.clear();
    });

    final result = await _controller.scan(
      onProgress: (progress) {
        if (!mounted) return;

        // A file the run has just copied is shown as it is written, so its cache
        // entry is dropped and its key changes at that moment: an already-mounted
        // image keeps the stream it resolved the first time (`AGENTS.md` §5).
        if (progress.record != null) {
          evictCachedImages([_controller.absolutePath(progress.record!)]);

          setState(() {
            _running.add(progress.record!);
            _generation += 1;
          });
        }

        setState(() => _progress = progress);
      },
    );

    if (!mounted) return;

    if (result is ImageFolderSuccess) {
      widget.onApplyValues(result.values);

      // What the run could not take is reported rather than guessed at: the
      // files in the folder that are not images, the images whose header could
      // not be read, and the images that could not be copied. The strings for
      // the last two are the ones the Photoset section already has, because
      // they say the same thing (`ai/image_folder_upload.md` §5).
      if (result.notImages.isNotEmpty) {
        _showMessage(l10n.imageFolderNotImages(result.notImages.join(', ')));
      }

      if (result.unreadImages.isNotEmpty) {
        _showMessage(l10n.photosetUnreadPhotos(result.unreadImages.join(', ')));
      }

      if (result.notCopied.isNotEmpty) {
        _showMessage(l10n.photosetNotCopied(result.notCopied.join(', ')));
      }
    } else if (result case ImageFolderFailure failure) {
      _showMessage(switch (failure.kind) {
        ImageFolderFailureKind.sourceEmpty => l10n.imageFolderSourceEmpty,
        ImageFolderFailureKind.sourceNotFound => l10n.photosetSourceNotFound,
        ImageFolderFailureKind.sourceNotReadable =>
          l10n.photosetSourceNotReadable,
      });
    }

    if (!mounted) return;

    // The run is over, so the section reads the images the way it always does —
    // the manifest — and the row for a run that is not going is not drawn.
    // Whatever the run copied is still shown, because a run that copied most of
    // the folder is not an error.
    setState(() {
      _action = _Action.none;
      _progress = null;
      _running.clear();
    });
  }

  /// What the section shows for an item: the records it has that are on disk,
  /// plus the records the run going now has copied. A run replaces the item's
  /// records, so the two are the same set at the end of it; while it runs the
  /// files already on disk stay shown and each new one is added as it is copied,
  /// so a re-scan does not blank the section while it works.
  List<ImageRecord> _imagesFor(ReleaseItem item) {
    if (_running.isEmpty) {
      return _controller.imagesFor(item);
    }

    final shown = {
      for (final record in _controller.imagesFor(item)) record.file: record,
      for (final record in _running) record.file: record,
    };

    return [for (final record in shown.values) record];
  }

  Widget _tile(String path, double imageHeight) => Padding(
    padding: const EdgeInsets.all(4),
    child: ImageTile(
      path: path,
      // The box is the size the packing worked out for this image, which is its
      // own ratio, so nothing is cropped.
      height: imageHeight,
      picture: imageFromFile(path, _generation, fit: BoxFit.cover),
    ),
  );

  /// The images of the folder as a masonry: columns of equal width, each image
  /// placed where its column is free, and an image clearly wider than it is
  /// tall spanning two columns (`ai/picking.md` §7). An image whose header
  /// could not be read takes a square tile.
  ///
  /// A tile that spans two columns cannot be a child of one column, so the grid
  /// is placed by position rather than by nesting, and the positions come from
  /// the pure function.
  Widget _grid(List<String> paths) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _tileWidth * 3;

        // At least one column. Each column is at least the tile width, so the
        // number of columns is bounded by the space there is, and no cap is
        // needed. With one column nothing can span.
        final columnCount = width >= _tileWidth ? width ~/ _tileWidth : 1;
        final columnWidth = width / columnCount;

        final ratios = [
          for (final path in paths) _controller.aspectRatio(path),
        ];

        final tiles = masonryPositions(
          ratios: ratios,
          columnCount: columnCount,
          columnWidth: columnWidth,
          labelHeight: _labelHeight,
          gap: _gap,
        );

        var gridHeight = 0.0;

        for (final tile in tiles) {
          final bottom = tile.top + tile.height + _labelHeight + _gap;

          if (bottom > gridHeight) {
            gridHeight = bottom;
          }
        }

        return SizedBox(
          height: gridHeight,
          child: Stack(
            children: [
              for (final tile in tiles)
                Positioned(
                  left: tile.column * columnWidth,
                  top: tile.top,
                  width: tile.span * columnWidth,
                  height: tile.height + _labelHeight + _gap,
                  child: _tile(paths[tile.index], tile.height),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _button(String label, void Function() onPressed) {
    final theme = Theme.of(context);

    return FilledButton(
      key: const ValueKey('imageFolderScanButton'),
      onPressed: _action == _Action.none ? onPressed : null,
      child: _action == _Action.scan
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onPrimary,
              ),
            )
          : Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final items = _controller.imageFolder();

    return Column(
      key: const ValueKey('imageFolderSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The button is in the title row because it is the action of the whole
        // section, not of a row inside it. The folder it reads is the source
        // row above the form; the section does not repeat it.
        SectionTitle(
          title: l10n.imageFolderSectionTitle,
          action: _button(l10n.scanPhotosets, () => _scan(l10n)),
        ),
        const SizedBox(height: 12),
        // Only the copy row, because for this type the item is the folder the
        // user picked: a row counting items would always say 1 / 1
        // (`ai/picking.md` §7). The row is drawn only while the run is going.
        if (_progress != null)
          ProgressRow(
            key: const ValueKey('imageFolderCopyProgress'),
            done: _progress!.done,
            total: _progress!.total,
            count: l10n.imageFolderCopyProgress(
              _progress!.done,
              _progress!.total,
            ),
          ),
        if (items.isEmpty)
          Text(l10n.imageFolderNoImages, style: theme.textTheme.bodyMedium)
        else
          for (final item in items) _itemRow(l10n, item),
      ],
    );
  }

  Widget _itemRow(AppLocalizations l10n, ReleaseItem item) {
    final theme = Theme.of(context);
    final images = _imagesFor(item);

    return Column(
      key: ValueKey('image-folder-row-${item.path}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(item.path, style: theme.textTheme.bodyMedium),
              ),
              // The number is the count of what is shown, so it grows as the run
              // copies: the section shows what is on disk, not what the folder
              // held before the run.
              Text(
                l10n.imageFolderCount(images.length),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        _grid([for (final record in images) _controller.absolutePath(record)]),
      ],
    );
  }
}

enum _Action { none, scan }
