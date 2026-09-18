#!/usr/bin/env python3
"""Score DMXtract extraction dumps against GDTF ground truth.

A faithful, self-contained port of the corrected eval-campaign rescorer
(the "rescore.py" audit fix). See README.md in this directory for the full
story; the short version is:

  Mode "footprint" is the set of DMX slots a mode actually occupies —
  offset_coarse plus offset_fine (when the channel has a distinct fine
  byte) — NOT mode.n_channels. n_channels is the *logical* channel-row
  count from the source table, and in this corpus it disagrees with the
  true DMX footprint on about two-thirds of modes (multi-byte channels,
  header-only rows, etc.). Every footprint computation in this file counts
  occupied DMX slots. Do not reintroduce n_channels as a scoring measure.

Inputs (all local-only; none of this data is committed to the repo):
  --db        path to unified.db (GDTF ground truth). Defaults to
              $DMXTRACT_UNIFIED_DB.
  --manifest  path to testcorpus/MANIFEST.local.md (filename -> GDTF
              fixture join; two row shapes: a GUID, or a bare integer
              "<id> (int id in unified.db...)").
  --extracts  directory of DMXtract fixture-v1 JSON dumps (one per source
              manual, same encode() as .dmxtract.json export).

Outputs (written to --out):
  scoreboard.csv  one row per scored fixture
  summary.md      aggregate + per-brand stats, filename-echo count

Metrics per fixture (mirroring the corrected audit exactly):
  mfr, mdl        difflib ratio of manufacturer / model name strings
  footprint_recall / footprint_precision
                  multiset intersection of truth vs. extracted mode
                  footprints, over truth modes / extracted modes resp.
                  Zero-mode files: a file with truth modes but zero
                  extracted modes still counts in the recall denominator
                  (recall becomes 0) but is EXCLUDED from precision (its
                  denominator, len(extracted footprints), is 0). This is
                  why footprint_recall and footprint_precision are
                  reported with different n's below - both are correct,
                  don't reconcile them to a single n.
  footprint_recall_tol1
                  recall with a +/-1 slot tolerance (greedy match)
  channel_name    difflib ratio between truth channel name (pretty or
                  attribute) and extracted channel name, walked per
                  occupied truth slot, over mode pairs chosen to maximize
                  this score within each true-footprint bucket
  fine_byte       binary: did the extraction mark the paired slot as a
                  fine byte of some channel (fineOf set)? Scored
                  separately from channel_name, never averaged into it.
  strict_attribute
                  binary: extracted gdtfAttribute case-insensitively
                  equal to truth attribute (independent of name_score;
                  this is taxonomy-vs-taxonomy, not string similarity)
  range_richness  of truth slots with >1 chan_function (i.e. a truth
                  channel that has real DMX sub-ranges, not a flat 0-255),
                  fraction where the extraction also recorded >1 range

Mode pairing: truth and extracted modes are bucketed by matching true
footprint, then paired to maximize summed channel_name score within each
bucket (exhaustive permutation search up to 6x6, greedy beyond that).

filename-echo: extracted model name ending in "UM" (the "User Manual"
doc-type suffix bleeding into the model field from the source filename,
e.g. "7PZ IP UM") - a specific, previously-undetected failure mode this
scorer flags but does not penalize numerically (it already depresses `mdl`
on its own).
"""
from __future__ import annotations

import argparse
import csv
import difflib
import json
import os
import re
import sqlite3
import statistics as st
import sys
from collections import Counter, defaultdict
from itertools import permutations

GUID_RE = re.compile(
    r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
)
INTID_RE = re.compile(r"(\d+)\s*\(int id in unified\.db")
FILENAME_ECHO_RE = re.compile(r"(?i)\bum$")


# --------------------------------------------------------------------------
# normalization / fuzzy scoring helpers
# --------------------------------------------------------------------------
def norm(s):
    """casefold, strip all punctuation/whitespace, keep alnum only."""
    if not s:
        return ""
    s = s.casefold()
    return re.sub(r"[^a-z0-9]", "", s)


