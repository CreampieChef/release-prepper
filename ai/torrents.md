# Torrent

A new section called **Torrent** is added to the release editor, as the last
thing in the form's second column, under its fields, in every layout branch. It
is not tied to a release type: the tool takes a file or a folder, so the section
works for every type.

## What it does

The app calls `mkbrr create` on what the user picked — the source, which is a
file or a directory — and writes the torrent in the release folder.

```
mkbrr create <release.source> --private=true --output <release_dir>/<release_name>.torrent
```

The output name is the release name, not the source basename, so a torrent made
from a picked folder is named after the release. `--output` is passed explicitly
because the tool's default is `<source basename>.torrent` written in the working
directory, and `ToolRunner` does not set one (`ai/bundled_native_tools.md`).

The app passes no tracker, comment, or piece length. It does not retry.

The file is an output, not a record: nothing is written to `release.json` or
`images.json`, so the app keeps no state for it and a run writes over whatever
is there. Re-running is what a user expects after a file in the release changes.

## Progress

The run takes time, so the section shows the progress as it arrives. The tool
reports a percentage in segments separated by carriage returns, with ANSI colour
codes even when its output is not a terminal, so the reader takes one segment at
a time and reads the fields in it; a segment with no percentage is not progress.
The reading is the wrapper's, because it is the tool's format; `ToolRunner` is
given an optional `onOutput` callback and does not interpret what it passes on.

A segment is the redrawn line: the description, the percentage, the bar, and the
elapsed and remaining pair. The rate is in a bracket before the percentage and
only appears once the tool has a measurement; the time left is the second half
of the first bracket with a colon after the percentage. A colour code is an
opening bracket that nothing closes, so a field cannot be read across one. A
segment that is only the spaces the tool writes to clear the line has neither,
and the last line has no pair at all.

The tool hashes pieces from every file at once, so it never names a current
file: the only names it prints are the list of files before the first segment.
There is nothing to show there.

A run that finishes in a few milliseconds reports only the final 100, so the bar
cannot assume the numbers arrive in steps.

The bar is drawn only once a run has started: before a run there is nothing to
show. The progress and the outcome are widget state, because the app records
nothing for the torrent file and the section is the only place the run's outcome
exists.

## The section

Its title row has the **Create** button at the right, as every section's action
does. The button is disabled while a run is going: the tool cannot run twice on
the same output at the same time.

With no source picked there is nothing to hash, so the title row is drawn with
nothing on the right — the same row as one with an action — and the section says
what has to happen first instead: "Pick a file first" or "Pick a folder first".
Which of the two is the release type's rule (`FieldList.sourceKind` in
`lib/feature/release/release_fields.dart`), not something the section can know
on its own. What a file that is already there says is still shown, because
picking a source would not change it, so the placeholder is only what the
section says when it has nothing else to say.

The source is not state this section holds, and typing in the source row does
not rebuild the editor, so the section registers its rebuild with the editor —
the widget that owns that row — and the editor calls it when the row is written
to. A plain callback, not a listener (rule 3).

Below it the bar and the percentage, then the rate and the time left as two
labelled lines, then what the run ended with — the path written, or the reason
it did not. A line is drawn only when the tool reported that field. The outcome
is said in the section rather than in a snackbar, because the section is already
the thing that shows the run.

A release opened again can already have the file. The app records nothing for
it, so the file on disk is the only thing that says a run happened, and the
section says what it finds before any run. It is the file the app would write,
not any `.torrent` in the folder: one left under an older release name is not
the one this release would write, and a run would write over it. The check is
synchronous, because the widget asks while it builds, the same way the poster
box asks for its file.

Next to the path the section shows a link whose text is the release directory
itself — a path is data, not a string, so it needs no key of its own — and which
opens that folder in the file manager the OS uses. Flutter cannot do this on its
own, so this is the app's only use of `url_launcher`, behind `FolderOpener`
(`lib/service/launcher/folder_opener.dart`) as a provider entry with a typed
result; a failure is shown as a message rather than swallowed. The link is drawn
only when the section has a path to be next to.

The section has no dirty flag and is not part of Ctrl+S: it does not edit a
field.

## Results

The wrapper returns typed results and the widget maps them to localized text
(rule 13):

* ran and wrote the file — the path
* not in the bundle — the installation is incomplete
* exited with a non-zero code — the code, including the case where the source no
  longer exists
* timed out — the call ran past the 60 minute window the app gives a create call

The tool is on the System Check page as the fifth row, checked with the
`version` subcommand (`ai/bundled_native_tools.md`).

