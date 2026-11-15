# Posting a topic with the torrent attached

The third part of the PornoLab feature. `ai/uploading_draft.md` stops at the
draft: the app saves the title and the message and does not publish anything.
Posting is what makes the topic, and it is the part that carries the torrent.

Nothing here is implemented. What follows is a record of one real upload — three
requests made in a browser on 2026-11-07, kept as HAR entries under
`temp/upload_requests/` (gitignored) — and the rules a feature built from it has
to follow. §2 is the recording; the rules after it are decisions, and §12 is
what the recording does not answer.

The values that identify the account and this upload are replaced with fakes,
and the stub in `testing-tools/pornolab-stub/` answers with the same ones, so
an example here and an answer from the stub read the same:

```
topic id      3000111
user id       40000111
name          stubuser
announce key  stubkey
```

The forum id 1857 and the draft id 11818 are kept as the recording has them,
because they name the place rather than the account.

## 1. What this is

Three things make this feature different from the one the app has:

- it publishes. The draft feature says plainly that nothing on the site becomes
  public through it (`ai/uploading_draft.md` §1). A post does, so this is the
  first feature of the app whose result the user cannot take back;
- it sends a file. Every request the app makes today is a form body or a JSON
  body; this one is `multipart/form-data` with a part that is the .torrent;
- its answer is a page read for a value the app did not choose. The page the
  token comes from is already read for a value, so the pattern exists, but the
  value there belongs to the app's session and this one is an id the site made.

The app cannot know that id before the post, which is why the form sends `t` as
0: the form says the submission makes a topic rather than changes one.

## 2. The recording

Three requests, in the order they were made. They are one submission, not three
independent calls: the first gives the token and draws the form, the second is
the submission, the third is the file the site made from it.

1. `GET posting.php?mode=newtopic&f=1857&draft=11818` — 200, `text/html;
   charset=windows-1251`. The page the draft is opened in: the form, the
   `form_token`, the account name, and the file field. The answer set `bb_data`
   again: the same value with one of its fields replaced by the time of the
   again: the same value with one of its fields replaced by the time of the page
   view, and a year's expiry. The app keeps the value a login gave it rather
   than the one a page rewrote, because it has no cookie jar
   (`ai/pornolab_login.md` §5); whether the site still accepts a value it has
   rotated is §12.
2. `POST posting.php` — `multipart/form-data`, the form as a browser sent it
   (§3), 200, `text/html; charset=windows-1251`. The answer is the page §5
   describes. It set no cookie: a post does not renew the session the way the
   page view before it did.
3. `GET dl.php?t=3000111` — 200, `application/x-bittorrent;
   name="[pornolab.net].t3000111.torrent"`, served as an attachment. The file §6
   describes.

The download carried the cookie, as the other two did, and carried `bb_dl`: the
page's own script sets that cookie when a download link is pressed, with the
topic id as its value, and the answer clears it. §6 says what that means for the
app.

## 3. The form

The body the browser sent is the page's form, in the order the page lays the
form out. The parts, in that order:

```
mode          newtopic
f             1857
t             0
p             0
draft_id      11818
subject       the title
topic_tags    empty
fontFace      -1
codeColor     black
codeSize      12
align         -1
codeUrl       empty
message       the message
MAX_FILE_SIZE 1048576
attach        the file
post          1
decflag       2
form_token    the token
```

The first five are the page's hidden fields: the mode, the forum, the topic and
the post this form is for — 0 for both, because the submission makes a topic
rather than changes one — and the draft the form was filled from. `subject` and
`message` are the contents of `title.txt` and `message.txt`, the same two files
the draft feature reads (`ai/description_template.md`), and `post` is the form's
hidden submit field.

Seven of the parts are the page's own state rather than data the app chose.
`topic_tags` is the form's tags field, which the message already contains.
`fontFace`, `codeColor`, `codeSize`, `align` and `codeUrl` are the BBCode
panel's controls, and `decflag` is the keyboard-layout select on the same panel:
its value is the layout the user had chosen, not something a submission needs.
`MAX_FILE_SIZE` is the limit the page declares for the file part. The app has
none of these, so it sends the fields it has and nothing for the ones it does
not have; whether the site wants a value for them is §12.

The file field is part of the form only after the page's script copies it there:
the HTML has it outside the form, and the order of a body is the order the DOM
was in at the moment of the submission, which is why the file part falls between
the message and `post`. The app builds the body, so the part is there by
definition; the order is kept as the recording has it, so that a request to the
site and a request to the stub are the same shape.