def ratio(a, b):
    a, b = norm(a), norm(b)
    if not a and not b:
        return None  # both empty -> not comparable, caller decides
    return difflib.SequenceMatcher(None, a, b).ratio()


# --------------------------------------------------------------------------
# MANIFEST parsing: filename -> {'guid': ...} or {'fixture_id': ...}
# --------------------------------------------------------------------------
def parse_manifest(path):
    mapping = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if "|" not in line or line.strip().startswith("filename") or not line.strip():
                continue
            fname = line.split("|")[0].strip()
            if not fname:
                continue
            m_int = INTID_RE.search(line)
            if m_int:
                mapping[fname] = {"fixture_id": int(m_int.group(1))}
                continue
            m_guid = GUID_RE.search(line)
            if m_guid:
                mapping[fname] = {"guid": m_guid.group(0).upper()}
                continue
            # no ground-truth join available for this row (gap-fill manual,
            # no GDTF target) - silently skipped, same as the audit script.
    return mapping


# --------------------------------------------------------------------------
# DB access
# --------------------------------------------------------------------------
def load_fixture_index(conn):
    """Preload all gdtf-source fixtures once (the gdtf_guid column is
    unindexed, so this avoids a full scan per lookup)."""
    cur = conn.execute(
        "SELECT fixture_id, gdtf_guid, manufacturer, model FROM fixture WHERE source='gdtf'"
    )
    by_guid = {}
    by_id = {}
    for fixture_id, guid, manufacturer, model in cur:
        row = {"fixture_id": fixture_id, "manufacturer": manufacturer, "model": model}
        by_id[fixture_id] = row
        if guid:
            by_guid[guid.upper()] = row
    return by_guid, by_id


def truth_modes(conn, fixture_id):
    """mode_id -> {idx, name, n_channels, slots, footprint}

    slots: (dmx_break, offset) -> {kind: 'coarse'|'fine', name, attr, n_cf}
    footprint: len(slots) == occupied DMX slot count (the corrected truth
    measure - see module docstring).
    """
    out = {}
    for mode_id, idx, name, n_channels in conn.execute(
        "SELECT mode_id, idx, name, n_channels FROM mode WHERE fixture_id=?",
        (fixture_id,),
    ):
        rows = []
        cids = []
        for cid, br, oc, of, nb, attr, pretty in conn.execute(
            "SELECT channel_id, dmx_break, offset_coarse, offset_fine, nbytes, "
            "attribute, pretty FROM channel WHERE mode_id=? ORDER BY channel_id",
            (mode_id,),
        ):
            rows.append((cid, br or 1, oc, of, nb, attr, pretty))
            cids.append(cid)
        cf = {}
        if cids:
            qmarks = ",".join("?" * len(cids))
            cf = dict(
                conn.execute(
                    f"SELECT channel_id, count(*) FROM chan_function "
                    f"WHERE channel_id IN ({qmarks}) GROUP BY channel_id",
                    cids,
                )
            )
        slots = {}
        for cid, br, oc, of, nb, attr, pretty in rows:
            nm = pretty or attr or ""
            if oc is not None:
                slots[(br, oc)] = {
                    "kind": "coarse",
                    "name": nm,
                    "attr": attr,
                    "n_cf": cf.get(cid, 0),
                }
            if of is not None and of != oc:
                slots[(br, of)] = {
                    "kind": "fine",
                    "name": nm,
                    "attr": attr,
                    "n_cf": cf.get(cid, 0),
                }
        out[mode_id] = {
            "idx": idx,
            "name": name,
            "n_channels": n_channels,
            "slots": slots,
            "footprint": len(slots),
        }
    return out


