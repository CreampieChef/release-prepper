import 'photoset_scanner.dart';

/// The picking rule (`ai/picking.md`): how many photos a pack picks, how they
/// are divided across the sets, and which ones inside a set. It is pure — it
/// takes the scanned sets and returns the picks, writes nothing and shows no
/// messages (rule 13) — so the rule can be tested on its own, because its
/// interesting cases are arithmetic rather than visual.
class PhotosetPicker {
  /// The numbers are a posting convention for the tracker, not a property of
  /// the pack. Whether they are constants here or values the tracker config
  /// holds is the decision `ai/photoset_pack.md` §7 names as open; the rule is
  /// the same either way, so they are kept as three numbers.
  static const minimumPicks = 5;
  static const percent = 5;
  static const maximumPicks = 50;

  /// The number the curve gives for a total (`ai/picking.md` §1). The three
  /// tiers the rule was described in are one curve: below 100 the percentage is
  /// under the minimum so the minimum shows, at 1000 it reaches the cap so the
  /// cap shows.
  static int pickCount(int total) {
    if (total <= 0) {
      return 0;
    }

    // ceil(total × percent / 100) in integer arithmetic, so the curve has no
    // rounding to drift.
    final share = (total * percent + 99) ~/ 100;
    var count = share < minimumPicks ? minimumPicks : share;

    if (count > maximumPicks) {
      count = maximumPicks;
    }

    // The case the tiers do not cover: a pack of 3 photos cannot pick 5.
    return count > total ? total : count;
  }

  /// The picks, one entry per set in the order the source gives them
  /// (`ai/picking.md` §2). A set with no photos is included with nothing
  /// picked, because the caller reports it rather than dropping it.
  static PickResult pick(List<ScannedSet> sets) {
    final total = sets.fold(0, (sum, set) => sum + set.photoCount);
    final count = pickCount(total);

    // The floor of each share. It is never above the set's size, because the
    // count is never above the total, so the cap `ai/picking.md` §2 describes
    // is what this arithmetic already does.
    final counts = List<int>.filled(sets.length, 0);
    final fractions = List<int>.filled(sets.length, 0);

    for (var index = 0; index < sets.length; index++) {
      final size = sets[index].photoCount;

      if (size == 0) {
        continue;
      }

      counts[index] = (count * size) ~/ total;
      fractions[index] = (count * size) % total;
    }

    // What rounding left over goes to the sets that can still take more,
    // largest fractional part first, ties broken by the order the source gives,
    // so the same input gives the same output.
    final order = [
      for (var index = 0; index < sets.length; index++)
        if (sets[index].photoCount > 0) index,
    ];

    order.sort((left, right) {
      final byFraction = fractions[right].compareTo(fractions[left]);
      return byFraction != 0 ? byFraction : left.compareTo(right);
    });

    var remaining = count - counts.fold(0, (sum, value) => sum + value);

    while (remaining > 0) {
      var distributed = false;

      for (final index in order) {
        if (remaining == 0) {
          break;
        }

        if (counts[index] < sets[index].photoCount) {
          counts[index]++;
          remaining--;
          distributed = true;
        }
      }

      // The sum of the sizes is the total, and the count is never above the
      // total, so there is always room. This is the guard, not the path.
      if (!distributed) {
        break;
      }
    }

    // The per-set minimum, which applies to every pack: a set that has photos
    // is never left out, and when it binds the total passes the cap.
    for (var index = 0; index < sets.length; index++) {
      if (sets[index].photoCount > 0 && counts[index] == 0) {
        counts[index] = 1;
      }
    }

    return PickResult(
      picks: [
        for (var index = 0; index < sets.length; index++)
          PickedSet(
            set: sets[index],
            photos: [
              for (final position in positions(
                sets[index].photoCount,
                counts[index],
              ))
                sets[index].photos[position],
            ],
          ),
      ],
    );
  }

  /// The pick positions inside a set: the centre of each interval, so the set
  /// is sampled from end to end rather than taken from its start, and a set
  /// that gives one photo gives its middle (`ai/picking.md` §3). Integer
  /// arithmetic, and defined for every count — `round` is not when a set gives
  /// every photo it has, because it produces positions past the end of the set.
  static List<int> positions(int size, int count) =>
      List.generate(count, (index) => (2 * index + 1) * size ~/ (2 * count));
}

/// One set and the photos it gives, in the order the source gives them. The
/// picking chooses which photos, not what order they are written in
/// (`ai/picking.md` §3).
class PickedSet {
  const PickedSet({required this.set, required this.photos});

  final ScannedSet set;
  final List<ScannedPhoto> photos;
}

/// The result of the rule, one entry per set in the order the source gives
/// them.
class PickResult {
  const PickResult({required this.picks});

  final List<PickedSet> picks;

  int get total =>
      [for (final pick in picks) pick.photos.length]
          .fold(0, (sum, count) => sum + count);
}
