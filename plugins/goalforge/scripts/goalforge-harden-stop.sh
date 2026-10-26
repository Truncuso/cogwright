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
#        goalforge-harden-stop.sh --reset --reason <text> --decision-ref <path> <wp-dir>
# Exit 0: round N+1 may run. Also the SOFT-token path: with no hard ceiling
#         configured, tokens above the soft threshold emit one `harden.warn`
#         row and still exit 0 (C4: tokens are a sensor, the round cap is the
#         only default hard park).
# Exit 3: PARK — rounds-so-far >= 2, OR cumulative tokens > a CONFIGURED hard
#         ceiling. Appends a `harden: ceiling-breached, rounds=<N>` row to
#         <wp-dir>/findings.md and emits `harden.parked` (best-effort — a
#         rejected/unavailable emit never changes this exit code); a WP whose
#         last `harden.parked` row is already later than its last
#         `harden.reset` row is STICKY — already parked — and this exit is
#         reached with NEITHER write repeated (wp-14, idempotent park).
# Exit 2: internal error (bad usage, wp-dir missing, overview.md unreadable,
#         corrupt trace line count fails to parse) — fail-closed, never a
#         silent pass.
#
# --reset mode (wp-14): re-enters a WP parked by the round cap on a recorded
# human ruling. `--decision-ref` is required and admission is fail-closed —
# the mechanism is documented at do_reset() below. Two exit codes only:
#   0  admitted — exactly one new `harden.reset` row for this WP is now in
#      the trace, read back after the emit.
#   2  every failure, told apart by a stable stderr prefix:
#      `goalforge-harden-stop: --reset refused — <reason>` for a POLICY
#      refusal (bad/missing --reason or --decision-ref, content, freshness,
#      not-currently-parked, wrong park-seq, out-of-WP decision-ref);
#      `goalforge-harden-stop: internal error — <reason>` for an internal
#      failure (corrupt trace, no python3, a failed lock or read-back).
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

# The ONE trace reader. Every consumer below (count_rounds, the `--reset`
# admission scan, the post-emit read-back) goes through it, so they share a
# single torn-tail policy: a JSON error on the LAST line is tolerated (a
# crash-mid-write fragment, per `goalforge-trace-emit`'s isolation rule), a
# JSON error on any EARLIER line is an internal error (exit 1). Blank and
# non-object lines yield None, so indices stay faithful to file line numbers.
JSONL_READER='
import json, os, sys

def _corrupt(path, i):
    sys.stderr.write(
        "goalforge-harden-stop: internal error — corrupt trace line %d in %s\n"
        % (i + 1, path))
    sys.exit(1)

def read_rows(path):
    """Yield (index, row-or-None) for every line of a JSONL trace.

    Torn-tail policy (T11, matching the goalforge-trace-emit isolation
    contract): an unparseable line is tolerated when it is the LAST line of
    the file, or when the line directly after it parses as a JSON object (the
    emitter prepends a newline before an append so a crash-mid-write
    fragment stays isolated on its own line, ahead of the next valid row).
    Any other unparseable line is real corruption -- an internal error.

    Reads bytes and decodes PER LINE (gate-B lap-3 MEDIUM (b)): a crash
    mid-write can tear a multibyte UTF-8 character in half, and a whole-file
    strict decode would raise UnicodeDecodeError before any line-level
    torn-tail handling ever runs. A UnicodeDecodeError on a given line is
    treated exactly like a JSONDecodeError under the same rule.
    """
    try:
        with open(path, "rb") as fh:
            raw_lines = fh.read().splitlines()
    except OSError as exc:
        sys.stderr.write(
            "goalforge-harden-stop: internal error — cannot read trace: "
            "%s (%s)\n" % (path, exc))
        sys.exit(1)

    def _decode_and_parse(raw_bytes):
        return json.loads(raw_bytes.decode("utf-8"))

    n = len(raw_lines)
    for i, raw_bytes in enumerate(raw_lines):
        if not raw_bytes.strip():
            yield i, None
            continue
        try:
            row = _decode_and_parse(raw_bytes)
        except (UnicodeDecodeError, json.JSONDecodeError):
            if i == n - 1:
                yield i, None
                continue
            try:
                nxt_obj = _decode_and_parse(raw_lines[i + 1])
            except (UnicodeDecodeError, json.JSONDecodeError):
                nxt_obj = None
            if isinstance(nxt_obj, dict):
                yield i, None
                continue
            _corrupt(path, i)
        yield i, row if isinstance(row, dict) else None
