#!/usr/bin/env bash
# goalforge-second-opinion.sh — wp-03/T5: the ONE second opinion on the gate C
# verdict, taken through the agent-dispatch leaf seam (leaf-interface.md v1).
#
# The provider, model, endpoint, budget, and egress class all come from
# references/dispatch.yaml's `second_opinion` stage row (`--dispatch <path>`);
# no provider is named here. The feature's spec.md frontmatter may NARROW the
# egress class (none < diff-only < overview < full); a widening value is
# ignored with a WARN row. No content is redacted in any class (ticket-45).
#
# Usage:
#   goalforge-second-opinion.sh <wp> --feature-dir <feature> \
#       [--dispatch <path>] [--verdict <file>] [--diff <file>]
#
#   <wp>            WP directory path, or a WP name under --feature-dir.
#   --verdict FILE  gate C verdict text (optional; empty when absent).
#   --diff FILE     the WP diff (optional; empty when absent) — deterministic
#                   input, never derived from the working tree by this script.
#
# Payload by egress class (verbatim, in this order):
#   none      -> no leaf call at all (skipped, reason `egress-none`)
#   diff-only -> verdict + diff
#   overview  -> verdict + diff + <wp>/overview.md
#   full      -> verdict + diff + <wp>/overview.md + <feature>/spec.md
#                + <wp>/findings.md (a missing findings.md is omitted and
#                noted in the reason)
#
# Trace rows (via scripts/goalforge-trace-emit, best-effort):
#   second_opinion.ok      — leaf ran and its turn completed (exit 0, or exit 4
#                            budget_exceeded/budget_check_failed: the result is
#                            kept, the overspend named in the reason)
#   second_opinion.skipped — reason `no-payload` (neither --verdict nor --diff
#                            resolves to a non-empty file: there is nothing to
#                            take an opinion ON), `dispatcher-absent` (leaf
#                            missing or not executable), `egress-none`,
#                            `payload-oversize <actual>/<cap>`, or
#                            `leaf-exit-<n>`
#
# The payload is handed to the leaf as a `--prompt` argv VALUE — the only
# payload flag inside leaf-interface v1.
#
# NOT `--prompt-file`, because of what the CONFIGURED provider's leaf does with
# it (verified 2026-09-13 by reading the leaves, not the interface doc):
#   ollama, zai, deepseek -> `_core/prompt_file.py`, a *structured handoff-brief*
#       parser (base-dir allowlist, frontmatter contract, exit 2/3) — a raw
#       payload file handed to it dies leaf-exit-3
#       (e.g. ollama/scripts/headless_dispatch:68-72)
#   codex                 -> reads the file RAW (`PROMPT="$(cat ...)"`,
#       codex/scripts/headless_dispatch:313-315), so a payload file WOULD work
#       there
# leaf-interface v1 therefore does admit a payload file on SOME leaf; the cap
# exists because the shipped `second_opinion` row runs on `ollama`, one of the
# three that route the flag through prompt_file.py. Re-point that row at codex
# and `--prompt-file` becomes available — a config-dependent fact, not a
# property of the interface.
#
# The size cap is CONFIGURED, not hardcoded: `second_opinion.max_payload_bytes`
# in the dispatch file (default and reviewed MAXIMUM 102400, inside
# MAX_ARG_STRLEN with headroom — see MAX_PAYLOAD_CEILING below). Above it
# the DIFF section is truncated head-first, marked in the payload and named in
# the emitted reason (`; diff-truncated N/M`). If the payload is STILL over the
# cap with the diff gone (an `egress: full` WP whose own documents exceed it),
# no leaf is called: `second_opinion.skipped` with reason
# `payload-oversize <actual>/<cap>`, exit 0.
#
# Every leaf call appends one propose-only ledger row to
# $GOALFORGE_DISPATCH_LEDGER (default
# ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/data/dispatch-decisions.jsonl).
#
# Exit 0 always (degrade-not-block): a second opinion is advisory, never a gate.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: goalforge-second-opinion.sh <wp> --feature-dir <feature> [--dispatch <path>] [--verdict <file>] [--diff <file>]" >&2
    exit 0
