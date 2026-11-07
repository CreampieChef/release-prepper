# Picking photos from a pack

**Implemented.** The rule is `lib/service/photosets/photoset_picker.dart`; the writing is the
photosets controller and the showing is the photosets section (§7). `ai/photoset_pack.md` §6 is the
seam this fills, and `ai/doc.md` §7 was rewritten in the same change, as the project rule requires.

## 1. How many

The number of photos to pick is one curve:

```
N = min(total, clamp(ceil(5% × total), 5, 50))
```

- Below 100 photos the percentage is under 5, so the minimum shows: 5.
- Between 100 and 1000 the percentage shows.
- At 1000 or more the percentage reaches 50, so the cap shows.

The rule was described as three tiers, and they are the same curve at every point: at 100 the
percentage is 5, at 1000 it is 50. The curve is what the code should hold, because three branches
that agree everywhere are one rule written twice. `min(total, …)` is the case the tiers do not
cover: a pack of 3 photos cannot pick 5.

Every set that has photos gets at least one, whatever the pack size. That is a floor on the result,
not a share of its own: it only changes anything when a set's proportional share is below one, and
when it does the total passes 50. The point of the minimum is that the post shows every set, so a
cap cannot remove a set from the post.

So a pack of 20 sets picks at least 20, even though 5% of its photos is 5. The curve decides how
many, the minimum decides that no set is left out, and the minimum wins when the two disagree.

## 2. Which sets

N is divided across the sets in proportion to their size, by largest remainder:

1. Each set's share is `N × its size / total`. Its count is the floor of that share.
2. A set can never give more than it has, so a count is capped at the set's size.
3. The picks left over — from rounding, and from sets that could not give what their share asked
   for — go to the sets that can still take more, in order of the largest fractional part of their
   share, until the total is N.
4. Then a set that has photos but ended with nothing gets one, and the total grows by the number of
   such sets. This is where the total can pass 50.
5. A tie is broken by the order the source gives, so the same input gives the same output.

A set with no photos contributes nothing and is reported, as the scan reports what it cannot take.

Example, the pack it was described with — 5 sets, 1200 photos, sizes 300, 250, 200, 250, 200:

- N = min(1200, clamp(ceil(60), 5, 50)) = 50.
- Shares: 12.5, 10.42, 8.33, 10.42, 8.33. Floors: 12, 10, 8, 10, 8 = 48.
- The two remaining picks go to the largest fractional parts: the 300 set and the first 250 set.
- Result: 13, 11, 8, 10, 8 = 50. Every share is above one, so the minimum does not bind here.

The same pack with 60 sets of 20 photos each is the case where it does: N is 50, every share is
0.83, so 50 sets get one and 10 get none, and the 10 are given one each — 60 in total.

## 3. Which photos inside a set

Within a set the picked photos are evenly spaced across it, so the set is sampled from end to end
rather than taken from its start. Each pick is at the centre of its own interval: for a set of m
photos giving k picks, the pick positions are

```
floor((i + 0.5) × m / k)   for i = 0 … k−1
```

which is evenly spaced, stays inside the set for every k, and starts at the middle of the first
interval rather than at the first photo. For k = 1 it is the middle photo of the set, which is what
the rule asks for when a set appears in the post with a single photo.

The two things the rule was given as — evenly spaced, and around the middle — agree on this
definition: the interval centres cover the set from end to end, and the middle is where a set that
contributes one photo is sampled from.

The picked photos keep the order the source gives them. The picking chooses which photos, not what
order they are written in, so the records stay in the order the scan wrote them
(`ai/photoset_pack.md` §4).

## 4. What the rule reads

Counts only. The resolutions are fields the scan fills and the post shows; they do not decide which
photos are picked. So the picker needs the scan to have run, for the counts, and nothing else from
the scan.

The numbers — 5, 5%, 50 — are a posting convention for the tracker, not a property of the pack.
Whether they are constants in the code or values the tracker config holds is the same decision
`ai/photoset_pack.md` §7 already names as open. The rule itself does not change either way, so the
rule is written here as data: three numbers and a distribution method.

## 5. Where it lives

`lib/service/photosets/photoset_picker.dart`: a pure function that takes the scanned sets and
returns the picks. No UI, no `BuildContext` (rule 13), no writing — the controller copies what the
rule chose and records it, and the widget shows it. The seam `ai/photoset_pack.md` §6 defines is
unchanged: the selector takes the items and a rule and returns the photos it picks; this document is
the rule.

The rule is tested on its own, because its interesting cases are arithmetic rather than visual: a
pack below 100, a pack at exactly 100 and exactly 1000, a pack with more sets than the cap, a set
smaller than its share, a set with no photos, and that the same input gives the same output twice.

The three numbers are constants on the class. If the tracker config decision goes the other way they
become values the config holds; the rule itself does not change either way.

