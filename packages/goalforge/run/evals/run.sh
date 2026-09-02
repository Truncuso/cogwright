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

# chain.yaml: route awareness — routing keys present
check_yaml "spec step is standard-route only (when_route: standard)" "when_route: standard"
check_yaml "decompose declares the fast_route add-wp override" "mode: add-wp"

# chain.yaml: goalforge/harden is human_gated
check_yaml "goalforge/harden step is human_gated: true" "human_gated: true"

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
check_contract "SKILL.md documents status machine" "draft → spec → hardened → ready → executing → verified"
check_contract "SKILL.md name declared" "name: goalforge-run"

# STATIC-CONTRACT: entry command routing documented
check_contract "entry command /spec documented" "/spec"
check_contract "entry command /plan documented" "/plan"
check_contract "entry command /implement documented" "/implement"
check_contract "entry command /verify documented" "/verify"

# ── ROUTE-ENUM: the documented enum is DERIVED from goalforge-route.sh ───────
# goalforge-route.sh is the only thing that emits a route value, so it — not a
# list typed into this harness — defines the enum. The probe set is lifted from
# the classifier's own accepted-value alternation (canonical plus whatever
# retired vocabulary it still normalizes on read); pinning each probe and
# collecting what it echoes back yields the emitted set, which is strictly the
# canonical enum.
PKG_ROOT="$(cd "$SKILL_DIR/.." && pwd)"
ROUTE_SH="$PKG_ROOT/scripts/goalforge-route.sh"
PROBE_VALUES="$(grep -E '\^route:' "$ROUTE_SH" | head -1 \
  | grep -oE '\(([a-z-]+\|)+[a-z-]+\)' | tr -d '()' | tr '|' ' ' || true)"
if [ -z "$PROBE_VALUES" ]; then
  echo "  FAIL [ROUTE-ENUM]: could not lift the accepted-route alternation from $ROUTE_SH"
  FAIL=$((FAIL+1))
fi
PROBE_DIR="$(mktemp -d)"
trap 'rm -rf "$PROBE_DIR"' EXIT

EMITTED=""
for v in $PROBE_VALUES; do
  printf -- '---\nroute: %s\n---\n## Goal\n\nenum probe\n' "$v" > "$PROBE_DIR/overview.md"
  emitted_v="$(bash "$ROUTE_SH" "$PROBE_DIR/overview.md" 2>/dev/null \
    | grep -o '"route": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  if [ -n "$emitted_v" ]; then
    EMITTED="$(printf '%s\n%s' "$EMITTED" "$emitted_v")"
  fi
done
EMITTED_SET="$(printf '%s\n' "$EMITTED" | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/ *$//')"

# ROUTE-ENUM 1: run/SKILL.md's canonical-enum line lists exactly the emitted set
DOC_SET="$(grep -o 'canonical enum `[^`]*`' "$SKILL_MD" | head -1 \
  | sed 's/.*`\(.*\)`.*/\1/' | tr '|' '\n' | tr -d ' ' | grep -v '^$' \
  | sort -u | tr '\n' ' ' | sed 's/ *$//')"
if [ -n "$EMITTED_SET" ] && [ "$DOC_SET" = "$EMITTED_SET" ]; then
  echo "  PASS [ROUTE-ENUM]: SKILL.md canonical enum == goalforge-route.sh emitted set ($EMITTED_SET)"
  PASS=$((PASS+1))
else
  echo "  FAIL [ROUTE-ENUM]: SKILL.md canonical enum != goalforge-route.sh emitted set"
  echo "        emitted:   '$EMITTED_SET'"
  echo "        documented:'$DOC_SET'"
  FAIL=$((FAIL+1))
fi

# ROUTE-ENUM 2: no retired route word (a probe value the classifier never emits)
# survives as a standalone word on a route-bearing line in run/ or commands/.
# The word boundary excludes '-' so an identifier like `captured-full-chain` is
# a name, not a route value.
STRAY_LINES=""
for v in $PROBE_VALUES; do
  case " $EMITTED_SET " in *" $v "*) continue ;; esac
  hits="$(grep -rniE "route" "$SKILL_DIR" "$PKG_ROOT/commands" \
    | grep -E "(^|[^A-Za-z0-9_-])${v}([^A-Za-z0-9_-]|$)" || true)"
  [ -n "$hits" ] && STRAY_LINES="$(printf '%s\n%s' "$STRAY_LINES" "$hits")"
done
STRAY_LINES="$(printf '%s\n' "$STRAY_LINES" | grep -v '^$' || true)"
if [ -z "$STRAY_LINES" ]; then
  echo "  PASS [ROUTE-ENUM]: no retired route vocabulary in run/ or commands/"
  PASS=$((PASS+1))
else
  echo "  FAIL [ROUTE-ENUM]: retired route vocabulary still present:"
  printf '%s\n' "$STRAY_LINES" | sed 's/^/        /'
  FAIL=$((FAIL+1))
fi

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

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
