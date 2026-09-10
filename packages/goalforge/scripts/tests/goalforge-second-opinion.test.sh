#!/usr/bin/env bash
# goalforge-second-opinion.test.sh — wp-03 b6 sabotage pair for the second
# opinion leg (egress class resolution, payload bytes, leaf seam, ledger).
#
#   known-good : the shipped `overview` row sends verdict + diff + overview.md
#                verbatim, records second_opinion.ok, and appends exactly one
#                propose-only ledger row per leaf call.
#   known-bad  : a dispatch row at `egress: none` calls NO leaf (skipped,
#                reason egress-none); a feature spec.md that tries to WIDEN
#                the class never adds a wider section — a widening value is
#                ignored with a WARN; a call with neither `--verdict` nor
#                `--diff` (the pre-lap pinned call) skips with reason
#                `no-payload` instead of sending an empty payload; and a diff
#                over 100 KiB is truncated in the payload and in the reason.
#
# Everything runs under one mktemp -d root: the stub leaf, CLAUDE_CONFIG_DIR,
# the feature dir, and GOALFORGE_DISPATCH_LEDGER. Nothing touches the live
# ledger, the checked-in fixtures, or a plans/ tree.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECOND_OPINION="$SD/../goalforge-second-opinion.sh"
FIXTURES="$SD/fixtures/dispatch"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export CLAUDE_CONFIG_DIR="$T/corpus"
export GOALFORGE_DISPATCH_LEDGER="$T/ledger/dispatch-decisions.jsonl"
CAPTURE="$T/capture-prompt.txt"
CALLS="$T/calls.log"

# --- stub leaf (leaf-interface.md v1: envelope + EXIT_CODE trailer) ----------
STUB="$CLAUDE_CONFIG_DIR/skills/agent-dispatch/stub-a/scripts/headless_dispatch"
mkdir -p "$(dirname "$STUB")"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
set -uo pipefail
PROMPT=""; OUTPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt) PROMPT="${2:-}"; shift 2 ;;
        --prompt-file) PROMPT="$(cat "${2:-}")"; shift 2 ;;
        --output) OUTPUT="${2:-}"; shift 2 ;;
        *) shift 2 ;;
    esac
done
printf '%s' "$PROMPT" > "$STUB_CAPTURE"
echo "call" >> "$STUB_CALLS"
STUB_EXIT="${STUB_EXIT:-0}"
STUB_REASON="${STUB_REASON:-}"
printf '{"type":"result","subtype":"success","is_error":false,"result":"stub second opinion: verdict looks sound","codex":{"reason":"%s"}}\n' "$STUB_REASON" > "$OUTPUT"
echo "EXIT_CODE=$STUB_EXIT" >> "$OUTPUT"
exit "$STUB_EXIT"
STUBEOF
chmod +x "$STUB"
export STUB_CAPTURE="$CAPTURE" STUB_CALLS="$CALLS"

# --- feature fixture ---------------------------------------------------------
FEATURE="$T/feature"
WP="$FEATURE/wp-01-example"
mkdir -p "$WP"
printf 'OVERVIEW-MARKER wp overview body\n' > "$WP/overview.md"
printf 'FINDINGS-MARKER one finding row\n' > "$WP/findings.md"
printf 'VERDICT-MARKER gate C: goal met\n' > "$T/verdict.txt"
printf 'DIFF-MARKER +one changed line\n' > "$T/wp.diff"

run_so() { # $1=dispatch fixture  $2=spec fixture (or "")  $3..=extra argv
    local dispatch="$1" spec="$2"; shift 2
    : > "$CALLS"; : > "$CAPTURE"
    if [[ -n "$spec" ]]; then cp "$FIXTURES/$spec" "$FEATURE/spec.md"; else rm -f "$FEATURE/spec.md"; fi
    rm -f "$FEATURE/trace-events.jsonl"
    bash "$SECOND_OPINION" "$WP" --feature-dir "$FEATURE" \
        --dispatch "$FIXTURES/$dispatch" "$@" \
        > "$T/stdout.txt" 2> "$T/stderr.txt"
    echo "$?" > "$T/exit.txt"
}

