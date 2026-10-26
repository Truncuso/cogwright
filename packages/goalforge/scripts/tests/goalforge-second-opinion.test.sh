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
#                `no-payload` instead of sending an empty payload; a diff
#                over 100 KiB is truncated in the payload and in the reason; a
#                cap ABOVE the argv ceiling is clamped with a WARN (honouring
#                200000 killed the exec itself: "Argument list too long"); and a
#                non-integer cap WARNs instead of defaulting in silence.
#   wp-15      : the leaf's `result` text is checked before a completed leaf
#                call counts as `second_opinion.ok` — a non-verdict reply
#                (recorded glm prose, or a `status:"failed"` codex reply)
#                yields `second_opinion.invalid` instead, on both the exit-0
#                and exit-4 budget-overspend paths; a real verdict (raw JSON,
#                as codex actually replies, or fenced) still yields `.ok`.
#
# Everything runs under one mktemp -d root: the stub leaf, CLAUDE_CONFIG_DIR,
# the feature dir, and GOALFORGE_DISPATCH_LEDGER. Nothing touches the live
# ledger, the checked-in fixtures, or a plans/ tree.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECOND_OPINION="$SD/../goalforge-second-opinion.sh"
FIXTURES="$SD/fixtures/dispatch"
SO_FIXTURES="$SD/../../evals/fixtures/second-opinion"
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
PROMPT=""; OUTPUT=""; SAW=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt) PROMPT="${2:-}"; SAW="--prompt"; shift 2 ;;
        --prompt-file)
            # The stub models the leaves a `second_opinion` row COULD select —
            # ollama, zai, deepseek — where the flag is a STRUCTURED
            # handoff-brief path through _core/prompt_file.py (base-dir
            # allowlist + frontmatter contract) and a raw payload file exits 3
            # (verified 2026-09-13). Other leaves (e.g. codex) read it raw and
            # would accept one; the script must not depend on which, so the
            # stub reproduces the exit-3 leaf and the script can never regress
            # to the flag behind a faked stub.
            echo "--prompt-file" > "$STUB_FLAG"
            echo "stub leaf: --prompt-file is a structured handoff brief, not a payload" >&2
            exit 3 ;;
        --output) OUTPUT="${2:-}"; shift 2 ;;
        *) shift 2 ;;
    esac
done
echo "$SAW" > "$STUB_FLAG"
printf '%s' "$PROMPT" > "$STUB_CAPTURE"
echo "call" >> "$STUB_CALLS"
STUB_EXIT="${STUB_EXIT:-0}"
STUB_REASON="${STUB_REASON:-}"
# The "result" field on a real envelope is itself JSON-encoded text (see any
# plans/goalforge-overhaul/second-opinions/*.json), so the stub must
# JSON-encode STUB_RESULT rather than splice it in with printf %s: a raw
# splice breaks the outer envelope the moment STUB_RESULT contains a quote —
# exactly what a verdict-shaped or sabotage fixture does.
if [[ -z "${STUB_RESULT:-}" ]]; then
    STUB_RESULT='{"status":"success","summary":"stub second opinion: verdict looks sound"}'
fi
STUB_RESULT="$STUB_RESULT" STUB_REASON="$STUB_REASON" python3 -c '
import json, os
print(json.dumps({
    "type": "result",
    "subtype": "success",
    "is_error": False,
    "result": os.environ["STUB_RESULT"],
    "codex": {"reason": os.environ["STUB_REASON"]},
}))
' > "$OUTPUT"
echo "EXIT_CODE=$STUB_EXIT" >> "$OUTPUT"
exit "$STUB_EXIT"
STUBEOF
chmod +x "$STUB"
FLAG="$T/payload-flag.txt"
export STUB_CAPTURE="$CAPTURE" STUB_CALLS="$CALLS" STUB_FLAG="$FLAG"

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
    : > "$CALLS"; : > "$CAPTURE"; : > "$FLAG"
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
# N1: the payload reaches the leaf as a `--prompt` argv VALUE. `--prompt-file`
# on a configured leaf is a structured handoff-brief path (exit 3), so this
# assertion FAILS if the script ever passes --prompt-file again.
if [[ "$(cat "$FLAG")" == "--prompt" ]]; then
    ok "payload handed to the leaf as --prompt (never --prompt-file)"
