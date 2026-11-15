#!/usr/bin/env python3
"""Answers as PornoLab for the requests the app makes to it through the tracker
client: the three a post is made of, and the page a forum name is read from.

    python3 testing-tools/pornolab-stub/rp_pornolab_stub.py [--port 40002]

The requests are the ones `ai/pornolab_upload.md` records: the page the form
token comes from, the form with the file attached, the file the tracker serves
back for the topic the form made, and the page the forum name is read from. What
is answered is the recorded shape: the pages are written in the charset the
recorded pages are in, the values this server is given are read as that
codepage, the page that answers a post is the recorded block with the recorded
wording, the served file is the file this server was given with the four keys
the recording shows added, and the forum page is the breadcrumb cell the app's
rule reads, in the shape a run against the site showed a page writing it. A
forum page is not in the recording, so the words on it are this server's own.

The app is pointed here by starting it with `--dev-tracker-stub`
(`ai/pornolab_upload.md` §10). The login and the call that saves a draft are
not answered here, so a post made through the app is made with a cookie a
real login gave. A request for the page the login redirect points at is
answered as not answered, so the chain a browser follows ends at one page: a
redirect whose target answers with the same redirect is a chain that never
ends, and each hop puts the value it was given inside another
`login.php?redirect=`.

The state is the one the recording shows the site having. The file a POST is
given is kept under `posted/` (gitignored), one file per topic, and `dl.php`
answers with it: a server that answered with a file it had not been given would
not be the thing the feature is tested against, because the file that comes back
is what the feature writes.

What is this server's own rather than a rule of the site: the topic ids it
assigns, the error shapes, the token, the announce key, the account name,
the words a forum page carries, the redirect for a request with no cookie
and the page that redirect points at, and the checks in `test_stub.py`,
which are this server's own tests rather than the app's. A test that asserts
one of these is asserting this server, not the site.
"""

import argparse
import html
import os
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
POSTED_DIR = os.path.join(HERE, "posted")

# The values the document uses, so an example there and an answer here read the
# same.
TOPIC_ID_START = 3000111
USER_ID = 40000111
NAME = "stubuser"
ANNOUNCE_KEY = "stubkey"

# The recorded pages are in Windows-1251 and the recorded form was sent in it,
# so this server writes in it and reads the values it is given as it.
CHARSET = "windows-1251"

# The limit and the extensions the recorded page declares for the file part.
MAX_FILE_SIZE = 1048576
EXTENSIONS = (".torrent", ".zip", ".rar")

# What this server answers, as the page that says so words it. A request that is
# not answered gets this page, including the page the login redirect points at:
# the login is not answered here, so a request for it says so rather than
# redirecting again, and the chain a browser follows ends at one page.
ANSWERED = "the stub answers posting.php, dl.php and viewforum.php"

# One fixed token, so a run can be made again against the same page. It is
# written as the recording writes it — as the assignment the page's script
# makes, not as a field the form declares — because the app reads both forms and
# this page is the one the recording shows.
TOKEN = "00000000000000000000000000000000"

# The address the served file names. The recording shows the site's own address
# in it rather than the address the request came to, so this server keeps that.
SITE_BASE = "https://pornolab.net"


def bdecode(data):
    """A bencoded value read as bytes, ints, lists and dictionaries."""
    position = 0

    def read():
        nonlocal position
        marker = data[position : position + 1]

        if marker == b"d":
            position += 1
            out = {}
            while data[position : position + 1] != b"e":
                # The key and the value are read in two statements, so that the
                # order is this code's and not the interpreter's: `out[read()] =
                # read()` reads the parts in the same order but stores them the
                # other way round on some interpreters.
                key = read()
                out[key] = read()
            position += 1
            return out

        if marker == b"l":
            position += 1
            out = []
            while data[position : position + 1] != b"e":
                out.append(read())
            position += 1
            return out

        if marker == b"i":
            end = data.index(b"e", position)
            out = int(data[position + 1 : end])
            position = end + 1
            return out

        end = data.index(b":", position)
        length = int(data[position:end])
        out = data[end + 1 : end + 1 + length]
        position = end + 1 + length
        return out

    return read()


def bencode(value):
    """A value written back as bencode. The keys of a dictionary are written
    sorted, which is the order the recording shows the tracker's file in."""
    if isinstance(value, dict):
        parts = [bencode(key) + bencode(item) for key, item in sorted(value.items())]
        return b"d" + b"".join(parts) + b"e"

    if isinstance(value, list):
        return b"l" + b"".join(bencode(item) for item in value) + b"e"

    if isinstance(value, int):
        return b"i" + str(value).encode() + b"e"

    if isinstance(value, bytes):
        return f"{len(value)}".encode() + b":" + value

    raise ValueError("not a bencoded value")