# --------------------------------------------------------------------------
# extraction JSON parsing
# --------------------------------------------------------------------------
def ex_modes(path):
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    ch = {c["id"]: c for c in d.get("channels", [])}
    modes = []
    for m in d.get("modes", []):
        slots = {}
        for entry in m.get("channels", []):
            off = entry.get("offset")
            if off is None:
                continue
            c = ch.get(entry.get("channelId"), {})
            slots[(entry.get("dmxBreak") or 1, off)] = {
                "name": c.get("name") or "",
                "fineOf": c.get("fineOf"),
                "attr": c.get("gdtfAttribute"),
                "ranges": c.get("ranges") or [],
            }
        modes.append({"name": m.get("name"), "footprint": len(slots), "slots": slots})
    identity = d.get("identity") or {}
    return {
        "manufacturer": identity.get("manufacturer") or "",
        "model": identity.get("model") or "",
        "modes": modes,
    }


# --------------------------------------------------------------------------
# per-mode-pair scoring
# --------------------------------------------------------------------------
def name_score(tm, em):
    """Score every occupied truth slot in this (truth mode, extracted mode)
    pair. Fine slots are scored separately (binary "was it marked as a fine
    byte of something"), never blended into the name-similarity mean.
    Returns (name_ratios, fine_hits, strict_attr_hits, detail)."""
    names, fines, attr_hits, detail = [], [], [], []
    for key, t in sorted(tm["slots"].items()):
        e = em["slots"].get(key)
        if t["kind"] == "fine":
            fines.append(1.0 if (e and e.get("fineOf")) else 0.0)
            continue
        if not norm(t["name"]):
            continue
        en = e.get("name") if e else ""
        r = ratio(t["name"], en)
        if r is None:
            continue
        names.append(r)
        ta = (t["attr"] or "").strip()
        ea = ((e or {}).get("attr") or "").strip()
        if ta:
            attr_hits.append(1.0 if ta.casefold() == ea.casefold() else 0.0)
        detail.append((key, t["name"], en, round(r, 3), ta, ea))
    return names, fines, attr_hits, detail


def range_richness(tm, em):
    num = den = 0
    for key, t in tm["slots"].items():
        if t["kind"] == "fine" or t["n_cf"] <= 1:
            continue
        den += 1
        e = em["slots"].get(key)
        if e and len(e.get("ranges") or []) > 1:
            num += 1
    return num, den


def pair_buckets(truth_list, extract_list):
    """Bucket (mode_id, footprint) / (extract_idx, footprint) pairs sharing
    a footprint value."""
    tb = defaultdict(list)
    eb = defaultdict(list)
    for mid, n in truth_list:
        tb[n].append(mid)
    for i, n in extract_list:
        eb[n].append(i)
    return [(n, tb[n], eb[n]) for n in tb if n in eb]


def best_pairing(tids, eids, score_of):
    """Pair truth mode ids with extracted mode indices to maximize total
    name-similarity score. Exhaustive over permutations up to 6x6 (bucket
    sizes are small in practice for this corpus); greedy fallback beyond
    that."""
    if len(tids) <= 6 and len(eids) <= 6:
        best, best_total = None, -1
        if len(tids) <= len(eids):
            for perm in permutations(eids, len(tids)):
                total = sum(score_of(a, b) for a, b in zip(tids, perm))
                if total > best_total:
                    best_total, best = total, list(zip(tids, perm))
        else:
            for perm in permutations(tids, len(eids)):
                total = sum(score_of(a, b) for a, b in zip(perm, eids))
                if total > best_total:
                    best_total, best = total, list(zip(perm, eids))
        return best
    used = set()
    best = []
    for tid in tids:
        cand = sorted(
            (e for e in eids if e not in used), key=lambda e: -score_of(tid, e)
        )
        if not cand:
            break
        used.add(cand[0])
        best.append((tid, cand[0]))
    return best


