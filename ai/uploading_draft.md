# Upload draft

The Upload draft section is the part of the release editor that saves the
generated title and message as a draft topic on PornoLab. It is the first
feature that talks to a site from Dart code rather than through a tool, so it
sets the shape the next one follows: a client behind an interface, typed
results, a credential in the Integration settings, and the log.

It is a PornoLab feature. A tracker the app has no rule for shows no section,
and the image folder type is not one of the types it covers, because that type
has no title to send.

## 1. What it does

The user fills the parent forum and presses Upload. The app:

1. GETs `https://pornolab.net/forum/posting.php?mode=newtopic&f=<FORUM_ID>`
   and reads the `form_token` from the response.
2. POSTs the title and the message to `https://pornolab.net/forum/ajax.php`.
3. Reads the draft id from the JSON response, builds the link to the draft,
   stores it as `draftUrl`, and shows it.

A second run updates the draft the app already made rather than making another
one, because the id it needs is read from the link it stored. A stored link with
no `draft` parameter — a `release.json` the user edited by hand — is read as no
draft, so that run makes one. A stored draft that has been deleted on the site is
one a run cannot update: the answer says so, and the run makes a new draft and
stores the link to it instead (§6).

The app does not publish the topic. It only saves a draft, so nothing on the
site becomes public through this feature.

## 2. The cookie

The cookie is not a field the page draws. It is what a login gives: the app
obtains it from the username and the password the Integration section has fields
for (`ai/pornolab_login.md`). It is stored under the key `pornolabCookie` in the
OS credential store, like the values the section does show, with the same
plain-storage fallback when that store cannot be reached. The value is the
`Cookie` header built from the `Set-Cookie` headers an answer gave, and the app
sends it as the `Cookie` header on the requests that need it.

Nothing was migrated from the field this section used to have: the key the
pasted value was stored under is not read any more.

The cookie is what makes the feature work, so a run that cannot be made is what
the section says rather than a run that fails, and the placeholder names the
first thing a run needs: the message, then a stored cookie, then the forum, the
same shape an inactive hoster checkbox has (`ai/upload_images.md`). The gate is
the cookie rather than the credentials, because the app does not make a login by
itself (`ai/pornolab_login.md` §7) and a run has nothing to send without one.

## 3. The user agent

Every request carries:

```
User-Agent: ReleasePrepper/0.0.1
```

built from `app_info.dart` — the app name and the version, the same values the
About popup shows — so the version in the header is the version the app is
running. The point is that a site can block a version it finds problems with,
which a generic client string does not allow. A product token is one word, so
the name is used here without the space its display name has.

No `Referer` is sent. The site accepts the header as it is written, so nothing
is sent in place of it.

## 4. The parent forum

`parentForum` is a field in the field lists of the four types the feature covers
— the single video, the two photoset types and the video pack — and not in the
image folder's. It is stored in `release.json` as any other field, so this is
not a format change.

Its row is the section's, not the form's, as `sceneUrl` is the Stash row's
(`ai/release_editor.md`): the field is where the section's action is, and the
user reads the row and the button together. `hasFormRow: false`, and the words
for the row are `parentForumLabel`, one of the names `fieldLabel` resolves.

The value is stored as the user wrote it. The app does not rebuild it into a
canonical form, because a forum URL is not one shape — a subsite forum, a
mirror, a URL with parameters — and the app cannot know which one the user
meant. The forum id is read from the `f` parameter when a request is made.

The shape rule, as `field_validation.dart` states it: an absolute URL, the host
`pornolab.net`, and `f` present as a positive integer. A bare id, a path without
the query, a URL without a host, or a host the app does not use is not accepted.
This is the `invalidForumUrl` kind, which is what the row shows and what a run
answers with when the value is not the shape.

The field is not part of the message's required set — no template reads it, so
writing it does not make a rendered message stale — and `isRequired` stays
false. The requirement is the section's own gate: the Upload button is disabled
while the field is empty, with a tooltip pointing at it, and the row shows the
shape rule as it stands, as the editor shows a problem on a row the user can
type into.

A clone copies the forum, because it is what the user typed, and not the link,
because the link is what a run wrote (`copiedByClone`).

## 5. The section

It is drawn below the Message section, in whatever space that section has: the
same column when the Message section is a column, the same whole width when it
is not (`ai/doc.md` §2). Its title row is `SectionTitle`, the title at the left
and the Upload button at the right, as every section's is. The title names the
tracker the draft goes to, because the app can talk to more than one.

What it shows:

- while nothing has been generated, the section is its title row — with no
  button, because nothing there can run — and the placeholder saying *Generate a
  message first*, the same shape the Screenshots section has when it has no
  images;
- once a message exists, the parent forum row, the Upload button, the outcome
  of the last run, and the link when the release has one. The outcome is said in
  the section rather than in a snackbar, because the section is already the
  thing that shows the run. The outcome is widget state; only the link is
  stored.

A run that updated the draft the stored link points at says nothing, because the
link is the result. A run that had to make a new one, because the stored draft
was deleted on the site, says so: the link the release holds changes through that
run, and the user cannot see why otherwise.

The placeholder names the first thing the section is missing, in the order the
section can act on it: the message, then a stored cookie, then the forum. The
login is one of these because the app does not make one by itself
(`ai/pornolab_login.md` §7), and the word for it names where to make it. The row
says the shape rule for the forum, so the tooltip names an empty field rather
than repeating the rule.

A link the release already has is shown even when the box has been reset, so the
placeholder is only what the section says when it has nothing else to say — the
rule the Torrent section uses (`ai/torrents.md`). A release whose message was
cleared still has a draft on the site, and the link that says so is not lost
because the box was reset.

The link is drawn with the label that says what it is, because its own text is
the link and a link is data. The label is the words of the field this section
owns, resolved through `fieldLabel` as the form's rows resolve theirs, and it is
drawn only when there is a link to label. Next to the link is the copy button,
the same call the Message section's copy buttons make, and it says nothing when
it works, as they do. The link opens the browser the OS uses through
`UrlOpener`, and a failure to open is shown as text rather than swallowed (rule
13).

The button is drawn only when there is something to send: a message exists, both
credentials are filled, and the forum is filled and its value passes the shape
rule. While a run is going the button is disabled.

The gate is a synchronous read, because the widget asks while it builds, the
same way `hasUploadableImages()` does. The credentials are read from
`SettingsController`, which the widget watches, so a login made from the
settings page changes what the gate says. The Message section is outside this
widget, so the section registers its rebuild with the editor, which calls it
when a generation writes the two files or a reset clears them (rule 3).

The subject and the message are the contents of `title.txt` and `message.txt`,
which always match what the Message section shows, because an edit in the box
writes the file at once (`ai/description_template.md`). The subject is read only
for a type that has a title; the type without one is not a type the section
covers, so that check is defensive.

The section has no dirty flag of its own. What it writes — the forum and the
link — goes through the editor's single write path, so the tab becomes dirty and
Ctrl+S saves it, as a Stash import does.

## 6. The run

The form body is `application/x-www-form-urlencoded; charset=UTF-8`, with the
values percent-encoded as UTF-8, so the newlines in a message are `%0A`:

```
action=topic_draft&mode=save&form_token=<TOKEN>&draft_id=<DRAFT_ID>&forum_id=<FORUM_ID>&subject=<TITLE>&message=<MESSAGE>
```

`DRAFT_ID` is 0 for a new draft, and the id read from the stored link's `draft`
parameter for an update.

The response is JSON:

```json
{"draft_id":10989,"is_tpl":0,"saved_at":"02:32:09","action":"topic_draft"}
```

The app takes the id, builds
`https://pornolab.net/forum/posting.php?mode=newtopic&f=<FORUM_ID>&draft=<DRAFT_ID>`,
writes it as `draftUrl`, and shows it. `is_tpl` is not read: the app never saves
as a template. The link is built from the site address the client holds, not
from the URL the user pasted, the same rule as the scene link
(`StashClient.siteBase`).

A draft the app stored can be deleted on the site, and the answer for an update
of it is the same shape with `gone` 1:

```json
{"draft_id":0,"gone":1,"action":"topic_draft"}
```

POST with `draft_id` 42 for a draft that had been
deleted. `draft_id` 0 is not a draft to link to, so no link is built from it:
the same form with `draft_id` 0 is the call that makes a new draft, so the run
makes one and the link it stores is the new draft's. The new draft is asked for
once — a second such answer is what the run ends with rather than a loop. The
token is the one already cached, so the page is not read again for the second
call.

The token is read from the first `form_token` value in the GET response, whether
it is a hidden input or the `ajax.form_token` assignment, because the page
builds its form with JavaScript and the example has only the assignment.

The token is cached for the app session, so a second run does not fetch the page
again. The cache is the client's own state — the first stateful service in the
app — and the client is the right place for it, because the token belongs to the
site session rather than to a release, and two releases of the same session
would share it. A run that is told the token was wrong drops the cache, so the
next run fetches it again. The app does not retry a run for a failure it cannot
act on, and it does not make a login from one (`ai/pornolab_login.md` §7). The
deleted draft above is the one case where the answer names what to do, so the run
does it in the same call.

