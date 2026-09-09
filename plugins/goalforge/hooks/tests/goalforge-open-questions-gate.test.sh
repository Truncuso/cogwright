#!/usr/bin/env bash
# goalforge-open-questions-gate.test.sh — sabotage pair for
# goalforge-open-questions-gate.sh (ticket-74 shape: known-bad exits 2,
# known-good exits 0), plus the gate.result trace-events.jsonl assertion
# (D9/T22): a fresh temp copy of the fixture under a temp plans root, so the
# real hook entry point (stdin, PLANS_ROOT resolution, goalforge-trace-emit)
# is exercised end to end. Fixtures live under
# packages/goalforge/evals/fixtures/hooks/goalforge-open-questions-gate/ —
# never inline here. Hermetic: everything happens in a mktemp dir; nothing is
# ever written into a real plans/ tree.
set -uo pipefail

HD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HD/goalforge-open-questions-gate.sh"
FIX="$HD/../evals/fixtures/hooks/goalforge-open-questions-gate"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A dedicated, throwaway plans root (SDD_PLANS_DIR) per fixture, so the
# gate.result row lands in a private trace-events.jsonl this test alone reads.
setup_case() { # <label> -> echoes the overview.md path it created
    local label="$1" root
    root="$WORK/$label"
    mkdir -p "$root/plans/feat"
    printf '%s' "$root/plans/feat/overview.md"
}

payload() { # <overview path>
    command jq -n --arg fp "$1" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"status: hardened", new_string:"status: ready"}}'
}

# ── known-bad: unresolved open question, ->ready edit -> exit 2 ────────────
bad_overview="$(setup_case bad)"
cp "$FIX/bad-overview.md" "$bad_overview"
OUT="$(payload "$bad_overview" | SDD_PLANS_DIR="$WORK/bad/plans" bash "$HOOK" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then
    ok "known-bad (unresolved OQ) -> exit 2"
else
    bad "known-bad (unresolved OQ) -> exit $rc (want 2)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

trace="$WORK/bad/plans/feat/trace-events.jsonl"
if [ -f "$trace" ] && command jq -e \
    'select(.type=="gate.result" and .gate=="open-questions" and .result=="fail" and (.wp|length>0))' \
    "$trace" >/dev/null 2>&1; then
    ok "known-bad -> gate.result{gate:open-questions,result:fail,wp:<set>} emitted"
else
    bad "known-bad -> gate.result row missing/malformed ($(cat "$trace" 2>/dev/null))"
fi

# ── known-good: every OQ resolved, ->ready edit -> exit 0 ──────────────────
good_overview="$(setup_case good)"
cp "$FIX/good-overview.md" "$good_overview"
OUT="$(payload "$good_overview" | SDD_PLANS_DIR="$WORK/good/plans" bash "$HOOK" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$OUT" ]; then
    ok "known-good (all OQ resolved) -> exit 0, silent"
else
    bad "known-good (all OQ resolved) -> exit $rc (want 0, silent) out='$OUT'"
fi

trace="$WORK/good/plans/feat/trace-events.jsonl"
if [ -f "$trace" ] && command jq -e \
    'select(.type=="gate.result" and .gate=="open-questions" and .result=="pass" and (.wp|length>0))' \
    "$trace" >/dev/null 2>&1; then
    ok "known-good -> gate.result{gate:open-questions,result:pass,wp:<set>} emitted"
else
    bad "known-good -> gate.result row missing/malformed ($(cat "$trace" 2>/dev/null))"
fi

# ── the hook's own internal self-test still passes ──────────────────────────
rc=0; bash "$HOOK" --self-test >"$WORK/selftest.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "--self-test passes (exit 0)" \
    || bad "--self-test exit $rc; $(cat "$WORK/selftest.out")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