# --------------------------------------------------------------------------
# per-fixture scoring
# --------------------------------------------------------------------------
def score_fixture(base, truth_row, T, E):
    truth_list = [(mid, d["footprint"]) for mid, d in T.items() if d["footprint"]]
    extract_list = [(i, m["footprint"]) for i, m in enumerate(E["modes"]) if m["footprint"]]
    tc = [n for _, n in truth_list]
    ec = [n for _, n in extract_list]

    inter = sum((Counter(tc) & Counter(ec)).values())
    recall = inter / len(tc) if tc else None
    precision = inter / len(ec) if ec else None

    # tolerant recall: +/-1 slot, greedy
    pool = sorted(ec)
    hit = 0
    for n in sorted(tc):
        for j, m in enumerate(pool):
            if abs(m - n) <= 1:
                hit += 1
                pool.pop(j)
                break
    recall_tol1 = hit / len(tc) if tc else None

    nm_all, fn_all, at_all = [], [], []
    rr_num = rr_den = n_pairs = 0
    for n, tids, eids in pair_buckets(truth_list, extract_list):
        cache = {}

        def score_of(tid, eidx, _cache=cache):
            if (tid, eidx) not in _cache:
                nm, fn, at, detail = name_score(T[tid], E["modes"][eidx])
                _cache[(tid, eidx)] = (st.mean(nm) if nm else 0.0, nm, fn, at)
            return _cache[(tid, eidx)][0]

        assignment = best_pairing(tids, eids, score_of)
        for tid, eidx in assignment:
            _, nm, fn, at = cache[(tid, eidx)]
            nm_all += nm
            fn_all += fn
            at_all += at
            n_pairs += 1
            a, b = range_richness(T[tid], E["modes"][eidx])
            rr_num += a
            rr_den += b

    ex_model = E["model"]
    return {
        "file": base,
        "brand": truth_row["manufacturer"],
        "model": truth_row["model"],
        "extracted_manufacturer": E["manufacturer"],
        "extracted_model": ex_model,
        "manufacturer_score": ratio(truth_row["manufacturer"] or "", E["manufacturer"]),
        "model_score": ratio(truth_row["model"] or "", E["model"]),
        "footprint_recall": recall,
        "footprint_precision": precision,
        "footprint_recall_tol1": recall_tol1,
        "channel_name_score": st.mean(nm_all) if nm_all else None,
        "fine_byte_score": st.mean(fn_all) if fn_all else None,
        "strict_attribute_score": st.mean(at_all) if at_all else None,
        "range_richness": rr_num / rr_den if rr_den else None,
        "range_richness_n": rr_den,
        "n_mode_pairs": n_pairs,
        "n_truth_modes": len(truth_list),
        "n_extracted_modes": len(extract_list),
        "fixture_id": truth_row["fixture_id"],
        "truth_footprints": ";".join(str(x) for x in sorted(tc)),
        "extract_footprints": ";".join(str(x) for x in sorted(ec)),
        "filename_echo": bool(ex_model and FILENAME_ECHO_RE.search(ex_model.strip())),
    }


CSV_FIELDS = [
    "file",
    "brand",
    "model",
    "extracted_manufacturer",
    "extracted_model",
    "manufacturer_score",
    "model_score",
    "footprint_recall",
    "footprint_precision",
    "footprint_recall_tol1",
    "channel_name_score",
    "fine_byte_score",
    "strict_attribute_score",
    "range_richness",
    "range_richness_n",
    "n_mode_pairs",
    "n_truth_modes",
    "n_extracted_modes",
    "fixture_id",
    "truth_footprints",
    "extract_footprints",
    "filename_echo",
]

AGG_KEYS = [
    ("manufacturer_score", "manufacturer name"),
    ("model_score", "model name"),
    ("footprint_recall", "footprint recall"),
    ("footprint_precision", "footprint precision"),
    ("footprint_recall_tol1", "footprint recall (+/-1 slot)"),
    ("channel_name_score", "channel-name difflib"),
    ("fine_byte_score", "fine-byte satisfied"),
    ("strict_attribute_score", "strict gdtfAttribute match"),
    ("range_richness", "range richness"),
]


def summarize(rows, key):
    vals = [r[key] for r in rows if r[key] is not None]
    if not vals:
        return None
    return {
        "n": len(vals),
        "mean": st.mean(vals),
        "median": st.median(vals),
        "min": min(vals),
        "max": max(vals),
    }


