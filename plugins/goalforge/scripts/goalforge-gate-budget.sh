#!/usr/bin/env bash
# goalforge-gate-budget.sh — ticket-74 / C4 sensor-noise budget: the ONE place
# a dispatcher checks whether a gate has burned its self-disable budget before
# invoking it.
#
# Usage:
#   goalforge-gate-budget.sh <gate> --feature-dir <dir> [--session <id>]
#
# The trace is the counter (ticket-74): this script counts `gate.result` rows
# with `result: fail` for <gate>, in the CURRENT session, since the last
# `commit.linked` row (a shipped fix resets the budget — D9 "no shipped fix").
# On the SECOND such fail with no intervening commit, the gate is disabled
# for the rest of the session and a `gate.disabled` row is written (via
# goalforge-trace-emit — never a raw append). A THIRD invocation for an
# already-disabled gate finds the prior `gate.disabled` row in the trace and
# stays exit 4 WITHOUT writing a second one (idempotent — no duplicate rows).
#
# Session-id fallback (documented, since no live producer this WP stamps
# `session` onto every `gate.result` row — see references/trace-events.md
# `gate.result`, the hook helper omits it):
#   1. --session <id>            explicit override (tests, non-interactive callers)
#   2. $CLAUDE_SESSION_ID         the running session's id
#   3. "unknown"                  degrade-not-block: every trace row lacking a
#      `session` field (or carrying a blank one) is treated as belonging to
#      THIS invocation's session for counting purposes — single-actor-per-repo
#      is the working assumption; a row carrying a DIFFERENT non-blank session
#      is excluded (cross-session noise never trips this session's budget).
#
# Exit codes:
#   0  gate has budget — caller should run the gate
#   4  gate is disabled for this session (self-disabled just now, or already)
#   2  internal error (bad usage, --feature-dir missing/not a directory,
#      trace-events.jsonl unreadable/corrupt) — fail-closed per ticket-74
#      ("an internal error is exit 2, fail-closed — never the silent 0")
#
# Zero-breakage note: an internal error here is a HARD 2, unlike
# goalforge-trace-emit's degrade-not-block I/O warnings — a caller that
# cannot determine the budget must not silently assume it has one.

set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GATE=""
FEATURE_DIR=""
SESSION_OPT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --feature-dir) FEATURE_DIR="${2:-}"; shift 2 ;;
        --session)     SESSION_OPT="${2:-}"; shift 2 ;;
        -h|--help)
            sed -n '2,20p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *)
            if [[ -z "$GATE" ]]; then
                GATE="$1"
                shift
            else
                echo "goalforge-gate-budget.sh: unexpected argument '$1'" >&2
                exit 2
            fi
            ;;
    esac
done

if [[ -z "$GATE" ]]; then
    echo "Usage: goalforge-gate-budget.sh <gate> --feature-dir <dir> [--session <id>]" >&2
    exit 2
fi
if [[ -z "$FEATURE_DIR" ]]; then
    echo "goalforge-gate-budget.sh: --feature-dir is required" >&2
    exit 2
fi
if [[ ! -d "$FEATURE_DIR" ]]; then
    echo "goalforge-gate-budget.sh: feature dir not found: $FEATURE_DIR" >&2
    exit 2
fi

SESSION="${SESSION_OPT:-${CLAUDE_SESSION_ID:-unknown}}"
TRACE_EMIT="$SD/goalforge-trace-emit"
TRACE_READ="$SD/goalforge-trace-read"

# ── Delegate the read + count + (conditional) emit to Python ────────────────
# Reuses goalforge-trace-read's read_events() (the single trace parser,
# B-12-SEAM) rather than reimplementing torn-tail/schema-branch handling here.

python3 - "$FEATURE_DIR" "$GATE" "$SESSION" "$TRACE_READ" "$TRACE_EMIT" <<'PYEOF'
import importlib.machinery
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

feature_dir, gate, session, trace_read_path, trace_emit_path = sys.argv[1:6]

# ── load goalforge-trace-read as a module (no .py extension on disk) ────────
try:
    loader = importlib.machinery.SourceFileLoader("goalforge_trace_read", trace_read_path)
    spec = importlib.util.spec_from_loader("goalforge_trace_read", loader)
    trace_read = importlib.util.module_from_spec(spec)
    loader.exec_module(trace_read)
except OSError as exc:
    print(f"goalforge-gate-budget: cannot load trace reader: {exc}", file=sys.stderr)
    sys.exit(2)

trace_path = Path(feature_dir) / "trace-events.jsonl"
if not trace_path.exists():
    events = []
else:
    try:
        # best-effort: a torn/unknown-version row never blocks a budget check —
        # only a missing --feature-dir (already checked by the caller) is a
        # hard usage error at this layer.
        events = trace_read.read_events(trace_path, strict=False)
    except OSError as exc:
        print(f"goalforge-gate-budget: cannot read trace: {exc}", file=sys.stderr)
        sys.exit(2)


def in_session(ev: dict) -> bool:
    """A row counts toward THIS session's budget if it carries no session
    (degrade-not-block: hooks that omit `session` are assumed same-session —
    see the script header's session-id fallback) or matches SESSION exactly."""
    row_session = ev.get("session")
    return not row_session or row_session == session


block_count = 0
disabled = False
for ev in events:
    et = ev.get("type")
    if et == "commit.linked":
        if in_session(ev):
            block_count = 0
            disabled = False
    elif et == "gate.result" and ev.get("gate") == gate:
        if in_session(ev) and str(ev.get("result", "")).lower() == "fail":
            block_count += 1
    elif et == "gate.disabled" and ev.get("gate") == gate:
        if in_session(ev):
            disabled = True

if disabled:
    # Idempotent: already disabled this session/window — no second row.
    sys.exit(4)

if block_count >= 2:
    row = {"type": "gate.disabled", "gate": gate,
           "reason": f"{block_count} fail results, no commit", "session": session}
    proc = subprocess.run(
        [sys.executable, trace_emit_path, "--feature-dir", feature_dir,
         "--event", json.dumps(row)],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        print(f"goalforge-gate-budget: gate.disabled emit failed: {proc.stderr}",
              file=sys.stderr)
        sys.exit(2)
    sys.exit(4)

sys.exit(0)
PYEOF
exit $?
