import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../service/videos/image_generator.dart';
import '../../service/videos/video_scanner.dart';
import '../image_tile.dart';
import '../release/file_size.dart';
import '../release/release.dart';
import '../release/release_fields.dart';
import '../release/release_store.dart';
import '../screenshots/images.dart';
import '../screenshots/images_store.dart';
import '../section_title.dart';
import '../tab/tab_manager.dart';
import 'video_pack_controller.dart';

/// The Video pack section, in place of the Screenshots section for a video pack
/// (`ai/video_pack.md` §5): its title row with the Scan and Generate buttons at
/// the right, the slider, the videos as a table with one row each, and what the
/// runs could not do, listed by name. Nothing is shown before a scan, because
/// opening a release is a read and changes nothing — but a release opened from
/// a manifest shows the items it recorded, because those are what the file
/// holds.
///
/// A row shows the name, the size, the duration, and whether the item has a
/// screenlist and how many screenshots it has; clicking it shows the values the
/// row does not show, and the images the run wrote for that item. The
/// additional data column comes with the feature that fills it, so the table
/// does not show a column that is always empty.
///
/// The values are shown as the model holds them, so a value the user corrected
/// shows as corrected. The per-item form that would edit these values does not
/// exist yet, so the section shows them without editing them.
///
/// The widget owns the layout and the widget state — the busy flags, the slider
/// value, the last scan and the last generation the section was given, and
/// which rows are open; the controller owns the side effects. It resolves its
/// dependencies from the provider scope and builds its own per-widget
/// controller, as the other sections do.
///
/// The section does not write fields itself: the values the scan counted are
/// handed to the editor's single write path through `onApplyValues`, so the tab
/// becomes dirty and Ctrl+S saves them.
class VideoPackSection extends StatefulWidget {
  const VideoPackSection({
    required this.release,
    required this.tabId,
    required this.onApplyValues,
    required this.onImagesChanged,
    super.key,
  });

  final Release release;
  final String tabId;

  /// Writes the values the scan counted through the editor's single write path.
  final void Function(Map<String, String> values) onApplyValues;

  /// Called when a generation run ends. A run writes images, so the count the
  /// Upload section shows is no longer the count the release has; the editor
  /// passes the function that tells it (rule 3: a plain callback, not a
  /// listener).
  final void Function() onImagesChanged;

  @override
  State<VideoPackSection> createState() => _VideoPackSectionState();
}

class _VideoPackSectionState extends State<VideoPackSection> {
  late final VideoPackController _controller;

  /// The smallest this section allows. A pack generates for many files at once,
  /// and a run with 0 writes only the screenlist, because mtn reads the video
  /// itself; the Single video section keeps a minimum of 3, because there the
  /// number is the set of frames a post shows (`ai/doc.md` §2).
  static const _minCount = 0;

  /// The slider value. Widget state: it decides what the section shows and is
  /// passed to the controller, which does not hold it.
  int _count = 0;

  /// Which action is running. Widget state, for the progress indicator on the
  /// button that is.
  bool _scanning = false;
  bool _generating = false;

  /// The last scan and the last generation the section was given. The reports
  /// are what those runs found, so they appear only after one. A scan replaces
  /// the items, so it clears the generation reports with it: they would name
  /// files that are no longer items.
  VideoPackSuccess? _lastScan;
  List<ImageGenerationResult> _lastGeneration = [];

  /// Which rows are open. Widget state, keyed by the item path, because the
  /// path is the record ID and stays the same across a re-scan of the same
  /// folder.
  final Set<String> _expanded = {};

  /// Increments on every image a run writes, because a run writes the same
  /// names again. It is the key of each tile's image, so a regenerated file is
  /// re-resolved and shown fresh (`AGENTS.md` rule 5). It changes per file
  /// rather than per run because a file is shown as it is written, and the tile
  /// for it must re-resolve at that moment.
  int _generation = 0;

