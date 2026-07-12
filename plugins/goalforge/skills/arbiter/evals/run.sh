#!/usr/bin/env bash
# evals/run.sh — sdd-arbiter static-contract checks
# The skill is model-driven (approach normalization + arbitration); behavioral
# output cannot be asserted without a model call, so these are static-contract
# checks over SKILL.md plus a wiring check against sdd-harden.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
SDD_HARDEN_MD="$(cd "$SKILL_DIR/../sdd-harden" && pwd)/SKILL.md"
PASS=0
FAIL=0

check() {
  local desc="$1"
  local pattern="$2"
  local file="${3:-$SKILL_MD}"
  if grep -qF "$pattern" "$file"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "        expected to find: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== sdd-arbiter: static-contract checks ==="

# Identity + version
check "skill name declared" "name: sdd-arbiter"
check "version declared" "version: 1.1.0"

# Trigger conditions
check "trigger: decision-required flag" "decision-required"
check "trigger: hard-to-reverse bet" "hard-to-reverse"

# Seven normalization axes
check "normalization axis: objective" "objective"
check "normalization axis: assumptions" "assumptions"
check "normalization axis: files touched" "files touched"
check "normalization axis: sequencing" "sequencing"
check "normalization axis: validation" "validation"
check "normalization axis: rollback" "rollback"
check "normalization axis: cost" "cost"

# Cross-review step
check "cross-review is dimension-by-dimension" "dimension-by-dimension"

# Decision memo output
check "decision memo output documented" "decision memo"
check "decision memo: chosen direction" "chosen direction"
check "decision memo: rejected alternatives" "rejected"
check "decision memo: verification gates" "verification gates"

# Advisory boundary
check "advisory / non-blocking" "advisory"
check "does not change human-gated transition" "hardened"
check "status authority stays with sdd-harden" "status authority"

# Stakes tiering (quick-compare vs full grid)
check "stakes tiering section present" "Stakes tiering"
check "quick-compare retains rollback axis" "rollback axis is never dropped"
check "quick-compare fails safe to full grid" "fail-safe"
check "full grid keeps seven axes" "Seven axes, not six — on the full grid"
check "optional cheap-tier grid via arbiter-grid role" "arbiter-grid"

# Hygiene
check "Gotchas section present" "## Gotchas"

# Wiring: sdd-harden references sdd-arbiter
# NOTE: this check is EXPECTED TO FAIL — the orchestrator wires sdd-harden,
# not this skill. It will pass once WP-orchestration wires the caller.
check "sdd-harden wires sdd-arbiter" "sdd-arbiter" "$SDD_HARDEN_MD"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
