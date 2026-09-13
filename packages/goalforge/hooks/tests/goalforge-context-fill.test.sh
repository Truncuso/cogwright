#!/usr/bin/env bash
# goalforge-context-fill.test.sh — sabotage pair for goalforge-context-fill.sh
# (b3).
#
# The load-bearing case is the COMPARISON: two transcripts whose sizes differ
# by 4x must yield two DIFFERENT percentages, in the direction of the sizes. A
# hook that prints a constant satisfies every single-fixture shape check and
# measures nothing — so a constant-printing stub is run here and must fail.
set -uo pipefail

HD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HD/goalforge-context-fill.sh"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 4x apart, built at test time — no fixture file needs checking in for this.
head -c 25000  /dev/zero | tr '\0' 'x' > "$WORK/small.jsonl"
head -c 100000 /dev/zero | tr '\0' 'x' > "$WORK/large.jsonl"

pct_of() { # <hook> <transcript>  -> the percentage as a number, or empty
    GOALFORGE_TRANSCRIPT_FIXTURE="$2" bash "$1" </dev/null 2>/dev/null \
        | sed -n 's/.*~\([0-9][0-9.]*\)%.*/\1/p' | head -n 1
}

line_of() { GOALFORGE_TRANSCRIPT_FIXTURE="$2" bash "$1" </dev/null 2>&1; }

# ── one line each, exit 0 ─────────────────────────────────────────────────
for f in small large; do
    out="$(line_of "$HOOK" "$WORK/$f.jsonl")"; rc=$?
    n="$(printf '%s\n' "$out" | grep -c .)"
    { [ "$rc" -eq 0 ] && [ "$n" -eq 1 ]; } && ok "$f transcript -> exactly one line, exit 0" \
        || bad "$f transcript -> exit $rc, $n line(s): '$out'"
done

# ── the comparison: 4x size -> strictly larger percentage ─────────────────
ps="$(pct_of "$HOOK" "$WORK/small.jsonl")"
pl="$(pct_of "$HOOK" "$WORK/large.jsonl")"
if [ -n "$ps" ] && [ -n "$pl" ] && awk -v a="$ps" -v b="$pl" 'BEGIN{exit !(b>a)}'; then
    ok "4x transcript -> strictly larger percentage ($ps% -> $pl%)"
else
    bad "percentages did not track size ('$ps' vs '$pl')"
fi

# ── absent transcript -> prints nothing, exit 0 ───────────────────────────
out="$(line_of "$HOOK" "$WORK/nope.jsonl")"; rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$out" ]; } && ok "absent transcript -> silent, exit 0" \
    || bad "absent transcript -> exit $rc out='$out'"

# ── no transcript in the payload at all -> silent, exit 0 ─────────────────
out="$(printf '%s' '{"source":"startup"}' | env -u GOALFORGE_TRANSCRIPT_FIXTURE bash "$HOOK" 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$out" ]; } && ok "payload without transcript_path -> silent, exit 0" \
    || bad "payload without transcript_path -> exit $rc out='$out'"

# ── sabotage: a constant-printing hook must fail the comparison ───────────
STUB="$WORK/constant.sh"
{
    echo '#!/usr/bin/env bash'
    echo 'echo "goalforge: context fill ~42.0% of the estimated window (0 transcript bytes)"'
} > "$STUB"
ps="$(pct_of "$STUB" "$WORK/small.jsonl")"
pl="$(pct_of "$STUB" "$WORK/large.jsonl")"
if [ -n "$ps" ] && [ -n "$pl" ] && awk -v a="$ps" -v b="$pl" 'BEGIN{exit !(b>a)}'; then
    bad "sabotage NOT caught: a constant percentage passed the comparison"
else
    ok "sabotage caught: constant-percentage hook fails the comparison"
fi

# ── sabotage: a hook that prints on an absent transcript ──────────────────
sed 's#^\[ -f "\$TRANSCRIPT" \] || exit 0#[ -f "$TRANSCRIPT" ] || { echo "goalforge: context fill ~0.0% of the estimated window (0 transcript bytes)"; exit 0; }#' \
    "$HOOK" > "$WORK/noisy.sh"
out="$(line_of "$WORK/noisy.sh" "$WORK/nope.jsonl")"
[ -n "$out" ] && ok "sabotage caught: noisy-on-absent hook is detectable" \
    || bad "sabotage NOT caught: noisy-on-absent stub stayed silent"

# ── the hook's own self-test ──────────────────────────────────────────────
rc=0; bash "$HOOK" --self-test >"$WORK/selftest.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "--self-test passes (exit 0)" \
    || bad "--self-test exit $rc; $(cat "$WORK/selftest.out")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
