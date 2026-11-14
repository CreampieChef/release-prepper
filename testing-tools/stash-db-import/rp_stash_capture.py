#!/usr/bin/env python3
"""Records a real StashDB response as data a test can use, and shows the form
the app's rule gives for it.

    python3 testing-tools/stash-db-import/rp_stash_capture.py [--port 40001]

It serves a form that takes an API key, a scene URL, and the subsite and site
the values should come out as; on "Create test data" it asks StashDB for that
scene, the same way the app does, and records the response under `captured/`
(gitignored) as one file per scene, with the expected values. Those files are
what `test/fixtures/stashdb/` is built from.

What is recorded is the response as StashDB gave it, not what this tool thinks
the field should be: a test that guards a rule needs the input, and the expected
value is the one entered here, kept next to it. The API key is not recorded.

The tool also reports the value the rule gives for the same data, so the
difference between what is expected and what the app produces is visible while a
case is being entered. That is a second copy of the rule, in Python, and the
rule in `lib/feature/stashdb/stash_controller.dart` is the one that counts; if
the two disagree, this copy is wrong, not there. It reads the domain mapping the
app ships, because a domain the mapping has is what the app writes.
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
CAPTURED_DIR = os.path.join(HERE, "captured")
INDEX = os.path.join(HERE, "index.html")

# The file the app reads for the domains it writes in a form of its own, so the
# value this tool reports is the one the app would write.
DOMAIN_MAP = os.path.normpath(
    os.path.join(HERE, "..", "..", "assets", "stashdb", "domain_map.json")
)

ENDPOINT = "https://stashdb.org/graphql"

# The one query, the same text the app sends (`StashClient.query`). It has to
# stay in step with it: a query that asks for different fields records data the
# tests cannot read back as the app reads it. The site each URL is recorded
# under is asked for with its name, its own URL and its category, because that
# is what says which site a URL belongs to; the app asks for the category only,
# so a capture with the app's query cannot show it. The ids of the studio, the
# parent and each site are asked for so a capture can show whether a site record
# is the studio's own record, rather than a record with a name to compare.
QUERY = r"""query($id: ID!) {
  findScene(id: $id) {
    id
    title
    code
    details
    release_date
    production_date
    studio {
      id
      name
      urls { url site { id name url category { name } } }
      parent { id name urls { url site { id name url category { name } } } }
    }
    tags { name }
    performers { as performer { name } }
    images { url }
  }
}"""

UUID = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I
)

# A recorded file is named after the scene, so a path that asks for one is a
# name that cannot be read as anything else — not a path outside the directory.
RECORDED = re.compile(r"^[0-9a-f-]{36}\.json$", re.I)

# The names the app compares against (`StashController`).
PRIMARY_SOURCE_CATEGORY = "Primary sources"
STUDIO_SITE_NAME = "Studio"


def scene_id(text):
    """The scene id from what was pasted: a UUID, or the last part of a scene
    URL. The same rule as `StashController.sceneId`."""
    text = text.strip()

    if UUID.match(text):
        return text.lower()

    try:
        parsed = urlparse(text if "://" in text else "https://" + text)
    except ValueError:
        return None

    segments = [part for part in parsed.path.split("/") if part]

    if not segments:
        return None

    last = segments[-1]

    return last.lower() if UUID.match(last) else None


def string(value):
    """A part the response does not report is empty, the same rule as the app's
    parser, so a case with no studio reads as nothing rather than as a guess."""
    return value if isinstance(value, str) else ""


def studio(node):
    """One studio as the response reports it: the name, and each URL with the
    site it is recorded under and that site's category."""
    node = node if isinstance(node, dict) else {}

    node = node if isinstance(node, dict) else {}
    urls = []

    for entry in node.get("urls") or []:
        if not isinstance(entry, dict):
            continue

        site = entry.get("site") or {}

        urls.append(
            {
                "url": string(entry.get("url")),
                "siteName": string(site.get("name")),
                "categoryName": string(
                    (site.get("category") or {}).get("name")
                ),
            }
        )

    return {"name": string(node.get("name")), "urls": urls}