The length of the body is declared, as a browser declares it. A server that is
not a browser reads that header rather than the body, so a form sent without it
is a chunked body, which is a shape neither the recording nor the app has a rule
for: a run against the stub could not read one, and the client read the write
failing instead of an answer.

What the page says about the file part is the rule the app works inside: the
maximum is 1 MB, and the accepted extensions are `.torrent`, `.zip` and `.rar`.
A .torrent for one video is tens of kilobytes, so a single file is not a
problem; a pack is a different size of file, and a piece list long enough to
pass 1 MB is possible (§12). The page also says a file can be attached only with
the message, never with a preview: a preview with a file chosen asks whether to
drop it.

## 4. The character set

The form declares no charset, so the browser sent the values in the page's: the
recorded body is Windows-1251, and the Cyrillic in it reads correctly when the
bytes are taken as that codepage. The app's rule for a body it builds is UTF-8
(`ai/uploading_draft.md` §6); its rule for a form it is filling is the page's
charset, because there it is reproducing what a browser sends
(`ai/pornolab_login.md` §4). A post is a form the app is filling, so the values
go in Windows-1251, and a character the codepage has no byte for is sent as its
UTF-8 bytes, as that document states for the login.

The two rules cannot both hold for the same field: the draft feature sends the
title and the message as UTF-8 to `ajax.php`, and this feature sends the same
two values in the page's charset. The recording does not decide which the site
reads, because the call that made the draft is not in it, and the draft came
back on the page as correct text either way. The rule above is taken because the
app is reproducing a form, not because the site was observed to prefer one
encoding; the question stays in §12.

The answer is read in the charset the answer declares, as the app already does
(`ai/uploading_draft.md` §6).

## 5. The answer

The answer is a page, not JSON, and the result of the request is the block
titled Information (Информация): the torrent was registered on the tracker, the
user is told to download it and put it for seeding in the same folder the
original files are in, and that it must be the file downloaded from the tracker
rather than the one they created. Then three links — back to the topic, back to
the forum, back to the front page.

The block is the whole result, and it carries the id twice, as the download link
and as the topic link:

```html
<table class="forumline message">
  <tr><th>Информация</th></tr>
  <tr><td>
    Торрент зарегистрирован на трекере<br /><br />
    Теперь вам <a class="dl-stub" href="dl.php?t=3000111">нужно его скачать</a>
    ...
    <p class="mrg_10"><a href="viewtopic.php?t=3000111">Вернуться в тему</a></p>
    <p class="mrg_10"><a href="viewforum.php?f=1857">Вернуться в форум</a></p>
  </td></tr>
</table>
```

The app reads the id from the block — the first `t` in it, which both links
carry — and builds the topic link from the site address the client holds, the
same rule as the draft link (`PornolabClient.draftUrl`, `StashClient.siteBase`).
The id is stored as `topicUrl`, next to `draftUrl`: it is what a run read rather
than what the user wrote, and it is a new key in `release.json`, so this is a
format change rather than a field added to a field list as `parentForum` was
(`ai/uploading_draft.md` §4). The path the run wrote is stored as
`trackerTorrentFile`, the fourth name the feature stores (§6), and both go
through the editor's single write path, because both are what a run produced.

Two things about the shape matter. The status is 200 for a post that worked, and
200 is also what an answer the app cannot name yet looks like, so the block is
what a result is read from and not the status alone: a 200 with no block is one
result until such an answer is seen (§12). And an answer like this cannot say
which of two things it refused — the form signature or the values — because the
JSON shape the draft call has for a refused token (`ai/uploading_draft.md` §7)
does not exist here, so a refused form and a page the app cannot read are one
result.

A run cannot be repeated without a consequence, and this is the feature where
that first becomes real. A second post makes a second topic; the app has no way
to take a posted topic back, and the page's own warning says an attached torrent
may not be deleted once its status is anything other than unverified, up to a
ban for doing it. So the app asks before it posts, the same shape the Torrent
section uses for a flag change (`ai/torrents.md`), and a run is made only on the
answer: a dismissed popup is not an agreement. The app does not post twice for a
release that already has a stored topic link, because the second post would be a
second topic for the same text, and the action is not offered for a release with
no draft link, because a post is made from a draft.