  /// The images the run in progress has written, as the controller reports
  /// them. Widget state: the table's flag columns and the open row's tiles show
  /// them as they arrive, so a frame appears when it is written rather than
  /// when the run ends. It is cleared when the run ends, because from then on
  /// the manifest is what the section reads.
  final List<ImageRecord> _running = [];

  // The width of a small tile in the detail. A row of a table is a compact
  // thing, so the frames are shown at thumbnail size rather than as the
  // full-width tiles the Single video section uses.
  static const _tileWidth = 120.0;

  @override
  void initState() {
    super.initState();

    _controller = VideoPackController(
      release: widget.release,
      scanner: context.read<VideoScanner>(),
      generator: context.read<ImageGenerator>(),
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
    setState(() => _scanning = true);

    final result = await _controller.scan();

    if (!mounted) return;

    if (result is VideoPackSuccess) {
      widget.onApplyValues(result.values);

      // A re-scan replaces the items, so a path that is no longer one is not
      // kept, and the reports of the previous run are not kept either.
      _expanded.retainAll(_controller.videos().map((item) => item.path));

      setState(() {
        _lastScan = result;
        _lastGeneration = [];
        _scanning = false;
      });
      return;
    }

    // The cases where nothing can happen at all get a message; what the scan
    // could not take is listed by the section, because a scan that ran and
    // excluded files is not an error.
    _showMessage(switch ((result as VideoPackFailure).kind) {
      VideoPackFailureKind.sourceEmpty => l10n.videoSourceEmpty,
      VideoPackFailureKind.sourceNotFound => l10n.videoSourceNotFound,
      VideoPackFailureKind.sourceNotReadable => l10n.videoSourceNotReadable,
    });

    if (!mounted) return;
    setState(() => _scanning = false);
  }

  Future<void> _generate(AppLocalizations l10n) async {
    setState(() {
      _generating = true;
      _running.clear();
    });

    final result = await _controller.generateImages(_count, (record) {
      if (!mounted) return;

      // The file was just written, so its cache entry is dropped and its key
      // changes; an already-mounted image keeps the stream it resolved the
      // first time (AGENTS.md rule 5).
      evictCachedImages([_controller.absolutePath(record)]);

      setState(() {
        _running.add(record);
        _generation += 1;
      });
    });

    if (!mounted) return;

    // The run is over, so the section reads the images the way it always does:
    // the records of the item whose files are on disk.
    setState(() {
      _lastGeneration = result.runs;
      _running.clear();
      _generating = false;
    });

    // The run wrote images, so the count the Upload section shows is no longer
    // the count the release has. It is told when the run ends, not while it
    // runs, because the records are what the count reads.
    if (result.written.isNotEmpty) {
      widget.onImagesChanged();
    }

    // Only what the run as a whole could not do is a message here: a tool that
    // is not installed is the same text the Single video section shows, and a
    // run that did most of the files is not an error, so those files are a
    // line.
    ImageGenerationFailureKind? stopped = result.failure;

    for (final run in result.runs) {
      if (run.failure != null && run.failure!.stopsRun) {
        stopped = run.failure;
        break;
      }
    }

    if (stopped != null) {
      _showMessage(_failureMessage(stopped, l10n));
    }
  }

  String _failureMessage(
    ImageGenerationFailureKind kind,
    AppLocalizations l10n,
  ) => switch (kind) {
    ImageGenerationFailureKind.probeToolNotAvailable =>
      l10n.probeToolNotAvailable,
    ImageGenerationFailureKind.ffmpegNotAvailable => l10n.ffmpegNotAvailable,
    ImageGenerationFailureKind.mtnNotAvailable => l10n.mtnNotAvailable,
    ImageGenerationFailureKind.manifestFailed => l10n.imagesManifestFailed,
    // What the run could not do to one file is a line, not a message.
    _ => '',
  };

  Widget _line(String text, TextStyle? style) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(text, style: style),
  );

