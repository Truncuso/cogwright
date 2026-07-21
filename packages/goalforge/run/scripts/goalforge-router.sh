#!/usr/bin/env bash
# goalforge-router.sh — deterministic chain.yaml step-resolver (the WP-07 gate).
#
# Parses the sibling chain.yaml and resolves each step's `skill:` against the
# installed skills under ~/.claude/skills/<skill>/SKILL.md. Prints one line per
# step (RESOLVED / UNRESOLVED) and exits non-zero if ANY step is UNRESOLVED.
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
SKILLS_ROOT="${CLAUDE_SKILLS_ROOT:-$HOME/.claude/skills}"

usage() {
  echo "usage: goalforge-router.sh --dry-run <feature>" >&2
  exit 2
}

[ "${1:-}" = "--dry-run" ] || usage
FEATURE="${2:-}"
[ -n "$FEATURE" ] || usage

[ -f "$CHAIN_YAML" ] || { echo "goalforge-router: chain.yaml not found: $CHAIN_YAML" >&2; exit 1; }

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
  if [ -f "$SKILLS_ROOT/$skill/SKILL.md" ]; then
    echo "$skill: RESOLVED ($SKILLS_ROOT/$skill/SKILL.md)"
  else
    echo "$skill: UNRESOLVED"
    unresolved=$((unresolved + 1))
  fi
done

[ "$unresolved" -eq 0 ] || { echo "goalforge-router: $unresolved unresolved step(s)" >&2; exit 1; }
exit 0
