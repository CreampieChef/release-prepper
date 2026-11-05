import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../service/native_tools/uptooda.dart';
import '../release/release.dart';
import '../release/release_store.dart';
import '../release/release_type.dart';
import '../screenshots/images_store.dart';
import '../section_title.dart';
import '../settings/settings_controller.dart';
import 'hoster_icon.dart';
import 'hosters.dart';
import 'upload_controller.dart';

/// The Upload images section below the Screenshots section
/// (`ai/upload_images.md`): its title row with the Upload button at the right,
/// the hoster list with checkboxes, and a progress bar per hoster. A bar is
/// there for every hoster, whether or not it can run and whether or not it has
/// anything to do, because the section shows what each hoster has from the
/// moment the release is opened. Until the release has a poster and an image of
/// the kind its type produces there is nothing to upload, so the section shows
/// the placeholder saying what has to happen first instead of the list. The
/// words name that kind, so a pack names the screenlist. The widget owns the
/// hoster selection and the layout; the controller owns the side effects. It
/// resolves its dependencies from the provider scope and builds its own
/// per-widget controller, as the editor and the Screenshots section do.
///
/// This is the first iteration of the UI. Per-image upload failures are not
/// shown: the bar shows them by staying below full, and the log is what the user
/// and the developer read. Only the cases where nothing can happen at all — the
/// tool is not in the bundle, or the manifest could not be written — get a
/// message, because a bar stuck at 0 with no explanation is not enough.
///
/// The count is the count the release has, so a generation run that adds images
/// changes it. The Screenshots section and this one cannot see each other, so
/// the editor — the widget that places both — is where they meet: this section
/// registers its rebuild with the editor, and the editor calls it when a run
/// ends. A run of this section is itself such a change, because it writes
/// `images.json`, so it tells the editor when one of its own runs ends; that
/// notice rebuilds every registered section, this one included. A plain
/// callback, not a listener (rule 3).
class UploadSection extends StatefulWidget {
  const UploadSection({
    required this.release,
    required this.subscribeImagesChanged,
    required this.onImagesChanged,
    super.key,
  });

  final Release release;

  /// Registers this section's rebuild with the editor, which calls it when a
  /// generation run ends.
  final void Function(void Function() rebuild) subscribeImagesChanged;

  /// Tells the editor that a run of this section ended, which is what rebuilds
  /// the sections that show what `images.json` holds.
  final void Function() onImagesChanged;

  @override
  State<UploadSection> createState() => _UploadSectionState();
}

class _UploadSectionState extends State<UploadSection> {
  late final UploadController _controller;

  /// The selected hosters. Widget state: it decides what the section shows and
  /// is passed to the controller, which does not hold it. Every hoster the app
  /// has is checked at first — the real ones, or the mock ones of a `--dev` run
  /// — and the selection is not stored between runs.
  final Set<String> _selected = {for (final hoster in hosters) hoster.name};

  /// What each bar shows, per hoster. Widget state, for the bars. It is the
  /// state `images.json` holds when the section is opened, and the progress
  /// reports from a run update the same entries, so a bar does not start empty
  /// when a release already has images uploaded (`ai/upload_images.md`).
  late final Map<String, UploadProgress> _progress;

  /// Whether the release has the poster and an image of the kind its type
  /// produces. Widget state: it decides whether the section shows the hoster
  /// list or the placeholder saying what has to happen first, and a generation
  /// run changes it, so the rebuild the editor calls reads it again.
  bool _hasImages = false;

  bool _busy = false;

  @override
  void initState() {
    super.initState();

    _controller = UploadController(
      release: widget.release,
      uptooda: context.read<Uptooda>(),
      store: context.read<ImagesStore>(),
      releaseStore: context.read<ReleaseStore>(),
    );

    _progress = _controller.progress();
    _hasImages = _controller.hasUploadableImages();

    widget.subscribeImagesChanged(_rebuildCounters);
  }

  /// The counters are read again. They are the state `images.json` holds, so a
  /// generation run that wrote images changes the total: the editor calls this
  /// when one ends. The entries are updated rather than replaced, so a bar does
  /// not move backwards. The same run can be what makes the release have the
  /// images the placeholder is waiting for, so that is read again too.
  void _rebuildCounters() {
    if (!mounted) return;

    setState(() {
      for (final entry in _controller.progress().entries) {
        _progress[entry.key] = entry.value;
      }

      _hasImages = _controller.hasUploadableImages();
    });
  }