def host(url):
    """The host of one URL, without `www.`. A value with no scheme is read as a
    host, as the app reads it. Nothing when there is no host to read."""
    text = url.strip()

    if not text:
        return None

    try:
        parsed = urlparse(text if "://" in text else "https://" + text)
    except ValueError:
        return None

    name = parsed.hostname

    if not name:
        return None

    return name[4:] if name.startswith("www.") else name


def source(st, domains):
    """The URL the domain is read from, with its host, or None. The same rule as
    `StashController._source`: the URLs in the Primary sources category are the
    candidates, and within them the one whose host is named for the studio,
    because a studio with a parent can have a URL in that category that is the
    parent's page; when nothing in the category is named for the studio, the
    first is what is read. Then the URL recorded under the site named Studio,
    then the first URL with a host. A URL with no host is not a candidate at any
    step."""
    first = None
    primary = None
    named = None
    site = None

    for url in st["urls"]:
        read = host(url["url"])

        if read is None:
            continue

        candidate = (url, read)

        if first is None:
            first = candidate

        if url["siteName"] == STUDIO_SITE_NAME and site is None:
            site = candidate

        if url["categoryName"] == PRIMARY_SOURCE_CATEGORY:
            if primary is None:
                primary = candidate

            if named is None and name_word(st["name"]) == first_label(read):
                named = candidate

    return named or primary or site or first


def first_label(host):
    """The part of a host a studio name is compared with, as the app compares
    it: the first label, or the whole host when there is no dot."""
    dot = host.find(".")

    return host if dot <= 0 else host[:dot]


def name_word(name):
    """The studio name as the word that comparison is made with."""
    return name.replace(" ", "").lower()


def domain(st, domains):
    """The domain as the app writes it: the mapping first, then the host with
    the name's capitalization when the name is the same word as the host's
    label. The same rule as `StashController._domain`."""
    read = source(st, domains)

    if read is None:
        return st["name"]

    _, host_name = read

    if host_name in domains:
        return domains[host_name]

    label = first_label(host_name)

    if label == host_name:
        return host_name

    rest = host_name[len(label):]

    return (
        st["name"].replace(" ", "") + rest
        if name_word(st["name"]) == label
        else host_name
    )


def record(api_key, scene_url):
    """One request to StashDB, answered as the app answers it: the same
    endpoint, the same query, and the key in the `ApiKey` header stash-box
    reads."""
    scene_id_value = scene_id(scene_url)

    if not scene_id_value:
        return None, "invalidInput"

    if not api_key:
        return None, "noApiKey"

    request = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(
            {"query": QUERY, "variables": {"id": scene_id_value}},
        ).encode(),
        headers={"ApiKey": api_key, "Content-Type": "application/json"},
    )

    try:
        with urllib.request.urlopen(request) as response:
            if response.status != 200:
                return None, "requestFailed"

            payload = json.loads(response.read().decode())
    except (urllib.error.URLError, json.JSONDecodeError):
        # A response with an error status arrives as HTTPError, which is a
        # URLError, so the two are the same thing here: nothing was read.
        return None, "requestFailed"

    if not isinstance(payload, dict):
        return None, "badResponse"

    if isinstance(payload.get("errors"), list) and payload["errors"]:
        return None, "graphqlError"

    data = payload.get("data")

    if not isinstance(data, dict):
        return None, "badResponse"

    scene = data.get("findScene")

    if not isinstance(scene, dict):
        return None, "notFound"

    return scene, None


def load_domains():
    """The mapping, as the app reads it: an object of strings, nothing when the
    file is not there or does not parse."""
    try:
        with open(DOMAIN_MAP, encoding="utf-8") as handle:
            mapping = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return {}

    return {
        key: value for key, value in mapping.items() if isinstance(value, str)
    }


