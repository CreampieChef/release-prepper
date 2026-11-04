import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../service/images/masonry.dart';
import '../../service/videos/image_generator.dart';
import '../image_tile.dart';
import '../release/release.dart';
import '../release/release_store.dart';
import '../section_title.dart';
import 'images.dart';
import 'images_store.dart';
import 'screenshots_controller.dart';

/// The Screenshots section below the editor form
/// (`ai/doc.md` §2): its title row with the Generate button at
/// the right, the slider for how many to generate, and the images that are on
/// disk — the screenshots and the screenlist, shown as the run writes them
/// rather than only when it ends, in two equal columns with the screenlist
/// first. With no item it shows the placeholder saying what has to happen
/// first, and its title row has no button, because nothing here can run without
/// a video. The widget owns the slider value, the layout, and the images the
/// run in progress has written; the controller owns the side effects. It
/// resolves its dependencies from the provider scope and builds its own
/// per-widget controller, as the editor does.
class ScreenshotsSection extends StatefulWidget {
  const ScreenshotsSection({
    required this.release,
    required this.onImagesChanged,
    super.key,
  });

  final Release release;

  /// Called when a run ends. A run writes images, so the count the Upload
  /// section shows is no longer the count the release has; the editor passes
  /// the function that tells it (rule 3: a plain callback, not a listener).
  final void Function() onImagesChanged;

  @override
  State<ScreenshotsSection> createState() => _ScreenshotsSectionState();
}

class _ScreenshotsSectionState extends State<ScreenshotsSection> {
  late final ScreenshotsController _controller;

  /// The smallest the slider allows here. It is the section's, not the
  /// generation's: a single video is a post with a set of frames, so 3 is the
  /// least that makes sense, while the Video pack section allows 0 because a
  /// run there can write only the screenlist.
  static const _minCount = 3;

  /// The masonry's tile height for the name under each image, and the gap
  /// between tiles — between the rows and between the columns, so the columns
  /// are what is left after one gap is taken out. The name is a fixed height,
  /// not a share of the column width, so the packing needs both as numbers.
  static const _labelHeight = 20.0;
  static const _gap = 12.0;

  /// The slider value. Widget state: it decides what the section shows and is
  /// passed to the controller, which does not hold it.
  int _count = 5;

  /// The images are being generated. Widget state, for the progress indicator.
  bool _busy = false;

  /// Increments on every image the run writes. It is the key of each tile's
  /// image, so a regenerated screenshot or screenlist is re-resolved and shown
  /// fresh: `Image` only re-resolves when its provider key changes, and the
  /// provider key is the file path, which is the same on a regeneration.
  /// Evicting the cache entry is not enough on its own — an already-mounted
  /// image keeps the stream it resolved the first time. Both halves are
  /// `imageFromFile` and `evictCachedImages`.
  ///
  /// It changes on each written file rather than once per run, because a file
  /// is shown as it is written and the tile for it must re-resolve at that
  /// moment, not at the end of the run.
  int _generation = 0;

  /// The images the run in progress has written, as the controller reports
  /// them. Widget state: the section shows them as they arrive, so a frame
  /// appears when it is written rather than when the run ends. It is cleared
  /// when the run ends, because from then on the manifest is what the section
  /// reads.
  final List<ImageRecord> _running = [];

