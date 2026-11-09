# Picking photos from a pack

**Implemented.** The rule is `lib/service/photosets/photoset_picker.dart`; the writing is the
photosets controller and the showing is the block and the photo area (§7). `ai/photoset_pack.md` §6
is the seam this fills, and the places in `ai/doc.md` that describe the feature — §2, the two
inventory entries in §3, the runtime flow in §5, and the key list in §6 — were updated in the same
change, as the project rule requires.

## 1. How many

The number is the user's: the popup asks for it and the rule runs with what it was asked for. What
the rule holds is the value the popup's slider opens at, which is also the slider's minimum, so the
user can only raise it — and only as far as the smaller of 100 and what the pack has, because a row
cannot offer more than the pack has.

```
opens at = clamp(ceil(5% × total), 5, 50)
can be raised to = min(100, total)
```

- Below 100 photos the percentage is under 5, so the minimum shows: 5.
- Between 100 and 1000 the percentage shows.
- At 1000 or more the percentage reaches 50, so the cap shows.

The rule was described as three tiers, and they are the same curve at every point: at 100 the
percentage is 5, at 1000 it is 50. The curve is what the code should hold, because three branches
that agree everywhere are one rule written twice.

At the run the count is taken as far as the pack has, because the rule never promises more photos
than exist: a pack of 3 photos picks 3. That is where `min(total, …)` belongs — not on the curve,
because the curve is the number the row shows, and the row shows a number a user can be asked for.
The two are `PhotosetPicker.initialCount` and the clamping in `pick`.

The same two bounds say what happens at or below the minimum: there is nothing to choose, because the
value the row would open at is the whole of what exists, so the bounds are the same number and there
is no range to move in. The row is not drawn for a pack of 5 or fewer, and the run copies everything,
which is what the clamping already does. This is not a rule of its own — it is what the two bounds
give at 5 — so the code draws the row only when they differ, and the tests show the absence as that
case rather than as a fixed size.

The old floor — every set with photos gets at least one, so a pack of 20 sets picked at least 20
even though 5% of its photos is 5 — is gone. It only changed anything when a set's share was below
one photo, and when it did the total was no longer the number asked for. When the number is the
user's, the run copies exactly that number, so a set whose share is below one photo gets none: that
is what §2 describes as the skipping of the smaller galleries, and what a small set is shown as in
the post.

## 2. Which photos: the two strategies

The popup offers two, and the rule runs with the one it was answered with. Both are the same
arithmetic with the count the user chose; they differ only in what the count is divided across.

Strategy one divides the count across the sets in proportion to their size, by largest remainder:

1. Each set's share is `count × its size / total`. Its count is the floor of that share.
2. A set can never give more than it has, so a count is capped at the set's size — which the
   arithmetic already does, because the count is never above the total.
3. The picks left over — from rounding, and from sets that could not give what their share asked
   for — go to the sets that can still take more, in order of the largest fractional part of their
   share, until the total is the count.
4. A tie is broken by the order the source gives, so the same input gives the same output.

There is no floor per set, so a set whose share is below one photo gets none. That is the skipping
of the smaller galleries: not a step of its own, but what the division already does when the count
is smaller than the number of sets. The result is exactly the number the user asked for, which is
what the floor used to break.

Strategy two treats the whole pack as one set: the count is placed evenly across the whole array of
the photos, in the order the source gives the sets and, within a set, the order it gives the
photos. The positions come from the same formula as §3, applied to the whole array instead of to one
set; the result is still reported per set, in the order the source gives them, because the records
are written per set (`ai/photoset_pack.md` §4).

A set with no photos contributes nothing and is reported, as the scan reports what it cannot take.

Example, the pack it was described with — 5 sets, 1200 photos, sizes 300, 250, 200, 250, 200, and
the count 50 asked for:

- Shares: 12.5, 10.42, 8.33, 10.42, 8.33. Floors: 12, 10, 8, 10, 8 = 48.
- The two remaining picks go to the largest fractional parts: the 300 set and the first 250 set.
- Result: 13, 11, 8, 10, 8 = 50.

The same pack with 60 sets of 20 photos each is the case where sets are skipped: every share is
0.83, so the floors are all 0 and the 50 go to the largest fractional parts in the order the source
gives the sets — the first 50 sets get one photo each and the last 10 get none. The total is 50,
not 60, and that is the difference the floor used to make.

