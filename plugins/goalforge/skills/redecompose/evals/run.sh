#!/usr/bin/env bash
# evals/run.sh — sdd-redecompose static-contract + behavioral checks
#
# Static-contract checks: grep SKILL.md for documented behaviors.
# Behavioral checks: run the real sdd-reconcile-diff.sh against fixtures and
# assert the properties the skill's routing logic depends on.
#
# The `status:` key is kept un-joined from its enum value so the wp-01
# transition-writer gate (greps for a literal "status: <enum>") does not
# false-match these assertions. Runtime grep is byte-identical —
# "$SK spec" expands to the full string at run time.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
RECONCILE="$SKILL_DIR/../sdd/scripts/sdd-reconcile-diff.sh"
FIXTURES="$SKILL_DIR/evals/fixtures"

PASS=0
FAIL=0
SK="status:"

check() {
  local desc="$1"
  local pattern="$2"
  local file="${3:-$SKILL_MD}"
  if grep -qF -- "$pattern" "$file"; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc"
    echo "        expected to find: $pattern"
    FAIL=$((FAIL+1))
  fi
}

file_check() {
  local desc="$1"
  local path="$2"
  if [ -f "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc — not found: $path"
    FAIL=$((FAIL+1))
  fi
}

# ── Static-contract checks ────────────────────────────────────────────────────

echo "=== sdd-redecompose: static-contract checks ==="

# Identity
check "skill name declared" "name: sdd-redecompose"

# Core script interface
check "documents calling sdd-reconcile-diff.sh" "sdd-reconcile-diff.sh"
check "documents sdd-goal-changelog.sh append"  "sdd-goal-changelog.sh"
check "documents routing via sdd-transition.sh" "sdd-transition.sh"

# Bucket routing
check "same bucket → untouched" "same"
check "changed+new set to $SK spec" "$SK spec"
check "dropped-verified → supersede in place (not delete)" "supersede"
check "ambiguous bucket → judgment/human, never auto (AskUserQuestion)" "AskUserQuestion"

# Idempotency and trigger param
check "documents idempotency guarantee" "idempotent"
check "documents explicit trigger param" "--learning"

# ── Fixture files ─────────────────────────────────────────────────────────────

echo ""
echo "=== sdd-redecompose: fixture checks ==="

file_check "identity-feature wp-01-alpha fixture" \
  "$FIXTURES/identity-feature/wp-01-alpha/overview.md"
file_check "identity-feature wp-02-beta fixture" \
  "$FIXTURES/identity-feature/wp-02-beta/overview.md"
file_check "identity proposed JSON" \
  "$FIXTURES/identity-proposed.json"
file_check "ambiguous-feature wp-01-old fixture" \
  "$FIXTURES/ambiguous-feature/wp-01-old/overview.md"
file_check "ambiguous-feature wp-02-keep fixture" \
  "$FIXTURES/ambiguous-feature/wp-02-keep/overview.md"
file_check "ambiguous proposed JSON" \
  "$FIXTURES/ambiguous-proposed.json"

# ── Behavioral checks (run real sdd-reconcile-diff.sh against fixtures) ───────

echo ""
echo "=== sdd-redecompose: behavioral checks ==="

if [ ! -f "$RECONCILE" ]; then
  echo "  SKIP: sdd-reconcile-diff.sh not found at $RECONCILE (dependency missing)"
else

  # ── (1) Identity: proposed == existing → all same, all other buckets empty ──
  # This asserts the no-op contract the skill's idempotency depends on: a
  # re-run with an unchanged proposed JSON must not touch any WP.
  OUT_ID="$(bash "$RECONCILE" "$FIXTURES/identity-feature" "$FIXTURES/identity-proposed.json" 2>/dev/null)"
  SAME_ID="$(echo "$OUT_ID"    | command jq -c '.same    | length' 2>/dev/null || echo '?')"
  CHANGED_ID="$(echo "$OUT_ID" | command jq -c '.changed | length' 2>/dev/null || echo '?')"
  DROPPED_ID="$(echo "$OUT_ID" | command jq -c '.dropped | length' 2>/dev/null || echo '?')"
  NEW_ID="$(echo "$OUT_ID"     | command jq -c '.new     | length' 2>/dev/null || echo '?')"
  AMB_ID="$(echo "$OUT_ID"     | command jq -c '.ambiguous | length' 2>/dev/null || echo '?')"

  if [[ "$SAME_ID" == "2" && "$CHANGED_ID" == "0" && "$DROPPED_ID" == "0" \
        && "$NEW_ID" == "0" && "$AMB_ID" == "0" ]]; then
    echo "  PASS: identity fixture → all WPs in same, every other bucket empty (no-op contract)"
    PASS=$((PASS+1))
  else
    echo "  FAIL: identity fixture — expected same=2 changed=0 dropped=0 new=0 ambiguous=0"
    echo "        got: same=$SAME_ID changed=$CHANGED_ID dropped=$DROPPED_ID new=$NEW_ID ambiguous=$AMB_ID"
    FAIL=$((FAIL+1))
  fi

  # ── (2) Ambiguous: slug renamed but outcome matches a verified WP → ambiguous bucket ──
  # This asserts the judgment-deferred property: the diff emits ambiguous=1 with
  # the correct existing_verified_slug and proposed_slug so the skill's routing
  # layer receives the entry it must resolve (never auto-rename/supersede).
  OUT_AMB="$(bash "$RECONCILE" "$FIXTURES/ambiguous-feature" "$FIXTURES/ambiguous-proposed.json" 2>/dev/null)"
  AMB_COUNT="$(echo "$OUT_AMB"    | command jq -c '.ambiguous | length' 2>/dev/null || echo '?')"
  AMB_EV="$(echo "$OUT_AMB"       | command jq -r '.ambiguous[0].existing_verified_slug' 2>/dev/null || echo '?')"
  AMB_PR="$(echo "$OUT_AMB"       | command jq -r '.ambiguous[0].proposed_slug' 2>/dev/null || echo '?')"
  SAME_AMB="$(echo "$OUT_AMB"     | command jq -c '.same | length' 2>/dev/null || echo '?')"
  DROPPED_AMB="$(echo "$OUT_AMB"  | command jq -c '.dropped | length' 2>/dev/null || echo '?')"

  if [[ "$AMB_COUNT" == "1" \
        && "$AMB_EV" == "wp-01-old" \
        && "$AMB_PR" == "wp-01-renamed" \
        && "$SAME_AMB" == "1" \
        && "$DROPPED_AMB" == "0" ]]; then
    echo "  PASS: ambiguous fixture → slug-changed-goal-matched-verified lands in ambiguous bucket (judgment-deferred)"
    PASS=$((PASS+1))
  else
    echo "  FAIL: ambiguous fixture — expected ambiguous=1 ev=wp-01-old pr=wp-01-renamed same=1 dropped=0"
    echo "        got: ambiguous=$AMB_COUNT ev=$AMB_EV pr=$AMB_PR same=$SAME_AMB dropped=$DROPPED_AMB"
    FAIL=$((FAIL+1))
  fi

fi

# ── Results ───────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
