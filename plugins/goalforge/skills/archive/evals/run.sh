#!/usr/bin/env bash
# evals/run.sh — goalforge-archive checks
#
# Check types:
#   STATIC-CONTRACT:   asserts SKILL.md declares the correct contract
#   FIXTURE:           asserts fixture files have the correct shape for the gate contract
#   BEHAVIORAL-STATIC: asserts the refusal template is present (static proxy for behavioral refusal)
set -euo pipefail
: "${COGWRIGHT_ROOT:=$HOME/10_projects/cogwright}"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
PASS=0
FAIL=0

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

echo "=== goalforge-archive: contract + fixture checks ==="

# STATIC-CONTRACT: identity
check STATIC-CONTRACT "skill name declared" "name: goalforge-archive"
check STATIC-CONTRACT "version metadata present" "version: 1.4.0"

# STATIC-CONTRACT: triggers (incl. negative — surface is constrained to archival)
check STATIC-CONTRACT "trigger: archive feature" "archive feature"
check STATIC-CONTRACT "trigger: migration archive" "migration archive"
check STATIC-CONTRACT "trigger: feature B supersedes A" "supersedes A"

# STATIC-CONTRACT: fail-closed status gate
check STATIC-CONTRACT "precondition: only when status: completed" "status: completed"
check STATIC-CONTRACT "cannot archive draft/ready/active" "Cannot archive a draft/ready/active feature"

# STATIC-CONTRACT: plain archive writes
check STATIC-CONTRACT "plain archive sets status: archived" "status: archived"

# STATIC-CONTRACT: supersession edges (both directions)
check STATIC-CONTRACT "writes supersedes: [[<old>]] on replacing feature" "supersedes: [[<old>]]"
check STATIC-CONTRACT "writes superseded_by: [[<feature>]] on replaced feature" "superseded_by: [[<feature>]]"
check STATIC-CONTRACT "verifies both slugs exist before writing" "verify **both** slugs resolve"

# STATIC-CONTRACT: validator + ensure-committed gates
check STATIC-CONTRACT "validator gate: goalforge-validate --strict" "goalforge-validate.sh --strict <PLANS_ROOT>"
check STATIC-CONTRACT "ensure-committed gate references the script" "goalforge-ensure-committed.sh"
check STATIC-CONTRACT "ensure-committed is path-scoped + branch-agnostic" "path-scoped"
check STATIC-CONTRACT "dotfiles exception (commit on master, no push)" "master"

# STATIC-CONTRACT: relocate mode (stranded archived → _archived/)
check STATIC-CONTRACT "relocate mode documented" "Relocate mode (stranded archived"
check STATIC-CONTRACT "relocate gate requires status: archived" "requires \`status: archived\`"
check STATIC-CONTRACT "relocate is move-only (no frontmatter edit)" "Move-only"
check STATIC-CONTRACT "relocate rejects --supersedes" "rejected here"

# STATIC-CONTRACT: not in chain
check STATIC-CONTRACT "NOT wired into chain.yaml" "NOT** wired into \`chain.yaml\`"

# STATIC-CONTRACT: state transition
check STATIC-CONTRACT "state transition: completed → archived" "completed → archived"
check STATIC-CONTRACT "archival is explicit user action only" "explicit user action only"

# STATIC-CONTRACT: reference-gate (Step 4b)
check STATIC-CONTRACT "reference-gate step documented" "Step 4b — Reference-gate"
check STATIC-CONTRACT "strict-refs flag documented" "strict-refs"
check STATIC-CONTRACT "ref-gate flags path refs not wikilinks" "PATH refs, not wikilinks"
check STATIC-CONTRACT "ref-gate refuses with exit 6 under strict" "REFUSES with exit 6"

# BEHAVIORAL-STATIC: refusal template present
check BEHAVIORAL-STATIC "refusal template: goalforge-archive REFUSED" "goalforge-archive REFUSED"
check BEHAVIORAL-STATIC "refusal prints required: completed" "(required: completed)"
check BEHAVIORAL-STATIC "refusal for missing supersedes slug" "supersedes target not found"

# FIXTURE: completed feature (happy path)
COMPLETED="$SKILL_DIR/evals/fixtures/feature-completed/overview.md"
file_check FIXTURE "fixture feature-completed/overview.md exists" "$COMPLETED"
if [ -f "$COMPLETED" ]; then
  check FIXTURE "completed fixture has status: completed" "status: completed" "$COMPLETED"
fi

# FIXTURE: active feature (fail-close case)
ACTIVE="$SKILL_DIR/evals/fixtures/feature-active/overview.md"
file_check FIXTURE "fixture feature-active/overview.md exists" "$ACTIVE"
if [ -f "$ACTIVE" ]; then
  check FIXTURE "active fixture has status: active (fail-close)" "status: active" "$ACTIVE"
fi

# FIXTURE: archived feature (relocate source; default mode fail-close)
ARCHIVED="$SKILL_DIR/evals/fixtures/feature-archived/overview.md"
file_check FIXTURE "fixture feature-archived/overview.md exists" "$ARCHIVED"
if [ -f "$ARCHIVED" ]; then
  check FIXTURE "archived fixture has status: archived (relocate source)" "status: archived" "$ARCHIVED"
fi