  /// Whether this hoster can take part in a run. A hoster whose script reads a
  /// credential cannot run without one, so its checkbox is inactive and says
  /// where the value is set. This is the same rule the controller applies when
  /// it builds the environment (`ai/bundled_native_tools.md`): the app never
  /// calls a hoster with an empty credential, so the section does not offer one
  /// as selected.
  bool _canRun(Hoster hoster, SettingsController settings) {
    final field = hoster.field;

    return field == null ||
        (settings.secretValues[field.name] ?? '').isNotEmpty;
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _upload(
    AppLocalizations l10n,
    SettingsController settings,
  ) async {
    // The values are read here, from the settings, so the controller builds no
    // dependency of its own (rule 4), and the hosters are passed as the
    // registry records rather than as names, because the call needs to know
    // which of them reads a credential.
    final selected = [
      for (final hoster in hosters)
        if (_selected.contains(hoster.name) && _canRun(hoster, settings))
          hoster,
    ];

    setState(() => _busy = true);

    final result = await _controller.upload(
      selected: selected,
      secrets: settings.secretValues,
      // The controller reports progress through a plain callback (rule 3); the
      // widget subscribes to it here and rebuilds the bars. The reports are the
      // same measure as the state read at open, so they update the entries that
      // are already there.
      onProgress: (progress) {
        if (!mounted) return;

        setState(() => _progress[progress.hoster] = progress);
      },
    );

    if (!mounted) return;

    if (result case UploadFailure failure) {
      _showMessage(switch (failure.kind) {
        UploadFailureKind.toolNotAvailable => l10n.uptoodaNotAvailable,
        UploadFailureKind.manifestFailed => l10n.imagesManifestFailed,
      });
    }

    if (!mounted) return;

    // The run wrote `images.json`, so the sections that show what it holds are
    // told: the editor rebuilds every registered one, this section included.
    widget.onImagesChanged();

    setState(() => _busy = false);
  }

  /// One hoster: its icon, its checkbox, its name, and its bar. The bar is
  /// there for every hoster the section shows, because it shows what each
  /// hoster has from the moment the release is opened (`ai/upload_images.md`).
  /// A hoster with none of the release's images is an empty bar: the bar is the
  /// share of those images this hoster has, and it has none, so it shows none.
  /// Whether there is anything left to do is what the count next to it says. A
  /// release with no images at all does not reach this row; the section shows
  /// the placeholder instead.
  Widget _hosterRow(
    Hoster hoster,
    SettingsController settings,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final progress = _progress[hoster.name]!;
    final canRun = _canRun(hoster, settings);

    final checkbox = Checkbox(
      value: canRun && _selected.contains(hoster.name),
      // Inactive while the credential this hoster needs is missing, with the
      // tooltip saying where to set it. A hoster that cannot run is not part of
      // the run.
      onChanged: canRun
          ? (value) => setState(() {
              if (value == true) {
                _selected.add(hoster.name);
              } else {
                _selected.remove(hoster.name);
              }
            })
          : null,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        HosterIcon(assetPath: hoster.iconAsset),
        const SizedBox(width: 8),
        if (canRun)
          checkbox
        else
          Tooltip(message: l10n.hosterApiKeyRequired, child: checkbox),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hoster.name, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: progress.total == 0 ? 0 : progress.done / progress.total,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.uploadProgress(progress.done, progress.total),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The words the placeholder says: what has to happen first. A switch, like
  /// the other per-type rules. Only the pack names the kind its run can write
  /// on its own, because a run over a pack can be asked to write only the
  /// screenlist (`ai/video_pack.md` §5). The other types keep the wording that
  /// names screenshots, which for the two photoset types and the image folder
  /// is not what the gate requires.
  String _placeholderText(AppLocalizations l10n) =>
      switch (widget.release.releaseType) {
        ReleaseType.videoPack => l10n.uploadNeedsScreenlistsFirst,
        ReleaseType.singleVideo ||
        ReleaseType.photosetPack ||
        ReleaseType.singlePhotoset ||
        ReleaseType.imageFolderUpload => l10n.uploadNeedsImagesFirst,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // Watched, not read: the checkbox for a hoster that needs a credential
    // changes when the value changes, and `SettingsController` is the
    // Listenable that says it did.
    final settings = context.watch<SettingsController>();

    return Column(
      key: const ValueKey('uploadSection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The button is in the title row because it is the action of the whole
        // section, not one of the rows it acts on. It is not drawn when there
        // is nothing to upload, the same as the list is not drawn then.
        SectionTitle(
          title: l10n.uploadSectionTitle,
          action: _hasImages ? _uploadButton(l10n, settings) : null,
        ),
        const SizedBox(height: 12),
        // A release that does not have the images a run here could upload says
        // what has to happen first instead of listing hosters with empty bars.
        if (!_hasImages)
          Text(_placeholderText(l10n), style: theme.textTheme.bodySmall)
        else
          for (final hoster in hosters) ...[
            _hosterRow(hoster, settings, l10n, theme),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _uploadButton(AppLocalizations l10n, SettingsController settings) {
    return FilledButton(
      onPressed: _busy ? null : () => _upload(l10n, settings),
      child: Text(l10n.uploadButton),
    );
  }
}
