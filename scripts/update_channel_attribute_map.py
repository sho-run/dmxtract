#!/usr/bin/env python3
"""Regenerate apps/web/lib/src/channel_attribute_map.g.dart from unified.db.

Mirrors the role scripts/update_brand_catalog.py and
scripts/update_gdtf_attribute_catalog.rb play for their own generated
files: this script reads a *local*, read-only ground-truth database
(never committed - see testcorpus/README / scripts/eval/README.md) and
turns it into a small, committable, generated Dart source file. Only the
generated *names* (a channel's common printed name paired with the GDTF
attribute it overwhelmingly turns out to mean) are committed; the
database itself, and any manual/PDF text, stay local. A channel-name-to-
attribute mapping mined from tens of thousands of real, published GDTF
fixture definitions is an uncopyrightable fact table, the same precedent
gdtf_attribute_catalog.g.dart and brand_catalog.g.dart already ship on.

What it does
------------
1. Reads `SELECT c.pretty, c.attribute, f.source, COUNT(*) FROM channel c
   JOIN mode m ON c.mode_id = m.mode_id JOIN fixture f ON m.fixture_id =
   f.fixture_id WHERE c.pretty IS NOT NULL AND c.attribute IS NOT NULL
   GROUP BY 1, 2, 3` from unified.db (merged from several fixture-library
   sources on GDTF's model - see
   ~/.claude/projects/.../unified-fixture-db.md). `source` is
   'gdtf' or a console-library source; falls back to an unweighted, source-less
   query against a database that has no `mode`/`fixture` tables (the
   minimal sample schema channel_attribute_map_test.dart's determinism
   test builds).
2. Drops any row whose `attribute` isn't a plausible bare GDTF attribute
   token (letters/digits/underscore only) - a handful of source rows
   carry free-text UI leftovers ("Main <> FX") in that column instead of
   a real attribute name.
3. Normalizes each `pretty` string into a lookup key: casefold, split a
   letter directly against an adjacent digit ("Blue25" -> "Blue 25"),
   collapse every other punctuation/whitespace run to a single space,
   then strip ONE trailing standalone digit token (a wheel/zone index -
   "Gobo 1" -> key "gobo", zone 1) and, after that, one trailing "f"/
   "fine" token ("Red Fine" / "Red F" -> key "red" - GDTF gives a fine
   channel the *same* Attribute as its coarse channel, so this is a
   free extra alias, not a guess). The attribute's own first digit run
   always templates onto a "{n}" placeholder ("Gobo1" -> "Gobo{n}"),
   whether or not this particular `pretty` spelling had its own zone
   digit — a plain "Frost" and a zoned "Frost 1" both mean concretely
   "Frost1", so keeping the same template for both reinforces one
   answer instead of splitting the vote between "Frost1" and
   "Frost{n}". The app substitutes a real zone number back in at lookup
   time (defaulting to "1" when the channel description had none of its
   own), so the generated entry generalizes across wheels/zones instead
   of hard-coding the one instance counted most.
4. Aggregates every (pretty, attribute) pair sharing a normalized key,
   split by source, and keeps the key only when it has strong,
   unambiguous evidence:
     - If GDTF alone backs the key with at least GDTF_MIN_EVIDENCE
       occurrences, the winning template is decided from GDTF's own
       votes alone, ignoring the console-library sources entirely for that decision.
       GDTF is ~18% of unified.db's channel rows, so pooling all three
       sources unweighted lets a the console-library sources dialect outvote GDTF on a
       key GDTF disagrees with (confirmed on real data: pooled votes
       send 'cct' to CTO on over ten thousand console-library rows and zero GDTF
       weight, while GDTF's own 698 rows for that key say CCT) - and
       scripts/eval/score_extraction.py's ground truth is itself
       GDTF-only, so a template GDTF-only evidence would have rejected
       is one the benchmark can never agree with anyway.
     - Otherwise (GDTF has little or no opinion), fall back to the
       pooled evidence across all sources, but require a much higher
       MIN_TOTAL_NO_GDTF - a thin, single-dialect entry with no GDTF
       backing at all is exactly the shape of a wrong or misleading
       mapping (confirmed on real data: 'sound sensitivity' -> a mic-
       gain control - mapping to Effects{n} on 89 console-library-only rows).
   Either way, the winning template must still clear MIN_RATIO of
   whichever evidence pool decided it - this is a *majority* mapping,
   not a unanimous one, since a real corpus mixes typos, alternate
   dialects and outright mislabeled fixtures.
5. Drops any key whose winning attribute is "NoFeature": the app's own
   `defaultGdtfAttribute` fallback already returns "NoFeature" for any
   channel classification doesn't recognize, so an explicit NoFeature
   entry here changes nothing and only bloats the table.
6. Drops any key whose winning template doesn't resolve to a real name
   in gdtf_attribute_catalog.g.dart (with n=1 substituted for "{n}" and
   the catalog's own "(n)"/"(m)" placeholders treated as wildcards) -
   the generator has no way to know a mined attribute spelling is real
   GDTF taxonomy rather than a source library's own free-text label
   ("Macro" from a console-library 'beam macro' pretty string, say - GDTF has no
   bare "Macro" attribute, only "ColorMacro(n)" and friends) until it's
   checked against the catalog that IS the definition of real GDTF
   taxonomy.
7. Emits a sorted, deterministic Dart source file: the same database
   contents always produce byte-identical output (no timestamps, no
   non-deterministic ordering).

Regeneration
------------
    python3 scripts/update_channel_attribute_map.py /path/to/unified.db

Optional second argument overrides the output path (default:
apps/web/lib/src/channel_attribute_map.g.dart). Re-run this and commit
the diff whenever unified.db's channel-name/attribute pairing changes;
do NOT hand-edit the generated file. Run twice back-to-back and `diff`
the two outputs to confirm determinism (a "catalog determinism" test in
apps/web/test/channel_attribute_map_test.dart does exactly that against
a fixed sample instead of the multi-GB real database).
"""

