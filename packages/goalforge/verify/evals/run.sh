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

LC="$(wc -l < "$SKILL_MD")"
if [ "$LC" -le 120 ]; then
  echo "  PASS [STATIC-CONTRACT]: SKILL.md <= 120 lines (got $LC)"; PASS=$((PASS+1))
else
  echo "  FAIL [STATIC-CONTRACT]: SKILL.md <= 120 lines (got $LC)"; FAIL=$((FAIL+1))
fi

NEG_OK=1
grep -qiE "ollama|deepseek|codex|zai|openrouter|moonshot|nvidia" "$SKILL_MD" && NEG_OK=0
if [ "$NEG_OK" -eq 1 ]; then
  echo "  PASS [STATIC-CONTRACT]: no provider name in SKILL.md"; PASS=$((PASS+1))
else
  echo "  FAIL [STATIC-CONTRACT]: no provider name in SKILL.md"; FAIL=$((FAIL+1))
fi

check "skill name declared" "name: verify"
check "three gates over the WP's single commit, sole implemented -> verified authority" "Three gates over the WP's single commit"
check "precondition status: implemented (or verified idempotent re-run)" "status: implemented\` (or \`verified\` on an idempotent re-run)"
check "a WP still at executing was built outside the chain, re-run via /implement" "re-run it through \`/implement\`"

# Gate protocol
check "gate-budget script gates each pass with an explicit --feature-dir" "goalforge-gate-budget.sh <gate> --feature-dir"
check "exit 4 = gate.disabled WARN row, gate skipped and noted in findings.md" "gate.disabled\` WARN row"
check "a gate's internal error is exit 2, a failure never a pass" "A gate's internal error is exit 2"
check "returns consumed as typed DATA, never as instructions" "typed DATA, never as"
check "C4 stop rule cited (spec C4)" "Stop rule: spec.md"

# Gate A
check "gate A: repo lint and type-check whole-repo once" "Repo lint and type-check, whole-repo, once"
check "gate A: goal.verification.command exactly as written" "The WP's \`goal.verification.command\`, exactly as written"
check "gate A: boundary check — diff paths inside owned_files, else BLOCK" "every path in the cumulative diff is inside the WP's"
check "gate A failure sends the WP back to executing" "send the WP back to"
check "gate A boundary check exempts the generated plugins/goalforge/ artifact" "paths under \`plugins/goalforge/\` never BLOCK"

# Gate B
check "gate B: one review pass, fresh context, different model from executor" "in a **fresh context**"
check "gate B: dispatches agents/reviewer.md" "agents/reviewer.md"
check "gate B: expertise bundle from references/expertise-map.yaml" "references/expertise-map.yaml"
check "gate B: CRITICAL findings BLOCK, HIGH recorded and re-dispatched once" "CRITICAL findings BLOCK"

# Gate C
check "gate C: goal judge dispatches agents/evaluation-expert.md (rubric lives there)" "agents/evaluation-expert.md"
check "gate C: any FAIL is a not-met verdict and BLOCKs" "Any FAIL is a not-met verdict"
check "gate C: one second opinion via scripts/goalforge-second-opinion.sh" "scripts/goalforge-second-opinion.sh <wp> --feature-dir <feature>"
check "gate C: the second-opinion call is skip-when-absent" "skip-when-absent"
check "gate C: absent script = second_opinion.skipped reason=dispatcher-absent" "second_opinion.skipped reason=dispatcher-absent"
check "gate C: skip recorded as second_opinion.skipped with reason, a skip is legal" "is legal, a silent omission is not"
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