  @override
  void initState() {
    super.initState();

    _controller = ScreenshotsController(
      release: widget.release,
      generator: context.read<ImageGenerator>(),
      store: context.read<ImagesStore>(),
      releaseStore: context.read<ReleaseStore>(),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _generate(AppLocalizations l10n) async {
    final item = _controller.singleItem();

    if (item == null) {
      return;
    }

    setState(() {
      _busy = true;
      _running.clear();
    });

    final result = await _controller.generate(item, _count, (record) {
      if (!mounted) return;

      // The file was just written, so its cache entry is dropped and its key
      // changes; an already-mounted image keeps the stream it resolved the
      // first time (AGENTS.md §5).
      evictCachedImages([_controller.absolutePath(record)]);

      setState(() {
        _running.add(record);
        _generation += 1;
      });
    });

    if (!mounted) return;

    // The run is over, so the section reads the images the way it always does:
    // the records of the item whose files are on disk. Whatever the run wrote
    // is shown even when it did not finish, because a run that wrote files
    // records them.
    setState(() {
      _running.clear();
      _busy = false;
    });

    // The run wrote images, so the count the Upload section shows is no longer
    // the count the release has. It is told when the run ends, not while it
    // runs, because the records are what the count reads.
    if (result.written.isNotEmpty) {
      widget.onImagesChanged();
    }

    if (result.failure != null) {
      _showMessage(_failureMessage(result.failure!, l10n));
    }
  }

  /// What the section shows: the records of the item whose files are on disk,
  /// plus the records the run in progress has written. A run replaces the
  /// item's records, so the two are the same set at the end of it; while it
  /// runs the files already on disk stay shown and each new frame is added as
  /// it is written, so a regeneration does not blank the section while it
  /// works.
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

  /// A run that could not do the one item this section has is an error, so it
  /// is a message. The Video pack section reports what it could not do to
  /// individual files as a line instead, because a run that did most of them is
  /// not an error.
  String _failureMessage(
    ImageGenerationFailureKind kind,
    AppLocalizations l10n,
  ) => switch (kind) {
    ImageGenerationFailureKind.fileNotFound => l10n.movieFileNotFound,
    ImageGenerationFailureKind.probeToolNotAvailable =>
      l10n.probeToolNotAvailable,
    ImageGenerationFailureKind.probeFailed => l10n.probeFailed,
    ImageGenerationFailureKind.ffmpegNotAvailable => l10n.ffmpegNotAvailable,
    ImageGenerationFailureKind.failed => l10n.screenshotFailed,
    ImageGenerationFailureKind.mtnNotAvailable => l10n.mtnNotAvailable,
    ImageGenerationFailureKind.screenlistFailed => l10n.screenlistFailed,
    ImageGenerationFailureKind.manifestFailed => l10n.imagesManifestFailed,
  };

  /// One image: the box the packing worked out for it, which is the shape its
  /// file reports, so nothing is cropped.
  Widget _tile(ImageRecord record, double height) {
    final path = _controller.absolutePath(record);

    return ImageTile(
      path: path,
      height: height,
      picture: imageFromFile(path, _generation, fit: BoxFit.cover),
    );
  }

  /// The images as a masonry in two equal columns (`ai/picking.md` §7): each
  /// image placed where its column is free, at the shape its file reports. The
  /// screenlist is first in the order the section builds, so it is the first
  /// tile the packing places and the top of the left column.
  ///
  /// Nothing spans here. The shared rule lets a photo wider than
  /// `landscapeSpanRatio` take two columns, and a frame is above that ratio, so
  /// with spans every tile would be as wide as the grid and the grid would be
  /// one column — not two. So the packing is called with a maximum span of 1.
  ///
  /// The gap is between the columns as well as between the rows, so a column is
  /// what is left after one gap is taken out of the width, and each column
  /// starts at its own offset. The packing counts the gap in the height of each
  /// tile, which is what keeps the rows apart; the columns need the same.
  Widget _grid(List<ImageRecord> records) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - _gap) / 2;

        final ratios = [
          for (final record in records)
            _controller.aspectRatio(_controller.absolutePath(record)),
        ];

        final tiles = masonryPositions(
          ratios: ratios,
          columnCount: 2,
          columnWidth: columnWidth,
          labelHeight: _labelHeight,
          gap: _gap,
          maxSpan: 1,
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
                  left: tile.column * (columnWidth + _gap),
                  top: tile.top,
                  width: columnWidth,
                  height: tile.height + _labelHeight + _gap,
                  child: _tile(records[tile.index], tile.height),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The button for the title row. It is always the base, so its size is fixed
  /// by its label and the title row does not reflow when the label changes to
  /// "Regenerate". While busy it is disabled and the spinner is overlaid on
  /// top; the label is made transparent so only the spinner shows, but the
  /// button keeps its exact footprint.
  Widget _generateButton(AppLocalizations l10n, bool hasImages) {
    final theme = Theme.of(context);

    return FilledButton(
      onPressed: _busy ? null : () => _generate(l10n),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            hasImages ? l10n.regenerateScreenshots : l10n.generateScreenshots,
            style: _busy ? TextStyle(color: Colors.transparent) : null,
          ),
          if (_busy)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onPrimary,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final item = _controller.singleItem();

    // With no video picked there is nothing this section can do, so it says
    // what has to happen first rather than showing controls that cannot run.
    if (item == null) {
      return Column(
        key: const ValueKey('screenshotsSection'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(title: l10n.screenshotsSectionTitle),
          const SizedBox(height: 12),
          Text(l10n.selectVideoFirst, style: theme.textTheme.bodySmall),
        ],
      );
    }

    // Only a file that is on disk is shown, for the same reason the image boxes
    // are, plus the files the run in progress has written.
    final images = _imagesFor(item);

    // The screenlist first: the order here is the order the grid packs in, so
    // the screenlist is the first tile and the top of the left column, and the
    // frames fill the columns after it.
    final shown = [
      for (final record in images)
        if (record.kind == ImageKind.screenlist) record,
      for (final record in images)
        if (record.kind == ImageKind.screenshot) record,
    ];

    return Column(
      key: const ValueKey('screenshotsSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The button is in the title row because it is the action of the whole
        // section, not one of the controls that set what it does.
        SectionTitle(
          title: l10n.screenshotsSectionTitle,
          action: _generateButton(l10n, shown.isNotEmpty),
        ),
        const SizedBox(height: 12),
        // The label, the slider and the count on one row, the same shape the
        // Video pack section has. The row is only the label and the controls
        // now that the button is in the title row, so it fits in one column
        // width: the label is about 150 px with the app's font and the slider
        // the rest. The count text has a fixed width so the number changing
        // does not move the slider.
        Row(
          children: [
            Text(l10n.screenshotCountLabel),
            Expanded(
              child: Slider(
                value: _count.toDouble(),
                min: _minCount.toDouble(),
                max: ImageGenerator.maxCount.toDouble(),
                divisions: ImageGenerator.maxCount - _minCount,
                label: '$_count',
                onChanged: (value) => setState(() => _count = value.round()),
              ),
            ),
            // A fixed width so the number changing does not move the slider.
            SizedBox(
              width: 28,
              child: Text('$_count', textAlign: TextAlign.center),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (shown.isEmpty)
          Text(l10n.noScreenshots, style: theme.textTheme.bodySmall)
        else
          _grid(shown),
      ],
    );
  }
}
