#!/usr/bin/env bash
# Eval harness for schema v5 (route enum, execution_plan, optional_depends_on,
# goal-mandatory marker). Offline, deterministic, no network/model calls.
# Drives each fixture in fixtures/ through goalforge-validate.sh and asserts the
# expected exit code AND (for the WARN-sensitive cases) WARN presence/absence
# in --show output. Exit 0 only if every case + both self-tests pass.
#
# Cases (WP goal.verification.check, plans/goalforge/wp-01-schema-v5/overview.md):
#   (a) v5-marked WP missing goal: at ready → rejected
#   (b) legacy no-marker WP at ready → accepted
#   (c) execution_plan: block (4-route enum + steps/dispatch/parallel/tiers)
#       parses without error
#   (d) dangling optional_depends_on target → non-fatal WARN, exit 0
#   (e) v5-marked WP WITH complete goal at ready → accepted, AND a
#       present-target optional_depends_on emits no WARN (positive direction)
#   (f) templates/wp-overview.md + templates/feature-overview.md carry
#       schema_version: 5
#   (g) goalforge-goal-hash.sh --self-test and goalforge-validate.sh --self-test both exit 0

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURES_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
VALIDATE_SH="$SKILL_DIR/scripts/goalforge-validate.sh"
GOAL_HASH_SH="$SKILL_DIR/scripts/goalforge-goal-hash.sh"
TEMPLATES_DIR="$SKILL_DIR/references/templates"

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

echo "=== schema-v5 fixture eval harness ==="
echo ""

# ── (a) v5-marked WP missing goal: at ready → rejected ──────────────────────
out_a="$(bash "$VALIDATE_SH" --show "$FIXTURES_DIR/a-v5-missing-goal" 2>&1)"
rc_a=$?
if [ "$rc_a" -ne 0 ] && echo "$out_a" | grep -q "goal:\` block is mandatory"; then
  check "(a) v5-marked WP missing goal at ready is rejected (non-zero exit + goal-mandatory ERROR)" "pass"
else
  check "(a) v5-marked WP missing goal at ready is rejected (non-zero exit + goal-mandatory ERROR)" "fail"
fi

# ── (b) legacy no-marker WP at ready → accepted ─────────────────────────────
out_b="$(bash "$VALIDATE_SH" --show "$FIXTURES_DIR/b-legacy-no-marker" 2>&1)"
rc_b=$?
if [ "$rc_b" -eq 0 ]; then
  check "(b) legacy no-marker WP at ready is accepted (exit 0)" "pass"
else
  check "(b) legacy no-marker WP at ready is accepted (exit 0)" "fail"
fi

# ── (c) execution_plan: block round-trips without error ─────────────────────
out_c="$(bash "$VALIDATE_SH" --show "$FIXTURES_DIR/c-execution-plan-roundtrip" 2>&1)"
rc_c=$?
if [ "$rc_c" -eq 0 ] && ! echo "$out_c" | grep -q "^ERROR"; then
  check "(c) execution_plan: block (4-route enum + steps/dispatch/parallel/tiers) parses without error" "pass"
else
  check "(c) execution_plan: block (4-route enum + steps/dispatch/parallel/tiers) parses without error" "fail"
fi

# ── (d) dangling optional_depends_on target → non-fatal WARN, exit 0 ────────
out_d="$(bash "$VALIDATE_SH" --show "$FIXTURES_DIR/d-dangling-optional-dep" 2>&1)"
rc_d=$?
if [ "$rc_d" -eq 0 ] && echo "$out_d" | grep -q "^WARN.*optional_depends_on: wp-99-ghost.*target not found"; then
  check "(d) dangling optional_depends_on target → non-fatal WARN, exit 0" "pass"
else
  check "(d) dangling optional_depends_on target → non-fatal WARN, exit 0" "fail"
fi

# ── (e) v5 WP WITH complete goal at ready → accepted; present-target dep, no WARN ──
out_e="$(bash "$VALIDATE_SH" --show "$FIXTURES_DIR/e-v5-complete-goal-present-dep" 2>&1)"
rc_e=$?
if [ "$rc_e" -eq 0 ] && ! echo "$out_e" | grep -q "optional_depends_on"; then
  check "(e) v5 WP with complete goal accepted AND present-target optional_depends_on emits no WARN" "pass"
else
  check "(e) v5 WP with complete goal accepted AND present-target optional_depends_on emits no WARN" "fail"
fi

# ── (f) templates carry schema_version: 5 ───────────────────────────────────
if grep -q "^schema_version: 5" "$TEMPLATES_DIR/wp-overview.md" \
   && grep -q "^schema_version: 5" "$TEMPLATES_DIR/feature-overview.md"; then
  check "(f) templates/wp-overview.md + templates/feature-overview.md carry schema_version: 5" "pass"
else
  check "(f) templates/wp-overview.md + templates/feature-overview.md carry schema_version: 5" "fail"
fi

# ── (g) both scripts' --self-test exit 0 ────────────────────────────────────
bash "$GOAL_HASH_SH" --self-test >/dev/null 2>&1
rc_hash_selftest=$?
check "(g) goalforge-goal-hash.sh --self-test exits 0" "$([ "$rc_hash_selftest" -eq 0 ] && echo pass || echo fail)"

bash "$VALIDATE_SH" --self-test >/dev/null 2>&1
rc_validate_selftest=$?
check "(g) goalforge-validate.sh --self-test exits 0" "$([ "$rc_validate_selftest" -eq 0 ] && echo pass || echo fail)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