run_so_pinned() { # the standard call: verdict + diff present
    run_so "$1" "$2" --verdict "$T/verdict.txt" --diff "${3:-$T/wp.diff}"
}

calls() { wc -l < "$CALLS" | tr -d ' '; }
trace_has() { grep -q "$1" "$FEATURE/trace-events.jsonl" 2>/dev/null; }

# --- case 1: leaf absent -> dispatcher-absent, no call ----------------------
mv "$STUB" "$STUB.hidden"
run_so_pinned dispatch-default.yaml spec-no-egress.md
if [[ "$(cat "$T/exit.txt")" == "0" ]] && trace_has 'dispatcher-absent'; then
    ok "leaf absent -> second_opinion.skipped reason dispatcher-absent, exit 0"
else
    bad "leaf absent -> second_opinion.skipped reason dispatcher-absent, exit 0"
    cat "$T/stderr.txt"
fi
[[ "$(calls)" == "0" ]] && ok "leaf absent -> no leaf call" || bad "leaf absent -> no leaf call"
mv "$STUB.hidden" "$STUB"

# --- case 2 (known-good): overview row, no feature override -----------------
run_so_pinned dispatch-default.yaml spec-no-egress.md
if [[ "$(calls)" == "1" ]] && trace_has 'second_opinion.ok'; then
    ok "overview row -> leaf called once, second_opinion.ok"
else
    bad "overview row -> leaf called once, second_opinion.ok"
    cat "$T/stderr.txt"
fi
if grep -q 'VERDICT-MARKER' "$CAPTURE" && grep -q 'DIFF-MARKER' "$CAPTURE" \
   && grep -q 'OVERVIEW-MARKER' "$CAPTURE" && ! grep -q 'FINDINGS-MARKER' "$CAPTURE"; then
    ok "overview payload = verdict + diff + overview.md, verbatim"
else
    bad "overview payload = verdict + diff + overview.md, verbatim"
fi
# section order
if [[ "$(grep -n '^## ' "$CAPTURE" | cut -d: -f2- | tr '\n' ',')" == "## verdict,## diff,## overview.md," ]]; then
    ok "overview payload section order: verdict, diff, overview.md"
else
    bad "overview payload section order: verdict, diff, overview.md"
    grep -n '^## ' "$CAPTURE"
fi
if [[ "$(wc -l < "$GOALFORGE_DISPATCH_LEDGER")" == "1" ]] \
   && grep -q '"decision": "propose-only"' "$GOALFORGE_DISPATCH_LEDGER" \
   && grep -q '"role": "second_opinion"' "$GOALFORGE_DISPATCH_LEDGER"; then
    ok "one propose-only ledger row per leaf call, at the pinned path"
else
    bad "one propose-only ledger row per leaf call, at the pinned path"
    cat "$GOALFORGE_DISPATCH_LEDGER" 2>/dev/null
fi

# --- case 3: feature narrows to diff-only -----------------------------------
run_so_pinned dispatch-default.yaml spec-egress-diff-only.md
if grep -q 'DIFF-MARKER' "$CAPTURE" && ! grep -q 'OVERVIEW-MARKER' "$CAPTURE"; then
    ok "feature egress: diff-only narrows the overview row (diff only)"
else
    bad "feature egress: diff-only narrows the overview row (diff only)"
fi

# --- case 4 (known-bad): feature tries to widen to full ---------------------
run_so_pinned dispatch-default.yaml spec-egress-full.md
if grep -q 'OVERVIEW-MARKER' "$CAPTURE" && ! grep -q 'FINDINGS-MARKER' "$CAPTURE" \
   && grep -q 'WARN' "$T/stderr.txt" && grep -q 'egress-widening-ignored' "$T/stderr.txt"; then
    ok "feature egress: full is ignored (payload stays overview) with a WARN"
else
    bad "feature egress: full is ignored (payload stays overview) with a WARN"
    cat "$T/stderr.txt"
fi

# --- case 5 (known-bad): row at egress none ---------------------------------
run_so_pinned dispatch-egress-none.yaml spec-no-egress.md
if [[ "$(calls)" == "0" ]] && trace_has 'egress-none'; then
    ok "egress: none row -> skipped reason egress-none, no leaf call"
else
    bad "egress: none row -> skipped reason egress-none, no leaf call"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 6: row at egress full ---------------------------------------------