## 6. Left open

- Whether the app copies the picked photos into the release or uploads them from the source.
  `ai/release_structure.md` §4 says copy, and the code copies. The cost is disk space and a source
  that may be gone later. This is `ai/photoset_pack.md` §9 and is not decided here.
- Whether the numbers are constants or tracker config (§4).

What re-running the picker does is no longer open: with no override the rule is deterministic, so a
re-pick recomputes the same picks and replaces the records it writes. It only differs when the scan
changed.

## 7. The block and the photo area

The Photoset feature is the extended section, not a new section. There is no slider: the number is
decided by the rule, and the feature shows what it decided rather than letting the user change it.

For a pack it is two widgets, because it is in two grid cells. The block is the page's first column:
its heading with the Scan and Pick buttons at its right, the rows the editor gives it, and the line
naming each set the scan found. The photo area is the columns after the first. One widget cannot be
two cells, so the two are two widgets, and what they have to share — the controller, and the
generation the pictures are keyed with — is held by the editor, the widget that places them
(`AGENTS.md` §5). A single photoset has no columns to put its pictures in, so there is no area
beside it: its block is the whole feature and draws the photos itself at the whole width, as it
always did (`ai/single_photoset.md` §7).

- Scan and Pick are two buttons in the block's heading row. Pick is disabled until a scan has run,
  because the rule reads the counts.

- Pick computes the picks and copies them in one step. There is no preview of the rule before the
  files are written: the feature shows what is on disk, as the Screenshots section does.

- The picked photos are grouped per set, in the order the source gives them, matching how the
  message groups them (`ai/photoset_pack.md` §7). The file name under each tile stays as the
  existing card has it.

- The rows the block draws — the path the user picked and the counts the scan took from it — are
  built by the editor, because they are form rows. For a pack they belong to the block; every other
  type keeps them as rows of the form.

- For a pack the area is titled Screenshots, because what it shows is the pictures rather than the
  list of sets, and it uses the title the Screenshots section titles itself with, so the two areas
  that show the same files the same way say the same word. One column per set, the line naming the
  set at the top of the column and its photos stacked under that line. The same line is in the
  block, which is what lists the sets, so for a pack a set's line is drawn twice: once in the block
  and once above its column. For a single photoset the block's heading is the title and it draws the
  photos under its line.

- The word Photosets is the block's heading and the label of the count field it draws, so it is said
  twice for a pack, and the word Screenshots once, as the title of the area. Only one column of the
  page is titled by the editor (`ai/doc.md` §2).

- A pack's grid draws exactly the page's columns, because the minimum column width and the gap
  between columns are constants in `lib/service/images/masonry.dart` and the editor gives the grid
  the number of columns it counted. When the area is the whole width there are no page columns to
  name, so it is not given any and fits its own, as the masonry always has.

- Nothing spans in a pack's grid: a group is the width of its column whatever shape its photos are,
  because a group is what the user reads as one set. The masonry keeps its spans, where there are no
  groups: a photo clearly wider than it is tall spans two columns, because a landscape at one column
  width reads as a small tile rather than as a landscape. The line is a ratio of 1.2, which is 6:5,
  so the common 4:3, 3:2 and 16:9 are above it and a near—square is not: a near—square in two
  columns is only a square twice as wide. A span can only start where both of its columns are free,
  so it starts at the lower of the two and the other column keeps a gap until it is level. Filling
  that gap would mean putting a photo out of the order the source gives, which is the rule the
  section keeps, so the gaps are left.

- A grid needs each photo's ratio before it draws, so the layout reads the header — the same reader
  the scan uses, read synchronously for the same reason `ImagesStore.loadSync` exists: a widget lays
  out while it builds. A photo whose header cannot be read takes a square tile and is reported as
  the scan reports what it cannot take.

- Both assignments are pure functions, so they are tested on their own: each group or photo goes to
  the column that is highest up when it is placed, ties to the lower index, and the order inside a
  column is the order the source gives. A group is placed whole, so its height is what decides its
  column, and that height includes the gap after each tile — the same gap the drawing reserves, so
  the assignment and the drawing agree. The heights are in pixels rather than relative, because a
  tile is its image plus the name under it and the name is a fixed height, so the same photos can be
  laid out differently in a window of a different width.

- The picked number in a row comes from the records that exist, so it appears only after a pick: the
  feature shows what is on disk.

- A set with no photos shows its count with nothing under it and is reported. Since the rule gives
  at least one photo to every set that has photos, a set shown with none is one the app could not
  read, which is the information that says it will not be in the post, so it is shown rather than
  left out. In a pack's grid such a set still takes a column: its line is drawn on its own, because
  a column is a set and the scan found that set. A column with no group in it is not a column the
  grid has, so a grid never draws more columns than there are sets.

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

