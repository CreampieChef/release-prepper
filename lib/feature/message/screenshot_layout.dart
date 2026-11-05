/// The two shapes the screenshot block can have for a release that groups its
/// images per item (`ai/video_pack.md` §7).
///
/// It is stored on the release, in `release.json`, because `message.txt` holds a
/// block built with one of the two: a release opened again shows the shape its
/// post was written with, not the shape the app happens to default to.
enum ScreenshotLayout {
  /// One spoiler per hoster, and inside it one per item.
  byHoster,

  /// One spoiler per item, and inside it one per hoster.
  byItem,
}
