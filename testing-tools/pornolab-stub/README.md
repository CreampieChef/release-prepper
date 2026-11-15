# pornolab-stub

A small server that answers as PornoLab for the requests the app makes to it
through the tracker client: the three a post is made of, and the page a forum
name is read from. Standard library only, and run by hand:

    python3 testing-tools/pornolab-stub/rp_pornolab_stub.py [--port 40002]

The requests are the ones `ai/pornolab_upload.md` records:

- `GET /forum/posting.php` answers with the page the form token comes from, with
  the form in the order §3 of that document lists it;
- `POST /forum/posting.php` reads the multipart form it is given and answers
  with the block the recording shows, with the id the topic got; the length of a
  form is read from the `Content-Length` header, as a browser declares it, so a
  form without one is not read;
- `GET /forum/dl.php` answers with the file the form was given, re-encoded with
  the four keys the recording shows the tracker adding, named as the recording
  names it;
- `GET /forum/viewforum.php` answers with a page whose breadcrumb names the
  forum the `f` value is for. This is the page the app's rule reads the forum
  name from, so the words are in the breadcrumb link as well as in the title,
  because the rule reads the breadcrumb and not the title. The recording has no
  forum page, so the words are this server's own: "Pornolab stub forum <f>".
  The shape is not the server's own: the breadcrumb is the table cell with the
  `nav` class, as a run against the site showed a page writing it, and that is
  what the rule reads (`ai/uploading_draft.md` §4). A page writes the cell twice
  and the app reads the first, which is what is answered here.

The login and the call that saves a draft are not answered: what is answered
here is the post and the name read for a forum, and the draft is a part of the
app that already works. A request for the login page is answered as not
answered, so the chain a browser follows from the redirect ends at one page: a
redirect whose target answers with the same redirect is a chain that never ends,
and each hop puts the value it was given inside another `login.php?redirect=`.

A POST is read before anything is answered, including a POST that is refused. A
server that answers without reading the body leaves the connection out of step:
the next thing it reads is the body as a request line, and the client is told a
response came without a request. A run is several calls on one connection, so
the first call that is not read takes the calls after it with it.

## Pointing the app at it

The app is started with `--dev-tracker-stub`, which is what makes it build its
requests and its links from `http://localhost:40002` — the port this script
serves on by default — instead of from the site (`ai/pornolab_upload.md` §10). A
post made through the app's Publish button then comes here, and the file the app
writes is the one this server gave back for the topic it made.

What a run here covers is the requests above. The page a forum name is read from
is asked for at the base the app was started with, as every request on the
client is, so the name the parent forum row shows for a run here is the name
this server's page carries. A post is made with a cookie the app already has:
the app does not log in by itself, and the login is not answered here, so the
cookie a run sends is one the real site gave.

## What it keeps

The file a POST is given is stored under `posted/<topic id>.torrent` beside this
script, and `dl.php` answers from what is stored. That is the state the
recording shows the site having, and it is the point of the server: a server
that answered with a file it had not been given would not be the thing the
feature is tested against, because the file that comes back is what the feature
writes.

The folder is gitignored, like what the other tools run by hand produce.

## What is read and written in Windows-1251

The recorded pages declare it and the recorded form was sent in it, so this
server writes pages in it and reads the values it is given as it. A byte the
codepage has no value for is read as the replacement character rather than as
UTF-8: the app's rule for a character the codepage has no byte for is to send
its UTF-8 bytes (`ai/pornolab_login.md` §4), and what the site does with those
bytes is the open question `ai/pornolab_upload.md` §12 keeps — reading them as
UTF-8 here would settle the question in the stub's favour, which is not what a
stub is for.

## What this server's own, not the site's

A test that asserts one of these is asserting this server, not the site:

- the topic ids it assigns, starting at 3000111 so the first answer is the one
  the document shows;
- the error shapes, because the recording has no failure;
- the words a forum page carries, because the recording has no forum page;
- the fixed token, the announce key `stubkey`, and the name `stubuser` it writes
  pages with;
- the redirect for a request with no cookie, and the page that redirect points
  at, which says what is answered rather than redirecting again so that the
  chain a browser follows ends at one page. Both are the behaviour
  `ai/uploading_draft.md` §6 states, rather than something this recording
  observed;
- the pages it writes, which are its own shapes with the block's wording as the
  recording has it — except the forum page's breadcrumb, which is the shape a
  run against the site showed (`ai/uploading_draft.md` §4). The BBCode panel and
  the keyboard select are not drawn, because this is not a browser.

The address the served file names is the site's own (`https://pornolab.net`), as
the recording has it, not the address the request came to — so a test that reads
the served file's `comment` sees the site's address, not this server's.

## The checks

`test_stub.py` beside this script is the server's own tests, not the app's. The
precondition is python3, standard library only, and it is run by hand:

    python3 testing-tools/pornolab-stub/test_stub.py

It starts its own server on a port the operating system gives, so a run does not
need the port this script serves on by default and does not conflict with a
running stub. What a POST stores goes to a temporary folder, so a run leaves
nothing in the tree, and the logging is off while the checks run.

The checks cover the shapes above: the form as it is read, the page the token
comes from, the block that answers a post, the served file with the four keys
added to it, the forum page with the breadcrumb cell the app's rule reads, the
refusals, the redirect for a request with no cookie and the chain ending at one
page, and that a request which is not answered is still read.

A change to this server is not reported as done until these pass. A failure says
one of two things: the change is not the shape this file records, or the shape
was changed on purpose, in which case the check and this file are changed with
it, in the same change.
