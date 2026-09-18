# DMXtract extraction benchmark

Scores DMXtract's manual-to-fixture extraction against real GDTF fixture
data: for each mined manual, it runs the extractor, then compares the
result's DMX modes/channels against the corresponding GDTF fixture in a
ground-truth database.

This directory (the tool) is public and MIT-licensed, same as the rest of
the repo. The **inputs it scores** — the mined manual PDFs/text, the corpus
manifest joining them to GDTF fixtures, and the GDTF ground-truth database
— are **local-only and never committed**. A public clone of this repo can
read and run this tool, but cannot run the benchmark itself without
supplying its own copies of that local data (see "Local data" below). That
is by design, enforced by two separate mechanisms with different scope:
`.gitignore`'s `testcorpus/*` keeps the corpus (mined manual PDFs/text,
the manifest, working dumps) out of `git add`/`git status` in the first
place, and `score_extraction.py` itself refuses to write `--out` to any
path inside the repo, since `scoreboard.csv`/`summary.md` carry truth and
extracted brand/model strings derived from that local-only data.
`node scripts/check-source-boundary.mjs` is a **separate, narrower**
check: it scans tracked files for a short list of specific forbidden
strings/paths/hashes (retired private-repo references and codenames), not
for corpus PDFs, extracted text, or database contents in general - don't
rely on it alone for the corpus/derived-data boundary above.

## The one lesson that matters: footprint, not n_channels

**A DMX mode's true size is the set of DMX slots it occupies — every
`offset_coarse` plus every distinct `offset_fine` — never
`mode.n_channels`.**

`n_channels` is a *logical* row count from the source fixture's channel
table. It disagrees with the true DMX slot footprint on roughly **two out
of every three modes** in this corpus's ground truth — chiefly because
multi-byte (coarse+fine) channels occupy two DMX slots but are one logical
row, and because some tables include header/label rows that don't occupy a
slot at all.

The first pass at this eval scored `n_channels` against `n_channels` and
produced numbers that looked plausible but were wrong. The corrected
scorer (what `score_extraction.py` implements) computes footprint as
occupied-slot sets on both the truth and extraction sides, and pairs
truth/extracted modes by matching footprint, not by matching n_channels.
**If you're tempted to "simplify" this by going back to counting channel
rows, don't — that's the exact regression this benchmark exists to catch.**

A few other things this scorer gets right that are easy to lose on a
rewrite:

- **Fine bytes are scored separately from names.** A fine-byte DMX slot
  isn't compared by name similarity (it usually has no meaningful name of
  its own) — it's scored as a binary "did the extraction mark this offset
  as a fine byte of some channel" (`fineOf` set).
- **Strict attribute match is its own metric, not folded into the
  difflib name score.** `strict_attribute_score` checks the extracted
  `gdtfAttribute` against the truth attribute taxonomy, case-insensitive
  exact match — independent of how close the free-text channel *name*
  is.
- **Zero-mode files count toward recall but are excluded from
  precision.** If a fixture has truth modes but the extractor produced
  zero modes, `footprint_recall` for that file is 0 (it's still in the
  denominator: `n` truth modes matched over `n` truth modes). But
  `footprint_precision`'s denominator is the *extracted* mode count, which
  is zero, so that file is excluded from the precision average entirely.
  `summary.md` reports both metrics with their own `n` rather than forcing
  them to agree — don't "fix" the mismatched `n`s, they're both correct.
