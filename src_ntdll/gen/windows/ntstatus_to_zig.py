#!/usr/bin/env python3
"""Scrape [MS-ERREF] 2.3.1 NTSTATUS Values straight from Microsoft Learn and
emit a Zig enum.

Adapted from a script that extracted MS-ERREF tables to TSV for offline,
diffable codegen. This version skips the TSV step and goes directly from the
HTML table to the Zig enum, and only handles the NTSTATUS table.

Every [MS-ERREF] code table has the same two-column shape -- a cell holding
the hexadecimal value and the symbolic name, and a cell holding the
description -- which is what TableParser below relies on.

Since NTSTATUS values are not guaranteed unique across facilities, the first
name to claim a given value becomes the real enum field; every later name
with the same value becomes a `pub const` alias pointing at it. Where the
specification gives a code a description, it is emitted as a `///` doc
comment above the field or alias.

Usage:
    python3 ntstatus_to_zig.py > ntstatus.zig
    python3 ntstatus_to_zig.py --out ntstatus.zig
    python3 ntstatus_to_zig.py page.html --out ntstatus.zig   # local copy
"""

import argparse
import html.parser
import re
import sys
import urllib.request
from datetime import datetime

NTSTATUS_URL = (
    "https://learn.microsoft.com/en-us/openspecs/windows_protocols/"
    "ms-erref/596a1078-e883-4972-9bbc-49e60bebca55"
)
SECTION = "2.3.1 NTSTATUS Values"

# Below this many rows, extraction is treated as a layout change rather than
# a result (observed row count at last extraction: ~1800).
MIN_ROWS = 1700

# The value cell holds "0xXXXXXXXX" and the symbolic name, normally in
# separate paragraphs but occasionally in one.
CODE_ONLY = re.compile(r"^0x([0-9A-Fa-f]{8})$")
CODE_AND_NAME = re.compile(r"^0x([0-9A-Fa-f]{8})\s+([A-Za-z_][A-Za-z0-9_]*)$")
NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


class TableParser(html.parser.HTMLParser):
    """Collect the paragraph texts of every two-column row of the code table."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.rows = []
        self._in_table = 0
        self._cells = None
        self._paragraphs = None
        self._text = None

    def handle_starttag(self, tag, attrs):
        if tag == "table":
            self._in_table += 1
        elif tag == "tr" and self._in_table:
            self._cells = []
        elif tag in ("td", "th") and self._cells is not None:
            self._paragraphs = []
        elif tag == "p" and self._paragraphs is not None:
            self._text = []

    def handle_endtag(self, tag):
        if tag == "p" and self._text is not None:
            text = re.sub(r"\s+", " ", "".join(self._text)).strip()
            if text:
                self._paragraphs.append(text)
            self._text = None
        elif tag in ("td", "th") and self._paragraphs is not None:
            self._cells.append(self._paragraphs)
            self._paragraphs = None
        elif tag == "tr" and self._cells is not None:
            if len(self._cells) == 2:
                self.rows.append(self._cells)
            self._cells = None
        elif tag == "table" and self._in_table:
            self._in_table -= 1

    def handle_data(self, data):
        if self._text is not None:
            self._text.append(data)


def extract(page, min_rows):
    """Return a list of (code_int, name, description) rows, one per name
    (a code with several names yields several rows sharing the description)."""
    parser = TableParser()
    parser.feed(page)

    out = []
    for value_cell, description_cell in parser.rows:
        if not value_cell:
            continue

        match = CODE_ONLY.match(value_cell[0])
        if match:
            code, names = match.group(1), [p for p in value_cell[1:] if NAME.match(p)]
        else:
            match = CODE_AND_NAME.match(value_cell[0])
            if not match:
                continue  # header row, or a cell that is not a code
            code, names = match.group(1), [match.group(2)]

        description = " ".join(description_cell)
        if not names or not description:
            raise SystemExit(f"row 0x{code} is missing a name or a description")

        for name in names:
            out.append((int(code, 16), name, description))

    if len(out) < min_rows:
        raise SystemExit(
            f"only {len(out)} rows extracted, want at least {min_rows}; "
            "the page layout has changed"
        )
    return out


def zig_doc_comment(text):
    """Render a single-line description as one or more '///' doc-comment
    lines, indented to match enum fields."""
    return [f"    /// {line}" for line in (text.splitlines() or [""])]


def build_zig_enum(rows, enum_name, source):
    """rows: (code_int, name, description) in specification order.
    First occurrence of a value becomes the real field; every later name
    with the same value becomes a pub const alias."""
    value_to_first_name = {}
    fields = []    # (name, code, description)
    aliases = []   # (alias_name, code, canonical_name, description)

    for code, full_name, description in rows:
        name = full_name.removeprefix("STATUS_")

        if code not in value_to_first_name:
            value_to_first_name[code] = name
            fields.append((name, code, description))
        else:
            canonical = value_to_first_name[code]
            if name != canonical:
                aliases.append((name, code, canonical, description))

    now_str = datetime.now().strftime("%d.%m.%Y - %H:%M")

    lines = []
    lines.append(f"// Auto-generated ({now_str}) from [MS-ERREF] 2.3.1 NTSTATUS Values.")
    lines.append(f"// Source: {source}")
    lines.append("// Do not edit by hand -- regenerate with ntstatus_to_zig.py instead.")
    lines.append("")
    lines.append(f"pub const {enum_name} = enum(u32) {{")
    for alias_name, code, _, description in aliases:
        lines.extend(zig_doc_comment(description))
        lines.append(f"    pub const {alias_name}: {enum_name} = @enumFromInt(0x{code:08X});")
    lines.append("")
    for name, code, description in fields:
        lines.extend(zig_doc_comment(description))
        lines.append(f"    {name} = 0x{code:08X},")
    lines.append("};")
    lines.append("")
    return "\n".join(lines), len(fields), len(aliases)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("page", nargs="?", help="a local copy of the page, instead of fetching it")
    parser.add_argument("--min-rows", type=int, default=MIN_ROWS, help="override the row floor")
    parser.add_argument("--out", help="output .zig path (default: stdout)")
    args = parser.parse_args()

    if args.page:
        source = args.page
        page = open(args.page, encoding="utf-8").read()
    else:
        source = NTSTATUS_URL
        with urllib.request.urlopen(NTSTATUS_URL) as response:
            page = response.read().decode("utf-8")

    rows = extract(page, args.min_rows)
    zig_src, n_fields, n_aliases = build_zig_enum(rows, "NTSTATUS", source)

    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(zig_src)
        print(f"Extracted {len(rows)} rows from {SECTION}.", file=sys.stderr)
        print(f"  -> {n_fields} unique enum fields", file=sys.stderr)
        print(f"  -> {n_aliases} aliases (duplicate values) written as pub const", file=sys.stderr)
        print(f"Wrote {args.out}", file=sys.stderr)
    else:
        sys.stdout.write(zig_src)


if __name__ == "__main__":
    main()