from __future__ import annotations

import re
import sqlite3
import subprocess
import sys
from pathlib import Path

# A key with at least this many GDTF-sourced occurrences is decided from
# GDTF's own votes alone (see step 4 above) - the actual per-key GDTF
# totals we've seen on real disagreements are either ~0 (no GDTF opinion)
# or several hundred, so a modest floor is enough to separate "GDTF has a
# real opinion here" from noise without also demanding GDTF alone clear
# the full evidence bar every other source needs.
GDTF_MIN_EVIDENCE = 20
MIN_TOTAL = 50
MIN_TOTAL_NO_GDTF = 300
MIN_RATIO = 0.85
MIN_KEY_LEN = 2

_ATTRIBUTE_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
_LETTER_DIGIT_BOUNDARY = re.compile(r"(?<=[a-z])(?=[0-9])|(?<=[0-9])(?=[a-z])")
_NON_ALNUM = re.compile(r"[^a-z0-9]+")
_CATALOG_NAME_RE = re.compile(r"name:\s*'([^']*)'")

# The CI-matching Dart SDK this environment keeps around specifically
# because the machine's own `dart` formats differently from the pinned CI
# version - see the "CRITICAL FORMATTER LESSON" this repo's agents are
# briefed on. Falls back to plain `dart` off $PATH when that SDK isn't
# present (e.g. outside this sandboxed environment).
_CI_DART = Path(
    "/private/tmp/claude-501/-Users-kennyvasko-Code-SeeingItAll/"
    "c48d4161-73b5-414b-86ba-5ee86a1b4b52/scratchpad/dartsdk/dart-sdk/bin/dart"
)


def normalize_key(pretty: str) -> str:
    """See the module docstring's step 3."""
    s = _LETTER_DIGIT_BOUNDARY.sub(" ", pretty.lower())
    s = _NON_ALNUM.sub(" ", s).strip()
    tokens = s.split()
    if not tokens:
        return ""
    if tokens[-1].isdigit():
        tokens = tokens[:-1]
    if tokens and tokens[-1] in ("f", "fine"):
        tokens = tokens[:-1]
    return " ".join(tokens)