else
    bad "payload handed to the leaf as --prompt (never --prompt-file): got '$(cat "$FLAG")'"
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

# --- case 11 (N6): a cap the WP's own documents blow -> payload-oversize -----
# dispatch-smallcap.yaml sets second_opinion.max_payload_bytes: 150, which the
# section headers + verdict + overview.md exceed on their own. Truncating the
# diff cannot help, so the reason must be `payload-oversize <actual>/<cap>`
# — never a misleading `diff-truncated 0/N` on a payload still over the cap.
run_so_pinned dispatch-smallcap.yaml spec-no-egress.md
if [[ "$(cat "$T/exit.txt")" == "0" ]] && [[ "$(calls)" == "0" ]] \
   && grep -q 'payload-oversize [0-9]*/150' "$FEATURE/trace-events.jsonl" 2>/dev/null \
   && ! trace_has 'diff-truncated'; then
    ok "configured cap the documents blow -> skipped reason payload-oversize N/150, no leaf call, exit 0"
else
    bad "configured cap the documents blow -> skipped reason payload-oversize N/150, no leaf call, exit 0"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 12 (R3-7): the cap is CONFIGURED, not hardcoded --------------------
# dispatch-midcap.yaml sets the cap to 8000 — a value that is NEITHER the
# script's default (102400) nor the smallcap 150. The same oversized diff as
# case 10 must therefore come out truncated to 8000, not to 102400. A script
# that ignored the dispatch file would send ~102400 bytes and fail here; the
# old version of this case re-used dispatch-default.yaml, whose cap equals the
# default, and so could not fail at all.
run_so_pinned dispatch-midcap.yaml spec-no-egress.md "$BIG"
MID_BYTES="$(wc -c < "$CAPTURE")"
if [[ "$(calls)" == "1" ]] && trace_has 'second_opinion.ok' \
   && [[ "$MID_BYTES" -le 8000 ]] && [[ "$MID_BYTES" -gt 150 ]] \
   && trace_has 'diff-truncated'; then
    ok "a configured cap of 8000 bounds the payload at 8000 (cap is configured: $MID_BYTES bytes)"
else
    bad "a configured cap of 8000 bounds the payload at 8000 (got $MID_BYTES bytes)"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 13 (R3-3): a cap above the argv ceiling is CLAMPED with a WARN -----
# dispatch-overcap.yaml sets 200000, the value the schema's prose invited.
# Pre-clamp, the script honoured it and the exec itself died: measured on this
# host "Argument list too long", payload 0 bytes, second_opinion.skipped —
# the B4 failure, reintroduced by a config edit. MAX_ARG_STRLEN here is
# PAGESIZE * 32 = 131072.
run_so_pinned dispatch-overcap.yaml spec-no-egress.md "$BIG"
OVER_BYTES="$(wc -c < "$CAPTURE")"
if [[ "$(calls)" == "1" ]] && trace_has 'second_opinion.ok' \
   && [[ "$OVER_BYTES" -le 102400 ]] \
   && grep -q 'exceeds the reviewed ceiling' "$T/stderr.txt" \
   && ! grep -qi 'argument list too long' "$T/stderr.txt"; then
    ok "a cap above the ceiling is clamped with a WARN, and the leaf still runs ($OVER_BYTES bytes)"
else
    bad "a cap above the ceiling is clamped with a WARN, and the leaf still runs ($OVER_BYTES bytes)"
    cat "$T/stderr.txt"
fi

# --- case 14 (R3-3): a non-integer cap WARNs, never silently defaults --------
run_so_pinned dispatch-badcap.yaml spec-no-egress.md
if [[ "$(calls)" == "1" ]] && trace_has 'second_opinion.ok' \
   && grep -q 'is not a positive integer' "$T/stderr.txt"; then
    ok "a non-integer cap falls back to the default WITH a WARN"
else
    bad "a non-integer cap falls back to the default WITH a WARN"
    cat "$T/stderr.txt"
fi

# --- case 14a (wp-15/b1): known-bad non-verdict prose -----------------------
# the actual recorded glm reply this WP guards against: prose, no JSON at all.
NON_VERDICT="$(cat "$SO_FIXTURES/known-bad-non-verdict.txt")"
STUB_RESULT="$NON_VERDICT" run_so_pinned dispatch-default.yaml spec-no-egress.md
if trace_has 'second_opinion.invalid' && trace_has 'non-verdict-result' \
   && ! trace_has 'second_opinion.ok'; then
    ok "known-bad non-verdict prose -> second_opinion.invalid, reason non-verdict-result"
