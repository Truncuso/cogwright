#!/usr/bin/env bash
# brief-stage eval case (wp-06 task-03): the STATIC brief-skip invariant.
# A complexity-gated (medium/high) task that reached implemented/verified with
# NO sibling brief-task-NN.md is flagged (WARN). A negative sibling — an ungated
# (low-complexity) task at the same status with no brief — is NOT flagged.
# Static current-file-state check; no transition observation. Offline.
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
title: brief-skip invariant fixture WP
status: ready
stage_updated: 2026-07-19
---
## Goal
Fixture WP for the static brief-skip invariant.
EOF

# GATED task: complexity high, status implemented, NO sibling brief-task-01.md → flagged.
cat > "$WP/task-01-gated-skip.md" <<'EOF'
---
name: task-01-gated-skip
title: a gated task that reached implemented without a brief
status: implemented
complexity: high
---
## Goal
Trip the brief-skip invariant.
EOF

# NEGATIVE control: ungated (low) task, same status, no brief → NOT flagged.
cat > "$WP/task-02-ungated-ok.md" <<'EOF'
---
name: task-02-ungated-ok
title: a low-complexity task legitimately skips briefing
status: implemented
complexity: low
---
## Goal
Must not be flagged by the brief-skip invariant.
EOF

out="$(bash "$VALIDATE_SH" --show "$TMP" 2>&1)"
rc=$?

flagged_gated=0
flagged_ungated=0
echo "$out" | grep -q "^WARN.*task-01-gated-skip.*brief stage was skipped" && flagged_gated=1
echo "$out" | grep -q "task-02-ungated-ok.*brief stage was skipped" && flagged_ungated=1

if [ "$flagged_gated" -eq 1 ] && [ "$flagged_ungated" -eq 0 ]; then
  echo "PASS: gated implemented task with no sibling brief is flagged; ungated is not"
  exit 0
else
  echo "FAIL: brief-skip invariant behaved wrong (gated=$flagged_gated ungated=$flagged_ungated rc=$rc)"
  echo "$out"
  exit 1
fi
