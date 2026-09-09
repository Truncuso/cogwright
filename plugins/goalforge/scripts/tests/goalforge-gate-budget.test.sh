#!/usr/bin/env bash
# goalforge-gate-budget.test.sh — sabotage pair + full behavioral coverage for
# goalforge-gate-budget.sh (T19, ticket-74 / C4 self-disable, b8).
#
# Drives the REAL goalforge-gate-budget.sh over throwaway COPIES of the fixture
# trees under evals/fixtures/gate-budget/ (never the checked-in fixture itself
# — the script under test WRITES a gate.disabled row on trip, so a live fixture
# dir would accumulate state across runs).
#
# Sabotage pair (ticket-74 contract — one known-bad exit-nonzero, one known-good
# exit-0), plus the full b8 case set from the WP checklist:
#   known-bad   two-block-no-commit   2 fails, no commit -> exit 4 (disabled)
#   known-good  one-block             1 fail             -> exit 0 (has budget)
#   two-block-then-commit             2 fails THEN a commit -> exit 0 (reset)
#   already-disabled                  a prior gate.disabled row -> exit 4,
#                                     WITHOUT writing a second row (idempotent)
#   internal-error                    missing --feature-dir -> exit 2

set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUDGET="$SD/../goalforge-gate-budget.sh"
FIXTURES="$SD/../../evals/fixtures/gate-budget"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# Copies a named fixture dir into a fresh throwaway tmp dir; echoes its path.
copy_fixture() {
    local name="$1" work
    work="$(mktemp -d)"
    cp "$FIXTURES/$name/trace-events.jsonl" "$work/trace-events.jsonl"
    printf '%s' "$work"
}

# ── known-bad: two BLOCK-equivalent (result: fail) rows, no commit ──────────
# Must self-disable: exit 4 AND a gate.disabled row appended to the trace.
W1="$(copy_fixture two-block-no-commit)"
"$BUDGET" example-gate --feature-dir "$W1" --session fixture-session
RC1=$?
if [ "$RC1" -eq 4 ] && grep -q '"type":"gate.disabled"' "$W1/trace-events.jsonl"; then
    ok "known-bad two-block-no-commit: exit 4 + gate.disabled row written"
else
    bad "known-bad two-block-no-commit: exit 4 + gate.disabled row written (rc=$RC1)"
    cat "$W1/trace-events.jsonl" | sed 's/^/        /'
fi
rm -rf "$W1"

# ── known-good: a single fail — budget intact ────────────────────────────────
W2="$(copy_fixture one-block)"
"$BUDGET" example-gate --feature-dir "$W2" --session fixture-session
RC2=$?
if [ "$RC2" -eq 0 ]; then
    ok "known-good one-block: exit 0 (budget intact)"
else
    bad "known-good one-block: exit 0 (budget intact) (rc=$RC2)"
fi
rm -rf "$W2"

# ── commit resets the budget: two fails THEN a shipped fix ──────────────────
W3="$(copy_fixture two-block-then-commit)"
"$BUDGET" example-gate --feature-dir "$W3" --session fixture-session
RC3=$?
if [ "$RC3" -eq 0 ]; then
    ok "two-block-then-commit: exit 0 (commit.linked resets the strike count)"
else
    bad "two-block-then-commit: exit 0 (commit.linked resets the strike count) (rc=$RC3)"
fi
rm -rf "$W3"

# ── idempotency: an already-disabled gate stays exit 4, no duplicate row ────
W4="$(copy_fixture already-disabled)"
BEFORE_LINES="$(wc -l < "$W4/trace-events.jsonl")"
"$BUDGET" example-gate --feature-dir "$W4" --session fixture-session
RC4=$?
AFTER_LINES="$(wc -l < "$W4/trace-events.jsonl")"
DISABLED_ROWS="$(grep -c '"type":"gate.disabled"' "$W4/trace-events.jsonl")"
if [ "$RC4" -eq 4 ] && [ "$BEFORE_LINES" -eq "$AFTER_LINES" ] && [ "$DISABLED_ROWS" -eq 1 ]; then
    ok "already-disabled: exit 4, no second gate.disabled row (idempotent)"
else
    bad "already-disabled: exit 4, no second gate.disabled row (idempotent) (rc=$RC4, before=$BEFORE_LINES, after=$AFTER_LINES, disabled_rows=$DISABLED_ROWS)"
fi
rm -rf "$W4"

# ── internal error: missing --feature-dir is a hard, fail-closed exit 2 ─────
OUT5="$("$BUDGET" example-gate 2>&1)"
RC5=$?
if [ "$RC5" -eq 2 ]; then
    ok "internal-error missing --feature-dir: exit 2 (fail-closed)"
else
    bad "internal-error missing --feature-dir: exit 2 (fail-closed) (rc=$RC5)"
    echo "$OUT5" | sed 's/^/        /'
fi

# ── internal error: --feature-dir that does not exist ───────────────────────
OUT6="$("$BUDGET" example-gate --feature-dir /nonexistent/gate-budget-fixture 2>&1)"
RC6=$?
if [ "$RC6" -eq 2 ]; then
    ok "internal-error nonexistent --feature-dir: exit 2 (fail-closed)"
else
    bad "internal-error nonexistent --feature-dir: exit 2 (fail-closed) (rc=$RC6)"
    echo "$OUT6" | sed 's/^/        /'
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