The popup names the two values the post is made from: the forum it goes to and
the title it carries. Those are the values the user may have changed since the
last run, and a decision about something that cannot be taken back is a decision
about them — the forum by the name `ai/uploading_draft.md` §4 says the row
shows, and the title by what the Message section holds. The popup is capped at
1000 px, as the Stash popup is (`ai/doc.md` §3): a dialog given no constraints
of its own is limited only by the screen, so a title longer than the cap makes
the popup as wide as the window rather than a block of lines.

The checkbox is what makes the answer an agreement, and its words are the user's
own statement rather than the app's: that the draft has been verified and is to
be uploaded unchanged, and that the post cannot be taken back. Its confirm is
not a button until the box is checked, so a press of it cannot be a slip, and a
dismissed popup stays not an agreement. This is the app's first action whose
result cannot be taken back, which is why the answer is asked for as an
agreement rather than as a click.

## 6. The file the tracker serves back

The file `dl.php` gives is not the file that was sent. The `info` dictionary is
byte for byte what the form carried, and four keys are added at the top of the
file: `announce`, `comment`, `publisher` and `publisher-url`. They come out in
sorted order, which is what an encoder that reads a file and writes it again
produces, so the site takes the file apart, adds fields of its own, and encodes
it again. The added ones name the announce line, the topic the file belongs to,
and the site.

The announce line carries a key, and the key is the one the tracker knows the
account by — `stubkey` here. That is why the page says the file to seed must be
the one downloaded from the tracker: the file the app wrote has no announce at
all, so a client seeding it announces to nothing. The app has no way to know the
key without asking the site for the file, and the file it gets is for the
account whose session asked — the same file downloaded through another session
is a different file. The last half of that is an inference from the key being in
the answer rather than in what was sent, and it is the whole reason this feature
cannot stop at the post.

So a run does not end at the answer. It downloads the tracker's copy and writes
it in the app's own folder inside the release, `_rp_torrent/`, under the name
the site gives it: `[pornolab.net].t3000111.torrent`. The folder is the app's
own, so it carries the app's prefix as the app's files inside a release do, and
it is created before the first file goes into it, as the log's folder is.

The file on disk is the thing that says a post happened, and the path it was
written at is recorded as `trackerTorrentFile`, relative to the release
directory, which is the shape `release.json` records a path inside a release as
(`ai/release_structure.md` §2). Only a run that wrote a file records one: a run
that made the topic and failed at the file wrote nothing. This is the exception
to the rule `ai/torrents.md` states, that nothing is recorded for a run's
output — what a run read is what is stored, and for a post that is the link.
The path is recorded as well because a release opened again cannot otherwise say
which file the post wrote, and because the editor's heading opens that file and
its folder by the name the record holds (§11).

The file that was sent is kept: nothing in the app deletes a file. So a release
that has been posted holds two `.torrent` files, the one its own run wrote under
the release name and the tracker's copy named by the topic id, and the path the
Torrent section shows is still the first. That is what `ai/torrents.md` says a
release holds after a post. The two names, and the folder the second is written
in, are read through one rule, `lib/service/torrent/torrent_path.dart`, because
the app writes one of them and sends the other: a feature naming the same path a
second time would be a second rule, and a controller asking another controller
for it is the dependency rule 3 avoids. The flag rule is not affected — the flag
was sent in the file, and the served file keeps it.

The download is a call for the account: the recorded one carried the cookie, and
the answer's key is the account's. It also carried `bb_dl` — the cookie the
page's script sets when a download link is pressed, with the topic id as its
value, which the answer cleared. The app has no cookie jar and cannot set a
cookie, so a download it makes is not attributed to a topic; whether the site
records such a download at all is §12.

## 7. The run

The gates are the draft feature's, in the order the section can act on them: the
message, then a stored cookie, then the forum, then a torrent to send
(`ai/uploading_draft.md` §5). A post is not made for a release with no file,
because the file is the point of this feature, and the gate stays a synchronous
read, as the other one is.

The run is three calls: the page the token comes from, the form, the download. A
cached token is used when there is one, a run told the token was wrong drops the
cache, and a run does not make a login and does not retry
(`ai/pornolab_login.md` §7). The last two calls cannot be reordered: there is no
id before the form is answered, so the download cannot be asked for earlier. A
run cannot be stopped, as no other network feature can.

