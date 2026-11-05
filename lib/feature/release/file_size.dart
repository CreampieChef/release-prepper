import '../../l10n/app_localizations.dart';

/// Item 16 of `ai/release_editor.md`: the byte count as the text the size field
/// shows, for example `9.5 GiB (10737418240 bytes)`.
///
/// The model stores the byte count, so this is only how the field shows it, and
/// it has to work for a value read from a manifest as well as for one the probe
/// wrote. A value that is not a number — a manifest edited by hand — is shown
/// as it is.
String formatFileSize(String bytes, AppLocalizations l10n) {
  final human = humanFileSize(bytes);

  // A value with no shorter form is the byte count itself, so the display would
  // only repeat it.
  if (human == bytes) {
    return bytes;
  }

  return l10n.fileSizeDisplay(human, bytes);
}

/// `9.5 GiB`: the human form alone, for a place that shows a size in a
/// fixed-width cell rather than as the field's text — the Video pack table's
/// size column. A value with no shorter form is the byte count as the model
/// holds it, so a caller does not have to handle that case separately.
String humanFileSize(String bytes) {
  final size = int.tryParse(bytes);

  if (size == null) {
    return bytes;
  }

  // Below 1 KiB there is no shorter form than the byte count.
  final human = _humanSize(size);

  return human.isEmpty ? bytes : human;
}

/// `9.5 GiB`: binary units, one decimal place, as the example in the document
/// writes it. Empty for a byte count too small to have a shorter form.
String _humanSize(int bytes) {
  if (bytes < 1024) {
    return '';
  }

  const units = ['KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
  var value = bytes / 1024;
  var unit = 0;

  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }

  return '${value.toStringAsFixed(1)} ${units[unit]}';
}
