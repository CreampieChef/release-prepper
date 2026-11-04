# Login

The app obtains the PornoLab cookie itself, from a username and a password,
rather than the user pasting it. It is the second part of the PornoLab feature
(`ai/uploading_draft.md` §2), and the first feature that writes a value the app
reads from the settings rather than only reading it.

## 1. What it does

The user sets a username and a password on Settings → Integration and logs in
there. The app then:

1. uses the cookie it has stored when a run needs one;
2. when it has none, says where to make the login rather than making one itself;
3. when the site does not accept a cookie, says what it was and where to log in
   again, and does not make the run again;
4. when the answer asks for a code, shows the image and takes the code from the
   user and sends it (§3, §6);
5. reports a login that did not work, or a cookie that did not, as an error,
   and says a login that worked in the same place (§3).

The app does not log in by itself, because the site asks for a captcha after a
few login attempts from the same address: a login the app made on its own would
use up the limit the user needs, and a run has no user to read an image (§7).

A code is only answered from the page: a run has no user to read an image, so a
run that gets an answer asking for one reports it as the result it is.

The login and the logout are made on the Integration page (§3). It is the only
path: a run does not make a login.

The manual cookie field is gone: the cookie is what the app obtains. The key the
pasted value lived under is not read any more and nothing is moved, because that
field was a stand-in for this feature rather than a record the app promises to
keep.

## 2. The values

Three values for pornolab in the credential store:

- `pornolabUsername` — what the user sets;
- `pornolabPassword` — what the user sets;
- `pornolabCookie` — the cookie the app writes. It is not a field the user
  edits, so it is a named key rather than an entry in the list the page draws.

The enum the page loops over is the list of fields, not of services, so it is
`SettingsField`: the two API-key entries keep their names, because the name is
the key and a rename would lose what a user has stored, plus the two new
entries. Each entry carries a `masked` flag, and the page reads the flag instead
of applying `obscureText: true` to every field in the loop (`_fieldLabel` in
`settings_page.dart`). A data list for four entries would be the
abstraction rule 3 refuses, so the flag is a getter on the enum; the page
already switches on the entry for its label, so the flag is one more read of the
same thing.

Storing a value and displaying it are two different things, and the documents
have to say so: the credential store holds values, and `masked` is a display
rule. The username is in the credential store and shown plainly. Nothing in
`SecretStore` changes — it has no notion of a secret beyond being the store.

The corner that follows: when the credential store cannot be reached and plain
storage is not allowed, a username cannot be stored at all, even though nothing
about it is confidential. The rule stays uniform — the field says what to
enable, as it does for the other values. Storing the username in `settings.json`
as an ordinary setting, like the release directory, is the alternative; it is
not taken, because the pair would then live in two places and the page would
need two rules about where a value is.

The stored cookie is used until the site refuses it or the user logs out from
the page. Nothing else ends it. The app does not know an expiry date, because
the attributes are dropped when a cookie is read (§5) — a `Cookie` header
carries none — so "expired" is what a refused cookie looks like: the first run
refused with it is the moment it expired.

A credential cannot change while a session exists, because the fields are
disabled while a cookie is stored (§3). So the cookie always belongs to the
account the fields show, and the page can say which account a session is for: it
is the account the user set, and it cannot change until they log out.

`SettingsController.setSecret` takes a key rather than a field, because a field
is what the page draws and a key is what the store holds: the cookie is a key
with no field, so the page cannot name one.

## 3. The Integration page

The section draws the two API-key fields as it does, and the PornoLab row as one
row: the username field, the password field, and the button.

The row's fields are capped at the same width as every other field on the page,
so the row does not make a field wider than the rest of it. What the row does is
put the three controls on one line when they fit and one control per line when
they do not, because a field cannot show its label at a width the label does not
fit in. The point where it stops is not a page breakpoint: it is what the three
controls need, and the button's part of that is measured from the label the app
is showing, so it moves with the language. Where the row is wider than the cap,
the fields take the cap and the row is not filled.

The username field is not masked and the password field is, from the flag in §2.
The button is:

- no cookie stored → **Log in**, enabled when both fields have text;
- a cookie stored → **Log out**, drawn in `colorScheme.error`. That is the red
  the repo already uses for a failed write (`recent_releases_page.dart`) and for
  the unsaved-changes dot (`tab_strip.dart`); it is the first use of it on a
  button — `TextButton.styleFrom(foregroundColor: ...)`, the same way the other
  buttons on the page are styled.

While a cookie is stored the two fields are disabled, so the row always shows
the account the session belongs to: a credential cannot change while a session
exists, and changing one means logging out first.

