#!/usr/bin/env bash
# goalforge-router.sh — deterministic chain.yaml step-resolver (the WP-07 gate).
#
# Parses the sibling chain.yaml and resolves each step's `skill:` relative to
# this script's own location: a `goalforge/<child>` step resolves to
# <child>/SKILL.md two levels above this script, which is the package tree
# (packages/goalforge/<child>/) and the generated plugin tree
# (plugins/goalforge/skills/<child>/) alike. A step without the `goalforge/`
# prefix is UNRESOLVED, and $HOME is not read for step resolution. Setting
# CLAUDE_SKILLS_ROOT overrides this: every step then resolves against
# $CLAUDE_SKILLS_ROOT/<skill>/SKILL.md. Prints one line per step
# (RESOLVED / UNRESOLVED).
#
# Before resolving steps it checks that the feature directory exists under a
# candidate plans root (goalforge_plans_roots, hooks/goalforge-plans-root.sh).
# Directory existence only: neither status nor spec presence is checked.
#
# Exit codes:
#   0  every step resolved
#   1  an unresolved step; chain.yaml missing, unparseable or empty; or the
#      plans-root helper not found
#   2  usage
#   3  feature directory not found under any candidate plans root
#
# This is the *deterministic* counterpart to the agent-driven
# `skill-router goalforge-run --dry-run` documented in SKILL.md (## --dry-run
# semantics). The agent-driven router stays the runtime mechanism; this script
# is the binary gate a deterministic goal.verification can call. The two are
# complementary, not a replacement.
#
# Usage:
#   goalforge-router.sh --dry-run <feature>
#
# --dry-run has NO side effects: no files written, no subagents dispatched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAIN_YAML="$SCRIPT_DIR/../chain.yaml"
OWN_SKILLS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  echo "usage: goalforge-router.sh --dry-run <feature>" >&2
  exit 2
}

[ "${1:-}" = "--dry-run" ] || usage
FEATURE="${2:-}"
[ -n "$FEATURE" ] || usage

[ -f "$CHAIN_YAML" ] || { echo "goalforge-router: chain.yaml not found: $CHAIN_YAML" >&2; exit 1; }

# Feature check. The plans-root helper sits two levels up in the package layout
# (run/scripts) and three levels up in the plugin layout (skills/run/scripts).
PLANS_ROOT_HELPER=""
for candidate in "$SCRIPT_DIR/../../hooks/goalforge-plans-root.sh" \
                 "$SCRIPT_DIR/../../../hooks/goalforge-plans-root.sh"; do
  if [ -f "$candidate" ]; then PLANS_ROOT_HELPER="$candidate"; break; fi
done
[ -n "$PLANS_ROOT_HELPER" ] || { echo "goalforge-router: plans-root helper not found" >&2; exit 1; }
# shellcheck source=/dev/null
. "$PLANS_ROOT_HELPER"
# "$PWD/." anchors the helper's git-root leg at the current directory.
PLANS_ROOTS="$(goalforge_plans_roots "$PWD/.")"
feature_found=0
while IFS= read -r root; do
  [ -n "$root" ] || continue
  if [ -d "$root/$FEATURE" ]; then feature_found=1; break; fi
done <<< "$PLANS_ROOTS"
if [ "$feature_found" -eq 0 ]; then
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    echo "goalforge-router: feature directory not found: $root/$FEATURE" >&2
  done <<< "$PLANS_ROOTS"
  exit 3
fi

# Extract the ordered list of step skills from chain.yaml (deterministic parse).
# `mapfile` needs bash 4+ (fine on Linux; macOS system bash is 3.x — use Homebrew bash).
# The python guards empty/null/malformed YAML so the parse emits a single clean error
# line instead of a traceback, then the empty-array guard below reports it and exits 1.
mapfile -t SKILLS < <(python3 - "$CHAIN_YAML" <<'PY'
import sys, yaml
try:
    chain = yaml.safe_load(open(sys.argv[1])) or {}
    for step in (chain.get("steps") or []):
        skill = (step or {}).get("skill")
        if skill:
            print(skill)
except Exception as e:
    sys.stderr.write(f"goalforge-router: failed to parse chain.yaml: {e}\n")
    sys.exit(1)
PY
)

[ "${#SKILLS[@]}" -gt 0 ] || { echo "goalforge-router: no steps found in chain.yaml" >&2; exit 1; }

# NOTE: "UNRESOLVED" contains the substring "RESOLVED"; a downstream `grep -c RESOLVED`
# counts both. Consumers MUST guard with `! grep -q UNRESOLVED` before counting, or match
# `': RESOLVED '`. The exit code below is the authoritative signal regardless.
echo "goalforge-router --dry-run: feature=$FEATURE chain=$CHAIN_YAML"
unresolved=0
for skill in "${SKILLS[@]}"; do
  if [ -n "${CLAUDE_SKILLS_ROOT:-}" ]; then
    skill_md="$CLAUDE_SKILLS_ROOT/$skill/SKILL.md"
  else
    case "$skill" in
      goalforge/*) skill_md="$OWN_SKILLS_DIR/${skill#goalforge/}/SKILL.md" ;;
      *) skill_md="" ;;
    esac
  fi
  if [ -n "$skill_md" ] && [ -f "$skill_md" ]; then
    echo "$skill: RESOLVED ($skill_md)"
  else
    echo "$skill: UNRESOLVED"
    unresolved=$((unresolved + 1))
  fi
done

[ "$unresolved" -eq 0 ] || { echo "goalforge-router: $unresolved unresolved step(s)" >&2; exit 1; }
exit 0
