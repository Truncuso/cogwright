#!/usr/bin/env bash
# evals/run.sh — sdd-verify checks
#
# Check types:
#   STATIC-CONTRACT: asserts SKILL.md declares the correct contract
#   FIXTURE:         asserts fixture files have the correct shape for the precondition contract
#   BEHAVIORAL-STATIC: asserts the refusal template is present (static proxy for behavioral refusal test)
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
IMPLEMENT_MD="$SKILL_DIR/../implement/SKILL.md"   # sibling skill (wp-02 boundary note)
PASS=0
FAIL=0
# The `status:` key, kept un-joined from its enum value so the wp-01
# transition-writer gate (greps for a literal "status: <enum>") does not
# false-match these fixture assertions. Runtime grep is byte-identical.
SK="status:"

check() {
  local type="$1"
  local desc="$2"
  local pattern="$3"
  local file="${4:-$SKILL_MD}"
  if grep -qF "$pattern" "$file"; then
    echo "  PASS [$type]: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL [$type]: $desc"
    echo "        expected to find: $pattern"
    FAIL=$((FAIL+1))
  fi
}

file_check() {
  local type="$1"
  local desc="$2"
  local path="$3"
  if [ -f "$path" ]; then
    echo "  PASS [$type]: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL [$type]: $desc — not found: $path"
    FAIL=$((FAIL+1))
  fi
}

echo "=== sdd-verify: contract + fixture checks ==="

# STATIC-CONTRACT: identity
check STATIC-CONTRACT "skill name declared" "name: sdd-verify"

# STATIC-CONTRACT: preconditions
check STATIC-CONTRACT "precondition: all tasks implemented" "All child tasks are \`implemented\`"
check STATIC-CONTRACT "precondition: findings.md must exist" "findings.md exists"

# STATIC-CONTRACT: delegation
check STATIC-CONTRACT "delegates to superpowers:verification-before-completion" "superpowers:verification-before-completion"

# STATIC-CONTRACT: state transition
check STATIC-CONTRACT "executing → verified transition" "executing → verified"

# ── Single semantic gate (cumulative WP diff) ───────────────────────────────
check STATIC-CONTRACT "single semantic gate on cumulative diff" "the single semantic gate"
check STATIC-CONTRACT "verify pass tier via role wp-verify" "wp-verify"
check STATIC-CONTRACT "one verify-and-simplify pass" "verify-and-simplify"
check STATIC-CONTRACT "post-simplify deterministic re-run" "re-run the deterministic eval suite"
check STATIC-CONTRACT "WP goal.verification is authoritative verdict" "authoritative completion verdict"
check STATIC-CONTRACT "verification-before-completion fed the diff" "fed the DIFF"

# ── Promotion + deferred commit backfill ────────────────────────────────────
check STATIC-CONTRACT "promote implemented → verified at gate" "implemented → verified"
check STATIC-CONTRACT "backfill commit from checkpoint.commit_sha" "checkpoint.commit_sha"
check STATIC-CONTRACT "backfill BEFORE --require-commit gate" "before the \`--require-commit\` gate"
check STATIC-CONTRACT "recap one-row-per-WP via record-wp" "record-wp"
check STATIC-CONTRACT "last-WP cross-WP integration review" "integration review"

# ── wp-02: executor-divergence naming + implement boundary (Gap 2) ──────────
check STATIC-CONTRACT "wp-02: executor-divergence cause named in refusal" "executor-divergence"
check STATIC-CONTRACT "wp-02: implement declares it never advances task status" "never advances task" "$IMPLEMENT_MD"

# BEHAVIORAL-STATIC: refusal template present
check BEHAVIORAL-STATIC "refusal template: sdd-verify REFUSED" "sdd-verify REFUSED"
check BEHAVIORAL-STATIC "refusal lists unverified tasks by name" "task-01-foo"
check BEHAVIORAL-STATIC "refusal reports findings.md presence" "findings.md: [present | MISSING]"

# STATIC-CONTRACT: do not advance on failure (text is "Do **not** advance")
check STATIC-CONTRACT "do not advance status on failure" "Do **not** advance"

# STATIC-CONTRACT: completion step 5 — commit-gate + ensure-committed
check STATIC-CONTRACT "step 5 commits only feature artifacts" "git add <PLANS_ROOT>/<feature>"
check STATIC-CONTRACT "step 5 ensure-committed gate references the script" "sdd-ensure-committed.sh"
check STATIC-CONTRACT "commit gate is path-scoped" "path-scoped (unrelated dirt"
check STATIC-CONTRACT "commit gate passes on master (dotfiles exception)" "passes on \`master\` under the dotfiles exception"

# STATIC-CONTRACT: completion step 6 — archive is gated, not automatic
check STATIC-CONTRACT "step 6 archive offer via sdd-archive" "sdd-archive <feature> [--supersedes <old>]"
check STATIC-CONTRACT "sdd-verify never writes feature status: archived" "sdd-verify never writes a feature to"
check STATIC-CONTRACT "transition: completed → archived via sdd-archive" "feature: completed → archived (explicit user action only — via sdd-archive)"

# FIXTURE: wp-executing directory
WP_DIR="$SKILL_DIR/evals/fixtures/wp-executing"
file_check FIXTURE "fixture overview.md exists" "$WP_DIR/overview.md"
file_check FIXTURE "fixture task-01-router-setup.md exists" "$WP_DIR/task-01-router-setup.md"
file_check FIXTURE "fixture findings.md exists" "$WP_DIR/findings.md"

if [ -f "$WP_DIR/overview.md" ]; then
  check FIXTURE "fixture overview has $SK executing" "$SK executing" "$WP_DIR/overview.md"
fi
if [ -f "$WP_DIR/task-01-router-setup.md" ]; then
  check FIXTURE "fixture task has $SK verified" "$SK verified" "$WP_DIR/task-01-router-setup.md"
  check FIXTURE "fixture task has non-empty verify field" "verify:" "$WP_DIR/task-01-router-setup.md"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
