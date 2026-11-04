import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../service/images/masonry.dart';
import '../../service/photosets/photoset_scanner.dart';
import '../image_tile.dart';
import '../release/release.dart';
import '../release/release_store.dart';
import '../release/release_type.dart';
import '../screenshots/images_store.dart';
import '../section_title.dart';
import '../tab/tab_manager.dart';
import 'photosets_controller.dart';

/// The Photoset section, in place of the Screenshots section for a photoset
/// (`ai/photoset_pack.md` §4, §6, `ai/single_photoset.md` §7): its title row
/// with the Scan and Pick buttons at the right, the photosets it found with the
/// number of photos in each, and the photos the rule picked, grouped per set
/// (`ai/picking.md` §7). The same widget serves a single photoset: with one
/// item the grid holds one card, and nothing in the layout branches on the
/// type. Only the strings it shows are resolved per type
/// (`ai/single_photoset.md` §4).
///
/// There is no slider: the number is decided by the rule, and the section shows
/// what it decided rather than letting the user change it. Pick is disabled
/// until a scan has run, because the rule reads the counts.
///
/// The widget owns the layout and the widget state — the busy flag, the last
/// scan the section was given, and the generation counter; the controller owns
/// the side effects. It resolves its dependencies from the provider scope and
/// builds its own per-widget controller, as the other sections do.
///
/// The section does not write fields itself: the values the scan counts are
/// handed to the editor's single write path through `onApplyValues`, so the tab
/// becomes dirty and Ctrl+S saves them.
class PhotosetSection extends StatefulWidget {
  const PhotosetSection({
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
  State<PhotosetSection> createState() => _PhotosetSectionState();
}

class _PhotosetSectionState extends State<PhotosetSection> {
  late final PhotosetController _controller;

  /// Which action is running. Widget state, for the progress indicator on the
  /// button that is.
  _Action _action = _Action.none;

  /// The last scan the section was given. The pick needs the photo names, and
  /// those are what the scan read, so a section that has not scanned cannot
  /// pick.
  ScanSuccess? _lastScan;

  /// Changes on each pick, so a photo written under the same name is
  /// re-resolved against the emptied cache — see the note on the generation
  /// counter in `AGENTS.md` §5. Re-picking writes the same names, which is the
  /// case the poster does not have.
  int _generation = 0;

  // The narrowest a column may be: the grid takes as many columns of this width
  // as the space allows. Each tile is as wide as its column, or two columns
  // when the photo is clearly landscape, and keeps the photo's own ratio, so
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

    _controller = PhotosetController(
      release: widget.release,
      scanner: context.read<PhotosetScanner>(),
      store: context.read<ImagesStore>(),
      releaseStore: context.read<ReleaseStore>(),
      tabManager: context.read<TabManager>(),
      tabId: widget.tabId,
    );
  }

  /// The strings for the type this section is showing (`ai/single_photoset.md`
  /// §4). The first arm is the strings for several sets, which is what every
  /// type that reaches this section has. The single video, the video pack and
  /// the image folder are in it only because a switch over the release types
  /// has to be exhaustive: they have the Screenshots section, the Video pack
  /// section and the Image folder section, so they never reach here.
  _SectionStrings _strings(AppLocalizations l10n) =>
      switch (widget.release.releaseType) {
        ReleaseType.singleVideo ||
        ReleaseType.videoPack ||
        ReleaseType.imageFolderUpload ||
        ReleaseType.photosetPack => _SectionStrings(
          title: l10n.photosetPackSectionTitle,
          emptyText: l10n.photosetPackNoPhotosets,
          pickHint: l10n.photosetPackSourceEmpty,
        ),
        ReleaseType.singlePhotoset => _SectionStrings(
          title: l10n.singlePhotosetSectionTitle,
          emptyText: l10n.singlePhotosetNoPhotosets,
          pickHint: l10n.singlePhotosetSourceEmpty,
        ),
      };

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

    widget.onApplyValues(result.values);

    if (result is PhotosetSuccess) {
      _lastScan = result.scan;
    }

    // What the scan could not take is reported rather than guessed at: entries
    // at the top level that are not photosets, photos whose header could not be
    // read, and display names two items would share.
    if (result.skipped.isNotEmpty) {
      _showMessage(l10n.photosetSkippedEntries(result.skipped.join(', ')));
    }

    if (result.unreadPhotos.isNotEmpty) {
      _showMessage(l10n.photosetUnreadPhotos(result.unreadPhotos.join(', ')));
    }

    // A display name is derived from the path, so `set01.zip` and `set01` both
    // show as `set01`. The two items keep their own paths, which are their IDs.
    if (result.nameCollisions.isNotEmpty) {
      _showMessage(
        l10n.photosetNameCollisions(
          [
            for (final collision in result.nameCollisions.entries)
              '${collision.key} (${collision.value.join(', ')})',
          ].join(', '),
        ),
      );
    }

    if (result case PhotosetFailure failure) {
      _showMessage(switch (failure.kind) {
        PhotosetFailureKind.sourceEmpty => _strings(l10n).pickHint,
        PhotosetFailureKind.sourceNotFound => l10n.photosetSourceNotFound,
        PhotosetFailureKind.sourceNotReadable => l10n.photosetSourceNotReadable,
      });
    }

    if (!mounted) return;
    setState(() => _action = _Action.none);
  }

