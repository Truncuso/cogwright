#!/usr/bin/env bash
# goalforge-rollup.test.sh — wp-03 b5 sabotage pair for the configured
# per-dispatch token WARN in goalforge-rollup.sh, driven over a throwaway
# mktemp feature dir (never a live plans/ tree).
#
#   known-good : a trace with one dispatch.completed at tokens 260000 read
#                against a dispatch file whose rollup.token_warn is 250000
#                prints a WARN line naming the dispatch and the threshold;
#                exit stays 0.
#   known-bad  : the SAME trace read against a dispatch file whose
#                rollup.token_warn is raised above 260000 prints NO WARN
#                line; exit stays 0 (the WARN tracks the config, not the
#                renderer's hard-coded taste).
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROLLUP="$SD/../goalforge-rollup.sh"
FIXTURES="$SD/fixtures/dispatch"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

FEATURE="$T/feature-rollup"; mkdir -p "$FEATURE"
cp "$FIXTURES/trace-b5.jsonl" "$FEATURE/trace-events.jsonl"

# A raised-threshold variant of the shipped default (only token_warn differs).
RAISED="$T/dispatch-token-warn-raised.yaml"
sed 's/^  token_warn: .*/  token_warn: 500000/' \
    "$FIXTURES/dispatch-default.yaml" > "$RAISED"

# ── known-good: configured threshold 250000 -> WARN naming dispatch + value ──
OUT="$(bash "$ROLLUP" "$FEATURE" --dispatch "$FIXTURES/dispatch-default.yaml" 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] \
   && grep -q 'WARN: dispatch goalforge-implementer tokens=260000 exceeds token_warn=250000' <<<"$OUT" \
   && grep -q 'Completed: 1 (.*tokens=260000 tool_uses=12)' <<<"$OUT"; then
    ok "known-good: tokens 260000 over token_warn 250000 -> WARN line, exit 0"
else
    bad "known-good: tokens 260000 over token_warn 250000 -> WARN line, exit 0 (rc=$RC)"
    echo "$OUT" | sed 's/^/        /'
fi

# ── known-bad: threshold raised above the row -> no WARN, still exit 0 ───────
OUT2="$(bash "$ROLLUP" "$FEATURE" --dispatch "$RAISED" 2>&1)"
RC2=$?
if [[ "$RC2" -eq 0 ]] && ! grep -q 'WARN: dispatch' <<<"$OUT2"; then
    ok "known-bad: token_warn raised above the row -> no WARN, exit 0"
else
    bad "known-bad: token_warn raised above the row -> no WARN, exit 0 (rc=$RC2)"
    echo "$OUT2" | sed 's/^/        /'
fi

echo
echo "goalforge-rollup.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