# BEHAVIORAL: --relocate gate logic on real fixtures (exit-code contract)
SCRIPT=""$COGWRIGHT_ROOT"/plugins/goalforge/scripts/goalforge-archive.sh"
if [ -x "$SCRIPT" ] || [ -f "$SCRIPT" ]; then
  TT="$(mktemp -d)"; mkdir -p "$TT/plans"
  cp -r "$SKILL_DIR/evals/fixtures/feature-archived"  "$TT/plans/feat-arch"
  cp -r "$SKILL_DIR/evals/fixtures/feature-completed" "$TT/plans/feat-comp"
  sed -i 's/^name: .*/name: feat-arch/' "$TT/plans/feat-arch/overview.md"
  sed -i 's/^name: .*/name: feat-comp/' "$TT/plans/feat-comp/overview.md"
  # relocate REFUSES a completed feature (exit 3) — capture rc (set -e safe)
  rc=0; bash "$SCRIPT" feat-comp --relocate --plans-root "$TT/plans" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 3 ]; then echo "  PASS [BEHAVIORAL]: --relocate refuses completed (exit 3)"; PASS=$((PASS+1))
  else echo "  FAIL [BEHAVIORAL]: --relocate should refuse completed with exit 3 (got $rc)"; FAIL=$((FAIL+1)); fi
  # relocate + --supersedes rejected (exit 2)
  rc=0; bash "$SCRIPT" feat-arch --relocate --supersedes x --plans-root "$TT/plans" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then echo "  PASS [BEHAVIORAL]: --relocate rejects --supersedes (exit 2)"; PASS=$((PASS+1))
  else echo "  FAIL [BEHAVIORAL]: --relocate+--supersedes should exit 2 (got $rc)"; FAIL=$((FAIL+1)); fi
  # relocate MOVES the stranded archived feature into _archived/ (exit 0)
  rc=0; bash "$SCRIPT" feat-arch --relocate --plans-root "$TT/plans" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] && [ -d "$TT/plans/_archived/feat-arch" ] && [ ! -d "$TT/plans/feat-arch" ]; then
    echo "  PASS [BEHAVIORAL]: --relocate moves archived feature to _archived/"; PASS=$((PASS+1))
  else echo "  FAIL [BEHAVIORAL]: --relocate move failed (rc=$rc)"; FAIL=$((FAIL+1)); fi
  rm -rf "$TT"
fi

# BEHAVIORAL: reference-gate (Step 4b) exit-code contract
if [ -f "$SCRIPT" ]; then
  RT="$(mktemp -d)"; mkdir -p "$RT/plans" "$RT/docs"
  cp -r "$SKILL_DIR/evals/fixtures/feature-completed" "$RT/plans/feat-comp"
  sed -i 's/^name: .*/name: feat-comp/' "$RT/plans/feat-comp/overview.md"
  # an external doc with an inbound PATH ref into the feature (would dangle on move)
  printf 'see plans/feat-comp/wp-01/findings.md for the playbook\n' > "$RT/docs/cross-cite.md"
  # danger + --strict-refs -> REFUSE exit 6
  rc=0; bash "$SCRIPT" feat-comp --strict-refs --plans-root "$RT/plans" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 6 ]; then echo "  PASS [BEHAVIORAL]: ref-gate refuses inbound path ref under --strict-refs (exit 6)"; PASS=$((PASS+1))
  else echo "  FAIL [BEHAVIORAL]: --strict-refs should exit 6 on inbound path ref (got $rc)"; FAIL=$((FAIL+1)); fi
  # danger + NO --strict-refs -> warn only, does NOT refuse (rc != 6); fresh copy (test 1 edited the other)
  RTW="$(mktemp -d)"; mkdir -p "$RTW/plans" "$RTW/docs"
  cp -r "$SKILL_DIR/evals/fixtures/feature-completed" "$RTW/plans/feat-comp"
  sed -i 's/^name: .*/name: feat-comp/' "$RTW/plans/feat-comp/overview.md"
  printf 'see plans/feat-comp/wp-01/findings.md for the playbook\n' > "$RTW/docs/cross-cite.md"
  rc=0; bash "$SCRIPT" feat-comp --plans-root "$RTW/plans" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 6 ]; then echo "  PASS [BEHAVIORAL]: ref-gate is warn-only without --strict-refs (rc=$rc != 6)"; PASS=$((PASS+1))
  else echo "  FAIL [BEHAVIORAL]: without --strict-refs ref-gate must not refuse (got 6)"; FAIL=$((FAIL+1)); fi
  rm -rf "$RTW"
  # clean (no inbound ref) + --strict-refs -> ref-gate passes (rc != 6)
  RC2="$(mktemp -d)"; mkdir -p "$RC2/plans"
  cp -r "$SKILL_DIR/evals/fixtures/feature-completed" "$RC2/plans/feat-clean"
  sed -i 's/^name: .*/name: feat-clean/' "$RC2/plans/feat-clean/overview.md"
  rc=0; bash "$SCRIPT" feat-clean --strict-refs --plans-root "$RC2/plans" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 6 ]; then echo "  PASS [BEHAVIORAL]: ref-gate passes clean feature under --strict-refs (rc=$rc != 6)"; PASS=$((PASS+1))
  else echo "  FAIL [BEHAVIORAL]: clean feature should not trip ref-gate (got 6)"; FAIL=$((FAIL+1)); fi
  rm -rf "$RT" "$RC2"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