def capture(api_key, scene_url, expected, overwrite):
    """Ask for the scene, write the file, and report what the rule gives for
    it. A file that is already there is not rewritten unless the page asks, so a
    case is not lost; the difference is reported either way."""
    scene, failure = record(api_key, scene_url)

    if failure:
        return None, failure

    domains = load_domains()
    entry = studio(scene.get("studio"))
    parent = studio((scene.get("studio") or {}).get("parent"))
    id = scene["id"]

    current = {
        "subsite": domain(entry, domains),
        "site": domain(parent, domains),
    }

    # The value as the app writes it for a single video: the two parts with the
    # separator, or the domain alone when there is no parent.
    joined = current["subsite"]
    if parent["name"] or parent["urls"]:
        joined = f"{current['subsite']} / {current['site']}"

    path = os.path.join(CAPTURED_DIR, f"{id}.json")
    written = os.path.relpath(path, os.path.dirname(CAPTURED_DIR))
    exists = os.path.exists(path)

    if exists and not overwrite:
        return {
            "id": id,
            "file": written,
            "exists": True,
            "current": current,
            "currentValue": joined,
        }, None

    if not os.path.isdir(CAPTURED_DIR):
        os.makedirs(CAPTURED_DIR)

    record_data = {
        "sceneId": id,
        "sceneUrl": scene_url.strip(),
        "capturedAt": datetime.now(timezone.utc).isoformat(),
        "expected": expected,
        "response": {"data": {"findScene": scene}},
    }

    with open(path, "w", encoding="utf-8") as handle:
        json.dump(record_data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    return {
        "id": id,
        "file": written,
        "exists": False,
        "current": current,
        "currentValue": joined,
    }, None


class Handler(BaseHTTPRequestHandler):
    def json_response(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode()

        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            try:
                with open(INDEX, "rb") as handle:
                    body = handle.read()
            except OSError:
                self.json_response(500, {"error": "index.html is missing"})
                return

            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        # A recorded case is served back as it is stored, so the page can show
        # one, and so the file a test reads can be seen in the browser.
        name = ""
        if self.path.startswith("/captured/"):
            name = self.path[len("/captured/"):]

        if not RECORDED.match(name):
            self.json_response(404, {"error": "notFound"})
            return

        try:
            with open(os.path.join(CAPTURED_DIR, name), "rb") as handle:
                body = handle.read()
        except OSError:
            self.json_response(404, {"error": "notFound"})
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/capture":
            self.json_response(404, {"error": "notFound"})
            return

        length = int(self.headers.get("Content-Length", 0))

        try:
            form = json.loads(self.rfile.read(length))
        except json.JSONDecodeError:
            self.json_response(400, {"error": "badResponse"})
            return

        if not isinstance(form, dict):
            self.json_response(400, {"error": "badResponse"})
            return

        scene_url = string(form.get("sceneUrl"))
        expected = {
            "subsite": string(form.get("expectedSubsite")),
            "site": string(form.get("expectedSite")),
        }

        result, failure = capture(
            string(form.get("apiKey")),
            scene_url,
            expected,
            bool(form.get("overwrite")),
        )

        if failure:
            self.json_response(400, {"error": failure})
            return

        print(f"{result['id']} -> {result['file']}", flush=True)
        self.json_response(200, {"record": result, "expected": expected})

    def log_message(self, format, *args):
        # The per-request line is noise here: what matters is which scene was
        # recorded, and the capture prints that itself.
        pass


def main():
    parser = argparse.ArgumentParser(
        description="Records StashDB responses as test data for this project."
    )
    parser.add_argument(
        "--port", type=int, default=40001, help="the port to serve on"
    )
    args = parser.parse_args()

    print(f"stash-db-import on http://127.0.0.1:{args.port}", flush=True)
    print(f"records go to {CAPTURED_DIR} (gitignored)", flush=True)

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("stopped", flush=True)
        return 0


if __name__ == "__main__":
    sys.exit(main())