'

# run_py <consumer-source> [argv...] — the reader plus one consumer, one python3.
run_py() {
    local src="$1"; shift
    python3 -c "$JSONL_READER
$src" "$@"
}

# Reads <feat-dir>/trace-events.jsonl, sums rounds + tokens for `harden.round`
# rows matching $wp — counting only rows AFTER the last HONOURED `harden.reset`
# row for this WP (wp-14: a reset restarts both the round count and the token
# total). A `harden.reset` row is honoured (T10/M1) only when the NEAREST
# EARLIER same-WP row of type `harden.parked`/`harden.reset` is itself a
# `harden.parked` row P, and the reset's `reason` cites the literal
# `park-seq=<P.seq>` with no digit directly after it — a reset that does not
# follow its own park, or cites the wrong park, is a no-op for this count. A
# trace with no HONOURED reset row for the WP counts from the start,
# unchanged. Prints "<rounds> <tokens>" on success. A missing trace file is
# zero rounds (round 1 may always run). A corrupt/unreadable trace that DOES
# exist is an internal error (empty stdout, caller sees it).
count_rounds() {
    local trace="$1" wp="$2"
    [ -f "$trace" ] || { echo "0 0"; return 0; }
    WP="$wp" run_py '
import re

wp = os.environ["WP"]
rows = list(read_rows(sys.argv[1]))

last_wp_type = None   # nearest EARLIER same-wp row: "parked" or "reset"
last_park_seq = None  # seq of the most recent same-wp harden.parked row
honoured_idx = -1

for i, row in rows:
    if not row or row.get("wp") != wp:
        continue
    t = row.get("type")
    if t == "harden.parked":
        last_park_seq = row.get("seq")
        last_wp_type = "parked"
    elif t == "harden.reset":
        if last_wp_type == "parked" and last_park_seq is not None:
            reason = row.get("reason") or ""
            pat = r"park-seq=" + re.escape(str(last_park_seq)) + r"(?!\d)"
            if re.search(pat, reason):
                honoured_idx = i
        last_wp_type = "reset"

rounds = 0
tokens = 0
for i, row in rows:
    if i <= honoured_idx or not row:
        continue
    if row.get("type") == "harden.round" and row.get("wp") == wp:
        rounds += 1
        t2 = row.get("tokens", 0)
        if isinstance(t2, (int, float)) and not isinstance(t2, bool):
            tokens += t2
print(f"{rounds} {int(tokens)}")
' "$trace"
}

# Idempotent park (T10/b13): a WP whose last `harden.parked` row for this WP
# is LATER (by trace position) than its last `harden.reset` row for this WP
# (ANY reset, honoured or not — park-seq binding makes each park a one-shot
# target and a probe must never move it) is already parked. Prints
# "STICKY <seq>" (seq of that park row) or "OPEN".
check_sticky() {
    local trace="$1" wp="$2"
    [ -f "$trace" ] || { echo "OPEN"; return 0; }
    WP="$wp" run_py '
wp = os.environ["WP"]
parked_idx = reset_idx = -1
parked_seq = None
for i, row in read_rows(sys.argv[1]):
    if not row or row.get("wp") != wp:
        continue
    if row.get("type") == "harden.parked":
        parked_idx, parked_seq = i, row.get("seq")
    elif row.get("type") == "harden.reset":
        reset_idx = i
if parked_idx >= 0 and parked_idx > reset_idx:
    print(f"STICKY {parked_seq}")
else:
    print("OPEN")
' "$trace"
}

# The seq of the LAST `harden.parked` row for $wp, or "none" — used to name a
# just-written park row in the `PARK — ... park-seq=<N>` stderr line (b13),
# read back after the best-effort emit since the emitter may drop it.
last_park_seq() {
    local trace="$1" wp="$2"
    [ -f "$trace" ] || { echo "none"; return 0; }
    WP="$wp" run_py '
wp = os.environ["WP"]
seq = None
for i, row in read_rows(sys.argv[1]):
    if row and row.get("wp") == wp and row.get("type") == "harden.parked":
        seq = row.get("seq")
print(seq if seq is not None else "none")
' "$trace" 2>/dev/null || echo none
}