The client does not follow redirects, because a cookie the site does not accept
is answered with a redirect before the page is served. GET
`posting.php?mode=newtopic&f=1842` with a session id the site does not accept:

```
HTTP/2 302
location: https://pornolab.net/forum/login.php?redirect=posting.php?mode=newtopic&f=1842
content-type: text/html; charset=windows-1251
set-cookie: plm=1; Path=/; Max-Age=2592000; HttpOnly; SameSite=Lax
```

with an empty body. Following it would land on the login page, which is the page
with no token `noToken` describes, so the app reads the status instead. A wrong
cookie is therefore the redirect rather than such a page, and the location is
what says it: a redirect whose location is the login page is the cookie refused,
and any other answer is the request failing. The word for it says where to log
in again, because the app does not do it.

A call that runs longer than 60 seconds is stopped and reported as a timeout,
the same limit `ToolRunner` has.

A response is read as the charset its Content-Type declares, because the site's
pages are not UTF-8 — reading one as UTF-8 is what a real run failed with. A
charset the app has no codec for, or none declared, is read as Latin-1, which
cannot fail: the values the app reads out of a response are ASCII, so an
encoding it does not know is not a reason to lose a run. What the text looks
like then is a matter for the log, where the site's own words go.

## 7. Results

The client returns typed results and the widget maps them to localized text
(rule 13). The mapping is the one the settings row shares, because the same
results are shown in two places (`ai/pornolab_login.md` §8):

- saved — the draft id, and the link built from it;
- the stored draft not being on the site any more: the client answers that answer
  by making a new draft, so what the widget sees is a saved draft with the new
  link, and the result says whether the run made one or updated the stored one —
  the section says which, because the link the release holds changes. The word
  below is for the case where the new draft is refused too;
- no cookie stored, no forum, or a forum that is not the shape: the checks the
  controller makes before the request, which are the same rules the button is
  gated on, so a run is not reached with a value they refuse. The word for the
  cookie names where to make the login, because the app does not make one;
- the login refused, and a login that gave no cookie;
- the cookie refused — the page the token is read from answered with the
  redirect to the login page (§6);
- no token in the response — a page that was served without a `form_token`;
- token rejected — `error_code` 1, the form signature the site did not accept;
- any other code the site reports, and a response that is not the JSON shape the
  app expects;
- no connection, or a response that is not 200;
- stopped by the timeout.

The three shapes the response has, as the tests hold them:

```json
{"draft_id":10989,"is_tpl":0,"saved_at":"02:32:09","action":"topic_draft"}
{"error_code":1,"error_msg":"…"}
{"draft_id":0,"gone":1,"action":"topic_draft"}
```

The second is the answer for a form signature the site did not accept. With a
cookie the site does not accept and a token the app did not read from a page,
the answer is this shape: the site reached the form check,
so the response cannot say which of the two it refused. A run reaches the form
check only when it has a token cached from a session the cookie is for, so for a
run this is the token rather than the cookie — a wrong cookie is answered
earlier, on the page the token is read from (§6).

The site's own `error_msg` text is not shown: it is one language, and a
user-visible string comes from `AppLocalizations`. The code is what the widget
maps, and the text the site wrote goes to the log.

## 8. Logging

Requests and responses are logged, in the same JSON Lines log the tools write to
(`ai/upload_images.md`), one entry per request and one per response. The `tool`
field is the site the app called, `pornolab`, as it is the name the app declared
the tool as. The `input` field is the request as the app made it: the headers it
set, with the cookie as the marker, the method, the URL, and the form fields of
the POST. A response entry carries the status, the headers, and what the app
read from it.

**A credential is never written as its value.** The cookie is recorded as the
redacted marker, not as the string, and the same rule is why the headers that
carry one — `Set-Cookie`, `Authorization`, `WWW-Authenticate` — are left out of
the entry. What is left is what a problem is read back from: the content type,
which says the charset the answer came in, and the location a redirect would
have gone to. A header with more than one value is recorded with the values the
response gave.

The HTML page is not recorded in full. The entry records the status and the
token the app read, because a page is not a result the log is for, and the page
header carries the account name the cookie belongs to.

A request that got no answer is recorded with the failure entry, so a call that
failed before a response is not left as a request with nothing after it. The
request entry is written first, then the response or the failure.

The log is a required constructor parameter of the client, as it is of
`ToolRunner`, and writing it is one of its side effects.