  /// What the flag columns and the open row show: the records of the item whose
  /// files are on disk, plus the records the run in progress has written for
  /// it. A run replaces the item's records, so the two are the same set at the
  /// end of it; while it runs the files already on disk stay shown and each new
  /// frame is added as it is written, so a row does not blank while the run
  /// works.
  List<ImageRecord> _imagesFor(ReleaseItem item) {
    if (_running.isEmpty) {
      return _controller.imagesFor(item);
    }

    final shown = {
      for (final record in _controller.imagesFor(item)) record.file: record,
      for (final record in _running)
        if (record.item == item.path) record.file: record,
    };

    return [for (final record in shown.values) record];
  }

  // The columns the table has now: the name, the size, the duration, and the
  // two flags the generation writes (`ai/video_pack.md` §5). The column for the
  // additional data comes with the feature that fills it, so the table does not
  // show a column that is always empty. The name is the widest column, because
  // a path is longer than the values beside it.
  static const _rowFields = [
    'name',
    'fileSize',
    'duration',
    'screenlist',
    'screenshots',
  ];

  // The values the detail shows: the ones the row does not. The stream lines
  // are long, so they cannot be columns, and each needs the label its field has
  // to be read at all. Which values go in the row and which in the detail is
  // the widget's layout, not the field list's order.
  static const _detailFields = [
    'videoType',
    'videoFormat',
    'videoStream',
    'audioStream',
  ];

  int _flex(String name) => switch (name) {
    'name' => 5,
    'fileSize' => 1,
    'duration' => 1,
    _ => 1,
  };

  /// The value columns are right-aligned, so the numbers line up and the short
  /// size forms read as numbers. The name is not a number, so it is not. The
  /// header follows its column, because a header at the left edge of a column
  /// whose values are at the right edge reads as a different column.
  bool _rightAligned(String name) => name != 'name';

  TextAlign _align(String name) =>
      _rightAligned(name) ? TextAlign.right : TextAlign.left;

  /// One cell. The header and the rows build their cells through the same
  /// function, so the columns line up.
  Widget _cell(String name, Widget content) =>
      Expanded(flex: _flex(name), child: content);

  Widget _text(String name, String value, TextStyle? style) =>
      Text(value, style: style, textAlign: _align(name));

  /// What a column shows for one item, given the images that run wrote for it.
  /// Only the two flag columns are not text: a screenlist is a yes or a no, and
  /// a count of 0 is shown as nothing, because a flag column that says 0 reads
  /// as an error rather than as an absence.
  Widget _cellContent(
    String name,
    ReleaseItem item,
    List<ImageRecord> images,
    AppLocalizations l10n,
    TextStyle? style,
  ) {
    switch (name) {
      case 'screenlist':
        return _flag(
          name,
          images.any((record) => record.kind == ImageKind.screenlist),
        );
      case 'screenshots':
        final count = _countOf(images, ImageKind.screenshot);

        return _text(name, count == 0 ? '' : '$count', style);
      default:
        return _text(name, _cellText(name, item, l10n), style);
    }
  }

  int _countOf(List<ImageRecord> images, ImageKind kind) =>
      images.where((record) => record.kind == kind).length;

