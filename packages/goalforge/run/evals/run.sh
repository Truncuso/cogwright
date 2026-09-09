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
REQUIRED_SKILLS="capture spec decompose harden execute verify"
for skill in $REQUIRED_SKILLS; do
  check_yaml "chain references skill: goalforge/$skill" "skill: goalforge/$skill"
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

# chain.yaml: goalforge/harden and goalforge/spec are human_gated (2 steps)
HUMAN_GATED_COUNT=$(grep -c "human_gated: true" "$CHAIN_YAML" || true)
if [ "$HUMAN_GATED_COUNT" -eq 2 ]; then
  echo "  PASS [YAML-STRUCTURE]: exactly 2 human_gated: true steps (spec, harden)"
  PASS=$((PASS+1))
else
  echo "  FAIL [YAML-STRUCTURE]: expected 2 human_gated: true steps, found $HUMAN_GATED_COUNT"
  FAIL=$((FAIL+1))
fi

# chain.yaml: loop-back step to goalforge-redecompose is re-entrant, not linear
check_yaml "redecompose step documented as re-entrant loop-back" "Loop-back (re-entrant)"

# chain.yaml: precondition status values are valid schema stages
VALID_STAGES="draft spec hardened ready executing implemented verified archived"
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
  SKILL_PATH="$SKILLS_ROOT/goalforge/$skill/SKILL.md"
  file_check YAML-STRUCTURE "skill goalforge/$skill resolves to $SKILL_PATH" "$SKILL_PATH"
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
check_contract "SKILL.md description documents the chain order" "capture → spec → decompose → harden → execute → verify"
check_contract "SKILL.md name declared" "name: goalforge-run"

# STATIC-CONTRACT: status-driven routing table documented (per-status entry)
check_contract "routing table: draft feature enters spec" "| \`draft\` | feature | spec |"
check_contract "routing table: spec WP enters harden" "| \`spec\` | WP | harden |"
check_contract "routing table: implemented WP enters verify" "| \`implemented\` | WP | verify |"
check_contract "hardened → ready gate documented as human" "human at \`hardened → ready\`"

# ROUTE-ENUM (wp-01-slim-core): the slim run/SKILL.md dropped route-based
# branching — chain.yaml is now one linear list and the routing table keys
# entirely off on-disk `status:` (checked above). goalforge-route.sh may still
# exist for other callers, but run/SKILL.md no longer documents a canonical
# route enum, so there is nothing here for this harness to cross-check.
PKG_ROOT="$(cd "$SKILL_DIR/.." && pwd)"

# ── WRAPPER: goalforge-run is PUBLIC-PINNED and its dry-run gate resolves ────
# Doctrine item 7 (S28/S46): the orchestrator is named in every command and in
# the parent SKILL.md, so it MUST have a reachable entry. The pin is a
# commands/ wrapper that loads run/SKILL.md by path; these checks assert the
# wrapper exists, that the path it names resolves, and that the deterministic
# router gate resolves every chain step.
WRAPPER="$PKG_ROOT/commands/goalforge-run.md"
file_check WRAPPER "commands/goalforge-run.md wrapper exists" "$WRAPPER"

if [ -f "$WRAPPER" ] && grep -qF 'skills/run/SKILL.md' "$WRAPPER"; then
  echo "  PASS [WRAPPER]: wrapper loads run/SKILL.md by path"
  PASS=$((PASS+1))
else
  echo "  FAIL [WRAPPER]: wrapper does not load run/SKILL.md by path"
  FAIL=$((FAIL+1))
fi

ROUTER_RC=0
ROUTER_OUT="$(bash "$SKILL_DIR/scripts/goalforge-router.sh" --dry-run goalforge-run-wrapper-probe 2>&1)" || ROUTER_RC=$?
RESOLVED_STEPS="$(printf '%s\n' "$ROUTER_OUT" | grep -c ': RESOLVED ' || true)"
if [ "$ROUTER_RC" -eq 0 ] && [ "$RESOLVED_STEPS" -eq 7 ] \
   && ! printf '%s\n' "$ROUTER_OUT" | grep -q 'UNRESOLVED'; then
  echo "  PASS [WRAPPER]: router --dry-run resolves all 7 chain steps"
  PASS=$((PASS+1))
else
  echo "  FAIL [WRAPPER]: router --dry-run did not resolve all 7 chain steps (rc=$ROUTER_RC, resolved=$RESOLVED_STEPS)"
  printf '%s\n' "$ROUTER_OUT" | sed 's/^/        /'
  FAIL=$((FAIL+1))
fi


# ── HERMETIC: chain resolution proven against a fixture skills tree ──────────
# The WRAPPER router run above resolves against the INSTALLED tree
# ($HOME/.claude/skills), so it passes or fails with the author's machine and
# its UNRESOLVED path is never exercised. These two runs pin
# CLAUDE_SKILLS_ROOT — the override goalforge-router.sh already supports — at a
# tree this harness builds, so both the resolve and the fail path are real.
HERMETIC_ROOT="$(mktemp -d)"
CHAIN_STEPS="$(grep -E '^[[:space:]]*- skill:' "$CHAIN_YAML" | sed 's/.*skill:[[:space:]]*//')"
for s in $CHAIN_STEPS; do
  mkdir -p "$HERMETIC_ROOT/$s"
  printf -- '---\nname: %s\n---\n' "${s##*/}" > "$HERMETIC_ROOT/$s/SKILL.md"
done

H_RC=0
H_OUT="$(CLAUDE_SKILLS_ROOT="$HERMETIC_ROOT" bash "$SKILL_DIR/scripts/goalforge-router.sh" \
  --dry-run hermetic-probe 2>&1)" || H_RC=$?
H_RESOLVED="$(printf '%s\n' "$H_OUT" | grep -c ': RESOLVED ' || true)"
if [ "$H_RC" -eq 0 ] && [ "$H_RESOLVED" -eq 7 ] \
   && ! printf '%s\n' "$H_OUT" | grep -q 'UNRESOLVED'; then
  echo "  PASS [HERMETIC]: router resolves all 7 steps against the fixture skills tree"
  PASS=$((PASS+1))
else
  echo "  FAIL [HERMETIC]: router did not resolve 7 steps in the fixture tree (rc=$H_RC, resolved=$H_RESOLVED)"
  printf '%s\n' "$H_OUT" | sed 's/^/        /'
  FAIL=$((FAIL+1))
fi

# Deliberately broken fixture tree: one step's SKILL.md removed. The resolver
# must report it UNRESOLVED and exit non-zero — the failure path the installed
# tree can never exercise.
BROKEN_STEP="$(printf '%s\n' "$CHAIN_STEPS" | head -1)"
rm -f "$HERMETIC_ROOT/$BROKEN_STEP/SKILL.md"
B_RC=0
B_OUT="$(CLAUDE_SKILLS_ROOT="$HERMETIC_ROOT" bash "$SKILL_DIR/scripts/goalforge-router.sh" \
  --dry-run hermetic-probe 2>&1)" || B_RC=$?
if [ "$B_RC" -ne 0 ] && printf '%s\n' "$B_OUT" | grep -q "^$BROKEN_STEP: UNRESOLVED$"; then
  echo "  PASS [HERMETIC]: a missing step SKILL.md is UNRESOLVED and exits non-zero"
  PASS=$((PASS+1))
else
  echo "  FAIL [HERMETIC]: a missing step SKILL.md must be UNRESOLVED and exit non-zero (rc=$B_RC)"
  printf '%s\n' "$B_OUT" | sed 's/^/        /'
  FAIL=$((FAIL+1))
fi
rm -rf "$HERMETIC_ROOT"
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