def templatize(attribute: str) -> str:
    """Replaces an attribute's first digit run with the "{n}" placeholder
    [_channelAttributeKey]/[gdtfAttributeForChannelName] substitute a zone
    number back into at lookup time (defaulting to "1" when the channel
    description carried no explicit zone digit of its own).

    Always templates, regardless of whether THIS PARTICULAR `pretty`
    spelling had its own trailing zone digit: a fixture whose manual
    calls its one frost wheel just "Frost" and a fixture whose manual
    calls its first of several "Frost 1" both mean the same attribute,
    concretely "Frost1" either way - keeping them as two different
    template strings ("Frost1" vs "Frost{n}") would split the vote
    between them instead of reinforcing the same answer.
    """
    match = re.search(r"\d+", attribute)
    if not match:
        return attribute
    return attribute[: match.start()] + "{n}" + attribute[match.end() :]


def load_rows(db_path: str) -> list[tuple[str, str, str | None, int]]:
    """Returns (pretty, attribute, source, count) rows.

    `source` is 'gdtf' or a console-library source, joined in via
    channel.mode_id -> mode.fixture_id -> fixture.source. Falls back to a
    source-less query (source always None) against a database that has
    no `mode`/`fixture` tables at all, which is what
    channel_attribute_map_test.dart's determinism test builds - a bare
    `channel(channel_id, pretty, attribute)` table standing in for
    unified.db's real, much wider schema.
    """
    uri = f"file:{db_path}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    try:
        try:
            cur = conn.execute(
                "SELECT c.pretty, c.attribute, f.source, COUNT(*) "
                "FROM channel c "
                "JOIN mode m ON c.mode_id = m.mode_id "
                "JOIN fixture f ON m.fixture_id = f.fixture_id "
                "WHERE c.pretty IS NOT NULL AND c.attribute IS NOT NULL "
                "GROUP BY 1, 2, 3"
            )
            return cur.fetchall()
        except sqlite3.OperationalError:
            cur = conn.execute(
                "SELECT pretty, attribute, NULL, COUNT(*) FROM channel "
                "WHERE pretty IS NOT NULL AND attribute IS NOT NULL "
                "GROUP BY 1, 2"
            )
            return cur.fetchall()
    finally:
        conn.close()


def load_catalog_names(catalog_path: Path) -> list[str]:
    """The GDTF attribute names gdtf_attribute_catalog.g.dart defines,
    e.g. "Gobo(n)Pos" or "Dimmer" - "(n)"/"(m)" mark a zone-index slot,
    same convention this script's own "{n}" placeholder mirrors.
    """
    if not catalog_path.exists():
        return []
    text = catalog_path.read_text()
    return _CATALOG_NAME_RE.findall(text)


def _catalog_pattern(name: str) -> re.Pattern[str]:
    pattern = re.escape(name).replace(r"\(n\)", r"\d+").replace(r"\(m\)", r"\d+")
    return re.compile(f"^{pattern}$")


def resolves_in_catalog(template: str, catalog_patterns: list[re.Pattern[str]]) -> bool:
    """Whether `template` (its "{n}" substituted with a concrete "1", the
    same substitution the app makes at lookup time when a channel had no
    zone digit of its own) names a real GDTF attribute - see step 6.
    """
    instance = template.replace("{n}", "1")
    return any(pattern.match(instance) for pattern in catalog_patterns)


