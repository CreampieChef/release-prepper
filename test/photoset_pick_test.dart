import 'package:flutter_test/flutter_test.dart';

import 'package:release_prepper/service/images/image_dimensions.dart';
import 'package:release_prepper/service/photosets/photoset_picker.dart';
import 'package:release_prepper/service/photosets/photoset_scanner.dart';

void main() {
  // A set with [count] photos, named so the positions can be read back. No
  // files: the rule is arithmetic, and it does not read anything.
  ScannedSet set(String path, int count) => ScannedSet(
    entry: SourceEntry(name: path, isDirectory: true, readPath: path),
    photos: [
      for (var index = 0; index < count; index++)
        ScannedPhoto(name: '${index.toString().padLeft(3, '0')}.jpg'),
    ],
  );

  List<int> counts(PickResult result) => [
    for (final pick in result.picks) pick.photos.length,
  ];

  test('the number is one curve', () {
    // Below 100 the percentage is under the minimum, so the minimum shows.
    expect(PhotosetPicker.pickCount(99), 5);
    expect(PhotosetPicker.pickCount(100), 5);

    // Between 100 and 1000 the percentage shows.
    expect(PhotosetPicker.pickCount(500), 25);
    expect(PhotosetPicker.pickCount(999), 50);

    // At 1000 the percentage reaches the cap, so the cap shows.
    expect(PhotosetPicker.pickCount(1000), 50);
    expect(PhotosetPicker.pickCount(1200), 50);

    // The case the tiers do not cover: a pack cannot pick more than it has.
    expect(PhotosetPicker.pickCount(3), 3);
    expect(PhotosetPicker.pickCount(0), 0);
  });

  test('the shares are divided by largest remainder', () {
    // The worked example in `ai/picking.md` §2.
    final result = PhotosetPicker.pick([
      set('set01', 300),
      set('set02', 250),
      set('set03', 200),
      set('set04', 250),
      set('set05', 200),
    ]);

    expect(result.total, 50);
    expect(counts(result), [13, 11, 8, 10, 8]);

    // The tie between the two 250 sets is broken by the order the source gives
    // them.
    expect(result.picks[1].set.path, 'set02');
  });

  test('the per-set minimum binds when a set would get nothing', () {
    // 60 sets of 20: every share is 0.83, so 50 sets get one by rounding and
    // the other 10 are given one, which is where the total passes the cap.
    final result = PhotosetPicker.pick([
      for (var index = 0; index < 60; index++) set('set$index', 20),
    ]);

    expect(counts(result), List.filled(60, 1));
    expect(result.total, 60);
  });

  test('the minimum applies to a small pack too', () {
    // 103 photos in two sets: the curve gives 6, and the set of 3 would get
    // none, so it gets one and the total grows past what the curve asked for.
    final result = PhotosetPicker.pick([set('set01', 3), set('set02', 100)]);

    expect(counts(result), [1, 6]);
    expect(result.total, 7);
  });

  test('a set with no photos contributes nothing and is still reported', () {
    final result = PhotosetPicker.pick([set('set01', 0), set('set02', 100)]);

    expect(counts(result), [0, 5]);
    expect(result.picks.first.set.path, 'set01');
    expect(result.picks.first.photos, isEmpty);
  });

  test('the same input gives the same output twice', () {
    final sets = [set('set01', 300), set('set02', 250), set('set03', 120)];

    expect(
      counts(PhotosetPicker.pick(sets)),
      counts(PhotosetPicker.pick(sets)),
    );
  });

  test('the picks inside a set are the centre of each interval', () {
    expect(PhotosetPicker.positions(10, 3), [1, 5, 8]);

    // A set that gives one photo gives its middle.
    expect(PhotosetPicker.positions(10, 1), [5]);

    // A set that gives every photo it has stays inside the set, which is why
    // the positions are computed with floor rather than round.
    expect(PhotosetPicker.positions(5, 5), [0, 1, 2, 3, 4]);

    // The positions are read back from the result, so the rule and the photos
    // agree. Two equal sets of 10 give the first one three picks, by the tie in
    // their shares.
    final result = PhotosetPicker.pick([set('set01', 10), set('set02', 10)]);

    expect(result.picks.first.photos.map((photo) => photo.name), [
      '001.jpg',
      '005.jpg',
      '008.jpg',
    ]);
  });

  test('the picks keep the order the source gives them', () {
    final result = PhotosetPicker.pick([set('set01', 10), set('set02', 10)]);

    for (final pick in result.picks) {
      final names = pick.photos.map((photo) => photo.name).toList();
      expect(names, names.toList()..sort());
    }
  });

  // The rule reads counts only, so a photo whose header could not be read is
  // picked the same way.
  test('the dimensions do not change what is picked', () {
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
      ]),
    );

    final measured = [
      for (var index = 0; index < 20; index++)
        ScannedPhoto(
          name: '${index.toString().padLeft(3, '0')}.jpg',
          dimensions: ImageDimensions(width: 100, height: 100),
        ),
    ];

    final unread = [
      for (var index = 0; index < 20; index++)
        ScannedPhoto(
          name: '${index.toString().padLeft(3, '0')}.jpg',
          dimensions: index == 7
              ? null
              : ImageDimensions(width: 100, height: 100),
        ),
    ];

    expect(countsOf(unread), countsOf(measured));
  });
}
