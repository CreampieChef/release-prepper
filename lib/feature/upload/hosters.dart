import '../settings/settings.dart';

/// The hosters the app has, in the order the Upload section lists them
/// (`ai/upload_images.md`). [name] is the `Server Name` from `Data/servers.xml`
/// (`ai/bundled_native_tools.md`): the value passed to `--server` must be the
/// exact name, so it is also what the section shows.
///
/// The selected hosters are not stored yet.
List<Hoster> get hosters => devMode ? mockHosters : realHosters;

/// Whether the app was started with `--dev`, which replaces the real hosters
/// with the mock ones so a development run uploads to the Python test server
/// instead of to a real hoster (`ai/upload_images.md`).
///
/// This is the one top-level variable in the app, and the one exception to rule
/// 10. It is set once by `main()` before the app is built and nothing writes it
/// afterwards, so the registry stays the single place the app and the tests
/// read the hosters from, and the message reads it for the poster hoster name
/// that applies to the run.
bool devMode = false;

/// The hosters a normal run uses.
const realHosters = [
  Hoster(name: 'fastpic.org', iconAsset: 'assets/icons/hosters/fastpic.png'),
  Hoster(
    name: 'turboimagehost.com',
    iconAsset: 'assets/icons/hosters/turboimagehost.png',
  ),
  Hoster(name: 'pixhost.to', iconAsset: 'assets/icons/hosters/pixhost.png'),
  Hoster(
    name: 'postimages.org',
    iconAsset: 'assets/icons/hosters/postimages.png',
    field: SettingsField.postimages,
  ),
];

/// The hosters a `--dev` run uses instead, which call the Python test server
/// (`test-hoster/rp_test_hoster.py`). They have no icon asset, so they are
/// drawn with the placeholder `HosterIcon` shows.
const mockHosters = [
  Hoster(name: 'rptest-a', iconAsset: 'assets/icons/hosters/rptest_a.png'),
  Hoster(name: 'rptest-b', iconAsset: 'assets/icons/hosters/rptest_b.png'),
];

class Hoster {
  const Hoster({required this.name, required this.iconAsset, this.field});

  final String name;

  /// The asset the section draws the hoster with.
  final String iconAsset;

  /// The settings field whose value this hoster's script reads, or null when
  /// the hoster needs no credential. This is the data behind two rules that
  /// used to be stated in prose: the app passes `UPTOODA_HOSTER_API_KEY` only
  /// for a hoster that has one here (`ai/bundled_native_tools.md`), and the
  /// section shows such a hoster as unusable while its value is empty
  /// (`ai/upload_images.md`).
  ///
  /// A hoster is listed here only when its bundled script can use the value, so
  /// this is the point where the settings field and the script meet. Postimages
  /// is the first: its script reads the variable. `fastpic_custom`,
  /// `turboimagehost_custom` and `pixhost.to` do not.
  final SettingsField? field;
}