else
    bad "known-bad non-verdict prose -> second_opinion.invalid, reason non-verdict-result"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 14b (wp-15/b1): known-bad status:"failed" reply -------------------
# a task-completion outcome, not an opinion: must not count as a verdict.
FAILED_STATUS="$(cat "$SO_FIXTURES/known-bad-failed-status.txt")"
STUB_RESULT="$FAILED_STATUS" run_so_pinned dispatch-default.yaml spec-no-egress.md
if trace_has 'second_opinion.invalid' && trace_has 'non-verdict-result' \
   && ! trace_has 'second_opinion.ok'; then
    ok "known-bad status:failed reply -> second_opinion.invalid (not an opinion)"
else
    bad "known-bad status:failed reply -> second_opinion.invalid (not an opinion)"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 14c (wp-15/b2): known-good verdict, raw JSON, no fence ------------
# verbatim result text from a recorded codex envelope — real replies are raw
# JSON, not fenced, so this is the common path, not a fallback.
GOOD_VERDICT="$(cat "$SO_FIXTURES/known-good-verdict.txt")"
STUB_RESULT="$GOOD_VERDICT" run_so_pinned dispatch-default.yaml spec-no-egress.md
if trace_has 'second_opinion.ok' && ! trace_has 'second_opinion.invalid'; then
    ok "known-good verdict fixture (raw, unfenced JSON) -> second_opinion.ok"