A disabled field cannot be edited, so it cannot commit; the commit rules apply
to the fields that can be edited. The button commits the fields' text before it
runs, so a request is never built from values the model does not hold. The note
that says where a value lives is said for every field, and once for the row
rather than once for each field in it, because the row is one place with three
controls in it.

Logging out does not call the site. The app has no session of its own beyond the
value it stored, so removing the value is what logging out means for it; the
site may still accept the cookie, and the next run has nothing to send and says
where to make the login again. It says nothing when it works — the row itself
shows the change — and a value that was not written shows the message the other
fields show.

The row reads the controller rather than holding its own state, because the
value it shows is the controller's and another feature reads the same value: the
draft section's gate is the cookie, so a login made here is something that
section shows too. The outcome of the last login is said in the section, next to
the row, because that is where the login is made; the page's snackbar stays for
what it is for now, a value that was not written.

The word is shown in the colour that says which the outcome was:
`colorScheme.error` for a login that did not work, and a green for one that
did. The green is the only colour in the app that is not the theme's, because
`ColorScheme` has no success role. The words for a failure are the set the two
features share (§8); the word for a login that worked is the page's own,
because a run has nothing to show for one — its success is the link it was
given. The space says the outcome of the last action, so a logout takes the word
away: a logout that works says nothing, as it does now.

When the answer asks for a code, the section shows it: the word first, then the
image the code is read from, then a field for the code. The word is the same one
the draft section says for that result (§8), so the two features say the same
thing. The code field is capped at the same width as the other fields on the
page.

The same button is the second half of the login, so it is gated on the code as
well as on the two credentials: a login with an empty code is the same answer
again, so there is nothing to send. The code is not a stored value and is not
committed as the fields are — it belongs to the page that asked for it, so a new
captcha is a new code and the text typed for the previous one is cleared. A
captcha is kept only for the answer that asked for it, so any other outcome
clears it. Logging out cannot be showing one: the button is Log out only when a
cookie is stored, and an answer that asks for a code stores none.

The image is shown with `Image.network` and is not stored anywhere, because a
captcha is not a record the app keeps. Each captcha is a different URL, so the
widget's key changes on its own and the rule in `ai/doc.md` §5 about an image
rewritten under the same name does not apply here. A load that does not work
shows nothing, as every image widget in the app does.

The row is the settings feature's, so it is not part of a release and not part
of Ctrl+S, as the rest of the page is not.

## 4. The request

One POST, `application/x-www-form-urlencoded`, to
`https://pornolab.net/forum/login.php`, with the fields the form has, in the
order the form declares them:

```
redirect=index.php
&login_username=<USERNAME>
&login_password=<PASSWORD>
&login=%C2%F5%EE%E4
```

The first login is the form as it stands, without a captcha, because the app
does not know whether the site will ask for one. When it does, the form's two
captcha fields go between the credentials and the button, in the order the form
declares them:

```
redirect=index.php
&login_username=<USERNAME>
&login_password=<PASSWORD>
&cap_sid=<SID>
&cap_code_<HASH>=<CODE>
&login=%C2%F5%EE%E4
```

The name of the code field is a hash that changes with the page, so it is read
from the page rather than assumed (§6). The two are sent only when there is a
code to send, which is the same rule the button is gated on (§3).

Two of the fields are not data the app chose. `redirect` is the form's
hidden field, and `login` is the name and the value of the submit button: a
browser sends a named submit button as part of the form data, and its value is
the button's label. The label is "Вход", and the page is Windows-1251, so a
browser sends it as `%C2%F5%EE%E4`. The app sends the same bytes.

The whole body is encoded in Windows-1251, not UTF-8. This is the one request
where the app does not use its UTF-8 rule (`ai/uploading_draft.md` §6), and the
reason is that here the app is reproducing what the site's own form sends rather
than building a body of its own. `Uri.encodeQueryComponent` encodes as UTF-8, so
a value is encoded to Windows-1251 bytes first and then percent-encoded, and the
body is written as bytes rather than as a String.

A character the codepage has no byte for is not dropped or replaced: a browser
percent-encodes its UTF-8 bytes when the form's charset cannot represent it, so
the app does the same. The site reads the form as Windows-1251, so a password
with such a character is refused there too; the point is that the app sends what
the browser sends rather than failing before the request. A percent escape is
two hex digits.

The Content-Type names no charset, as a browser's does not. Whether the site
reads the form as the charset its page declares or as UTF-8 is an open question
(§12); for an ASCII username and password the two are the same.

