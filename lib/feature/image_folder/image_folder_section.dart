import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../service/images/masonry.dart';
import '../../service/photosets/photoset_scanner.dart';
import '../image_tile.dart';
import '../release/release.dart';
import '../release/release_store.dart';
import '../screenshots/images_store.dart';
import '../section_title.dart';
import '../tab/tab_manager.dart';
import 'image_folder_controller.dart';

/// The Image folder section, in place of the Screenshots and Photosets sections
/// for this type (`ai/image_folder_upload.md`): its title row with the Scan
/// button at the right, the images it found shown as a masonry, and what the
/// run could not take reported as a message.
///
/// There is no Pick button, because for this type the scan and the copy are the
/// same action: what the rule copies is every image in the folder, so there is
/// nothing to choose after the scan. There is no slider either, for the same
/// reason the Photoset section has none — the number is what the folder
/// contains, not a choice.
///
/// The widget owns the layout and the widget state — the busy flag and the
/// generation counter; the controller owns the side effects. It resolves its
/// dependencies from the provider scope and builds its own per-widget
/// controller, as the other sections do.
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

  /// Changes on each run, so an image written under the same name is
  /// re-resolved against the emptied cache — see the note on the generation
  /// counter in `AGENTS.md` §5. Re-scanning writes the same names, which is the
  /// case the poster does not have.
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
    setState(() => _action = _Action.scan);

    final result = await _controller.scan();

    if (!mounted) return;

    if (result is ImageFolderSuccess) {
      widget.onApplyValues(result.values);

      // Whatever the run wrote is shown, even when it did not finish: an image
      // that could not be copied must not hide the ones that were.
      if (result.written.isNotEmpty) {
        evictCachedImages([
          for (final record in result.written) _controller.absolutePath(record),
        ]);
        setState(() => _generation += 1);
      }

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
    setState(() => _action = _Action.none);
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
        if (items.isEmpty)
          Text(l10n.imageFolderNoImages, style: theme.textTheme.bodyMedium)
        else
          for (final item in items) _itemRow(l10n, item),
      ],
    );
  }

  Widget _itemRow(AppLocalizations l10n, ReleaseItem item) {
    final theme = Theme.of(context);
    final images = _controller.imagesFor(item);

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
              // The number comes from the records that exist, so it appears
              // only after a run: the section shows what is on disk.
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
