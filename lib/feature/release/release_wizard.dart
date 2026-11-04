import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'dart:io';

import '../../l10n/app_localizations.dart';
import '../recent_releases/recent_releases_controller.dart';
import '../settings/settings_controller.dart';
import '../tracker_icon.dart';
import 'release.dart';
import 'release_store.dart';
import 'release_type.dart';
import 'release_wizard_controller.dart';
import 'tracker.dart';

class ReleaseWizard extends StatefulWidget {
  const ReleaseWizard({required this.onCreated, super.key});

  final ValueChanged<Release> onCreated;

  @override
  State<ReleaseWizard> createState() => _ReleaseWizardState();
}

class _ReleaseWizardState extends State<ReleaseWizard> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _savePathController = TextEditingController();

  late final ReleaseWizardController _controller;

  Tracker _tracker = Tracker.pornolab;
  ReleaseType _releaseType = ReleaseType.singleVideo;

  @override
  void initState() {
    super.initState();
    _controller = ReleaseWizardController(
      store: context.read<ReleaseStore>(),
      defaultReleaseDirectory: context
          .read<SettingsController>()
          .defaultReleaseDirectory,
      recentReleases: context.read<RecentReleasesController>(),
    );
    _savePathController.text = _controller.defaultReleaseDirectory;
  }

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    _savePathController.dispose();
    super.dispose();
  }

  String? _validateName(String? value, AppLocalizations l10n) {
    return switch (validateReleaseName(value)) {
      ReleaseNameValidationError.required => l10n.releaseNameRequired,
      ReleaseNameValidationError.invalid => l10n.releaseNameInvalid,
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
        initialDirectory = _controller.defaultReleaseDirectory;
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

  Future<void> _createRelease(AppLocalizations l10n) async {
    if (!_formKey.currentState!.validate()) return;

    final release = await _controller.create(
      savePath: _savePathController.text.trim(),
      name: _nameController.text,
      tracker: _tracker,
      releaseType: _releaseType,
    );

    if (!mounted) return;

    if (release != null) {
      widget.onCreated(release);
      return;
    }

    switch (_controller.creationFailure) {
      case ReleaseCreationFailure.alreadyExists:
        _showMessage(l10n.releaseAlreadyExists);
      case ReleaseCreationFailure.failed:
      case null:
        _showMessage(l10n.releaseCreationFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final isBusy = _controller.isCreating;

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
                      l10n.newRelease,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
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
                            onPressed: isBusy
                                ? null
                                : () => _pickSavePath(l10n),
                            icon: const Icon(Icons.folder_open),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownMenuFormField<Tracker>(
                      initialSelection: _tracker,
                      enabled: !isBusy,
                      selectOnly: true,
                      label: Text(l10n.trackerLabel),
                      inputDecorationTheme: const InputDecorationTheme(
                        border: OutlineInputBorder(),
                      ),
                      // Match the parent width, like the other form fields.
                      expandedInsets: EdgeInsets.zero,
                      // The option list is the trackers the app knows. A
                      // tracker's display name is the same in every language,
                      // so it is not an AppLocalizations key.
                      dropdownMenuEntries: [
                        for (final tracker in Tracker.values)
                          DropdownMenuEntry(
                            value: tracker,
                            label: tracker.displayName,
                            leadingIcon: TrackerIcon(tracker: tracker),
                          ),
                      ],
                      onSelected: (value) {
                        if (value != null) {
                          setState(() => _tracker = value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownMenuFormField<ReleaseType>(
                      initialSelection: _releaseType,
                      enabled: !isBusy,
                      selectOnly: true,
                      label: Text(l10n.releaseTypeLabel),
                      inputDecorationTheme: const InputDecorationTheme(
                        border: OutlineInputBorder(),
                      ),
                      // Match the parent width, like the other form fields.
                      expandedInsets: EdgeInsets.zero,
                      // The option list is the release types the app has field
                      // lists for, which is every type it knows. The label is
                      // the display name; the value is the technical name the
                      // manifest writes.
                      dropdownMenuEntries: [
                        for (final releaseType in ReleaseType.values)
                          DropdownMenuEntry(
                            value: releaseType,
                            label: releaseTypeLabel(releaseType, l10n),
                          ),
                      ],
                      onSelected: (value) {
                        if (value != null) {
                          setState(() => _releaseType = value);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: isBusy ? null : () => _createRelease(l10n),
                        icon: _controller.isCreating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.create_new_folder),
                        label: Text(l10n.createButton),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