def tracker_file(data, topic_id):
    """The file as it was given, with the four keys the recording shows the site
    adding. The `info` dictionary is left as it came, so the pieces the app
    hashed are the pieces that are served back."""
    decoded = bdecode(data)

    if not isinstance(decoded, dict):
        raise ValueError("the file is not a bencoded dictionary")

    topic_url = f"{SITE_BASE}/forum/viewtopic.php?t={topic_id}"
    decoded[b"announce"] = f"http://plab.site/ann?uk={ANNOUNCE_KEY}".encode()
    decoded[b"comment"] = topic_url.encode()
    decoded[b"publisher"] = b"pornolab.net"
    decoded[b"publisher-url"] = topic_url.encode()

    return bencode(decoded)


def parse_multipart(body, boundary):
    """The parts of a multipart form as the form sent them: the fields by name,
    and the file part as its name, its name on the sender's side, and its bytes.
    Values are read in the charset the form was sent in.

    The delimiter is taken from the body rather than from the header: a
    browser writes the whole delimiter as the boundary parameter, so the
    header's value and the delimiter differ by the two dashes RFC 2046 asks for,
    and the body is what the parts are separated by.
    """
    delimiter = body.split(b"\r\n", 1)[0]

    if not delimiter.endswith(boundary.encode()):
        return {}, None

    fields = {}
    file_part = None

    for raw in body.split(delimiter)[1:-1]:
        head, _, content = raw.partition(b"\r\n\r\n")
        content = content[:-2] if content.endswith(b"\r\n") else content
        name = re.search(rb'name="([^"]*)"', head)

        if name is None:
            continue

        field = name.group(1).decode(CHARSET, "replace")
        filename = re.search(rb'filename="([^"]*)"', head)

        if filename:
            file_part = (field, filename.group(1).decode(CHARSET, "replace"), content)
        else:
            fields[field] = content.decode(CHARSET, "replace")

    return fields, file_part


def page_head(title="pornolab.net"):
    """The part of a page the app does not read, kept because the recording has
    it: the account name, and the user id in the link beside it. The title is
    the site's own for the pages the recording has; a page the recording does
    not have is titled with what this server's own."""
    return (
        f'<!doctype html>\n<html>\n<head>\n<meta charset="{CHARSET}">\n'
        f"<title>{html.escape(title)}</title>\n</head>\n<body>\n"
        '<div class="topmenu">Вы зашли как: '
        f'<a href="./profile.php?mode=viewprofile&amp;u={USER_ID}">'
        f'<b class="med">{NAME}</b></a></div>\n'
    )


def form_page(query):
    """The page the token is read from, with the form in the order the recorded
    form lays it out. The app reads the token and nothing else from this page;
    the form is here so that a request made to this server can be compared with
    the recording. The token is written as the recording writes it, as the
    assignment the page's script makes, because the recording has no field for
    it."""
    forum_id = (query.get("f") or ["0"])[0]
    draft_id = (query.get("draft") or ["0"])[0]

    fields = [
        ("mode", "newtopic"),
        ("f", forum_id),
        ("t", "0"),
        ("p", "0"),
        ("draft_id", draft_id),
        ("subject", ""),
        ("topic_tags", ""),
        ("fontFace", "-1"),
        ("codeColor", "black"),
        ("codeSize", "12"),
        ("align", "-1"),
        ("codeUrl", ""),
        ("message", ""),
        ("MAX_FILE_SIZE", str(MAX_FILE_SIZE)),
        ("post", "1"),
        ("decflag", "2"),
    ]

    out = page_head()
    out += '<form method="post" action="posting.php" enctype="multipart/form-data">\n'

    for name, value in fields:
        out += f'<input type="hidden" name="{name}" value="{html.escape(value)}" />\n'

        # The file part is what the page declares its limits for, and the order
        # the recording sends the form in has it between the message and the
        # post.
        if name == "message":
            out += (
                f"максимальный размер: <b>{MAX_FILE_SIZE // 1024}&nbsp;MB</b>, "
                f"файлы: <b>{', '.join(EXTENSIONS)}</b>\n"
                '<input type="file" name="attach" />\n'
            )

    out += f"<script>ajax.form_token = '{TOKEN}';</script>\n</form>\n</body>\n</html>\n"
    return out