Two sets of 10 photos with the count 5 asked for, as strategy two: the positions of the whole array
of 20 are 2, 6, 10, 14, 18, so the first set gives photos 2 and 6 and the second gives 0, 4 and 8 —
2 and 3, which is not what strategy one gives for the same pack (3 and 2).

## 3. Which photos inside a group

Within the group a count is divided over, the picked photos are evenly spaced across it, so the group
is sampled from end to end rather than taken from its start. Each pick is at the centre of its own
interval: for a group of m photos giving k picks, the pick positions are

```
floor((i + 0.5) × m / k)   for i = 0 … k−1
```

which is evenly spaced, stays inside the group for every k, and starts at the middle of the first
interval rather than at the first photo. For k = 1 it is the middle photo of the group, which is what
the rule asks for when a set appears in the post with a single photo. The integer form the code uses
is the same value, `(2i + 1) × m ÷ 2k` with integer division, because `round` gives positions past
the end when a group gives every photo it has.

The two things the rule was given as — evenly spaced, and around the middle — agree on this
definition: the interval centres cover the group from end to end, and the middle is where a group that
contributes one photo is sampled from.

The same formula serves both strategies of §2, because strategy two is strategy one applied to the
whole array instead of to one set: under strategy one the group is a set, under strategy two it is the
pack, so the positions are read as positions in the whole array and then taken back per set. That is
the only place the two differ, and it is why the formula is written once.

The picked photos keep the order the source gives them. The picking chooses which photos, not what
order they are written in, so the records stay in the order the scan wrote them
(`ai/photoset_pack.md` §4).

## 4. What the rule reads, and the extremes it keeps

Counts. The resolutions are fields the scan fills and the post shows, and they do not decide which
photos are picked — except when the popup asks for the extremes, which is the one case where the rule
does read them. So the picker needs the scan to have run, for the counts, and the dimensions only for
what the checkbox asks for.

When the extremes are asked for, the rule keeps the smallest and the largest photo by pixel area among
the picks, on the same comparison the scan uses for the fields it writes, so the rule agrees with what
the post says. An extreme that is not among the picks replaces the pick nearest to it, so the run
copies exactly the count the user asked for: the guarantee is kept without adding a photo, because the
count is the number the user chose.

Three things make this deterministic, and they are what the tests check rather than rely on:

- An extreme put in this way is never put out again for the other one. Without that, a count of two
  would put the first extreme back out to make room for the second, and the guarantee would be kept
  for one extreme only. A count below three is the case the guarantee cannot keep at all, because two
  extremes need two picks; the popup's minimum is above three, so this is the guard, not the path.
- A photo whose header could not be read has no area, so it cannot be an extreme, and a pack with
  nothing measurable has nothing to guarantee.
- Of the picks that can be replaced, the first one at the nearest distance in the order the source
  gives is the one replaced, and the first photo of an equal area is the extreme. So the same input
  gives the same output.

The numbers — 5, 5%, 50, and the 100 the slider goes up to — are a posting convention for the
tracker, not a property of the pack. Whether they are constants in the code or values the tracker
config holds is the same decision `ai/photoset_pack.md` §7 already names as open. The rule itself does
not change either way, so the rule is written here as data: numbers, a distribution method, and the
extremes.

## 5. Where it lives

`lib/service/photosets/photoset_picker.dart`: a pure function that takes the scanned sets and the
options the popup answered with — the count, the strategy, the extremes — and returns the picks. No
UI, no `BuildContext` (rule 13), no writing — the controller copies what the rule chose and records
it, and the widget shows it. The popup owns the values as widget state, as the other sections own
their sliders, and hands them over as `PickOptions`; that is the whole interface between the two, and
it is why the rule can be called with what a test would answer rather than with what a widget shows.

The seam `ai/photoset_pack.md` §6 defines is unchanged: the selector takes the items and a rule and
returns the photos it picks; this document is the rule.

