#!/usr/bin/env bash
# evals/run.sh — goalforge-run dry-run structural checks
#
# Check types:
#   YAML-STRUCTURE:  parses chain.yaml and asserts step order and skill presence
#   STATIC-CONTRACT: asserts SKILL.md documents --dry-run semantics and status machine
#
# These are entirely deterministic: no network, no model calls.
# chain.yaml is parsed with grep/awk — no yaml parser required.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
CHAIN_YAML="$SKILL_DIR/chain.yaml"
SKILLS_ROOT="$(cd "$(dirname "$SKILL_DIR")/.." && pwd)"
PASS=0
FAIL=0

check_contract() {
  local desc="$1"
  local pattern="$2"
  local file="${3:-$SKILL_MD}"
  if grep -qF "$pattern" "$file"; then
    echo "  PASS [STATIC-CONTRACT]: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL [STATIC-CONTRACT]: $desc"
    echo "        expected to find: $pattern"
    FAIL=$((FAIL+1))
  fi
}

check_yaml() {
  local desc="$1"
  local pattern="$2"
  if grep -qF "$pattern" "$CHAIN_YAML"; then
    echo "  PASS [YAML-STRUCTURE]: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL [YAML-STRUCTURE]: $desc"
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

echo "=== goalforge-run: chain.yaml dry-run structural checks ==="

# chain.yaml exists
file_check YAML-STRUCTURE "chain.yaml exists" "$CHAIN_YAML"

# chain.yaml: name
check_yaml "chain name is goalforge-run" "name: goalforge-run"

# chain.yaml: all 6 required skills present
REQUIRED_SKILLS="goalforge-capture goalforge-spec goalforge-decompose goalforge-harden goalforge-execute goalforge-verify"
for skill in $REQUIRED_SKILLS; do
  check_yaml "chain references skill: $skill" "skill: $skill"
done

# chain.yaml: step count — 6 linear + 1 loop-back (goalforge-redecompose)
STEP_COUNT=$(grep -c "^\s*- skill:" "$CHAIN_YAML" || true)
if [ "$STEP_COUNT" -eq 7 ]; then
  echo "  PASS [YAML-STRUCTURE]: chain has exactly 7 steps (found $STEP_COUNT)"
  PASS=$((PASS+1))
else
  echo "  FAIL [YAML-STRUCTURE]: expected 7 steps, found $STEP_COUNT"
  FAIL=$((FAIL+1))
fi

# chain.yaml: route awareness — fast/full routing keys present
check_yaml "spec step is full-route only (when_route: full)" "when_route: full"
check_yaml "decompose declares the fast_route add-wp override" "mode: add-wp"

# chain.yaml: goalforge-harden is human_gated
check_yaml "goalforge-harden step is human_gated: true" "human_gated: true"

# chain.yaml: precondition status values are valid schema stages
VALID_STAGES="draft spec hardened ready executing verified archived"
# Extract all status: values from chain preconditions
PRECOND_STATUSES=$(grep -A2 "precondition:" "$CHAIN_YAML" | grep "status:" | awk '{print $2}')
for status in $PRECOND_STATUSES; do
  VALID=false
  for stage in $VALID_STAGES; do
    if [ "$status" = "$stage" ]; then
      VALID=true
      break
    fi
  done
  if $VALID; then
    echo "  PASS [YAML-STRUCTURE]: precondition status '$status' is a valid schema stage"
    PASS=$((PASS+1))
  else
    echo "  FAIL [YAML-STRUCTURE]: precondition status '$status' is NOT a valid schema stage"
    FAIL=$((FAIL+1))
  fi
done

# Each skill resolves to an existing SKILL.md
for skill in $REQUIRED_SKILLS; do
  SKILL_PATH="$SKILLS_ROOT/$skill/SKILL.md"
  file_check YAML-STRUCTURE "skill $skill resolves to $SKILL_PATH" "$SKILL_PATH"
done

# STATIC-CONTRACT: --dry-run semantics documented in SKILL.md
# Use grep -e to avoid ugrep treating --dry-run as a flag
if grep -qe '\-\-dry-run' "$SKILL_MD"; then
  echo "  PASS [STATIC-CONTRACT]: SKILL.md documents --dry-run semantics"
  PASS=$((PASS+1))
else
  echo "  FAIL [STATIC-CONTRACT]: SKILL.md documents --dry-run semantics"
  FAIL=$((FAIL+1))
fi
check_contract "SKILL.md documents status machine" "draft → spec → hardened → ready → executing → verified"
check_contract "SKILL.md name declared" "name: goalforge-run"

# STATIC-CONTRACT: entry command routing documented
check_contract "entry command /spec documented" "/spec"
check_contract "entry command /plan documented" "/plan"
check_contract "entry command /implement documented" "/implement"
check_contract "entry command /verify documented" "/verify"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
