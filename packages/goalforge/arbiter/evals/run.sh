#!/usr/bin/env bash
# evals/run.sh — goalforge-arbiter static-contract checks
# The skill is model-driven (approach normalization + arbitration); behavioral
# output cannot be asserted without a model call, so these are static-contract
# checks over SKILL.md plus a wiring check against goalforge-harden.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
SDD_HARDEN_MD="$(cd "$SKILL_DIR/../harden" && pwd)/SKILL.md"
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

echo "=== goalforge-arbiter: static-contract checks ==="

# Identity + version
check "skill name declared" "name: goalforge-arbiter"
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
check "status authority stays with goalforge-harden" "status authority"

# Stakes tiering (quick-compare vs full grid)
check "stakes tiering section present" "Stakes tiering"
check "quick-compare retains rollback axis" "rollback axis is never dropped"
check "quick-compare fails safe to full grid" "fail-safe"
check "full grid keeps seven axes" "Seven axes, not six — on the full grid"
check "optional cheap-tier grid via arbiter-grid role" "arbiter-grid"

# Hygiene
check "Gotchas section present" "## Gotchas"

# Wiring: harden references goalforge-arbiter
check "harden wires goalforge-arbiter" "goalforge-arbiter" "$SDD_HARDEN_MD"


# ── BEHAVIORAL (via goal router): a judgment goal is never decided in-script ─
# The arbiter's boundary — advisory, model-driven, never a deterministic
# verdict — has a deterministic half that IS executable: goalforge-goal-eval.py
# must route a `judge` goal OUT (exit 2 with a dispatch directive) instead of
# deciding it, and must fail closed on a malformed judge check rather than
# fabricating one.
GOAL_EVAL="$(cd "$SKILL_DIR/.." && pwd)/scripts/goalforge-goal-eval.py"
JUDGE_FIXTURE="$SKILL_DIR/evals/fixtures/judge-goal.md"
BAD_JUDGE_FIXTURE="$SKILL_DIR/evals/fixtures/malformed-judge-goal.md"

for f in "$JUDGE_FIXTURE" "$BAD_JUDGE_FIXTURE"; do
  if [ -f "$f" ]; then
    echo "  PASS: fixture exists: $(basename "$f")"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: fixture missing: $f"
    FAIL=$((FAIL + 1))
  fi
done

JRC=0
JOUT="$(python3 "$GOAL_EVAL" --wp "$JUDGE_FIXTURE" 2>&1)" || JRC=$?
if [ "$JRC" -eq 2 ] && printf '%s' "$JOUT" | grep -q '"dispatch": "judge"'; then
  echo "  PASS: judge goal routed out undecided (exit 2 + dispatch directive)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: judge goal must exit 2 with a judge dispatch directive (rc=$JRC)"
  printf '%s\n' "$JOUT" | sed 's/^/        /'
  FAIL=$((FAIL + 1))
fi

BRC=0
BOUT="$(python3 "$GOAL_EVAL" --wp "$BAD_JUDGE_FIXTURE" 2>&1)" || BRC=$?
if [ "$BRC" -ne 0 ] && [ "$BRC" -ne 2 ] && printf '%s' "$BOUT" | grep -q 'not a mapping'; then
  echo "  PASS: malformed judge check fails closed (no fabricated verdict)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: malformed judge check must fail closed, not decide (rc=$BRC)"
  printf '%s\n' "$BOUT" | sed 's/^/        /'
  FAIL=$((FAIL + 1))
fi
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