  Widget _flag(String name, bool value) {
    if (!value) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: _rightAligned(name)
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: const Icon(Icons.check, size: 16),
    );
  }

  /// What a column shows for one item. The name column shows the path, because
  /// that is the record ID and two files in different subfolders can have the
  /// same file name (`ai/release_structure.md` §2); the size is the short form,
  /// because a fixed-width cell cannot hold the byte count as well. A value the
  /// model does not have is shown as nothing, because a file the probe could
  /// not read has none, and the report line says which files those are.
  String _cellText(String name, ReleaseItem item, AppLocalizations l10n) =>
      switch (name) {
        'name' => item.path,
        'fileSize' => humanFileSize(item.fields.value(name)),
        _ => item.fields.value(name),
      };

  /// What a column is called. The header names it by the label its field has,
  /// so the table and the form above it use the same words for the same values.
  /// The name is not a field, and neither are the two flags, so those three
  /// come from their own keys.
  String _headerText(String name, AppLocalizations l10n) => switch (name) {
    'name' => l10n.fileNameLabel,
    'screenlist' => l10n.screenlistLabel,
    'screenshots' => l10n.screenshotsLabel,
    _ => fieldLabel(name, l10n, widget.release.releaseType),
  };

  Widget _header(AppLocalizations l10n) {
    final heading = Theme.of(context).textTheme.labelMedium;

    return Row(
      key: const ValueKey('videoTableHeader'),
      children: [
        for (final name in _rowFields)
          _cell(name, _text(name, _headerText(name, l10n), heading)),
      ],
    );
  }

  /// One video as a row, and the values the row does not show when it is open.
  /// Clicking the row opens it; the values that are in the row are not repeated
  /// in the detail. The images are read once for the row, so the flag columns
  /// and the detail do not each read `images.json`.
  ///
  /// Every other row is tinted, because a table read as bands of text is
  /// followed with the eye. The tint covers the detail as well, because the
  /// band belongs to the row: an open row that is half tinted reads as two
  /// rows. The parity is the position in the order the items are stored, so a
  /// re-scan of the same folder does not change a row's colour.
  ///
  /// The tint is on a `Material` and not on a plain container, because the
  /// hover highlight is painted on the canvas of the nearest `Material`
  /// ancestor: a container paints its colour over that, so a tinted row would
  /// show no highlight at all. A row that is not tinted is a transparent
  /// `Material` for the same reason, so every row is the same shape rather than
  /// two kinds of row.
  Widget _row(AppLocalizations l10n, ReleaseItem item, int index) {
    final theme = Theme.of(context);
    final open = _expanded.contains(item.path);
    final images = _imagesFor(item);

    return Material(
      color: index.isOdd
          ? theme.colorScheme.surfaceContainerHigh
          : Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('video-row-${item.path}'),
            onTap: () => setState(() {
              if (open) {
                _expanded.remove(item.path);
              } else {
                _expanded.add(item.path);
              }
            }),
            // The padding is what makes a tinted row read as a band rather than
            // as a line of text with a colour behind it; the same value the
            // detail lines use.
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final name in _rowFields)
                    _cell(
                      name,
                      _cellContent(
                        name,
                        item,
                        images,
                        l10n,
                        theme.textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (open) _detail(l10n, item, images),
        ],
      ),
    );
  }

  /// The values the row does not show, each with the label its field has, and
  /// the images the run wrote for this item. The screenlist is shown at the
  /// detail's full width, because it is the summary of the video and a grid is
  /// as tall as its rows; the screenshots are small tiles in a wrap, because an
  /// expanded row of a table that lists many items has to stay a row. Only the
  /// open row builds them, so a closed row costs nothing. The names are not
  /// repeated under the tiles, because the row already names the item.
  ///
  /// Only a file that is on disk is shown, for the same reason the flag columns
  /// are: a record whose file was deleted is not an image the app can show.
  Widget _detail(
    AppLocalizations l10n,
    ReleaseItem item,
    List<ImageRecord> images,
  ) {
    final lines = [
      for (final name in _detailFields)
        if (item.fields.value(name).isNotEmpty)
          '${fieldLabel(name, l10n, widget.release.releaseType)}: ${item.fields.value(name)}',
    ];

    final screenlists = [
      for (final record in images)
        if (record.kind == ImageKind.screenlist)
          _controller.absolutePath(record),
    ];
    final screenshots = [
      for (final record in images)
        if (record.kind == ImageKind.screenshot)
          _controller.absolutePath(record),
    ];

    if (lines.isEmpty && images.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in lines)
          _line(line, Theme.of(context).textTheme.bodySmall),
        if (screenlists.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final path in screenlists)
            ImageTile(
              path: path,
              showName: false,
              picture: imageFromFile(path, _generation),
            ),
        ],
        if (screenshots.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final path in screenshots)
                SizedBox(
                  width: _tileWidth,
                  child: ImageTile(
                    path: path,
                    showName: false,
                    picture: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: imageFromFile(
                        path,
                        _generation,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// What the scan could not take and what the generation could not do, as the
  /// lines the section shows. A scan that ran and excluded files is not an
  /// error, so these are lines in the section rather than messages; the same is
  /// true of a run that did most of the files. A run that stopped because a
  /// tool is not installed is a message, so it is not listed here.
  List<String> _reportLines(
    AppLocalizations l10n,
    VideoPackSuccess scan,
    List<ImageGenerationResult> runs,
  ) {
    final failed = [
      for (final run in runs)
        if (run.failure != null && !run.failure!.stopsRun) run.item,
    ];

    return [
      if (scan.skipped.isNotEmpty)
        l10n.videoSkippedFiles(scan.skipped.join(', ')),
      if (scan.unprobed.isNotEmpty)
        l10n.videoUnprobedFiles(scan.unprobed.join(', ')),
      if (scan.emptyFolders.isNotEmpty)
        l10n.videoEmptyFolders(scan.emptyFolders.join(', ')),
      if (scan.unreadable.isNotEmpty)
        l10n.videoUnreadableFolders(scan.unreadable.join(', ')),
      if (failed.isNotEmpty) l10n.imagesFailedFiles(failed.join(', ')),
    ];
  }

  /// The buttons for the title row. They keep the shape the section had when
  /// they were in its body: the child is replaced by the spinner while the run
  /// goes.
  Widget _scanButton(AppLocalizations l10n) {
    final theme = Theme.of(context);

    return FilledButton(
      key: const ValueKey('videoScanButton'),
      onPressed: _scanning ? null : () => _scan(l10n),
      child: _scanning
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onPrimary,
              ),
            )
          : Text(l10n.scanVideos),
    );
  }

  // There is no "Regenerate" variant here: the run replaces what it writes, so
  // the same button is the same action whether or not the files are already
  // there. It is disabled when there is nothing to generate, because a run over
  // no items does nothing.
  Widget _generateButton(AppLocalizations l10n, bool hasVideos) {
    final theme = Theme.of(context);

    return FilledButton(
      key: const ValueKey('videoGenerateButton'),
      onPressed: _generating || !hasVideos ? null : () => _generate(l10n),
      child: _generating
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onPrimary,
              ),
            )
          : Text(l10n.generatePackImages),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scan = _lastScan;
    final videos = _controller.videos();
    final reports = scan == null
        ? const <String>[]
        : _reportLines(l10n, scan, _lastGeneration);

    return Column(
      key: const ValueKey('videoPackSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The buttons are in the title row because they are the actions of the
        // whole section, not of a row inside it. The folder the scan reads is
        // the source row above the form; the section does not repeat it.
        SectionTitle(
          title: l10n.videoPackSectionTitle,
          action: Row(
            children: [
              _scanButton(l10n),
              const SizedBox(width: 8),
              _generateButton(l10n, videos.isNotEmpty),
            ],
          ),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        if (videos.isEmpty)
          Text(l10n.noVideos, style: theme.textTheme.bodyMedium)
        else ...[
          _header(l10n),
          for (final (index, item) in videos.indexed) _row(l10n, item, index),
        ],
        // The lines come after the videos, because they say what is not among
        // them. A folder the walk could not read is listed rather than counted
        // as empty, because the scan cannot say whether it had a video in it,
        // so the counts in the form above are known to be incomplete when this
        // line appears.
        if (reports.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final line in reports) _line(line, theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}
