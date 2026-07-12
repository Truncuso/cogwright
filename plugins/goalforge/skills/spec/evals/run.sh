#!/usr/bin/env bash
# evals/run.sh — sdd-spec static-contract checks
# All checks are static-contract (design pass + spec writing requires model).
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
PASS=0
FAIL=0

check() {
  local desc="$1"
  local pattern="$2"
  if grep -qF "$pattern" "$SKILL_MD"; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc"
    echo "        expected to find: $pattern"
    FAIL=$((FAIL+1))
  fi
}

echo "=== sdd-spec: static-contract checks ==="

# Identity
check "skill name declared" "name: sdd-spec"

# Input contract
check "input is overview.md with status draft" "status: draft"

# Output contract
check "spec.md output declared" "plans/<feature>/spec.md"
check "spec.md template is feature-spec.md" "feature-spec.md"
check "overview.md status advances to ready" "status: ready"

# Human gate
check "human-gated transition documented" "human-gated"
check "draft → spec transition documented" "draft → spec"
check "skill must present draft before writing" "present the draft spec"

# Template marker
check "feature-spec template marker documented" "<!-- Template: feature-spec v4 (frontmatter-first, flat layout) -->"

# Guardrails (no WP files)
check "no WP creation guardrail" "Never"

# Fixture existence
FIXTURE="$SKILL_DIR/evals/fixtures/overview.md"
if [ -f "$FIXTURE" ]; then
  echo "  PASS: fixture overview.md exists"
  PASS=$((PASS+1))
  # Verify fixture has required frontmatter
  if grep -q "status: draft" "$FIXTURE"; then
    echo "  PASS: fixture has status: draft"
    PASS=$((PASS+1))
  else
    echo "  FAIL: fixture missing status: draft"
    FAIL=$((FAIL+1))
  fi
else
  echo "  FAIL: fixture overview.md missing"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
