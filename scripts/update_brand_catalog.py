#!/usr/bin/env python3
"""Regenerate apps/web/lib/src/brand_catalog.g.dart from unified.db.

Mirrors the role scripts/update_gdtf_attribute_catalog.rb plays for
apps/web/lib/src/gdtf_attribute_catalog.g.dart: this script reads a
*local*, read-only ground-truth database (never committed - see
testcorpus/README / scripts/eval/README.md) and turns it into a small,
committable, generated Dart source file. Only the generated *names* are
committed; the database itself, and any manual/PDF text, stay local. A
manufacturer name is an uncopyrightable fact (see gdtf_attribute_catalog.g.dart's
own precedent of committing a generated fact table), so this is safe to
ship in the public MIT repo.

What it does
------------
1. Reads DISTINCT manufacturer names (with row counts) from unified.db's
   `fixture` table, which merges several independent fixture-library
   sources (GDTF Share, MagicQ, and others) on GDTF's model - see
   ~/.claude/projects/.../unified-fixture-db.md for the schema's history.
2. Normalizes: trims whitespace, drops empty/blank rows, drops anything
   under MIN_LEN characters (too short to safely word-match in prose:
   "NA", "Q", "K9", ...).
3. Drops rows matching DENYLIST - names that are either (a) placeholder/
   test data visible in the raw DISTINCT list (GDTF Template, BEGA Test,
   Company NA, ...), (b) visualization/control *software* whose name
   sometimes ends up in a fixture library's manufacturer field but which
   a fixture's own manual never prints as its maker (BlenderDMX, ChamSys,
   Resolume, ...), or (c) ordinary English words that show up as
   standalone manufacturer rows and would false-positive constantly in
   manual prose ("Bright", "Vision", "Star", "Matrix", ...). This list is
   curated BY HAND from inspecting the actual DISTINCT output (see
   scratch analysis at generation time) - it is deliberately small and
   evidence-based, not a generic stopword list. Extend it the same way:
   inspect new DISTINCT rows, don't guess.
4. Collapses case-variant duplicates that share the same normalized key
   (lowercased, punctuation-insensitive word sequence) into one canonical
   entry - e.g. "Laserworld" / "LaserWorld" / "Laserworld " all collapse
   to one entry with the others recorded as aliases. The canonical
   spelling is the variant with the most fixture rows in the source db
   (ties broken alphabetically, so regeneration is deterministic even if
   sqlite's GROUP BY order ever changed).
5. Emits a sorted, deduplicated, deterministic Dart source file: the same
   database contents always produce byte-identical output (no
   timestamps, no non-deterministic ordering).

Regeneration
------------
    python3 scripts/update_brand_catalog.py /path/to/unified.db

Optional second argument overrides the output path (default:
apps/web/lib/src/brand_catalog.g.dart). Re-run this and commit the diff
whenever unified.db's manufacturer set changes; do NOT hand-edit the
generated file. Run twice back-to-back and `diff` the two outputs to
confirm determinism (a `catalog determinism` test in
apps/web/test/brand_catalog_test.dart does exactly this against a fixed
sample instead of the multi-GB real database).
"""

from __future__ import annotations

import re
import sqlite3
import subprocess
import sys
from pathlib import Path

MIN_LEN = 3

# Evidence-based denylist - see the module docstring. Keys are matched
# case-insensitively against the *normalized* (whitespace-collapsed)
# manufacturer string.
DENYLIST = {
    # placeholder / test rows visible in the raw DISTINCT list
    "na",
    "company na",
    "custom",
    "default",
    "generic",
    "generic amazon light",
    "test",
    "bega test",
    "bs test",
    "user test",
    "led-pixel test",
    "latest moon test 150",
    "gdtf template 2",
    "gdtf templaterew",
    "gdtf training",
    "no name",
    "other",
    "unknown",
    "set",
    # lighting-control / visualization software, not fixture makers
    "gdtf",
    "gdtf hed",
    "dgd gdtf",
    "blenderdmx",
    "blenderdmx cheap",
    "capture visualiser",
    "chamsys",
    "compulite",
    "depence",
    "depence2",
    "madmapper",
    "millumin",
    "modul8",
    "onyx",
    "resolume",
    "vectorworks inc",
    "wysiwyg",
    # unrelated software/games that leak into a MagicQ custom-fixture
    # library's manufacturer field
    "epic games",
    "minecraft",
    "unreal engine",
    "warcraft",
    # generic English words that occur as standalone manufacturer rows
    # and would false-positive throughout ordinary manual prose
    "arena",
    "aura",
    "boost",
    "bright",
    "brighter",
    "broadway",
    "china",
    "chinese",
    "comet",
    "eclipse",
    "element",
    "flash",
    "ghost",
    "glow",
    "hive",
    "matrix",
    "orion",
    "pulse",
    "spark",
    "spike",
    "star",
    "titan",
    "venue",
    "vision",
    # lighting-domain jargon that shows up constantly in ordinary manual
    # prose, independent of any actual brand ("moving HEAD", "RGB
    # color", "Test Prg" = test program, generic "Colours"/"Illumination"
    # section headings, "the light source" as a plain descriptive
    # phrase for the lamp/LED itself) - found by cross-referencing the
    # raw DISTINCT list against a catalog scan's false-positive brand
    # attributions on the GDTF benchmark corpus (scripts/eval), not
    # guessed in the abstract.
    "head",
    "rgb",
    "prg",
    "colours",
    "illumination",
    "the light source",
    # "Rainbow" as a standalone catalog row is a DMX colour-effect/gobo
    # name ("so-called 'Rainbow' effect", "CW rainbow effect from slow to
    # fast"), not a brand - found via the alias-occurrence-dedup fix
    # (apps/web/lib/src/extraction_rules.dart's _brandOccurrences): once
    # a brand's real mention count is no longer inflated by its number of
    # case-variant spellings, Showtec_Phantom3RBeam_UM's 8 real
    # "Showtec" mentions no longer outscore "Rainbow"'s 10 real (but
    # entirely jargon) mentions on raw count alone.
    "rainbow",
    # Product-line words that also show up as their own standalone
    # manufacturer row (real MagicQ/GDTF data quirk): a manual naming its
    # own product this way repeats the word constantly, at far higher
    # frequency than any real separate brand mention could reach.
    "helix",
    "fusion",
    "laser",
    "maniac",
}

