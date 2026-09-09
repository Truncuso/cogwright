#!/usr/bin/env bash
# goalforge-rollup.sh — read-side renderer over a feature's trace-events.jsonl
# (D13: "state in one file" — trace-events.jsonl is the single state
# substrate; this script never reads or writes recap.md, per-task checkpoint
# blocks, or a todo.md rollup — all three are RETIRED by wp-01/C6).
#
# Usage:
#   goalforge-rollup.sh <feature-dir> [--session <id>]
#
# Reads (NEVER writes to these):
#   <feature-dir>/trace-events.jsonl   — the sole input (via goalforge-trace-read)
#
# Writes: NOTHING. Prints a per-WP rollup + a shipping-metric line to STDOUT.
# A missing trace-events.jsonl is not an error (a feature that hasn't started
# executing yet has no trace) — the renderer prints an empty rollup and exits 0.
#
# Per-WP section (only WPs that appear in the trace are listed, in the order
# their first event appears): dispatches (dispatch.launched, task/agent/model/
# effort), gate results (gate.result, gate=result pairs in trace order), harden
# rounds (harden.round/harden.parked, if any), the linked commit
# (commit.linked, most recent by seq), and whether the WP verified
# (wp.verified).
#
# Shipping metric (D9): "WPs verified this session: N" — counts distinct WPs
# with a `wp.verified` row IN THE RESOLVED SESSION (same fallback + degrade
# rule as goalforge-gate-budget.sh: --session override > $CLAUDE_SESSION_ID >
# "unknown"; a row with no `session` field is assumed to belong to the current
# session — see that script's header for the full rationale).
#
# Idempotent: running twice back-to-back on an unchanged trace produces
# byte-identical stdout (no wall-clock stamps in the body).
#
# Exit 0 on success (including "no trace yet"). Exit 1 only when <feature-dir>
# does not exist / is unreadable — this script is called from
# goalforge-transition.sh's critical section under `set -e`, so it must never
# fail on a valid, existing feature dir.

set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: goalforge-rollup.sh <feature-dir> [--session <id>]" >&2
    exit 1
fi

FEATURE_DIR_ARG="$1"; shift
SESSION_OPT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --session) SESSION_OPT="${2:-}"; shift 2 ;;
        *)         echo "goalforge-rollup.sh: unexpected argument '$1'" >&2; exit 1 ;;
    esac
done

FEATURE_DIR="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$FEATURE_DIR_ARG")"
if [[ ! -d "$FEATURE_DIR" ]]; then
    echo "ERROR: feature dir not found: $FEATURE_DIR" >&2
    exit 1
fi

SESSION="${SESSION_OPT:-${CLAUDE_SESSION_ID:-unknown}}"
TRACE_READ="$SD/goalforge-trace-read"

python3 - "$FEATURE_DIR" "$SESSION" "$TRACE_READ" <<'PYEOF'
import importlib.machinery
import importlib.util
import sys
from pathlib import Path

feature_dir, session, trace_read_path = sys.argv[1:4]

loader = importlib.machinery.SourceFileLoader("goalforge_trace_read", trace_read_path)
spec = importlib.util.spec_from_loader("goalforge_trace_read", loader)
trace_read = importlib.util.module_from_spec(spec)
loader.exec_module(trace_read)

trace_path = Path(feature_dir) / "trace-events.jsonl"
if trace_path.exists():
    # Best-effort: a torn/unknown-version row is a renderer's problem, never a
    # reason to fail a caller running inside a `set -e` critical section.
    events = trace_read.read_events(trace_path, strict=False)
else:
    events = []


def in_session(ev: dict) -> bool:
    row_session = ev.get("session")
    return not row_session or row_session == session


# ── Group per-WP, preserving first-appearance order ─────────────────────────
wp_order: list[str] = []
wps: dict[str, dict] = {}


def wp_bucket(wp: str) -> dict:
    if wp not in wps:
        wp_order.append(wp)
        wps[wp] = {"dispatches": [], "gates": [], "harden_rounds": [],
                    "harden_parked": None, "commit": None, "verified": False,
                    "verified_reason": None}
    return wps[wp]


verified_this_session: set[str] = set()

for ev in events:
    et = ev.get("type")
    wp = ev.get("wp")
    if et == "dispatch.launched" and wp:
        b = wp_bucket(wp)
        b["dispatches"].append({
            "task": ev.get("task", ""), "agent": ev.get("agent", ""),
            "model": ev.get("model", ""), "effort": ev.get("effort", ""),
        })
    elif et == "gate.result" and wp:
        b = wp_bucket(wp)
        b["gates"].append((ev.get("gate", ""), ev.get("result", "")))
    elif et == "harden.round" and wp:
        b = wp_bucket(wp)
        b["harden_rounds"].append((ev.get("round"), ev.get("tokens")))
    elif et == "harden.parked" and wp:
        b = wp_bucket(wp)
        b["harden_parked"] = (ev.get("rounds"), ev.get("reason", ""))
    elif et == "commit.linked" and wp:
        b = wp_bucket(wp)
        b["commit"] = ev.get("commit")
    elif et == "wp.verified" and wp:
        b = wp_bucket(wp)
        b["verified"] = True
        b["verified_reason"] = ev.get("reason", "")
        if in_session(ev):
            verified_this_session.add(wp)

feature_name = Path(feature_dir).name

lines: list[str] = []
lines.append(f"# Trace Rollup — {feature_name}")
lines.append("")
lines.append("Read-side render of trace-events.jsonl (D13) — no todo.md, no")
lines.append("recap.md, no per-task checkpoints; the trace is the single state")
lines.append("substrate.")
lines.append("")

if not wp_order:
    lines.append("_No trace events yet._")
else:
    for wp in wp_order:
        b = wps[wp]
        lines.append(f"## {wp}")
        if b["dispatches"]:
            parts = [
                f'{d["task"] or "?"}:{d["agent"] or "?"}@{d["model"] or "?"}/{d["effort"] or "?"}'
                for d in b["dispatches"]
            ]
            lines.append(f"- Dispatches: {len(b['dispatches'])} ({', '.join(parts)})")
        else:
            lines.append("- Dispatches: none")
        if b["gates"]:
            gate_parts = [f"{g}={r}" for g, r in b["gates"]]
            lines.append(f"- Gate results: {', '.join(gate_parts)}")
        else:
            lines.append("- Gate results: none")
        if b["harden_rounds"]:
            round_parts = [f"round {r} ({t} tok)" for r, t in b["harden_rounds"]]
            lines.append(f"- Harden rounds: {', '.join(round_parts)}")
        if b["harden_parked"]:
            rounds, reason = b["harden_parked"]
            lines.append(f"- Harden parked: rounds={rounds} ({reason})")
        lines.append(f"- Commit: {b['commit'] or 'none'}")
        lines.append(f"- Verified: {'yes' if b['verified'] else 'no'}")
        lines.append("")

lines.append("## Shipping metric")
lines.append("")
lines.append(f"WPs verified this session: {len(verified_this_session)}")

sys.stdout.write("\n".join(lines) + "\n")
sys.exit(0)
PYEOF
exit $?
