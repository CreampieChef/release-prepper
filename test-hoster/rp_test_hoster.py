#!/usr/bin/env python3
"""A tiny photo hoster for testing Release Prepper.

    python3 test-hoster/rp_test_hoster.py --latency 200 --success-rate 0.9
    [--port 80]

Every upload takes `latency` milliseconds on average, each one deviating by up to
half either way, and succeeds with probability `success_rate`. Serving is not
simulated: a stored file, a thumbnail, a view page and a delete are answered at
once, so reading the images back is not throttled. The test hosters in
`Data/servers.xml` (`rptest-a`, `rptest-b`) call this server with their
own tag, so one server answers as several hosters; the scripts hardcode the default
http port, because the URLs this server reports must be on it — PornoLab does not
render images hosted on other ports — so a reported URL carries no port suffix, and
a different `--port` needs the scripts changed too. Port 80 needs elevated
privileges.

Files are stored under `photos/<tag>/` next to this script — the original name with
a random id before the extension — and served back from the same URL the upload
response reports.

Needs ffmpeg on PATH to make the thumbnail; without it an upload fails.
"""

import argparse
import html
import json
import mimetypes
import os
import random
import re
import shutil
import string
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
PHOTOS_DIR = os.path.join(HERE, "photos")

# A tag and a stored name are both parts of a URL path, so both are kept to the
# characters that cannot be read back differently.
SAFE = re.compile(r"[A-Za-z0-9._-]+")
ID_CHARS = string.ascii_lowercase + string.digits


class Config:
    def __init__(self, latency, success_rate, port):
        # The reported URLs must not carry a port suffix on the default port, because
        # that is the only shape the site renders.
        url_port_suffix = "" if port == 80 else ":" + str(port)
        self.latency = latency
        self.success_rate = success_rate
        self.port = port
        self.base_url = f"http://127.0.0.1{url_port_suffix}"

    def delay(self):
        """The delay for one upload, in milliseconds: the average, deviating by up to half either way."""
        return random.uniform(self.latency * 0.5, self.latency * 1.5)

    def upload_succeeds(self):
        return random.random() < self.success_rate


class TestServer(ThreadingHTTPServer):
    """Threaded, because several hosters call the same server at the same time."""

    daemon_threads = True

    def __init__(self, config):
        super().__init__(("127.0.0.1", config.port), HosterHandler)
        self.config = config


class HosterHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        config = self.server.config
        # An upload is the simulated part of this server: it takes the delay and the
        # success rate. Serving does not, see do_GET.
        delay = self._delay()

        if urlparse(self.path).path != "/upload":
            self._error(404, "no upload at this path", delay)
            return

        boundary = re.search(r'boundary="?([^";]+)"?', self.headers.get("Content-Type", ""))
        length = int(self.headers.get("Content-Length", 0))
        if not boundary or length == 0:
            self._error(400, "not a multipart form", delay)
            return

        fields, file_part = _parse_multipart(self.rfile.read(length), boundary.group(1))
        tag = fields.get("tag", "")
        if not SAFE.fullmatch(tag):
            self._error(400, "bad tag", delay)
            return
        if file_part is None:
            self._error(400, "no file", delay)
            return

        if not config.upload_succeeds():
            self._log(f"POST /upload {tag}/{file_part[1]} -> failed", delay)
            self._json({"success": False, "error": "upload failed"})
            return

        stem, ext = _split_name(file_part[1])
        identifier = "".join(random.choices(ID_CHARS, k=8))
        stored = f"{stem}_{identifier}{ext}"
        thumb = f"{stem}_{identifier}_thumb.jpg"

        directory = os.path.join(PHOTOS_DIR, tag)
        os.makedirs(directory, exist_ok=True)
        stored_path = os.path.join(directory, stored)
        with open(stored_path, "wb") as out:
            out.write(file_part[2])

        width = _thumb_width(fields.get("thumb_width", ""))
        if not _make_thumb(stored_path, os.path.join(directory, thumb), width):
            self._error(500, "thumbnail failed", delay)
            return

        base = config.base_url
        self._log(f"POST /upload {tag}/{file_part[1]} -> {tag}/{stored}", delay)
        self._json(
            {
                "success": True,
                "filename": stored,
                "delete_url": f"{base}/{tag}/{stored}?delete=1",
                "direct_url": f"{base}/{tag}/{stored}",
                "thumb_url": f"{base}/{tag}/{thumb}",
                "view_url": f"{base}/{tag}/{stored}.html",
            }
        )

    def do_GET(self):
        # Serving is not simulated: there is no delay to wait and no failure to draw, so
        # the request is answered at once and the log reports the time it took as none.
        delay = 0.0

        request = urlparse(self.path)
        parts = [unquote(part) for part in request.path.split("/") if part]
        if len(parts) != 2 or not SAFE.fullmatch(parts[0]):
            self._error(404, "not found", delay)
            return

        tag, name = parts
        directory = os.path.join(PHOTOS_DIR, tag)

        if name.endswith(".html"):
            # The view page is not a stored file; it is the page for one.
            stored = name[:-len(".html")]
            if not os.path.isfile(os.path.join(directory, stored)):
                self._error(404, "not found", delay)
                return
            self._log(f"GET {request.path}", delay)
            self._respond(200, _view_page(tag, stored))
            return

        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            self._error(404, "not found", delay)
            return

        if request.query == "delete=1":
            targets = [path]
            if not name.endswith("_thumb.jpg"):
                targets.append(_thumb_path(path))
            deleted = []
            try:
                for target in targets:
                    if os.path.isfile(target):
                        os.remove(target)
                        deleted.append(os.path.basename(target))
            except OSError as error:
                self._error(500, f"delete failed: {error}", delay)
                return
            self._log(f"GET {request.path} -> {', '.join(deleted)}", delay)
            self._json({"success": True, "deleted": deleted})
            return

        mime = mimetypes.guess_type(name)[0] or "application/octet-stream"
        with open(path, "rb") as source:
            self._log(f"GET {request.path}", delay)
            self._respond(200, source.read(), mime)

    def _delay(self):
        """Wait the delay an upload gets, and report it so the log can say it."""
        delay = self.server.config.delay()
        time.sleep(delay / 1000)
        return delay

    def _json(self, value):
        self._respond(200, json.dumps(value).encode(), "application/json")

    def _error(self, status, message, delay):
        self._log(f"{self.command} {self.path} -> {status} {message}", delay)
        self._respond(status, _text(message))

    def _respond(self, status, body, content_type="text/plain; charset=utf-8"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _log(self, message, delay):
        print(f"{message} ({delay:.0f} ms)", flush=True)

    def log_message(self, format, *args):
        """The default per-request line is replaced by the one this server logs itself."""


def _parse_multipart(body, boundary):
    """The fields and the file part of a multipart form, as uptooda sends them."""
    fields = {}
    file_part = None
    for raw in body.split(b"--" + boundary.encode()):
        if raw.startswith(b"--"):
            continue  # the closing marker
        raw = raw.lstrip(b"\r\n")
        if not raw:
            continue
        head, _, content = raw.partition(b"\r\n\r\n")
        if content.endswith(b"\r\n"):
            content = content[:-2]  # the delimiter before the next boundary
        disposition = next(
            (
                line
                for line in head.split(b"\r\n")
                if line.lower().startswith(b"content-disposition")
            ),
            None,
        )
        if disposition is None:
            continue
        name_match = re.search(rb'name="([^"]*)"', disposition)
        if name_match is None:
            continue
        name = name_match.group(1).decode()
        filename_match = re.search(rb'filename="([^"]*)"', disposition)
        if filename_match:
            file_part = (name, filename_match.group(1).decode(), content)
        else:
            fields[name] = content.decode()
    return fields, file_part


def _split_name(filename):
    """The name as it is stored: the given name with a random id before the extension."""
    stem, ext = os.path.splitext(os.path.basename(filename))
    stem = re.sub(r"[^\w.\-]", "_", stem) or "file"
    ext = re.sub(r"[^\w.\-]", "", ext).lower()
    return stem, ext


def _thumb_width(value):
    try:
        return max(1, int(value))
    except ValueError:
        return 300


def _thumb_path(path):
    stem, _ = os.path.splitext(path)
    return f"{stem}_thumb.jpg"


def _make_thumb(source, target, width):
    try:
        subprocess.run(
            [
                "ffmpeg",
                "-loglevel",
                "error",
                "-y",
                "-i",
                source,
                "-vf",
                f"scale={width}:-2",
                target,
            ],
            check=True,
        )
        return True
    except (FileNotFoundError, subprocess.CalledProcessError) as error:
        print(f"ffmpeg failed for {source}: {error}", file=sys.stderr, flush=True)
        return False


def _view_page(tag, name):
    link = f"/{tag}/{name}"
    return (
        f"<!doctype html><title>{html.escape(name)}</title>"
        f"<p><img src=\"{link}\" alt=\"{html.escape(name)}\"></p>"
        f"<p><a href=\"{link}\">{html.escape(name)}</a></p>"
    ).encode()


def _text(message):
    return message.encode()


def main():
    parser = argparse.ArgumentParser(
        description="A tiny photo hoster that answers as a test hoster for Release Prepper."
    )
    parser.add_argument(
        "--latency",
        type=float,
        default=200.0,
        help="average upload latency in milliseconds, each upload deviating by up to 50%%",
    )
    parser.add_argument(
        "--success-rate",
        type=float,
        default=1.0,
        help="probability an upload succeeds, 0 to 1",
    )
    parser.add_argument("--port", type=int, default=80)
    args = parser.parse_args()

    if not 0.0 <= args.success_rate <= 1.0:
        parser.error("--success-rate must be between 0 and 1")
    if args.latency < 0:
        parser.error("--latency must not be negative")

    config = Config(args.latency, args.success_rate, args.port)
    print(f"test hoster on {config.base_url}, photos in {PHOTOS_DIR}")
    print(f"average upload latency {args.latency} ms (+-50%), upload success rate {args.success_rate}")
    if shutil.which("ffmpeg") is None:
        print("warning: ffmpeg is not on PATH, so uploads cannot make a thumbnail", file=sys.stderr)

    server = TestServer(config)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("stopped", flush=True)


if __name__ == "__main__":
    main()
