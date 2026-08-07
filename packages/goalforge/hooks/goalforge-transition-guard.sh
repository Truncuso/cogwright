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
# SCOPE: wired as a PreToolUse hook (hooks.json, matcher `Edit` — it reads an
# Edit payload's old_string/new_string and can evaluate nothing else; a status
# change via Write/MultiEdit is blocked outright by goalforge-single-writer).
# Fast path: exit 0, silently, unless the edited file resolves under a plans
# root — resolution order owned by the sourced goalforge-plans-root.sh.
#
# Usage:
#   <PreToolUse JSON on stdin> | goalforge-transition-guard.sh
#   goalforge-transition-guard.sh --from <state> --to <state>
#   goalforge-transition-guard.sh --self-test
set -uo pipefail

# readlink -f resolves the dotfiles install route, where the file at
# ~/.claude/hooks/ is a SYMLINK into the package: HOOK_DIR then names the real
# hooks/ dir, so the single sibling-relative state-machine address below holds
# for all three routes (package, plugin, dotfiles symlink) — no second climb.
HOOK_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")" && pwd)"
SELF="$HOOK_DIR/$(basename "${BASH_SOURCE[0]}")"
STATE_MACHINE="$HOOK_DIR/../references/state-machine.md"
# shellcheck source=./goalforge-plans-root.sh
. "$HOOK_DIR/goalforge-plans-root.sh" 2>/dev/null || {
    echo "goalforge-transition-guard: goalforge-plans-root.sh not found beside the hook — skipping (zero-breakage)" >&2
    exit 0
}

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
# An unresolvable table still passes open (zero-breakage) — but it does so
# LOUDLY: a silently dead gate is indistinguishable from a working one, so the
# one condition an operator cannot otherwise observe gets a stderr note.
do_check() {
    local v
    if [[ ! -r "$STATE_MACHINE" ]]; then
        echo "goalforge-transition-guard: note — state-machine table unreadable at $STATE_MACHINE; edge legality NOT checked (passing open)." >&2
        return 0
    fi
    v="$(edge_verdict "$STATE_MACHINE" "$1" "$2")"
    [[ "$v" == "illegal" ]] && return 2 || return 0
}

# ── Cheap bash prefilter ────────────────────────────────────────────────────
# Runs on the raw payload BEFORE any interpreter spawn, on every Edit in the
# session. CONSERVATIVE by construction: it returns 1 only for a payload that
# CANNOT be ours (no overview.md anywhere in the text, or a plainly-extractable
# file_path outside every plans root). Anything it cannot judge — no file_path
# key, a quoted path carrying escapes — returns 0 and falls through to the
# python parser, which stays the authority.
prefilter() {
    local raw="$1" rest fp
    case "$raw" in *overview.md*) ;; *) return 1 ;; esac
    rest="${raw#*\"file_path\":}"
    [[ "$rest" == "$raw" ]] && return 0          # no file_path key -> parser decides
    rest="${rest#"${rest%%[![:space:]]*}"}"      # drop leading whitespace
    case "$rest" in \"*) rest="${rest#\"}"; fp="${rest%%\"*}" ;; *) return 0 ;; esac
    case "$fp" in *\\*) return 0 ;; esac         # escaped path -> parser decodes it
    goalforge_under_plans_root "$fp" || return 1
    return 0
}

