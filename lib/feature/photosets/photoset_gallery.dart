import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../section_title.dart';
import 'photoset_group.dart';

/// The area a photoset shows its picked photos in: the title row, and the grid
/// the feature fits from the two widths it gives (`ai/picking.md` §7,
/// `ai/photoset_pack.md` §6). This is the half of the feature that draws the
/// photos, for both photoset types: the data block — the heading, the rows, the
/// counts, the lines naming the sets — is `PhotosetBlock`, because the block is
/// the page's second column and the pictures are the space after it, and one
/// widget cannot be two grid cells. The two read the same `PhotosetState`,
/// which the editor builds, so the run that writes the files and the pictures
/// that show them are not one widget's state (`AGENTS.md` §5).
///
/// It has no state of its own: a run happens in the block, which notifies the
/// editor as each photo is written, so the pictures here appear during the run
/// and are resolved against the cache that run emptied.
class PhotosetGallery extends StatelessWidget {
  const PhotosetGallery({required this.state, super.key});

  /// The controller the block runs, and the generation its runs advance.
  final PhotosetState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final strings = photosetStrings(state.controller.release.releaseType, l10n);
    final groups = photosetGroups(state, state.controller.photosets());

    return Column(
      key: const ValueKey('photosetGallery'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Nothing runs here: the buttons belong to the block, which is the
        //
        // widget that reads the folder and runs the rule. The title row is the
        //
        // text on its own, which is the same row as a section with no action.
        SectionTitle(title: strings.photosTitle),
        const SizedBox(height: 12),
        photosetPhotoGrid(state, groups),
      ],
    );
  }
}