fi

WP_ARG="$1"; shift
FEATURE_DIR=""
DISPATCH_PATH="$SD/../references/dispatch.yaml"
VERDICT_FILE=""
DIFF_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --feature-dir) FEATURE_DIR="${2:-}"; shift 2 ;;
        --dispatch)    DISPATCH_PATH="${2:-}"; shift 2 ;;
        --verdict)     VERDICT_FILE="${2:-}"; shift 2 ;;
        --diff)        DIFF_FILE="${2:-}"; shift 2 ;;
        *) echo "goalforge-second-opinion.sh: unexpected argument '$1'" >&2; exit 0 ;;
    esac
done

if [[ -z "$FEATURE_DIR" || ! -d "$FEATURE_DIR" ]]; then
    echo "goalforge-second-opinion.sh: --feature-dir must name an existing directory" >&2
    exit 0
fi

if [[ -d "$WP_ARG" ]]; then
    WP_DIR="$WP_ARG"
else
    WP_DIR="$FEATURE_DIR/$WP_ARG"
fi
WP_NAME="$(basename "$WP_ARG")"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MAX_PAYLOAD_DEFAULT=$((100 * 1024))  # fallback only; the dispatch file is the source
MAX_PAYLOAD_BYTES="$MAX_PAYLOAD_DEFAULT"

# UPPER CLAMP on the configured cap. The payload travels as ONE argv string, so
# it is bounded by MAX_ARG_STRLEN = PAGESIZE * 32 — measured on a 4 KiB-page
# host: 131072, where 131000 bytes exec'd and 131100 exited 126. The leaf
# re-passes the same value through `_core/intent_gate.sh` and then `claude -p`,
# each another single argv string, so the cap is held well below that limit:
# 102400 leaves ~28 KiB for flag names, the leaf's own additions, and a host
# with the same page size. A configured value above this ceiling is CLAMPED with
# a WARN rather than honoured into an exec failure (exit 126).
MAX_PAYLOAD_CEILING=$((100 * 1024))

emit() { # $1=event type  $2=reason  ($PROVIDER/$MODEL when resolved)
    local emitter="$SD/goalforge-trace-emit"
    [[ -f "$emitter" ]] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    TYPE="$1" WP="$WP_NAME" REASON="$2" PROVIDER="${PROVIDER:-}" MODEL="${MODEL:-}" python3 -c '
import json, os, sys
row = {"type": os.environ["TYPE"], "wp": os.environ["WP"], "reason": os.environ["REASON"]}
for key in ("provider", "model"):
    val = os.environ.get(key.upper(), "")
    if val:
        row[key] = val
sys.stdout.write(json.dumps(row))
' 2>/dev/null | python3 "$emitter" --feature-dir "$FEATURE_DIR" >/dev/null 2>&1 || true
    return 0
}

# --- nothing to opine on? --------------------------------------------------
# Both inputs empty (flag absent, or the file is missing/zero-length) means the
# caller has no verdict and no diff to send. Sending an empty payload would
# record a content-free `second_opinion.ok`, so skip before resolving anything.
HAVE_VERDICT=0; HAVE_DIFF=0
[[ -n "$VERDICT_FILE" && -s "$VERDICT_FILE" ]] && HAVE_VERDICT=1
[[ -n "$DIFF_FILE" && -s "$DIFF_FILE" ]] && HAVE_DIFF=1
if [[ "$HAVE_VERDICT" -eq 0 && "$HAVE_DIFF" -eq 0 ]]; then
    PROVIDER=""; MODEL=""
    emit second_opinion.skipped "no-payload"
    exit 0
fi

