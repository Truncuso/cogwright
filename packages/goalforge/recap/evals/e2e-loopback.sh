#!/usr/bin/env bash
# e2e-loopback.sh — end-to-end dogfood: drive a fixture WP through the full
#   execute -> verify -> inject-gap -> loop-back -> re-execute -> verify cycle
#   and assert recap.md records ONE commit per WP (at WP altitude, not per task),
#   the loop-back entry, and the final status line.
#
# This proves goalforge-recap (the living trace) and goalforge-watchdog (the gap audit whose
# finding triggers a loop-back) integrate into the goalforge-execute/goalforge-verify loop
# WITHOUT changing loop control or status-advance authority: the harness only
# records into recap.md; it never advances a real WP status.
#
# Fixture-only: everything happens inside a mktemp git repo. No real feature
# plan is touched. Exit 0 on all-pass, non-zero on any failed assertion.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECAP_SH="$SCRIPT_DIR/../../scripts/recap.sh"

[[ -f "$RECAP_SH" ]] || { echo "FATAL: recap.sh not found at $RECAP_SH" >&2; exit 1; }

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# ── Fixture git repo (commit hashes come from git rev-parse, same as the loop) ──
git -C "$TMPDIR" init -q
git -C "$TMPDIR" config user.email "e2e@test.local"
git -C "$TMPDIR" config user.name "e2e"

RECAP="$TMPDIR/recap.md"
WP="wp-fixture"
PASS=0
FAIL=0

assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# Make a fixture commit and echo its short hash (models an goalforge-execute task commit).
fixture_commit() {
  local msg="$1"
  echo "$msg $RANDOM" > "$TMPDIR/work.txt"
  git -C "$TMPDIR" add work.txt
  git -C "$TMPDIR" commit -q -m "$msg"
  git -C "$TMPDIR" rev-parse --short HEAD
}

echo "=== goalforge-recap e2e: execute -> verify -> gap -> loop-back -> re-execute -> verify ==="

# 1. goalforge-execute Step 0: recap init for the feature
bash "$RECAP_SH" init "$RECAP" "fixture-feature"

# 2. goalforge-execute: task-01 commit -> Step 8.5 recap append-task
C1="$(fixture_commit 'feat(task-01): first task')"
( cd "$TMPDIR" && bash "$RECAP_SH" append-task "$RECAP" "$WP" "task-01" "ok" )

# 3. goalforge-execute: task-02 commit -> Step 8.5 recap append-task
C2="$(fixture_commit 'feat(task-02): second task')"
( cd "$TMPDIR" && bash "$RECAP_SH" append-task "$RECAP" "$WP" "task-02" "ok" )

assert "task-01 row present (2-col, no per-task commit column)" "grep -qF '| task-01 | ok |' '$RECAP'"
assert "task-02 row present (2-col, no per-task commit column)" "grep -qF '| task-02 | ok |' '$RECAP'"
assert "task table has no Commit column" "! grep -qF '| Task | Commit | Result |' '$RECAP'"

# 4. goalforge-verify: acceptance passes, then goalforge-watchdog audits the diff and finds a
#    semantic gap (missing test at the changed seam). The gap finding triggers a
#    loop-back -> goalforge-execute Step 8.5 records it. (Watchdog is model-driven; the
#    harness injects the gap deterministically to exercise the recorded path.)
( cd "$TMPDIR" && bash "$RECAP_SH" append-loopback "$RECAP" "$WP" "2" "watchdog: missing test at changed seam" "task-02" )

assert "loop-back entry recorded (iter 2, re-executed task-02)" \
  "grep -qF 'iter 2: watchdog: missing test at changed seam (re-executed task-02)' '$RECAP'"

# 5. goalforge-execute re-executes task-02 with the fix -> new commit -> append-task
#    UPDATES the task-02 row in place with the new commit (per-task commit ref
#    tracks the re-execution; no duplicate row).
C2B="$(fixture_commit 'fix(task-02): add missing test at seam')"
( cd "$TMPDIR" && bash "$RECAP_SH" append-task "$RECAP" "$WP" "task-02" "ok" )

assert "task-02 row not duplicated after loop-back" \
  "[[ \$(grep -c '| task-02 |' '$RECAP') -eq 1 ]]"

# 6. goalforge-verify: record the WP as ONE row carrying the SINGLE WP commit at WP
#    altitude (record-wp) — the answer to "trace too many commits" — then rollup.
WPC="$(git -C "$TMPDIR" rev-parse --short HEAD)"
( cd "$TMPDIR" && bash "$RECAP_SH" record-wp "$RECAP" "$WP" "yellow" "$WPC" "completed after 1 loop-back" )
( cd "$TMPDIR" && bash "$RECAP_SH" rollup "$RECAP" )

assert "WP status line carries the single WP commit ($WPC)" \
  "grep -qF 'Status: yellow — $WPC — completed after 1 loop-back' '$RECAP'"
assert "feature rollup counts the WP (1 yellow)" "grep -qF '1 yellow' '$RECAP'"
assert "exactly one commit hash recorded for the WP (one-commit-per-WP trace)" \
  "[[ \$(grep -cF \"$WPC\" '$RECAP') -eq 1 ]]"

# 7. Loop-control invariant: the harness never advanced a real WP status; recap
#    is record-only. Assert the recap file is the ONLY artifact mutated (no plan
#    status files exist in the fixture).
assert "record-only: no plan overview.md written by recap" "[[ ! -e '$TMPDIR/overview.md' ]]"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
