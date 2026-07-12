#!/usr/bin/env bash
# evals/run.sh — goalforge-recap eval harness
#
# Behavioral assertions (driven by scripts/recap.sh against a temp fixture) +
# static-contract checks on SKILL.md.
# Exit 0 on all-pass, exit 1 on any failure.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
RECAP_SH="$SKILL_DIR/scripts/recap.sh"

PASS=0
FAIL=0

check() {
  local desc="$1"
  local pattern="$2"
  if grep -qF "$pattern" "$SKILL_MD"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "        expected to find: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

assert() {
  local desc="$1"
  local cond="$2"
  if eval "$cond"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# ── Static: SKILL.md contract ────────────────────────────────────────────────
echo "=== goalforge-recap: static-contract checks ==="

check "name declared as goalforge-recap"       "name: goalforge-recap"
check "version declared"                 "version: 2.0.0"
check "recap.md mentioned"               "recap.md"
check "record-wp subcommand documented"  "record-wp"
check "one commit per WP (no per-task commit column)" "one commit per WP"
check "task table is 2-col (no Commit column)" "| Task | Result |"
check "Gotchas section present"          "## Gotchas"
check "skill-measure.sh hook present"    "skill-measure.sh goalforge-recap"
check "skill-trace.sh hook present"      "skill-trace.sh goalforge-recap:stop"
check "append-task subcommand documented" "append-task"
check "finalize subcommand documented"   "finalize"
check "rollup subcommand documented"     "rollup"
check "green/yellow/red semantics"       "green** — all tasks"
check "maintenance comment documented"   "do not hand-edit"

# ── Behavioral: lifecycle assertions via recap.sh ────────────────────────────
echo ""
echo "=== goalforge-recap: behavioral lifecycle checks ==="

TMPDIR_FIXTURE="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_FIXTURE"; }
trap cleanup EXIT

# Set up a minimal git repo for commit hash resolution
git -C "$TMPDIR_FIXTURE" init -q
git -C "$TMPDIR_FIXTURE" config user.email "eval@test.com"
git -C "$TMPDIR_FIXTURE" config user.name "Eval"
touch "$TMPDIR_FIXTURE/x"
git -C "$TMPDIR_FIXTURE" add x
git -C "$TMPDIR_FIXTURE" commit -q -m "eval-init"

RECAP="$TMPDIR_FIXTURE/recap.md"

# 1. init
bash "$RECAP_SH" init "$RECAP" "eval-feature"
assert "init: file created"                "[[ -f '$RECAP' ]]"
assert "init: header line present"         "grep -qF '# Recap — eval-feature' '$RECAP'"

# 2. init idempotency
BEFORE="$(cat "$RECAP")"
bash "$RECAP_SH" init "$RECAP" "eval-feature"
AFTER="$(cat "$RECAP")"
assert "init: idempotent (double-init = same file)" "[[ '$BEFORE' == '$AFTER' ]]"

# 3. append-task — first task
bash "$RECAP_SH" append-task "$RECAP" "wp-01" "setup" "ok"
assert "append-task: WP section created"   "grep -qF '## wp-01' '$RECAP'"
assert "append-task: task row written"     "grep -qF '| setup |' '$RECAP'"
assert "append-task: result column ok"     "grep -qF '| ok |' '$RECAP'"

# 4. append-task idempotency
bash "$RECAP_SH" append-task "$RECAP" "wp-01" "setup" "ok"
COUNT="$(grep -c '| setup |' "$RECAP")"
assert "append-task: no duplicate row on repeat call" "[[ '$COUNT' == '1' ]]"

# 5. append-loopback
bash "$RECAP_SH" append-loopback "$RECAP" "wp-01" "1" "flaky test" "setup"
assert "append-loopback: Loop-backs header present"  "grep -qF 'Loop-backs:' '$RECAP'"
assert "append-loopback: entry recorded"             "grep -qF 'iter 1: flaky test (re-executed setup)' '$RECAP'"

# 5b. append-loopback idempotency (same iter twice = upsert, not duplicated)
bash "$RECAP_SH" append-loopback "$RECAP" "wp-01" "1" "flaky test" "setup"
assert "append-loopback: idempotent (single entry per iter)" "[[ \$(grep -c '^- iter 1:' '$RECAP') -eq 1 ]]"

# 6. finalize
bash "$RECAP_SH" finalize "$RECAP" "wp-01" "yellow" "completed with loop-back"
assert "finalize: Status line written"      "grep -qF 'Status: yellow — completed with loop-back' '$RECAP'"

# 7. finalize idempotency (update, not duplicate)
bash "$RECAP_SH" finalize "$RECAP" "wp-01" "green" "clean on retry"
SC="$(grep -c '^Status:' "$RECAP")"
assert "finalize: only one Status line per WP"   "[[ '$SC' == '1' ]]"
assert "finalize: color updated in place"        "grep -qF 'Status: green — clean on retry' '$RECAP'"

# 8. second WP + rollup
bash "$RECAP_SH" append-task "$RECAP" "wp-02" "build" "ok"
bash "$RECAP_SH" finalize "$RECAP" "wp-02" "red" "blocked on dep"
bash "$RECAP_SH" rollup "$RECAP"
assert "rollup: Feature rollup section present"  "grep -qF '## Feature rollup' '$RECAP'"
assert "rollup: counts green WPs"                "grep -qF '1 green' '$RECAP'"
assert "rollup: counts red WPs"                  "grep -qF '1 red' '$RECAP'"
assert "rollup: total WP count"                  "grep -qF 'of 2 WPs' '$RECAP'"

# 9. rollup idempotency
bash "$RECAP_SH" rollup "$RECAP"
RC="$(grep -c '## Feature rollup' "$RECAP")"
assert "rollup: idempotent (single rollup section)" "[[ '$RC' == '1' ]]"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