# --------------------------------------------------------------------------
# CLI / input validation
# --------------------------------------------------------------------------
def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    print(
        "\nThis benchmark needs local-only inputs (mined manual text, the "
        "MANIFEST.local.md corpus join, and the unified.db ground-truth "
        "database) that are not part of this public repo. See "
        "scripts/eval/README.md for what each one is and how to get them.",
        file=sys.stderr,
    )
    sys.exit(1)


def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument(
        "--db",
        default=os.environ.get("DMXTRACT_UNIFIED_DB"),
        help="path to unified.db (default: $DMXTRACT_UNIFIED_DB)",
    )
    p.add_argument(
        "--manifest",
        default=os.path.join(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
            "testcorpus",
            "MANIFEST.local.md",
        ),
        help="path to testcorpus/MANIFEST.local.md",
    )
    p.add_argument("--extracts", required=True, help="directory of extraction-dump JSON files")
    p.add_argument(
        "--out",
        required=True,
        help="directory to write scoreboard.csv / summary.md into (must be "
        "outside the repo - scoreboard.csv carries truth and extracted "
        "brand/model strings derived from local-only corpus data, and is "
        "not covered by .gitignore or check-source-boundary.mjs)",
    )
    return p.parse_args(argv)


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def reject_out_under_repo(out_dir):
    """scoreboard.csv/summary.md carry truth + extracted brand/model strings
    derived from local-only corpus data (mined manuals, unified.db). Nothing
    in .gitignore or check-source-boundary.mjs is aware of this output, so a
    reader who passes an in-repo --out could commit derived corpus data by
    accident. Refuse outright rather than rely on the user remembering to
    gitignore whatever directory name they picked."""
    resolved = os.path.realpath(out_dir)
    repo = os.path.realpath(REPO_ROOT)
    if resolved == repo or resolved.startswith(repo + os.sep):
        fail(
            f"--out ({out_dir}) resolves inside the repo ({repo}). "
            "scoreboard.csv/summary.md contain truth and extracted "
            "brand/model strings derived from local-only corpus data and "
            "must never be written into this tree - pass a path outside "
            "the repo (e.g. under $TMPDIR, as run_benchmark.sh does)."
        )


