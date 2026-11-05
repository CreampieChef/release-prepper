# Upload images

The Upload section is the part of the release editor that sends the release's
images to the photo hosters. It comes after the type's own section — the
Screenshots section for a single video — and before the Message section. With
room for four columns it is the fourth; otherwise it is below the type's section
in the same column, or below the form at the whole width for the types whose
section is a masonry.

## Hosters

The section lists the hosters with a checkbox each, every one checked at first.
The app has the four real ones — `fastpic.org`, `turboimagehost.com`,
`pixhost.to` and `postimages.org` — and, started with `--dev`, the two mock ones
instead (`rptest-a`, `rptest-b`), which call the Python test server
(`ai/bundled_native_tools.md`), so a development run does not upload to a real
hoster. Each is drawn with its icon, a PNG in `assets/icons/hosters/`; a mock
hoster has no icon asset, so it is drawn with the placeholder.

The selection is widget state and is not stored, so a session that is opened
again starts with every hoster checked.

A hoster whose script reads a credential cannot run without one. While that
value is empty its checkbox is inactive, with a tooltip saying where to set it:
Settings → Integration. A hoster that cannot run is not part of a run, so the
app never calls its script with an empty credential.

The name passed to `--server` is the `Server Name` from `Data/servers.xml`; the
label shown in the list may be shorter, but the value must be the exact name.

## What is uploaded

Every image recorded in `images.json`: the poster, the photos, the screenshots
and the screenlists. The poster is a record like the others, which is what lets
its URLs be stored. The video thumbnail is not a record, so it is not uploaded.

## The run

The Upload button is in the section's title row, at the right, because it is the
action of the section as a whole rather than of one hoster. Clicking it starts a
run.

* One image per tool call.
* One image at a time per hoster. Several hosters run at the same time.
* The app does not retry. The tool's built-in retries are used with their
  default values.
* A call that runs longer than 60 seconds is stopped and reported as a failure.
* A credential is passed through the environment variable
  `UPTOODA_HOSTER_API_KEY`, not as a command-line argument, and only for the
  hosters whose script reads one (`ai/bundled_native_tools.md`). Postimages is
  the only one, and the value is the one the Integration settings hold.

## Skipping

When the user runs again, an image already uploaded to a hoster is skipped. An
image that failed is tried again, as long as that hoster is selected. A hoster
that is not selected is never attempted. The work list is in the order
`images.json` lists the records, which is the order the file preserves.

Only successful uploads are stored, so a record with no entry for a hoster is
what the skip rule reads: it means that image has not been uploaded to that
hoster.

## Progress

A bar is drawn for every hoster in the list, whether or not it can run, and
shows the images that hoster has over the images the release has. A release with
no images shows an empty bar: it has none. The count next to the bar is the
count the release has, so a generation run that adds images changes it, and a
run with nothing left to do reads 0 / 0.

The state is read from `images.json` when the release is opened, so a release
with everything uploaded shows full bars before anything runs. A run continues
from that state rather than starting a new count, so a bar never moves
backwards: a release with 10 of 20 uploaded shows 50% when it is opened, and a
run that uploads 5 more ends at 75%.

The state is read again when something the section shows changes: a generation
run that adds images, or a poster that is written or removed. The poster is one
of the release's images and the widget that writes it is not this section, so
the editor — the widget that places both — is where they meet: the section
registers its rebuild with the editor, and a run of this section reports its own
end the same way, because it writes `images.json`.

Until the release has the poster and at least one image of the kind its type
produces, the section shows a placeholder saying what has to happen first
instead of the hoster list, because there is nothing it could upload. That is
also what makes it show the list when a poster arrives after the images the gate
requires, and the placeholder again when the poster is removed.

Per-image failures are not shown: a bar shows them by staying below full, and
the log is what a user reads. Only the cases where nothing can happen at all —
the tool is not in the bundle, or the manifest could not be written — get a
message, because a bar stuck at 0 with no explanation is not enough.

## Model

`ImageRecord` holds, per image, a map of hoster to URL type to URL:
`delete_url`, `direct_url`, `thumb_url`, `view_url`. bbcode is built from these,
not taken from the tool.

## Logging

Every interaction with uptooda is logged. The tool is run with `Process.start`,
so each output line is recorded as it arrives rather than at the end of the
call; `Process.run` would buffer everything until the process exits.

The log is `<release_dir>/logs/log_<first_log_date>.json`, one JSON object per
line, because entries are appended as they happen. A file is named after the
first entry it holds and every later entry goes into the same file. Writes are
serialised, since several hosters write at the same time and a JSON Lines file
cannot be appended to from two places at once.

There are two entry types. A line the tool wrote records the date it was
received, the tool called, the input — the arguments of the call, repeated on
every entry so each entry stands on its own — the stream it came from, `stdout`
or `stderr`, and the line. The end of a call is an entry of its own, with the
same fields plus the exit code and whether the call was stopped by the timeout;
an exit code is not an output line, so it cannot be a line entry. The code is
null for a call stopped by the timeout.

Progress lines use carriage returns as well as newlines. Entries are split on
newlines and the carriage returns are kept inside the recorded text.

`ToolRunner` writes the log. It is the only code that runs an external process,
and writing the log is one of its side effects, so the log is a required
constructor parameter.

## Open work

* How progress and per-image failures are presented. The first iteration shows
  them only through the bars and the log.
* Stopping a run in progress.
* The one-image-at-a-time-per-hoster rule, since some hosters accept more images
  at the same time.
* Storing the hoster selection.
* The log format.
