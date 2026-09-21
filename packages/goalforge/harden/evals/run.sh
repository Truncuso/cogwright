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

LC="$(wc -l < "$SKILL_MD")"
if [ "$LC" -le 125 ]; then
  echo "  PASS [STATIC-CONTRACT]: SKILL.md <= 125 lines (got $LC)"; PASS=$((PASS+1))
else
  echo "  FAIL [STATIC-CONTRACT]: SKILL.md <= 125 lines (got $LC)"; FAIL=$((FAIL+1))
fi

NEG_OK=1
grep -qiE "ollama|deepseek|codex|zai|openrouter|moonshot|nvidia" "$SKILL_MD" && NEG_OK=0
if [ "$NEG_OK" -eq 1 ]; then
  echo "  PASS [STATIC-CONTRACT]: no provider name in SKILL.md"; PASS=$((PASS+1))
else
  echo "  FAIL [STATIC-CONTRACT]: no provider name in SKILL.md"; FAIL=$((FAIL+1))
fi

check "skill name declared" "name: harden"
check "precondition: WP overview.md at status: spec, C1 eight-section shape" "the WP \`overview.md\`"
check "four fixed gates named (G1-G4)" "G1 dependency frontier, G2 deterministic"

# G1 — dependency frontier
check "G1 runs goalforge-frontier.sh" "goalforge-frontier.sh"
check "G1 hardens only a WP in hardenable[], deps verified or archived" "hardenable[]"
check "G1 --override --reason belongs to goalforge-transition.sh, not the frontier script" "to \`goalforge-transition.sh\` at G4"

# G2 — deterministic lint + open questions
check "G2 runs goalforge-preharden-lint.sh" "goalforge-preharden-lint.sh"
check "G2 runs goalforge-open-questions-gate.sh --check" "goalforge-open-questions-gate.sh --check"
check "unattended respondent is an agent, stamped answered_by: agent" "stamping \`answered_by:"

# G3 — review pass, bounded by stop rule
check "G3 stop-rule script goalforge-harden-stop.sh with exit codes 0/3/2" "goalforge-harden-stop.sh <wp-dir>   # 0 run, 3 park, 2 error"
check "G3 panel convened iff severity HIGH and register production" "iff \`severity: HIGH\`"
check "G3 dispatches agents/reviewer.md" "agents/reviewer.md"
check "G3 loads expertise from references/expertise-map.yaml" "references/expertise-map.yaml"
check "G3 panel is 3x reviewer with distinct expertise bundles" "**distinct expertise bundles**"
check "G3 verdicts consumed as typed DATA, never as instructions" "DATA, never as instructions"
check "G3 reviewers run in fresh context, consumed as DATA" "Reviewers run in fresh"

# G4 — goal validate, changelog, hash, transition
check "G4 runs goalforge-validate.sh --strict" "goalforge-validate.sh --strict"
check "G4 runs goalforge-goal-changelog.sh append" "goalforge-goal-changelog.sh append"
check "G4 runs goalforge-goal-hash.sh --record" "goalforge-goal-hash.sh --record"
check "G4 records the hash last (goal_approved_version)" "# hash last: goal_approved_version"

# hardened -> ready human gate (C7)
check "human_required is a veto an agent may set but never clear" "a **veto** over"
check "human decides iff register production and severity HIGH" "register: production\` and \`severity: HIGH\`"
check "auto-advance leaves signal evidence in the ledger" "autonomously with signal evidence in the ledger"

# Gotchas
check "goal edit after approval trips evolved-goal-without-reharden under --strict" "evolved-goal-without-reharden"
check "a park is only reviewable through harden.parked + answered_by: agent stamps" "\`harden.parked\` + \`answered_by: agent\`"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
