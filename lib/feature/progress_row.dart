import 'package:flutter/material.dart';

/// The row a section draws while one of its runs is going: the bar and the count
/// next to it. Shared by the Photoset block and the Image folder section, because
/// both show a run the same way, with the same bar the Upload section draws for
/// each hoster (`ai/picking.md` §7, `ai/image_folder_upload.md` §5,
/// `ai/upload_images.md`).
///
/// A row is drawn only once a run has started, because before a run there is
/// nothing to show, and after one the results the run produced are what the
/// section shows — the same rule the Torrent section follows (`ai/torrents.md`).
///
/// The words for a run's progress are per release type, so the caller resolves
/// them and passes what they say. Presentational only: no state, so no
/// controller.
class ProgressRow extends StatelessWidget {
  const ProgressRow({
    required this.done,
    required this.total,
    required this.count,
    super.key,
  });

  final int done;
  final int total;

  /// The two numbers, in the words the caller resolved for the type.
  final String count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A run with nothing to do is an empty bar, the same measure the Upload
        // section's rows use (`ai/upload_images.md`).
        LinearProgressIndicator(value: total == 0 ? 0 : done / total),
        const SizedBox(height: 4),
        Text(count, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
