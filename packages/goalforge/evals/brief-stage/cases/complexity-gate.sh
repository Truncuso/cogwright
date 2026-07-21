#!/usr/bin/env bash
# brief-stage eval case (wp-06 task-05): the COMPLEXITY GATE, read from the task
# frontmatter `complexity` field in {medium,high} (NOT goalforge-wp-complexity.sh).
#
# The gate decision is exercised deterministically through goalforge-validate.sh's
# static brief-skip invariant, which reads `complexity` from exactly the same
# task-frontmatter field the brief-authoring gate does:
#   - a MEDIUM task that reached `implemented` WITHOUT a sibling brief is flagged
#     (the gate fired → a brief was required → skipping it is a WARN);
#   - the SAME medium task WITH a sibling brief-task-NN.md is NOT flagged
#     (the gate fired → a brief was authored → satisfied);
#   - a LOW task at the same status WITHOUT a brief is NOT flagged
#     (the gate did NOT fire → low tasks skip briefing entirely).
# Together: medium triggers brief authoring, low does not. Offline, deterministic.
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
title: complexity-gate fixture WP
status: ready
stage_updated: 2026-07-19
---
## Goal
Fixture WP for the complexity gate (medium triggers a brief, low does not).
EOF

# MEDIUM, implemented, NO brief → gate fired, brief required but skipped → flagged.
cat > "$WP/task-01-medium-no-brief.md" <<'EOF'
---
name: task-01-medium-no-brief
title: a medium task that reached implemented without a brief
status: implemented
complexity: medium
---
## Goal
The complexity gate fires for a medium task; skipping the brief is flagged.
EOF

# MEDIUM, implemented, WITH brief → gate fired, brief authored → NOT flagged.
cat > "$WP/task-02-medium-briefed.md" <<'EOF'
---
name: task-02-medium-briefed
title: a medium task that was briefed
status: implemented
complexity: medium
---
## Goal
The complexity gate fires and a brief was authored; must not be flagged.
EOF
cat > "$WP/brief-task-02.md" <<'EOF'
---
task: task-02-medium-briefed
created: 2026-07-19
brief_tier: opus@high
---
## References
| file:line | git blob SHA |
| --- | --- |
| src/x.py:1 | 0000000000000000000000000000000000000000 |
EOF

# LOW, implemented, NO brief → gate did NOT fire → NOT flagged.
cat > "$WP/task-03-low-no-brief.md" <<'EOF'
---
name: task-03-low-no-brief
title: a low task that legitimately skips briefing
status: implemented
complexity: low
---
## Goal
The complexity gate does not fire for a low task; no brief is required.
EOF

out="$(bash "$VALIDATE_SH" --show "$TMP" 2>&1)"
rc=$?

fail() { echo "FAIL: $1"; echo "--- output ---"; echo "$out"; exit 1; }

flag_medium_nobrief=0; flag_medium_briefed=0; flag_low=0
echo "$out" | grep -q "task-01-medium-no-brief.*brief stage was skipped" && flag_medium_nobrief=1
echo "$out" | grep -q "task-02-medium-briefed.*brief stage was skipped" && flag_medium_briefed=1
echo "$out" | grep -q "task-03-low-no-brief.*brief stage was skipped"    && flag_low=1

[ "$flag_medium_nobrief" -eq 1 ] || fail "medium task with no brief was NOT flagged (gate should fire)"
[ "$flag_medium_briefed" -eq 0 ] || fail "medium task WITH a brief was flagged (should be satisfied)"
[ "$flag_low" -eq 0 ]            || fail "low task was flagged (gate must not fire for low complexity)"

echo "PASS: complexity gate — medium triggers brief authoring (flagged when skipped, satisfied when briefed); low does not"
exit 0