The login form has no `form_token`, so no page is read first: one request.

## 5. Reading the cookie

From each `Set-Cookie` in the answer the app keeps the `name=value` pair and
drops the attributes — `path`, `domain`, `expires`, `HttpOnly`, `Secure` — and
joins the pairs with `; `. That is the `Cookie` header value the app sends, and
it is stored under `pornolabCookie`. An answer with no pairs is not stored. More
than one header is more than one pair.

The app has no cookie jar and does not need one: it sends what it stored, so
whether the site marked the cookie persistent or a session cookie makes no
difference to the app.

## 6. Judging a login

The client does not follow redirects (`ai/uploading_draft.md` §6), so the login
answer is seen as it is:

- a redirect means the login was accepted;
- the login page itself means it was not;
- the login page that asks for a code is a refused login the user can still
  answer. That page echoes the credentials back and complains only about the
  code, so the credentials were accepted and the form cannot be completed
  without it.

A `Set-Cookie` on its own is not proof, because the site sets a session cookie
for an anonymous visitor too. The cookie is taken only from an answer that shows
the login was accepted.

The three parts the app needs from a page that asks for a code are the image
the code is read from, the hidden `cap_sid` that says which captcha an answer
is for, and the name of the code field. A page with only some of them is the
refused login rather than a captcha, because a code the app cannot show is a
code the user cannot type. The cookie the same answer set travels with the
three, because the app has no cookie jar and the code is checked against the
session the page that asked for it belongs to (§9).

The refused shape is what the live site gives for a wrong password: a 200 login
page with a cookie for the anonymous visitor, which is the case the paragraph
above is about. The captcha shape is what the same site gives after failed
logins from the same address, and it is the shape the parser was written from.
The accepted shape is not observed — it is the shape the site's login handler
has, so the tests hold the three as the rule, the same rule
`ai/uploading_draft.md` §9 states for the JSON responses.

## 7. The run

The gates are the same rules the button is gated on, with the credentials
replaced by the cookie: a message exists, a cookie is stored, and the forum
passes the shape rule. The placeholder names the first thing the section is
missing, in the order it can act on it: the message, then the login, then the
forum.

The app does not make a login from a run, and it does not retry one. The reason
is the captcha: the site asks for one after a few login attempts from the same
address, and a login the app made on its own would use up the limit the user
needs in order to log in, while a run has no user to read the image. So the
login stays the page's action: a run that has nothing stored says where to make
it, and a run whose cookie the site did not accept says what it was and where to
log in again.

A run is the page the token comes from, then the call that saves the draft.

A login is a new site session, so the cached form token is dropped when the app
logs in: the token belongs to the session the cookie is for, and a new cookie is
a new session.

The values, the login, and the logout belong to `SettingsController`, because it
owns the credential store: it makes the call, writes the value, and removes it.
It takes `PornolabClient` as a required constructor parameter (rule 4), added at
the composition root, and returns typed results the widget maps (rule 13).
`DraftController` asks it for the cookie, which makes it the first controller
that depends on another controller — a deviation to record in `ai/doc.md` §4. A
session controller between the two is the alternative, and for one read that is
the abstraction rule 3 refuses.

The cookie is still not held in the draft controller: it is read per call, as
`ai/uploading_draft.md` §10 states. What changes is that the feature can write
it.

## 8. Results

The client returns typed results and the widget maps them to localized text
(rule 13):

- no username, or no password: the check before the login, the same rule the
  settings page gates its button on;
- no cookie stored: the check before the run, the same rule the draft section
  gates its button on. The word for it is the placeholder the tooltip shows, so
  the gate and the result say the same thing, as they do for a field;
- login refused — the answer was the login page;
- the answer asked for a code — the one result that carries what the page gave,
  because the widget shows the image and the field. It is a field of the failure
  rather than a result case of its own so that the words for a result stay one
  set; the code the user types is not part of it, because that is given to the
  next request rather than carried in a result.
- login accepted with no cookie in the answer;
- the cookie refused — the page the token comes from answered with the redirect
  to the login page (`ai/uploading_draft.md` §6). The word says where to log in
  again, because the app does not do it (§7);
- no connection, or an answer that is neither 200 nor a redirect;
- stopped by the timeout.

The same results are what the Integration section maps for its button, so the
words are one set shared by the two features rather than a set per feature.

The word for a login that worked is not in that set, because only the page shows
it: a run has nothing to show for one, its success is the link it was given. So
it is a string the page resolves, which is rule 13 as it usually reads — the
shared mapping is the recorded exception, and this word is not part of it.

