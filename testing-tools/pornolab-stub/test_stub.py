#!/usr/bin/env python3
"""The shapes this server answers with, checked against it. Standard library
only; the precondition is python3.

    python3 testing-tools/pornolab-stub/test_stub.py

The tests start the server themselves, on a port the operating system gives, so
a run does not need the port the stub serves on by default and does not conflict
with a running stub. What a POST stores is written to a temporary folder, so a
run leaves nothing beside the script.

One post is made as the fixture, because the tests that check what a topic is
served back for need a topic to read. It is the first post the server sees, so
its answer is the id the document's example uses. Every other test makes its own
request, so what one test sees is not what another left behind.

The wording a test asserts is this server's own for the shapes the recording has
no example of, as the list in `README.md` says. What the app reads is the block,
so a test that asserts the block is there is asserting the site's shape — the
same is true of the breadcrumb cell, which is the shape a run against the site
showed a page writing.

A change to the server is not reported as done while one of these fails. A
failure says either that the change is not the shape `README.md` records, or
that the shape was changed on purpose, in which case the check and the document
are changed with it, in the same change.
"""

import http.client
import os
import re
import shutil
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

import rp_pornolab_stub as stub

COOKIE = "bb_data=1-40000111-stubkey-1; testCookie=1"
BOUNDARY = "----geckoformboundarystub"

TORRENT = stub.bencode({
    b"created by": b"mkbrr/1.27.0 (https://github.com/autobrr/mkbrr)",
    b"creation date": 1794040663,
    b"info": {
        b"length": 9281547387,
        b"name": b"Test.Release.2160p.mp4",
        b"piece length": 8388608,
        b"pieces": b"\x01\x02\x03\x04",
        b"private": 1,
    },
})

# The form as the recording sent it, so the values the parse is checked against
# are the values a browser put in the form.
FIELDS = [
    ("mode", "newtopic"),
    ("f", "1857"),
    ("t", "0"),
    ("p", "0"),
    ("draft_id", "11818"),
    ("subject", "[Test] May Thai (GP2352)"),
    ("topic_tags", ""),
    ("fontFace", "-1"),
    ("codeColor", "black"),
    ("codeSize", "12"),
    ("align", "-1"),
    ("codeUrl", ""),
    ("message", "[b]В ролях[/b]: May Thai\n[b]Жанр[/b]: Жан"),
    ("MAX_FILE_SIZE", "1048576"),
    ("post", "1"),
    ("decflag", "2"),
    ("form_token", stub.TOKEN),
]

SERVER = None
BASE = ""
STORED_DIR = ""
ANSWER = ""
TOPIC_ID = None


def form_body(fields, file_part=None):
    """The body as a browser sends it: the values in the charset the page is
    in."""
    parts = []

    for name, value in fields:
        parts.append(
            f"--{BOUNDARY}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n"
            + value.encode("cp1251", "replace").decode("latin-1")
            + "\r\n"
        )

    if file_part:
        name, filename, content = file_part
        parts.append(
            f"--{BOUNDARY}\r\nContent-Disposition: form-data; name=\"{name}\"; "
            f'filename="{filename}"\r\nContent-Type: application/x-bittorrent\r\n\r\n'
            + content.decode("latin-1")
            + "\r\n"
        )

    return ("".join(parts) + f"--{BOUNDARY}--\r\n").encode("latin-1")


def text(response):
    """A page as the text it declares itself to be. A file is returned as
    bytes."""
    body = response.read()

    if "charset=" in response.headers.get("Content-Type", ""):
        return body.decode("cp1251", "replace")

    return body


def topic_id_from(answer):
    """The id the block carries, as the app reads it: from the download link."""
    return int(re.search(r"dl\.php\?t=(\d+)", answer).group(1))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def get(path, cookie=COOKIE, follow=True):
    req = urllib.request.Request(f"{BASE}{path}")

    if cookie:
        req.add_header("Cookie", cookie)

    if not follow:
        return urllib.request.build_opener(NoRedirect).open(req)

    return urllib.request.urlopen(req)


def post(path, body, cookie=COOKIE):
    req = urllib.request.Request(f"{BASE}{path}", data=body, method="POST")
    req.add_header("Content-Type", f"multipart/form-data; boundary={BOUNDARY}")
    req.add_header("Content-Length", str(len(body)))

    if cookie:
        req.add_header("Cookie", cookie)

    return urllib.request.urlopen(req)


def one_hop(path, cookie=COOKIE):
    """One request, not followed, as a browser would read the first hop of a
    redirect."""
    try:
        return get(path, cookie=cookie, follow=False)
    except urllib.error.HTTPError as error:
        return error


def submit(fields, file_part=None, cookie=COOKIE):
    """One submission, answered as the block or as the page that says what went
    wrong."""
    return text(post("/posting.php", form_body(fields, file_part), cookie))