# Parse a PreToolUse Edit event from stdin → prints "<from> <to> <file>" or
# nothing.
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
print(mo.group(1), mn.group(1), fp)
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

    # PLANS_ROOT resolution pair (spec §Interface Contract): the SAME illegal
    # edge engages under $SDD_PLANS_DIR and fast-paths silently outside every
    # resolved root. Driven through a SUBPROCESS so the assertion covers the
    # real stdin entry point, not just do_check().
    local d payload pos_out neg_out pos_rc neg_rc
    d="$(mktemp -d)"
    mkdir -p "$d/plans/f" "$d/elsewhere"
    # `spec -> archived` is enum-valid (so the payload parser yields an edge)
    # but carries no row in the edges table, i.e. a confirmed illegal edge.
    payload() { # <overview path>
        python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":"status: spec\n","new_string":"status: archived\n"}}))' "$1"
    }
    pos_out="$(payload "$d/plans/f/overview.md" | SDD_PLANS_DIR="$d/plans" bash "$SELF" 2>&1)"; pos_rc=$?
    { [[ -n "$pos_out" ]] || [[ "$pos_rc" -ne 0 ]]; } \
        && ok "illegal edge under \$SDD_PLANS_DIR -> hook engaged" \
        || no "under \$SDD_PLANS_DIR should engage (rc=$pos_rc, out='$pos_out')"

    neg_out="$(payload "$d/elsewhere/overview.md" | SDD_PLANS_DIR="$d/plans" bash "$SELF" 2>&1)"; neg_rc=$?
    { [[ "$neg_rc" -eq 0 ]] && [[ -z "$neg_out" ]]; } \
        && ok "same edge outside every plans root -> silent exit-0 fast path" \
        || no "outside every plans root should fast-path silently (rc=$neg_rc, out='$neg_out')"

    # The blocking path must SAY why: exit 2 with an empty stderr leaves the
    # operator with a refused edit and no reason. stderr only — stdout stays
    # clean for the hook protocol.
    local blk_err blk_rc
    blk_err="$(payload "$d/plans/f/overview.md" | SDD_PLANS_DIR="$d/plans" bash "$SELF" 2>&1 >/dev/null)"; blk_rc=$?
    { [[ "$blk_rc" -eq 2 ]] && [[ -n "$blk_err" ]]; } \
        && ok "blocked edge -> exit 2 with a non-empty stderr reason" \
        || no "blocked edge should print a reason (rc=$blk_rc, err='$blk_err')"

    # PLANS_ROOT legs 2 and 3 (spec §Interface Contract). SDD_PLANS_DIR is UNSET
    # for all four and $HOME points at an empty sandbox, so each case can only
    # pass through the leg it names: deleting the git-root leg or the
    # ~/.claude/plans leg from goalforge-plans-root.sh turns one of these red.
    local hs="$d/home"
    mkdir -p "$hs/.claude/plans/f" "$hs/.claude/notplans"
    git init -q "$d/leg2repo" 2>/dev/null
    mkdir -p "$d/leg2repo/plans/f" "$d/leg2repo/notplans"
    leg() { # <label> <overview path> <engage|silent>
        local out rc
        out="$(payload "$2" | env -u SDD_PLANS_DIR HOME="$hs" bash "$SELF" 2>&1)"; rc=$?
        if [[ "$3" == engage ]]; then
            { [[ -n "$out" ]] || [[ "$rc" -ne 0 ]]; } && ok "$1" || no "$1 (rc=$rc, out='$out')"
        else
            { [[ "$rc" -eq 0 ]] && [[ -z "$out" ]]; } && ok "$1" || no "$1 (rc=$rc, out='$out')"
        fi
    }
    leg "leg 2: <git-root>/plans/** -> hook engaged"               "$d/leg2repo/plans/f/overview.md"   engage
    leg "leg 2 negative: same git repo outside plans/ -> silent"   "$d/leg2repo/notplans/overview.md"  silent
    leg "leg 3: \$HOME/.claude/plans/** -> hook engaged"           "$hs/.claude/plans/f/overview.md"   engage
    leg "leg 3 negative: \$HOME/.claude outside plans/ -> silent"  "$hs/.claude/notplans/overview.md"  silent

    rm -rf "$d"

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

# Hook path: derive from/to (+ the edited file) from the PreToolUse event on
# stdin. The payload is slurped ONCE here so the bash prefilter can reject the
# overwhelming majority of Edits without spawning python at all; only a payload
# that survives it reaches the parser. `read` splits on IFS, so FILE takes the
# remainder of the line — a path containing spaces stays intact.
RAW="$(cat 2>/dev/null || true)"
[[ -n "$RAW" ]] || exit 0
prefilter "$RAW" || exit 0
FILE=""
read -r FROM TO FILE < <(printf '%s' "$RAW" | parse_stdin) || true
if [[ -z "${FROM:-}" || -z "${TO:-}" ]]; then
    exit 0   # not a WP-status edit, or parse failed → never block
fi
# Fast path: a status edit outside every resolved plans root is not ours.
goalforge_under_plans_root "${FILE:-}" || exit 0
do_check "$FROM" "$TO"
rc=$?
if [[ "$rc" -eq 2 ]]; then
    echo "goalforge-transition-guard: BLOCK — $FILE: '$FROM -> $TO' is not an edge in references/state-machine.md; use goalforge-transition.sh." >&2
    exit 2
fi
exit 0
