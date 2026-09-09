#!/usr/bin/env bash
# Eval harness for the wp-07 wave route (planning-fan-out choreography).
# Deterministic, no model, no network. Exit 0 = all pass, non-zero = failures.
#
# Covers WP goal.verification checks (a)–(c2):
#   (a) a wave-route fixture execution_plan lists the ACTIVE four wave-stage
#       sequence (explore, parallel-spec, cross-spec-judge, fixer) in order;
#   (b) a 2-feature fixture's owned-set declarations are disjoint;
#   (c) an overlapping-owned-set fixture is flagged by the ownership check;
#   (c2) a nested-glob owned-set collision is flagged by containment, not
#        literal-string overlap.
#
# (d) — run/SKILL.md carrying an inline wave worked-example + a
# dispatch-template.md cross-ref — is DELETED (wp-01 round 2, gate B new
# finding): T21 cut run/SKILL.md to a 52-line chain-driver skill that owns
# none of that content any more (`references/dispatch-template.md` is the
# sole home for the wave-orchestration text now). The assertion tested
# machinery this WP removed.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GOALFORGE_DIR="$(cd "$HERE/../.." && pwd)"
FIXTURES="$HERE/fixtures"
DISJOINT_CHECK="$HERE/owned-set-disjoint.py"
PASS=0
FAIL=0

check() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "pass" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== wave-route eval harness ==="
echo ""

# ── (a) execution_plan stage order ───────────────────────────────────────────
echo "[ (a) active four-stage sequence order ]"

PLAN_FIXTURE="$FIXTURES/wave-execution-plan.md"
ORDER_OK="pass"
if [ -f "$PLAN_FIXTURE" ]; then
  # route: must be pinned explicitly to wave.
  grep -qE '^route:[[:space:]]*wave$' "$PLAN_FIXTURE" || ORDER_OK="fail"
  # Line numbers of each active stage token in execution_plan.steps.
  L_EXPLORE=$(grep -n '^\s*-\s*explore-fan-out$'        "$PLAN_FIXTURE" | head -1 | cut -d: -f1)
  L_PARALLEL=$(grep -n '^\s*-\s*parallel-spec-authors$' "$PLAN_FIXTURE" | head -1 | cut -d: -f1)
  L_JUDGE=$(grep -n '^\s*-\s*cross-spec-judge$'         "$PLAN_FIXTURE" | head -1 | cut -d: -f1)
  L_FIXER=$(grep -n '^\s*-\s*fixer$'                    "$PLAN_FIXTURE" | head -1 | cut -d: -f1)
  if [ -z "$L_EXPLORE" ] || [ -z "$L_PARALLEL" ] || [ -z "$L_JUDGE" ] || [ -z "$L_FIXER" ]; then
    ORDER_OK="fail"
  elif ! { [ "$L_EXPLORE" -lt "$L_PARALLEL" ] && [ "$L_PARALLEL" -lt "$L_JUDGE" ] && [ "$L_JUDGE" -lt "$L_FIXER" ]; }; then
    ORDER_OK="fail"
  fi
  # Deferred stages must NOT appear in the active steps fixture.
  grep -qE '^\s*-\s*(cold-tier1-audit|parallel-hygiene)' "$PLAN_FIXTURE" && ORDER_OK="fail"
else
  ORDER_OK="fail"
fi
check "execution_plan lists explore→parallel-spec→cross-spec-judge→fixer in order" "$ORDER_OK"

echo ""

# ── (b) disjoint owned-sets pass ─────────────────────────────────────────────
echo "[ (b) disjoint owned-sets ]"

DISJOINT_OK="pass"
if python3 "$DISJOINT_CHECK" \
     "$FIXTURES/disjoint/brief-feature-a.md" \
     "$FIXTURES/disjoint/brief-feature-b.md" | grep -q '^DISJOINT$'; then
  DISJOINT_OK="pass"
else
  DISJOINT_OK="fail"
fi
check "2-feature disjoint fixture passes the ownership check (exit 0/DISJOINT)" "$DISJOINT_OK"

echo ""

# ── (c) overlapping owned-set flagged ────────────────────────────────────────
echo "[ (c) overlapping owned-set flagged ]"

OVERLAP_OK="pass"
set +e
OVERLAP_OUT=$(python3 "$DISJOINT_CHECK" \
     "$FIXTURES/overlap/brief-feature-a.md" \
     "$FIXTURES/overlap/brief-feature-b.md")
OVERLAP_RC=$?
set -e
# Must exit 1 AND name the overlap on the shared path.
if [ "$OVERLAP_RC" -eq 1 ] && echo "$OVERLAP_OUT" | grep -q '^OVERLAP '; then
  OVERLAP_OK="pass"
else
  OVERLAP_OK="fail"
fi
check "overlapping owned-set fixture is flagged (exit 1/OVERLAP)" "$OVERLAP_OK"

echo ""

# ── (c2) nested-glob owned-set collision flagged ─────────────────────────────
echo "[ (c2) nested-glob owned-set collision flagged ]"

NESTED_OK="pass"
set +e
NESTED_OUT=$(python3 "$DISJOINT_CHECK" \
     "$FIXTURES/nested-overlap/brief-feature-a.md" \
     "$FIXTURES/nested-overlap/brief-feature-b.md")
NESTED_RC=$?
set -e
# Owned globs are DIFFERENT literal strings but cover overlapping path-trees;
# a literal set-intersection would miss this. Must be flagged via containment.
if [ "$NESTED_RC" -eq 1 ] && echo "$NESTED_OUT" | grep -q '^OVERLAP '; then
  NESTED_OK="pass"
else
  NESTED_OK="fail"
fi
check "nested-glob owned-set collision is flagged (exit 1/OVERLAP)" "$NESTED_OK"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
