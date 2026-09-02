#!/usr/bin/env bash
# evals/run.sh — goalforge-watchdog static-contract checks
# The skill is model-driven (semantic gap audit); behavioral output cannot be
# asserted without a model call, so these are static-contract checks over
# SKILL.md plus a wiring check against goalforge-verify.
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

echo "=== goalforge-watchdog: static-contract checks ==="

# Identity + version
check "skill name declared" "name: goalforge-watchdog"
check "version declared" "version: 1.1.0"

# Core concept
check "gap audit concept present" "gap audit"
check "semantic-only boundary stated" "semantic"
check "invoked by goalforge-verify after acceptance" "after"

# Granularity redesign: WP diff range (not per-task commit hashes)
check "file collection via WP diff range" "WP diff range"
check "robust to one-commit-per-WP cleanup" "one-commit-per-WP"
check "folded into goalforge-verify single pass" "folded into"

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

# Wiring: goalforge-verify references goalforge-watchdog
check "verify wires goalforge-watchdog" "goalforge-watchdog" "$SDD_VERIFY_MD"


# ── BEHAVIORAL (via validator): the claimed-vs-implemented gap, mechanically ─
# The watchdog's semantic pass must not be the first thing that notices a WP
# claiming `verified` over a task that is only `implemented`. That form of the
# gap class is deterministic, so it is asserted here by executing
# goalforge-validate.sh against a fixture whose ONLY defect is that mismatch.
VALIDATE="$(cd "$SKILL_DIR/.." && pwd)/scripts/goalforge-validate.sh"
GAP_FIXTURE="$SKILL_DIR/evals/fixtures/wp-claimed-verified"
if [ -f "$GAP_FIXTURE/wp-01-gap-audit/overview.md" ]; then
  echo "  PASS: wp-claimed-verified fixture tree exists"
  PASS=$((PASS + 1))
else
  echo "  FAIL: wp-claimed-verified fixture tree missing: $GAP_FIXTURE"
  FAIL=$((FAIL + 1))
fi

if bash "$VALIDATE" --strict "$GAP_FIXTURE" >/dev/null 2>&1; then
  echo "  FAIL: WP verified over an implemented task must be rejected (validator must exit non-zero)"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: WP verified over an implemented task rejected by validator"
  PASS=$((PASS + 1))
fi

# Green counterpart: the same tree with the task promoted (and its status
# mirror updated) validates clean, so the non-zero above is the gap and
# nothing else.
GAP_TMP="$(mktemp -d)"
cp -R "$GAP_FIXTURE" "$GAP_TMP/f"
sed -i 's/^status: implemented$/status: verified/' "$GAP_TMP/f/wp-01-gap-audit/task-01-gap-probe.md"
sed -i 's/| Gap probe | implemented |/| Gap probe | verified |/' "$GAP_TMP/f/wp-01-gap-audit/overview.md"
if bash "$VALIDATE" --strict "$GAP_TMP/f" >/dev/null 2>&1; then
  echo "  PASS: the same tree with the task promoted validates clean"
  PASS=$((PASS + 1))
else
  echo "  FAIL: the same tree with the task promoted should validate clean"
  bash "$VALIDATE" --strict "$GAP_TMP/f" 2>&1 | sed 's/^/        /' || true
  FAIL=$((FAIL + 1))
fi
rm -rf "$GAP_TMP"
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
