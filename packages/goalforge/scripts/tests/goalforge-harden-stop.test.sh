#!/usr/bin/env bash
# goalforge-harden-stop.test.sh — sabotage pair for goalforge-harden-stop.sh
# (b6 / ticket-74 shape: known-bad exits 3 [park], known-good exits 0).
# Fixtures live under packages/goalforge/evals/fixtures/harden-stop/ — a
# <feature>/<wp>/ tree each carrying its own trace-events.jsonl at feature
# altitude, never inline here.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STOP="$SD/../goalforge-harden-stop.sh"
FIX="$SD/../../evals/fixtures/harden-stop"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# Work on throwaway copies so a run that appends findings.md never mutates
# the checked-in fixture tree.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -r "$FIX/two-rounds-feature"   "$WORK/two-rounds-feature"
cp -r "$FIX/one-round-feature"    "$WORK/one-round-feature"
cp -r "$FIX/token-ceiling-feature" "$WORK/token-ceiling-feature"

# ── known-bad: 2 harden.round rows recorded, ceiling=2 -> round 3 parks ─────
WP="$WORK/two-rounds-feature/wp-two-rounds"
OUT="$(bash "$STOP" "$WP" 2>&1)"; rc=$?
if [ "$rc" -eq 3 ]; then
    ok "2 rounds recorded -> exit 3 (park)"
else
    bad "2 rounds recorded -> exit 3 (park) (rc=$rc)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi
if [ -f "$WP/findings.md" ] && grep -q 'harden: ceiling-breached, rounds=2' "$WP/findings.md"; then
    ok "park appends the findings.md ceiling-breached row"
else
    bad "park appends the findings.md ceiling-breached row"
    [ -f "$WP/findings.md" ] && sed 's/^/        /' "$WP/findings.md"
fi

# ── known-good: 1 harden.round row recorded -> round 2 may run ─────────────
WP2="$WORK/one-round-feature/wp-one-round"
OUT2="$(bash "$STOP" "$WP2" 2>&1)"; rc2=$?
if [ "$rc2" -eq 0 ]; then
    ok "1 round recorded -> exit 0 (round may run)"
else
    bad "1 round recorded -> exit 0 (round may run) (rc=$rc2)"
    printf '%s\n' "$OUT2" | sed 's/^/        /'
fi
if [ ! -f "$WP2/findings.md" ]; then
    ok "no park -> no findings.md row written"
else
    bad "no park -> no findings.md row written"
fi

# ── token ceiling: 1 round but tokens over the default 60000 ceiling -> park
WP3="$WORK/token-ceiling-feature/wp-token-ceiling"
bash "$STOP" "$WP3" >/dev/null 2>&1; rc3=$?
if [ "$rc3" -eq 3 ]; then
    ok "token ceiling breached (70000 > 60000) -> exit 3 (park)"
else
    bad "token ceiling breached -> exit 3 (park) (rc=$rc3)"
fi

# ── SDD_HARDEN_TOKEN_CEILING override raises the ceiling -> no longer parks
rm -f "$WP3/findings.md"   # clear the previous case's park row first
SDD_HARDEN_TOKEN_CEILING=100000 bash "$STOP" "$WP3" >/dev/null 2>&1; rc4=$?
if [ "$rc4" -eq 0 ]; then
    ok "SDD_HARDEN_TOKEN_CEILING override raises the ceiling -> exit 0"
else
    bad "SDD_HARDEN_TOKEN_CEILING override raises the ceiling -> exit 0 (rc=$rc4)"
fi

# ── sabotage: jq masked off PATH -> harden.parked row still written ─────────
cp -r "$FIX/two-rounds-feature" "$WORK/two-rounds-jqmask"
JQ_STUB_DIR="$(mktemp -d)"
cat > "$JQ_STUB_DIR/jq" <<'EOF'
#!/usr/bin/env bash
echo "jq: masked for test" >&2
exit 127
EOF
chmod +x "$JQ_STUB_DIR/jq"
WP7="$WORK/two-rounds-jqmask/wp-two-rounds"
PATH="$JQ_STUB_DIR:$PATH" bash "$STOP" "$WP7" >/tmp/hs-jqmask.out 2>&1; rc7=$?
TRACE7="$WORK/two-rounds-jqmask/trace-events.jsonl"
if [ "$rc7" -eq 3 ] && [ -f "$TRACE7" ] && grep -q '"type":"harden.parked"' "$TRACE7" 2>/dev/null; then
    ok "jq masked off PATH -> harden.parked row still written (python3, no jq dependency)"
else
    bad "jq masked off PATH -> harden.parked row still written (rc=$rc7)"
    [ -f "$TRACE7" ] && sed 's/^/        /' "$TRACE7"
    sed 's/^/        /' /tmp/hs-jqmask.out
fi
rm -rf "$JQ_STUB_DIR"

# ── internal error: nonexistent wp-dir -> exit 2 ─────────────────────────────
bash "$STOP" "$WORK/does-not-exist" >/dev/null 2>/dev/null; rc5=$?
if [ "$rc5" -eq 2 ]; then
    ok "nonexistent wp-dir -> exit 2 (internal error)"
else
    bad "nonexistent wp-dir -> exit 2 (internal error) (rc=$rc5)"
fi

# ── usage error: no argument -> exit 2 ───────────────────────────────────────
bash "$STOP" >/dev/null 2>/dev/null; rc6=$?
if [ "$rc6" -eq 2 ]; then
    ok "no argument -> exit 2 (usage error)"
else
    bad "no argument -> exit 2 (usage error) (rc=$rc6)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
