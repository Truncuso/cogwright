#!/usr/bin/env bash
# goalforge-harden-stop.sh — C4 harden stop rule: round counter + token
# ceiling, read from the feature's trace.
#
# spec.md C4 (as amended): tokens are a SOFT sensor — over the threshold the
# run WARNs and continues; the ROUND CAP is hard (max 2 rounds, round 2
# diff-only; a third round parks); a token ceiling set in the environment
# (SDD_HARDEN_TOKEN_CEILING) or in dispatch.yaml (`harden.token_ceiling`) is a
# HARD ceiling and parks on breach. b6: "a harden run on a WP with a BLOCK that survives
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
# Usage: goalforge-harden-stop.sh <wp-dir> [--dispatch <path>]
# Exit 0: round N+1 may run. Also the SOFT-token path: with no hard ceiling
#         configured, tokens above the soft threshold emit one `harden.warn`
#         row and still exit 0 (C4: tokens are a sensor, the round cap is the
#         only default hard park).
# Exit 3: PARK — rounds-so-far >= 2, OR cumulative tokens > a CONFIGURED hard
#         ceiling. Appends a `harden: ceiling-breached, rounds=<N>` row to
#         <wp-dir>/findings.md and emits `harden.parked` (best-effort — a
#         rejected/unavailable emit never changes this exit code).
# Exit 2: internal error (bad usage, wp-dir missing, overview.md unreadable,
#         corrupt trace line count fails to parse) — fail-closed, never a
#         silent pass.
#
# Ceiling knobs: max rounds is fixed at 2 (C4). The token ceiling is HARD only
# when configured: `SDD_HARDEN_TOKEN_CEILING=<N>` (wins) or `harden.token_ceiling:
# <N>` in the dispatch file (`--dispatch <path>`, default the package
# references/dispatch.yaml). With neither set (the shipped `null`), the token
# budget is a soft threshold picked from the WP's `severity`/`register`:
# 300000 for a `severity: HIGH` + `register: production` panel WP, else 60000.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MAX_ROUNDS=2
readonly SOFT_PANEL=300000
readonly SOFT_SINGLE=60000
DISPATCH_PATH="$SCRIPT_DIR/../references/dispatch.yaml"

# Best-effort event emit — never affects this script's exit code. $1 is a JSON
# object on stdin's behalf, already rendered by the caller.
emit_json() {
    local feat_dir="$1" payload="$2" emit
    emit="$SCRIPT_DIR/goalforge-trace-emit"
    [ -x "$emit" ] || return 0
    [ -n "$feat_dir" ] || return 0
    printf '%s' "$payload" | "$emit" --feature-dir "$feat_dir" >/dev/null 2>&1 || true
    return 0
}

emit_event() {
    local type="$1" wp="$2" feat_dir="$3" reason="$4" rounds="$5" payload
    command -v python3 >/dev/null 2>&1 || return 0
    payload="$(TYPE="$type" WP="$wp" REASON="$reason" ROUNDS="$rounds" python3 -c '
import json, os, sys
sys.stdout.write(json.dumps({
    "type": os.environ["TYPE"],
    "wp": os.environ["WP"],
    "reason": os.environ["REASON"],
    "rounds": int(os.environ["ROUNDS"]),
}))
' 2>/dev/null)" || return 0
    emit_json "$feat_dir" "$payload"
}

emit_warn() {
    local wp="$1" feat_dir="$2" tokens="$3" threshold="$4" payload
    command -v python3 >/dev/null 2>&1 || return 0
    payload="$(WP="$wp" TOKENS="$tokens" THRESHOLD="$threshold" python3 -c '
import json, os, sys
sys.stdout.write(json.dumps({
    "type": "harden.warn",
    "wp": os.environ["WP"],
    "reason": "tokens-above-soft-threshold",
    "tokens": int(os.environ["TOKENS"]),
    "threshold": int(os.environ["THRESHOLD"]),
}))
' 2>/dev/null)" || return 0
    emit_json "$feat_dir" "$payload"
}