New l10n keys in both arb files: `pornolabUsernameLabel`,
`pornolabPasswordLabel`, `loginButton`, `logoutButton`, `captchaCodeLabel`,
`pornolabLoginAccepted`, `pornolabCookieRefused`, `draftNeedsLoginFirst`, and
the words for the results, including `pornolabNeedsCaptcha`. The word for a code
is said the same way in both features, so it names only what the answer asked
for and not where the user should type it — the settings page has the field, the
draft section does not. `pornolabCookieLabel` is removed with the field, and
`draftNeedsCredentialsFirst` with the gate it belonged to.

## 9. Logging

The login is one request entry and one response entry, like every other call.

A login is recorded in the app data directory, because the settings page is the
only place one is made and outside a release there is no release directory — the
same rule the System Check page follows (`ai/doc.md` §2). The `tool` field is
`pornolab`, and the entry says nothing about where the call came from.

The first login request carries the User-Agent and no `Cookie` header, because
when the app logs in it has no cookie to send. Its entry therefore has no Cookie
line at all, rather than one with the marker. The request with a code is the one
case a login has a Cookie line, because the app sends the cookie the page that
asked for the code set (§6); it is recorded as the marker, as every cookie is.

Neither cookie is ever recorded as a value. The `Cookie` header the app sends on
the other calls is recorded as the redacted marker, as every credential is
(`ai/uploading_draft.md` §8, and `ai/doc.md` §3 for the entry type that carries
the marker); `Set-Cookie` is not recorded at all, as every header that carries a
credential is left out. The display rule and the redaction rule are not the same
thing: the username is shown plainly on the page and still not written as its
value in the log. The `login` field is a constant, so it is recorded as its
value.

The captcha's two fields are recorded as their values. `cap_sid` is a value
read out of a page, as a form token is, and the code is not a credential but
the thing the user read from an image; neither is confidential, and both are
what the answer is judged by, so an entry has to be able to say them.

What tells a login apart is the status and the location a redirect would have
gone to — which is what §6 reads, so the log can say the outcome without the
values.

## 10. Testing

Nothing in the tests reaches the network; the client is behind an interface, as
`SecretStore` is. The one exception is the captcha image: a test reads the
provider the widget was given rather than the image it resolves, but building
the widget starts a load, so that test does make a request. It does not depend
on the answer, because the image widget's error builder is what keeps a load
that does not work from being reported as an error — the same thing that makes
the app show nothing rather than an error. What is tested:

- the form body, including the Windows-1251 percent-encoding of the button label
  and of a value with non-ASCII characters, a character the codepage cannot
  represent, and an escape for a byte under 0x10; and the body with the captcha
  fields, in the order the form declares them;
- the captcha parse: the three parts the form carries, a page with only some of
  them is not a captcha, and a link the page writes without a scheme is made one
  the app can request;
- the `Set-Cookie` parse: attributes dropped, pairs joined, more than one
  header, an answer with no pairs;
- the judgement: a redirect is accepted, the login page is refused, and the
  login page asking for a code is the result that carries what the page gave
  and the cookie the same answer set;
- the location that is the login page — as the site sends it and as a relative
  path — and the page the token is read from not being it. The answer the site
  gives a wrong cookie is held as a test: the 302 with the location, not
  followed, so the call ends there (`ai/uploading_draft.md` §6);
- the run: a run with no cookie stored is not made and says where to log in; a
  cookie the site does not accept is said as the result it is and the run is not
  made again; a run that fails for any other reason is made once;
- the token cache dropped by a login;
- the redaction — an entry never holds the username or the password, and does
  hold the `redirect` and `login` fields, and a captcha entry records the code
  and the sid as their values while the cookie stays the marker;
- the field list: the mask flag and the keys;
- the draft section's gate: the button disabled while no cookie is stored, the
  order the placeholder names — the message, then the login, then the field;
- the row: the two fields and the button on one row, the username shown plainly
  and the password masked, the fields capped at the same width as the other
  fields on the page, the fields disabled while a cookie is stored, the
  button Log in when none is stored and Log out when one is, Log in disabled
  while a credential is empty or a call runs, the outcome of the last login
  shown in the section in the colour that says which it was — the red for a
  failure and the green for a login that worked — and a field committed by the
  button before the call is made. Being one row is
  checked by where the three controls are drawn, not by a `Row` ancestor finder,
  because the page has another row the finder would match; the same check at a
  window narrower than the three controls need shows them on three lines;
- the row changing when a login stores a cookie, because it reads the controller
  rather than holding its own state;
