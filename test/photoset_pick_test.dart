import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/service/images/image_dimensions.dart';
import 'package:release_prepper/service/photosets/photoset_picker.dart';
import 'package:release_prepper/service/photosets/photoset_scanner.dart';

void main() {
  // A set with [count] photos, named so the positions can be read back. No
  // files: the rule is arithmetic, and it does not read anything — the sizes
  // are what it does not read, so the fixture gives none.
  ScannedSet set(String path, int count) => ScannedSet(
    entry: SourceEntry(name: path, isDirectory: true, readPath: path),
    photos: [
      for (var index = 0; index < count; index++)
        ScannedPhoto(name: '${index.toString().padLeft(3, '0')}.jpg', size: 0),
    ],
  );

  // The same with dimensions, for the extremes, which are the one part of the
  // rule that reads them. Every photo has the given area except the ones the
  // test marks, so an extreme is one photo and not the whole fixture.
  ScannedSet measuredSet(
    String path,
    int count, {
    Map<int, ImageDimensions> extremes = const {},
  }) => ScannedSet(
    entry: SourceEntry(name: path, isDirectory: true, readPath: path),
    photos: [
      for (var index = 0; index < count; index++)
        ScannedPhoto(
          name: '${index.toString().padLeft(3, '0')}.jpg',
          size: 0,
          dimensions:
              extremes[index] ?? const ImageDimensions(width: 200, height: 200),
        ),
    ],
  );

  List<int> counts(PickResult result) => [
    for (final pick in result.picks) pick.photos.length,
  ];

  // The test calls the rule with what the popup would answer, so the numbers it
  // compares are the rule's own.
  PickOptions options(
    int count, {
    PickStrategy strategy = PickStrategy.perSet,
    bool includeExtremes = false,
  }) => PickOptions(
    count: count,
    strategy: strategy,
    includeExtremes: includeExtremes,
  );

  test('the value the popup opens at is the curve', () {
    // Below 100 the percentage is under the minimum, so the minimum shows.
    expect(PhotosetPicker.initialCount(99), 5);
    expect(PhotosetPicker.initialCount(100), 5);

    // Between 100 and 1000 the percentage shows.
    expect(PhotosetPicker.initialCount(500), 25);
    expect(PhotosetPicker.initialCount(999), 50);

    // At 1000 the percentage reaches the cap, so the cap shows.
    expect(PhotosetPicker.initialCount(1000), 50);
    expect(PhotosetPicker.initialCount(1200), 50);

    // A pack of 3 photos cannot pick 5; the rule clamps at the run, not here,
    // because the popup's minimum is what the row shows and the run takes what
    // exists.
    expect(PhotosetPicker.initialCount(3), 5);
    expect(PhotosetPicker.initialCount(0), 0);
  });

  test('the top of the range the popup can move the count in', () {
    // The cap, but a row cannot offer more than the pack has.
    expect(PhotosetPicker.maximumCountFor(150), 100);
    expect(PhotosetPicker.maximumCountFor(100), 100);
    expect(PhotosetPicker.maximumCountFor(20), 20);

    // At or below the minimum the top is the value the row opens at, so there is
    // nothing to move and the popup draws no row for the count.
    expect(PhotosetPicker.maximumCountFor(5), 5);
    expect(PhotosetPicker.maximumCountFor(3), 3);

    // Six is the smallest pack the row can show, because the value it opens at is
    // below what exists there.
    expect(PhotosetPicker.maximumCountFor(6), 6);
    expect(
      PhotosetPicker.maximumCountFor(6) > PhotosetPicker.initialCount(6),
      isTrue,
    );
  });

  test('the rule never picks more photos than the pack has', () {
    // The case the popup cannot show on its slider: the row asked for more than
    // the pack has, so the run takes everything.
    final result = PhotosetPicker.pick([set('set01', 3)], options(10));

    expect(result.total, 3);
    expect(counts(result), [3]);
  });

  test('the shares are divided by largest remainder', () {
    // The worked example in `ai/picking.md` §2.
    final result = PhotosetPicker.pick([
      set('set01', 300),
      set('set02', 250),
      set('set03', 200),
      set('set04', 250),
      set('set05', 200),
    ], options(50));

    expect(result.total, 50);
    expect(counts(result), [13, 11, 8, 10, 8]);

    // The tie between the two 250 sets is broken by the order the source gives
    // them.
    expect(result.picks[1].set.path, 'set02');
  });

  test('the smaller galleries are skipped when the count cannot reach them', () {
    // 60 sets of 20, 50 asked for: every share is 0.83, so the division already
    // leaves the last 10 with nothing, and nothing puts a photo back into them —
    // that is what the skipping of the smaller galleries is, with no step of its
    // own (`ai/picking.md` §2).
    final result = PhotosetPicker.pick([
      for (var index = 0; index < 60; index++) set('set$index', 20),
    ], options(50));

    expect(counts(result), [
      for (var index = 0; index < 60; index++) index < 50 ? 1 : 0,
    ]);
    expect(result.total, 50);
  });

  test('a small gallery is skipped when its share is below one photo', () {
    // 3 photos in one set and 100 in the other: the set of 3 has a share below
    // one, so it is skipped, and the total is the count asked for exactly.
    final result = PhotosetPicker.pick([
      set('set01', 3),
      set('set02', 100),
    ], options(6));

    expect(counts(result), [0, 6]);
    expect(result.total, 6);
  });

  test('the extremes replace the nearest pick, keeping the count', () {
    // Two measured sets of 20, 5 asked for. The division gives [3, 2] and the
    // interval centres [3, 10, 16] and [5, 15], so neither extreme is among the
    // picks; each replaces its nearest pick and the run still copies 5.
    final result = PhotosetPicker.pick([
      measuredSet(
        'set01',
        20,
        extremes: {0: const ImageDimensions(width: 10, height: 10)},
      ),
      measuredSet(
        'set02',
        20,
        extremes: {19: const ImageDimensions(width: 300, height: 300)},
      ),
    ], options(5, includeExtremes: true));

    expect(counts(result), [3, 2]);

    // Each extreme replaces the pick nearest to its own position: the first the
    // nearest of its set, the second the second position of its set, because
    // that is the nearest of the picks the division placed in that set.
    expect(result.picks.first.photos.map((photo) => photo.name), [
      '000.jpg',
      '010.jpg',
      '016.jpg',
    ]);
    expect(result.picks.last.photos.map((photo) => photo.name), [
      '005.jpg',
      '019.jpg',
    ]);
  });

  test('extremes that are among the picks are left as they are', () {
    // The same fixture with the extremes at positions the division already
    // reaches, so the answer is the answer without the checkbox.
    final withoutExtremes = PhotosetPicker.pick([
      measuredSet('set01', 20),
      measuredSet('set02', 20),
    ], options(5));
    final withExtremes = PhotosetPicker.pick([
      measuredSet(
        'set01',
        20,
        extremes: {3: const ImageDimensions(width: 10, height: 10)},
      ),
      measuredSet(
        'set02',
        20,
        extremes: {15: const ImageDimensions(width: 300, height: 300)},
      ),
    ], options(5, includeExtremes: true));

    expect(counts(withExtremes), counts(withoutExtremes));
  });

  test('a photo whose header cannot be read cannot be an extreme', () {
    // The unmeasured photo is at a position the division reaches; as the scan
    // says, it has no area, so it is not an extreme, and the answer is the same
    // as without the checkbox.
    final sets = [
      ScannedSet(
        entry: SourceEntry(name: 'set01', isDirectory: true, readPath: 'set01'),
        photos: [
          for (var index = 0; index < 20; index++)
            ScannedPhoto(
              name: '${index.toString().padLeft(3, '0')}.jpg',
              size: 0,
              dimensions: index == 3
                  ? null
                  : const ImageDimensions(width: 200, height: 200),
            ),
        ],
      ),
    ];

    expect(
      counts(PhotosetPicker.pick(sets, options(10, includeExtremes: true))),
      counts(PhotosetPicker.pick(sets, options(10))),
    );
  });

  test('an extreme is never replaced for the other one', () {
    // One measured set of 20, 2 asked for: the division gives one photo at its
    // centre, which the first extreme replaces, and the second one must not take
    // that photo back — without the rule that an extreme is kept, the nearest
    // pick to the second extreme would be the first.
    final result = PhotosetPicker.pick([
      measuredSet(
        'set01',
        20,
        extremes: {
          0: const ImageDimensions(width: 10, height: 10),
          2: const ImageDimensions(width: 300, height: 300),
        },
      ),
    ], options(2, includeExtremes: true));

    expect(result.total, 2);
    expect(result.picks.first.photos.map((photo) => photo.name), [
      '000.jpg',
      '002.jpg',
    ]);
  });

  test('the whole pack as one set picks across the whole array', () {
    // Two sets of 10, 5 asked for: the interval centres of the whole 20 are the
    // positions, and the result stays grouped by set, in the order the source
    // gives them (`ai/picking.md` §3).
    final result = PhotosetPicker.pick([
      set('set01', 10),
      set('set02', 10),
    ], options(5, strategy: PickStrategy.wholePack));

    expect(counts(result), [2, 3]);
    expect(result.picks.first.photos.map((photo) => photo.name), [
      '002.jpg',
      '006.jpg',
    ]);
    expect(result.picks.last.photos.map((photo) => photo.name), [
      '000.jpg',
      '004.jpg',
      '008.jpg',
    ]);
  });

  test('a set with no photos contributes nothing and is still reported', () {
    final result = PhotosetPicker.pick([
      set('set01', 0),
      set('set02', 100),
    ], options(5));

    expect(counts(result), [0, 5]);
    expect(result.picks.first.set.path, 'set01');
    expect(result.picks.first.photos, isEmpty);
  });

  test('the same input gives the same output twice', () {
    final sets = [set('set01', 300), set('set02', 250), set('set03', 120)];

    expect(
      counts(PhotosetPicker.pick(sets, options(50))),
      counts(PhotosetPicker.pick(sets, options(50))),
    );
  });

  test('the picks inside a set are the centre of each interval', () {
    expect(PhotosetPicker.positions(10, 3), [1, 5, 8]);

    // A group that gives one photo gives its middle.
    expect(PhotosetPicker.positions(10, 1), [5]);

    // A group that gives every photo it has stays inside itself, which is why
    // the positions are computed with floor rather than round.
    expect(PhotosetPicker.positions(5, 5), [0, 1, 2, 3, 4]);
  });

  test('the picks keep the order the source gives them', () {
    final result = PhotosetPicker.pick([
      set('set01', 10),
      set('set02', 10),
    ], options(5));

    for (final pick in result.picks) {
      final names = pick.photos.map((photo) => photo.name).toList();
      expect(names, names.toList()..sort());
    }
  });

  // The rule reads dimensions only for the extremes, so without the checkbox the
  // dimensions do not change what is picked.
  test('without the extremes the dimensions do not change what is picked', () {
    List<int> countsOf(List<ScannedPhoto> photos) => counts(
      PhotosetPicker.pick([
        ScannedSet(
          entry: SourceEntry(
            name: 'set01',
            isDirectory: true,
            readPath: 'set01',
          ),
          photos: photos,
        ),
      ], options(5)),
    );

    final measured = [
      for (var index = 0; index < 20; index++)
        ScannedPhoto(
          name: '${index.toString().padLeft(3, '0')}.jpg',
          size: 0,
          dimensions: const ImageDimensions(width: 100, height: 100),
        ),
    ];

    final unread = [
      for (var index = 0; index < 20; index++)
        ScannedPhoto(
          name: '${index.toString().padLeft(3, '0')}.jpg',
          size: 0,
          dimensions: index == 7
              ? null
              : const ImageDimensions(width: 100, height: 100),
        ),
    ];

    expect(countsOf(unread), countsOf(measured));
  });
}
