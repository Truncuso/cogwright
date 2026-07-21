#!/usr/bin/env bash
# brief-stage eval case (wp-06 task-04): a FRESH brief — every References anchor's
# current git blob SHA matches the recorded SHA and the WP goal-hash is unchanged —
# passes staleness re-validation unchanged. The executor may consume it; the
# immutable brief is left untouched and NO re-brief request is recorded.
# Offline, deterministic — no network / model calls.
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
STALE_SH="$SKILL_DIR/execute/brief-staleness.sh"
GOAL_HASH_SH="$SKILL_DIR/scripts/goalforge-goal-hash.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

WP="$TMP/wp-01-fixture"
mkdir -p "$WP/src"
printf 'def handler():\n    return "ok"\n' > "$WP/src/handler.py"
SHA="$(git hash-object "$WP/src/handler.py")"

cat > "$WP/overview.md" <<'EOF'
---
name: wp-01-fixture
title: staleness-fresh fixture WP
status: ready
stage_updated: 2026-07-19
goal:
  outcome: "fixture goal for staleness-fresh"
  verification:
    strategy: deterministic
---
## Goal
fixture
EOF
GH="$(bash "$GOAL_HASH_SH" "$WP")"

cat > "$WP/brief-task-01-fresh.md" <<EOF
---
task: task-01-fresh
created: 2026-07-19
brief_tier: opus@high
---
## References
| file:line | git blob SHA |
| --- | --- |
| src/handler.py:1 | $SHA |
| goal:wp-01-fixture | $GH |

## Context
delta-only brief context.

## Skeleton
\`\`\`python
def handler() -> str: ...
\`\`\`

Task pointer: task-01-fresh.md
EOF
BRIEF_BEFORE="$(cat "$WP/brief-task-01-fresh.md")"

cat > "$WP/task-01-fresh.md" <<'EOF'
---
name: task-01-fresh
status: briefed
complexity: medium
---
## Goal
Fixture task consuming a fresh brief.
EOF

out="$(bash "$STALE_SH" "$WP" "task-01-fresh" 2>&1)"
rc=$?

fail() { echo "FAIL: $1"; echo "--- output ---"; echo "$out"; exit 1; }

[ "$rc" -eq 0 ] || fail "expected exit 0 (FRESH), got rc=$rc"
echo "$out" | grep -q "verdict: FRESH" || fail "expected verdict: FRESH"
if grep -q "rebrief_requested" "$WP/task-01-fresh.md"; then
  fail "a fresh brief must NOT record a re-brief request"
fi
if [ "$BRIEF_BEFORE" != "$(cat "$WP/brief-task-01-fresh.md")" ]; then
  fail "the immutable brief was modified during re-validation"
fi

# Gated (wp-08 single-writer hook): the sanctioned Bash-path status writer is
# allowed while the Edit tool is blocked. Assert only when the hook is present.
HOOK="$HOME/.claude/hooks/goalforge-single-writer.sh"
if [ -f "$HOOK" ]; then
  echo "INFO: wp-08 single-writer hook present — pending→briefed sanctioned-path assertion in force (see task-05 suite)."
else
  echo "SKIP: wp-08 single-writer hook absent — pending→briefed sanctioned-path assertion gated (task-04 Step 4)."
fi

echo "PASS: fresh brief passes staleness re-validation unchanged (exit 0, no re-brief, brief immutable)"
exit 0
