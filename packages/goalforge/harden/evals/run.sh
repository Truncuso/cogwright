#!/usr/bin/env bash
# evals/run.sh — goalforge-harden checks
#
# Check types:
#   STATIC-CONTRACT: asserts SKILL.md declares the C1-C7 contract this slim
#                     skill now states (wp-01-slim-core: G1-G4 gates)
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
PASS=0
FAIL=0

check() {
  local desc="$1"
  local pattern="$2"
  if grep -qF -- "$pattern" "$SKILL_MD"; then
    echo "  PASS [STATIC-CONTRACT]: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL [STATIC-CONTRACT]: $desc"
    echo "        expected to find: $pattern"
    FAIL=$((FAIL+1))
  fi
}

echo "=== goalforge-harden: contract checks ==="

check "skill name declared" "name: goalforge-harden"
check "precondition: WP overview.md at status: spec, C1 eight-section shape" "the WP \`overview.md\`"
check "four fixed gates named (G1-G4)" "G1 dependency frontier, G2 deterministic"

# G1 — dependency frontier
check "G1 runs goalforge-frontier.sh" "goalforge-frontier.sh"
check "G1 hardens only a WP in hardenable[], deps verified or archived" "hardenable[]"

# G2 — deterministic lint + open questions
check "G2 runs goalforge-preharden-lint.sh" "goalforge-preharden-lint.sh"
check "G2 runs goalforge-open-questions-gate.sh --check" "goalforge-open-questions-gate.sh --check"
check "unattended respondent is an agent, stamped answered_by: agent" "stamping \`answered_by:"

# G3 — review pass, bounded by stop rule
check "G3 stop-rule script goalforge-harden-stop.sh with exit codes 0/3/2" "goalforge-harden-stop.sh <wp-dir>   # 0 run, 3 park, 2 error"
check "G3 panel convened iff severity HIGH and register production" "iff \`severity: HIGH\`"
check "G3 reviewers run in fresh context, consumed as DATA" "Reviewers run in fresh"

# G4 — goal validate, changelog, hash, transition
check "G4 runs goalforge-validate.sh --strict" "goalforge-validate.sh --strict"
check "G4 runs goalforge-goal-changelog.sh append" "goalforge-goal-changelog.sh append"
check "G4 runs goalforge-goal-hash.sh --record" "goalforge-goal-hash.sh --record"
check "G4 records hash last, after the goal block validates" "record the hash last so"

# hardened -> ready human gate (C7)
check "human_required is a veto an agent may set but never clear" "a **veto** over"
check "human decides iff register production and severity HIGH" "register: production\` and \`severity: HIGH\`"
check "auto-advance leaves signal evidence in the ledger" "advance autonomously"

# Gotchas
check "goal edit after approval trips evolved-goal-without-reharden under --strict" "evolved-goal-without-reharden"
check "a park is only reviewable through harden.parked + answered_by: agent stamps" "\`harden.parked\` row and the"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
