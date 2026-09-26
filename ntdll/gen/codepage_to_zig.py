#!/usr/bin/env python3
"""Scrape the Code Page Identifiers table from Microsoft Learn and emit a
Zig enum.

Adapted from a script that extracted [MS-ERREF] NTSTATUS values to a Zig
enum. This page's table has a different shape -- three plain columns
(Identifier, .NET Name, Additional information) with no nested paragraphs
per cell -- so the row/cell extraction was rewritten; the doc-comment and
enum-emission logic is otherwise the same idea.

Every identifier is unique, but the ".NET Name" column is not: it is often
blank (e.g. 709, 710) and occasionally repeated across different
identifiers (e.g. "iso-2022-jp" names both 50220 and 50222). So each row
gets exactly one enum field, named:
    - the .NET Name, if present and not already used by another row
    - otherwise the "Additional information" text
    - with " (identifier)" appended if that name was already claimed
Any resulting name that is not a legal bare Zig identifier is emitted as
an @"..." quoted identifier.

Usage:
    python3 codepage_to_zig.py > codepages.zig
    python3 codepage_to_zig.py --out codepages.zig
    python3 codepage_to_zig.py page.html --out codepages.zig   # local copy
"""

import argparse
import html.parser
import re
import sys
import urllib.request
from datetime import datetime

CODEPAGE_URL = (
    "https://learn.microsoft.com/en-us/windows/win32/intl/code-page-identifiers"
)

# Below this many rows, extraction is treated as a layout change rather than
# a result (observed row count at last extraction: ~148).
MIN_ROWS = 140

IDENTIFIER = re.compile(r"^\d+$")
ZIG_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
BOLD = re.compile(r"\*\*(.*?)\*\*")


class TableParser(html.parser.HTMLParser):
    """Collect the plain text of every three-column row of the table."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.rows = []
        self._in_table = 0
        self._cells = None
        self._text = None

    def handle_starttag(self, tag, attrs):
        if tag == "table":
            self._in_table += 1
        elif tag == "tr" and self._in_table:
            self._cells = []
        elif tag in ("td", "th") and self._cells is not None:
            self._text = []

    def handle_endtag(self, tag):
        if tag in ("td", "th") and self._text is not None:
            text = re.sub(r"\s+", " ", "".join(self._text)).strip()
            self._cells.append(text)
            self._text = None
        elif tag == "tr" and self._cells is not None:
            if len(self._cells) == 3:
                self.rows.append(self._cells)
            self._cells = None
        elif tag == "table" and self._in_table:
            self._in_table -= 1

    def handle_data(self, data):
        if self._text is not None:
            self._text.append(data)


def extract(page, min_rows):
    """Return a list of (identifier_int, dotnet_name, description) rows,
    one per table row, in document order."""
    parser = TableParser()
    parser.feed(page)

    out = []
    for ident_text, name_text, desc_text in parser.rows:
        ident_text = ident_text.strip()
        if not IDENTIFIER.match(ident_text):
            continue  # header row, or a row that isn't a code page entry

        description = BOLD.sub(r"\1", desc_text.strip())
        if not description:
            raise SystemExit(f"identifier {ident_text} is missing a description")

        out.append((int(ident_text), name_text.strip(), description))

    if len(out) < min_rows:
        raise SystemExit(
            f"only {len(out)} rows extracted, want at least {min_rows}; "
            "the page layout has changed"
        )
    return out


def zig_name(raw):
    """Return a Zig-legal identifier token for raw: bare if it already
    matches Zig's plain identifier grammar, otherwise an @"..." literal."""
    if ZIG_IDENT.match(raw):
        return raw
    escaped = raw.replace("\\", "\\\\").replace('"', '\\"')
    return f'@"{escaped}"'


def zig_doc_comment(text):
    """Render a single-line description as one or more '///' doc-comment
    lines, indented to match enum fields."""
    return [f"    /// {line}" for line in (text.splitlines() or [""])]


def build_zig_enum(rows, enum_name, source):
    """rows: (identifier_int, dotnet_name, description) in document order.
    Each row becomes exactly one field; a name already claimed by an
    earlier identifier gets " (identifier)" appended to disambiguate."""
    used_names = {}  # display name -> identifier that claimed it
    fields = []       # (zig_token, identifier, description)

    for identifier, dotnet_name, description in rows:
        base = dotnet_name if dotnet_name else description
        name = base
        if name in used_names:
            name = f"{base} ({identifier})"
        used_names[name] = identifier
        fields.append((zig_name(name), identifier, description))

    now_str = datetime.now().strftime("%d.%m.%Y - %H:%M")

    lines = []
    lines.append(f"// Auto-generated ({now_str}) from the Code Page Identifiers table.")
    lines.append(f"// Source: {source}")
    lines.append("// Do not edit by hand -- regenerate with codepage_to_zig.py instead.")
    lines.append("")
    lines.append(f"pub const {enum_name} = enum(u32) {{")
    for name, identifier, description in fields:
        lines.extend(zig_doc_comment(description))
        lines.append(f"    {name} = {identifier},")
    lines.append("};")
    lines.append("")
    return "\n".join(lines), len(fields)


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
        source = CODEPAGE_URL
        with urllib.request.urlopen(CODEPAGE_URL) as response:
            page = response.read().decode("utf-8")

    rows = extract(page, args.min_rows)
    zig_src, n_fields = build_zig_enum(rows, "CODEPAGE", source)

    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(zig_src)
        print(f"Extracted {len(rows)} rows from the Code Page Identifiers table.", file=sys.stderr)
        print(f"  -> {n_fields} enum fields", file=sys.stderr)
        print(f"Wrote {args.out}", file=sys.stderr)
    else:
        sys.stdout.write(zig_src)


if __name__ == "__main__":
    main()