The rule is tested on its own, because its interesting cases are arithmetic rather than visual: the
curve at a pack below 100, at exactly 100 and exactly 1000, and a pack smaller than the number the
row asks for; a set smaller than its share and a pack with more sets than the count; the largest
remainder and the ties it breaks; the whole pack as one set; an extreme replacing its nearest pick,
an extreme that is already among the picks, a photo whose header cannot be read, and a count that
cannot hold both extremes; a set with no photos; and that the same input gives the same output twice.
What the popup shows is tested as a widget, separately, because that is a drawing rather than
arithmetic.

The numbers are constants on the class. If the tracker config decision goes the other way they become
values the config holds; the rule itself does not change either way.

## 6. Left open

- Whether the app copies the picked photos into the release or uploads them from the source.
  `ai/release_structure.md` §4 says copy, and the code copies. The cost is disk space and a source
  that may be gone later. This is `ai/photoset_pack.md` §9 and is not decided here.
- Whether the numbers are constants or tracker config (§4).

What re-running the picker does is no longer open: with the same answer the rule is deterministic, so
a re-pick with the same values recomputes the same picks and replaces the records it writes. It only
differs when the scan changed or the popup was answered differently — and the popup does not remember
the last answer, so a re-pick starts from the rule's values again (§7).

## 7. The block and the photo area

The Photoset feature is the extended section, not a new section. Pick opens a popup, and the popup's
values are the popup's own widget state, as the other sections hold their slider values: the extremes
checkbox, the choice of strategy, and the slider for the count. The three are what the rule is called
with, and the rule is called with what the popup answered with — the feature does not show what the
rule decided on its own, because the rule no longer decides the number by itself.

Only a pack has the choice of strategy. For the type with one set the whole pack is that set, so the
two answers are the same and there is nothing to choose, so the strings for the choice are null for
that type and the popup draws no row for it (`ai/single_photoset.md` §6). The popup is one
implementation for both types, and what a type does not have is what is not drawn: null in the strings
resolved per type, as the header naming a list and the row counting items are here. The answer for
that type carries the strategy the popup opens with, which is what both answers give for one set.

The values open at the rule's, on every open rather than remembered from the last popup: the count the
curve gives for the total the scan read (§1), the division per set, and the extremes kept. The count
can only be raised, because its minimum is the value the row opens at, and only as far as the smaller
of 100 and what the pack has (§1). At or below the minimum the two are the same number, so there is
nothing to move and the row for the count is not drawn: the answer carries the value the popup opened
at, and the run takes what exists. The run
happens on the popup's answer, and a popup dismissed without one — Cancel, or any other dismissal —
runs nothing, the same rule as the close popup (`ai/doc.md` §2). A widget test that is not about the
popup answers it with the extremes off, because the fixtures those tests build carry no dimensions and
the extremes are the only part of the rule that reads them (§4).

For a pack it is two widgets, because it is in two grid cells. The block is the page's second
column, at the most the width this feature gives it: its heading with the Scan and Pick buttons at
its right, the rows the editor gives it, the header naming the list of sets, the row naming the two
columns of that list, and the line naming each set the scan found. What the row has left after the
fields' column and the block's column is the photo area. One widget cannot be two cells, so the two
are two widgets, and what they have to share — the controller, and the generation the pictures are
keyed with — is held by the editor, the widget that places them (`AGENTS.md` §5). The sections that
need a column's width — the Upload section, the Message section, the draft — stay stacked below the
fields in the fields' column, because the block's column is too narrow for their rows, and the
Torrent section is drawn at the top of that stack, above the Upload section (`ai/torrents.md`). A
single photoset has no space beside its block for its pictures, so there is no area beside it: its
block is the whole feature and draws the photos with the same grid the pack draws, but not split by
kind, because with one set there is nothing to group (`ai/single_photoset.md` §7).

- Scan and Pick are two buttons in the block's heading row. Pick is disabled until a scan has run,
  because what the popup opens with is what the scan read: the slider's value is the number the curve
  gives for the total, and a block that has not scanned has no total. The block keeps no values of its
  own; it asks the rule what the popup should open with, the way the feature asks the rule for the
  rest.

- Pick asks the popup, and the run happens on its answer. There is no preview of the rule before the
  files are written: the feature shows what is on disk, as the Screenshots section does. The popup is
  the asking rather than a preview — it decides the number, the method, and the extremes, and the run
  is the rule applied to what it decided, in one step.