- logging out removes the value from the store and makes no request, and the
  next run says where to log in; it also takes the word for the login that made
  the session away, because the space says the outcome of the last action;
- the captcha block: the word, the image and the code field shown after an
  answer that asks for one, the button gated on the code, the second call made
  with the captcha and what was typed into it, and a captcha kept only for the
  answer that asked for it;
- the first login request sends no `Cookie` header, and the request with a code
  sends the cookie the captcha page gave; no entry holds a cookie value —
  neither the header the app sends nor the one an answer gave;
- the results mapped to text.

The field keys the tests look for are `secret-pornolabUsername` and
`secret-pornolabPassword`, and the row adds one for the button.

The tests are the three files the feature changes:
`test/pornolab_client_test.dart` for the rules on the interface,
`test/settings_test.dart` for the fields, the flag and the buttons, and
`test/draft_section_test.dart` for the gate and the run. The client fake they
share is `test/fake_pornolab_client.dart`, because a run asks the settings
feature for the login and both controllers have to be given the same client. It
records what each login was given, including the captcha's field name and the
code, which is what a test checks the second call against.

## 11. The code

- `lib/service/network/pornolab_client.dart` — `login()` on the interface, the
  Windows-1251 body, the `Set-Cookie` parse, the captcha parse, the judgement.
  The rules are on the interface so a test exercises them without a request.
  `LoginCaptcha` is what a page that asks for a code gave the app, and the code
  the user types is given to the next request rather than carried in it.
- `lib/feature/settings/settings.dart` — `SettingsField` with the key and the
  mask flag, and the `pornolabCookie` key the app writes the cookie under.
- `lib/feature/settings/settings_controller.dart` — `setSecret` by key and the
  login. Logging out is that same write with an empty value, called from the
  page: there is no logout method, because there is nothing to do beyond
  removing the value the app stored. The login takes the captcha and the code;
  a run calls it with neither, which is the shape the first login is. It takes
  `PornolabClient` and the app data directory as required constructor
  parameters, for the same reason `SystemCheckController` is given one: a call
  made from the page has no release directory.
- `lib/feature/pornolab_results.dart` — the words for a result, as one set the
  settings page and the draft section both read. It is the exception to rule 13
  recorded in `ai/doc.md` §4.
- `lib/feature/settings/settings_page.dart` — the loop reads the flag, the
  labels for the two new fields, and the row: the two fields and the button, the
  fields disabled while a cookie is stored, and the button in the error colour
  when it is Log out. The outcome of the last login, the word for it and the
  colour it is shown in, and the captcha are widget state: the image, the code
  field, and the button gated on the code.
- `lib/feature/draft/draft_controller.dart` — the gates, and the cookie read
  through `SettingsController`. A run is made once and does not log in.
- `lib/feature/draft/draft_section.dart` — the words for a result, read from the
  mapping above.
- `lib/app/app_providers.dart` — no new entry. `SettingsController` and
  `PornolabClient` are already there; the settings entry gains the two
  parameters above, and the draft controller takes `SettingsController` from the
  scope.

No native tool is called, so the System Check page does not change.

## 12. Open questions

- Whether the site reads the login body as Windows-1251 or as UTF-8, and whether
  naming the charset in the Content-Type would change that. The form §4 is what
  the code sends, and the site is not probed.
- Whether the site needs `sid` or `autologin` with the four fields. `redirect`
  is sent because the form has it as a hidden field. A browser sends
  `autologin=1` when the checkbox is on; the app sends nothing, because it keeps
  the cookie itself.
- Whether a redirect is the only shape a successful login has, and whether the
  login page is the only shape a refused one has (§6).
- Whether the captcha check works for a client that has no browser session. The
  app sends the cookie the page that asked for the code set, as a browser
  would, which is the plan rather than an observation: the captcha shape was
  read from a page a browser was given.
- Whether a stale cookie can be told from a rejected token. A POST with a
  cookie the site does not accept is answered by the
  form check, so that answer cannot say which of the two it refused. What the
  site does say is the page the token is read from: a cookie it does not accept
  is answered with the redirect (`ai/uploading_draft.md` §6), which is why the
  two are read as different results. A run reaches the form check only when it
  has a token cached from a session the cookie is for, so a run that is answered
  by the form check has a token the site refused rather than a cookie.
- Whether logging out should tell the site. It does not: the app removes the
  value it stored, and the site may still accept the cookie for a session the
  app no longer uses.
- Whether `www.pornolab.net` should be accepted. It is the same question as
  `ai/uploading_draft.md` §11.
- Whether a run can be stopped. It cannot, as no other network feature can.