# Real, established manufacturers whose name is *also* an ordinary English
# word or abbreviation ("etc.", the verb "work") far too common in
# unrelated manual prose to trust from raw occurrence count the way the
# rest of the catalog is - but unlike DENYLIST's entries, these are
# well-documented current brands (ETC/Electronic Theatre Controls, WORK
# Pro, Highlite's Infinity line) it would be wrong to make permanently
# unattributable. Kept in the catalog with `requiresStrongSignal: true`
# instead of dropped outright: the matcher only accepts them on an
# explicit self-identification match ("thank you for purchasing this
# <brand> product"), never on word count alone.
STRONG_SIGNAL_ONLY = {
    "etc",
    "work",
    "infinity",
}


def normalize_key(value: str) -> str:
    """Punctuation-insensitive, case-insensitive grouping key."""
    words = re.findall(r"[A-Za-z0-9]+", value.lower())
    return " ".join(words)


def escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def load_rows(db_path: str) -> list[tuple[str, int]]:
    uri = f"file:{db_path}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    try:
        cur = conn.execute(
            "SELECT manufacturer, COUNT(*) FROM fixture GROUP BY manufacturer"
        )
        return cur.fetchall()
    finally:
        conn.close()


def build_catalog(rows: list[tuple[str, int]]):
    """Returns a sorted list of (canonical, tuple(aliases)) entries."""
    groups: dict[str, list[tuple[str, int]]] = {}
    for raw, count in rows:
        if raw is None:
            continue
        value = raw.strip()
        if len(value) < MIN_LEN:
            continue
        key = normalize_key(value)
        if not key or key in DENYLIST:
            continue
        groups.setdefault(key, []).append((value, count or 0))

    entries = []
    for key, variants in groups.items():
        # Canonical = most fixture rows, ties broken alphabetically so
        # regeneration is deterministic regardless of sqlite row order.
        variants_sorted = sorted(variants, key=lambda v: (-v[1], v[0]))
        canonical = variants_sorted[0][0]
        # Dedup alias spellings (case-sensitive dedup - "Laserworld" and
        # "LaserWorld" are both kept if both appear), excluding the
        # canonical spelling itself, sorted for determinism.
        seen_spellings = {canonical}
        aliases = []
        for spelling, _count in variants_sorted[1:]:
            if spelling not in seen_spellings:
                aliases.append(spelling)
                seen_spellings.add(spelling)
        aliases.sort()
        entries.append((canonical, tuple(aliases), key in STRONG_SIGNAL_ONLY))

    entries.sort(key=lambda e: (e[0].lower(), e[0]))
    return entries


def render(entries) -> str:
    out = []
    out.append(
        "// Generated from unified.db's `fixture` table (manufacturer column,\n"
        "// merged from several fixture-library sources - see\n"
        "// ~/.claude/projects/.../unified-fixture-db.md). Run\n"
        "// scripts/update_brand_catalog.py to refresh this file. Do not hand-edit.\n"
        f"// Entry count: {len(entries)}\n"
        "part of 'brand_catalog.dart';\n"
        "\n"
        "const brandCatalog = <BrandCatalogEntry>[\n"
    )
    for canonical, aliases, requires_strong_signal in entries:
        alias_literal = ", ".join(f"'{escape(a)}'" for a in aliases)
        strong_signal_literal = (
            ", requiresStrongSignal: true" if requires_strong_signal else ""
        )
        out.append(
            f"  BrandCatalogEntry(canonical: '{escape(canonical)}', "
            f"aliases: [{alias_literal}]{strong_signal_literal}),\n"
        )
    out.append("];\n")
    return "".join(out)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            "usage: update_brand_catalog.py <path-to-unified.db> [output-path]",
            file=sys.stderr,
        )
        return 2
    db_path = argv[1]
    target = (
        argv[2]
        if len(argv) > 2
        else "apps/web/lib/src/brand_catalog.g.dart"
    )
    rows = load_rows(db_path)
    entries = build_catalog(rows)
    text = render(entries)
    Path(target).write_text(text)
    try:
        subprocess.run(
            ["dart", "format", str(target)],
            check=True,
            capture_output=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        print(f"warning: dart format failed on {target}: {exc}", file=sys.stderr)
    print(f"Wrote {len(entries)} brand catalog entries to {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
