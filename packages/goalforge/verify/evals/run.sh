#!/usr/bin/env bash
# evals/run.sh — goalforge-verify checks
#
# Check types:
#   STATIC-CONTRACT: asserts SKILL.md declares the C1-C7 contract this slim
#                     skill now states (wp-01-slim-core: gates A/B/C over the
#                     WP's single commit, implemented -> verified)
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

echo "=== goalforge-verify: contract checks ==="

check "skill name declared" "name: goalforge-verify"
check "three gates over the WP's single commit, sole implemented -> verified authority" "Three gates over the WP's single commit"
check "precondition status: implemented (or verified idempotent re-run)" "status: implemented\` (or \`verified\` on an idempotent re-run)"
check "a WP still at executing was built outside the chain, re-run via /implement" "re-run it through \`/implement\`"

# Gate protocol
check "gate-budget script gates each pass with an explicit --feature-dir" "goalforge-gate-budget.sh <gate> --feature-dir"
check "exit 4 = gate.disabled WARN row, gate skipped and noted in findings.md" "gate.disabled\` WARN row"
check "a gate's internal error is exit 2, a failure never a pass" "A gate's internal error is exit 2"

# Gate A
check "gate A: repo lint and type-check whole-repo once" "Repo lint and type-check, whole-repo, once"
check "gate A: goal.verification.command exactly as written" "The WP's \`goal.verification.command\`, exactly as written"
check "gate A: boundary check — diff paths inside owned_files, else BLOCK" "every path in the cumulative diff is inside the WP's"
check "gate A failure sends the WP back to executing" "send the WP back to"

# Gate B
check "gate B: one review pass, fresh context, different model from executor" "in a **fresh context**"
check "gate B: CRITICAL findings BLOCK, HIGH recorded and re-dispatched once" "CRITICAL findings BLOCK"

# Gate C
check "gate C: goal judge binary rubric (outcome/behaviors/no-shim/scope)" "**No shim**"
check "gate C: any FAIL is a not-met verdict and BLOCKs" "Any FAIL is a not-met verdict"
check "gate C: one foreign second opinion via headless_dispatch" "headless_dispatch"
check "gate C: skip recorded as second_opinion.skipped with reason, a skip is legal" "a skip is legal, a silent omission is not"
check "judge/second-opinion disagreement escalates to the human, never break the tie" "escalates to the human"

# Completion
check "advance status then emit wp.verified" "emit \`wp.verified\`"
check "last WP triggers one integration review over the whole-feature diff" "Last WP?"

# Gotchas
check "a gate that does not emit gate.result is not a gate" "A gate that does not emit \`gate.result\` is not a gate"
check "the second opinion checks the judge, not the code" "checks the judge, not the code"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