What the app has for the second call is the form rather than a body it invents:
the fields it has and the file, in the order §3 lists them, in the page's
charset. The file it sends is the one its own run wrote (`ai/torrents.md`), so a
post is not made before a run has produced a file to carry.

The file is written by another feature's run, and the gate is read while the
section builds, so a file that appears is not something this section can see
without building again. The run that makes it ends by telling the editor, which
is what builds the section again — the same path an upload run ends with for
what it wrote to `images.json` (`ai/uploading_draft.md` §5, `ai/torrents.md`).
Only a run that wrote a file says so, because the notice says what a run wrote
rather than that one happened.

## 8. Results

The client returns typed results and the widget maps them to localized text
(rule 13), reading the mapping the settings row shares where a result is the
same (`ai/pornolab_login.md` §8). The cases this feature adds:

- posted — the topic id, and the link built from it;
- the file written after it, or not written. The two are said apart, because the
  topic exists either way and the user needs to know which of the two the
  release has; the file is named by the path it was written at rather than by
  its name, because that is the path the record holds and a name alone would
  not say which folder the file is in; the same path is named for a run that
  wrote no file, because it is the path that run would have written the file
  at;
- no message, no cookie, no forum, or no file to send: the checks made before
  the run, the same rules the button is gated on, so a run is not reached with a
  value they refuse;
- the cookie refused — the page the token comes from answered with the redirect
  to the login page (§2);
- a form the site did not accept, and an answer that is 200 but is not the block
  §5 describes: one result, because a page like this cannot say which of the two
  it refused;
- a file the site did not accept — over the limit the form declares, or not one
  of the extensions: one result until such an answer is seen;
- no connection, or an answer that is not 200;
- stopped by the timeout.

The word for a post that worked is not in that set, because a run has nothing to
show for one beyond the link, as `ai/pornolab_login.md` §8 says for a login. The
section shows the link, and the link is the result.

## 9. Logging

The same rules as every other call (`ai/uploading_draft.md` §8,
`ai/pornolab_login.md` §9): one entry per request and one per response, the tool
field `pornolab`, the cookie as the redacted marker, the headers that carry a
credential left out, and no page recorded in full.

What this feature adds is a file, and a part of a form is not a field, so an
entry does not hold its bytes: it holds the name the part was given with and its
size, which is what a problem with a file is read back from. The form fields of
the POST are recorded as values, as a form body is. The response entry holds the
status and the id the app read, as the entry for the page the token comes from
holds the token the app read. The entry for the download holds the status and
the name the file came with, because the name is the id and the size is what
says the file is there.

Alongside that, the same calls can be written as plain text for a run that was
started with `--unsafe-verbose-tracker-logging` — the two things
`ai/uploading_draft.md` §8 keeps as markers, which is what a problem with an
encoding or with a field the site wants is read back from. A run without the
flag writes nothing, so this is what a run that was started to be read writes. A
file part is recorded there as its name and its size, as here.

## 10. Testing, and the stub

Nothing in the app's tests reaches the network, so the client stays behind an
interface and the parse and the rules are what the tests exercise
(`ai/uploading_draft.md` §9). What the tests hold here are the shapes the
recording gives, trimmed the way the example page is (`ai/uploading_draft.md`
§9): the block with its two links, and the page with the token assignment and
nothing else. What they cover:

- the form body: the parts in the order §3 lists them, the file part with its
  name and its content type, and a value encoded as the page's charset;
- the id read from the block, both as the page writes the link and as a path;
- the path the served file is written at, as the rule in
  `lib/service/torrent/torrent_path.dart` names it;
- the gate order, and a run with no file to send not being made, and a file
  outside what the form declares being refused before the request;
- the run that wrote a file telling the editor, as that is what builds the
  section the gate reads the file in, and a run that wrote none telling nothing;
- the log's line for a file part: the name and the size, never the bytes, as
  the app's log records it and as the plain text copy records it;
- the results mapped to text;
- the served file being written in the app's folder under the name the site
  gives it, the result carrying the path in the shape the record holds it as,
  and a download or a write that fails answering as the file not being written
  rather than as the run failing;
- the values a run that wrote a file applies: the link and the path, both
  through the editor's write path, and a run that wrote no file applying only
  the link, because a run that failed at the file wrote nothing;
- the publish action not being offered for a release with no draft link or for
  one that already has a topic, its confirm being gated by the checkbox, the
  words that checkbox says, a popup that is dismissed not being an agreement,
  and the popup being capped at 1000 px so a title longer than the cap does not
  make it as wide as the window;
