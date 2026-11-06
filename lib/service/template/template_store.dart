import 'package:flutter/services.dart';

import '../../feature/release/release_type.dart';
import '../../feature/release/tracker.dart';
import 'style.dart';

/// Reads the template, the title template, the signature and the style for a
/// tracker and a release type from the app bundle (`ai/description_template.md`).
/// One folder per tracker holds the files.
///
/// The folder and the template file are named by the technical names, so the
/// value `release.json` writes, the enum value and the asset path are the same
/// string.
///
/// The asset bundle is a constructor parameter rather than `rootBundle`, so the
/// service reads no static (rule 10) and a test can substitute it.
class TemplateStore {
  TemplateStore({required this.bundle});

  final AssetBundle bundle;

  /// The default style. User styles come after user settings exist, so there is
  /// one name for now.
  static const defaultStyleFile = 'vanilla.style';

  /// The title template. It is the tracker's rule for how a post title is
  /// written, so there is one file per tracker — but a type whose title is
  /// written differently has its own file, named `<releaseType>.title.txt`,
  /// which is read first (`ai/description_template.md`), and a type with no
  /// title reads neither (`hasTitle`).
  static const titleFile = 'title.txt';

  /// The app signature: the app's own credit line. It is stored per tracker,
  /// because a tracker publishes its own wording for it, the same as the style
  /// and the title (`ai/description_template.md` §App signature). The templates
  /// place it with the `{{appSignature}}` block variable, so where it goes is
  /// the template's, not the code's.
  static const signatureFile = 'appSignature.txt';

  Future<TemplateResult> load({
    required Tracker tracker,
    required ReleaseType releaseType,
  }) async {
    final folder = 'assets/templates/${tracker.name}';

    final template = await _read('$folder/${releaseType.name}.txt');

    if (template == null) {
      return const TemplateFailure(TemplateFailureKind.templateNotFound);
    }

    final styleText = await _read('$folder/$defaultStyleFile');

    if (styleText == null) {
      return const TemplateFailure(TemplateFailureKind.styleNotFound);
    }

    // A type with no title reads no file (`hasTitle`), so there is nothing for
    // the section to show. Otherwise the title is read per release type first,
    // because a type may write it differently: a photoset has no video quality
    // to put in a title (`ai/single_photoset.md` §8). The tracker's file is the
    // fallback for a type that has none. A tracker without either still
    // generates the message: the title is empty rather than a failure, because
    // the post text does not depend on it.
    final title = hasTitle(releaseType)
        ? await _read('$folder/${releaseType.name}.title.txt') ??
              await _read('$folder/$titleFile') ??
              ''
        : '';

    // The app signature is one file per tracker, so there is no per-type file
    // for it, and a tracker without one reads as absent rather than as a
    // failure, the same rule as a title file: the post text does not depend on
    // it.
    final signature = await _read('$folder/$signatureFile') ?? '';

    return TemplateSuccess(
      template: template,
      title: title,
      signature: signature,
      style: Style.parse(styleText),
    );
  }

  /// One file from the bundle, or null when it is not there. The bundle reports
  /// a key it does not have with `FlutterError`, which is an `Error` and not an
  /// `Exception`, so `on Exception` alone would let a missing file escape as an
  /// unhandled exception in the running app; the test fakes throw the same
  /// shape.
  Future<String?> _read(String key) async {
    try {
      return await bundle.loadString(key);
    } catch (_) {
      return null;
    }
  }
}

sealed class TemplateResult {
  const TemplateResult();
}

final class TemplateSuccess extends TemplateResult {
  const TemplateSuccess({
    required this.template,
    required this.title,
    required this.signature,
    required this.style,
  });

  final String template;
  final String title;

  /// The app signature, or an empty string when the tracker has no file for it.
  final String signature;

  final Style style;
}

final class TemplateFailure extends TemplateResult {
  const TemplateFailure(this.kind);

  final TemplateFailureKind kind;
}

enum TemplateFailureKind {
  /// The template for this tracker and release type is not in the bundle. A
  /// type can have a field list before its template is written — the photoset
  /// pack is one (`ai/photoset_pack.md` §7), so this is what a pack gets until
  /// its template file exists.
  templateNotFound,

  /// The style file is not in the bundle.
  styleNotFound,
}
