#!/usr/bin/env bash
# goalforge-trace-emit.test.sh — ticket-74 sabotage pair for goalforge-trace-emit
# (wp-14 validating single-writer emitter), driven via its CLI over throwaway
# mktemp feature dirs (never a live plans/ tree).
#
#   known-bad  : an event with an unknown `type` (or missing a required field)
#                is rejected exit 2, and the log is left byte-unchanged.
#   known-good : a valid `gate.result` event (wp/gate/result all present, per
#                references/trace-events.md) is accepted exit 2->0, appended.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="$SD/../goalforge-trace-emit"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ── known-bad: unknown event type -> exit 2, no log file created ────────────
FD1="$T/unknown-type"; mkdir -p "$FD1"
OUT="$("$EMIT" --feature-dir "$FD1" --event '{"type":"no.such.type","wp":"wp-1"}' 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && [[ ! -f "$FD1/trace-events.jsonl" ]]; then
    ok "known-bad: unknown event type -> exit 2, log byte-unchanged (never created)"
else
    bad "known-bad: unknown event type -> exit 2, log byte-unchanged (rc=$RC)"
    echo "$OUT" | sed 's/^/        /'
fi

# ── known-bad: missing required field (gate.result needs wp/gate/result) ────
FD2="$T/missing-field"; mkdir -p "$FD2"
OUT2="$("$EMIT" --feature-dir "$FD2" --event '{"type":"gate.result","wp":"wp-1"}' 2>&1)"
RC2=$?
if [[ "$RC2" -eq 2 ]] && [[ ! -f "$FD2/trace-events.jsonl" ]]; then
    ok "known-bad: missing required field -> exit 2, log byte-unchanged"
else
    bad "known-bad: missing required field -> exit 2, log byte-unchanged (rc=$RC2)"
    echo "$OUT2" | sed 's/^/        /'
fi

# ── known-good: a valid gate.result event is accepted and appended ──────────
FD3="$T/valid-gate-result"; mkdir -p "$FD3"
OUT3="$("$EMIT" --feature-dir "$FD3" --print-row \
    --event '{"type":"gate.result","wp":"wp-01-x","gate":"verify","result":"pass"}' 2>&1)"
RC3=$?
if [[ "$RC3" -eq 0 ]] \
   && [[ -f "$FD3/trace-events.jsonl" ]] \
   && grep -q '"type":"gate.result"' "$FD3/trace-events.jsonl" \
   && grep -q '"seq":0' "$FD3/trace-events.jsonl"; then
    ok "known-good: valid gate.result -> exit 0, appended with seq 0"
else
    bad "known-good: valid gate.result -> exit 0, appended with seq 0 (rc=$RC3)"
    echo "$OUT3" | sed 's/^/        /'
fi

# ── known-bad: dispatch.completed without tokens/tool_uses (wp-03 b4) ───────
FD4="$T/dispatch-completed-no-sizing"; mkdir -p "$FD4"
OUT4="$("$EMIT" --feature-dir "$FD4" \
    --event '{"type":"dispatch.completed","wp":"wp-01-x","agent":"goalforge-implementer","outcome":"success","exit_code":0}' 2>&1)"
RC4=$?
if [[ "$RC4" -eq 2 ]] && [[ ! -f "$FD4/trace-events.jsonl" ]]; then
    ok "known-bad: dispatch.completed without tokens/tool_uses -> exit 2, no log bytes"
else
    bad "known-bad: dispatch.completed without tokens/tool_uses -> exit 2, no log bytes (rc=$RC4)"
    echo "$OUT4" | sed 's/^/        /'
fi

# ── known-good: dispatch.completed with both sizing fields (wp-03 b4) ───────
FD5="$T/dispatch-completed-sized"; mkdir -p "$FD5"
OUT5="$("$EMIT" --feature-dir "$FD5" \
    --event '{"type":"dispatch.completed","wp":"wp-01-x","agent":"goalforge-implementer","outcome":"success","exit_code":0,"tokens":1234,"tool_uses":5}' 2>&1)"
RC5=$?
if [[ "$RC5" -eq 0 ]] \
   && grep -q '"tokens":1234' "$FD5/trace-events.jsonl" \
   && grep -q '"tool_uses":5' "$FD5/trace-events.jsonl"; then
    ok "known-good: dispatch.completed with tokens+tool_uses -> exit 0, appended"
else
    bad "known-good: dispatch.completed with tokens+tool_uses -> exit 0, appended (rc=$RC5)"
    echo "$OUT5" | sed 's/^/        /'
fi

echo
echo "goalforge-trace-emit.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
