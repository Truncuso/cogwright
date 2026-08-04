#!/usr/bin/env bash
# evals/run.sh — goalforge-capture static-contract checks
# All checks are static-contract (skill transforms markdown via model;
# behavioral output cannot be asserted without a model call).
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

# Ordering-aware check: assert $2 (first) appears on an earlier line than $3
# (second) in SKILL.md — a bare substring match cannot catch a step landing in
# the wrong order. Fails if either pattern is missing.
check_order() {
  local desc="$1"
  local first="$2"
  local second="$3"
  local ln_first ln_second
  ln_first=$(grep -nF "$first" "$SKILL_MD" | head -n 1 | cut -d: -f1)
  ln_second=$(grep -nF "$second" "$SKILL_MD" | head -n 1 | cut -d: -f1)
  if [ -n "$ln_first" ] && [ -n "$ln_second" ] && [ "$ln_first" -lt "$ln_second" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (first@${ln_first:-none} must precede second@${ln_second:-none})"
    FAIL=$((FAIL+1))
  fi
}

# Regex-aware check: the archived-collision guard is prose whose exact wording is
# not pinned by the contract — assert its load-bearing tokens, not a sentence.
check_re() {
  local desc="$1"
  local pattern="$2"
  if grep -qE "$pattern" "$SKILL_MD"; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc"
    echo "        expected to match: $pattern"
    FAIL=$((FAIL+1))
  fi
}

echo "=== goalforge-capture: static-contract checks ==="

# Identity
check "skill name declared" "name: goalforge-capture"

# Output contract
check "overview.md output declared" "plans/<feature>/overview.md"
check "overview.md initial status is draft" "status: draft"
check "todo.md output declared" "plans/<feature>/todo.md"
check "feature-overview template referenced" "feature-overview.md"
check "feature-todo template referenced" "feature-todo.md"

# Template marker
check "template marker present" "<!-- Template: feature-overview v4 (frontmatter-first, flat layout) -->"

# Idempotency
check "idempotency: folder present + overview present = update in place" "Folder present, \`overview.md\` present"

# Idempotency — archived-collision branch. A slug absent from the ACTIVE root may
# still exist ARCHIVED; stamping a fresh `status: draft` then yields two nodes for
# one slug (okf-substrate duplicate stub, 2026-08-03).
check_re "idempotency probes plans/_archived/ for the slug" "_archived/(<feature>|<slug>)/"
check_re "idempotency probes ideas/_archived/<slug>.md" "ideas/_archived/(<feature>|<slug>)\\.md"
check_re "archived collision HALTs instead of stamping a fresh draft" "HALT"
check_re "archived collision presents restore vs new slug" "[Rr]estore"

# FIXTURE: the tree shape Step 2 must probe (slug absent live, present archived)
FIX="$SKILL_DIR/evals/fixtures/plans-archived-collision"
for f in "$FIX/_archived/okf-substrate/overview.md" \
         "$FIX/ideas/_archived/okf-substrate.md" \
         "$FIX/live-feature/overview.md"; do
  if [ -f "$f" ]; then
    echo "  PASS: fixture present: ${f#"$FIX/"}"
    PASS=$((PASS+1))
  else
    echo "  FAIL: fixture missing: $f"
    FAIL=$((FAIL+1))
  fi
done
if [ ! -e "$FIX/okf-substrate" ] && [ -d "$FIX/_archived/okf-substrate" ]; then
  echo "  PASS: fixture pins the defect shape (slug absent live, present archived)"
  PASS=$((PASS+1))
else
  echo "  FAIL: fixture must carry okf-substrate ONLY under _archived/"
  FAIL=$((FAIL+1))
fi

# Guardrails
check "never create WP folders guardrail" "Never"
check "spec.md creation forbidden" "spec.md"
check "stage_updated not applicable to feature overview" "stage_updated"

# Slugification
check "slugification example documented" "user-auth-revamp"

# Route classification (Step 4c) + fast path
check "route classifier invoked (goalforge-route.sh)" "goalforge-route.sh"
check "route stamped as frontmatter data" "route:"
check "borderline verdict confirms with the human" "borderline"
check "fast-path runbook present" "Fast path"
check "fast path delegates WP authoring to add-wp" "Add-WP mode"
check "fast path never skips verification" "never skips verification"
check "fast path records goal hash (reconciles wp-01 ready-gate)" "goalforge-goal-hash.sh --record"
check_order "fast path records goal hash BEFORE spec->ready --mode auto" \
  "goalforge-goal-hash.sh --record" "goalforge-transition.sh <wp> ready"

# Route classifier self-test (deterministic regression)
if bash "$SKILL_DIR/../scripts/goalforge-route.sh" --self-test >/dev/null 2>&1; then
  echo "  PASS: goalforge-route.sh --self-test green"
  PASS=$((PASS+1))
else
  echo "  FAIL: goalforge-route.sh --self-test failed"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