# --- resolve the second_opinion stage row + the effective egress class -------
# Prints 7 lines: model, provider, leaf (may be empty), max_budget_usd,
# effective egress class, widening-warn flag (1|0), max_payload_bytes.
# Empty output = unreadable.
CFG="$(DISPATCH_PATH="$DISPATCH_PATH" SPEC_PATH="$FEATURE_DIR/spec.md" \
    MAX_PAYLOAD_DEFAULT="$MAX_PAYLOAD_DEFAULT" MAX_PAYLOAD_CEILING="$MAX_PAYLOAD_CEILING" \
    python3 -c '
import os, sys

import yaml

ORDER = ["none", "diff-only", "overview", "full"]

try:
    with open(os.environ["DISPATCH_PATH"], encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except (OSError, yaml.YAMLError):
    sys.exit(1)

row = ((data.get("stages") or {}).get("second_opinion")) or {}
providers = {p.get("name"): p for p in (data.get("providers") or []) if isinstance(p, dict)}
prov = providers.get(row.get("provider"), {})

egress = row.get("egress", "none")
if egress not in ORDER:
    egress = "none"

warn = "0"
try:
    text = open(os.environ["SPEC_PATH"], encoding="utf-8").read()
except OSError:
    text = ""
if text.startswith("---"):
    fm = yaml.safe_load(text.split("---", 2)[1]) or {}
    want = fm.get("egress") if isinstance(fm, dict) else None
    if want in ORDER:
        if ORDER.index(want) < ORDER.index(egress):
            egress = want
        elif ORDER.index(want) > ORDER.index(egress):
            warn = "1"

print(row.get("model", ""))
print(row.get("provider", ""))
print(prov.get("leaf") or "")
print(prov.get("max_budget_usd", 0.10))
print(egress)
print(warn)

# Line 7: "<cap> <status>", status in ok|clamped|invalid|absent. The key is
# OPTIONAL: absent means the default. A non-integer or non-positive value is
# `invalid` (default + WARN, never silence); a value above the ceiling is
# `clamped` (ceiling + WARN), because the payload is one argv string.
DEFAULT = int(os.environ["MAX_PAYLOAD_DEFAULT"])
CEILING = int(os.environ["MAX_PAYLOAD_CEILING"])
raw = (data.get("second_opinion") or {}).get("max_payload_bytes")
if raw is None:
    cap, status = DEFAULT, "absent"
elif isinstance(raw, bool):
    cap, status = DEFAULT, "invalid"
else:
    try:
        cap, status = int(raw), "ok"
    except (TypeError, ValueError):
        cap, status = DEFAULT, "invalid"
    else:
        if cap <= 0:
            cap, status = DEFAULT, "invalid"
        elif cap > CEILING:
            cap, status = CEILING, "clamped"
print(f"{cap} {status}")
' 2>/dev/null)"

if [[ -z "$CFG" ]]; then
    PROVIDER=""; MODEL=""
    emit second_opinion.skipped "dispatch config unreadable: $DISPATCH_PATH"
    exit 0
fi

{ read -r MODEL; read -r PROVIDER; read -r LEAF_REL; read -r BUDGET; read -r EGRESS; read -r WIDEN; read -r CAP_LINE; } <<< "$CFG"
read -r CFG_CAP CAP_STATUS <<< "$CAP_LINE"
[[ "$CFG_CAP" =~ ^[0-9]+$ ]] && MAX_PAYLOAD_BYTES="$CFG_CAP"
case "${CAP_STATUS:-}" in
    clamped)
        echo "WARN: goalforge-second-opinion.sh: second_opinion.max_payload_bytes in" \
             "$DISPATCH_PATH exceeds the reviewed ceiling $MAX_PAYLOAD_CEILING (one argv" \
             "string must stay inside MAX_ARG_STRLEN) — clamped to $MAX_PAYLOAD_BYTES" >&2 ;;
    invalid)
        echo "WARN: goalforge-second-opinion.sh: second_opinion.max_payload_bytes in" \
             "$DISPATCH_PATH is not a positive integer — using the default" \
             "$MAX_PAYLOAD_BYTES" >&2 ;;
esac

