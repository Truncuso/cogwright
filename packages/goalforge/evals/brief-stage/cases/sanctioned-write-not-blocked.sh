#!/usr/bin/env bash
# brief-stage eval case (wp-06 task-05, Step 5): the pending→briefed status write
# via the SANCTIONED Bash-path writer is NOT hook-blocked, while the same mutation
# via the Edit tool IS blocked.
#
# The single-writer hook (wp-08) discriminates purely on tool surface: it blocks
# Edit/Write/MultiEdit mutations of `status:`/`goal_approved_version:` on plan/WP
# files (exit 2) and never sees the sanctioned Bash-path writers
# (goalforge-transition.sh) — they mutate via `Bash`, which the tool_name filter
# lets through by construction. The hook's own --self-test proves exactly this
# discrimination (Edit status mutation → detected/blocked; Bash tool_name → not
# detected/allowed), which is the guarantee the pending→briefed write relies on.
#
# GATED on the wp-08 single-writer hook landing: SKIP (pass) when absent.
set -uo pipefail

HOOK="$HOME/.claude/hooks/goalforge-single-writer.sh"

if [ ! -f "$HOOK" ]; then
  echo "SKIP: wp-08 single-writer hook absent — pending→briefed sanctioned-path assertion gated (Step 5)."
  exit 0
fi

out="$(bash "$HOOK" --self-test 2>&1)"
rc=$?

if [ "$rc" -ne 0 ]; then
  echo "FAIL: single-writer hook --self-test did not pass (rc=$rc)"
  echo "$out"
  exit 1
fi

# The self-test must specifically cover: Edit status mutation blocked AND a
# Bash tool_name allowed — the exact Edit-blocked / sanctioned-Bash-allowed
# discrimination the pending→briefed write depends on.
echo "$out" | grep -qi "Edit status mutation.*detected"   || { echo "FAIL: self-test lacks the Edit-status-mutation-blocked assertion"; echo "$out"; exit 1; }
echo "$out" | grep -qi "Bash tool_name.*not detected"     || { echo "FAIL: self-test lacks the Bash-tool-name-allowed assertion"; echo "$out"; exit 1; }

echo "PASS: single-writer hook blocks Edit-surface status mutation and allows the sanctioned Bash-path writer (pending→briefed not hook-blocked)"
exit 0
