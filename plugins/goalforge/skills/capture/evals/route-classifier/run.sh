#!/usr/bin/env bash
# route-classifier/run.sh — deterministic fixture suite for goalforge-route.sh.
#
# Two modes:
#   (default)          drive every fixture through goalforge-route.sh and assert
#                      its expected route/confidence; also run the classifier's
#                      own --self-test. Exit 0 only when all cases pass.
#   --emit <fixture>   simulate goalforge-capture: classify the named fixture and
#                      print the overview frontmatter it would stamp — route: +
#                      the derived execution_plan: block. Consumed as DATA by
#                      task-02 (--emit standard) and task-03 (--emit one-go-shaped)
#                      behavioral checks.
#
# Fixtures live under fixtures/. Cases (a-f) mirror the WP goal.verification.
set -uo pipefail
: "${COGWRIGHT_ROOT:=$HOME/10_projects/cogwright}"

HERE="$(cd "$(dirname "$0")" && pwd)"
FIX="$HERE/fixtures"
ROUTE_SH="$COGWRIGHT_ROOT/plugins/goalforge/scripts/goalforge-route.sh"

# --- execution_plan derivation (mirrors capture/SKILL.md Step 4d) -----------
# Pure function of (route, variant). variant=one-go only refines fast's dispatch.
emit_plan() {
    local route="$1" variant="${2:-plain}"
    case "$route" in
        fast)
            local impl="inline"
            [[ "$variant" == "one-go" ]] && impl="agent"
            cat <<EOF
route: fast
execution_plan:
  steps: [implement, verify]
  dispatch: {implement: $impl, verify: inline}
  parallel: []
  tiers: {implement: sonnet, judge: opus}
EOF
            ;;
        standard)
            cat <<'EOF'
route: standard
execution_plan:
  steps: [spec, decompose, harden, execute, verify]
  dispatch: {spec: inline, decompose: inline, harden: inline, execute: inline, verify: inline}
  parallel: []
  tiers: {explore: haiku, spec_author: sonnet, judge: opus, boilerplate: haiku}
EOF
            ;;
        wave)
            cat <<'EOF'
route: wave
execution_plan:
  steps: [spec, decompose, harden, execute, verify]
  dispatch: {spec: agent, decompose: agent, harden: inline, execute: agent, verify: inline}
  parallel: [[spec], [decompose, hygiene]]
  tiers: {explore: sonnet, spec_author: opus, judge: opus, boilerplate: haiku}
EOF
            ;;
        *) echo "emit_plan: unknown route '$route'" >&2; return 1 ;;
    esac
}

# --emit <fixture>: classify then print the stamped frontmatter (route + plan).
run_emit() {
    local name="$1" fixture="$FIX/$1.md"
    [[ -f "$fixture" ]] || { echo "no such fixture: $name" >&2; exit 1; }
    local out route variant="plain"
    out="$(bash "$ROUTE_SH" "$fixture")" || { echo "classify failed: $name" >&2; exit 1; }
    route="$(echo "$out" | command jq -r .route)"
    [[ "$name" == "one-go-shaped" ]] && variant="one-go"
    emit_plan "$route" "$variant"
}