REASON_SUFFIX=""
if [[ "$WIDEN" == "1" ]]; then
    echo "WARN: goalforge-second-opinion.sh: feature spec.md egress widens the '$EGRESS' stage row — ignored (egress-widening-ignored)" >&2
    REASON_SUFFIX="; egress-widening-ignored"
fi

if [[ "$EGRESS" == "none" ]]; then
    emit second_opinion.skipped "egress-none${REASON_SUFFIX}"
    exit 0
fi

# --- resolve the leaf --------------------------------------------------------
CORPUS_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LEAF=""
case "$LEAF_REL" in
    "")   LEAF="" ;;
    "~/"*) LEAF="$HOME/${LEAF_REL#\~/}" ;;
    /*)   LEAF="$LEAF_REL" ;;
    *)    LEAF="$CORPUS_ROOT/$LEAF_REL" ;;
esac

if [[ -z "$LEAF" || ! -x "$LEAF" ]]; then
    emit second_opinion.skipped "dispatcher-absent${REASON_SUFFIX}"
    exit 0
fi

# --- build the payload -------------------------------------------------------
PAYLOAD="$TMP/payload.txt"
DIFF_BODY="$TMP/diff-body.txt"
: > "$DIFF_BODY"
[[ "$HAVE_DIFF" -eq 1 ]] && cat "$DIFF_FILE" > "$DIFF_BODY"

build_payload() { # $1 = the diff body to embed
    {
        echo "# second opinion on the gate C verdict — $WP_NAME"
        echo "# egress class: $EGRESS (no redaction)"
        echo
        echo "## verdict"
        [[ "$HAVE_VERDICT" -eq 1 ]] && cat "$VERDICT_FILE"
        echo
        echo "## diff"
        cat "$1"
        if [[ "$EGRESS" == "overview" || "$EGRESS" == "full" ]]; then
            echo; echo "## overview.md"
            [[ -f "$WP_DIR/overview.md" ]] && cat "$WP_DIR/overview.md"
        fi
        if [[ "$EGRESS" == "full" ]]; then
            echo; echo "## spec.md"
            [[ -f "$FEATURE_DIR/spec.md" ]] && cat "$FEATURE_DIR/spec.md"
            if [[ -f "$WP_DIR/findings.md" ]]; then
                echo; echo "## findings.md"; cat "$WP_DIR/findings.md"
            fi
        fi
    } > "$PAYLOAD"
}
build_payload "$DIFF_BODY"

if [[ "$EGRESS" == "full" && ! -f "$WP_DIR/findings.md" ]]; then
    REASON_SUFFIX="${REASON_SUFFIX}; findings.md absent"
fi

# Size cap: keep the head of the DIFF section and say so, in the payload and in
# the reason. The other sections are bounded by the WP's own documents.
PAYLOAD_BYTES="$(wc -c < "$PAYLOAD")"
if [[ "$PAYLOAD_BYTES" -gt "$MAX_PAYLOAD_BYTES" ]]; then
    DIFF_BYTES="$(wc -c < "$DIFF_BODY")"
    # Reserve room for the marker itself (sized with DIFF_BYTES in both slots,
    # an upper bound: KEEP is never wider than DIFF_BYTES).
    MARKER_RESERVE="$(printf '\n[diff truncated: %s of %s bytes]\n' "$DIFF_BYTES" "$DIFF_BYTES" | wc -c)"
    OVERHEAD=$((PAYLOAD_BYTES - DIFF_BYTES + MARKER_RESERVE))
    KEEP=$((MAX_PAYLOAD_BYTES - OVERHEAD))
    [[ "$KEEP" -lt 0 ]] && KEEP=0
    TRUNCATED="$TMP/diff-truncated.txt"
    head -c "$KEEP" "$DIFF_BODY" > "$TRUNCATED"
    printf '\n[diff truncated: %s of %s bytes]\n' "$KEEP" "$DIFF_BYTES" >> "$TRUNCATED"
    build_payload "$TRUNCATED"
    # The diff is not the only section: an `egress: full` WP whose own documents
    # exceed the cap cannot be made to fit by truncating the diff at all. Say so
    # instead of reporting a misleading `diff-truncated 0/N` and sending it.
    NOW_BYTES="$(wc -c < "$PAYLOAD")"
    if [[ "$NOW_BYTES" -gt "$MAX_PAYLOAD_BYTES" ]]; then
        emit second_opinion.skipped \
            "payload-oversize ${NOW_BYTES}/${MAX_PAYLOAD_BYTES}${REASON_SUFFIX}"
        exit 0
    fi
    REASON_SUFFIX="${REASON_SUFFIX}; diff-truncated ${KEEP}/${DIFF_BYTES}"
fi

# --- call the leaf -----------------------------------------------------------
# `--prompt` (an argv VALUE), the only payload flag in leaf-interface.md v1.
# NOT `--prompt-file`: on the leaves the shipped row can select (ollama, zai,
# deepseek — verified 2026-09-13) that flag is a structured handoff-brief path
# through `_core/prompt_file.py` (base-dir allowlist + frontmatter contract,
# exit 2/3), so a raw payload file handed to it dies leaf-exit-3. The codex leaf
# reads it raw (codex/scripts/headless_dispatch:313-315) and would accept one —
# which is why the cap is keyed to the CONFIGURED provider, not to the
# interface. The cap above keeps the argv value inside MAX_ARG_STRLEN.
OUT="$TMP/out.json"
"$LEAF" --model "$MODEL" --prompt "$(cat "$PAYLOAD")" --output "$OUT" --max-budget-usd "$BUDGET"
LEAF_EXIT=$?

# leaf-interface.md §6 hazard 1: the EXIT_CODE trailer is not valid JSON.
DECODED="$(OUT="$OUT" python3 -c '
import json, os, sys
try:
    raw = open(os.environ["OUT"], encoding="utf-8").read()
except OSError:
    sys.exit(0)
body = "\n".join(l for l in raw.splitlines() if not l.startswith("EXIT_CODE="))
try:
    env = json.loads(body)
except json.JSONDecodeError:
    sys.exit(0)
result = env.get("result") or ""
reason = (env.get("codex") or {}).get("reason") or ""
print(reason)
print(" ".join(str(result).split())[:200])
' 2>/dev/null)"
LEAF_REASON="$(printf '%s\n' "$DECODED" | sed -n 1p)"
LEAF_RESULT="$(printf '%s\n' "$DECODED" | sed -n 2p)"

# --- propose-only ledger row (every leaf call) -------------------------------
LEDGER="${GOALFORGE_DISPATCH_LEDGER:-$CORPUS_ROOT/data/dispatch-decisions.jsonl}"
LEDGER="$LEDGER" WP="$WP_NAME" PROVIDER="$PROVIDER" MODEL="$MODEL" EGRESS="$EGRESS" \
EXIT_CODE="$LEAF_EXIT" python3 -c '
import json, os, sys, time
from pathlib import Path
row = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "wp": os.environ["WP"],
    "role": "second_opinion",
    "provider": os.environ["PROVIDER"],
    "model": os.environ["MODEL"],
    "egress": os.environ["EGRESS"],
    "decision": "propose-only",
    "exit_code": int(os.environ["EXIT_CODE"]),
}
target = Path(os.environ["LEDGER"])
try:
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, sort_keys=True) + "\n")
except OSError as exc:
    print(f"WARN: goalforge-second-opinion.sh: ledger row to {target}: {exc}", file=sys.stderr)
' || true

if [[ "$LEAF_EXIT" -eq 0 ]]; then
    emit second_opinion.ok "${LEAF_RESULT}${REASON_SUFFIX}"
elif [[ "$LEAF_EXIT" -eq 4 && ( "$LEAF_REASON" == "budget_exceeded" || "$LEAF_REASON" == "budget_check_failed" ) ]]; then
    emit second_opinion.ok "${LEAF_RESULT}${REASON_SUFFIX}; overspend: $LEAF_REASON"
else
    emit second_opinion.skipped "leaf-exit-${LEAF_EXIT}${REASON_SUFFIX}"
fi

exit 0
