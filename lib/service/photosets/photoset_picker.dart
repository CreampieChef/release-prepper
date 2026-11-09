import 'photoset_scanner.dart';

import '../images/image_dimensions.dart';

/// The two strategies the popup offers for which photos are picked
/// (`ai/picking.md` §2). The count is not the rule's decision either: the
/// popup decides the count, the strategy, and the extremes, and the rule is
/// called with what it decided.
enum PickStrategy {
  /// The count is divided across the sets in proportion to their size, by
  /// largest remainder, with no floor per set: a set whose share is below one
  /// photo gets none, so the smaller galleries are skipped when the count is
  /// smaller than the number of sets.
  perSet,

  /// The whole pack is treated as one set: the count is placed evenly across
  /// the whole array, in the order the source gives the sets and, within a set,
  /// the order it gives the photos.
  wholePack,
}

/// What the popup decided: the count, the strategy, and whether the extremes
/// must be among the picks. The popup owns these as widget state, as the other
/// sections own their sliders; this is what the rule is called with.
class PickOptions {
  const PickOptions({
    required this.count,
    required this.strategy,
    required this.includeExtremes,
  });

  final int count;
  final PickStrategy strategy;
  final bool includeExtremes;
}

/// The picking rule (`ai/picking.md`): how many photos a pack picks, how the
/// chosen strategy divides them, and the extremes the popup asked for. It is
/// pure — it takes the scanned sets and the options and returns the picks,
/// writes nothing and shows no messages (rule 13) — so the rule can be tested
/// on its own, because its interesting cases are arithmetic rather than visual.
class PhotosetPicker {
  /// The numbers are a posting convention for the tracker, not a property of
  /// the pack. Whether they are constants here or values the tracker config
  /// holds is the decision `ai/photoset_pack.md` §7 names as open; the rule is
  /// the same either way, so they are kept as numbers. These are the numbers
  /// the popup's slider is built from.
  static const percent = 5;
  static const minimumCount = 5;
  static const initialCap = 50;
  static const maximumCount = 100;

  /// The value the popup's slider opens at, which is its minimum
  /// (`ai/picking.md` §1): 5% of the total rounded up, not below the minimum
  /// and not above the cap, so the user can only raise it. The rule takes the
  /// count as the user chose it except that it cannot pick more photos than
  /// there are, so for a pack smaller than what the row asks for, the run takes
  /// everything.
  static int initialCount(int total) {
    if (total <= 0) {
      return 0;
    }

    // ceil(total × percent / 100) in integer arithmetic, so the curve has no
    // rounding to drift.
    final share = (total * percent + 99) ~/ 100;

    var count = share < minimumCount ? minimumCount : share;

    if (count > initialCap) {
      count = initialCap;
    }

    return count;
  }

  /// The value the popup's slider can be raised to (`ai/picking.md` §1): the cap,
  /// but a row cannot offer more than the pack has, so this is the smaller of the
  /// two. For a pack at or below the minimum the two bounds are the same number,
  /// so there is nothing for the row to move and the popup draws nothing for the
  /// count; the run takes what exists, which is the clamping `pick` already does.
  static int maximumCountFor(int total) =>
      total < maximumCount ? total : maximumCount;

  /// The picks, one entry per set in the order the source gives them
  /// (`ai/picking.md` §2). A set with no photos is included with nothing
  /// picked, because the caller reports it rather than dropping it.
  static PickResult pick(List<ScannedSet> sets, PickOptions options) {
    final total = sets.fold(0, (sum, set) => sum + set.photoCount);

    // The rule never promises more photos than the pack has, so the count the
    // popup asked for is taken as far as what is there.
    final count = options.count > total ? total : options.count;

    // Which photos are picked is held as positions in the whole array of the
    // pack, in the order the source gives them, because that is the one shape
    // both strategies choose in and the one shape the extremes step reads.
    final chosen = <int>{};

    if (count > 0) {
      switch (options.strategy) {
        case PickStrategy.perSet:
          chosen.addAll(perSetPositions(sets, count));
        case PickStrategy.wholePack:
          chosen.addAll(positions(total, count));
      }

      if (options.includeExtremes) {
        keepExtremes(sets, chosen);
      }
    }

    // The positions are read back as the picks per set, in the order the source
    // gives them, so that the caller can copy set by set and keep the records
    // in the order the scan wrote them (`ai/picking.md` §3).
    final picks = <PickedSet>[];
    var start = 0;

    for (final set in sets) {
      final end = start + set.photoCount;

      picks.add(
        PickedSet(
          set: set,
          photos: [
            for (var position = start; position < end; position++)
              if (chosen.contains(position)) set.photos[position - start],
          ],
        ),
      );

      start += set.photoCount;
    }

    return PickResult(picks: picks);
  }