- While a run is going the block draws a progress row: the bar and the count next to it, with the
  shared `ProgressRow` (`lib/feature/progress_row.dart`), the same shape as the bar the Upload
  section draws for each hoster (`ai/upload_images.md`). The row is drawn only while a run is going,
  as the Torrent section's progress is (`ai/torrents.md`): before a run there is nothing to show, and
  after one the results the run produced are what the block shows. The words around the two numbers
  name what the run counts, so they are resolved per type and the row is given what they say
  (`ai/doc.md` §6).

- Both counts are known before the run has done anything, because both are what the run can know
  first: the scan decides which entries are items before it reads any of them, and the pick is the
  rule's arithmetic before it copies a file. So a row has a measure from its first report. The scan
  counts items, which is what a type's item is: for the type whose item is the folder the user picked
  the item count is one, so a row counting items says nothing, its words for a scan row are null, and
  nothing is drawn for that type (`ai/image_folder_upload.md` §5).

- What the block shows while a run is going is what the run has done so far, not what it will do.
  A set's line is drawn when that set is read, so a root with many sets shows what it has found as it
  finds it; the items are replaced at the report that only gives the total — the point the scan has
  decided what the source contains — so a scan that cannot read the folder replaces nothing. A pick
  shows the photos as it copies them, and the count on a line is the records that exist, so a photo
  the run could not write does not move it, which is the rule the Upload section's bars follow.
  Because the block and the photo area are two widgets in two grid cells, the block records what its
  run wrote in the state the editor holds and tells the editor for each photo, so the area builds as
  each photo is written rather than after the run — the generation cannot be the block's own counter
  here for the same reason it is not a widget's counter in `AGENTS.md` §5.

- The picked photos are one grid, not one column per set.
  For a pack the grid is split by kind instead of being one set of columns: the portraits are drawn
  in columns of the portrait width and the landscapes in columns of the landscape width, and the two
  never share a column. Within each kind the order is the order the source gives the sets and,
  within a set, the order it gives the photos, so the order across the whole grid is not the order
  the source gives — that is what grouping by kind means. A single photoset is not split, so its
  photos are in the order the source gives them (`ai/single_photoset.md` §7). Nothing groups them by
  set, so each tile says which set its photo is from as well as its file name. The line naming the
  set is drawn only where the grid mixes sets, which is the pack's; a single photoset has one set,
  which its block names above the photos, so its tiles keep the file name alone. The message still
  groups them by set (`ai/photoset_pack.md` §7), because that is a list rather than a grid.

- The rows the block draws — the path the user picked and the counts the scan took from it — are
  built by the editor, because they are form rows. For a pack they belong to the block; every other
  type keeps them as rows of the form.

- For a pack the area is titled Screenshots, because what it shows is the pictures rather than the
list of sets, and it uses the title the Screenshots section titles itself with, so the two areas
that show the same files the same way say the same word. The line naming a set is drawn once, in the
block, which is what lists the sets: the grid no longer names a set above its photos, because the
tile says which set its photo is from. For a single photoset the block's heading is the title and it
draws the photos under its line.

- The word Photosets is the block's heading and the label of the count field it draws, so it is said
  twice for a pack, and the word Screenshots once, as the title of the area. Only one column of the
  page is titled by the editor (`ai/doc.md` §2).

- The grid is the same for both types, at the three numbers `photoset_group.dart` gives it:
  as many columns of `photosetColumnWidth` as fit in the space the area is given, and what those
  columns cannot use is shared out rather than left as a strip at the right, so a column is that
  width or a little more — except where the pack bounds it, below. A landscape takes the number of
  those columns that makes it `photosetLandscapeWidth` wide, worked out by `photoSpanCount`, because
  a grid can only be a whole number of columns wide. The columns have no gap of their own, because a
  spanned column must be exactly as many of them as the two numbers say: the space between two tiles
  is the padding inside them. The block's column is at most `photosetBlockMaxWidth`, and the width
  it does not use is the area's, so the cap does not leave an empty strip beside the block. The
  fitting is in `lib/service/images/masonry.dart` with the rest of the placement.

