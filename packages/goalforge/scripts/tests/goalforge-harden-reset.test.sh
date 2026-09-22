#!/usr/bin/env bash
# goalforge-harden-reset.test.sh — wp-14: harden.reset re-entry (b1-b14).
# All wp-14 cases live here; scripts/tests/goalforge-harden-stop.test.sh is
# restored to its pre-wp-14 (a3baafa) content (b4). Fixtures live under
# packages/goalforge/evals/fixtures/harden-stop/ — a <feature>/<wp>/ tree
# each carrying its own trace-events.jsonl, never inline here except where a
# case constructs a one-off shape at test runtime on a mktemp copy.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STOP="$SD/../goalforge-harden-stop.sh"
EMIT="$SD/../goalforge-trace-emit"
FIX="$SD/../../evals/fixtures/harden-stop"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# mkruling <path> <reason-text> — a decision-ref file shaped like a real
# findings.md ruling section: the attended marker `answered_by: human` plus
# the verbatim --reason locator. Both are required by the b6 content gate.
mkruling() {
    cat > "$1" <<RULINGEOF
# findings

## Human rulings

- $2 — re-enter harden after the recorded park.
  answered_by: human
RULINGEOF
}

# parked_count <trace> -> integer count of harden.parked rows in it.
parked_count() { local n; n="$(grep -c '"type":"harden.parked"' "$1" 2>/dev/null)"; printf '%s' "${n:-0}"; }
reset_count()  { local n; n="$(grep -c '"type":"harden.reset"'  "$1" 2>/dev/null)"; printf '%s' "${n:-0}"; }
ceiling_lines() { local wp_dir="$1"; [ -f "$wp_dir/findings.md" ] && grep -c 'harden: ceiling-breached' "$wp_dir/findings.md" 2>/dev/null || echo 0; }
last_park_ts()  { grep '"type":"harden.parked"' "$1" | tail -1 | grep -oE '"ts":"[^"]+"' | cut -d'"' -f4; }
last_park_seq_of() { grep '"type":"harden.parked"' "$1" | tail -1 | grep -oE '"seq":[0-9]+' | cut -d: -f2; }
epoch_of() { date -u -d "$1" +%s; }

# ═══════════════════════════════════════════════════════════════════════════
# b1: reset clears the park (plain run, no --reset); fail-closed on read-back
# ═══════════════════════════════════════════════════════════════════════════

cp -r "$FIX/reset-cleared-feature" "$WORK/b1-cleared"
WPR1="$WORK/b1-cleared/wp-reset-cleared"
TRACER1="$WORK/b1-cleared/trace-events.jsonl"
PARKED_BEFORE_R1="$(parked_count "$TRACER1")"
OUTR1="$(bash "$STOP" "$WPR1" 2>&1)"; rcr1=$?
if [ "$rcr1" -eq 0 ]; then ok "b1: 2 rounds + harden.reset row -> exit 0 (reset clears the park)"
else bad "b1: 2 rounds + harden.reset row -> exit 0 (rc=$rcr1)"; printf '%s\n' "$OUTR1" | sed 's/^/        /'; fi
if [ ! -f "$WPR1/findings.md" ]; then ok "b1: reset clears the park -> no findings.md ceiling-breached row"
else bad "b1: reset clears the park -> no findings.md ceiling-breached row"; fi
if [ "$(parked_count "$TRACER1")" = "$PARKED_BEFORE_R1" ]; then ok "b1: reset clears the park -> no NEW harden.parked row emitted"
else bad "b1: reset clears the park -> no NEW harden.parked row emitted"; fi

# rows before the reset contribute to neither the round count nor the token
# total: a hard ceiling well below the pre-reset tokens (26000) still passes.
SDD_HARDEN_TOKEN_CEILING=100 bash "$STOP" "$WPR1" >/dev/null 2>&1; rcr1tok=$?
if [ "$rcr1tok" -eq 0 ]; then ok "b1: pre-reset tokens (26000) do not count toward a post-reset hard ceiling of 100"
else bad "b1: pre-reset tokens (26000) do not count toward a post-reset hard ceiling of 100 (rc=$rcr1tok)"; fi
rm -f "$WPR1/findings.md"

# ── b1 known-bad (i): same fixture, harden.reset line deleted -> exit 3 ─────
cp -r "$FIX/reset-cleared-feature" "$WORK/b1-kb1"
TRACER1KB1="$WORK/b1-kb1/trace-events.jsonl"
grep -v '"type":"harden.reset"' "$TRACER1KB1" > "$TRACER1KB1.tmp" && mv "$TRACER1KB1.tmp" "$TRACER1KB1"
bash "$STOP" "$WORK/b1-kb1/wp-reset-cleared" >/dev/null 2>&1; rcr1kb1=$?
if [ "$rcr1kb1" -eq 3 ]; then ok "b1 known-bad(i): harden.reset row deleted (2 rounds, no reset) -> exit 3"
else bad "b1 known-bad(i): harden.reset row deleted -> exit 3 (rc=$rcr1kb1)"; fi

# A fixture-local copy of scripts/ whose goalforge-trace-emit is a stub that
# warns and exits 0 WITHOUT appending — the emitter's real degrade path
# (goalforge-trace-emit:26-31) — used to drive the b1 fail-closed known-bads.
STUBDIR="$WORK/reset-stub-scripts"
mkdir -p "$STUBDIR"
cp "$STOP" "$STUBDIR/goalforge-harden-stop.sh"
cat > "$STUBDIR/goalforge-trace-emit" <<'STUBEOF'
#!/usr/bin/env bash
echo "goalforge-trace-emit: WARN stub — emit suppressed for test" >&2
exit 0
STUBEOF
chmod +x "$STUBDIR/goalforge-trace-emit"
STOP_STUB="$STUBDIR/goalforge-harden-stop.sh"

# ── b1 known-bad (ii): --reset via a stub emitter against a parked WP with
#    NO pre-existing reset row -> exit 2 (read-back sees nothing appended) ──
cp -r "$FIX/reset-decision-ref-feature" "$WORK/b1-kb2"
WPR1KB2="$WORK/b1-kb2/wp-reset-decision-ref"
R1KB2="human ruling 2026-09-13 park-seq=2"
DRKB2="$WPR1KB2/dr-kb2.md"; mkruling "$DRKB2" "$R1KB2"; touch -d "2026-09-13T09:25:00Z" "$DRKB2"
bash "$STOP_STUB" --reset --reason "$R1KB2" --decision-ref "$DRKB2" "$WPR1KB2" >/dev/null 2>&1; rcr1kb2=$?
if [ "$rcr1kb2" -eq 2 ]; then ok "b1 known-bad(ii): --reset via stub emitter (degrade-not-block) -> exit 2"
else bad "b1 known-bad(ii): --reset via stub emitter -> exit 2 (rc=$rcr1kb2)"; fi

# ── b1 known-bad (iii): --reset via the same stub, against a COPY whose trace
#    ALREADY holds a harden.reset row for this WP -> ALSO exit 2 (the
#    pre-existing row sits at/before the pre-call baseline; "exactly one NEW
#    row", never a whole-log count). Rewrite the seq-3 row to THIS call's
#    reason/decision_ref, then append a NEW harden.parked row AFTER it (higher
#    seq, ts older than the decision-ref's mtime) so b6's four admission
#    conditions all pass and the call actually REACHES the emit.
cp -r "$FIX/reset-cleared-feature" "$WORK/b1-kb3"
TRACER1KB3="$WORK/b1-kb3/trace-events.jsonl"
WPR1KB3="$WORK/b1-kb3/wp-reset-cleared"
DRKB3="$WPR1KB3/dr-kb3.md"
R1KB3="human ruling 2026-09-10 park-seq=4"
mkruling "$DRKB3" "$R1KB3"; touch -d "2026-09-10T09:45:00Z" "$DRKB3"
# Rewrite the seq-3 harden.reset row's reason/decision_ref to THIS call's
# own values, so only the read-back BASELINE (not the reason+decision_ref
# match) can discriminate known-bad (iii).
python3 - "$TRACER1KB3" wp-reset-cleared "$R1KB3" "$DRKB3" <<'PY'
import json, sys
trace_path, wp, reason, decision_ref = sys.argv[1:5]
with open(trace_path, encoding="utf-8") as fh:
    lines = fh.read().splitlines()
target = None
for i, line in enumerate(lines):
    if line.strip() and json.loads(line).get("type") == "harden.reset" \
       and json.loads(line).get("wp") == wp:
        target = i