def served(topic_id=None):
    """The answer for a topic, as the response is: its bytes and its headers."""
    return get(f"/dl.php?t={topic_id or TOPIC_ID}")


def setUpModule():
    global SERVER, BASE, STORED_DIR, ANSWER, TOPIC_ID

    # The logging is turned off for the run: a test reports what it checked, and
    # a line for every request over that is not what a run here is for.
    stub.StubHandler.log_message = lambda *args: None
    stub.StubHandler._log = lambda self, line: None

    # What a POST stores is written here rather than beside the script, so a run
    # leaves nothing in the tree.
    STORED_DIR = tempfile.mkdtemp()
    stub.POSTED_DIR = STORED_DIR

    SERVER = stub.StubServer(0)
    BASE = f"http://127.0.0.1:{SERVER.server_port}/forum"
    threading.Thread(target=SERVER.serve_forever, daemon=True).start()

    # The fixture: the form with the file attached, answered as the block.
    ANSWER = submit(FIELDS, ("attach", "test.torrent", TORRENT))
    TOPIC_ID = topic_id_from(ANSWER)


def tearDownModule():
    SERVER.shutdown()
    SERVER.server_close()
    shutil.rmtree(STORED_DIR)


class StubTest(unittest.TestCase):
    # The parse, checked directly.

    def test_the_form_is_read_in_the_charset_the_form_is_sent_in(self):
        fields, _ = stub.parse_multipart(
            form_body(FIELDS, ("attach", "test.torrent", TORRENT)), BOUNDARY
        )

        self.assertEqual(
            fields["message"], "[b]В ролях[/b]: May Thai\n[b]Жанр[/b]: Жан"
        )

    def test_the_file_part_is_kept_as_its_bytes(self):
        _, file_part = stub.parse_multipart(
            form_body(FIELDS, ("attach", "test.torrent", TORRENT)), BOUNDARY
        )

        self.assertIsNotNone(file_part)
        self.assertEqual(file_part[2], TORRENT)

    # The page the token comes from.

    def test_the_page_declares_the_charset_the_recording_declares(self):
        response = get("/posting.php?mode=newtopic&f=1857&draft=11818")

        self.assertIn("charset=windows-1251", response.headers["Content-Type"])

    def test_the_token_is_the_assignment_the_recording_has(self):
        page = text(get("/posting.php?mode=newtopic&f=1857&draft=11818"))
        token = re.search(r"ajax\.form_token = '([0-9a-f]+)'", page)

        self.assertIsNotNone(token, "the page has no token assignment")
        self.assertEqual(token.group(1), stub.TOKEN)

    def test_the_page_names_the_account_with_the_values_the_document_uses(self):
        page = text(get("/posting.php?mode=newtopic&f=1857&draft=11818"))

        self.assertIn(stub.NAME, page)
        self.assertIn(f"u={stub.USER_ID}", page)

    def test_the_form_the_page_draws_has_the_file_field_and_its_limit(self):
        page = text(get("/posting.php?mode=newtopic&f=1857&draft=11818"))

        self.assertIn('name="attach"', page)
        self.assertIn(str(stub.MAX_FILE_SIZE), page)

    # The submission, as the fixture made it.

    def test_the_answer_is_the_block_with_the_recordings_wording(self):
        self.assertIn("Торрент зарегистрирован на трекере", ANSWER)

    def test_the_block_carries_the_id_the_documents_example_uses(self):
        self.assertEqual(TOPIC_ID, stub.TOPIC_ID_START)
        self.assertIn(f"dl.php?t={stub.TOPIC_ID_START}", ANSWER)
        self.assertIn(f"viewtopic.php?t={stub.TOPIC_ID_START}", ANSWER)

    def test_the_block_names_the_forum_the_form_was_sent_for(self):
        self.assertIn("viewforum.php?f=1857", ANSWER)

    # The page the forum name is read from.

    def test_the_forum_page_names_the_forum_the_id_is_for(self):
        page = text(get("/viewforum.php?f=1857"))

        self.assertIn("Pornolab stub forum 1857", page)

    def test_the_breadcrumb_link_the_apps_rule_reads_carries_that_name(self):
        page = text(get("/viewforum.php?f=1857"))

        self.assertIn(
            '<a href="viewforum.php?f=1857">Pornolab stub forum 1857</a>',
            page,
        )

    def test_the_breadcrumb_is_the_cell_the_apps_rule_reads(self):
        page = text(get("/viewforum.php?f=1857"))

        # The shape a run against the site showed a page writing, which is what
        # the app reads. A page writes the cell twice and the app reads the
        # first, so this server writes the first as the site does.
        self.assertIn('<td class="nav nav-top" width="100">', page)

    def test_the_title_carries_the_same_words_as_the_breadcrumb(self):
        page = text(get("/viewforum.php?f=1857"))

        self.assertIn("<title>Pornolab stub forum 1857</title>", page)

    def test_a_forum_id_that_is_not_a_number_is_refused(self):
        self.assertIn(
            "no forum with that id", text(get("/viewforum.php?f=abc"))
        )

    # The file the tracker serves back.

    def test_the_served_file_is_the_file_that_was_sent_re_encoded(self):
        self.assertGreater(len(served().read()), len(TORRENT))

    def test_the_info_dictionary_is_the_one_that_was_sent(self):
        decoded = stub.bdecode(served().read())
        sent = stub.bdecode(TORRENT)

        self.assertEqual(decoded[b"info"], sent[b"info"])

    def test_the_four_keys_the_recording_shows_are_added(self):
        keys = (b"announce", b"comment", b"publisher", b"publisher-url")

        for key in keys:
            self.assertIn(key, stub.bdecode(served().read()))

    def test_the_keys_are_written_in_sorted_order(self):
        decoded = stub.bdecode(served().read())

        self.assertEqual(list(decoded.keys()), sorted(decoded.keys()))

    def test_the_name_the_file_is_served_with_is_the_recordings_shape(self):
        self.assertIn(
            f'filename="[pornolab.net].t{TOPIC_ID}.torrent"',
            served().headers.get("Content-Disposition", ""),
        )

    def test_what_is_stored_is_the_file_as_it_was_sent(self):
        path = os.path.join(stub.POSTED_DIR, f"{TOPIC_ID}.torrent")

        with open(path, "rb") as stored:
            self.assertEqual(stored.read(), TORRENT)

    # A request with no cookie, and the chain that follows it.

    def test_a_request_with_no_cookie_is_the_login_page_redirect(self):
        hop = one_hop("/posting.php?mode=newtopic&f=1857", cookie="")

        self.assertEqual(hop.code, 302)
        self.assertEqual(
            hop.headers.get("Location"),
            "/forum/login.php?redirect=posting.php?mode=newtopic&f=1857",
        )

    def test_the_chain_ends_at_the_page_the_redirect_points_at(self):
        # A browser follows the location, so the chain has to end at a page. The
        # page it points at is the login, which this server does not answer, so
        # that page says what is answered rather than redirecting again. While
        # it answered with the same redirect the chain never ended: every hop
        # put the value it was given inside another `login.php?redirect=`, and a
        # browser followed it forever. A check that reads one hop cannot see
        # that, so the second hop is read here.
        first = one_hop("/", cookie="")

        self.assertEqual(first.code, 302)
        self.assertEqual(
            first.headers.get("Location"), "/forum/login.php?redirect="
        )

        second = one_hop("/login.php?redirect=", cookie="")

        self.assertEqual(second.code, 200)
        self.assertIn("the stub answers", text(second))

    # The shapes this server has because the recording has no example of them.

    def test_a_submission_with_no_file_is_refused(self):
        self.assertIn("no file", submit(FIELDS, None))

    def test_a_file_that_is_not_a_bencoded_torrent_is_refused(self):
        answer = submit(FIELDS, ("attach", "test.rar", b"not bencoded"))

        self.assertIn("not a bencoded torrent", answer)

    def test_an_extension_the_form_does_not_declare_is_refused(self):
        self.assertIn(
            "extensions", submit(FIELDS, ("attach", "test.txt", TORRENT))
        )

    def test_a_file_over_the_limit_the_form_declares_is_refused(self):
        answer = submit(FIELDS, ("attach", "big.torrent", b"x" * 1048577))

        self.assertIn("over the limit", answer)

    def test_a_token_the_page_did_not_give_is_refused(self):
        fields = [(n, "wrong" if n == "form_token" else v) for n, v in FIELDS]
        answer = submit(fields, ("attach", "test.torrent", TORRENT))

        self.assertIn("form token", answer)

    def test_an_id_with_no_file_here_is_refused(self):
        self.assertIn("no topic with that id", text(get("/dl.php?t=9999999")))

    def test_a_request_that_is_not_answered_is_still_read(self):
        # A run is several calls on one connection, so a request that is
        # answered without being read takes the calls after it with it: the next
        # thing the server reads is the body as a request line, and the client
        # is told a response came without a request.
        connection = http.client.HTTPConnection("127.0.0.1", SERVER.server_port)

        try:
            connection.request(
                "POST",
                "/forum/ajax.php",
                body=b"action=topic_draft&mode=save&form_token=x",
                headers={
                    "Cookie": COOKIE,
                    "Content-Type": "application/x-www-form-urlencoded",
                },
            )
            connection.getresponse().read()

            connection.request(
                "GET", "/forum/dl.php?t=9999999", headers={"Cookie": COOKIE}
            )
            kept = connection.getresponse().read().decode("cp1251")

            self.assertIn("no topic with that id", kept)
        finally:
            connection.close()


if __name__ == "__main__":
    unittest.main()