- the base the app was started with, and a run being made to that base rather
  than to the site, as the same value is what the links are built from;
- the length the form declares, as the length of the body it is built from, and
  the text log's line for it;
- the page a forum name is read from being asked for at that base, so a run
  against the stub shows the name that page carries.

The stub (`testing-tools/pornolab-stub/`) is for a run made against a real HTTP
server, and the app can be pointed at it: `--dev-tracker-stub` is what points it
there. The base the requests and the links are built from is the address the
stub serves on — `http://localhost:40002`, the port the script defaults to —
when the app was started with the flag, and the site's address otherwise. One
value, because a run and the link it shows have to agree: the link built from
the site for a topic the stub made is not the topic the app made. The flag is
read once by `main()` before the app is built, as the flag that chooses the mock
hosters is (`ai/upload_images.md`), and it is the second of the three top-level
variables in the app — the second exception to rule 10 — because no part of the
app is the place that decides an address.

The two flags choose different things, so a run can use the mock hosters and the
real site, or the stub and the real hosters. The port is not a rule of the app:
it is the stub's, so the flag names no port and the app uses the one the stub
serves on.

What the stub answers is the post and the page a forum name is read from. The
page is asked for at the same base the post requests are made to, so a run
against the stub shows the name that page carries, and that name is the stub's
own wording, because the recording has no forum page (`ai/uploading_draft.md`
§4).

What the stub does not answer is what a run against it does not cover: the login
and the call that saves a draft. A post is made with a cookie the app already
has, because it does not make a login by itself (`ai/pornolab_login.md` §7), so
a post can be made against the stub with the cookie a real login stored; a run
that asks for the login, or that saves a draft, is answered as the stub answers
anything it is not asked about. The test photo hoster has the same problem and
answers it the other way, because a hoster is a list rather than an address.

A request the stub is not asked about is still read, because the body is read
before the answer is written. A run is several calls on one connection, and a
call answered without its body being read puts the calls after it out of step:
the client is told a response came without a request, and the rest of the run
reads as an answer to the wrong request.

The stub answers the requests a post is made of as the recording shows them, and
the forum page with the shape the rule reads and its own words, and it is
stateful in the one way the recording shows the site being stateful: it keeps
the file a POST gives it, and answers `dl.php` for the topic it made with that
file, re-encoded with the four keys added. A stub that answered with a file it
had not been given would not be the thing this feature needs to be tested
against, because the file that comes back is what the feature writes.

What the stub is not. A test that asserts one of these is asserting the stub
rather than the site:

- the ids it assigns are its own, starting at 3000111 so the first answer is the
  one §5 shows;
- the error shapes are the stub's, because the recording has no failure;
- the words a forum page carries are the stub's, because the recording has no
  forum page. Its shape is not the stub's either: a run against the site showed
  the page writing the breadcrumb as a table cell with the `nav` class, which is
  what the rule reads (`ai/uploading_draft.md` §4), and the stub writes the page
  in that shape;
- the key is the constant `stubkey` and the name it writes pages with is
  `stubuser`;
- the redirect for a request with no cookie is the behaviour
  `ai/uploading_draft.md` §6 states, not something this recording observed;
- the pages it writes are its own, with the block's wording as the recording has
  it. The BBCode panel and the keyboard select are not drawn, because the stub
  is not a browser.

What it stores is `posted/<topic id>.torrent` beside the script, gitignored like
the other tools produce. Its own rules are in the `README.md` next to it, as the
tools run by hand have.

## 11. Where it would sit

No new feature files for the post itself: this is the feature
`ai/uploading_draft.md` §10 describes, with a second action, two service files,
and three buttons added to a widget the feature already names. The measurement
the heading row needs is the shared helper `lib/feature/text_width.dart`,
because the settings page measures the same thing for its rows (`ai/doc.md` §3).

- `lib/service/network/pornolab_client.dart` — the method that sends the form
  with a file, and the rules on the interface: the form as §3 lists it, a value
  encoded as the page's charset, the id read from the block, and the name read
  from the page the field's value points at. The path the served file is written
  at is not a rule on the client: it is the path rule in `torrent_path.dart`
  below, and the result carries that path in the shape the format records it as.
  The interface reads a JSON answer today; this is a second kind of answer, so
  the client gains it rather than changing the first. The base the requests and
  the links are built from is the client's rule as well (§10), so a test asserts
  it through the links and through the calls a run makes. A name is asked for at
  that base, not at the host a value names, so a run against the stub shows the
  name the stub's page carries.
