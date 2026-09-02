#!/usr/bin/env bash
# convert-canonical.test.sh — the gate for the canonical-shape conversion.
#
# RED before convert-canonical.py runs: trigger-run.sh --dry-run reports 13
# shape errors and exits 2. GREEN after: files_found 13, files_canonical 13,
# shape_errors [], plus a re-run of the converter that leaves no git diff.
#
# The shared runner is resolved the way trigger-run.sh resolves it; set
# SKILL_TRIGGER_RUNNER to point at a checkout. If the runner is absent the
# caller prints a `gap:` marker and exits 0 — this test then FAILS rather than
# reading a skipped run as a pass.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PKG_ROOT" && git rev-parse --show-toplevel)"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# --- 1. shape gate ----------------------------------------------------------
report="$(bash "$HERE/trigger-run.sh" --dry-run 2>/dev/null)"
rc=$?

grep -q '"files_found": 13' <<<"$report" || fail "files_found is not 13"
grep -q '"files_canonical": 13' <<<"$report" || fail "files_canonical is not 13 (pre-conversion dialect still present)"
grep -q '"shape_errors": \[\]' <<<"$report" || fail "shape_errors is not empty"
[ "$rc" -eq 0 ] || fail "trigger-run.sh --dry-run exited $rc, expected 0"
grep -q '"coverage": "skipped"' <<<"$report" || fail "--dry-run must report coverage skipped"

# --- 2. converter idempotency ----------------------------------------------
# Compare the tree's diff before and after a re-run. Once the conversion is
# committed the working tree is clean, `pre` is empty, and this reduces exactly
# to `git diff --quiet -- packages/goalforge`, asserted explicitly below.
pre="$(git -C "$REPO_ROOT" diff -- packages/goalforge)"
python3 "$HERE/convert-canonical.py" >/dev/null || fail "convert-canonical.py exited non-zero"
post="$(git -C "$REPO_ROOT" diff -- packages/goalforge)"
[ "$pre" = "$post" ] || fail "re-running convert-canonical.py changed packages/goalforge (not idempotent)"
if [ -z "$pre" ]; then
    git -C "$REPO_ROOT" diff --quiet -- packages/goalforge \
        || fail "git diff -- packages/goalforge is not clean after a converter re-run"
fi

echo "PASS: 13/13 canonical, no shape errors, converter idempotent"