- Only the pack splits the columns by kind, and the counts decide the split.
  A kind with no photos has no columns; a kind with photos has at least one column — for a landscape
  that is one of its own, so the span — and never more than its photos need, which is one column per
  photo. What the two minimums do not take is shared in proportion to the counts, and a kind already
  at what its photos need gives its share to the other, so a few photos of one kind do not make
  columns for the other kind that nothing fills. A landscape can only be drawn across a whole span,
  so the columns a landscape zone gets are whole spans: the column rounding leaves over is one that
  kind cannot place a photo in, so it goes to the other, as a share it cannot take does, and when
  neither can take it the column is not counted at all, so the width is shared out among the
  columns that are rather than left as a strip at the right. Without this the assignment can never
  reach such a column, because a span only starts where both of its columns are free and a tie goes
  to the lower index, so a zone given an odd number puts every photo in its first pair and the last
  column is empty for the whole height of the grid. A zone capped at its photos cannot always use
  the space it is given, so this is the one place the share is bounded: `photosetColumnMaxWidth` is
  the widest a column is drawn at, twice the portrait width, and the width past it is left at the
  right rather than a column being made wider. A single photoset is not capped, so its columns keep
  using the whole space. The two counts are a pure function, `photoZoneColumnCounts`, for the same
  reason the assignment is one.

- The two zones are drawn side by side, portraits first, each starting at the top of the area,
  and each kind is packed inside its own columns. When the space cannot hold one column of both
  kinds — that is the least either can be given — the grid is not split at all and every photo is
  laid out as one grid with spans, as it was before. That is also what a single photoset does, and
  what a pack does when only one kind of photo is present.

- The block's column is the cap when the page's column is wider, and the page's column width when it
is narrower, so the cap only ever makes the block smaller. When what the row has left cannot hold
one column of the grid, the area is below the row at the whole width instead, and the space beside
the block is left empty: that is what a strict maximum costs at a narrow window. The alternative —
letting the block take the whole width when nothing else can use it — would make the cap depend on
the window, so it is not taken.

- A photo clearly wider than it is tall spans the number of columns the two widths give, because a
  landscape at one column width reads as a small tile rather than as a landscape. The line is a
  ratio of 1.2, which is 6:5, so the common 4:3, 3:2 and 16:9 are above it and a near—square is not:
  a near—square in two columns is only a square twice as wide. A span can only start where both of
  its columns are free, so it starts at the lower of the two and the other column keeps a gap until
  it is level. Filling that gap would mean putting a photo out of the order the source gives, which
  is the rule the section keeps, so the gaps are left: being efficient comes from the number of
  columns and from using the whole space, not from reordering. A span stays inside the columns of
  its own kind, so a tile is never drawn across the boundary between the two zones, and the same
  ratio is what decides which zone a photo is in — `isLandscape()` is the one line the drawing and
  the counts share. A photo whose header could not be read is the square the drawing lays it out as,
  and a square is a portrait.

- A grid needs each photo's ratio before it draws, so the layout reads the header — the same reader
  the scan uses, read synchronously for the same reason `ImagesStore.loadSync` exists: a widget lays
  out while it builds. A photo whose header cannot be read takes a square tile and is reported as
  the scan reports what it cannot take.

- The assignment is a pure function, so it is tested on its own: each photo goes to the columns that
  are highest up when it is placed, ties to the lower index, and the order is the order the source
  gives within a zone. It is asked once for each zone, so a photo is only ever placed in its own
  kind's columns (`ai/picking.md` §7). The heights are in pixels rather than relative, because a
  tile is its image plus the lines under it and those are a fixed height rather than a share of the
  column width, so the same photos can be laid out differently in a window of a different width. The
  assignment counts the lines the drawing reserves — the file name, and the line naming the set
  where the grid draws one — so the two agree on a tile's height.

- Each label line is one line, cut with an ellipsis when the text is longer than the width the
  tile is drawn at. The height the assignment reserves for a tile counts one line for each label, so
  a name that wrapped would make the tile taller than the box the grid sized for it, and the two
  have to agree on the height. It is the shared tile that does this, because the three sections that
  show these files the same way can all reach a narrow column. Only what is painted is cut, not the
  text: a tile whose label is cut still says the whole name to a test that looks for it.

