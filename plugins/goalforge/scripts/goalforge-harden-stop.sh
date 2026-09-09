#!/usr/bin/env bash
# goalforge-harden-stop.sh — C4 harden stop rule: round counter + token
# ceiling, read from the feature's trace.
#
# spec.md C4: "Harden: max 2 rounds, round 2 diff-only; token ceiling 60k per
# WP; breach parks." b6: "a harden run on a WP with a BLOCK that survives
# round 2 ... round 3 would start ... harden parks with
# `harden: ceiling-breached, rounds=2` and a findings.md row; no third review
# call."
#
# Source of truth: `harden.round` rows in the feature's `trace-events.jsonl`
# (one per completed harden round), filtered to this WP. This event type is
# NOT YET in the trace-events.md schema/enum as of this script (T14) — it is
# the minimal shape this gate needs and is documented here for T20 to
# register:
#
#   { "type": "harden.round", "wp": "<wp-slug>", "round": <int>=1,
#     "tokens": <int>=0 }
#
# plus the envelope (seq/ts/schema_version) and attribution fields every
# other event carries. The harden skill (T13) is the intended producer, one
# row per completed round.
#
# Usage: goalforge-harden-stop.sh <wp-dir>
# Exit 0: round N+1 may run (rounds-so-far < ceiling AND tokens <= ceiling).
# Exit 3: PARK — rounds-so-far >= 2, OR cumulative tokens > ceiling. Appends
#         a `harden: ceiling-breached, rounds=<N>` row to <wp-dir>/findings.md
#         and emits `harden.parked` (best-effort; not yet schema-registered,
#         see T20 — a rejected/unavailable emit never changes this exit code).
# Exit 2: internal error (bad usage, wp-dir missing, overview.md unreadable,
#         corrupt trace line count fails to parse) — fail-closed, never a
#         silent pass.
#
# Ceiling knobs: max rounds is fixed at 2 (C4). Token ceiling defaults to
# 60000 (C4's "60k per WP"), overridable via SDD_HARDEN_TOKEN_CEILING.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MAX_ROUNDS=2
TOKEN_CEILING="${SDD_HARDEN_TOKEN_CEILING:-60000}"

# Best-effort event emit — never affects this script's exit code.
emit_event() {
    local type="$1" wp="$2" feat_dir="$3" reason="$4" rounds="$5" emit
    emit="$SCRIPT_DIR/goalforge-trace-emit"
    [ -x "$emit" ] || return 0
    [ -n "$feat_dir" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    TYPE="$type" WP="$wp" REASON="$reason" ROUNDS="$rounds" python3 -c '
import json, os, sys
sys.stdout.write(json.dumps({
    "type": os.environ["TYPE"],
    "wp": os.environ["WP"],
    "reason": os.environ["REASON"],
    "rounds": int(os.environ["ROUNDS"]),
}))
' 2>/dev/null | "$emit" --feature-dir "$feat_dir" >/dev/null 2>&1 || true
    return 0
}

wp_name() {
    local f="$1" n
    n="$(awk 'NR==1 && $0=="---"{infm=1;next} infm && $0=="---"{exit} infm && /^name:[ \t]*/ {sub(/^name:[ \t]*/,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit}' "$f" 2>/dev/null)"
    [ -n "$n" ] && printf '%s' "$n" || basename "$(dirname "$f")"
}

# Reads <feat-dir>/trace-events.jsonl, sums rounds + tokens for `harden.round`
# rows matching $wp. Prints "<rounds> <tokens>" on success. A missing trace
# file is zero rounds (round 1 may always run). A corrupt/unreadable trace
# that DOES exist is an internal error (empty stdout, caller sees it).
count_rounds() {
    local trace="$1" wp="$2"
    [ -f "$trace" ] || { echo "0 0"; return 0; }
    python3 - "$trace" "$wp" <<'PY'
import json, sys
trace, wp = sys.argv[1], sys.argv[2]
rounds = 0
tokens = 0
try:
    with open(trace, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
except OSError:
    sys.exit(1)
for i, raw in enumerate(lines):
    if not raw.strip():
        continue
    try:
        row = json.loads(raw)
    except json.JSONDecodeError:
        if i == len(lines) - 1:
            continue  # torn-tail: last line only, tolerated
        sys.exit(1)   # corrupt non-trailing line -> internal error
    if not isinstance(row, dict):
        continue
    if row.get("type") == "harden.round" and row.get("wp") == wp:
        rounds += 1
        t = row.get("tokens", 0)
        if isinstance(t, (int, float)) and not isinstance(t, bool):
            tokens += t
print(f"{rounds} {int(tokens)}")
PY
}

run() {
    local wp_dir="$1" ov feat_dir wp trace out rounds tokens

    if [ ! -d "$wp_dir" ]; then
        echo "goalforge-harden-stop: internal error — not a directory: $wp_dir" >&2
        return 2
    fi
    ov="$wp_dir/overview.md"
    if [ ! -f "$ov" ]; then
        echo "goalforge-harden-stop: internal error — no overview.md in $wp_dir" >&2
        return 2
    fi

    wp="$(wp_name "$ov")"
    feat_dir="$(cd "$wp_dir/.." && pwd)"
    trace="$feat_dir/trace-events.jsonl"

    out="$(count_rounds "$trace" "$wp")" || {
        echo "goalforge-harden-stop: internal error — unreadable/corrupt trace: $trace" >&2
        return 2
    }
    rounds="${out%% *}"
    tokens="${out##* }"
    case "$rounds$tokens" in *[!0-9]*) echo "goalforge-harden-stop: internal error — bad trace read" >&2; return 2 ;; esac

    if [ "$rounds" -ge "$MAX_ROUNDS" ] || [ "$tokens" -gt "$TOKEN_CEILING" ]; then
        local reason="harden: ceiling-breached, rounds=$rounds"
        {
            [ -f "$wp_dir/findings.md" ] || printf '# findings\n\n## Harden Stop\n\n' > "$wp_dir/findings.md"
            printf -- '- %s (tokens=%s, ceiling=%s)\n' "$reason" "$tokens" "$TOKEN_CEILING" >> "$wp_dir/findings.md"
        }
        echo "goalforge-harden-stop: PARK — $wp: $reason (tokens=$tokens, ceiling=$TOKEN_CEILING)" >&2
        emit_event "harden.parked" "$wp" "$feat_dir" "$reason" "$rounds"
        return 3
    fi

    return 0
}

case "${1:-}" in
    "") echo "usage: goalforge-harden-stop.sh <wp-dir>" >&2; exit 2 ;;
    *)  run "$1"; exit $? ;;
esac
