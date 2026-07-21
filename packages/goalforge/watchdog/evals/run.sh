#!/usr/bin/env bash
# evals/run.sh — sdd-watchdog static-contract checks
# The skill is model-driven (semantic gap audit); behavioral output cannot be
# asserted without a model call, so these are static-contract checks over
# SKILL.md plus a wiring check against sdd-verify.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
SDD_VERIFY_MD="$(cd "$SKILL_DIR/../verify" && pwd)/SKILL.md"
PASS=0
FAIL=0

check() {
  local desc="$1"
  local pattern="$2"
  local file="${3:-$SKILL_MD}"
  if grep -qF "$pattern" "$file"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "        expected to find: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== sdd-watchdog: static-contract checks ==="

# Identity + version
check "skill name declared" "name: goalforge-watchdog"
check "version declared" "version: 1.1.0"

# Core concept
check "gap audit concept present" "gap audit"
check "semantic-only boundary stated" "semantic"
check "invoked by sdd-verify after acceptance" "after"

# Granularity redesign: WP diff range (not per-task commit hashes)
check "file collection via WP diff range" "WP diff range"
check "robust to one-commit-per-WP cleanup" "one-commit-per-WP"
check "folded into sdd-verify single pass" "folded into"

# Three gap classes
check "claimed-vs-implemented class" "claimed-vs-implemented"
check "missing tests/docs class" "missing tests/docs"
check "deviations class" "deviations"

# Output modes (OQ-2)
check "light summary is the default" "Light summary (DEFAULT)"
check "deep verify-gap.md opt-in" "verify-gap.md"

# Non-duplication boundary (OQ-5)
check "cross-links sdd-verification-integrity-gaps" "sdd-verification-integrity-gaps"
check "no duplication of mechanical checks" "does **not**"

# Advisory, not a gate
check "advisory / non-blocking" "advisory"
check "does not block status-advance authority" "status authority"

# Hygiene
check "Gotchas section present" "## Gotchas"

# Wiring: sdd-verify references sdd-watchdog
check "verify wires goalforge-watchdog" "goalforge-watchdog" "$SDD_VERIFY_MD"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