  /// Strategy one: the positions the count gives when it is divided across the
  /// sets in proportion to their size, by largest remainder (`ai/picking.md`
  /// §2), read as positions in the whole array. There is no floor per set, so a
  /// set whose share is below one photo gets none, and that is what the skipping
  /// of the smaller galleries is: not a step of its own, but what the division
  /// already does when the count is smaller than the number of sets.
  static List<int> perSetPositions(List<ScannedSet> sets, int count) {
    final total = sets.fold(0, (sum, set) => sum + set.photoCount);

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

    // What rounding leaves over goes to the sets that can still take more, in
    // order of the largest fractional part, ties broken by the order the source
    // gives, so the same input gives the same output.
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

    final picked = <int>[];
    var start = 0;

    for (var index = 0; index < sets.length; index++) {
      for (final position in positions(sets[index].photoCount, counts[index])) {
        picked.add(start + position);
      }

      start += sets[index].photoCount;
    }

    return picked;
  }

  /// The extremes the popup asked for (`ai/picking.md` §4): the smallest and
  /// the largest photo by pixel area, on the same comparison the scan uses for
  /// the fields it writes, so the rule agrees with what the post says. An
  /// extreme that is not among the picks replaces the pick nearest to it, so the
  /// run copies exactly the count the user asked for. An extreme put in this way
  /// is never put out again for the other one, which is what makes a count below
  /// three the case the guarantee cannot keep — the popup's minimum is above
  /// three, so that case is the guard, not the path.
  static void keepExtremes(List<ScannedSet> sets, Set<int> chosen) {
    final kept = <int>{};

    for (final position in [
      extremePosition(sets, (left, right) => left.area < right.area),
      extremePosition(sets, (left, right) => left.area > right.area),
    ]) {
      // A photo whose header could not be read has no area, so it cannot be an
      // extreme, and a pack with nothing measurable has nothing to guarantee.
      if (position == null) {
        continue;
      }

      if (chosen.contains(position)) {
        kept.add(position);
        continue;
      }

      // The nearest pick that is not itself an extreme put in for the other one.
      // The picks are read in the order the source gives them, so the first one
      // at the nearest distance is the one that comes first, and the same input
      // gives the same output.
      int? nearest;

      for (final index in chosen.toList()..sort()) {
        if (kept.contains(index)) {
          continue;
        }

        if (nearest == null ||
            (index - position).abs() < (nearest - position).abs()) {
          nearest = index;
        }
      }

      // The count cannot hold both extremes.
      if (nearest == null) {
        continue;
      }

      chosen.remove(nearest);
      chosen.add(position);
      kept.add(position);
    }
  }

  /// The position in the whole array of the photo that the comparison says is
  /// the extreme — the smallest or the largest by pixel area
  /// (`ai/picking.md` §4). Null when no photo could be measured, which is what
  /// the scan reports as well. The first photo of an equal area is the one kept,
  /// so the same input gives the same output twice.
  static int? extremePosition(
    List<ScannedSet> sets,
    bool Function(ImageDimensions, ImageDimensions) isMore,
  ) {
    ImageDimensions? best;
    int? position;
    var start = 0;

    for (final set in sets) {
      for (var index = 0; index < set.photoCount; index++) {
        final dimensions = set.photos[index].dimensions;

        if (dimensions == null) {
          continue;
        }

        if (best == null || isMore(dimensions, best)) {
          best = dimensions;
          position = start + index;
        }
      }

      start += set.photoCount;
    }

    return position;
  }

  /// The pick positions: the centre of each interval, so the thing being picked
  /// from is sampled from end to end rather than taken from its start, and a
  /// group that gives one photo gives its middle (`ai/picking.md` §3). The same
  /// rule serves both strategies, because strategy two is strategy one applied to
  /// the whole array instead of to one set. Integer arithmetic, and defined for
  /// every count — `round` is not when a group gives every photo it has, because
  /// it produces positions past the end.
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