# resolve_wp <wp-dir> — validate the WP directory and derive the identifiers
# every mode needs. Sets OV / WP / FEAT_DIR / TRACE in the caller's scope;
# prints the internal-error reason and returns 2 when the dir is unusable.
resolve_wp() {
    local wp_dir="$1"
    if [ ! -d "$wp_dir" ]; then
        echo "goalforge-harden-stop: internal error — not a directory: $wp_dir" >&2
        return 2
    fi
    OV="$wp_dir/overview.md"
    if [ ! -f "$OV" ]; then
        echo "goalforge-harden-stop: internal error — no overview.md in $wp_dir" >&2
        return 2
    fi
    WP="$(wp_name "$OV")"
    FEAT_DIR="$(cd "$wp_dir/.." && pwd)"
    TRACE="$FEAT_DIR/trace-events.jsonl"
}

# do_reset — wp-14 `--reset` mode. Short-circuits BEFORE run()'s ceiling/park
# path: no findings.md row, no `harden.parked` emit, on the allow path or on
# any block below. `--decision-ref <path>` is REQUIRED and admitted only when
# it passes FOUR conjunctive checks, each with its own stderr reason under the
# `--reset refused —` prefix:
#
#   (a) content      — the file's text carries the attended marker
#                       `answered_by: human` AND the verbatim `--reason`
#                       string. The ruling must be IN the referenced record,
#                       so the chain's own findings.md bookkeeping (a
#                       `harden: ceiling-breached` park row and nothing else)
#                       cannot clear the cap.
#   (b) freshness    — the file's mtime is strictly newer (second
#                       granularity, UTC) than the ts of the last
#                       `harden.parked` row for this WP. Equal second is
#                       REJECTED.
#   (c) parked       — the WP is CURRENTLY parked: its last `harden.parked`
#                       row comes after its last `harden.reset` row. No park
#                       row, or a reset already following the last park, is
#                       not parked.
#   (d) park binding — (lap-2 ruling, closes gate-B C1/H1) `--reason` is
#                       non-empty/non-whitespace and contains the literal
#                       `park-seq=<N>`, N being the `seq` field of this WP's
#                       last `harden.parked` row, with no digit directly
#                       after N; and `realpath(--decision-ref)` lies inside
#                       `realpath(<wp-dir>)`. Ties a ruling to the ONE park
#                       it names — a ruling that stays in findings.md, or a
#                       later mtime bump, can never re-clear a LATER park.
#
# T9/L1: one exclusive flock on `<feature-dir>/trace-events.reset.lock` — NOT
# the emitter's own `trace-events.lock`, which would deadlock (OQ5) — spans
# admission, the emit and the read-back; released on process exit.
#
# On admission it emits one `harden.reset` row carrying `rounds_cleared` (the
# round count `count_rounds` would have read) and `decision_ref`, and requires
# — fail-closed, since `goalforge-trace-emit` is degrade-not-block — a
# post-emit read-back: a `harden.reset` row for this WP, matching this call's
# `reason` and `decision_ref`, strictly beyond the pre-call trace line count.
# Exit 0 only once that read-back succeeds; exit 2 (`internal error —`)
# otherwise.
do_reset() {
    local wp_dir="$1" reason="$2" decision_ref="$3"

    resolve_wp "$wp_dir" || return 2

    if ! exec 8>"$FEAT_DIR/trace-events.reset.lock"; then
        echo "goalforge-harden-stop: internal error — cannot open reset lock: $FEAT_DIR/trace-events.reset.lock" >&2
        return 2
    fi
    flock -x 8

    # (d, part 1) reason non-empty/non-whitespace — checked first so an empty
    # reason never trivially satisfies the (a) content substring check below.
    case "$reason" in
        *[![:space:]]*) : ;;
        *) echo "goalforge-harden-stop: --reset refused — --reason must not be empty or whitespace-only" >&2; return 2 ;;
    esac
    if [ -z "$decision_ref" ]; then
        echo "goalforge-harden-stop: --reset refused — --decision-ref is required" >&2
        return 2
    fi
    if [ ! -f "$decision_ref" ]; then
        echo "goalforge-harden-stop: --reset refused — decision-ref does not exist: $decision_ref" >&2
        return 2
    fi
    # (d, part 2) realpath scope — a decision-ref must resolve inside the WP
    # dir (rejects a symlink whose target escapes it, and any doc elsewhere).
    local ref_real wp_real
    ref_real="$(realpath "$decision_ref" 2>/dev/null)" || {
        echo "goalforge-harden-stop: --reset refused — decision-ref unreadable: $decision_ref" >&2
        return 2
    }
    wp_real="$(realpath "$wp_dir")"
    case "$ref_real" in
        "$wp_real"/*) : ;;
        *) echo "goalforge-harden-stop: --reset refused — decision-ref must resolve inside the WP dir: $decision_ref" >&2; return 2 ;;
    esac
    command -v python3 >/dev/null 2>&1 || {
        echo "goalforge-harden-stop: internal error — python3 required for --reset" >&2
        return 2
    }

    # Admission: checks (a), (b), (c), (d-park-seq) in order, each its own
    # stderr reason. Prints the pre-call trace line count (the read-back
    # baseline) on pass.
    local baseline
    baseline="$(WP="$WP" REASON="$reason" DECISION_REF="$decision_ref" run_py '
import os, re
from datetime import datetime

wp = os.environ["WP"]
reason = os.environ["REASON"]
ref = os.environ["DECISION_REF"]

def refuse(msg):
    sys.stderr.write("goalforge-harden-stop: --reset refused — %s\n" % msg)
    raise SystemExit(1)

# (a) content gate
try:
    with open(ref, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
except OSError:
    refuse("decision-ref unreadable: " + ref)
if "answered_by: human" not in text:
    refuse("decision-ref carries no `answered_by: human` marker: " + ref)
if reason not in text:
    refuse("decision-ref does not contain the --reason text: " + reason)

trace = sys.argv[1]
if not os.path.isfile(trace):
    refuse("no harden.parked row found for wp " + wp)
rows = list(read_rows(trace))

parked_idx = reset_idx = -1
parked_ts = parked_seq = None
for i, row in rows:
    if not row or row.get("wp") != wp:
        continue
    if row.get("type") == "harden.parked":
        parked_idx, parked_ts, parked_seq = i, row.get("ts"), row.get("seq")   # last match wins
    elif row.get("type") == "harden.reset":
        reset_idx = i

# (b) freshness gate
if parked_idx < 0:
    refuse("no harden.parked row found for wp " + wp)
ts_str = str(parked_ts)
if ts_str.endswith("Z"):
    ts_str = ts_str[:-1] + "+00:00"
try:
    ts_epoch = int(datetime.fromisoformat(ts_str).timestamp())
except ValueError:
    refuse("unparseable harden.parked ts: " + str(parked_ts))
try:
    mtime_epoch = int(os.stat(ref).st_mtime)
except OSError:
    refuse("decision-ref unreadable: " + ref)
if mtime_epoch <= ts_epoch:
    refuse("decision-ref not newer than the last harden.parked row "
           "(decision-ref mtime=%d, parked ts=%d)" % (mtime_epoch, ts_epoch))

# (c) currently-parked gate
if reset_idx > parked_idx:
    refuse("wp %s is not currently parked — harden.reset at line %d already "
           "follows the last harden.parked at line %d"
           % (wp, reset_idx + 1, parked_idx + 1))

# (d) park binding — the reason must cite the exact park it answers.
if parked_seq is None:
    refuse("the last harden.parked row for wp %s has no seq field" % wp)
pat = r"park-seq=" + re.escape(str(parked_seq)) + r"(?!\d)"
if not re.search(pat, reason):
    refuse("--reason does not cite park-seq=%s (the last harden.parked row for wp %s)"
           % (parked_seq, wp))

print(len(rows))
' "$TRACE")" || return 2

    local out rounds
    out="$(count_rounds "$TRACE" "$WP")" || {
        echo "goalforge-harden-stop: internal error — unreadable/corrupt trace: $TRACE" >&2
        return 2
    }
    rounds="${out%% *}"
    case "$rounds" in *[!0-9]*) echo "goalforge-harden-stop: internal error — bad trace read" >&2; return 2 ;; esac

    local payload
    payload="$(WP="$WP" REASON="$reason" ROUNDS="$rounds" REF="$decision_ref" python3 -c '
import json, os, sys
sys.stdout.write(json.dumps({
    "type": "harden.reset",
    "wp": os.environ["WP"],
    "reason": os.environ["REASON"],
    "rounds_cleared": int(os.environ["ROUNDS"]),
    "decision_ref": os.environ["REF"],
}))
' 2>/dev/null)"
    emit_json "$FEAT_DIR" "$payload"

    # Read-back: the fail-closed mechanism (T9/L1). A pre-existing
    # harden.reset row (at or before $baseline) does not satisfy this, and
    # nor does a sibling row that merely shares type+wp — it must match this
    # call's own `reason` and `decision_ref`.
    WP="$WP" BASELINE="$baseline" REASON="$reason" DECISION_REF="$decision_ref" run_py '
import os
wp = os.environ["WP"]
baseline = int(os.environ["BASELINE"])
reason = os.environ["REASON"]
decision_ref = os.environ["DECISION_REF"]
trace = sys.argv[1]
if not os.path.isfile(trace):
    sys.exit(1)
for i, row in read_rows(trace):
    if i < baseline or not row:
        continue
    if row.get("type") == "harden.reset" and row.get("wp") == wp \
       and row.get("reason") == reason and row.get("decision_ref") == decision_ref:
        sys.exit(0)
sys.exit(1)
' "$TRACE"
    if [ $? -ne 0 ]; then
        echo "goalforge-harden-stop: internal error — no matching harden.reset row observed after emit (read-back failed)" >&2
        return 2
    fi

    echo "goalforge-harden-stop: RESET — $WP: rounds_cleared=$rounds ($reason)" >&2
    return 0
}

run() {
    local wp_dir="$1" out rounds tokens

    resolve_wp "$wp_dir" || return 2

    # T10/b13: idempotent park — a WP already parked (its last harden.parked
    # row for this WP is later than its last harden.reset row, ANY reset)
    # stays parked without a repeat write: under park-seq binding a repeat
    # park would move the seq a ruling is bound to and stale it.
    local sticky
    sticky="$(check_sticky "$TRACE" "$WP")" || {
        echo "goalforge-harden-stop: internal error — unreadable/corrupt trace: $TRACE" >&2
        return 2
    }
    case "$sticky" in
        "STICKY "*)
            echo "goalforge-harden-stop: already parked (park-seq=${sticky#STICKY })" >&2
            return 3
            ;;
    esac

    out="$(count_rounds "$TRACE" "$WP")" || {
        echo "goalforge-harden-stop: internal error — unreadable/corrupt trace: $TRACE" >&2
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
        emit_event "harden.parked" "$WP" "$FEAT_DIR" "$reason" "$rounds"
        local pseq
        pseq="$(last_park_seq "$TRACE" "$WP")"
        echo "goalforge-harden-stop: PARK — $WP: $reason (tokens=$tokens, ceiling=${hard:-none}) park-seq=$pseq" >&2
        return 3
    fi

    # No hard ceiling: tokens are a soft sensor — WARN and continue.
    if [ -z "$hard" ]; then
        local threshold
        threshold="$(soft_threshold "$OV")"
        if [ "$tokens" -gt "$threshold" ]; then
            echo "goalforge-harden-stop: WARN — $WP: tokens=$tokens above soft threshold $threshold" >&2
            emit_warn "$WP" "$FEAT_DIR" "$tokens" "$threshold"
        fi
    fi

    return 0
}

usage() { echo "usage: goalforge-harden-stop.sh <wp-dir> [--dispatch <path>] | goalforge-harden-stop.sh --reset --reason <text> --decision-ref <path> <wp-dir>" >&2; }

WP_DIR=""
RESET=0
REASON=""
DECISION_REF=""
DISPATCH_SET=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dispatch)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            DISPATCH_PATH="$2"; DISPATCH_SET=1; shift 2 ;;
        --reset)
            RESET=1; shift ;;
        --reason)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            REASON="$2"; shift 2 ;;
        --decision-ref)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            DECISION_REF="$2"; shift 2 ;;
        -*) usage; exit 2 ;;
        *)
            [ -z "$WP_DIR" ] || { usage; exit 2; }
            WP_DIR="$1"; shift ;;
    esac
done
[ -n "$WP_DIR" ] || { usage; exit 2; }

# Mode flags are not silently ignored: each is valid in exactly one mode.
# --reset short-circuits here, BEFORE run()'s ceiling/park path.
if [ "$RESET" -eq 1 ]; then
    if [ "$DISPATCH_SET" -eq 1 ]; then
        echo "goalforge-harden-stop: --reset refused — --dispatch is not valid with --reset" >&2
        usage; exit 2
    fi
    do_reset "$WP_DIR" "$REASON" "$DECISION_REF"; exit $?
fi
if [ -n "$REASON" ] || [ -n "$DECISION_REF" ]; then
    echo "goalforge-harden-stop: --reason/--decision-ref require --reset" >&2
    usage; exit 2
fi

run "$WP_DIR"; exit $?
