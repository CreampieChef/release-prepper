import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../recent_releases/recent_releases_controller.dart';
import '../screenshots/images_store.dart';
import 'clone_wizard_controller.dart';
import 'release.dart';
import 'release_store.dart';
import 'release_wizard_controller.dart';

/// The clone form: the name the clone is created under and the folder it goes
/// in. The tracker and the release type are the source's and are not chosen
/// here — a clone is the same release with a different video. What the form
/// copies is the controller's; this widget shows the source, the fields, and
/// the warning the poster state decides.
class CloneWizard extends StatefulWidget {
  const CloneWizard({required this.source, required this.onCreated, super.key});

  final Release source;

  final ValueChanged<Release> onCreated;

  @override
  State<CloneWizard> createState() => _CloneWizardState();
}

class _CloneWizardState extends State<CloneWizard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _savePathController;

  late final CloneWizardController _controller;

  /// The widget's own busy flag for its progress indicator, not controller
  /// state (rule 3).
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _controller = CloneWizardController(
      source: widget.source,
      store: context.read<ReleaseStore>(),
      images: context.read<ImagesStore>(),
      recentReleases: context.read<RecentReleasesController>(),
    );
    _nameController = TextEditingController(text: widget.source.name);
    _savePathController = TextEditingController(
      text: _controller.defaultSavePath,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _savePathController.dispose();
    super.dispose();
  }

  String? _validateName(String? value, AppLocalizations l10n) {
    return switch (validateCloneName(value, widget.source.name)) {
      CloneNameValidationError.required => l10n.releaseNameRequired,
      CloneNameValidationError.invalid => l10n.releaseNameInvalid,
      CloneNameValidationError.sameAsSource => l10n.cloneNameMustDiffer,
      null => null,
    };
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickSavePath(AppLocalizations l10n) async {
    try {
      var initialDirectory = _savePathController.text.trim();

      if (initialDirectory.isEmpty ||
          !await Directory(initialDirectory).exists()) {
        initialDirectory = _controller.defaultSavePath;
      }

      final selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: l10n.chooseSavePath,
        initialDirectory: initialDirectory.isEmpty ? null : initialDirectory,
      );

      if (!mounted || selectedDirectory == null) return;
      _savePathController.text = selectedDirectory;
    } catch (_) {
      _showMessage(l10n.folderPickerFailed);
    }
  }

  Future<void> _createClone(AppLocalizations l10n) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isBusy = true);

    final result = await _controller.create(
      savePath: _savePathController.text.trim(),
      name: _nameController.text,
    );

    if (!mounted) return;
    setState(() => _isBusy = false);

    switch (result) {
      case CloneCreationSuccess(release: final release):
        widget.onCreated(release);
      case CloneCreationFailure(kind: final kind):
        // The same messages the wizard's create uses, because the failure
        // vocabulary is the same.
        switch (kind) {
          case ReleaseCreationFailure.alreadyExists:
            _showMessage(l10n.releaseAlreadyExists);
          case ReleaseCreationFailure.failed:
            _showMessage(l10n.releaseCreationFailed);
        }
    }
  }

  /// The warning the poster state decides. The controller answers with the
  /// state, not the text (rule 13); this is where it becomes a string.
  String _warningText(ClonePosterStatus status, AppLocalizations l10n) =>
      switch (status) {
        ClonePosterStatus.noPoster => l10n.cloneNoPosterWarning,
        ClonePosterStatus.notUploaded => l10n.clonePosterNotUploadedWarning,
        ClonePosterStatus.uploaded => '',
      };

  Widget _warningLine(String text, AppLocalizations l10n) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final warning = _warningText(_controller.posterStatus(), l10n);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.cloneRelease,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                Text(l10n.cloneSourceLabel(widget.source.name)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(
                      RegExp(r'[\x00-\x1F<>:"/\\|?*]'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: l10n.releaseNameLabel,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => _validateName(value, l10n),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _savePathController,
                        decoration: InputDecoration(
                          labelText: l10n.savePathLabel,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l10n.savePathRequired;
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: IconButton(
                        tooltip: l10n.chooseSavePath,
                        onPressed: _isBusy ? null : () => _pickSavePath(l10n),
                        icon: const Icon(Icons.folder_open),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (warning.isNotEmpty) ...[
                  _warningLine(warning, l10n),
                  const SizedBox(height: 24),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _isBusy ? null : () => _createClone(l10n),
                    icon: _isBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.content_copy),
                    label: Text(l10n.createButton),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
