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
DFIX="$SD/fixtures/dispatch"
DISP_NULL="$DFIX/dispatch-default.yaml"      # harden.token_ceiling: null
DISP_300K="$DFIX/dispatch-ceiling-300k.yaml" # harden.token_ceiling: 300000
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# mkfeat <name> <trace fixture> -> prints a writable feature dir under $WORK
# holding a copy of fixtures/dispatch/wp-harden-high/ plus that trace.
mkfeat() {
    local dir="$WORK/$1"
    mkdir -p "$dir"
    cp -r "$DFIX/wp-harden-high" "$dir/wp-harden-high"
    cp "$DFIX/$2" "$dir/trace-events.jsonl"
    printf '%s' "$dir"
}

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

# ── soft sensor: 1 round, 70000 tokens, NO configured ceiling -> WARN, exit 0
# (was a park before wp-03 T7: with `harden.token_ceiling: null` and
# SDD_HARDEN_TOKEN_CEILING unset the token budget is a sensor, not a gate.)
WP3="$WORK/token-ceiling-feature/wp-token-ceiling"
bash "$STOP" "$WP3" --dispatch "$DISP_NULL" >/dev/null 2>&1; rc3=$?
if [ "$rc3" -eq 0 ] && [ ! -f "$WP3/findings.md" ]; then
    ok "70000 tokens, no configured ceiling -> exit 0 (soft sensor, no park)"
else
    bad "70000 tokens, no configured ceiling -> exit 0 (rc=$rc3)"
fi

# ── SDD_HARDEN_TOKEN_CEILING=<N> keeps its meaning: a hard ceiling -> park
SDD_HARDEN_TOKEN_CEILING=60000 bash "$STOP" "$WP3" --dispatch "$DISP_NULL" >/dev/null 2>&1; rc4=$?
if [ "$rc4" -eq 3 ]; then
    ok "SDD_HARDEN_TOKEN_CEILING=60000 (70000 > 60000) -> exit 3 (hard park)"
else
    bad "SDD_HARDEN_TOKEN_CEILING=60000 -> exit 3 (hard park) (rc=$rc4)"
fi
rm -f "$WP3/findings.md"

# ── b7 (1): 320k tokens, severity HIGH + register production, ceiling null,
#            SDD_HARDEN_TOKEN_CEILING unset -> exit 0 + one harden.warn row
#            naming the 300000 panel threshold.
B1="$(mkfeat b7-warn trace-b7-320k.jsonl)"
bash "$STOP" "$B1/wp-harden-high" --dispatch "$DISP_NULL" >/dev/null 2>&1; rcb1=$?
WARN_ROW="$(grep '"type":"harden.warn"' "$B1/trace-events.jsonl" 2>/dev/null)"
if [ "$rcb1" -eq 0 ] && [ -n "$WARN_ROW" ] && \
   printf '%s' "$WARN_ROW" | grep -q '"threshold":300000' && \
   printf '%s' "$WARN_ROW" | grep -q '"tokens":320000'; then
    ok "b7(1): 320k + ceiling null + env unset -> exit 0 + harden.warn threshold=300000"
else
    bad "b7(1): 320k + ceiling null + env unset -> exit 0 + harden.warn threshold=300000 (rc=$rcb1)"
    printf '%s\n' "$WARN_ROW" | sed 's/^/        /'
fi
if [ ! -f "$B1/wp-harden-high/findings.md" ]; then
    ok "b7(1): soft WARN writes no findings.md park row"
else
    bad "b7(1): soft WARN writes no findings.md park row"
fi

# ── b7 (2): same trace, SDD_HARDEN_TOKEN_CEILING=300000 -> hard park.
B2="$(mkfeat b7-env-park trace-b7-320k.jsonl)"
SDD_HARDEN_TOKEN_CEILING=300000 bash "$STOP" "$B2/wp-harden-high" --dispatch "$DISP_NULL" >/dev/null 2>&1; rcb2=$?
if [ "$rcb2" -eq 3 ] && grep -q '"type":"harden.parked"' "$B2/trace-events.jsonl" 2>/dev/null; then
    ok "b7(2): 320k + SDD_HARDEN_TOKEN_CEILING=300000 -> exit 3 + harden.parked"
else
    bad "b7(2): 320k + SDD_HARDEN_TOKEN_CEILING=300000 -> exit 3 + harden.parked (rc=$rcb2)"
fi

# ── b7 (3): the round cap is the only DEFAULT hard park: 2 rounds, 2k tokens.
B3="$(mkfeat b7-rounds trace-b7-rounds2.jsonl)"
bash "$STOP" "$B3/wp-harden-high" --dispatch "$DISP_NULL" >/dev/null 2>&1; rcb3=$?
PARK_ROW="$(grep '"type":"harden.parked"' "$B3/trace-events.jsonl" 2>/dev/null)"
if [ "$rcb3" -eq 3 ] && printf '%s' "$PARK_ROW" | grep -q 'rounds=2'; then
    ok "b7(3): rounds-2 fixture -> exit 3 + harden.parked reason rounds=2"
else
    bad "b7(3): rounds-2 fixture -> exit 3 + harden.parked reason rounds=2 (rc=$rcb3)"
    printf '%s\n' "$PARK_ROW" | sed 's/^/        /'
fi

# ── b7 (4): 320k against a dispatch file with harden.token_ceiling: 300000.
B4="$(mkfeat b7-config-park trace-b7-320k.jsonl)"
bash "$STOP" "$B4/wp-harden-high" --dispatch "$DISP_300K" >/dev/null 2>&1; rcb4=$?
if [ "$rcb4" -eq 3 ] && grep -q '"type":"harden.parked"' "$B4/trace-events.jsonl" 2>/dev/null; then
    ok "b7(4): 320k + --dispatch harden.token_ceiling=300000 -> exit 3 + harden.parked"
else
    bad "b7(4): 320k + --dispatch harden.token_ceiling=300000 -> exit 3 + harden.parked (rc=$rcb4)"
fi

# ── sabotage: jq masked off PATH -> harden.parked row still written ─────────
cp -r "$FIX/two-rounds-feature" "$WORK/two-rounds-jqmask"
JQ_STUB_DIR="$WORK/jq-stub"; mkdir -p "$JQ_STUB_DIR"
cat > "$JQ_STUB_DIR/jq" <<'EOF'
#!/usr/bin/env bash
echo "jq: masked for test" >&2
exit 127
EOF
chmod +x "$JQ_STUB_DIR/jq"
WP7="$WORK/two-rounds-jqmask/wp-two-rounds"
PATH="$JQ_STUB_DIR:$PATH" bash "$STOP" "$WP7" >"$WORK/hs-jqmask.out" 2>&1; rc7=$?
TRACE7="$WORK/two-rounds-jqmask/trace-events.jsonl"
if [ "$rc7" -eq 3 ] && [ -f "$TRACE7" ] && grep -q '"type":"harden.parked"' "$TRACE7" 2>/dev/null; then
    ok "jq masked off PATH -> harden.parked row still written (python3, no jq dependency)"
else
    bad "jq masked off PATH -> harden.parked row still written (rc=$rc7)"
    [ -f "$TRACE7" ] && sed 's/^/        /' "$TRACE7"
    sed 's/^/        /' "$WORK/hs-jqmask.out"
fi


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
echo "goalforge-harden-stop.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