# `harden.token_ceiling` from the dispatch file. Prints the integer when the
# key is an int; prints nothing (no hard ceiling) when the file is absent,
# unreadable, invalid, or the key is null/non-integer.
config_ceiling() {
    local path="$1"
    [ -f "$path" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    python3 - "$path" <<'PY' 2>/dev/null || true
import sys
import yaml
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except (OSError, yaml.YAMLError):
    sys.exit(0)
ceiling = (data.get("harden") or {}).get("token_ceiling")
if isinstance(ceiling, int) and not isinstance(ceiling, bool):
    print(ceiling)
PY
}

# Soft threshold from the WP overview.md frontmatter: the panel band (300k)
# only for severity HIGH + register production, else the single-pass 60k.
soft_threshold() {
    local ov="$1" sev reg
    sev="$(awk 'NR==1 && $0=="---"{infm=1;next} infm && $0=="---"{exit} infm && /^severity:[ \t]*/ {sub(/^severity:[ \t]*/,""); gsub(/["'"'"']/,""); print; exit}' "$ov" 2>/dev/null)"
    reg="$(awk 'NR==1 && $0=="---"{infm=1;next} infm && $0=="---"{exit} infm && /^register:[ \t]*/ {sub(/^register:[ \t]*/,""); gsub(/["'"'"']/,""); print; exit}' "$ov" 2>/dev/null)"
    if [ "$sev" = "HIGH" ] && [ "$reg" = "production" ]; then
        printf '%s' "$SOFT_PANEL"
    else
        printf '%s' "$SOFT_SINGLE"
    fi
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

    # Hard ceiling only when configured: env wins over the dispatch file.
    local hard=""
    if [ -n "${SDD_HARDEN_TOKEN_CEILING:-}" ]; then
        hard="$SDD_HARDEN_TOKEN_CEILING"
    else
        hard="$(config_ceiling "$DISPATCH_PATH")"
    fi
    case "$hard" in *[!0-9]*) hard="" ;; esac

    if [ "$rounds" -ge "$MAX_ROUNDS" ] || { [ -n "$hard" ] && [ "$tokens" -gt "$hard" ]; }; then
        local reason="harden: ceiling-breached, rounds=$rounds"
        {
            [ -f "$wp_dir/findings.md" ] || printf '# findings\n\n## Harden Stop\n\n' > "$wp_dir/findings.md"
            printf -- '- %s (tokens=%s, ceiling=%s)\n' "$reason" "$tokens" "${hard:-none}" >> "$wp_dir/findings.md"
        }
        echo "goalforge-harden-stop: PARK — $wp: $reason (tokens=$tokens, ceiling=${hard:-none})" >&2
        emit_event "harden.parked" "$wp" "$feat_dir" "$reason" "$rounds"
        return 3
    fi

    # No hard ceiling: tokens are a soft sensor — WARN and continue.
    if [ -z "$hard" ]; then
        local threshold
        threshold="$(soft_threshold "$ov")"
        if [ "$tokens" -gt "$threshold" ]; then
            echo "goalforge-harden-stop: WARN — $wp: tokens=$tokens above soft threshold $threshold" >&2
            emit_warn "$wp" "$feat_dir" "$tokens" "$threshold"
        fi
    fi

    return 0
}

usage() { echo "usage: goalforge-harden-stop.sh <wp-dir> [--dispatch <path>]" >&2; }

WP_DIR=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dispatch)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            DISPATCH_PATH="$2"; shift 2 ;;
        -*) usage; exit 2 ;;
        *)
            [ -z "$WP_DIR" ] || { usage; exit 2; }
            WP_DIR="$1"; shift ;;
    esac
done
[ -n "$WP_DIR" ] || { usage; exit 2; }
run "$WP_DIR"; exit $?