- `lib/main.dart` — reads `--dev-tracker-stub` before the app is built, as it
  reads the flag that chooses the mock hosters. The base is the client's rule,
  so the flag is not passed anywhere: no part of the app is the place that
  decides an address, which is why the flag is the exception rule 10 records.
- `lib/service/torrent/torrent_path.dart` — the name the app writes a release's
  torrent under, the same file when it is already there, and the folder the
  tracker's copy is written in with the path it is written at in it, so that the
  feature that writes the file and the feature that sends it read one rule (§6).
- `lib/service/logging/debug_text_log.dart` — the plain text copy of the same
  calls (`ai/uploading_draft.md` §8), written only for a run started with
  `--unsafe-verbose-tracker-logging`. Its own service so that whether anything
  is written is one place and the call sites stay with the client that makes the
  calls, and the flag it reads is the third exception to rule 10.
- `lib/feature/draft/draft_controller.dart` — the gates extended with the file,
  and the two runs.
- `lib/feature/draft/draft_section.dart` — the post as the section's second
  action, the popup asked before it, the label the row shows, and the words for
  the results.
- `lib/feature/pornolab_results.dart` — the words for what a post ended with,
  read from the same mapping the settings row uses.
- `lib/feature/release/release_fields.dart` — `topicUrl` and
  `trackerTorrentFile` as names the feature stores; the other two are unchanged.
  `trackerTorrentFile` is the one name in a field list whose value is a path,
  and its flags are the same as the other three names: no row the form builds,
  not required, not read by a template, not copied by a clone, because it is
  what a run wrote rather than what the user typed. It has no label, because
  nothing shows it as a field: the two buttons the editor's heading has are what
  read it.
- `lib/feature/release/release_editor.dart` and its controller — the three
  buttons the heading row has at its right edge: the link the record holds, the
  path it holds joined with the release directory, and the folder that path is
  in. Each is drawn disabled while the record has no value for it, and a
  failed open is said in a snackbar, because the heading is the page's title
  and has no body to say an outcome in. The path is opened through
  `PathOpener`, the service the Torrent section already uses
  (`ai/torrents.md`), and the link through `UrlOpener`, the one the draft
  section already uses.
- `lib/service/torrent/torrent_file.dart` — unchanged: the app writes the served
  file and does not read it, so the bencode read is not what a post needs.

The section is the same section, because a post is the second half of the same
feature and the field it acts on — `parentForum` — is already its row
(`ai/uploading_draft.md` §4). A tracker the app has no rule for shows no
section, as the draft feature says, and the image folder type stays outside this
feature for the same reason it is outside the draft: it has no title to send.

No native tool is called, so the System Check page does not change: `mkbrr` is
called by the run that makes the file a post carries, which is already reported.

## 12. Open questions

- Whether the site reads a form body as Windows-1251 or as UTF-8 (§4), and which
  one the app should use for the two values the draft feature already sends as
  UTF-8. As the rules stand, the two features would send the same text in two
  ways.
- Whether the fields §3 names as the page's state are needed by the site. The
  recording has them because a browser sends the form as it is, and an app that
  sends only the fields it has may be answered differently.
- Whether a post can be made without a file. The form allows it and the app does
  not; for a tracker whose releases are torrents a topic with no file is not a
  release, but that is a rule of the site the recording does not show.
- Whether the name of the file part matters to the site. The recorded name is
  not the app's (`ai/torrents.md`), and the site names the stored file by the
  topic id, so the name sent may be nothing more than what a browser writes.
- Whether a .torrent can pass the 1 MB the form declares, and what the app does
  when it does. A piece list is 20 bytes per piece, so a large pack with a small
  piece length can be over it, and the app has no rule for a file a site
  refused.
- Whether a download made without the `bb_dl` cookie the page's script sets is
  recorded as a download by the site (§6).
- Whether the id has any other shape in the answer, and whether an answer that
  is not the block is a failure at all (§5).
- Whether the site still accepts a `bb_data` value it has rotated for an account
  (§2). The app keeps the value a login gave it, and a page view writes a new
  one.
- Whether `www.pornolab.net` should be accepted — the same question as
  `ai/uploading_draft.md` §11.
- Whether a run can be stopped. It cannot, as no other network feature can.