def main(argv=None):
    args = parse_args(argv)

    if not args.db:
        fail(
            "no ground-truth database given. Pass --db /path/to/unified.db or "
            "set DMXTRACT_UNIFIED_DB."
        )
    if not os.path.isfile(args.db):
        fail(f"ground-truth database not found: {args.db}")
    if not os.path.isfile(args.manifest):
        fail(f"manifest not found: {args.manifest} (pass --manifest to point elsewhere)")
    if not os.path.isdir(args.extracts):
        fail(f"extracts directory not found: {args.extracts}")
    reject_out_under_repo(args.out)

    try:
        manifest = parse_manifest(args.manifest)
    except OSError as e:
        fail(f"could not read manifest {args.manifest}: {e}")

    try:
        conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
        by_guid, by_id = load_fixture_index(conn)
    except sqlite3.Error as e:
        fail(f"could not read ground-truth database {args.db}: {e}")

    os.makedirs(args.out, exist_ok=True)

    files = sorted(f for f in os.listdir(args.extracts) if f.endswith(".json"))
    if not files:
        fail(f"no .json extraction dumps found in {args.extracts}")

    rows = []
    skipped_no_mapping = []
    skipped_no_db_row = []
    for fj in files:
        base = fj[:-5] + ".pdf"
        mrow = manifest.get(base)
        if not mrow:
            skipped_no_mapping.append(base)
            continue
        frow = by_guid.get(mrow["guid"]) if "guid" in mrow else by_id.get(mrow["fixture_id"])
        if not frow:
            skipped_no_db_row.append(base)
            continue
        T = truth_modes(conn, frow["fixture_id"])
        try:
            E = ex_modes(os.path.join(args.extracts, fj))
        except (OSError, json.JSONDecodeError) as e:
            print(f"warning: could not read {fj}: {e}", file=sys.stderr)
            continue
        rows.append(score_fixture(base, frow, T, E))

    if not rows:
        fail(
            "no fixtures could be scored - manifest, database, and extracts "
            "dir did not join on anything. Check that --extracts filenames "
            "match testcorpus/MANIFEST.local.md rows."
        )

    scoreboard_path = os.path.join(args.out, "scoreboard.csv")
    with open(scoreboard_path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        w.writeheader()
        for r in rows:
            out = dict(r)
            for k, v in out.items():
                if isinstance(v, float):
                    out[k] = round(v, 4)
            w.writerow(out)

    agg = {key: summarize(rows, key) for key, _ in AGG_KEYS}
    zero_overlap = sum(1 for r in rows if r["footprint_recall"] == 0)
    perfect_recall = sum(1 for r in rows if r["footprint_recall"] == 1.0)
    filename_echo = sum(1 for r in rows if r["filename_echo"])

    by_brand = defaultdict(list)
    for r in rows:
        by_brand[r["brand"]].append(r)

    summary_path = os.path.join(args.out, "summary.md")
    with open(summary_path, "w", encoding="utf-8") as f:
        f.write("# DMXtract extraction benchmark\n\n")
        f.write(
            "Mode footprint = occupied DMX slots (offset_coarse + offset_fine), "
            "never mode.n_channels. See README.md.\n\n"
        )
        f.write(f"Scored fixtures: {len(rows)}\n\n")
        if skipped_no_mapping:
            f.write(f"Skipped, no manifest row: {len(skipped_no_mapping)}\n")
        if skipped_no_db_row:
            f.write(f"Skipped, manifest row but no matching DB fixture: {len(skipped_no_db_row)}\n")
        f.write("\n## Aggregate\n\n")
        f.write("| metric | n | mean | median | min | max |\n|---|---|---|---|---|---|\n")
        for key, label in AGG_KEYS:
            v = agg[key]
            if v:
                f.write(
                    f"| {label} | {v['n']} | {v['mean']:.3f} | {v['median']:.3f} | "
                    f"{v['min']:.3f} | {v['max']:.3f} |\n"
                )
        f.write(
            "\nfootprint_recall and footprint_precision have different n's on "
            "purpose: a fixture with truth modes but zero extracted modes "
            "counts toward recall (as 0) but is excluded from precision "
            "(empty denominator). Both are reported above rather than "
            "reconciled to a single n.\n"
        )
        f.write(f"\nZero-overlap fixtures (footprint_recall == 0): {zero_overlap}\n")
        f.write(f"Perfect-recall fixtures (footprint_recall == 1.0): {perfect_recall}\n")
        f.write(
            f"\nFilename-echo models (extracted model name ending in \"UM\", the "
            f"doc-type suffix leaking in from the source filename): {filename_echo}\n"
        )
        f.write("\n## Per-brand\n\n")
        f.write("| brand | n | footprint_recall mean | footprint_precision mean | channel_name mean |\n")
        f.write("|---|---|---|---|---|\n")
        for brand, rs in sorted(by_brand.items(), key=lambda kv: -len(kv[1])):
            rec = summarize(rs, "footprint_recall")
            prec = summarize(rs, "footprint_precision")
            cn = summarize(rs, "channel_name_score")
            rec_s = "n/a" if rec is None else "%.3f" % rec["mean"]
            prec_s = "n/a" if prec is None else "%.3f" % prec["mean"]
            cn_s = "n/a" if cn is None else "%.3f" % cn["mean"]
            f.write(f"| {brand} | {len(rs)} | {rec_s} | {prec_s} | {cn_s} |\n")

    print(f"scored {len(rows)} fixture(s)")
    for key, label in AGG_KEYS:
        v = agg[key]
        if v:
            print(f"  {label:32s} n={v['n']:3d} mean={v['mean']:.3f} median={v['median']:.3f}")
    print(f"  zero-overlap fixtures: {zero_overlap}")
    print(f"  perfect-recall fixtures: {perfect_recall}")
    print(f"  filename-echo models: {filename_echo}")
    print(f"\nwrote {scoreboard_path}")
    print(f"wrote {summary_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
