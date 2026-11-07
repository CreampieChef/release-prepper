## 7. The block and the photo area

The Photoset feature is the extended section, not a new section. There is no slider: the number is
decided by the rule, and the feature shows what it decided rather than letting the user change it.

For a pack it is two widgets, because it is in two grid cells. The block is the page's second
column, at the most the width this feature gives it: its heading with the Scan and Pick buttons at
its right, the rows the editor gives it, and the line naming each set the scan found. What the row
has left after the fields' column and the block's column is the photo area. One widget cannot be two
cells, so the two are two widgets, and what they have to share — the controller, and the generation
the pictures are keyed with — is held by the editor, the widget that places them (`AGENTS.md` §5).
The sections that need a column's width — the Upload section, the Message section, the draft — stay
stacked below the fields in the fields' column, because the block's column is too narrow for their
rows. A single photoset has no space beside its block for its pictures, so there is no area beside
it: its block is the whole feature and draws the photos with the same grid the pack uses
(`ai/single_photoset.md` §7).

- Scan and Pick are two buttons in the block's heading row. Pick is disabled until a scan has run,
  because the rule reads the counts.

- Pick computes the picks and copies them in one step. There is no preview of the rule before the
  files are written: the feature shows what is on disk, as the Screenshots section does.

- The picked photos are one grid, not one column per set: every photo the rule picked, in the order
the source gives the sets and, within a set, the order it gives the photos. Nothing groups them, so
each tile says which set its photo is from as well as its file name. The line naming the set is
drawn only where the grid mixes sets, which is the pack's; a single photoset has one set, which its
block names above the photos, so its tiles keep the file name alone. The message still groups them
by set (`ai/photoset_pack.md` §7), because that is a list rather than a grid.

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

- The grid is the same for both types, at the three numbers `photoset_group.dart` gives it: as many
columns of `photosetColumnWidth` as fit in the space the area is given, and what those columns
cannot use is shared out rather than left as a strip at the right, so a column is that width or a
little more. A landscape takes the number of those columns that makes it `photosetLandscapeWidth`
wide, worked out by `photoSpanCount`, because a grid can only be a whole number of columns wide. The
columns have no gap of their own, because a spanned column must be exactly as many of them as the
two numbers say: the space between two tiles is the padding inside them. The block's column is at
most `photosetBlockMaxWidth`, and the width it does not use is the area's, so the cap does not leave
an empty strip beside the block. The fitting is in `lib/service/images/masonry.dart` with the rest
of the placement.

- The block's column is the cap when the page's column is wider, and the page's column width when it
is narrower, so the cap only ever makes the block smaller. When what the row has left cannot hold
one column of the grid, the area is below the row at the whole width instead, and the space beside
the block is left empty: that is what a strict maximum costs at a narrow window. The alternative —
letting the block take the whole width when nothing else can use it — would make the cap depend on
the window, so it is not taken.

- A photo clearly wider than it is tall spans the number of columns the two widths give, because a
landscape at one column width reads as a small tile rather than as a landscape. The line is a ratio
of 1.2, which is 6:5, so the common 4:3, 3:2 and 16:9 are above it and a near—square is not: a
near—square in two columns is only a square twice as wide. A span can only start where both of its
columns are free, so it starts at the lower of the two and the other column keeps a gap until it is
level. Filling that gap would mean putting a photo out of the order the source gives, which is the
rule the section keeps, so the gaps are left: being efficient comes from the number of columns and
from using the whole space, not from reordering.

- A grid needs each photo's ratio before it draws, so the layout reads the header — the same reader
  the scan uses, read synchronously for the same reason `ImagesStore.loadSync` exists: a widget lays
  out while it builds. A photo whose header cannot be read takes a square tile and is reported as
  the scan reports what it cannot take.

- The assignment is a pure function, so it is tested on its own: each photo goes to the columns that
are highest up when it is placed, ties to the lower index, and the order is the order the source
gives. The heights are in pixels rather than relative, because a tile is its image plus the lines
under it and those are a fixed height rather than a share of the column width, so the same photos
can be laid out differently in a window of a different width. The assignment counts the lines the
drawing reserves — the file name, and the line naming the set where the grid draws one — so the two
agree on a tile's height.

- The picked number in a row comes from the records that exist, so it appears only after a pick: the
  feature shows what is on disk.

- A set with no photos shows its count in the block and is reported. Since the rule gives at least
one photo to every set that has photos, a set shown with none is one the app could not read, which
is the information that says it will not be in the post, so it is shown rather than left out. With
no grouping there is no column for such a set to take: the grid has nothing for it, and it is only
the line in the block.

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
