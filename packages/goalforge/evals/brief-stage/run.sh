#!/usr/bin/env bash
# brief-stage eval suite (wp-06 task-05) — the full gate for the goalforge/brief
# stage. Aggregates every per-task case under cases/ and exits 0 only when all
# pass. Deterministic, offline (no network / model calls).
#
# Coverage (maps to the WP goal.verification checks a–e):
#   complexity-gate.sh              (a) complexity gate: medium triggers, low does not
#   artifact-shape-delta-only.sh    (b) delta-only artifact shape {task,created,brief_tier}
#   validate-briefed-ok.sh          (c) briefed status validates with 0 errors
#   validate-gated-skip-flagged.sh  (c) static brief-skip invariant (high vs low)
#   staleness-drift.sh              (d) staleness drift trips re-validation → re-brief request
#   staleness-fresh.sh              (e) fresh brief passes unchanged
#   sanctioned-write-not-blocked.sh (Step 5) pending→briefed sanctioned Bash-path write not hook-blocked
set -uo pipefail

CASE_DIR="$(cd "$(dirname "$0")/cases" && pwd)"

# Deterministic, explicit order (a → e → Step 5).
CASES=(
  complexity-gate.sh
  artifact-shape-delta-only.sh
  validate-briefed-ok.sh
  validate-gated-skip-flagged.sh
  staleness-drift.sh
  staleness-fresh.sh
  sanctioned-write-not-blocked.sh
)

pass=0
fail=0
failed_names=""

echo "=== goalforge brief-stage eval suite (wp-06) ==="
for c in "${CASES[@]}"; do
  path="$CASE_DIR/$c"
  if [ ! -f "$path" ]; then
    echo "MISSING: $c"
    fail=$((fail+1))
    failed_names="$failed_names $c(missing)"
    continue
  fi
  out="$(bash "$path" 2>&1)"
  rc=$?
  last="$(printf '%s\n' "$out" | tail -n1)"
  if [ "$rc" -eq 0 ]; then
    echo "ok   $c — $last"
    pass=$((pass+1))
  else
    echo "FAIL $c (rc=$rc)"
    printf '%s\n' "$out" | sed 's/^/       /'
    fail=$((fail+1))
    failed_names="$failed_names $c"
  fi
done

echo "-----------------------------------------------"
echo "brief-stage: $pass passed, $fail failed (of ${#CASES[@]})"
if [ "$fail" -ne 0 ]; then
  echo "FAILED:$failed_names"
  exit 1
fi
echo "brief-stage suite: ALL PASS"
exit 0