def block_page(topic_id, forum_id):
    """The page that answers a post, as the recording has it: the block that
    says the file was registered, with the id in the download link and in the
    topic link. That block is the whole result of the request."""
    return (
        page_head()
        + '<table class="forumline message">\n'
        + "\t<tr><th>Информация</th></tr>\n"
        + "\t<tr><td>\n"
        + '\t\t<div class="mrg_16">\n'
        + "\t\t\tТоррент зарегистрирован на трекере<br /><br />\n"
        + f'\t\t\tТеперь вам <a class="dl-stub" href="dl.php?t={topic_id}">'
        + "<b>нужно его скачать</b></a>\n"
        + "\t\t\tи поставить на закачку у самого себя в ту же директорию, где лежат\n"
        + "\t\t\tоригинальные файлы<br /><br />\n"
        + '\t\t\t<span style="color: darkred; font-weight: bold">Нужно поставить на\n'
        + "\t\t\tраздачу именно торрент, скачанный с трекера, а не тот, что вы\n"
        + "\t\t\tсоздали.</span>\n"
        + "\t\t</div>\n"
        + '\t\t<div class="mrg_12"><p class="mrg_10">'
        + f'<a href="viewtopic.php?t={topic_id}">Вернуться в тему</a></p>'
        + f'<p class="mrg_10"><a href="viewforum.php?f={forum_id}">'
        + "Вернуться в форум</a></p></div>\n"
        + "\t</td></tr>\n</table>\n</body>\n</html>\n"
    )


def forum_page(forum_id):
    """The page the forum name is read from. The words are this server's own,
    because the recording has no forum page; the shape is not. A run against the
    site showed the page writing the breadcrumb as a table cell with the `nav`
    class, which is what the app's rule reads (`ai/uploading_draft.md` §4), so
    that is the shape this server writes. The page writes the cell twice, at the
    top and at the bottom, and the app reads the first, which is what is written
    here. A title alone would not be read, because the rule reads the
    breadcrumb, not the title."""
    name = f"Pornolab stub forum {forum_id}"

    return (
        page_head(name)
        + "<table>\n<tr>\n"
        + '<td class="nav nav-top" width="100">\n'
        + '<a href="./index.php">Список форумов</a>\n'
        + '<em>&raquo;</em> '
        + f'<a href="viewforum.php?f={forum_id}">{html.escape(name)}</a>\n'
        + "</td>\n</tr>\n</table>\n</body>\n</html>\n"
    )


def error_page(message):
    """A shape this server has and the site is not known to have. The app reads
    the block, and a page without it is one result until the site's own shape is
    seen (`ai/pornolab_upload.md` §5), so what a test can be run against here is
    the fact that the block is not there, not this wording."""
    return (
        page_head()
        + '<table class="forumline message">\n'
        + "\t<tr><th>Ошибка</th></tr>\n"
        + f"\t<tr><td>{html.escape(message)}</td></tr>\n"
        + "</table>\n</body>\n</html>\n"
    )


class Store:
    """The topics this server has been given, and the file that was sent for
    each. The file served back is built from what is stored here, which is the
    point of keeping it."""

    def __init__(self):
        self.lock = threading.Lock()
        self.topics = {}
        self.next_topic_id = TOPIC_ID_START

    def add(self, data):
        with self.lock:
            topic_id = self.next_topic_id
            self.next_topic_id += 1
            self.topics[topic_id] = data
            return topic_id

    def get(self, topic_id):
        return self.topics.get(topic_id)


class StubServer(ThreadingHTTPServer):
    """Threaded, because the app makes a run per tab, and two tabs can be
    open."""

    daemon_threads = True

    def __init__(self, port):
        super().__init__(("127.0.0.1", port), StubHandler)
        self.store = Store()


class StubHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        url = urlparse(self.path)

        if not self.headers.get("Cookie"):
            self._refused(url)
            return

        query = parse_qs(url.query)

        if url.path == "/forum/posting.php":
            self._log(f"GET {self.path} -> the form page")
            self._page(form_page(query))
            return

        if url.path == "/forum/viewforum.php":
            raw = (query.get("f") or [""])[0]

            if not raw.isdigit():
                self._page(error_page("no forum with that id"))
                return

            self._log(f"GET {self.path} -> the forum page")
            self._page(forum_page(int(raw)))
            return

        if url.path != "/forum/dl.php":
            self._page(error_page(ANSWERED))
            return

        raw = (query.get("t") or [""])[0]

        if not raw.isdigit():
            self._page(error_page("no topic with that id"))
            return

        topic_id = int(raw)
        data = self.server.store.get(topic_id)

        if data is None:
            self._page(error_page("no topic with that id"))
            return

        body = tracker_file(data, topic_id)
        name = f"[pornolab.net].t{topic_id}.torrent"
        self._log(f"GET {self.path} -> {name}, {len(body)} bytes")
        self._attachment(body, name)

    def do_POST(self):
        url = urlparse(self.path)

        # The body is read before anything is answered. A server that answers
        # without reading it leaves the connection out of step: the next thing
        # it reads is the body as a request line, and the client is told a
        # response came without a request. A run is several calls on one
        # connection, so the first call that is not answered takes the ones
        # after it with it.
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))

        if not self.headers.get("Cookie"):
            self._refused(url)
            return

        if url.path != "/forum/posting.php":
            self._page(error_page("the stub answers posting.php"))
            return

        boundary = re.search(
            r'boundary="?([^";]+)"?', self.headers.get("Content-Type", "")
        )

        if not boundary or not body:
            self._page(error_page("not a multipart form"))
            return

        fields, file_part = parse_multipart(body, boundary.group(1))

        if fields.get("form_token") != TOKEN:
            self._page(error_page("the form token was not accepted"))
            return

        if file_part is None:
            self._page(error_page("no file"))
            return

        _, filename, content = file_part

        if not filename.lower().endswith(EXTENSIONS):
            self._page(error_page("not one of the extensions the form declares"))
            return

        limit = int(fields.get("MAX_FILE_SIZE") or MAX_FILE_SIZE)

        if len(content) > limit:
            self._page(error_page("the file is over the limit the form declares"))
            return

        try:
            bdecode(content)
        except ValueError:
            self._page(error_page("the file is not a bencoded torrent"))
            return

        topic_id = self.server.store.add(content)

        os.makedirs(POSTED_DIR, exist_ok=True)
        stored = os.path.join(POSTED_DIR, f"{topic_id}.torrent")
        with open(stored, "wb") as out:
            out.write(content)

        self._log(
            f"POST {self.path} -> topic {topic_id}, {len(content)} bytes, "
            f"stored as {stored}"
        )
        self._page(block_page(topic_id, fields.get("f", "0")))

    def _refused(self, url):
        """The behaviour `ai/uploading_draft.md` §6 states rather than something
        a recording of a post shows. The location is written as a path, which
        the app's rule reads the same way as the full URL the site sends.

        The page the redirect points at is not answered here, so a request for
        it gets the page that says what is answered. A redirect whose target
        answers with the same redirect is a chain a browser follows forever,
        and each hop puts the value it was given inside another
        `login.php?redirect=`, so the chain grows and never ends. Answering
        the target as not answered is what ends it.
        """
        name = url.path.rsplit("/", 1)[-1]

        if name == "login.php":
            self._log(f"{self.command} {self.path} -> no cookie, not answered here")
            self._page(error_page(ANSWERED))
            return

        redirect = f"{name}?{url.query}" if url.query else name

        self._log(f"{self.command} {self.path} -> no cookie, the login page")
        self.send_response(302)
        self.send_header("Location", f"/forum/login.php?redirect={redirect}")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _page(self, text, status=200):
        body = text.encode(CHARSET, "replace")
        self.send_response(status)
        self.send_header("Content-Type", f"text/html; charset={CHARSET}")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _attachment(self, body, name):
        self.send_response(200)
        self.send_header("Content-Type", f'application/x-bittorrent; name="{name}"')
        self.send_header("Content-Disposition", f'attachment; filename="{name}"')
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _log(self, line):
        print(line, flush=True)


def main():
    parser = argparse.ArgumentParser(
        description="Answers as PornoLab for the three requests a post is made of."
    )
    parser.add_argument("--port", type=int, default=40002, help="the port to serve on")
    args = parser.parse_args()

    print(f"pornolab-stub on http://127.0.0.1:{args.port}", flush=True)
    print(
        f"the values the document uses: topic id from {TOPIC_ID_START}, "
        f"user id {USER_ID}, name {NAME}, key {ANNOUNCE_KEY}",
        flush=True,
    )
    print(f"uploaded files go to {POSTED_DIR} (gitignored)", flush=True)

    server = StubServer(args.port)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("stopped", flush=True)
        return 0


if __name__ == "__main__":
    sys.exit(main())
