#!/usr/bin/env bash
# evals/run.sh — goalforge-decompose checks
#
# Check types:
#   STATIC-CONTRACT: asserts SKILL.md declares the C1-C7 contract this slim
#                     skill now states (wp-01-slim-core)
#   FIXTURE:         asserts fixture files have the right shape
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
PASS=0
FAIL=0

check() {
  local type="$1"
  local desc="$2"
  local pattern="$3"
  local file="${4:-$SKILL_MD}"
  if grep -qF -- "$pattern" "$file"; then
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

echo "=== goalforge-decompose: contract + fixture checks ==="

# STATIC-CONTRACT: identity
check STATIC-CONTRACT "skill name declared" "name: decompose"

# STATIC-CONTRACT: input spec.md, feature must be status: ready
check STATIC-CONTRACT "input spec.md declared" "plans/<feature>/spec.md"
check STATIC-CONTRACT "feature must be status: ready to decompose" "the feature \`overview.md\` is \`status: ready\`"

# STATIC-CONTRACT: C1 — one overview.md per WP, no per-item files, no todo.md
check STATIC-CONTRACT "writes only overview.md (no per-item files, no todo.md)" "No per-item files, no todo.md"
check STATIC-CONTRACT "birth status is spec, never another status" "born \`status: spec\`, never another status"
check STATIC-CONTRACT "checklist item carries no status/complexity/verify/depends_on/commit field" "An item carries no status, complexity, verify, depends_on, or commit"

# STATIC-CONTRACT: C2 frontmatter fields
check STATIC-CONTRACT "WP frontmatter includes owned_files" "\`owned_files\` (the file boundary)"
check STATIC-CONTRACT "WP frontmatter includes contract_slice" "\`contract_slice\`"
check STATIC-CONTRACT "WP frontmatter includes goal_approved_version: null at birth" "goal_approved_version: null"
check STATIC-CONTRACT "schema_version: 6 stamped" "schema_version: 6"

# STATIC-CONTRACT: goal block always WP-authored
check STATIC-CONTRACT "goal.outcome/verification always WP-authored, never inherited" "always WP-authored, never inherited"

# STATIC-CONTRACT: checklist line shape
check STATIC-CONTRACT "checklist item shape names files and behavior ids" "- [ ] T1 <imperative outcome> {files: a, b} [b1,b2]"

# STATIC-CONTRACT: C1 eight-section body order
check STATIC-CONTRACT "C1 eight-section body order stamped" "in the C1 order \`## Goal\`, \`## Verification\`, \`## Owned Files\`, \`## Depends On\`,"
check STATIC-CONTRACT "C1 body order names Goal Changelog as final section" "\`## Goal Changelog\`, and no"

# STATIC-CONTRACT: self-check rules (facet coverage, one owner backward deps)
check STATIC-CONTRACT "self-check: facet coverage rule" "Facet coverage"
check STATIC-CONTRACT "self-check: one owner, backward deps rule" "One owner, backward deps"

# STATIC-CONTRACT: Step 6 lint + validate gates
check STATIC-CONTRACT "Step 6 runs section-lint" "goalforge-section-lint.sh"
check STATIC-CONTRACT "Step 6 runs validate --show" "goalforge-validate.sh --feature"

# STATIC-CONTRACT: Add-WP mode
check STATIC-CONTRACT "Add-WP mode documented" "Add-WP mode"
check STATIC-CONTRACT "Add-WP appends ONE WP, touching no existing WP" "touching no existing WP"
check STATIC-CONTRACT "Add-WP carries --derived-from / --source re-entry flags" "\`--derived-from <ref>\`"
check STATIC-CONTRACT "a restructure routes to goalforge-redecompose" "goalforge-redecompose"

# FIXTURE: spec.md exists and has correct shape
SPEC="$SKILL_DIR/evals/fixtures/spec.md"
file_check FIXTURE "spec.md fixture exists" "$SPEC"
if [ -f "$SPEC" ]; then
  check FIXTURE "spec fixture has an Interface Contract section" "## Interface Contract" "$SPEC"
  check FIXTURE "spec fixture has a Work Packages table" "| WP |" "$SPEC"
fi

# FIXTURE: overview.md exists with the ready status
OVERVIEW="$SKILL_DIR/evals/fixtures/overview.md"
file_check FIXTURE "overview.md fixture exists" "$OVERVIEW"
if [ -f "$OVERVIEW" ]; then
  check FIXTURE "overview fixture has status: ready" "status: ready" "$OVERVIEW"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