else
    bad "known-good verdict fixture (raw, unfenced JSON) -> second_opinion.ok"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 14d (wp-15/b2): known-good verdict inside a fenced ```json block --
GOOD_FENCED="$(cat "$SO_FIXTURES/known-good-fenced.txt")"
STUB_RESULT="$GOOD_FENCED" run_so_pinned dispatch-default.yaml spec-no-egress.md
if trace_has 'second_opinion.ok' && ! trace_has 'second_opinion.invalid'; then
    ok "known-good verdict fixture (fenced json block) -> second_opinion.ok"
else
    bad "known-good verdict fixture (fenced json block) -> second_opinion.ok"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 14e (wp-15/T2/b1): exit-4 budget_exceeded + non-verdict reply -----
# the budget-overspend branch applies the SAME verdict check as exit-0, and
# keeps its `; overspend: <reason>` suffix on the invalid row too.
STUB_EXIT=4 STUB_REASON=budget_exceeded STUB_RESULT="$NON_VERDICT" \
    run_so_pinned dispatch-default.yaml spec-no-egress.md
if trace_has 'second_opinion.invalid' && trace_has 'non-verdict-result' \
   && trace_has 'overspend: budget_exceeded' && ! trace_has 'second_opinion.ok'; then
    ok "exit-4 budget_exceeded + non-verdict reply -> second_opinion.invalid, overspend suffix kept"
else
    bad "exit-4 budget_exceeded + non-verdict reply -> second_opinion.invalid, overspend suffix kept"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 14f (M1-v8): known-good status:"partial" reply (verbatim) --------
# a verbatim recorded codex reply for wp-10-respec-edge, `status:"partial"`.
# 4 of 10 recorded codex envelopes use `status:"partial"`, so dropping it from
# the accepted status tuple would misclassify ~40% of real verdicts.
PARTIAL_STATUS="$(cat "$SO_FIXTURES/known-good-partial-status.txt")"
STUB_RESULT="$PARTIAL_STATUS" run_so_pinned dispatch-default.yaml spec-no-egress.md
if trace_has 'second_opinion.ok' && ! trace_has 'second_opinion.invalid'; then
    ok "known-good status:partial fixture (verbatim recorded reply) -> second_opinion.ok"
else
    bad "known-good status:partial fixture (verbatim recorded reply) -> second_opinion.ok"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 14g (M1-v8): known-good verdict-key reply (no status field) ------
VERDICT_KEY="$(cat "$SO_FIXTURES/known-good-verdict-key.txt")"
STUB_RESULT="$VERDICT_KEY" run_so_pinned dispatch-default.yaml spec-no-egress.md
if trace_has 'second_opinion.ok' && ! trace_has 'second_opinion.invalid'; then
    ok "known-good verdict-key fixture (no status field) -> second_opinion.ok"
else
    bad "known-good verdict-key fixture (no status field) -> second_opinion.ok"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 14h (M1-v8): known-bad status:"success" with an empty summary ----
EMPTY_SUMMARY="$(cat "$SO_FIXTURES/known-bad-empty-summary.txt")"
STUB_RESULT="$EMPTY_SUMMARY" run_so_pinned dispatch-default.yaml spec-no-egress.md
if trace_has 'second_opinion.invalid' && trace_has 'non-verdict-result' \
   && ! trace_has 'second_opinion.ok'; then
    ok "known-bad empty-summary reply -> second_opinion.invalid"
else
    bad "known-bad empty-summary reply -> second_opinion.invalid"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 14i (M1-v8/L2-v8): prose quoting a fenced status:"failed" block --
# the fenced block is parseable JSON but not verdict-shaped once status:failed
# is rejected before the verdict-key fallback (L2-v8) — a fenced-path mutant
# that accepted ANY parseable fenced block regardless of shape would wrongly
# pass this as .ok.
FENCED_FAILED="$(cat "$SO_FIXTURES/known-bad-prose-fenced-failed.txt")"
STUB_RESULT="$FENCED_FAILED" run_so_pinned dispatch-default.yaml spec-no-egress.md
if trace_has 'second_opinion.invalid' && trace_has 'non-verdict-result' \
   && ! trace_has 'second_opinion.ok'; then
    ok "known-bad prose quoting a fenced status:failed block -> second_opinion.invalid"
else
    bad "known-bad prose quoting a fenced status:failed block -> second_opinion.invalid"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 14j (L2-v8): raw status:"failed" reply that ALSO carries a verdict
# key must still be rejected — `{"status":"failed","verdict":"..."}` must not
# fall through to the verdict-key branch just because `verdict` is non-empty;
# a `failed` status is a task-completion outcome, never an opinion.
FAILED_WITH_VERDICT="$(cat "$SO_FIXTURES/known-bad-failed-with-verdict.txt")"
STUB_RESULT="$FAILED_WITH_VERDICT" run_so_pinned dispatch-default.yaml spec-no-egress.md
if trace_has 'second_opinion.invalid' && trace_has 'non-verdict-result' \
   && ! trace_has 'second_opinion.ok'; then
    ok "known-bad status:failed reply with a verdict key -> second_opinion.invalid"
else
    bad "known-bad status:failed reply with a verdict key -> second_opinion.invalid"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 15 (issue 579): the full leaf result is recoverable, not just the --
# --- 200-char excerpt kept in the trace row's `reason` ----------------------
# A leaf result over 200 chars must still be fully recoverable afterwards: the
# `second_opinion.ok` row's `reason` stays a short excerpt (readability), but
# the row also carries a `decision_ref` pointing at a file under
# `<feature-dir>/second-opinions/` that holds the leaf's FULL, untruncated
# JSON envelope. (wp-15/T5b: LONG_RESULT is now verdict-shaped JSON — a bare
# prose string would now read as a non-verdict — and MARKER sits well past
# character 200 of the whitespace-collapsed result, so its absence from
# `reason` and presence in the decision_ref file is what proves the excerpt
# really stops at 200 chars; a check on the raw $LONG_RESULT string would pass
# vacuously since decision_ref holds the whole JSON-escaped text anyway.)
MARKER="ISSUE579-RECOVERABILITY-MARKER"
FILLER="$(printf 'pad %.0s' $(seq 1 60))"
LONG_RESULT="$(printf '{"status":"success","summary":"%s%s"}' "$FILLER" "$MARKER")"
STUB_RESULT="$LONG_RESULT" run_so_pinned dispatch-default.yaml spec-no-egress.md
DECISION_REF_LINE="$(grep 'second_opinion.ok' "$FEATURE/trace-events.jsonl" | tail -1)"
REF_REL="$(printf '%s' "$DECISION_REF_LINE" | grep -o '"decision_ref":"[^"]*"' | cut -d'"' -f4)"
if [[ -n "$REF_REL" ]] && [[ -f "$FEATURE/$REF_REL" ]] \
   && grep -q "$MARKER" "$FEATURE/$REF_REL" \
   && ! grep -q "$MARKER" "$FEATURE/trace-events.jsonl"; then
    ok "full leaf result recoverable via decision_ref (reason stays a short excerpt)"
else
    bad "full leaf result recoverable via decision_ref (reason stays a short excerpt)"
    echo "  decision_ref: '$REF_REL'"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# --- case 16 (issue 579): the exit-4 budget_exceeded persist site, and -------
# --- skipped rows never carry a decision_ref ---------------------------------
# The `second_opinion.ok` emit for the budget_exceeded/budget_check_failed
# path is a SEPARATE call site from the exit-0 one (case 15 only exercises the
# latter): it must persist and reference the full leaf output too.
STUB_EXIT=4 STUB_REASON=budget_exceeded STUB_RESULT="$LONG_RESULT" \
    run_so_pinned dispatch-default.yaml spec-no-egress.md
BUDGET_LINE="$(grep 'second_opinion.ok' "$FEATURE/trace-events.jsonl" | tail -1)"
BUDGET_REF="$(printf '%s' "$BUDGET_LINE" | grep -o '"decision_ref":"[^"]*"' | cut -d'"' -f4)"
if [[ -n "$BUDGET_REF" ]] && [[ -f "$FEATURE/$BUDGET_REF" ]] \
   && grep -q "$MARKER" "$FEATURE/$BUDGET_REF" \
   && ! grep -q "$MARKER" "$FEATURE/trace-events.jsonl"; then
    ok "exit-4 budget_exceeded also persists + references the full leaf result"
else
    bad "exit-4 budget_exceeded also persists + references the full leaf result"
    echo "  decision_ref: '$BUDGET_REF'"
    cat "$FEATURE/trace-events.jsonl" 2>/dev/null
fi

# a second_opinion.skipped row (leaf never ran to completion) must carry NO
# decision_ref at all — reuse the leaf-exit-1 scenario from case 8.
STUB_EXIT=1 run_so_pinned dispatch-default.yaml spec-no-egress.md
SKIPPED_LINE="$(grep 'second_opinion.skipped' "$FEATURE/trace-events.jsonl" | tail -1)"
if [[ -n "$SKIPPED_LINE" ]] && ! printf '%s' "$SKIPPED_LINE" | grep -q '"decision_ref"'; then
    ok "second_opinion.skipped rows carry no decision_ref"
else
    bad "second_opinion.skipped rows carry no decision_ref"
    echo "  $SKIPPED_LINE"
fi

# ledger accumulated exactly one row per leaf call (cases 2,3,4,6,7,8,10,12,13,
# 14,14a,14b,14c,14d,14e,14f,14g,14h,14i,14j,15,16a,16b = 23; cases 1, 5, 9 and
# 11 never reach the leaf. 16b reaches the leaf — STUB_EXIT=1 — but its
# second_opinion.skipped emit carries no decision_ref, which is exactly the
# case it asserts)
if [[ "$(wc -l < "$GOALFORGE_DISPATCH_LEDGER")" == "23" ]]; then
    ok "ledger row count equals leaf-call count (23)"
else
    bad "ledger row count equals leaf-call count (23): got $(wc -l < "$GOALFORGE_DISPATCH_LEDGER")"
fi

# --- case 17 (wp-15 fix/b4): the SHIPPED dispatch.yaml pins codex/gpt-6-luna
# and carries no ollama providers[] row -----------------------------------
# Reads the real, checked-in references/dispatch.yaml (not a test fixture),
# so a revert of dispatch.yaml back to an ollama-shipped state is caught
# here, not just by eyeballing the diff.
SHIPPED_DISPATCH="$SD/../../references/dispatch.yaml"
SHIPPED_CHECK="$(python3 -c '
import sys
import yaml
with open(sys.argv[1], encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
row = (data.get("stages") or {}).get("second_opinion") or {}
names = [p.get("name") for p in (data.get("providers") or []) if isinstance(p, dict)]
ok = row.get("provider") == "codex" and row.get("model") == "gpt-6-luna" and "ollama" not in names
print("1" if ok else "0")
' "$SHIPPED_DISPATCH" 2>/dev/null)"
if [[ "$SHIPPED_CHECK" == "1" ]]; then
    ok "shipped dispatch.yaml second_opinion row is codex/gpt-6-luna, no ollama providers row"
else
    bad "shipped dispatch.yaml second_opinion row is codex/gpt-6-luna, no ollama providers row"
fi

echo
echo "goalforge-second-opinion.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
