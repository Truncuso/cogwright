#!/usr/bin/env bash
# goalforge-launch-gate.sh — PreToolUse guard on Agent/Workflow dispatch.
#
# Refuses to LAUNCH a new sub-agent or workflow when the remaining session
# quota is already below the threshold. Two sonnet agents died mid-WP on the
# 5h limit (HTTP 429) on 2026-09-09; a dispatch launched at 3% remaining does
# not finish, it just burns the rest of the window and loses its work.
#
# Contract:
#   threshold   $GOALFORGE_LAUNCH_THRESHOLD_PCT, DEFAULT 10 (README §Install).
#               Deliberately NOT a references/dispatch.yaml key — that file has
#               no such key and is owned elsewhere.
#   quota       read through hooks/goalforge-quota-read.sh, the ONE adapter.
#               `{}` (unknown) or an unparseable figure ⇒ exit 0, SILENT. A
#               quota source that cannot be read never blocks the user's work.
#   block       exit 2 with the remaining percentage AND the threshold on
#               stderr. NO trace event is emitted: `gate.result` requires a
#               `wp` field and the emitter a `--feature-dir`, and a PreToolUse
#               hook on a dispatch has neither.
#   warn        the explanatory WARN block prints ONCE per session, marked by
#               a file under $GOALFORGE_LAUNCH_MARKER_DIR (default
#               ${TMPDIR:-/tmp}/goalforge-launch-gate/<session-id>). The
#               directory is created by this hook and reaped by the OS — never
#               by goalforge. Marker gone ⇒ fresh session ⇒ the WARN prints
#               again. Subsequent blocks still print the one-line BLOCK.
#   kill switch GOALFORGE_LAUNCH_GATE=0 disables the gate entirely: exit 0,
#               print nothing, whatever the quota says. A guardrail that can
#               refuse the user's OWN dispatch must be switchable off without
#               editing hooks.json (spatiotemporal-composability: teardown of
#               granted authority is an invariant, not a nicety). It is
#               documented in README §Install and NEVER named on stderr: a
#               PreToolUse hook's stderr reaches the model, and a guardrail
#               that prints its own bypass is not a guardrail (V5).
#
# SCOPE: hooks.json PreToolUse, matcher `Agent|Workflow`.
#
# Usage:
#   <PreToolUse JSON on stdin> | goalforge-launch-gate.sh
#   goalforge-launch-gate.sh --self-test
#
# ZERO-BREAKAGE: every internal error exits 0. Exit 2 happens only on a
# confirmed under-threshold reading.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")" && pwd)"
SELF="$HOOK_DIR/$(basename "${BASH_SOURCE[0]}")"
QUOTA_READ="$HOOK_DIR/goalforge-quota-read.sh"

DEFAULT_THRESHOLD=10

# Print the threshold: the override when it is a plain non-negative integer,
# else the default (a typo must not silently disable or maximise the gate).
resolve_threshold() {
    local t="${GOALFORGE_LAUNCH_THRESHOLD_PCT:-}"
    case "$t" in
        ''|*[!0-9]*) printf '%s' "$DEFAULT_THRESHOLD" ;;
        *)           printf '%s' "$t" ;;
    esac
}

# Print the session id from the PreToolUse payload ($1), or `default`.
# Sanitised to [A-Za-z0-9._-] so it can only ever name a leaf directory.
session_id_from() {
    local raw="$1" rest id
    rest="${raw#*\"session_id\":}"
    [ "$rest" = "$raw" ] && { printf 'default'; return 0; }
    rest="${rest#"${rest%%[![:space:]]*}"}"
    case "$rest" in \"*) rest="${rest#\"}"; id="${rest%%\"*}" ;; *) printf 'default'; return 0 ;; esac
    id="$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '_')"
    # `.` and `..` survive the character filter but are not leaf names: they
    # would place the marker in, or one level ABOVE, the marker dir and make
    # the once-per-session marker collide across sessions (verify round 1, V7).
    case "$id" in ''|.|..) id=default ;; esac
    printf '%s' "$id"
}