- The block has a heading row, which is the title row a section titles itself with, and the list
  of sets has a header of its own below the rows the editor gave the block: the heading names the
  block, the header names the list. Only a pack has that header, because only a pack has a list — a
  single photoset has one set, and a header naming a list reads wrong for one item — so the strings
  are resolved per type, and the type without a list has null there and draws nothing. The header is
  not drawn above the placeholder that says the list is empty, because a header naming a list is not
  drawn above an empty one. It has no action: the buttons belong to the whole block, and they are in
  its heading row.

- The list also names the two columns its lines draw, as the two tables name theirs
  (`ai/video_pack.md` §5): a row above the first line, with the name and the pair of numbers, in the
  style a table header is drawn in. Each header sits where its column's values sit — the name at the
  left edge, the count at the right edge, where the numbers are — and the row has the lines'
  horizontal padding, so its text is above the values rather than beside them. The row is built the
  way a line is, so the two agree on where the columns are: the name cell takes the space the value
  cell does not need, and the widest thing in the count column is the header itself, because a count
  is a few digits. It is drawn only for the type that has a list, as the header naming the list is,
  and the words for the name are the ones the same feature's field label already has, because a name
  shown in a column is the same value the form's field names.

- The row fits on one line in both languages the app has, and that is measured rather than assumed:
  at the style a table header is drawn in, the two strings measure 182 px in English and 228 px in
  Russian, the longer of the two, against the 392 px inside the padding at the width this feature
  caps the block at. So it is one line at every width the page builds a column at, and it would wrap
  only on a block narrower than 236 px, which the page never builds. Nothing is cut: a name in the
  list wraps rather than being cut, as it always does.

- Every other line of the list is tinted, because a list read as bands of text is followed with the
  eye — the same rule the Video pack section follows (`ai/video_pack.md` §5), with the same vertical
  padding that makes a tinted line read as a band rather than as a line of text with a colour behind
  it. The horizontal padding is this list's own, 4 px, so a name or a count is not drawn against the
  edge of the band it is on; the tables have none, so this is the one place the two shapes differ,
  and it is a difference inside a line, never in how wide a band is. The parity is the position in
  the order the items are stored, so a re-scan of the same folder does not change a line's colour.
  The header naming the list and the row naming the columns are not lines, so neither is tinted. The
  band is the line's, not the set's: the photos of a set are what the grid shows, and a band round
  them would be a band around a set rather than a line of the list. The tint is on the line's own
  `Material`, as the table rows' are, so a line is the same shape whether or not it is tinted and
  keeps a hover highlight if it ever becomes clickable — a plain container paints its colour over
  the highlight, which is painted on the canvas of the nearest `Material` ancestor. Nothing in this
  list is clickable today, so the reason is the shape the tables have, not a highlight the list
  shows.

- The line naming a set shows two numbers, `picked / total`: what the rule picked for that set,
  and what the scan counted for it. Before a pick the first number is 0, because nothing has been
  picked and the feature shows what is on disk. The second is the value the scan wrote for the item,
  kept as the model stores it, so a count a user edited in `release.json` is shown as it is — the
  same rule as the size field showing a value it cannot format.

- A set with no photos shows its count in the block and is reported, as the scan reports what it
cannot take, and the rule gives it nothing. It is shown rather than left out, because the list is what
the scan found. With no grouping there is no column for such a set to take: the grid has nothing for
it, and it is only the line in the block.

Since the rule no longer gives a photo to every set that has photos, a line showing 0 picked after a
run is not one message: it is a set the scan could not read, or a set the chosen count did not reach —
a share below one photo under strategy one, no position inside it under strategy two. The line says the
same number for both, because the number it shows is the records that exist, and which of the two it
is is not something the block knows.

- Re—picking writes the same names, so the feature needs the cache eviction and a key that changes
  on each run, as `AGENTS.md` §5 requires. This is the case the poster does not have and the picked
  photos do. Eviction alone is not enough: the widget that shows a picture resolves its provider
  once, and the key is the file path, so a picture written under the same name is shown as the one
  decoded the first time. So the block records what its run wrote and the tiles are keyed with a
  generation that moves on each run, and the area that draws them must build again — which it does
  only when the editor does, because the generation cannot be the block's own counter when the
  pictures are in another widget.

- The picked photos are `kind: photo` records with `item` set to the set's path, so the Upload
  section's progress bars count them unchanged.
