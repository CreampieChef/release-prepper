#!/usr/bin/env python3
"""Check the comment paragraphs in Dart files against the house width.

The house rule (AGENTS.md §6): the marker is the paragraph separator, so a
paragraph is the run of comment lines that share one - `///` or `//`. A line
that is only the marker is the separator between two paragraphs, not a line of
one. A paragraph that already fits keeps the shape it was given: nothing here
touches it. Only a paragraph with a line over the width is rewrapped, as a
whole, plain fill, with the marker repeated on each line and the indent kept.

A word that does not fit inside the width cannot be broken, so a paragraph
whose over-long line is one such word is left as it is and is not reported.

Nothing outside the comments is touched: the formatter is the house style for
the code, and it does not reflow comments. The generated
`lib/l10n/app_localizations*.dart` are skipped, because `gen-l10n` writes them
as it is given: a paragraph over the width there is written again by the next
run, and is fixed in the `.arb` source instead.

Run from the repository root:

    python3 tools/wrap_comments.py [path ...] [--fix]

With no path it checks `lib` and `test`. It reports each paragraph it would
rewrite and exits 1 when there is one; `--fix` writes them.
"""
import os
import sys

WIDTH = 80
DEFAULT_PATHS = ["lib", "test"]


def marker_of(line):
    """The comment marker a line opens with, or None if it is not a comment."""
    s = line.lstrip()

    if s.startswith("///"):
        return "///"

    if s.startswith("//"):
        return "//"

    return None


def indent_of(line):
    return line[: len(line) - len(line.lstrip())]


def body_of(line, marker):
    """The text of a line, without the marker and without the indent."""
    return line.lstrip()[len(marker):].strip()


def paragraphs(lines):
    """Each comment paragraph, as (start, end, marker, lines)."""
    i = 0

    while i < len(lines):
        marker = marker_of(lines[i])

        if marker is None:
            i += 1
            continue

        end = i

        while end < len(lines) and lines[end].strip():
            m = marker_of(lines[end])

            if m != marker or not body_of(lines[end], m):
                break

            end += 1

        # A line that is only the marker separates two paragraphs: it is not a
        # paragraph, so it is not yielded, and it still moves the scan on.
        if end > i:
            yield i, end, marker, lines[i:end]
            i = end
        else:
            i += 1


def fill(words, hang):
    """Plain fill at the width. A word that does not fit on a line of its own
    is what it is: the line it lands on stays over-long."""
    out, cur = [], ""

    for word in words:
        if not cur:
            cur = hang + word
        elif len(cur) + 1 + len(word) > WIDTH:
            out.append(cur)
            cur = hang + word
        else:
            cur = cur + " " + word

    return out + [cur]


def is_over(block, marker):
    """Whether this is a paragraph the tool would rewrite: a line over the width
    that is made of more than one word, so a fill can make it fit."""
    for line in block:
        if len(line) > WIDTH and len(body_of(line, marker).split()) > 1:
            return True

    return False


def is_generated(path):
    return os.path.basename(path).startswith("app_localizations")


def dart_files(paths):
    for path in paths:
        if os.path.isfile(path):
            if path.endswith(".dart") and not is_generated(path):
                yield path
            continue

        for root, _, names in os.walk(path):
            for name in sorted(names):
                if not name.endswith(".dart"):
                    continue

                full = os.path.join(root, name)

                if not is_generated(full):
                    yield full


def check(path, write):
    with open(path, encoding="utf-8", newline="") as fh:
        text = fh.read()

    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.split(newline)
    found = []

    for start, end, marker, block in paragraphs(lines):
        if not is_over(block, marker):
            continue

        hang = indent_of(block[0]) + marker + " "
        words = [w for line in block for w in body_of(line, marker).split()]
        rewritten = fill(words, hang)

        if rewritten == block:
            continue

        found.append((start, rewritten))

        if write:
            lines[start:end] = rewritten

    if not found:
        return False

    for start, _ in found:
        print(f"{path}:{start + 1}: comment paragraph over {WIDTH} columns")

    if write:
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(newline.join(lines))

    return True


def main():
    argv = sys.argv[1:]
    write = "--fix" in argv
    paths = [a for a in argv if a != "--fix"] or DEFAULT_PATHS

    found = False

    for path in dart_files(paths):
        found = check(path, write) or found

    if not found and write:
        print("nothing to rewrite")

    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