def build_map(
    rows: list[tuple[str, str, str | None, int]],
    catalog_patterns: list[re.Pattern[str]],
) -> list[tuple[str, str, int, float]]:
    """Returns a sorted list of (key, attribute_template, total, ratio)."""
    # counts[key][source_or_'?'][template] -> occurrences. Grouping by
    # source (rather than a single pooled total) is what lets GDTF's own
    # votes be judged on their own, separately from the much larger
    # the console-library sources pool - see step 4.
    counts: dict[str, dict[str, dict[str, int]]] = {}
    # Whether `rows` carries real source labels at all. [load_rows] falls
    # back to a source-less query (every row's source is None) against a
    # database with no mode/fixture tables to join - the minimal sample
    # schema channel_attribute_map_test.dart's determinism test builds.
    # Without a source column there's no such thing as "GDTF evidence" to
    # weigh, so that fallback keeps the plain, unweighted MIN_TOTAL gate
    # instead of demanding MIN_TOTAL_NO_GDTF that no source-blind row
    # could ever have earned an exemption from.
    has_source_info = any(source is not None for _, _, source, _ in rows)
    for pretty, attribute, source, count in rows:
        if pretty is None or attribute is None or not _ATTRIBUTE_RE.match(attribute):
            continue
        key = normalize_key(pretty)
        if len(key) < MIN_KEY_LEN:
            continue
        template = templatize(attribute)
        by_source = counts.setdefault(key, {})
        by_template = by_source.setdefault(source or "?", {})
        by_template[template] = by_template.get(template, 0) + count

    entries = []
    for key, by_source in counts.items():
        gdtf_counts = by_source.get("gdtf", {})
        gdtf_total = sum(gdtf_counts.values())
        if gdtf_total >= GDTF_MIN_EVIDENCE:
            pool = gdtf_counts
            total = gdtf_total
        else:
            pool: dict[str, int] = {}
            for by_template in by_source.values():
                for template, count in by_template.items():
                    pool[template] = pool.get(template, 0) + count
            total = sum(pool.values())
            floor = MIN_TOTAL_NO_GDTF if has_source_info else MIN_TOTAL
            if total < floor:
                continue
        if total < MIN_TOTAL:
            continue
        # Ties broken alphabetically by template so regeneration is
        # deterministic regardless of dict/sqlite iteration order.
        best_template, best_count = max(pool.items(), key=lambda kv: (kv[1], kv[0]))
        if best_template == "NoFeature":
            continue
        ratio = best_count / total
        if ratio < MIN_RATIO:
            continue
        if catalog_patterns and not resolves_in_catalog(best_template, catalog_patterns):
            continue
        entries.append((key, best_template, total, ratio))

    entries.sort(key=lambda e: e[0])
    return entries


def escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def render(entries: list[tuple[str, str, int, float]]) -> str:
    out = []
    out.append(
        "// Generated from unified.db's `channel` table (pretty/attribute\n"
        "// columns, majority-voted per normalized name, weighted toward\n"
        "// GDTF-sourced evidence - see\n"
        "// ~/.claude/projects/.../unified-fixture-db.md). Run\n"
        "// scripts/update_channel_attribute_map.py to refresh this file. Do\n"
        "// not hand-edit.\n"
        f"// Entry count: {len(entries)}\n"
        "part of 'channel_attribute_map.dart';\n"
        "\n"
        "const channelAttributeMap = <String, String>{\n"
    )
    for key, template, _total, _ratio in entries:
        out.append(f"  '{escape(key)}': '{escape(template)}',\n")
    out.append("};\n")
    return "".join(out)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            "usage: update_channel_attribute_map.py <path-to-unified.db> [output-path]",
            file=sys.stderr,
        )
        return 2
    db_path = argv[1]
    target = (
        argv[2] if len(argv) > 2 else "apps/web/lib/src/channel_attribute_map.g.dart"
    )
    catalog_path = (
        Path(__file__).resolve().parent.parent
        / "apps/web/lib/src/gdtf_attribute_catalog.g.dart"
    )
    catalog_names = load_catalog_names(catalog_path)
    if not catalog_names:
        print(
            f"warning: no attribute names loaded from {catalog_path} - "
            "skipping catalog validation (step 6).",
            file=sys.stderr,
        )
    catalog_patterns = [_catalog_pattern(name) for name in catalog_names]
    rows = load_rows(db_path)
    entries = build_map(rows, catalog_patterns)
    text = render(entries)
    Path(target).write_text(text)
    dart_bin = str(_CI_DART) if _CI_DART.exists() else "dart"
    try:
        subprocess.run([dart_bin, "format", str(target)], check=True, capture_output=True)
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        print(f"warning: dart format failed on {target}: {exc}", file=sys.stderr)
    print(f"Wrote {len(entries)} channel attribute map entries to {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
