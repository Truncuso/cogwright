#!/usr/bin/env bash
# run.sh — deterministic eval suite for the WP-04 execution_plan CONSUMER.
#
# Drives the REAL deterministic consumer boundary
# skills/goalforge/run/scripts/goalforge-plan-consumer.sh (never a hypothetical
# mock) over the fixture suite, asserting every case named in the WP
# goal.verification check. Dispatch resolution is read from the consumer's stub
# dispatch log (the parsed execution_plan) — no live model calls. Exits 0 only
# when all assertions pass; prints the first failure and exits 1 otherwise.
#
# Cases (WP goal.verification):
#   (a) 3-step satisfiable contiguous plan drives exactly those steps
#   (b) inline-vs-agent dispatch resolved from the stub dispatch log
#   (c) parallel:[[a],[b,c]] read as two sequential batches
#   (d) absent execution_plan: block => standard route + legacy all-inline
#   (e) consumer source makes ZERO calls to goalforge-route.sh
#   (f) stale / precondition-inconsistent / unresolvable plans are rejected
#       (hard non-silent failure, exit non-zero)
set -uo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$SUITE_DIR/fixtures"
CONSUMER="$SUITE_DIR/../../run/scripts/goalforge-plan-consumer.sh"

fail=0

pass() { printf 'PASS  %s\n' "$1"; }
fault() { printf 'FAIL  %s\n' "$1" >&2; fail=1; }

# assert_eq <label> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then pass "$1"; else
    fault "$1"; printf '        expected: %q\n        actual:   %q\n' "$2" "$3" >&2
  fi
}

# assert_reject <label> <fixture-overview> — consumer must exit non-zero on --emit-batches
assert_reject() {
  local label="$1" ov="$2" out rc
  out="$(bash "$CONSUMER" --emit-batches "$ov" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    pass "$label (exit $rc, non-silent)"
  else
    fault "$label — expected non-zero exit, got 0"; printf '        output: %s\n' "$out" >&2
  fi
}

[ -f "$CONSUMER" ] || { echo "run.sh: consumer script not found: $CONSUMER" >&2; exit 1; }

# --- (a) 3-step satisfiable contiguous plan drives exactly those steps ---
a_out="$(bash "$CONSUMER" --emit-batches "$FIX/three-step/overview.md")"
a_steps="$(echo "$a_out" | sed 's/^batch [0-9]*: //' | tr ',' '\n' | sort | paste -sd, -)"
assert_eq "(a) three-step drives exactly [decompose,harden,spec]" "decompose,harden,spec" "$a_steps"

# --- (b) inline-vs-agent dispatch from the stub dispatch log ---
assert_eq "(b) mixed-dispatch decompose => agent" "agent" \
  "$(bash "$CONSUMER" --dispatch-of decompose "$FIX/mixed-dispatch/overview.md")"
assert_eq "(b) mixed-dispatch harden => inline (explicit)" "inline" \
  "$(bash "$CONSUMER" --dispatch-of harden "$FIX/mixed-dispatch/overview.md")"
assert_eq "(b) mixed-dispatch spec => inline (implicit default)" "inline" \
  "$(bash "$CONSUMER" --dispatch-of spec "$FIX/mixed-dispatch/overview.md")"

# --- (c) parallel:[[a],[b,c]] => two sequential batches ---
c_out="$(bash "$CONSUMER" --emit-batches "$FIX/parallel-groups/overview.md")"
assert_eq "(c) parallel-groups batch count = 2" "2" "$(echo "$c_out" | grep -c '^batch ')"
assert_eq "(c) parallel-groups batch 1 = spec" "batch 1: spec" "$(echo "$c_out" | sed -n '1p')"
assert_eq "(c) parallel-groups batch 2 = decompose,harden" "batch 2: decompose,harden" "$(echo "$c_out" | sed -n '2p')"

# --- (d) absent block => standard route + legacy all-inline singleton batches ---
assert_eq "(d) no-plan route => standard" "standard" \
  "$(bash "$CONSUMER" --route "$FIX/no-plan/overview.md")"
d_out="$(bash "$CONSUMER" --emit-batches "$FIX/no-plan/overview.md")"
assert_eq "(d) no-plan emits 7 singleton batches (full chain)" "7" "$(echo "$d_out" | grep -c '^batch ')"
assert_eq "(d) no-plan batch 1 = capture (canonical chain order)" "batch 1: capture" "$(echo "$d_out" | sed -n '1p')"
assert_eq "(d) no-plan spec dispatch => inline (legacy all-inline)" "inline" \
  "$(bash "$CONSUMER" --dispatch-of spec "$FIX/no-plan/overview.md")"

# --- (e) consumer source makes ZERO calls to goalforge-route.sh ---
# Only doc-comment mentions are allowed; a CALL would be a non-comment line
# invoking the script. Assert no non-comment line references goalforge-route.sh.
route_calls="$(grep -n 'goalforge-route\.sh' "$CONSUMER" | grep -v '^[0-9]*:[[:space:]]*#' | grep -v '# ' || true)"
assert_eq "(e) zero calls to goalforge-route.sh in consumer source" "" "$route_calls"

# --- (f) stale / precondition-inconsistent / unresolvable => hard rejection ---
assert_reject "(f) stale-plan (dispatch names absent step)" "$FIX/stale-plan/overview.md"
assert_reject "(f) precondition-inconsistent (non-contiguous steps)" "$FIX/precondition-inconsistent/overview.md"
assert_reject "(f) unresolvable-step (no chain basename)" "$FIX/unresolvable-step/overview.md"
assert_reject "(f) parallel-omits-step (uncovered declared step)" "$FIX/parallel-omits-step/overview.md"
assert_reject "(f) parallel-duplicate-step (step in two groups)" "$FIX/parallel-duplicate-step/overview.md"
assert_reject "(f) parallel-empty (parallel: [] drops all steps)" "$FIX/parallel-empty/overview.md"

echo "---"
if [ "$fail" -eq 0 ]; then
  echo "runner-plan-consumer eval suite: ALL PASS"
  exit 0
else
  echo "runner-plan-consumer eval suite: FAILURES above" >&2
  exit 1
fi
