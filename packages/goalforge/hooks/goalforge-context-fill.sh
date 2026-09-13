#!/usr/bin/env bash
# goalforge-context-fill.sh — SessionStart context-fill sensor.
#
# Prints ONE line estimating how full the context window already is, from the
# byte size of the session transcript. A resumed or compacted session starts
# with a transcript that is already large; knowing that at line one is what
# lets a skill decide to park a handoff instead of opening a third work loop.
#
# This WP ships the SENSOR only. The consumer (sprint/autopilot handing off at
# ~60%) is a separate change elsewhere.
#
# Estimate: bytes / $GOALFORGE_CONTEXT_BUDGET_BYTES. The default 800000 is
# 200k tokens at the usual ~4 bytes/token — an ESTIMATE, stated as one, never
# a billing figure. It is monotone in transcript size, which is the only
# property anything downstream relies on.
#
# Inputs:
#   stdin                            SessionStart JSON (reads `transcript_path`)
#   GOALFORGE_TRANSCRIPT_FIXTURE     override the transcript path (tests)
#   GOALFORGE_CONTEXT_BUDGET_BYTES   override the denominator
#
# No transcript (absent path, unreadable, or none in the payload) ⇒ prints
# NOTHING. ZERO-BREAKAGE: always exits 0.
#
# Usage:
#   <SessionStart JSON on stdin> | goalforge-context-fill.sh
#   goalforge-context-fill.sh --self-test
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")" && pwd)"
SELF="$HOOK_DIR/$(basename "${BASH_SOURCE[0]}")"

DEFAULT_BUDGET_BYTES=800000

resolve_budget() {
    local b="${GOALFORGE_CONTEXT_BUDGET_BYTES:-}"
    case "$b" in
        ''|*[!0-9]*|0) printf '%s' "$DEFAULT_BUDGET_BYTES" ;;
        *)             printf '%s' "$b" ;;
    esac
}

# Print the transcript path from the payload ($1), or nothing.
transcript_from() {
    local raw="$1" rest fp
    rest="${raw#*\"transcript_path\":}"
    [ "$rest" = "$raw" ] && return 0
    rest="${rest#"${rest%%[![:space:]]*}"}"
    case "$rest" in \"*) rest="${rest#\"}"; fp="${rest%%\"*}" ;; *) return 0 ;; esac
    case "$fp" in *\\*) return 0 ;; esac      # escaped path: not ours to decode
    printf '%s' "$fp"
}

# Print the fill percentage to one decimal place for <bytes> ($1), capped at
# 100.0. One decimal is load-bearing: two transcripts of genuinely different
# size must report different numbers, and integer rounding hides small deltas.
fill_pct() {
    local bytes="$1" budget
    budget="$(resolve_budget)"
    awk -v b="$bytes" -v cap="$budget" 'BEGIN {
        p = (b * 100.0) / cap
        if (p > 100) p = 100
        printf "%.1f", p
    }'
}

self_test() {
    local p=0 f=0 d out small large
    ok() { echo "  PASS: $1"; p=$((p+1)); }
    no() { echo "  FAIL: $1"; f=$((f+1)); }
    echo "=== goalforge-context-fill.sh --self-test ==="
    d="$(mktemp -d)"
    trap 'rm -rf "$d"' RETURN

    head -c 20000 /dev/zero | tr '\0' 'x' > "$d/small.jsonl"
    head -c 80000 /dev/zero | tr '\0' 'x' > "$d/large.jsonl"
    small="$(GOALFORGE_TRANSCRIPT_FIXTURE="$d/small.jsonl" bash "$SELF" </dev/null)"
    large="$(GOALFORGE_TRANSCRIPT_FIXTURE="$d/large.jsonl" bash "$SELF" </dev/null)"
    [ -n "$small" ] && [ -n "$large" ] && [ "$small" != "$large" ] \
        && ok "4x transcript size -> different line" \
        || no "sizes did not change the line ('$small' vs '$large')"

    out="$(GOALFORGE_TRANSCRIPT_FIXTURE="$d/absent.jsonl" bash "$SELF" </dev/null)"
    [ -z "$out" ] && ok "absent transcript -> prints nothing" || no "absent transcript printed '$out'"

    out="$(transcript_from '{"transcript_path":"/x/y.jsonl","source":"startup"}')"
    [ "$out" = "/x/y.jsonl" ] && ok "transcript_path parsed from payload" || no "parsed '$out'"

    echo ""
    echo "Results: $p passed, $f failed"
    [ "$f" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

RAW="$(cat 2>/dev/null || true)"
TRANSCRIPT="${GOALFORGE_TRANSCRIPT_FIXTURE:-$(transcript_from "$RAW")}"
[ -n "${TRANSCRIPT:-}" ] || exit 0
[ -f "$TRANSCRIPT" ] || exit 0

BYTES="$(wc -c < "$TRANSCRIPT" 2>/dev/null | tr -d '[:space:]')"
case "${BYTES:-}" in ''|*[!0-9]*) exit 0 ;; esac
command -v awk >/dev/null 2>&1 || exit 0

echo "goalforge: context fill ~$(fill_pct "$BYTES")% of the estimated window ($BYTES transcript bytes)"
exit 0
