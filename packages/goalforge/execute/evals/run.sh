#!/usr/bin/env bash
# evals/run.sh — goalforge-execute checks
#
# Check types:
#   STATIC-CONTRACT: asserts SKILL.md declares the C1-C7 contract this slim
#                     skill now states (wp-01-slim-core: one dispatch, one
#                     commit, ready -> executing -> implemented)
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

echo "=== goalforge-execute: contract checks ==="

check "skill name declared" "name: execute"
check "drives ready -> executing -> implemented" "\`ready → executing →"
check "verified is written only by goalforge-verify, never here" "written only by"
check "re-entry: already executing skips the transition, resumes at step 2" "Already \`executing\` ⇒ re-entry"
check "status advance goes through the single writer, never hand-edited" "never hand-edit \`status:\`"
check "register production: deterministic gate mandatory, tests from behaviors[]" "\`goal.verification.behaviors[]\`, \`goal.verification.command\` must pass first"
check "register spike: spike code never merged, findings.md is the deliverable" "spike code is never merged"

# C5 — ownership decision
check "one agent owns the whole WP by default" "One agent owns the whole WP by default"
check "split only when owned_files > 8 or disjoint {files:} AND parallel: true" "more than 8 entries"
check "batches never commit — the one WP commit is execute's" "never commit**: the one WP commit is yours"
check "dispatch resolved via goalforge-pick-agent.py" "goalforge-pick-agent.py"
check "dispatch role is implement" "--role implement"
check "blast radius escalates the tier" "blast radius"
check "brief states model AND effort explicitly, not the agent default" "never the agent default"

# The WP brief
check "one brief per dispatch, written in-session, no brief/task files" "No brief files, no task files"
check "off-limits edit outside owned set is a BLOCKED return" "a needed edit outside the set is a BLOCKED"
check "premise-check: unmet premise is a first-class BLOCKED return" "Premise check"

# C4 — stop rule
check "stop rule: goal met, attempts >= 2, token ceiling, premise-blocked, repeat gate failure" "attempts >= 2\` on the same checklist item"
check "SDD_WP_TOKEN_CEILING default 400000" "SDD_WP_TOKEN_CEILING\` (default \`400000\`)"
check "on stop, findings.md gets the reason and finding.recorded emits" "emit \`finding.recorded\`"
check "unattended parks and exits cleanly on a stop" "SDD_AUTONOMY=unattended"

# Step 6 — deterministic eval, one commit
check "run goal.verification.command exactly as written, plus lint/typecheck" "exactly as written, plus repo lint"
check "exactly one conventional commit per WP" "make **exactly one** conventional"
check "commit emits commit.linked with its sha" "emit \`commit.linked\` with its sha"
check "advance to implemented, hand off to goalforge-verify" "hand off to \`goalforge-verify\`"

# Gotchas
check "verified is never written here — sole authority is goalforge-verify" "sole authority"
check "batches never commit — verify gate A checks diff paths subset owned_files" "diff paths ⊆ owned_files"
check "one owner is the default, not the fallback" "One owner is the default, not the fallback"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