# --- default suite ----------------------------------------------------------
run_suite() {
    local p=0 f=0 out
    field() { echo "$1" | command jq -r "$2"; }
    expect() {  # <fixture> <expected-route> <expected-confidence> <desc>
        out="$(bash "$ROUTE_SH" "$FIX/$1.md")"
        if [[ "$(field "$out" .route)" == "$2" && "$(field "$out" .confidence)" == "$3" ]]; then
            echo "  PASS: $4"; p=$((p+1))
        else
            echo "  FAIL: $4 -> $out"; f=$((f+1))
        fi
    }

    echo "=== route-classifier fixture suite ==="

    # (a) 3 canonical fixtures classify to the expected route
    expect fast     fast     clear      "a1 canonical fast -> fast/clear"
    expect standard standard clear      "a2 canonical standard -> standard/clear"
    expect wave     wave     clear      "a3 canonical wave -> wave/clear"

    # (b) legacy vocab normalizes on read, confidence: pinned
    expect legacy-full   standard pinned "b1 legacy full -> standard/pinned"
    expect legacy-one-go fast     pinned "b2 legacy one-go -> fast/pinned"

    # (c) weak-signal-only -> borderline (safe default standard)
    expect borderline standard borderline "c borderline weak-signal -> standard/borderline"

    # (d) pinned NEW-vocab route (wave, NOT fast) echoes as-is
    expect pinned-new-vocab wave pinned "d pinned new-vocab wave -> wave/pinned"

    # (e) one-go-shaped classifies to fast; its emitted plan has implement: agent, no spec
    expect one-go-shaped fast pinned "e1 one-go-shaped -> fast/pinned"
    out="$(run_emit one-go-shaped)"
    if echo "$out" | grep -Eq '^route:[[:space:]]*fast\b' \
       && echo "$out" | grep -Eq 'implement:[[:space:]]*agent' \
       && ! echo "$out" | grep -Eq 'steps:.*\bspec\b'; then
        echo "  PASS: e2 one-go-shaped emit -> fast + implement:agent, no spec"; p=$((p+1))
    else
        echo "  FAIL: e2 one-go-shaped emit -> $out"; f=$((f+1))
    fi

    # standard emit round-trip (task-02 shape)
    out="$(run_emit standard)"
    if echo "$out" | grep -Eq '^route:[[:space:]]*(fast|standard|wave)\b' \
       && echo "$out" | grep -Eq '^execution_plan:' \
       && echo "$out" | grep -Eq '^[[:space:]]+steps:[[:space:]]*\['; then
        echo "  PASS: emit standard -> route + well-formed execution_plan"; p=$((p+1))
    else
        echo "  FAIL: emit standard -> $out"; f=$((f+1))
    fi

    # wave emit round-trip: route wave + all 5 dispatch keys + wave tiers
    # (guards the wave emit path against silently drifting from SKILL.md Step 4d).
    out="$(run_emit wave)"
    if echo "$out" | grep -Eq '^route:[[:space:]]*wave\b' \
       && echo "$out" | grep -Eq 'dispatch:.*spec:[[:space:]]*agent' \
       && echo "$out" | grep -Eq 'dispatch:.*decompose:[[:space:]]*agent' \
       && echo "$out" | grep -Eq 'dispatch:.*harden:[[:space:]]*inline' \
       && echo "$out" | grep -Eq 'dispatch:.*execute:[[:space:]]*agent' \
       && echo "$out" | grep -Eq 'dispatch:.*verify:[[:space:]]*inline' \
       && echo "$out" | grep -Eq 'tiers:.*explore:[[:space:]]*sonnet' \
       && echo "$out" | grep -Eq 'tiers:.*spec_author:[[:space:]]*opus' \
       && echo "$out" | grep -Eq 'tiers:.*judge:[[:space:]]*opus' \
       && echo "$out" | grep -Eq 'tiers:.*boilerplate:[[:space:]]*haiku'; then
        echo "  PASS: emit wave -> route wave + 5-key dispatch + wave tiers"; p=$((p+1))
    else
        echo "  FAIL: emit wave -> $out"; f=$((f+1))
    fi

    # (f) classifier self-test green
    if bash "$ROUTE_SH" --self-test >/dev/null 2>&1; then
        echo "  PASS: f goalforge-route.sh --self-test green"; p=$((p+1))
    else
        echo "  FAIL: f goalforge-route.sh --self-test"; f=$((f+1))
    fi

    echo ""
    echo "Results: $p passed, $f failed"
    [[ "$f" -eq 0 ]]
}

case "${1:-}" in
    --emit) [[ -n "${2:-}" ]] || { echo "usage: run.sh --emit <fixture>" >&2; exit 1; }
            run_emit "$2" ;;
    "")     run_suite; exit $? ;;
    *)      echo "usage: run.sh [--emit <fixture>]" >&2; exit 1 ;;
esac