# Print the five-hour remaining percentage as an integer, or nothing when the
# adapter reports `{}` / anything unparseable.
# The adapter's JSON is passed through the ENVIRONMENT, not a pipe: this
# python3 invocation reads its program from a heredoc, so a piped stdin would
# be shadowed by that redirect and the parser would see an empty document.
five_h_remaining_pct() {
    local quota
    [ -x "$QUOTA_READ" ] || [ -f "$QUOTA_READ" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    quota="$(bash "$QUOTA_READ" 2>/dev/null)" || return 0
    GF_QUOTA_JSON="$quota" python3 - <<'PY' 2>/dev/null
import json, os, sys
try:
    data = json.loads(os.environ.get("GF_QUOTA_JSON", ""))
except Exception:
    sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
val = data.get("five_h_remaining_pct")
if isinstance(val, bool) or not isinstance(val, (int, float)):
    sys.exit(0)
print(int(val))
PY
}

self_test() {
    local p=0 f=0 d out rc
    ok() { echo "  PASS: $1"; p=$((p+1)); }
    no() { echo "  FAIL: $1"; f=$((f+1)); }
    echo "=== goalforge-launch-gate.sh --self-test ==="
    d="$(mktemp -d)"
    trap 'rm -rf "$d"' RETURN

    [ "$(GOALFORGE_LAUNCH_THRESHOLD_PCT=25 resolve_threshold)" = 25 ] \
        && ok "threshold override honoured" || no "threshold override ignored"
    [ "$(GOALFORGE_LAUNCH_THRESHOLD_PCT=oops resolve_threshold)" = "$DEFAULT_THRESHOLD" ] \
        && ok "garbage threshold falls back to the default" || no "garbage threshold not defaulted"
    [ "$(unset GOALFORGE_LAUNCH_THRESHOLD_PCT; resolve_threshold)" = "$DEFAULT_THRESHOLD" ] \
        && ok "default threshold is $DEFAULT_THRESHOLD" || no "default threshold wrong"

    out="$(session_id_from '{"session_id":"ab/cd","tool_name":"Agent"}')"
    [ "$out" = "ab_cd" ] && ok "session id sanitised to one leaf segment" || no "session id got '$out'"
    out="$(session_id_from '{"tool_name":"Agent"}')"
    [ "$out" = "default" ] && ok "absent session id -> default" || no "absent session id got '$out'"
    out="$(session_id_from '{"session_id":"..","tool_name":"Agent"}')"
    [ "$out" = "default" ] && ok "session id '..' -> default" || no "session id '..' got '$out'"
    out="$(session_id_from '{"session_id":".","tool_name":"Agent"}')"
    [ "$out" = "default" ] && ok "session id '.' -> default" || no "session id '.' got '$out'"

    printf '{"five_h_remaining_pct": 3}\n' > "$d/low.json"
    rc=0
    out="$(printf '{"tool_name":"Agent","session_id":"s1"}' \
        | GOALFORGE_QUOTA_FIXTURE="$d/low.json" GOALFORGE_LAUNCH_MARKER_DIR="$d/m1" \
          bash "$SELF" 2>&1)" || rc=$?
    [ "$rc" -eq 2 ] && ok "under threshold -> exit 2" || no "under threshold -> exit $rc (want 2)"

    echo ""
    echo "Results: $p passed, $f failed"
    [ "$f" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

# ── Kill switch, evaluated before anything else can print or block ──────────
[ "${GOALFORGE_LAUNCH_GATE:-1}" = "0" ] && exit 0

RAW="$(cat 2>/dev/null || true)"

PCT="$(five_h_remaining_pct)"
case "${PCT:-}" in
    ''|*[!0-9]*) exit 0 ;;          # unknown / unparseable -> never block
esac

THRESHOLD="$(resolve_threshold)"
[ "$PCT" -ge "$THRESHOLD" ] && exit 0

SESSION="$(session_id_from "$RAW")"
MARKER_DIR="${GOALFORGE_LAUNCH_MARKER_DIR:-${TMPDIR:-/tmp}/goalforge-launch-gate/$SESSION}"
MARKER="$MARKER_DIR/warned"

if [ ! -f "$MARKER" ]; then
    echo "goalforge-launch-gate: WARN — this session has ${PCT}% of the 5h window left (threshold ${THRESHOLD}%)." >&2
    echo "  A dispatch launched below the threshold typically dies mid-run on the rate limit and loses its work." >&2
    echo "  Finish in-session, park a handoff, or wait for the window to reset." >&2
    echo "  Raise or lower the bar with GOALFORGE_LAUNCH_THRESHOLD_PCT." >&2
    mkdir -p "$MARKER_DIR" 2>/dev/null && : > "$MARKER" 2>/dev/null || true
fi

echo "goalforge-launch-gate: BLOCK — ${PCT}% of the 5h window remains, below the ${THRESHOLD}% launch threshold; dispatch refused." >&2
exit 2