run_so_pinned dispatch-egress-full.yaml spec-no-egress.md
if grep -q 'VERDICT-MARKER' "$CAPTURE" && grep -q 'DIFF-MARKER' "$CAPTURE" \
   && grep -q 'OVERVIEW-MARKER' "$CAPTURE" && grep -q 'FINDINGS-MARKER' "$CAPTURE" \
   && grep -q 'fixture-spec-no-egress' "$CAPTURE"; then
    ok "egress: full row -> diff + overview.md + spec.md + findings.md"
else
    bad "egress: full row -> diff + overview.md + spec.md + findings.md"
    grep -n '^## ' "$CAPTURE"
fi

# --- case 7: exit 4 budget_exceeded keeps the result ------------------------
STUB_EXIT=4 STUB_REASON=budget_exceeded run_so_pinned dispatch-default.yaml spec-no-egress.md
if trace_has 'second_opinion.ok' && trace_has 'budget_exceeded'; then
    ok "leaf exit 4 budget_exceeded -> result kept, second_opinion.ok"
else
    bad "leaf exit 4 budget_exceeded -> result kept, second_opinion.ok"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 8: a non-terminal leaf failure skips, never blocks -----------------
STUB_EXIT=1 run_so_pinned dispatch-default.yaml spec-no-egress.md
if [[ "$(cat "$T/exit.txt")" == "0" ]] && trace_has 'leaf-exit-1'; then
    ok "leaf exit 1 -> second_opinion.skipped reason leaf-exit-1, exit 0"
else
    bad "leaf exit 1 -> second_opinion.skipped reason leaf-exit-1, exit 0"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 9 (known-bad): the pinned call with neither --verdict nor --diff ---
# verify/SKILL.md pinned the call WITHOUT the payload flags before this lap;
# such a call must skip, not send an empty verdict + empty diff to the leaf.
run_so dispatch-default.yaml spec-no-egress.md
if [[ "$(cat "$T/exit.txt")" == "0" ]] && [[ "$(calls)" == "0" ]] && trace_has 'no-payload'; then
    ok "no --verdict and no --diff -> skipped reason no-payload, no leaf call, exit 0"
else
    bad "no --verdict and no --diff -> skipped reason no-payload, no leaf call, exit 0"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# an EMPTY (zero-length) verdict/diff pair is the same no-payload case
: > "$T/empty.txt"
run_so dispatch-default.yaml spec-no-egress.md --verdict "$T/empty.txt" --diff "$T/empty.txt"
if [[ "$(calls)" == "0" ]] && trace_has 'no-payload'; then
    ok "empty --verdict and --diff files -> no-payload, no leaf call"
else
    bad "empty --verdict and --diff files -> no-payload, no leaf call"
fi

# --- case 10: an oversized diff is truncated, in the payload AND the reason --
BIG="$T/big.diff"
{ echo 'DIFF-MARKER +one changed line'; head -c 150000 /dev/zero | tr '\0' 'x'; } > "$BIG"
run_so_pinned dispatch-default.yaml spec-no-egress.md "$BIG"
CAP_BYTES="$(wc -c < "$CAPTURE")"
if [[ "$(calls)" == "1" ]] && grep -q '\[diff truncated: [0-9]* of [0-9]* bytes\]' "$CAPTURE" \
   && [[ "$CAP_BYTES" -le 102400 ]] && trace_has 'diff-truncated'; then
    ok "diff over 100 KiB -> payload truncated with a marker, reason says diff-truncated N/M"
else
    bad "diff over 100 KiB -> payload truncated with a marker, reason says diff-truncated N/M"
    echo "  payload bytes: $CAP_BYTES"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# ledger accumulated exactly one row per leaf call (cases 2,3,4,6,7,8,10 = 7;
# cases 1, 5 and 9 never reach the leaf)
if [[ "$(wc -l < "$GOALFORGE_DISPATCH_LEDGER")" == "7" ]]; then
    ok "ledger row count equals leaf-call count (7)"
else
    bad "ledger row count equals leaf-call count (7): got $(wc -l < "$GOALFORGE_DISPATCH_LEDGER")"
fi

echo
echo "goalforge-second-opinion.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
