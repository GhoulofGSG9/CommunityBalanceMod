#!/usr/bin/env python3
"""Generate the docs changelog pages from the in-game changelog.

Single source of truth: src/lua/GUIBetaBalanceChangelogData.lua holds both edition
changelogs as Lua long-bracket strings ([[ ... ]]):

    if kCBMaddon then    -> Content Edition  (first  [[...]] block)
    else                 -> Core Edition     (second [[...]] block)

Devs keep that file up to date for the in-game changelog window; this script reads
the two blocks straight out of it and writes docs/content.md + docs/core.md so the
website never drifts. No Lua interpreter required - the blocks are extracted by text.

Run from the repo root:  python3 tools/gen-changelog.py
"""

import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(REPO_ROOT, "src", "lua", "GUIBetaBalanceChangelogData.lua")

# Top-level "## MARINE" / "## ALIEN" / "## GENERAL" sections get a banner image the
# first time their family appears (matches the imagery already used in the docs).
BANNERS = {
    "MARINE": "Marine_Banner.webp",
    "ALIEN": "Alien_Banner.webp",
    "GENERAL": "Global_Banner.webp",
}

# Tabs in the source are used both for the block's base indent and for list nesting.
# Expand to a fixed width so indent depth is measurable, then normalise.
TAB_WIDTH = 4
BASE_INDENT = TAB_WIDTH  # every line in the block is indented one tab inside [[ ]]

EDITIONS = [
    {
        "key": "content",
        "name": "Content",
        "out": os.path.join(REPO_ROOT, "docs", "content.md"),
        "blurb": "the **full** CBM suite: every new unit, structure, weapon and ability "
                 "plus all balance, QoL, performance and bugfix changes.",
    },
    {
        "key": "core",
        "name": "Core",
        "out": os.path.join(REPO_ROOT, "docs", "core.md"),
        "blurb": "the balance, QoL, performance and bugfix changes only - the vanilla "
                 "NS2 roster is kept (Carapace, no new units or weapons).",
    },
]


def extract_blocks(text):
    """Return the two [[ ... ]] long-bracket strings, in file order."""
    blocks = re.findall(r"gChangelogData\s*=\s*\[\[(.*?)\]\]", text, re.DOTALL)
    if len(blocks) < 2:
        sys.exit("ERROR: expected two gChangelogData [[...]] blocks (Content + Core), "
                 "found %d. Has the source file format changed?" % len(blocks))
    return blocks[0], blocks[1]


def heading_level(stripped):
    """Number of leading '#' if the line is a heading, else 0."""
    n = 0
    while n < len(stripped) and stripped[n] == "#":
        n += 1
    return n if n and n <= 6 else 0


def transform(blob):
    """Turn an in-game changelog blob into clean Markdown."""
    lines = blob.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    out = []
    seen_banner = set()

    for raw in lines:
        line = raw.expandtabs(TAB_WIDTH).rstrip()
        if not line.strip():
            out.append("")
            continue

        indent = len(line) - len(line.lstrip(" "))
        stripped = line.strip()

        level = heading_level(stripped)
        if level:
            text = stripped[level:].strip()  # drop the '#' run + any glued char
            # Banner before the first MARINE/ALIEN/GENERAL family heading.
            family = text.split()[0].upper() if text else ""
            if level == 2 and family in BANNERS and family not in seen_banner:
                seen_banner.add(family)
                img = BANNERS[family]
                out.append('![%s](./assets/images/%s "%s")' % (family, img, family))
                out.append("")
            out.append("%s %s" % ("#" * level, text))
            continue

        if stripped.startswith("- "):
            rel = max(0, indent - BASE_INDENT)
            # top-level bullets sit at rel ~2 (tab + 2 spaces); each nesting adds ~2.
            depth = max(0, round((rel - 2) / 2))
            out.append("%s%s" % ("  " * depth, stripped))
            continue

        # Anything else: intro / paragraph text, flattened to column 0.
        out.append(stripped)

    # Collapse 3+ blank lines and trim leading/trailing blanks.
    md = "\n".join(out)
    md = re.sub(r"\n{3,}", "\n\n", md).strip("\n")
    return md


def render_page(edition, body):
    return (
        "---\n"
        "title: %s Edition Changelog\n"
        "---\n"
        "<!-- AUTO-GENERATED from src/lua/GUIBetaBalanceChangelogData.lua by "
        "tools/gen-changelog.py. Do not edit by hand - your changes will be overwritten. -->\n"
        "\n"
        "# Community Balance Mod &mdash; %s Edition\n"
        "\n"
        "*Changes versus vanilla NS2. This page is %s*\n"
        "\n"
        "[&larr; Back to overview](./)\n"
        "\n"
        "%s\n"
    ) % (edition["name"], edition["name"], edition["blurb"], body)


def main():
    with open(SOURCE, "r", encoding="utf-8") as f:
        text = f.read()

    content_blob, core_blob = extract_blocks(text)
    blobs = {"content": content_blob, "core": core_blob}

    for edition in EDITIONS:
        body = transform(blobs[edition["key"]])
        page = render_page(edition, body)
        with open(edition["out"], "w", encoding="utf-8", newline="\n") as f:
            f.write(page)
        print("wrote %s (%d lines)" % (
            os.path.relpath(edition["out"], REPO_ROOT), page.count("\n")))


if __name__ == "__main__":
    main()
