#!/usr/bin/env bash
# brief-stage eval case (wp-06 task-03): a task fixture at status `briefed`
# validates with 0 errors. `briefed` is the interim task status between pending
# and in-progress (full order pending→briefed→in-progress→implemented→verified).
# Offline, deterministic — no network / model calls.
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
VALIDATE_SH="$SKILL_DIR/scripts/goalforge-validate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

WP="$TMP/wp-01-fixture"
mkdir -p "$WP"

cat > "$WP/overview.md" <<'EOF'
---
name: wp-fixture
title: briefed-status fixture WP
status: ready
stage_updated: 2026-07-19
---
## Goal
Fixture WP for the briefed-status validator case.
EOF

# A gated (medium) task at the interim `briefed` status — no brief required yet
# (the brief-skip invariant fires only at implemented/verified).
cat > "$WP/task-01-briefed-fixture.md" <<'EOF'
---
name: task-01-briefed-fixture
title: a task parked at the interim briefed status
status: briefed
complexity: medium
---
## Goal
Validate that `briefed` is an accepted task status.
EOF

out="$(bash "$VALIDATE_SH" --show "$TMP" 2>&1)"
rc=$?

if [ "$rc" -eq 0 ] && ! echo "$out" | grep -q "^ERROR"; then
  echo "PASS: briefed-status task validates with 0 errors (exit 0, no ERROR)"
  exit 0
else
  echo "FAIL: briefed-status task did not validate cleanly (rc=$rc)"
  echo "$out"
  exit 1
fi