row = json.loads(lines[target])
row["reason"] = reason
row["decision_ref"] = decision_ref
lines[target] = json.dumps(row, separators=(",", ":"))
with open(trace_path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
PY
printf '%s\n' '{"seq":4,"ts":"2026-09-10T09:40:00Z","type":"harden.parked","schema_version":1,"wp":"wp-reset-cleared","reason":"ceiling-breached","rounds":2}' >> "$TRACER1KB3"
bash "$STOP_STUB" --reset --reason "$R1KB3" --decision-ref "$DRKB3" "$WPR1KB3" >"$WORK/kb3.out" 2>&1; rcr1kb3=$?
if [ "$rcr1kb3" -eq 2 ] && grep -q 'read-back failed' "$WORK/kb3.out" \
   && ! grep -q 'not currently parked' "$WORK/kb3.out"; then
    ok "b1 known-bad(iii): --reset via stub emitter, pre-existing reset row -> exit 2 at the READ-BACK"
else
    bad "b1 known-bad(iii): --reset via stub emitter, pre-existing reset row -> exit 2 at the READ-BACK (rc=$rcr1kb3)"
    sed 's/^/        /' "$WORK/kb3.out"
fi

# ═══════════════════════════════════════════════════════════════════════════
# b2: reset does not raise the cap -- 2 NEW rounds after reset -> park
# ═══════════════════════════════════════════════════════════════════════════

cp -r "$FIX/reset-then-two-feature" "$WORK/b2-then-two"
WPR2="$WORK/b2-then-two/wp-reset-then-two"
TRACER2="$WORK/b2-then-two/trace-events.jsonl"
bash "$STOP" "$WPR2" >/dev/null 2>&1; rcr2=$?
if [ "$rcr2" -eq 3 ]; then ok "b2: 1 pre-reset round + 2 post-reset rounds -> exit 3 (cap not raised)"
else bad "b2: 1 pre-reset round + 2 post-reset rounds -> exit 3 (rc=$rcr2)"; fi
if [ -f "$WPR2/findings.md" ] && grep -q 'rounds=2' "$WPR2/findings.md" && ! grep -q 'rounds=4' "$WPR2/findings.md"; then
    ok "b2: findings.md row reads rounds=2 (post-reset only), not rounds=4"
else bad "b2: findings.md row reads rounds=2 (post-reset only), not rounds=4"; fi
# tokens=3000 is the post-reset-only sum (1000+2000); a start-of-log sum
# would read tokens=1000999 (999999+1000+2000... wait see comment) instead.
if [ -f "$WPR2/findings.md" ] && grep -q 'tokens=3000' "$WPR2/findings.md" && ! grep -q 'tokens=1002999' "$WPR2/findings.md"; then
    ok "b2: token sum covers only the two post-reset rounds (3000), pre-reset tokens ignored"
else bad "b2: token sum covers only the two post-reset rounds (3000), pre-reset tokens ignored"; fi
if PARKED_TRACE="$TRACER2" python3 - wp-reset-then-two 2 <<'PY'
import json, os, sys
wp, expected = sys.argv[1], int(sys.argv[2])
rounds = None
for raw in open(os.environ["PARKED_TRACE"], encoding="utf-8"):
    if not raw.strip():
        continue
    row = json.loads(raw)
    if row.get("type") == "harden.parked" and row.get("wp") == wp:
        rounds = row.get("rounds")
sys.exit(0 if rounds == expected else 1)
PY
then
    ok "b2: harden.parked row's parsed rounds field is 2"
else bad "b2: harden.parked row's parsed rounds field is 2"; fi

# ── b2 known-bad: one of the two post-reset rounds removed -> exit 0 ────────
cp -r "$FIX/reset-then-two-feature" "$WORK/b2-kb"
TRACER2KB="$WORK/b2-kb/trace-events.jsonl"
head -n -1 "$TRACER2KB" > "$TRACER2KB.tmp" && mv "$TRACER2KB.tmp" "$TRACER2KB"
bash "$STOP" "$WORK/b2-kb/wp-reset-then-two" >/dev/null 2>&1; rcr2kb=$?
if [ "$rcr2kb" -eq 0 ]; then ok "b2 known-bad: one post-reset round removed (only 1 remains) -> exit 0"
else bad "b2 known-bad: one post-reset round removed -> exit 0 (rc=$rcr2kb)"; fi

# ═══════════════════════════════════════════════════════════════════════════
# b3: a reset row is scoped to its WP -- a sibling's reset/park never
# touches this WP's count, and never un-sticks its park
# ═══════════════════════════════════════════════════════════════════════════

# (1) as shipped: wp-A has no park row of its own -> still exits 3, writes
# exactly one NEW harden.parked row for wp-A.
cp -r "$FIX/reset-other-wp-feature" "$WORK/b3-case1"
WPR3="$WORK/b3-case1/wp-reset-other"
TRACER3="$WORK/b3-case1/trace-events.jsonl"
PARKED_BEFORE_R3="$(parked_count "$TRACER3")"
bash "$STOP" "$WPR3" >/dev/null 2>&1; rcr3=$?
PARKED_AFTER_R3="$(parked_count "$TRACER3")"
if [ "$rcr3" -eq 3 ] && [ "$PARKED_AFTER_R3" = "$((PARKED_BEFORE_R3 + 1))" ]; then
    ok "b3(1): 2 rounds for wp-A + a sibling's honoured reset -> wp-A still exits 3, one new park row"
else
    bad "b3(1): 2 rounds for wp-A + a sibling's honoured reset -> wp-A still exits 3, one new park row (rc=$rcr3)"
fi

# ── b3 known-bad: the reset row's (and park row's) wp changed to match -> 0 ─
cp -r "$FIX/reset-other-wp-feature" "$WORK/b3-kb"
TRACER3KB="$WORK/b3-kb/trace-events.jsonl"
sed -i 's/"wp":"wp-sibling"/"wp":"wp-reset-other"/' "$TRACER3KB"
bash "$STOP" "$WORK/b3-kb/wp-reset-other" >/dev/null 2>&1; rcr3kb=$?
if [ "$rcr3kb" -eq 0 ]; then ok "b3 known-bad: sibling's park+reset rows' wp mutated to match -> exit 0"
else bad "b3 known-bad: sibling's park+reset rows' wp mutated to match -> exit 0 (rc=$rcr3kb)"; fi

# (2) a wp-A harden.parked row INSERTED BEFORE the sibling's reset, seqs
# renumbered (wp-A rounds 0,1; wp-B park 2; wp-A park 3; wp-B reset 4, still
# citing park-seq=2) -> wp-A is ALREADY PARKED; the sibling's later reset
# never un-sticks it.
mkdir -p "$WORK/b3-case2/wp-reset-other"
cp "$FIX/reset-other-wp-feature/wp-reset-other/overview.md" "$WORK/b3-case2/wp-reset-other/overview.md"
cat > "$WORK/b3-case2/trace-events.jsonl" <<'EOF'
{"seq":0,"ts":"2026-09-12T09:00:00Z","type":"harden.round","schema_version":1,"wp":"wp-reset-other","round":1,"tokens":5000}
{"seq":1,"ts":"2026-09-12T09:10:00Z","type":"harden.round","schema_version":1,"wp":"wp-reset-other","round":2,"tokens":6000}
{"seq":2,"ts":"2026-09-12T09:15:00Z","type":"harden.parked","schema_version":1,"wp":"wp-sibling","reason":"ceiling-breached","rounds":2}
{"seq":3,"ts":"2026-09-12T09:17:00Z","type":"harden.parked","schema_version":1,"wp":"wp-reset-other","reason":"ceiling-breached","rounds":2}
{"seq":4,"ts":"2026-09-12T09:20:00Z","type":"harden.reset","schema_version":1,"wp":"wp-sibling","reason":"human ruling 2026-09-12 park-seq=2","rounds_cleared":2,"decision_ref":"findings.md"}
EOF
WPR3C2="$WORK/b3-case2/wp-reset-other"
TRACER3C2="$WORK/b3-case2/trace-events.jsonl"
PARKED_BEFORE_R3C2="$(parked_count "$TRACER3C2")"
OUTR3C2="$(bash "$STOP" "$WPR3C2" 2>&1)"; rcr3c2=$?
PARKED_AFTER_R3C2="$(parked_count "$TRACER3C2")"
if [ "$rcr3c2" -eq 3 ] && [ "$PARKED_AFTER_R3C2" = "$PARKED_BEFORE_R3C2" ] \
   && printf '%s' "$OUTR3C2" | grep -q 'already parked (park-seq=3)'; then
    ok "b3(2): a sibling's later reset never un-sticks wp-A's own park -> already parked (park-seq=3)"
else
    bad "b3(2): a sibling's later reset never un-sticks wp-A's own park (rc=$rcr3c2)"
    printf '%s\n' "$OUTR3C2" | sed 's/^/        /'
fi

# ═══════════════════════════════════════════════════════════════════════════
# b5: harden.reset in the emitter's schema (valid emits, missing field rejected)
# ═══════════════════════════════════════════════════════════════════════════

B5DIR="$WORK/b5-emit"
mkdir -p "$B5DIR"
"$EMIT" --feature-dir "$B5DIR" \
  --event '{"type":"harden.reset","wp":"wp-b5","reason":"human ruling test park-seq=1","rounds_cleared":2,"decision_ref":"findings.md"}' \
  >/dev/null 2>&1; rcb5valid=$?
if [ "$rcb5valid" -eq 0 ] && grep -q '"type":"harden.reset"' "$B5DIR/trace-events.jsonl" 2>/dev/null; then
    ok "b5: well-formed harden.reset event emits through goalforge-trace-emit, exit 0"
else bad "b5: well-formed harden.reset event emits through goalforge-trace-emit, exit 0 (rc=$rcb5valid)"; fi
B5BEFORE="$(wc -l < "$B5DIR/trace-events.jsonl" 2>/dev/null || echo 0)"
"$EMIT" --feature-dir "$B5DIR" \
  --event '{"type":"harden.reset","wp":"wp-b5","reason":"human ruling test","decision_ref":"findings.md"}' \
  >"$WORK/b5-missing.out" 2>&1; rcb5missing=$?
B5AFTER="$(wc -l < "$B5DIR/trace-events.jsonl" 2>/dev/null || echo 0)"
if [ "$rcb5missing" -eq 2 ] && [ "$B5BEFORE" = "$B5AFTER" ]; then
    ok "b5: harden.reset missing rounds_cleared -> exit 2, log byte-unchanged"
else bad "b5: harden.reset missing rounds_cleared -> exit 2, log byte-unchanged (rc=$rcb5missing)"; fi

B5BEFORE2="$(wc -l < "$B5DIR/trace-events.jsonl" 2>/dev/null || echo 0)"
"$EMIT" --feature-dir "$B5DIR" \
  --event '{"type":"harden.reset","wp":"wp-b5","reason":"human ruling test","rounds_cleared":2}' \
  >"$WORK/b5-nodref.out" 2>&1; rcb5nodref=$?
B5AFTER2="$(wc -l < "$B5DIR/trace-events.jsonl" 2>/dev/null || echo 0)"
if [ "$rcb5nodref" -eq 2 ] && [ "$B5BEFORE2" = "$B5AFTER2" ]; then
    ok "b5: harden.reset missing decision_ref -> exit 2, log byte-unchanged"
else bad "b5: harden.reset missing decision_ref -> exit 2, log byte-unchanged (rc=$rcb5nodref)"; fi

SCHEMA_DOC="$SD/../../references/trace-events.md"
RUNSH="$SD/../../evals/trace-substrate/run.sh"
if python3 - "$SCHEMA_DOC" "$RUNSH" <<'PY'
import json, re, sys
doc_path, runsh_path = sys.argv[1], sys.argv[2]
lines = open(doc_path, encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(lines) if l.strip() == "```json") + 1
end = next(j for j in range(start, len(lines)) if lines[j].strip() == "```")
schema = json.loads("\n".join(lines[start:end]))
branch_count = len(schema.get("oneOf", []))
runsh = open(runsh_path, encoding="utf-8").read()
m = re.search(r"== (\d+), \"expected \d+ schema branches\"", runsh)
if not m:
    sys.exit(1)
pinned = int(m.group(1))
sys.exit(0 if branch_count == pinned else 1)
PY
then
    ok "b5: embedded schema oneOf branch count matches evals/trace-substrate/run.sh's pin"
else bad "b5: embedded schema oneOf branch count matches evals/trace-substrate/run.sh's pin"; fi

# ═══════════════════════════════════════════════════════════════════════════
# b6: --reset admission = FOUR conjunctive conditions -- (a) content gate,
# (b) freshness, (c) currently-parked, (d) park binding (park-seq + scope)
# ═══════════════════════════════════════════════════════════════════════════

cp -r "$FIX/reset-decision-ref-feature" "$WORK/b6"
WPR6="$WORK/b6/wp-reset-decision-ref"
TRACER6="$WORK/b6/trace-events.jsonl"
R6="human ruling 2026-09-13 park-seq=2"
PARKED_EPOCH="$(epoch_of '2026-09-13T09:20:00Z')"

mkruling_at() { mkruling "$1" "$2"; touch -d "@$3" "$1"; }

DR6_FRESH="$WPR6/dr6-fresh.md";   mkruling_at "$DR6_FRESH" "$R6" "$((PARKED_EPOCH + 60))"
DR6_EQUAL="$WPR6/dr6-equal.md";   mkruling_at "$DR6_EQUAL" "$R6" "$PARKED_EPOCH"
DR6_STALE="$WPR6/dr6-stale.md";   mkruling_at "$DR6_STALE" "$R6" "$((PARKED_EPOCH - 60))"
DR6_MISSING="$WPR6/dr6-missing.md"   # deliberately never created

# candidate (4): the chain's OWN findings.md bookkeeping — no human marks.
DR6_CHAIN="$WPR6/dr6-chain-park.md"
printf '%s\n' '# findings' '' '## Harden Stop' '' '- harden: ceiling-breached, rounds=2 (tokens=21000, ceiling=none)' > "$DR6_CHAIN"
touch -d "@$((PARKED_EPOCH + 60))" "$DR6_CHAIN"

# candidate (6) MARKER-ONLY / (7) REASON-ONLY
DR6_MARKERONLY="$WPR6/dr6-marker-only.md"
printf '%s\n' 'answered_by: human' > "$DR6_MARKERONLY"; touch -d "@$((PARKED_EPOCH + 60))" "$DR6_MARKERONLY"
DR6_REASONONLY="$WPR6/dr6-reason-only.md"
printf '%s\n' "$R6" > "$DR6_REASONONLY"; touch -d "@$((PARKED_EPOCH + 60))" "$DR6_REASONONLY"

# candidate (8) OUTSIDE the WP dir / (9) SYMLINK inside pointing outside
DR6_OUTSIDE="$WORK/dr6-outside.md"; mkruling_at "$DR6_OUTSIDE" "$R6" "$((PARKED_EPOCH + 60))"
DR6_SYMLINK="$WPR6/dr6-symlink.md"; ln -s "$DR6_OUTSIDE" "$DR6_SYMLINK"

# reason variants (10)-(14), each paired with a candidate-(1)-shaped file
# containing that exact reason.
R6_NOTOKEN="human ruling 2026-09-13, no park cited"
DR6_NOTOKEN="$WPR6/dr6-notoken.md"; mkruling_at "$DR6_NOTOKEN" "$R6_NOTOKEN" "$((PARKED_EPOCH + 60))"
R6_WRONGSEQ="human ruling 2026-09-13 park-seq=1"
DR6_WRONGSEQ="$WPR6/dr6-wrongseq.md"; mkruling_at "$DR6_WRONGSEQ" "$R6_WRONGSEQ" "$((PARKED_EPOCH + 60))"
R6_EXTRADIGIT="human ruling 2026-09-13 park-seq=20"
DR6_EXTRADIGIT="$WPR6/dr6-extradigit.md"; mkruling_at "$DR6_EXTRADIGIT" "$R6_EXTRADIGIT" "$((PARKED_EPOCH + 60))"

parked_count6() { parked_count "$TRACER6"; }
findings6() { ceiling_lines "$WPR6"; }
PRE_PARKED6="$(parked_count6)"
PRE_FINDINGS6="$(findings6)"

b6_block_case() {
    local label="$1"; shift
    local pre_hash post_hash
    pre_hash="$(md5sum "$TRACER6" | awk '{print $1}')"
    bash "$STOP" "$@" >"$WORK/b6-$label.out" 2>&1
    local rc=$?
    post_hash="$(md5sum "$TRACER6" | awk '{print $1}')"
    if [ "$rc" -eq 2 ] && [ -s "$WORK/b6-$label.out" ] && [ "$pre_hash" = "$post_hash" ] \
       && [ "$(parked_count6)" = "$PRE_PARKED6" ] && [ "$(findings6)" = "$PRE_FINDINGS6" ]; then
        ok "b6: $label -> exit 2, trace byte-identical, no park-path side effects"
    else
        bad "b6: $label -> exit 2, trace byte-identical, no park-path side effects (rc=$rc)"
        sed 's/^/        /' "$WORK/b6-$label.out"
    fi
}
b6_block_case "equal-second"    --reset --reason "$R6" --decision-ref "$DR6_EQUAL"       "$WPR6"
b6_block_case "stale"           --reset --reason "$R6" --decision-ref "$DR6_STALE"       "$WPR6"
b6_block_case "missing-path"    --reset --reason "$R6" --decision-ref "$DR6_MISSING"     "$WPR6"
b6_block_case "omitted-flag"    --reset --reason "$R6"                                   "$WPR6"
b6_block_case "chain-park-only" --reset --reason "$R6" --decision-ref "$DR6_CHAIN"       "$WPR6"
b6_block_case "marker-only"     --reset --reason "$R6" --decision-ref "$DR6_MARKERONLY"  "$WPR6"
b6_block_case "reason-only"     --reset --reason "$R6" --decision-ref "$DR6_REASONONLY"  "$WPR6"
b6_block_case "outside-wp"      --reset --reason "$R6" --decision-ref "$DR6_OUTSIDE"     "$WPR6"
b6_block_case "symlink-escape"  --reset --reason "$R6" --decision-ref "$DR6_SYMLINK"     "$WPR6"
b6_block_case "no-park-seq"     --reset --reason "$R6_NOTOKEN"    --decision-ref "$DR6_NOTOKEN"    "$WPR6"
b6_block_case "wrong-park-seq"  --reset --reason "$R6_WRONGSEQ"   --decision-ref "$DR6_WRONGSEQ"   "$WPR6"
b6_block_case "extra-digit"     --reset --reason "$R6_EXTRADIGIT" --decision-ref "$DR6_EXTRADIGIT" "$WPR6"
b6_block_case "empty-reason"    --reset --reason ""  --decision-ref "$DR6_FRESH"         "$WPR6"
b6_block_case "whitespace-reason" --reset --reason " " --decision-ref "$DR6_FRESH"       "$WPR6"

# allow case: fresh decision-ref carrying the marker, the reason locator and
# the correct park-seq.
bash "$STOP" --reset --reason "$R6" --decision-ref "$DR6_FRESH" "$WPR6" >"$WORK/b6-fresh.out" 2>&1
rc_b6_fresh=$?
new_reset_rows6="$(reset_count "$TRACER6")"
if [ "$rc_b6_fresh" -eq 0 ] && [ "$new_reset_rows6" = "1" ] \
   && [ "$(parked_count6)" = "$PRE_PARKED6" ] && [ "$(findings6)" = "$PRE_FINDINGS6" ]; then
    ok "b6: fresh decision-ref (correct park-seq) -> exit 0, exactly one new harden.reset row, no park-path side effects"
else
    bad "b6: fresh decision-ref -> exit 0, exactly one new harden.reset row (rc=$rc_b6_fresh)"
    sed 's/^/        /' "$WORK/b6-fresh.out"
fi
if grep '"type":"harden.reset"' "$TRACER6" | grep -q "\"decision_ref\":\"$DR6_FRESH\""; then
    ok "b6: the emitted harden.reset row carries decision_ref (the path as given)"
else
    bad "b6: the emitted harden.reset row carries decision_ref (the path as given)"
fi

# repeat of the admitted candidate with no new park in between -> exit 2
# (condition (c), the gate-B B2 reproduction).
b6_block_case "repeat-after-admission" --reset --reason "$R6" --decision-ref "$DR6_FRESH" "$WPR6"
if grep -q 'not currently parked' "$WORK/b6-repeat-after-admission.out"; then
    ok "b6: the repeat reset is refused by the currently-parked gate by name"
else
    bad "b6: the repeat reset is refused by the currently-parked gate by name"
    sed 's/^/        /' "$WORK/b6-repeat-after-admission.out"
fi

# --dispatch alongside --reset, and --reason/--decision-ref without --reset.
DFIX="$SD/fixtures/dispatch"
bash "$STOP" --reset --reason "$R6" --decision-ref "$DR6_FRESH" --dispatch "$DFIX/dispatch-default.yaml" "$WPR6" >"$WORK/b6-dispatch.out" 2>&1; rc_b6_disp=$?
if [ "$rc_b6_disp" -eq 2 ] && grep -q 'usage:' "$WORK/b6-dispatch.out" \
   && grep -q '^goalforge-harden-stop: --reset refused — --dispatch is not valid with --reset$' "$WORK/b6-dispatch.out"; then
    ok "b6: --dispatch with --reset -> exit 2 with usage and the --reset refused prefix"
else bad "b6: --dispatch with --reset -> exit 2 with usage (rc=$rc_b6_disp)"; sed 's/^/        /' "$WORK/b6-dispatch.out"; fi

bash "$STOP" --reason "$R6" "$WPR6" >"$WORK/b6-reason-noreset.out" 2>&1; rc_b6_rnr=$?
bash "$STOP" --decision-ref "$DR6_FRESH" "$WPR6" >"$WORK/b6-dref-noreset.out" 2>&1; rc_b6_dnr=$?
if [ "$rc_b6_rnr" -eq 2 ] && [ "$rc_b6_dnr" -eq 2 ] \
   && grep -q 'require --reset' "$WORK/b6-reason-noreset.out" \
   && grep -q 'require --reset' "$WORK/b6-dref-noreset.out"; then
    ok "b6: --reason/--decision-ref without --reset -> exit 2 with usage"
else
    bad "b6: --reason/--decision-ref without --reset -> exit 2 with usage (rc=$rc_b6_rnr/$rc_b6_dnr)"
fi

# ── gate-B lap-2 attack repros atk1-atk3 ─────────────────────────────────────

# atk1: an older unrelated `answered_by: human` line already in findings.md,
# a park appended after it, --reason "ceiling-breached" (the chain's own park
# text, no park-seq token) -> must be refused.
cp -r "$FIX/two-rounds-feature" "$WORK/atk1"
WPATK1="$WORK/atk1/wp-two-rounds"
printf '%s\n' '# findings' '' '## Old ruling' '' '- an unrelated earlier decision.' '  answered_by: human' > "$WPATK1/findings.md"
bash "$STOP" "$WPATK1" >/dev/null 2>&1   # park; appends a NEW findings.md line
touch -d "@$(( $(epoch_of "$(last_park_ts "$WORK/atk1/trace-events.jsonl")") + 60 ))" "$WPATK1/findings.md"
bash "$STOP" --reset --reason "ceiling-breached" --decision-ref "$WPATK1/findings.md" "$WPATK1" >"$WORK/atk1.out" 2>&1; rc_atk1=$?
if [ "$rc_atk1" -eq 2 ]; then ok "b6: atk1 (chain park-row text, no park-seq, an old unrelated human marker) -> exit 2"
else bad "b6: atk1 -> exit 2 (rc=$rc_atk1)"; sed 's/^/        /' "$WORK/atk1.out"; fi

# atk2: the SAME ruling re-admitted against a SECOND, LATER park -> must be
# refused (park-seq binding). Validated in full detail under b7 below too.
cp -r "$FIX/reset-decision-ref-feature" "$WORK/atk2"
WPATK2="$WORK/atk2/wp-reset-decision-ref"
TRACEATK2="$WORK/atk2/trace-events.jsonl"
RATK2="R-1 park-seq=2"
DRATK2="$WPATK2/dr-atk2.md"; mkruling_at "$DRATK2" "$RATK2" "$((PARKED_EPOCH + 60))"
bash "$STOP" --reset --reason "$RATK2" --decision-ref "$DRATK2" "$WPATK2" >/dev/null 2>&1
"$EMIT" --feature-dir "$WORK/atk2" --event "{\"type\":\"harden.round\",\"wp\":\"wp-reset-decision-ref\",\"round\":1,\"tokens\":1000}" >/dev/null
"$EMIT" --feature-dir "$WORK/atk2" --event "{\"type\":\"harden.round\",\"wp\":\"wp-reset-decision-ref\",\"round\":2,\"tokens\":2000}" >/dev/null
bash "$STOP" "$WPATK2" >/dev/null 2>&1   # parks again at a NEW, higher seq
NEWPARKTS_ATK2="$(last_park_ts "$TRACEATK2")"
touch -d "@$(( $(epoch_of "$NEWPARKTS_ATK2") + 60 ))" "$DRATK2"
bash "$STOP" --reset --reason "$RATK2" --decision-ref "$DRATK2" "$WPATK2" >"$WORK/atk2.out" 2>&1; rc_atk2=$?
if [ "$rc_atk2" -eq 2 ] && grep -q 'park-seq' "$WORK/atk2.out" && [ "$(reset_count "$TRACEATK2")" = "1" ]; then
    ok "b6: atk2 (the same ruling reused against a second, later park) -> exit 2, park-seq refusal"
else
    bad "b6: atk2 -> exit 2, park-seq refusal (rc=$rc_atk2)"
    sed 's/^/        /' "$WORK/atk2.out"
fi

# atk3: a fresh copy of harden/SKILL.md (it contains `answered_by: human`) as
# --decision-ref with --reason " " -> exit 2, both outside and inside the WP.
cp -r "$FIX/reset-decision-ref-feature" "$WORK/atk3"
WPATK3="$WORK/atk3/wp-reset-decision-ref"
cp "$SD/../../harden/SKILL.md" "$WORK/atk3-skill-outside.md"; touch -d "@$((PARKED_EPOCH + 60))" "$WORK/atk3-skill-outside.md"
cp "$SD/../../harden/SKILL.md" "$WPATK3/atk3-skill-inside.md"; touch -d "@$((PARKED_EPOCH + 60))" "$WPATK3/atk3-skill-inside.md"
bash "$STOP" --reset --reason " " --decision-ref "$WORK/atk3-skill-outside.md" "$WPATK3" >"$WORK/atk3-outside.out" 2>&1; rc_atk3o=$?
bash "$STOP" --reset --reason " " --decision-ref "$WPATK3/atk3-skill-inside.md" "$WPATK3" >"$WORK/atk3-inside.out" 2>&1; rc_atk3i=$?
if [ "$rc_atk3o" -eq 2 ] && [ "$rc_atk3i" -eq 2 ]; then
    ok "b6: atk3 (SKILL.md as decision-ref, whitespace reason) -> exit 2 outside and inside the WP dir"
else
    bad "b6: atk3 -> exit 2 outside and inside the WP dir (rc=$rc_atk3o/$rc_atk3i)"
fi

# (verify lap-3 fix-forward item 4) --reset against an UNPARKED at-cap WP
# (two-rounds-feature: two harden.round rows, no harden.parked row at all) --
# admission's currently-parked gate has no park row to find, so it refuses
# before run()'s park path is ever reachable: exit 2, no new harden.parked
# row, no findings.md written, even though the WP sits at the round cap.
cp -r "$FIX/two-rounds-feature" "$WORK/b6-unparked"
WPR6U="$WORK/b6-unparked/wp-two-rounds"
TRACER6U="$WORK/b6-unparked/trace-events.jsonl"
R6U="human ruling 2026-09-24 park-seq=2"
DR6U="$WPR6U/dr6u.md"; mkruling "$DR6U" "$R6U"
PRE_PARKED6U="$(parked_count "$TRACER6U")"
bash "$STOP" --reset --reason "$R6U" --decision-ref "$DR6U" "$WPR6U" >"$WORK/b6-unparked.out" 2>&1; rc6u=$?
POST_PARKED6U="$(parked_count "$TRACER6U")"
if [ "$rc6u" -eq 2 ] && [ "$POST_PARKED6U" = "$PRE_PARKED6U" ] && [ ! -f "$WPR6U/findings.md" ]; then
    ok "b6: --reset against an unparked at-cap WP (two-rounds-feature) -> exit 2, no new harden.parked row, no findings.md"
else
    bad "b6: --reset against an unparked at-cap WP -> exit 2, no new park, no findings.md (rc=$rc6u, parked $PRE_PARKED6U->$POST_PARKED6U)"
    sed 's/^/        /' "$WORK/b6-unparked.out"
fi
# stderr prefix asserted below under b9 (check_prefix is defined there).

# ═══════════════════════════════════════════════════════════════════════════
# b7: the CONSUMER honours a harden.reset row only when it directly follows
# a same-WP harden.parked row and cites that park's seq (M1)
# ═══════════════════════════════════════════════════════════════════════════

# (1) as shipped -> exit 0 (already exercised by b1 above; re-asserted here
# under the b7 label for completeness).
cp -r "$FIX/reset-cleared-feature" "$WORK/b7-case1"
bash "$STOP" "$WORK/b7-case1/wp-reset-cleared" >/dev/null 2>&1; rc_b7_1=$?
if [ "$rc_b7_1" -eq 0 ]; then ok "b7(1): reset directly follows its own park, cites its seq -> exit 0"
else bad "b7(1): reset directly follows its own park, cites its seq -> exit 0 (rc=$rc_b7_1)"; fi

# followup_reset <feature-dir> <wp-dir> <wp> -- after a plain run re-parks a
# WP, mint an admissible --reset citing the NEW park's seq and assert rc 0
# (an unhonoured reset never wedges the WP for good).
followup_reset() {
    local feat="$1" wp_dir="$2" wp="$3" label="$4"
    local trace="$feat/trace-events.jsonl"
    local pseq pts dr r
    pseq="$(last_park_seq_of "$trace")"
    pts="$(last_park_ts "$trace")"
    r="follow-up ruling for $label park-seq=$pseq"
    dr="$wp_dir/followup-$label.md"
    mkruling_at "$dr" "$r" "$(( $(epoch_of "$pts") + 60 ))"
    bash "$STOP" --reset --reason "$r" --decision-ref "$dr" "$wp_dir" >"$WORK/followup-$label.out" 2>&1
    local rc=$?
    if [ "$rc" -eq 0 ]; then ok "b7($label): follow-up --reset citing the NEW park-seq=$pseq -> exit 0 (never permanently wedged)"
    else bad "b7($label): follow-up --reset -> exit 0 (rc=$rc)"; sed 's/^/        /' "$WORK/followup-$label.out"; fi
}

# (2) reset row's reason rewritten to cite the WRONG park-seq -> unhonoured:
# plain run exits 3, writes exactly ONE new harden.parked row, PARK stderr
# (not "already parked"), and a follow-up --reset succeeds.
cp -r "$FIX/reset-cleared-feature" "$WORK/b7-case2"
TRACE72="$WORK/b7-case2/trace-events.jsonl"
WP72="$WORK/b7-case2/wp-reset-cleared"
sed -i 's/park-seq=2/park-seq=1/' "$TRACE72"
PRE72="$(parked_count "$TRACE72")"
OUT72="$(bash "$STOP" "$WP72" 2>&1)"; rc72=$?
POST72="$(parked_count "$TRACE72")"
if [ "$rc72" -eq 3 ] && [ "$POST72" = "$((PRE72 + 1))" ] \
   && printf '%s' "$OUT72" | grep -q 'PARK — ' && ! printf '%s' "$OUT72" | grep -q 'already parked'; then
    ok "b7(2): reset citing the WRONG park-seq is unhonoured -> exit 3, one new park, PARK stderr (not already-parked)"
else
    bad "b7(2): reset citing the WRONG park-seq is unhonoured (rc=$rc72)"
    printf '%s\n' "$OUT72" | sed 's/^/        /'
fi
followup_reset "$WORK/b7-case2" "$WP72" wp-reset-cleared case2

# (3) the harden.parked row deleted, so the reset follows no park -> exit 3.
cp -r "$FIX/reset-cleared-feature" "$WORK/b7-case3"
TRACE73="$WORK/b7-case3/trace-events.jsonl"
grep -v '"type":"harden.parked"' "$TRACE73" > "$TRACE73.tmp" && mv "$TRACE73.tmp" "$TRACE73"
bash "$STOP" "$WORK/b7-case3/wp-reset-cleared" >/dev/null 2>&1; rc73=$?
if [ "$rc73" -eq 3 ]; then ok "b7(3): reset follows no park -> exit 3"
else bad "b7(3): reset follows no park -> exit 3 (rc=$rc73)"; fi

# (4) atk4: a harden.reset row emitted DIRECTLY (bypassing --reset admission)
# with a nonexistent decision_ref and a reason lacking park-seq -> unhonoured.
cp -r "$FIX/reset-decision-ref-feature" "$WORK/b7-case4"
FEAT74="$WORK/b7-case4"
WP74="$FEAT74/wp-reset-decision-ref"
TRACE74="$FEAT74/trace-events.jsonl"
"$EMIT" --feature-dir "$FEAT74" \
  --event '{"type":"harden.reset","wp":"wp-reset-decision-ref","reason":"r","rounds_cleared":2,"decision_ref":"/nonexistent"}' >/dev/null 2>&1
PRE74="$(parked_count "$TRACE74")"
OUT74="$(bash "$STOP" "$WP74" 2>&1)"; rc74=$?
POST74="$(parked_count "$TRACE74")"
if [ "$rc74" -eq 3 ] && [ "$POST74" = "$((PRE74 + 1))" ] \
   && printf '%s' "$OUT74" | grep -q 'PARK — ' && ! printf '%s' "$OUT74" | grep -q 'already parked'; then
    ok "b7(4)/atk4: a directly-emitted reset with no park-seq is unhonoured -> exit 3, one new park"
else
    bad "b7(4)/atk4: a directly-emitted reset is unhonoured (rc=$rc74)"
    printf '%s\n' "$OUT74" | sed 's/^/        /'
fi
followup_reset "$FEAT74" "$WP74" wp-reset-decision-ref case4

# (5) an honoured reset, two rounds, then a SECOND reset ALSO citing the
# FIRST park's seq (not preceded by a new park) -> the second is unhonoured.
cp -r "$FIX/reset-decision-ref-feature" "$WORK/b7-case5"
FEAT75="$WORK/b7-case5"
WP75="$FEAT75/wp-reset-decision-ref"
TRACE75="$FEAT75/trace-events.jsonl"
"$EMIT" --feature-dir "$FEAT75" --event '{"type":"harden.reset","wp":"wp-reset-decision-ref","reason":"r1 park-seq=2","rounds_cleared":2,"decision_ref":"findings.md"}' >/dev/null 2>&1
"$EMIT" --feature-dir "$FEAT75" --event '{"type":"harden.round","wp":"wp-reset-decision-ref","round":1,"tokens":10}' >/dev/null 2>&1
"$EMIT" --feature-dir "$FEAT75" --event '{"type":"harden.round","wp":"wp-reset-decision-ref","round":2,"tokens":20}' >/dev/null 2>&1
"$EMIT" --feature-dir "$FEAT75" --event '{"type":"harden.reset","wp":"wp-reset-decision-ref","reason":"r2 park-seq=2","rounds_cleared":2,"decision_ref":"findings.md"}' >/dev/null 2>&1
PRE75="$(parked_count "$TRACE75")"
OUT75="$(bash "$STOP" "$WP75" 2>&1)"; rc75=$?
POST75="$(parked_count "$TRACE75")"
if [ "$rc75" -eq 3 ] && [ "$POST75" = "$((PRE75 + 1))" ] \
   && printf '%s' "$OUT75" | grep -q 'PARK — ' && ! printf '%s' "$OUT75" | grep -q 'already parked'; then
    ok "b7(5): a second reset not preceded by a new park is unhonoured -> exit 3, one new park"
else
    bad "b7(5): a second reset not preceded by a new park is unhonoured (rc=$rc75)"
    printf '%s\n' "$OUT75" | sed 's/^/        /'
fi
followup_reset "$FEAT75" "$WP75" wp-reset-decision-ref case5

# (6) an honoured reset whose decision_ref names a file that does not exist
# -> the CONSUMER does not re-validate decision_ref -> exit 0.
cp -r "$FIX/reset-cleared-feature" "$WORK/b7-case6"
TRACE76="$WORK/b7-case6/trace-events.jsonl"
sed -i 's#"decision_ref":"findings.md"#"decision_ref":"/does/not/exist"#' "$TRACE76"
bash "$STOP" "$WORK/b7-case6/wp-reset-cleared" >/dev/null 2>&1; rc76=$?
if [ "$rc76" -eq 0 ]; then ok "b7(6): decision_ref not re-read by the consumer (nonexistent path, honoured reset) -> exit 0"
else bad "b7(6): decision_ref not re-read by the consumer -> exit 0 (rc=$rc76)"; fi

# (7) two rows inserted BETWEEN the park and the reset -- a sibling-WP round
# and a same-WP harden.warn -- seqs renumbered, reset still citing park-seq=2.
mkdir -p "$WORK/b7-case7/wp-reset-cleared"
cp "$FIX/reset-cleared-feature/wp-reset-cleared/overview.md" "$WORK/b7-case7/wp-reset-cleared/overview.md"
cat > "$WORK/b7-case7/trace-events.jsonl" <<'EOF'
{"seq":0,"ts":"2026-09-10T09:00:00Z","type":"harden.round","schema_version":1,"wp":"wp-reset-cleared","round":1,"tokens":12000}
{"seq":1,"ts":"2026-09-10T09:10:00Z","type":"harden.round","schema_version":1,"wp":"wp-reset-cleared","round":2,"tokens":14000}
{"seq":2,"ts":"2026-09-10T09:20:00Z","type":"harden.parked","schema_version":1,"wp":"wp-reset-cleared","reason":"ceiling-breached","rounds":2}
{"seq":3,"ts":"2026-09-10T09:22:00Z","type":"harden.round","schema_version":1,"wp":"wp-sibling","round":1,"tokens":999}
{"seq":4,"ts":"2026-09-10T09:24:00Z","type":"harden.warn","schema_version":1,"wp":"wp-reset-cleared","reason":"tokens-above-soft-threshold","tokens":70000,"threshold":60000}
{"seq":5,"ts":"2026-09-10T09:30:00Z","type":"harden.reset","schema_version":1,"wp":"wp-reset-cleared","reason":"human ruling 2026-09-10 park-seq=2","rounds_cleared":2,"decision_ref":"findings.md"}
EOF
bash "$STOP" "$WORK/b7-case7/wp-reset-cleared" >/dev/null 2>&1; rc77=$?
if [ "$rc77" -eq 0 ]; then ok "b7(7): a sibling round + a same-WP harden.warn between park and reset never break the binding -> exit 0"
else bad "b7(7): interleaved non-park/reset rows never break the binding -> exit 0 (rc=$rc77)"; fi

# (8) (verify lap-3 fix-forward item 3) a directly-emitted reset citing
# park-seq=<P.seq><digit> -- park seq 2, reason citing "park-seq=20" -- must
# NOT be honoured by a bare substring match on "park-seq=2". Strip the
# fixture's own (correctly-bound) reset row first so the digit-suffixed one
# is the only same-WP row directly following the park.
cp -r "$FIX/reset-cleared-feature" "$WORK/b7-case8"
FEAT78="$WORK/b7-case8"
WP78="$FEAT78/wp-reset-cleared"
TRACE78="$FEAT78/trace-events.jsonl"
grep -v '"type":"harden.reset"' "$TRACE78" > "$TRACE78.tmp" && mv "$TRACE78.tmp" "$TRACE78"
"$EMIT" --feature-dir "$FEAT78" \
  --event '{"type":"harden.reset","wp":"wp-reset-cleared","reason":"human ruling park-seq=20","rounds_cleared":2,"decision_ref":"findings.md"}' >/dev/null 2>&1
PRE78="$(parked_count "$TRACE78")"
OUT78="$(bash "$STOP" "$WP78" 2>&1)"; rc78=$?
POST78="$(parked_count "$TRACE78")"
if [ "$rc78" -eq 3 ] && [ "$POST78" = "$((PRE78 + 1))" ] \
   && printf '%s' "$OUT78" | grep -q 'PARK — ' && ! printf '%s' "$OUT78" | grep -q 'already parked'; then
    ok "b7(8): a directly-emitted reset citing park-seq=<P.seq><digit> (park-seq=20 for park 2) is unhonoured -> exit 3, one new park"
else
    bad "b7(8): a directly-emitted reset citing park-seq=<P.seq><digit> is unhonoured -> exit 3 (rc=$rc78)"
    printf '%s\n' "$OUT78" | sed 's/^/        /'
fi
followup_reset "$FEAT78" "$WP78" wp-reset-cleared case8

# ═══════════════════════════════════════════════════════════════════════════
# b8: one exclusive flock spans admission, emit and read-back (L1)
# ═══════════════════════════════════════════════════════════════════════════

REAL_EMIT_ABS="$(cd "$(dirname "$EMIT")" && pwd)/$(basename "$EMIT")"

# (1) four identical --reset invocations launched concurrently -> exactly
# one exits 0, the other three exit 2 "not currently parked", one new row.
cp -r "$FIX/reset-decision-ref-feature" "$WORK/b8-concurrent"
WP81="$WORK/b8-concurrent/wp-reset-decision-ref"
TRACE81="$WORK/b8-concurrent/trace-events.jsonl"
R81="human ruling 2026-09-13 park-seq=2"
DR81="$WP81/dr81.md"; mkruling_at "$DR81" "$R81" "$((PARKED_EPOCH + 60))"
for i in 1 2 3 4; do
    ( bash "$STOP" --reset --reason "$R81" --decision-ref "$DR81" "$WP81" >"$WORK/b8-c$i.out" 2>&1; echo $? > "$WORK/b8-c$i.rc" ) &
done
wait
rcs="$(cat "$WORK"/b8-c*.rc | sort | tr '\n' ' ')"
if [ "$rcs" = "0 2 2 2 " ] && [ "$(reset_count "$TRACE81")" = "1" ]; then
    ok "b8(1): four concurrent --reset calls -> exactly one exit 0, three exit 2, one new row"
else
    bad "b8(1): four concurrent --reset calls -> exactly one exit 0, three exit 2, one new row (rcs=$rcs, rows=$(reset_count "$TRACE81"))"
fi
if grep -l 'not currently parked' "$WORK"/b8-c*.out | wc -l | grep -q '^3$'; then
    ok "b8(1): the three losers are refused under the currently-parked gate by name"
else bad "b8(1): the three losers are refused under the currently-parked gate by name"; fi

# (2) a wrapper emitter that probes the reset lock non-blocking BEFORE
# delegating to the real emitter -> finds it HELD (do_reset holds it across
# the emit).
WRAP2="$WORK/wrap2-scripts"; mkdir -p "$WRAP2"
cp "$STOP" "$WRAP2/goalforge-harden-stop.sh"
cat > "$WRAP2/goalforge-trace-emit" <<WRAPEOF
#!/usr/bin/env bash
FD=""
prev=""
for a in "\$@"; do
    if [ "\$prev" = "--feature-dir" ]; then FD="\$a"; fi
    prev="\$a"
done
exec 9>"\$FD/trace-events.reset.lock"
if flock -n 9; then
    echo FREE >> "$WORK/wrap2-lockstate.log"
    flock -u 9
else
    echo HELD >> "$WORK/wrap2-lockstate.log"
fi
exec 9>&-
exec "$REAL_EMIT_ABS" "\$@"
WRAPEOF
chmod +x "$WRAP2/goalforge-trace-emit"
cp -r "$FIX/reset-decision-ref-feature" "$WORK/b8-case2"
WP82="$WORK/b8-case2/wp-reset-decision-ref"
R82="human ruling 2026-09-13 park-seq=2"
DR82="$WP82/dr82.md"; mkruling_at "$DR82" "$R82" "$((PARKED_EPOCH + 60))"
bash "$WRAP2/goalforge-harden-stop.sh" --reset --reason "$R82" --decision-ref "$DR82" "$WP82" >"$WORK/b8-case2.out" 2>&1; rc82=$?
if [ "$rc82" -eq 0 ] && [ "$(cat "$WORK/wrap2-lockstate.log" 2>/dev/null)" = "HELD" ]; then
    ok "b8(2): the wrapper's non-blocking probe finds the reset lock HELD during the emit -> exit 0"
else
    bad "b8(2): the wrapper's non-blocking probe finds the reset lock HELD during the emit (rc=$rc82, state=$(cat "$WORK/wrap2-lockstate.log" 2>/dev/null))"
fi

# (3) a wrapper that rewrites the payload's `reason` before delegating -- a
# harden.reset row for this WP lands beyond the baseline, but it is not THIS
# call's row: the read-back must match reason+decision_ref, not just type+wp.
WRAP3="$WORK/wrap3-scripts"; mkdir -p "$WRAP3"
cp "$STOP" "$WRAP3/goalforge-harden-stop.sh"
cat > "$WRAP3/goalforge-trace-emit" <<WRAPEOF
#!/usr/bin/env python3
# do_reset() pipes the event JSON on STDIN (emit_json: printf ... | \$emit
# --feature-dir <dir>) -- never as an --event argument. Read stdin, rewrite,
# re-pipe to the real emitter, forwarding argv unchanged.
import json, sys, subprocess
raw = sys.stdin.read()
ev = json.loads(raw)
if ev.get("type") == "harden.reset":
    ev["reason"] = "REWRITTEN " + ev["reason"]
    raw = json.dumps(ev)
proc = subprocess.run(["$REAL_EMIT_ABS"] + sys.argv[1:], input=raw, text=True)
sys.exit(proc.returncode)
WRAPEOF
chmod +x "$WRAP3/goalforge-trace-emit"
cp -r "$FIX/reset-decision-ref-feature" "$WORK/b8-case3"
WP83="$WORK/b8-case3/wp-reset-decision-ref"
R83="human ruling 2026-09-13 park-seq=2"
DR83="$WP83/dr83.md"; mkruling_at "$DR83" "$R83" "$((PARKED_EPOCH + 60))"
bash "$WRAP3/goalforge-harden-stop.sh" --reset --reason "$R83" --decision-ref "$DR83" "$WP83" >"$WORK/b8-case3.out" 2>&1; rc83=$?
if [ "$rc83" -eq 2 ] && grep -q 'read-back failed' "$WORK/b8-case3.out"; then
    ok "b8(3): a wrapper rewriting reason before delegating -> exit 2, read-back failure named"
else
    bad "b8(3): a wrapper rewriting reason before delegating -> exit 2, read-back failure (rc=$rc83)"
    sed 's/^/        /' "$WORK/b8-case3.out"
fi

# (4) a wrapper that rewrites ONLY decision_ref before delegating.
WRAP4="$WORK/wrap4-scripts"; mkdir -p "$WRAP4"
cp "$STOP" "$WRAP4/goalforge-harden-stop.sh"
cat > "$WRAP4/goalforge-trace-emit" <<WRAPEOF
#!/usr/bin/env python3
# See WRAP3's comment: the event JSON arrives on STDIN, not --event.
import json, sys, subprocess
raw = sys.stdin.read()
ev = json.loads(raw)
if ev.get("type") == "harden.reset":
    ev["decision_ref"] = "findings.md"
    raw = json.dumps(ev)
proc = subprocess.run(["$REAL_EMIT_ABS"] + sys.argv[1:], input=raw, text=True)
sys.exit(proc.returncode)
WRAPEOF
chmod +x "$WRAP4/goalforge-trace-emit"
cp -r "$FIX/reset-decision-ref-feature" "$WORK/b8-case4"
WP84="$WORK/b8-case4/wp-reset-decision-ref"
R84="human ruling 2026-09-13 park-seq=2"
DR84="$WP84/dr84.md"; mkruling_at "$DR84" "$R84" "$((PARKED_EPOCH + 60))"
bash "$WRAP4/goalforge-harden-stop.sh" --reset --reason "$R84" --decision-ref "$DR84" "$WP84" >"$WORK/b8-case4.out" 2>&1; rc84=$?
if [ "$rc84" -eq 2 ] && grep -q 'read-back failed' "$WORK/b8-case4.out"; then
    ok "b8(4): a wrapper rewriting decision_ref before delegating -> exit 2, read-back failure named"
else
    bad "b8(4): a wrapper rewriting decision_ref before delegating -> exit 2, read-back failure (rc=$rc84)"
    sed 's/^/        /' "$WORK/b8-case4.out"
fi

# ═══════════════════════════════════════════════════════════════════════════
# b9: every --reset exit 2 carries exactly one of two stable stderr prefixes
# ═══════════════════════════════════════════════════════════════════════════

check_prefix() {
    local label="$1" outfile="$2" want="$3"   # want: refused | internal
    local has_refused has_internal
    has_refused=0; has_internal=0
    grep -q '^goalforge-harden-stop: --reset refused — .' "$outfile" && has_refused=1
    grep -q '^goalforge-harden-stop: internal error — .' "$outfile" && has_internal=1
    if [ "$want" = "refused" ] && [ "$has_refused" -eq 1 ] && [ "$has_internal" -eq 0 ]; then
        ok "b9: $label -> --reset refused prefix, no internal-error line"
    elif [ "$want" = "internal" ] && [ "$has_internal" -eq 1 ]; then
        ok "b9: $label -> internal error prefix present"
    else
        bad "b9: $label -> $want prefix (refused=$has_refused internal=$has_internal)"
        sed 's/^/        /' "$outfile"
    fi
}
check_prefix "equal-second"     "$WORK/b6-equal-second.out"     refused
check_prefix "stale"            "$WORK/b6-stale.out"            refused
check_prefix "missing-path"     "$WORK/b6-missing-path.out"     refused
check_prefix "omitted-flag"     "$WORK/b6-omitted-flag.out"     refused
check_prefix "chain-park-only"  "$WORK/b6-chain-park-only.out"  refused
check_prefix "marker-only"      "$WORK/b6-marker-only.out"      refused
check_prefix "reason-only"      "$WORK/b6-reason-only.out"      refused
check_prefix "outside-wp"       "$WORK/b6-outside-wp.out"       refused
check_prefix "symlink-escape"   "$WORK/b6-symlink-escape.out"   refused
check_prefix "no-park-seq"      "$WORK/b6-no-park-seq.out"      refused
check_prefix "wrong-park-seq"   "$WORK/b6-wrong-park-seq.out"   refused
check_prefix "extra-digit"      "$WORK/b6-extra-digit.out"      refused
check_prefix "empty-reason"     "$WORK/b6-empty-reason.out"     refused
check_prefix "whitespace-reason" "$WORK/b6-whitespace-reason.out" refused
check_prefix "repeat-after-admission" "$WORK/b6-repeat-after-admission.out" refused
check_prefix "dispatch-with-reset"    "$WORK/b6-dispatch.out"                refused
check_prefix "unparked-at-cap"        "$WORK/b6-unparked.out"                refused
check_prefix "b1-kb-ii (stub emitter, no reset row)"  "$WORK/kb3.out" internal
check_prefix "b8(3) reason-rewrite wrapper"    "$WORK/b8-case3.out" internal
check_prefix "b8(4) decision_ref-rewrite wrapper" "$WORK/b8-case4.out" internal

# corrupt-trace admission path -- previously silent (gate-B lap-2 L2 repro).
cp -r "$FIX/reset-decision-ref-feature" "$WORK/b9-corrupt"
WP9C="$WORK/b9-corrupt/wp-reset-decision-ref"
TRACE9C="$WORK/b9-corrupt/trace-events.jsonl"
printf 'not json A\nnot json B\n' >> "$TRACE9C"
R9C="human ruling 2026-09-13 park-seq=2"
DR9C="$WP9C/dr9c.md"; mkruling_at "$DR9C" "$R9C" "$((PARKED_EPOCH + 60))"
bash "$STOP" --reset --reason "$R9C" --decision-ref "$DR9C" "$WP9C" >"$WORK/b9-corrupt.out" 2>&1; rc9c=$?
if [ "$rc9c" -eq 2 ] && [ -s "$WORK/b9-corrupt.out" ]; then
    check_prefix "corrupt interior trace line during --reset admission" "$WORK/b9-corrupt.out" internal
else
    bad "b9: corrupt interior trace line during --reset admission -> exit 2 with stderr (rc=$rc9c)"
fi

# missing WP dir.
bash "$STOP" --reset --reason "x" --decision-ref "/nonexistent" "$WORK/does-not-exist" >"$WORK/b9-nowp.out" 2>&1; rc9nowp=$?
if [ "$rc9nowp" -eq 2 ]; then check_prefix "missing WP dir under --reset" "$WORK/b9-nowp.out" internal
else bad "b9: missing WP dir under --reset -> exit 2 (rc=$rc9nowp)"; fi

# header documents --reset, the refused prefix and the internal-error prefix.
HEADER_TEXT="$(awk '/^set -uo pipefail/{exit} {print}' "$STOP")"
if printf '%s' "$HEADER_TEXT" | grep -q -- '--reset' \
   && printf '%s' "$HEADER_TEXT" | grep -q 'refused' \
   && printf '%s' "$HEADER_TEXT" | grep -q 'internal error'; then
    ok "b9: the header comment documents --reset, the refused prefix and the internal-error prefix"
else
    bad "b9: the header comment documents --reset, the refused prefix and the internal-error prefix"
fi

# ═══════════════════════════════════════════════════════════════════════════
# b10: the shared reader tolerates the emitter's torn-tail isolation contract
# ═══════════════════════════════════════════════════════════════════════════

cp -r "$FIX/reset-decision-ref-feature" "$WORK/b10-torn"
WP10="$WORK/b10-torn/wp-reset-decision-ref"
TRACE10="$WORK/b10-torn/trace-events.jsonl"
printf '{"seq":3,"ts":"2026' >> "$TRACE10"
R10="human ruling 2026-09-13 park-seq=2"
DR10="$WP10/dr10.md"; mkruling_at "$DR10" "$R10" "$((PARKED_EPOCH + 60))"
bash "$STOP" --reset --reason "$R10" --decision-ref "$DR10" "$WP10" >"$WORK/b10-reset.out" 2>&1; rc10r=$?
if [ "$rc10r" -eq 0 ] && [ "$(reset_count "$TRACE10")" = "1" ]; then
    ok "b10: --reset against a newline-less torn tail -> exit 0, exactly one new row read back"
else
    bad "b10: --reset against a newline-less torn tail -> exit 0 (rc=$rc10r)"
    sed 's/^/        /' "$WORK/b10-reset.out"
fi
bash "$STOP" "$WP10" >/dev/null 2>&1; rc10p=$?
if [ "$rc10p" -eq 0 ]; then ok "b10: a plain run after the torn-tail reset -> exit 0 (not wedged)"
else bad "b10: a plain run after the torn-tail reset -> exit 0 (rc=$rc10p)"; fi

# second copy: two consecutive unparseable lines -- real corruption, tolerated
# by neither the last-line rule nor the next-line-parses rule. (verify lap-3
# fix-forward item 5) the --reset decision-ref must resolve INSIDE this
# copy's own WP dir -- an out-of-WP path (the old $DR10, which lives under
# b10-torn) is refused by the (d) scope check before the trace is ever read,
# which asserts the wrong prefix; an in-WP decision-ref reaches the corrupt
# trace read and exits under the internal-error prefix instead.
cp -r "$FIX/two-rounds-feature" "$WORK/b10-corrupt"
TRACE10C="$WORK/b10-corrupt/trace-events.jsonl"
printf 'garbage line one\ngarbage line two\n' >> "$TRACE10C"
bash "$STOP" "$WORK/b10-corrupt/wp-two-rounds" >/dev/null 2>&1; rc10c1=$?
DR10C="$WORK/b10-corrupt/wp-two-rounds/dr10c.md"
mkruling "$DR10C" "x park-seq=0"
bash "$STOP" --reset --reason "x park-seq=0" --decision-ref "$DR10C" "$WORK/b10-corrupt/wp-two-rounds" >"$WORK/b10-corrupt-reset.out" 2>&1; rc10c2=$?
if [ "$rc10c1" -eq 2 ] && [ "$rc10c2" -eq 2 ]; then
    ok "b10: two consecutive unparseable lines -> both a plain run and --reset exit 2"
else
    bad "b10: two consecutive unparseable lines -> both exit 2 (plain=$rc10c1, reset=$rc10c2)"
    sed 's/^/        /' "$WORK/b10-corrupt-reset.out"
fi
check_prefix "b10 corrupt second-copy --reset (in-WP decision-ref)" "$WORK/b10-corrupt-reset.out" internal

# third copy: a torn TRAILING row cut mid multibyte UTF-8 character (gate-B
# lap-3 MEDIUM (b)) -- the shared reader decodes PER LINE, not the whole file
# in one strict-utf8 read, so a crash-mid-write fragment that tears a
# multibyte character in half isolates on its own last line exactly like the
# ASCII fragment above, for both a plain run and --reset.
cp -r "$FIX/reset-decision-ref-feature" "$WORK/b10-mb"
WP10MB="$WORK/b10-mb/wp-reset-decision-ref"
TRACE10MB="$WORK/b10-mb/trace-events.jsonl"
printf '{"seq":3,"ts":"2026-09-10T09:40:00Z","note":"em dash \xe2\x80' >> "$TRACE10MB"
R10MB="human ruling 2026-09-13 park-seq=2"
DR10MB="$WP10MB/dr10mb.md"; mkruling_at "$DR10MB" "$R10MB" "$((PARKED_EPOCH + 60))"
bash "$STOP" --reset --reason "$R10MB" --decision-ref "$DR10MB" "$WP10MB" >"$WORK/b10-mb-reset.out" 2>&1; rc10mbr=$?
if [ "$rc10mbr" -eq 0 ] && [ "$(reset_count "$TRACE10MB")" = "1" ]; then
    ok "b10: --reset against a torn TRAILING row cut mid multibyte UTF-8 character -> exit 0, exactly one new row read back"
else
    bad "b10: --reset against a torn multibyte-UTF-8 tail -> exit 0 (rc=$rc10mbr)"
    sed 's/^/        /' "$WORK/b10-mb-reset.out"
fi
bash "$STOP" "$WP10MB" >/dev/null 2>&1; rc10mbp=$?
if [ "$rc10mbp" -eq 0 ]; then ok "b10: a plain run after the torn-multibyte reset -> exit 0 (not wedged)"
else bad "b10: a plain run after the torn-multibyte reset -> exit 0 (rc=$rc10mbp)"; fi

# ═══════════════════════════════════════════════════════════════════════════
# b11: a second recorded ruling gives a second re-entry
# ═══════════════════════════════════════════════════════════════════════════

cp -r "$FIX/reset-twice-feature" "$WORK/b11-plain"
bash "$STOP" "$WORK/b11-plain/wp-reset-twice" >"$WORK/b11-plain.out" 2>&1; rc11p=$?
if [ "$rc11p" -eq 0 ] && [ ! -f "$WORK/b11-plain/wp-reset-twice/findings.md" ]; then
    ok "b11: two honoured resets, each citing its own park -> plain run exits 0, no new park, no findings.md"
else
    bad "b11: two honoured resets -> plain run exits 0 (rc=$rc11p)"
    sed 's/^/        /' "$WORK/b11-plain.out"
fi

cp -r "$FIX/reset-twice-feature" "$WORK/b11-reset"
FEAT11="$WORK/b11-reset"
WP11="$FEAT11/wp-reset-twice"
TRACE11="$FEAT11/trace-events.jsonl"
# remove the seq-7 (second) reset row, leaving the WP parked again at seq 6.
grep -v '"seq":7' "$TRACE11" > "$TRACE11.tmp" && mv "$TRACE11.tmp" "$TRACE11"
R11="second human ruling park-seq=6"
DR11="$WP11/dr11.md"; mkruling_at "$DR11" "$R11" "$(( $(epoch_of "$(last_park_ts "$TRACE11")") + 60 ))"
bash "$STOP" --reset --reason "$R11" --decision-ref "$DR11" "$WP11" >"$WORK/b11-reset.out" 2>&1; rc11r=$?
if [ "$rc11r" -eq 0 ]; then ok "b11: --reset citing the second park's seq (after the shipped 2nd reset is removed) -> exit 0"
else bad "b11: --reset citing the second park's seq -> exit 0 (rc=$rc11r)"; sed 's/^/        /' "$WORK/b11-reset.out"; fi
bash "$STOP" "$WP11" >/dev/null 2>&1; rc11p2=$?
if [ "$rc11p2" -eq 0 ]; then ok "b11: a plain run after the second --reset -> exit 0"
else bad "b11: a plain run after the second --reset -> exit 0 (rc=$rc11p2)"; fi

# ═══════════════════════════════════════════════════════════════════════════
# b12: every harden.reset row in the reset-* fixtures is schema-shaped and
# park-bound (the b7 honour predicate holds for every shipped row)
# ═══════════════════════════════════════════════════════════════════════════

# check_fixture_conformance <trace.jsonl>... -- b12: every harden.reset row
# in the given traces (a) carries every field the schema's harden.reset
# oneOf branch requires, and (b) satisfies the b7 honour predicate (the
# nearest earlier same-wp park/reset row is a park row P, and reason cites
# the literal park-seq=<P.seq> with no digit directly after it).
check_fixture_conformance() {
    python3 - "$SCHEMA_DOC" "$@" <<'PY'
import json, re, sys
doc_path = sys.argv[1]
trace_paths = sys.argv[2:]
lines = open(doc_path, encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(lines) if l.strip() == "```json") + 1
end = next(j for j in range(start, len(lines)) if lines[j].strip() == "```")
schema = json.loads("\n".join(lines[start:end]))
branch = next(b for b in schema["oneOf"]
              if b.get("properties", {}).get("type", {}).get("const") == "harden.reset")
required = branch["required"]
ok = True
for trace_path in trace_paths:
    rows = [json.loads(r) for r in open(trace_path, encoding="utf-8") if r.strip()]
    last_wp_type, last_park_seq = {}, {}
    for row in rows:
        wp, t = row.get("wp"), row.get("type")
        if t == "harden.parked":
            last_park_seq[wp] = row.get("seq")
            last_wp_type[wp] = "parked"
            continue
        if t != "harden.reset":
            continue
        for field in required:
            if field not in row:
                sys.stderr.write(f"{trace_path}: seq={row.get('seq')} missing {field!r}\n")
                ok = False
        honoured = False
        if last_wp_type.get(wp) == "parked" and wp in last_park_seq:
            pat = r"park-seq=" + re.escape(str(last_park_seq[wp])) + r"(?!\d)"
            honoured = bool(re.search(pat, row.get("reason") or ""))
        if not honoured:
            sys.stderr.write(f"{trace_path}: seq={row.get('seq')} for wp {wp!r} not park-bound\n")
            ok = False
        last_wp_type[wp] = "reset"
sys.exit(0 if ok else 1)
PY
}

if check_fixture_conformance \
    "$FIX/reset-cleared-feature/trace-events.jsonl" \
    "$FIX/reset-then-two-feature/trace-events.jsonl" \
    "$FIX/reset-other-wp-feature/trace-events.jsonl" \
    "$FIX/reset-decision-ref-feature/trace-events.jsonl" \
    "$FIX/reset-twice-feature/trace-events.jsonl"; then
    ok "b12: every harden.reset row in the reset-* fixtures is schema-required-field-complete and park-bound"
else
    bad "b12: every harden.reset row in the reset-* fixtures is schema-required-field-complete and park-bound"
fi

# known-bad: a reset row that carries no decision_ref must fail the check.
cp "$FIX/reset-cleared-feature/trace-events.jsonl" "$WORK/b12-nodref.jsonl"
sed -i 's/,"decision_ref":"findings.md"//' "$WORK/b12-nodref.jsonl"
if check_fixture_conformance "$WORK/b12-nodref.jsonl" 2>/dev/null; then
    bad "b12 known-bad: a reset row missing decision_ref must fail the conformance check"
else
    ok "b12 known-bad: a reset row missing decision_ref fails the conformance check"
fi

# known-bad: a reset row citing another WP's park (the pre-review b3 shape).
cp "$FIX/reset-other-wp-feature/trace-events.jsonl" "$WORK/b12-crosswp.jsonl"
if check_fixture_conformance "$WORK/b12-crosswp.jsonl" 2>/dev/null; then
    ok "b12: reset-other-wp-feature's reset row is bound to its OWN wp's park (not cross-wp)"
else
    bad "b12: reset-other-wp-feature's reset row should be bound to its own wp's park"
fi

# ═══════════════════════════════════════════════════════════════════════════
# b13: idempotent park -- an already-parked WP stays parked without a repeat
# write; park-seq output contract (PARK vs already parked)
# ═══════════════════════════════════════════════════════════════════════════

# (1) two-rounds-feature (no park row initially): run twice.
cp -r "$FIX/two-rounds-feature" "$WORK/b13-1"
WP13A="$WORK/b13-1/wp-two-rounds"
TRACE13A="$WORK/b13-1/trace-events.jsonl"
OUT13A1="$(bash "$STOP" "$WP13A" 2>&1)"; rc13a1=$?
TRACE13A_SUM1="$(md5sum "$TRACE13A" | awk '{print $1}')"
LINES13A1="$(ceiling_lines "$WP13A")"
NEWSEQ13A="$(last_park_seq_of "$TRACE13A")"
if [ "$rc13a1" -eq 3 ] && [ "$LINES13A1" = "1" ] \
   && printf '%s' "$OUT13A1" | grep -q "PARK — .*park-seq=$NEWSEQ13A\$"; then
    ok "b13(1) run1: fresh park -> exit 3, one findings.md line, PARK stderr names the written row's seq"
else
    bad "b13(1) run1: fresh park (rc=$rc13a1)"
    printf '%s\n' "$OUT13A1" | sed 's/^/        /'
fi
OUT13A2="$(bash "$STOP" "$WP13A" 2>&1)"; rc13a2=$?
TRACE13A_SUM2="$(md5sum "$TRACE13A" | awk '{print $1}')"
LINES13A2="$(ceiling_lines "$WP13A")"
if [ "$rc13a2" -eq 3 ] && [ "$TRACE13A_SUM1" = "$TRACE13A_SUM2" ] && [ "$LINES13A1" = "$LINES13A2" ] \
   && printf '%s' "$OUT13A2" | grep -q "already parked (park-seq=$NEWSEQ13A)" \
   && ! printf '%s' "$OUT13A2" | grep -q 'PARK — '; then
    ok "b13(1) run2 (already parked): exit 3, trace and findings.md byte-identical, distinct already-parked stderr"
else
    bad "b13(1) run2 (already parked)"
    printf '%s\n' "$OUT13A2" | sed 's/^/        /'
fi

# (2) reset-decision-ref-feature: last park follows no reset -> already
# parked on the FIRST plain run.
cp -r "$FIX/reset-decision-ref-feature" "$WORK/b13-2"
WP13B="$WORK/b13-2/wp-reset-decision-ref"
TRACE13B="$WORK/b13-2/trace-events.jsonl"
SUM13B_BEFORE="$(md5sum "$TRACE13B" | awk '{print $1}')"
LINES13B_BEFORE="$(ceiling_lines "$WP13B")"
OUT13B="$(bash "$STOP" "$WP13B" 2>&1)"; rc13b=$?
SUM13B_AFTER="$(md5sum "$TRACE13B" | awk '{print $1}')"
LINES13B_AFTER="$(ceiling_lines "$WP13B")"
if [ "$rc13b" -eq 3 ] && [ "$SUM13B_BEFORE" = "$SUM13B_AFTER" ] && [ "$LINES13B_BEFORE" = "$LINES13B_AFTER" ] \
   && printf '%s' "$OUT13B" | grep -q 'already parked (park-seq=2)'; then
    ok "b13(2): a WP already parked with no reset following -> exit 3, byte-identical, already-parked stderr"
else
    bad "b13(2): a WP already parked with no reset following (rc=$rc13b)"
    printf '%s\n' "$OUT13B" | sed 's/^/        /'
fi

# ═══════════════════════════════════════════════════════════════════════════
# b14: harden/SKILL.md guidance matches the park output contract
# ═══════════════════════════════════════════════════════════════════════════

SKILL_MD="$SD/../../harden/SKILL.md"
if grep -q 'already parked' "$SKILL_MD"; then ok "b14: harden/SKILL.md mentions 'already parked'"
else bad "b14: harden/SKILL.md mentions 'already parked'"; fi

EXIT3_BLOCK="$(sed -n '70,71p' "$SKILL_MD")"
REENTRY_LINE="$(sed -n '74p' "$SKILL_MD")"
if printf '%s' "$EXIT3_BLOCK" | grep -q 'park-seq='; then ok "b14: the exit-3 guidance (lines 70-71) cites park-seq="
else bad "b14: the exit-3 guidance (lines 70-71) cites park-seq="; fi
if printf '%s' "$REENTRY_LINE" | grep -q 'park-seq='; then ok "b14: the re-entry line (74) cites park-seq="
else bad "b14: the re-entry line (74) cites park-seq="; fi
if grep -qiE 'append[^.]*harden: ceiling-breached' "$SKILL_MD"; then
    bad "b14: SKILL.md must not instruct the agent to append the harden: ceiling-breached line itself"
else
    ok "b14: SKILL.md does not instruct the agent to append the harden: ceiling-breached line itself"
fi
LINE67="$(sed -n '67p' "$SKILL_MD")"
if printf '%s' "$LINE67" | grep -q -- 'PARK —' \
   && ! printf '%s' "$LINE67" | grep -qi 'every exit 3'; then
    ok "b14: line 67 scopes the stage-report call to a NEW park (PARK — output), not every exit 3"
else
    bad "b14: line 67 scopes the stage-report call to a NEW park (PARK — output), not every exit 3"
fi

echo ""
echo "goalforge-harden-reset.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