- **md5-duplicate PDFs**: a handful of manuals in the mined corpus are
  byte-identical re-hosted copies of the same PDF under a different
  filename. On the 136-fixture reference run this is **15 of 136 scored
  rows (11%), in 6 duplicate groups**: BeamZ MHL1240 (×3), Elation
  FuzeWash500 (×2), Eurolite IPPIXStrobeFROST (×2), FunGeneration LEDPot
  (×2), Robe Footsie (×4), Robe Footsie Slim (×2). The manifest and scorer
  don't de-duplicate these, so the 136 scored rows are not 136
  independent samples, and it's worse than lost weighting: duplicate text
  can be scored against **mutually exclusive ground truth**. Worst case
  here - the Robe Footsie ×4 group is one identical manual PDF scored
  against 4 different GDTF fixtures whose truth footprints don't overlap
  (`{5,28,35}` for the two Footsie1 variants vs `{5,36,49}` for the two
  Footsie2 variants), so at least two of the four rows must score low
  recall regardless of extractor quality. If you're using aggregate
  numbers to compare *extraction approaches* (not to report a single "how
  good is DMXtract" number), be aware near-duplicate fixtures give that
  fixture's score extra weight, and some of that weight is unwinnable.

## What it measures

Per fixture (one mined manual matched to one GDTF fixture):

| metric | what it means |
|---|---|
| `manufacturer_score` / `model_score` | difflib similarity of the identity strings |
| `footprint_recall` | fraction of truth mode footprints also present in the extraction (multiset match) |
| `footprint_precision` | fraction of extracted mode footprints that are real (present in truth) |
| `footprint_recall_tol1` | recall with a ±1 DMX-slot tolerance |
| `channel_name_score` | difflib similarity of channel names, walked per occupied truth slot, over the truth/extracted mode pairing that maximizes this score |
| `fine_byte_score` | binary: fine-byte truth slots marked as `fineOf` something in the extraction |
| `strict_attribute_score` | binary: extracted `gdtfAttribute` exactly matches the truth attribute (case-insensitive) |
| `range_richness` | of truth channels with real DMX sub-ranges (>1 `chan_function`), fraction where the extraction also recorded >1 range |

Mode pairing: truth and extracted modes are bucketed by matching true
footprint, then paired within each bucket to maximize total
`channel_name_score` (exhaustive permutation search up to 6×6 modes,
greedy beyond that).

Aggregates in `summary.md`: mean/median/min/max per metric, per-brand
breakdown, zero-overlap fixture count (`footprint_recall == 0`),
perfect-recall fixture count (`footprint_recall == 1.0`), and a
filename-echo count — extracted model name matching `(?i)\bum$` (case-
insensitive, word-boundary "um" at the end of the string), which in
practice on this corpus means the "User Manual" doc-type suffix from the
source filename (` UM`) leaking into the identity field, a specific
failure mode worth tracking on its own.

## Reference numbers (136-fixture eval, 2026-09-18)

From the corrected audit pass, scoring 136 mined manuals against
`unified.db` GDTF ground truth:

| metric | n | mean | median |
|---|---|---|---|
| footprint_recall | 136 | 0.748 | 1.000 |
| footprint_precision | 129 | 0.730 | 1.000 |
| footprint_recall_tol1 | 136 | 0.768 | 1.000 |
| channel_name_score (difflib) | 121 | 0.272 | 0.248 |
| fine_byte_score | 75 | 0.331 | 0.100 |
| strict_attribute_score | 121 | 0.170 | 0.085 |
| range_richness | 84 | 0.210 | 0.000 |

- Zero-overlap fixtures (`footprint_recall == 0`): 15
- Perfect-recall fixtures (`footprint_recall == 1.0`): 81
- Filename-echo models (`" UM"` suffix): 38

Re-running the benchmark end-to-end (fresh extraction, not the saved
dumps above) will drift slightly from these numbers as the extractor
changes — that's expected and fine. What should *not* drift is the
scoring methodology itself (footprint, not n_channels; separate fine-byte
and strict-attribute metrics; the recall/precision denominator split).
Treat a large, unexplained jump in these reference numbers as a signal to
check whether the scorer regressed before assuming the extractor did.

## Local data this benchmark needs

None of the following are in the repo. `score_extraction.py` fails fast
with a plain-English explanation (not a stack trace) if any are missing.

1. **Ground-truth database** (`--db`, or `$DMXTRACT_UNIFIED_DB`) — a
   SQLite database with GDTF fixture data: `fixture(source, gdtf_guid,
   manufacturer, model)`, `mode(fixture_id, name, n_channels)`,
   `channel(mode_id, dmx_break, offset_coarse, offset_fine, nbytes,
   attribute, pretty)`, `chan_function(channel_id, name, attribute,
   dmx_from, dmx_to)`.
2. **Corpus manifest** (`--manifest`, default
   `testcorpus/MANIFEST.local.md`, gitignored) — joins mined manual
   filenames to GDTF fixture ids. Each row is either
   `<filename>.pdf | ... | <GDTF GUID somewhere in the row> | ...` or
   `<filename>.pdf | ... | <int id> (int id in unified.db...) | ...` —
   `score_extraction.py`'s `parse_manifest` handles both shapes.
3. **Mined manual text** (input to the extraction-dump step, not to
   `score_extraction.py` directly) — a directory of page-marked `.txt`
   files, one per manual, each page preceded by a
   `=== DMXTRACT PAGE N ===` marker (the same convention
   `apps/web/lib/src/manual_extractor_web.dart` produces from a real
   PDF/OCR pass). Point `run_benchmark.sh` at this directory, or set
   `$DMXTRACT_EVAL_TEXT_DIR`.

## Usage

```sh
# score an existing directory of extraction-dump JSON files
python3 scripts/eval/score_extraction.py \
  --db "$DMXTRACT_UNIFIED_DB" \
  --manifest testcorpus/MANIFEST.local.md \
  --extracts /path/to/extraction/dumps \
  --out /path/to/scoreboard/output

# one command: dump the whole corpus through the extractor, then score it
export DMXTRACT_UNIFIED_DB=/path/to/unified.db
scripts/eval/run_benchmark.sh /path/to/manual/text/dir [work-dir]
```

`run_benchmark.sh` always restores `apps/web/analysis_options.yaml`
before it exits (success or failure): running Dart tests via the Flutter
test harness auto-writes an `analyzer: exclude:` block into that file, and
this benchmark must never leave the working tree dirty.

## Extraction-dump tool

`apps/web/tool/dump_extractions.dart` is a **plain Dart entry point** —
run with `dart run`, no `flutter test` harness needed. This was verified,
not assumed: `lib/src/extraction_rules.dart` and `lib/src/model.dart`
import only `dart:convert` and `lib/src/gdtf_attribute_catalog.dart` (a
generated data file with no imports at all) — no `package:flutter`
anywhere in that import graph. `dart run` works directly against
`apps/web/.dart_tool/package_config.json` (already resolved by whichever
`flutter pub get` last ran in this tree) without needing the Flutter SDK's
own Dart toolchain.

It writes one `<name>.json` per `<name>.txt` input — the exact output of
`FixtureProject.encode()`, the same method `export_service.dart` uses for
a real `.dmxtract.json` export — plus a `SUMMARY.txt` line per fixture.

```sh
cd apps/web
dart run tool/dump_extractions.dart /path/to/text/dir /path/to/output/dir
```
