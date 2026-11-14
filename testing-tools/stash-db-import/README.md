# stash-db-import

A page and a small server that record one StashDB scene as data a test can use.
Standard library only, and run by hand:

    python3 testing-tools/stash-db-import/rp_stash_capture.py [--port 40001]

The form takes an API key, a scene URL or scene ID, and the subsite and site the
values should come out as. On "Create test data" the server asks StashDB for
that scene — the same endpoint, the same fields as `StashClient.query` with the
additions described below, the key in the `ApiKey` header stash-box reads — and
writes `captured/<scene id>.json` (gitignored), one file per scene:

```json
{
  "sceneId": "…",
  "sceneUrl": "the text that was typed",
  "capturedAt": "2026-11-14T01:31:54+00:00",
  "expected": { "subsite": "…", "site": "…" },
  "response": { "data": { "findScene": { … } } }
}
```

The API key is not recorded. A file that is already there is not rewritten
unless the form asks, so a case is not lost by being entered again.

The response is kept as StashDB gave it, not as a summary of it: the order of a
studio's URL list and the category each URL is recorded under are what the rule
reads, so a shortened case is a different case. The expected values are kept
next to it because they are what a test asserts, and they are not in the
response.

What the page shows is the expected value and the value the rule gives for the
same data, so a wrong result is visible while a case is being entered. That is a
second copy of the rule, in Python, and the rule in
`lib/feature/stashdb/stash_controller.dart` is the one that counts — if the two
disagree, this copy is wrong, not there. The same for the fields the query asks
for, with the additions in the next two paragraphs, and for the scene ID rule:
keep them in step with the app, because a page that asks for different fields
records data the tests cannot read back as the app reads it.
This copy reads `assets/stashdb/domain_map.json`, because a domain the mapping
has is what the app writes for it.

The tool asks for the same fields the app's query asks for, which are the ones
the rule reads: the name of the site each URL is recorded under, and its
category. A studio's URL list holds links to other databases, so which site
record a URL belongs to is what says whether it is the studio's own site, and
within the Primary sources category the name is the only signal — the order the
response lists the URLs in does not say which is the studio's own.

It also asks for the ids of the studio, the parent and each site, which the app
does not. Neither can be the signal the rule uses, and a capture is what shows
that: a subsite and its parent share one site record, so a site id matches the
studio's id for the parent's page too, and a site's own URL is empty when the
record is the studio's. The name is the only signal, which is what the tool
compares the URLs by.

The files under `captured/` are the source of the test cases. A case is
committed as a fixture the tests read, so the tests run on a machine that has no
captures here. A fixture is the response trimmed to the fields the rule reads —
the studio and the parent, each URL with the site it is recorded under and that
site's category — plus the expected values, one file per case named after the
scene. A case that is the same shape as another is not kept twice, and nothing a
test cannot read is stored: the title, the code, the dates, the tags, the
performers, the images, the site's id and its own URL are not in a fixture,
because the rule does not read them.

A request answers as the app answers it: a response that is not 200, one that
reports GraphQL errors, one that is not the shape a GraphQL response has, and
one that answers with no scene are the four the page can show, and they are the
same conditions `StashClient.parseResponse` names.
