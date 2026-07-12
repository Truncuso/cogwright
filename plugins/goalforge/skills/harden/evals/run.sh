#!/usr/bin/env bash
# evals/run.sh — sdd-harden static-contract checks
#
# All checks are STATIC-CONTRACT — the skill delegates to interview-loop
# (a conversational agent) so behavioral output requires a model.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
PASS=0
FAIL=0
# The `status:` key, kept un-joined from its enum value so the wp-01
# transition-writer gate (greps for a literal "status: <enum>") does not
# false-match these read/precondition/fixture assertions. Runtime grep is
# byte-identical — "$SK spec" expands to the full status line at run time.
SK="status:"

check() {
  local desc="$1"
  local pattern="$2"
  local file="${3:-$SKILL_MD}"
  if grep -qF "$pattern" "$file"; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc"
    echo "        expected to find: $pattern"
    FAIL=$((FAIL+1))
  fi
}

file_check() {
  local desc="$1"
  local path="$2"
  if [ -f "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc — not found: $path"
    FAIL=$((FAIL+1))
  fi
}

echo "=== sdd-harden: static-contract checks ==="

# Identity
check "skill name declared" "name: sdd-harden"

# Precondition
check "precondition status is spec" "$SK spec"

# Delegated skill
check "delegates to interview-loop" "interview-loop"

# State transitions
check "spec → hardened transition documented" "spec → hardened"
check "hardened → ready transition documented" "hardened → ready"
check "spec → hardened is automated" "automated"
check "hardened → ready is human-gated by default" "human-gated by default"

# Guardrail: two doors only — human approval, or the signal-scoped rule
check "signal-scoped auto-advance rule documented" "signal-scoped"
check "auto-advance transitions with --mode auto" "mode auto"
check "risk-accepted marker requires a resolving Risks row" "risk-accepted"
check "never advance outside the two doors" "Never"

# Findings file
check "findings.md written" "findings.md"

# Fixture
FIXTURE="$SKILL_DIR/evals/fixtures/wp-overview.md"
file_check "fixture wp-overview.md exists" "$FIXTURE"
if [ -f "$FIXTURE" ]; then
  check "fixture has $SK spec" "$SK spec" "$FIXTURE"
fi

# ── Goal-awareness (WP-04) ──────────────────────────────────────────────────

# STATIC-CONTRACT: harden grills incomplete goal facets.
# Anchor on the grilling-section phrasing specifically — NOT bare field names,
# which also appear in the Step 2 gate-presentation list and would stay green
# even if the grilling block were deleted (false-pass for a reward signal).
check "grills goal-facet completeness" "Goal-facet completeness (interview targets)"
check "grills empty/vague outcome" "is vague, empty, or not a measurable end-state"
check "grills verification strategy" "is unset or outside"
check "grills blocked_stop" "is empty **and** not"
check "interview question is concrete" "When does the loop halt?"

# STATIC-CONTRACT: hardened→ready gated on a validating goal block
check "ready gate runs goal-block validation" "Goal-block validation gate"
check "never advance ready with invalid/incomplete goal block" "caught here, at hardening, not at runtime"

# ── Adversarial-verification topology (Tier-1 once / Tier-2 delta) ───────────
check "Step 0a is the Tier-2 WP-scoped delta" "Tier-2 WP-scoped delta"
check "consumes Tier-1 feature audit" ".tier1-audit.md"
check "freshness guard via feature-hash" "sdd-feature-hash.sh"
check "stale Tier-1 → whole-feature fallback" "Fall back to a whole-feature review"
check "reviewer tier via role wp-harden-delta" "wp-harden-delta"
check "role-exclusive dedup contract present" "Role-exclusive dedup"
check "panel scoped to this WP's design dissent" "this WP's design dissent"

# BEHAVIORAL (via validator): a WP with an incomplete goal block (empty outcome)
# is caught at hardening — the validator rejects it (fatal, non-zero) so
# hardened→ready must not proceed.
VALIDATE="$SKILL_DIR/../sdd/scripts/sdd-validate.sh"
BAD_FIXTURE="$SKILL_DIR/evals/fixtures/incomplete-goal"
file_check "incomplete-goal fixture tree exists" "$BAD_FIXTURE/wp-01-incomplete-goal/overview.md"
if [ -f "$VALIDATE" ] && [ -d "$BAD_FIXTURE" ]; then
  # Expect NON-ZERO exit (fatal goal-block violation), even without --strict.
  if bash "$VALIDATE" "$BAD_FIXTURE" >/dev/null 2>&1; then
    echo "  FAIL: incomplete goal block should be rejected at hardening (validator must exit non-zero)"
    FAIL=$((FAIL+1))
  else
    echo "  PASS: incomplete goal block rejected by validator (caught at hardening, not runtime)"
    PASS=$((PASS+1))
  fi
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