## 9. Testing

Nothing in the tests reaches the network. The client is behind an interface, as
`SecretStore` is, so the feature is tested against a fake; the parse and the
rules are what the tests exercise, as `StashClient.parseResponse` is. The same
rule covers writing this feature: the site is not probed, so what the responses
look like comes from the examples here, not from a request.

The example page is not stored in the repo: it carries the account name and
other data from a real session. The tests use a trimmed version of it in the
test file — the assignment with a token and nothing else — plus the two JSON
shapes.

What is tested:

- the forum id read from a URL, and the shape rule;
- the form body, including the percent-encoding of a message with newlines;
- the token extraction from the two forms the page writes it in;
- the JSON parse, and each result the client can return;
- the charset a response is read as, including the one a real run failed with;
- the headers the log records, with the ones that carry a credential left out;
- the redaction — an entry never holds the cookie — and the failure entry a
  request with no answer writes;
- the update path: a stored link gives the id, an absent one gives 0;
- the `gone` shape, and the run that answers it by asking for a new draft once
  rather than by linking to `draft_id` 0;
- the user agent, checked against `app_info.dart` rather than written in the
  test;
- the login form body, encoded from its Windows-1251 bytes, and the value of the
  submit button;
- the `Cookie` value built from the `Set-Cookie` headers, and the two answers
  that decide whether a login was accepted;
- the login entry the log writes, with the credentials as the marker and no
  cookie recorded, and the request it sends, which carries no `Cookie` header;
- the form token cache being dropped by a login;
- the settings row: the field list and the mask flag, the username shown plainly
  and the password masked, the three controls on one line, the button committing
  the fields before it calls the site, the red Log out, the fields disabled
  while a session exists, and a logout making no request;
- the location that is the login page, and the answer a wrong cookie gets on the
  page the token is read from being read as the cookie refused rather than as
  the request failing;
- the section: the placeholder while no message exists, the button disabled
  while no cookie is stored, the order the placeholder names, a run with nothing
  stored not being made, a cookie the site did not accept being said as the
  result it is with the run not made again, the button disabled while the forum
  is empty, the link shown from a stored value before any run, the label drawn
  only with a link, the copy button writing to the clipboard, and the link
  opening through the fake launcher;
- the section saying which of the two a run did: the line for the run that made
  a new draft, and nothing said for the run that updated the stored one.

The coverage as the tests hold it is in the test files themselves:
`test/pornolab_client_test.dart`, `test/draft_section_test.dart` and
`test/settings_test.dart`. The client fake is `test/fake_pornolab_client.dart`,
shared by the tests that build the controllers, because a run asks the settings
feature for the login and both have to be given the same client.

## 10. The code

The shape is the one the rest of the app uses:

- `lib/service/network/pornolab_client.dart` — the interface, the rules it
  applies as functions on it, and the implementation over the `HttpClient` the
  app already has. The rules are on the interface so a test exercises them
  without a request.
- `lib/feature/draft/draft_controller.dart` — the gates, the rule for the one
  field the feature owns, and the run. It holds nothing that can change while
  the app is running: the cookie is read from `SettingsController` per call, and
  a run does not make a login. That is the first controller that depends on
  another controller, recorded in `ai/doc.md` §4.
- `lib/feature/draft/draft_section.dart` — the widget, and the words it shows
  for a result, read from the mapping the settings page shares.
- `lib/service/launcher/url_opener.dart` — opening a URL in a browser, the
  second job for `url_launcher`, behind a service with a typed result as
  `FolderOpener` is.
- `lib/service/logging/tool_log_entry.dart` — the three entry types a network
  call is recorded with, and the redacted marker.

The file listing is in `ai/doc.md` §3. No native tool is called, so the System
Check page does not change.

## 11. Open questions

- The other `error_code` values `ajax.php` can return. Only the wrong-token one
  is known, so the rest are one result until they are seen.
- Whether the app can tell a stale cookie from a rejected token. Both look like
  the same response, so the words for that result cover both.
- Whether `www.pornolab.net` should be accepted. The rule as written takes the
  host the app builds links from, so a mirror or a subsite host is refused, and
  a forum URL on another host is a value the user may well have meant.
- Whether the parent forum row should be drawn before a message exists. It is
  not, because the section is its title row and the placeholder while nothing
  can run — but the forum is something the user may want to fill first, and the
  order is a choice rather than a consequence.
- Whether a run can be stopped. No other network feature can be.
- Whether the app can delete a draft it made. It cannot; the site is the only
  place the draft exists.
