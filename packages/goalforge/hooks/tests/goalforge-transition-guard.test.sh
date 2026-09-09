#!/usr/bin/env bash
# goalforge-transition-guard.test.sh — sabotage pair for
# goalforge-transition-guard.sh (ticket-74 shape: known-bad exits 2,
# known-good exits 0), plus the gate.result trace-events.jsonl assertion
# (D9/T22). Fixtures live under
# packages/goalforge/evals/fixtures/hooks/goalforge-transition-guard/ — never
# inline here. Hermetic: everything happens in a mktemp dir; nothing is ever
# written into a real plans/ tree.
set -uo pipefail

HD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HD/goalforge-transition-guard.sh"
FIX="$HD/../evals/fixtures/hooks/goalforge-transition-guard"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

setup_case() { # <label> -> echoes the overview.md path it created
    local label="$1" root
    root="$WORK/$label"
    mkdir -p "$root/plans/feat"
    printf '%s' "$root/plans/feat/overview.md"
}

# `spec -> archived` is enum-valid but carries no row in the state-machine
# edges table -> a confirmed illegal edge (matches the hook's own self-test).
bad_payload() { # <overview path>
    command jq -n --arg fp "$1" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"status: spec", new_string:"status: archived"}}'
}
# `spec -> hardened` is a legal forward edge.
good_payload() { # <overview path>
    command jq -n --arg fp "$1" \
        '{tool_name:"Edit", tool_input:{file_path:$fp, old_string:"status: spec", new_string:"status: hardened"}}'
}

# ── known-bad: illegal edge -> exit 2 ────────────────────────────────────────
bad_overview="$(setup_case bad)"
cp "$FIX/bad-overview.md" "$bad_overview"
OUT="$(bad_payload "$bad_overview" | SDD_PLANS_DIR="$WORK/bad/plans" bash "$HOOK" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then
    ok "known-bad (illegal edge spec->archived) -> exit 2"
else
    bad "known-bad (illegal edge) -> exit $rc (want 2)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

trace="$WORK/bad/plans/feat/trace-events.jsonl"
if [ -f "$trace" ] && command jq -e \
    'select(.type=="gate.result" and .gate=="transition-guard" and .result=="fail" and (.wp|length>0))' \
    "$trace" >/dev/null 2>&1; then
    ok "known-bad -> gate.result{gate:transition-guard,result:fail,wp:<set>} emitted"
else
    bad "known-bad -> gate.result row missing/malformed ($(cat "$trace" 2>/dev/null))"
fi

# ── known-good: legal edge -> exit 0 ────────────────────────────────────────
good_overview="$(setup_case good)"
cp "$FIX/good-overview.md" "$good_overview"
OUT="$(good_payload "$good_overview" | SDD_PLANS_DIR="$WORK/good/plans" bash "$HOOK" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$OUT" ]; then
    ok "known-good (legal edge spec->hardened) -> exit 0, silent"
else
    bad "known-good (legal edge) -> exit $rc (want 0, silent) out='$OUT'"
fi

trace="$WORK/good/plans/feat/trace-events.jsonl"
if [ -f "$trace" ] && command jq -e \
    'select(.type=="gate.result" and .gate=="transition-guard" and .result=="pass" and (.wp|length>0))' \
    "$trace" >/dev/null 2>&1; then
    ok "known-good -> gate.result{gate:transition-guard,result:pass,wp:<set>} emitted"
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
