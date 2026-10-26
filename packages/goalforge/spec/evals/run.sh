#!/usr/bin/env bash
# evals/run.sh — goalforge-spec static-contract checks
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

echo "=== goalforge-spec: static-contract checks ==="

# Identity
check "skill name declared" "name: spec"

# Input contract
check "input is overview.md with status draft" "status: draft"

# Output contract
check "spec.md output declared" "plans/<feature>/spec.md"
check "spec.md template is feature-spec.md" "feature-spec.md"
check "overview.md status advances to ready" "status: ready"

# Human gate
check "human-gated transition documented" "human-gated"
check "spec → ready single spec-approval gate documented" "spec → ready is the single human-gated spec-approval transition"
# Negative: the retired gate claims must not reappear (ground truth:
# state-machine.md human-gates spec→ready only; draft→spec is the ungated
# proposal edge and no draft→ready row exists)
RETIRED=0
for claim in '(the feature gate) is one of two human-gated' 'draft → ready' 'draft -> ready' 'draft → spec` is one of two human-gated'; do
  if grep -qF -- "$claim" "$SKILL_MD"; then
    echo "  FAIL: retired human-gate claim present: $claim"
    RETIRED=1
  fi
done
if [ "$RETIRED" -eq 0 ]; then
  echo "  PASS: retired human-gate claims absent"
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1))
fi
check "skill must present the proposal before ratifying" "present the proposal to the user"

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


# ── BEHAVIORAL (via validator): the frontmatter goalforge-spec writes is legal
# The fixture checks above only assert that the fixture CONTAINS `status:
# draft`. They cannot tell a schema-valid feature overview from a malformed
# one. These runs execute goalforge-validate.sh — the schema oracle — over the
# green fixture and over a deliberately broken copy carrying a non-enum status.
VALIDATE="$(cd "$SKILL_DIR/.." && pwd)/scripts/goalforge-validate.sh"
BAD_FIXTURE="$SKILL_DIR/evals/fixtures/invalid-status"

SPEC_TMP="$(mktemp -d)"
cp "$FIXTURE" "$SPEC_TMP/overview.md"
if bash "$VALIDATE" --strict "$SPEC_TMP" >/dev/null 2>&1; then
  echo "  PASS: draft fixture validates clean against the schema"
  PASS=$((PASS+1))
else
  echo "  FAIL: draft fixture should validate clean against the schema"
  bash "$VALIDATE" --strict "$SPEC_TMP" 2>&1 | sed 's/^/        /' || true
  FAIL=$((FAIL+1))
fi
rm -rf "$SPEC_TMP"

if [ -f "$BAD_FIXTURE/overview.md" ]; then
  echo "  PASS: invalid-status fixture exists"
  PASS=$((PASS+1))
else
  echo "  FAIL: invalid-status fixture missing: $BAD_FIXTURE/overview.md"
  FAIL=$((FAIL+1))
fi
if bash "$VALIDATE" --strict "$BAD_FIXTURE" >/dev/null 2>&1; then
  echo "  FAIL: a non-enum status must be rejected (validator must exit non-zero)"
  FAIL=$((FAIL+1))
else
  echo "  PASS: a non-enum status is rejected by the validator"
  PASS=$((PASS+1))
fi
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
