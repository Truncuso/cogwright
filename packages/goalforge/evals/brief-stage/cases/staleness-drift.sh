#!/usr/bin/env bash
# brief-stage eval case (wp-06 task-04): a STALE brief — a References anchor's file
# git blob SHA drifted from the recorded SHA (case A), and the WP goal-hash drifted
# from the recorded goal-hash (case B) — trips the executor's staleness
# re-validation. On drift a re-brief request is recorded in the TASK checkpoint
# block, the immutable brief is left untouched, and the stale brief is NOT consumed
# (nonzero exit). Offline, deterministic — no network / model calls.
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
STALE_SH="$SKILL_DIR/execute/brief-staleness.sh"
GOAL_HASH_SH="$SKILL_DIR/scripts/goalforge-goal-hash.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; echo "--- output ---"; echo "${out:-}"; exit 1; }

# ── Case A: a referenced file's blob SHA drifts ──────────────────────────────
WPA="$TMP/wp-01-fixture"
mkdir -p "$WPA/src"
printf 'def handler():\n    return "v1"\n' > "$WPA/src/handler.py"
SHA_A="$(git hash-object "$WPA/src/handler.py")"

cat > "$WPA/overview.md" <<'EOF'
---
name: wp-01-fixture
title: staleness-drift fixture WP (blob)
status: ready
stage_updated: 2026-07-19
goal:
  outcome: "fixture goal for staleness-drift blob case"
  verification:
    strategy: deterministic
---
## Goal
fixture
EOF
GH_A="$(bash "$GOAL_HASH_SH" "$WPA")"

cat > "$WPA/brief-task-01-drift.md" <<EOF
---
task: task-01-drift
created: 2026-07-19
brief_tier: opus@high
---
## References
| file:line | git blob SHA |
| --- | --- |
| src/handler.py:1 | $SHA_A |
| goal:wp-01-fixture | $GH_A |
EOF
BRIEF_A_BEFORE="$(cat "$WPA/brief-task-01-drift.md")"

cat > "$WPA/task-01-drift.md" <<'EOF'
---
name: task-01-drift
status: briefed
complexity: medium
---
## Goal
Fixture task whose referenced file drifted after briefing.
EOF

# Drift the referenced file's content → its git blob SHA changes.
printf 'def handler():\n    return "v2-CHANGED"\n' > "$WPA/src/handler.py"

out="$(bash "$STALE_SH" "$WPA" "task-01-drift" 2>&1)"; rc=$?
[ "$rc" -eq 3 ] || fail "case A: expected exit 3 (STALE), got rc=$rc"
echo "$out" | grep -q "verdict: STALE" || fail "case A: expected verdict: STALE"
grep -q "rebrief_requested: true" "$WPA/task-01-drift.md" || fail "case A: re-brief request not recorded in task checkpoint"
grep -q "## Checkpoint" "$WPA/task-01-drift.md" || fail "case A: checkpoint block not present"
[ "$BRIEF_A_BEFORE" = "$(cat "$WPA/brief-task-01-drift.md")" ] || fail "case A: immutable brief was modified"

# ── Case B: the WP goal-hash drifts ──────────────────────────────────────────
WPB="$TMP/wp-02-fixture"
mkdir -p "$WPB/src"
printf 'def worker():\n    return 1\n' > "$WPB/src/worker.py"
SHA_B="$(git hash-object "$WPB/src/worker.py")"

cat > "$WPB/overview.md" <<'EOF'
---
name: wp-02-fixture
title: staleness-drift fixture WP (goal-hash)
status: ready
stage_updated: 2026-07-19
goal:
  outcome: "ORIGINAL goal outcome"
  verification:
    strategy: deterministic
---
## Goal
fixture
EOF

cat > "$WPB/brief-task-01-goaldrift.md" <<EOF
---
task: task-01-goaldrift
created: 2026-07-19
brief_tier: opus@high
---
## References
| file:line | git blob SHA |
| --- | --- |
| src/worker.py:1 | $SHA_B |
| goal:wp-02-fixture | deadbeefstale |
EOF

cat > "$WPB/task-01-goaldrift.md" <<'EOF'
---
name: task-01-goaldrift
status: briefed
complexity: medium
---
## Goal
Fixture task whose WP goal-hash drifted after briefing.
EOF

out="$(bash "$STALE_SH" "$WPB" "task-01-goaldrift" 2>&1)"; rc=$?
[ "$rc" -eq 3 ] || fail "case B: expected exit 3 (STALE goal-hash), got rc=$rc"
echo "$out" | grep -q "goal-hash" || fail "case B: expected a goal-hash drift reason"
grep -q "rebrief_requested: true" "$WPB/task-01-goaldrift.md" || fail "case B: re-brief request not recorded"

echo "PASS: staleness drift (blob SHA + goal-hash) trips re-validation, records re-brief request, brief immutable, stale brief not consumed"
exit 0