  Future<void> _pick(AppLocalizations l10n) async {
    final scan = _lastScan;

    if (scan == null) {
      return;
    }

    setState(() => _action = _Action.pick);

    final result = await _controller.pick(scan);

    if (!mounted) return;

    // Whatever the run wrote is shown, even when it did not finish: a photo
    // that could not be copied must not hide the ones that were.
    if (result.written.isNotEmpty) {
      evictCachedImages([
        for (final record in result.written) _controller.absolutePath(record),
      ]);
      setState(() => _generation += 1);
    }

    if (result.notCopied.isNotEmpty) {
      _showMessage(l10n.photosetNotCopied(result.notCopied.join(', ')));
    }

    // A set with no photos contributes nothing to the pick, so it is reported
    // rather than left out.
    if (result.emptySets.isNotEmpty) {
      _showMessage(l10n.photosetEmptySets(result.emptySets.join(', ')));
    }

    if (!mounted) return;
    setState(() => _action = _Action.none);
  }

  /// The count a row shows. The model stores it as a string, so a value that is
  /// not a number — a manifest edited by the user — is shown as it is, the same
  /// way the size field shows a value it cannot format.
  String _count(AppLocalizations l10n, ReleaseItem item) {
    final value = item.fields.value('photoCount');
    final count = int.tryParse(value);

    return count == null ? value : l10n.photosetPhotoCount(count);
  }

  Widget _tile(String path, double imageHeight) => Padding(
    padding: const EdgeInsets.all(4),
    child: ImageTile(
      path: path,
      // The box is the size the packing worked out for this photo, which is its
      // own ratio, so nothing is cropped.
      height: imageHeight,
      picture: imageFromFile(path, _generation, fit: BoxFit.cover),
    ),
  );

  /// The picked photos of one set as a masonry: columns of equal width, each
  /// photo placed where its column is free, and a photo clearly wider than it
  /// is tall spanning two columns (`ai/picking.md` §7). A photo whose header
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

  Widget _button(
    String keyName,
    String label,
    bool enabled,
    _Action running,
    void Function() onPressed,
  ) {
    final theme = Theme.of(context);

    return FilledButton(
      key: ValueKey(keyName),
      onPressed: enabled && _action == _Action.none ? onPressed : null,
      child: _action == running
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
    final photosets = _controller.photosets();
    final strings = _strings(l10n);

    return Column(
      key: const ValueKey('photosetSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The buttons are in the title row because they are the actions of the
        // whole section, not of a row inside it. The folder they read is the
        // source row above the form; the section does not repeat it.
        SectionTitle(
          title: strings.title,
          action: Row(
            children: [
              _button(
                'photosetScanButton',
                l10n.scanPhotosets,
                true,
                _Action.scan,
                () => _scan(l10n),
              ),
              const SizedBox(width: 8),
              // The rule reads the counts, so it cannot run before the scan
              // has.
              _button(
                'photosetPickButton',
                l10n.pickPhotosets,
                _lastScan != null,
                _Action.pick,
                () => _pick(l10n),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (photosets.isEmpty)
          Text(strings.emptyText, style: theme.textTheme.bodyMedium)
        else
          for (final item in photosets) _setRow(l10n, item),
      ],
    );
  }

  Widget _setRow(AppLocalizations l10n, ReleaseItem item) {
    final theme = Theme.of(context);
    final picked = _controller.pickedPhotos(item.path);

    return Column(
      key: ValueKey('photoset-row-${item.path}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _controller.displayName(item.path),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(_count(l10n, item), style: theme.textTheme.bodySmall),
              // The picked number comes from the records that exist, so it
              // appears only after a pick: the section shows what is on disk.
              if (picked.isNotEmpty)
                Text(
                  l10n.photosetPickedCount(picked.length),
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
        _grid(picked),
      ],
    );
  }
}

enum _Action { none, scan, pick }

/// The strings this section shows for the release type it is showing. They
/// assume several sets, so they read wrong for one, and they are resolved per
/// type as `fieldLabel` is (`ai/single_photoset.md` §4). The Scan and Pick
/// buttons, the count line and the report lines are not here: they say the same
/// thing for one set as for many.
class _SectionStrings {
  const _SectionStrings({
    required this.title,
    required this.emptyText,
    required this.pickHint,
  });

  final String title;
  final String emptyText;

  /// What the section says when the user asks it to pick before the source has
  /// been picked.
  final String pickHint;
}
