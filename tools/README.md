# tools

Scripts that are run by hand on the repository. They are not part of the app,
and nothing in `lib/` reads them. Standard library only.

## wrap_comments.py

Checks the comment paragraphs in Dart files against the house width, the one
rule 6 of `AGENTS.md` states. The formatter does not reflow comments, so this
is the part of the house style that a formatter cannot check.

The rule it applies is the one the house follows:

- a paragraph is the run of comment lines that share one marker, `///` or `//`;
  a line that is only the marker separates two paragraphs;
- a paragraph that already fits keeps the shape it was given, so it is never
  rewritten;
- a paragraph with a line over the width is reported, and `--fix` rewrites it as
  plain fill, with the marker repeated on each line;
- a word that does not fit inside the width cannot be broken, so a paragraph
  whose over-long line is one such word is left as it is and is not reported;
- the generated `lib/l10n/app_localizations*.dart` are skipped: `gen-l10n`
  writes them as it is given, so a paragraph over the width there is written
  again by the next run, and is fixed in the `.arb` source instead.

Run from the repository root:

    python3 tools/wrap_comments.py [path ...] [--fix]

With no path it checks `lib` and `test`. It reports each paragraph it would
rewrite and exits 1 when there is one, so it is the check that is run before a
change is committed; `--fix` writes the paragraphs it reports.

Markdown is not checked. Prose under `ai/` is wrapped at the width each file
already uses, and the file tree in `ai/doc.md` §3 is a layout rather than prose,
so a line added there is written by hand.
