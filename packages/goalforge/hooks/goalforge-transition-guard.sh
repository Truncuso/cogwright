#!/usr/bin/env bash
# goalforge-transition-guard.sh — advisory PreToolUse-style guard for WP-status edits.
#
# Given a proposed WP `status:` edit (a PreToolUse Edit event on stdin, or an
# explicit `--from <s> --to <s>`), this blocks an ILLEGAL edge (exit 2) per
#   skills/goalforge/references/state-machine.md
# and passes a legal edge (exit 0).
#
# ZERO-BREAKAGE: exit 0 on ANY internal error (missing input, parse failure,
# missing/garbled state-machine) — a hook must never block because it itself
# failed. The ONLY non-zero exit is exit 2 for a confirmed illegal edge.
#
# NOT wired into hooks.json — wiring a blocking PreToolUse hook is a deliberate,
# separate step (see the WP report's HOOK WIRING note).
#
# Usage:
#   <PreToolUse JSON on stdin> | goalforge-transition-guard.sh
#   goalforge-transition-guard.sh --from <state> --to <state>
#   goalforge-transition-guard.sh --self-test
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$HOOK_DIR/$(basename "${BASH_SOURCE[0]}")"
STATE_MACHINE="$HOOK_DIR/../skills/goalforge/references/state-machine.md"

# ── Edge verdict: prints "legal" | "illegal" | "error" ──────────────────────
# "error" (table missing/unreadable/parse failure) is treated as pass — the
# guard never blocks on its own failure.
edge_verdict() {
    # args: <state-machine-path> <from> <to>
    python3 - "$1" "$2" "$3" <<'PY' 2>/dev/null || echo error
import sys
sm, frm, to = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    text = open(sm, encoding="utf-8").read()
except OSError:
    print("error"); sys.exit(0)
in_edges = False
for ln in text.splitlines():
    s = ln.strip()
    if s.startswith("## "):
        in_edges = s.lower().startswith("## edges")
        continue
    if not in_edges or not s.startswith("|"):
        continue
    cells = [c.strip() for c in s.strip("|").split("|")]
    if len(cells) < 4:
        continue
    if cells[0].lower() == "from" or set("".join(cells)) <= set("-: "):
        continue
    if cells[0] == frm and cells[1] == to:
        print("legal"); sys.exit(0)
print("illegal")
PY
}

# Returns 2 for a confirmed illegal edge, 0 otherwise (legal or any error).
do_check() {
    local v
    v="$(edge_verdict "$STATE_MACHINE" "$1" "$2")"
    [[ "$v" == "illegal" ]] && return 2 || return 0
}

# Parse a PreToolUse Edit event from stdin → prints "<from> <to>" or nothing.
# Nothing means "not applicable" (not a WP overview status edit / parse failed)
# → the caller treats that as exit 0.
# stdin is slurped into a variable and handed to python via the environment so
# the heredoc (which itself occupies python's stdin as the program source) does
# not collide with reading the JSON.
parse_stdin() {
    local input
    input="$(cat)" || return 0
    [[ -z "$input" ]] && return 0
    GUARD_JSON="$input" python3 - <<'PY' 2>/dev/null
import os, sys, json, re
try:
    data = json.loads(os.environ.get("GUARD_JSON", ""))
except Exception:
    sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
ti = data.get("tool_input") or {}
fp = str(ti.get("file_path") or "")
if not fp.endswith("overview.md"):
    sys.exit(0)
old = str(ti.get("old_string") or "")
new = str(ti.get("new_string") or "")
enum = r"(draft|spec|hardened|ready|executing|verified|archived)"
mo = re.search(r"^\s*status:\s*['\"]?" + enum, old, re.MULTILINE)
mn = re.search(r"^\s*status:\s*['\"]?" + enum, new, re.MULTILINE)
if not (mo and mn) or mo.group(1) == mn.group(1):
    sys.exit(0)
print(mo.group(1), mn.group(1))
PY
}

# ── Self-test ───────────────────────────────────────────────────────────────
self_test() {
    local p=0 f=0 rc
    local ok no
    ok() { echo "  PASS: $1"; p=$((p+1)); }
    no() { echo "  FAIL: $1"; f=$((f+1)); }

    echo "=== goalforge-transition-guard.sh --self-test ==="

    # illegal edge → exit 2
    do_check spec nonsense; rc=$?
    [[ "$rc" -eq 2 ]] && ok "illegal edge -> exit 2" || no "illegal edge should exit 2 (got $rc)"

    # legal edge → exit 0
    do_check spec hardened; rc=$?
    [[ "$rc" -eq 0 ]] && ok "legal forward edge -> exit 0" || no "legal edge should exit 0 (got $rc)"

    # legal reverse edge → exit 0 (free-reverse)
    do_check verified spec; rc=$?
    [[ "$rc" -eq 0 ]] && ok "legal reverse edge -> exit 0 (free-reverse)" || no "reverse edge should exit 0 (got $rc)"

    # internal error (missing state-machine) → exit 0 (zero-breakage)
    local save="$STATE_MACHINE"
    STATE_MACHINE="/nonexistent/state-machine.md"
    do_check spec hardened; rc=$?
    STATE_MACHINE="$save"
    [[ "$rc" -eq 0 ]] && ok "internal error -> exit 0 (zero-breakage)" || no "internal error should exit 0 (got $rc)"

    echo ""
    echo "Results: $p passed, $f failed"
    [[ "$f" -eq 0 ]]
}

# ── Argument parsing ────────────────────────────────────────────────────────
FROM=""
TO=""
SELFTEST=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-test) SELFTEST=1; shift ;;
        --from)      FROM="${2:-}"; shift 2 ;;
        --to)        TO="${2:-}"; shift 2 ;;
        *)           shift ;;   # ignore unknown args (zero-breakage)
    esac
done

if [[ "$SELFTEST" -eq 1 ]]; then
    self_test
    exit $?
fi

# Explicit --from/--to path.
if [[ -n "$FROM" && -n "$TO" ]]; then
    do_check "$FROM" "$TO"
    exit $?
fi

# Hook path: derive from/to from the PreToolUse Edit event on stdin.
read -r FROM TO < <(parse_stdin) || true
if [[ -z "${FROM:-}" || -z "${TO:-}" ]]; then
    exit 0   # not a WP-status edit, or parse failed → never block
fi
do_check "$FROM" "$TO"
exit $?
