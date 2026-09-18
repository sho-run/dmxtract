#!/usr/bin/env bash
# One-command DMXtract extraction benchmark: dump a directory of page-marked
# manual .txt files through the extractor, score the dumps against GDTF
# ground truth, and print the summary.
#
# All of this benchmark's inputs are local-only (mined manuals, the
# corpus-to-GDTF manifest, the ground-truth db) and are never committed -
# see README.md. This script only touches the public scripts/eval/ tool.
#
# Usage:
#   scripts/eval/run_benchmark.sh [text-dir] [work-dir]
#
#   text-dir  directory of page-marked *.txt manuals to extract.
#             Default: $DMXTRACT_EVAL_TEXT_DIR if set, otherwise this
#             script fails with a clear message (there is no public
#             default corpus).
#   work-dir  where dumps + scoreboard get written. Default: a fresh temp
#             dir under $TMPDIR (nothing under the repo is touched).
#
# Env:
#   DMXTRACT_UNIFIED_DB     path to unified.db (ground truth). Required.
#   DMXTRACT_EVAL_TEXT_DIR  fallback for the text-dir positional arg.
#
# Leaves `git status` clean: `flutter test` (run indirectly by nothing
# here, but by anyone who ran it earlier in the working tree) auto-writes
# an analyzer:exclude block into apps/web/analysis_options.yaml, so this
# script always `git checkout`s that file back before it exits - even on
# failure.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
WEB_DIR="$REPO_ROOT/apps/web"

TEXT_DIR="${1:-${DMXTRACT_EVAL_TEXT_DIR:-}}"
if [[ -z "$TEXT_DIR" ]]; then
  echo "error: no text-dir given and \$DMXTRACT_EVAL_TEXT_DIR is not set." >&2
  echo "usage: $0 [text-dir] [work-dir]" >&2
  echo "This benchmark's manual-text corpus is local-only - see README.md." >&2
  exit 1
fi
if [[ ! -d "$TEXT_DIR" ]]; then
  echo "error: text-dir not found: $TEXT_DIR" >&2
  exit 1
fi
if [[ -z "${DMXTRACT_UNIFIED_DB:-}" ]]; then
  echo "error: \$DMXTRACT_UNIFIED_DB is not set (ground-truth db, required)." >&2
  echo "This benchmark's ground-truth database is local-only - see README.md." >&2
  exit 1
fi
if [[ ! -f "$DMXTRACT_UNIFIED_DB" ]]; then
  echo "error: ground-truth database not found: $DMXTRACT_UNIFIED_DB" >&2
  exit 1
fi

WORK_DIR="${2:-$(mktemp -d "${TMPDIR:-/tmp}/dmxtract-eval.XXXXXX")}"
mkdir -p "$WORK_DIR"
EXTRACT_DIR="$WORK_DIR/extract"
SCORE_DIR="$WORK_DIR/score"
mkdir -p "$EXTRACT_DIR" "$SCORE_DIR"

restore_analysis_options() {
  # `flutter test`/`flutter analyze` (invoked anywhere in this working tree,
  # including by a developer in another terminal) auto-writes an
  # analyzer:exclude block into this file. Restore it, success or failure -
  # but only when the only uncommitted change is that auto-written block.
  # A developer's own legitimate edits to this file must never be silently
  # discarded just because the benchmark happened to run.
  local f="apps/web/analysis_options.yaml"
  local diff
  diff="$(git -C "$REPO_ROOT" diff -- "$f" 2>/dev/null)" || return 0
  [[ -z "$diff" ]] && return 0
  # Every changed line must be an addition, and every added line (besides
  # diff/hunk headers) must belong to the auto-written analyzer:exclude
  # block: "analyzer:", "  exclude:", or a "    - ..." bullet under it.
  if echo "$diff" | grep -qE '^-[^-]'; then
    echo "warning: $f has edits beyond the auto-written analyzer:exclude" >&2
    echo "block (removed lines present) - leaving it as-is, not restoring." >&2
    return 0
  fi
  local bad
  bad="$(echo "$diff" | grep -E '^\+[^+]' | grep -vE '^\+(analyzer:|  exclude:|    - )' || true)"
  if [[ -n "$bad" ]]; then
    echo "warning: $f has edits beyond the auto-written analyzer:exclude" >&2
    echo "block - leaving it as-is, not restoring. Unexpected lines:" >&2
    echo "$bad" >&2
    return 0
  fi
  git -C "$REPO_ROOT" checkout -- "$f" 2>/dev/null || true
}
trap restore_analysis_options EXIT

echo "== dumping extractions: $TEXT_DIR -> $EXTRACT_DIR =="
( cd "$WEB_DIR" && dart run tool/dump_extractions.dart "$TEXT_DIR" "$EXTRACT_DIR" )

echo
echo "== scoring: $EXTRACT_DIR -> $SCORE_DIR =="
python3 "$HERE/score_extraction.py" \
  --db "${DMXTRACT_UNIFIED_DB:-}" \
  --manifest "$REPO_ROOT/testcorpus/MANIFEST.local.md" \
  --extracts "$EXTRACT_DIR" \
  --out "$SCORE_DIR"

echo
echo "== summary ($SCORE_DIR/summary.md) =="
cat "$SCORE_DIR/summary.md"

echo
echo "work dir: $WORK_DIR"
