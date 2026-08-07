#!/usr/bin/env bash
# goalforge-open-questions-gate.sh — dormant PreToolUse-style guard.
#
# Blocks a WP `→ ready` status edit while its `overview.md` still holds an
# UNRESOLVED open question. The hard backstop under the soft, human-gated
# `hardened → ready` transition in the goalforge-harden skill.
#
# An open question is a bullet under the `## Open Questions` section. A bullet is
# RESOLVED when its text (after the bullet marker) begins with one of:
#   ~~  [x]  [X]  [resolved]  [assumption]  [deferred]  RESOLVED  ASSUMPTION  DEFERRED
# or with `[risk-accepted: <id>]` where <id> resolves to a `- id: <id>` entry
# under the same file's `## Risks` section (schema.md §Risks block). A bare
# `[risk-accepted]` or a dangling id counts as UNRESOLVED — the marker is the
# link, the Risks row is the record.
# An absent or empty `## Open Questions` section passes (no open questions).
#
# Sibling of goalforge-transition-guard.sh: it catches HAND-edits to `status:`. The
# canonical writer (goalforge-transition.sh) writes status directly, not via the Edit
# tool, so this guard is the backstop for the manual path.
#
# ZERO-BREAKAGE: exit 0 on ANY internal error (missing input, parse failure,
# unreadable file) — a hook must never block because it itself failed. The ONLY
# non-zero exit is exit 2 for a confirmed `→ready` edit with >=1 unresolved OQ.
#
# SCOPE: wired as a PreToolUse hook (hooks.json, matcher `Edit` — it reads an
# Edit payload's old_string/new_string and can evaluate nothing else; a status
# change via Write/MultiEdit is blocked outright by goalforge-single-writer).
# Fast path: exit 0, silently, unless the edited file resolves under a plans
# root — resolution order owned by the sourced goalforge-plans-root.sh.
#
# Usage:
#   <PreToolUse Edit JSON on stdin> | goalforge-open-questions-gate.sh
#   goalforge-open-questions-gate.sh --check <overview.md>     # prints unresolved count
#   goalforge-open-questions-gate.sh --self-test
set -uo pipefail

# readlink -f so the dotfiles install route (a symlink in ~/.claude/hooks/
# pointing into the package) still finds the sibling helper.
HOOK_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")" && pwd)"
SELF="$HOOK_DIR/$(basename "${BASH_SOURCE[0]}")"
# shellcheck source=./goalforge-plans-root.sh
. "$HOOK_DIR/goalforge-plans-root.sh" 2>/dev/null || {
    echo "goalforge-open-questions-gate: goalforge-plans-root.sh not found beside the hook — skipping (zero-breakage)" >&2
    exit 0
}

# ── Unresolved-OQ count: prints an integer (0 on ANY error) ─────────────────
unresolved_count() {
    # arg: <overview.md path>
    python3 - "$1" <<'PY' 2>/dev/null || echo 0
import sys, re
try:
    text = open(sys.argv[1], encoding="utf-8").read()
except OSError:
    print(0); sys.exit(0)
RESOLVED_PREFIX = ("~~", "[x]", "[X]", "[resolved]", "[assumption]", "[deferred]")
RESOLVED_WORD = ("RESOLVED", "ASSUMPTION", "DEFERRED")

# Risk ids: `- id: <id>` entries under the `## Risks` section (schema.md
# §Risks block). A [risk-accepted: <id>] bullet resolves iff <id> is here.
risk_ids, in_risks = set(), False
for ln in text.splitlines():
    h = re.match(r"^#{1,6}\s+(.*?)\s*$", ln)
    if h:
        in_risks = h.group(1).strip().lower() == "risks"
        continue
    if in_risks:
        r = re.match(r"^\s*-\s*id:\s*(\S+)\s*$", ln)
        if r:
            risk_ids.add(r.group(1))

in_oq = False
unresolved = 0
for ln in text.splitlines():
    h = re.match(r"^#{1,6}\s+(.*?)\s*$", ln)
    if h:
        in_oq = h.group(1).strip().lower() == "open questions"
        continue
    if not in_oq:
        continue
    b = re.match(r"^\s*[-*]\s+(.*\S)\s*$", ln)
    if not b:
        continue
    body = b.group(1)
    if any(body.startswith(p) for p in RESOLVED_PREFIX):
        continue
    if any(body.upper().startswith(w) for w in RESOLVED_WORD):
        continue
    ra = re.match(r"^\[risk-accepted:\s*([^\]\s]+)\s*\]", body)
    if ra and ra.group(1) in risk_ids:
        continue                     # linked accepted risk = resolved
    unresolved += 1                  # incl. bare/dangling [risk-accepted]
print(unresolved)
PY
}

# Parse a PreToolUse Edit event from stdin. Prints the overview.md path ONLY when
# the edit is a transition whose NEW status is `ready` and old status is not
# already `ready`. Prints nothing otherwise (caller treats that as exit 0).
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
if not mn or mn.group(1) != "ready":
    sys.exit(0)                      # not a transition INTO ready
if mo and mo.group(1) == "ready":
    sys.exit(0)                      # already ready → no transition
print(fp)
PY
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

# Returns 2 if file has >=1 unresolved OQ, else 0. Zero-breakage on a bad path.
do_check() {
    local n
    [[ -f "$1" ]] || return 0
    n="$(unresolved_count "$1")"
    [[ "${n:-0}" =~ ^[0-9]+$ ]] || return 0
    [[ "$n" -gt 0 ]] && return 2 || return 0
}

# ── Self-test ───────────────────────────────────────────────────────────────
self_test() {
    local p=0 f=0 rc n d
    ok() { echo "  PASS: $1"; p=$((p+1)); }
    no() { echo "  FAIL: $1"; f=$((f+1)); }

    echo "=== goalforge-open-questions-gate.sh --self-test ==="
    d="$(mktemp -d)"
    trap 'rm -rf "$d"' RETURN

    # 2 unmarked OQ → count 2
    printf -- '## Open Questions\n\n- OQ1: a?\n- OQ2: b?\n' > "$d/two.md"
    n="$(unresolved_count "$d/two.md")"
    [[ "$n" -eq 2 ]] && ok "two unmarked OQ -> count 2" || no "two unmarked OQ -> count $n (want 2)"

    # all marked resolved → count 0
    printf -- '## Open Questions\n\n- [resolved] OQ1\n- ~~OQ2~~\n- ASSUMPTION OQ3\n- [deferred] OQ4\n' > "$d/done.md"
    n="$(unresolved_count "$d/done.md")"
    [[ "$n" -eq 0 ]] && ok "all-marked OQ -> count 0" || no "all-marked OQ -> count $n (want 0)"

    # no OQ section → count 0
    printf -- '## Goal\n\nstuff\n' > "$d/none.md"
    n="$(unresolved_count "$d/none.md")"
    [[ "$n" -eq 0 ]] && ok "no OQ section -> count 0" || no "no OQ section -> count $n (want 0)"

    # risk-accepted with a resolving Risks row → count 0
    printf -- '## Open Questions\n\n- [risk-accepted: retry-storm] OQ1?\n\n## Risks\n\n- id: retry-storm\n  risk: burst retries\n  impact: LOW\n  likelihood: LOW\n  owner: session\n  revisit: at goalforge-verify\n' > "$d/risk-ok.md"
    n="$(unresolved_count "$d/risk-ok.md")"
    [[ "$n" -eq 0 ]] && ok "linked risk-accepted -> count 0" || no "linked risk-accepted -> count $n (want 0)"

    # dangling risk-accepted id → count 1
    printf -- '## Open Questions\n\n- [risk-accepted: ghost] OQ1?\n\n## Risks\n\n- id: other\n' > "$d/risk-dangling.md"
    n="$(unresolved_count "$d/risk-dangling.md")"
    [[ "$n" -eq 1 ]] && ok "dangling risk-accepted -> count 1" || no "dangling risk-accepted -> count $n (want 1)"

    # bare [risk-accepted] with no id → count 1
    printf -- '## Open Questions\n\n- [risk-accepted] OQ1?\n\n## Risks\n\n- id: x\n' > "$d/risk-bare.md"
    n="$(unresolved_count "$d/risk-bare.md")"
    [[ "$n" -eq 1 ]] && ok "bare risk-accepted -> count 1" || no "bare risk-accepted -> count $n (want 1)"

    # next heading ends the section (a later bullet is not an OQ)
    printf -- '## Open Questions\n\n- [x] OQ1\n\n## Tasks\n\n- raw task bullet\n' > "$d/scoped.md"
    n="$(unresolved_count "$d/scoped.md")"
    [[ "$n" -eq 0 ]] && ok "section scoped to its heading -> count 0" || no "section scope leak -> count $n (want 0)"

    # do_check: unresolved → 2, clean → 0
    do_check "$d/two.md"; rc=$?
    [[ "$rc" -eq 2 ]] && ok "do_check unresolved -> exit 2" || no "do_check unresolved -> exit $rc (want 2)"
    do_check "$d/done.md"; rc=$?
    [[ "$rc" -eq 0 ]] && ok "do_check clean -> exit 0" || no "do_check clean -> exit $rc (want 0)"

    # zero-breakage: missing file → exit 0
    do_check "$d/missing.md"; rc=$?
    [[ "$rc" -eq 0 ]] && ok "missing file -> exit 0 (zero-breakage)" || no "missing file -> exit $rc (want 0)"

    # parse_stdin: →ready overview edit prints the path
    local out
    out="$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"x/overview.md","old_string":"status: hardened","new_string":"status: ready"}}' | parse_stdin)"
    [[ "$out" == "x/overview.md" ]] && ok "parse_stdin ->ready prints path" || no "parse_stdin ->ready got '$out'"

    # parse_stdin: →spec edit prints nothing (only gates ready)
    out="$(printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"x/overview.md","old_string":"status: draft","new_string":"status: spec"}}' | parse_stdin)"
    [[ -z "$out" ]] && ok "parse_stdin ->spec prints nothing" || no "parse_stdin ->spec got '$out'"

    # PLANS_ROOT resolution pair (spec §Interface Contract): the SAME →ready
    # edit on an overview carrying an unresolved OQ engages under
    # $SDD_PLANS_DIR and fast-paths silently outside every resolved root.
    # Driven through a SUBPROCESS so the real stdin entry point is covered.
    local pos_out neg_out pos_rc neg_rc oq
    oq='## Open Questions\n\n- OQ1: unresolved?\n'
    mkdir -p "$d/plans/f" "$d/elsewhere"
    printf -- "$oq" > "$d/plans/f/overview.md"
    printf -- "$oq" > "$d/elsewhere/overview.md"
    payload() { # <overview path>
        python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":"status: hardened","new_string":"status: ready"}}))' "$1"
    }
    pos_out="$(payload "$d/plans/f/overview.md" | SDD_PLANS_DIR="$d/plans" bash "$SELF" 2>&1)"; pos_rc=$?
    { [[ -n "$pos_out" ]] || [[ "$pos_rc" -ne 0 ]]; } \
        && ok "->ready with an open question under \$SDD_PLANS_DIR -> hook engaged" \
        || no "under \$SDD_PLANS_DIR should engage (rc=$pos_rc, out='$pos_out')"

    neg_out="$(payload "$d/elsewhere/overview.md" | SDD_PLANS_DIR="$d/plans" bash "$SELF" 2>&1)"; neg_rc=$?
    { [[ "$neg_rc" -eq 0 ]] && [[ -z "$neg_out" ]]; } \
        && ok "same edit outside every plans root -> silent exit-0 fast path" \
        || no "outside every plans root should fast-path silently (rc=$neg_rc, out='$neg_out')"

    # PLANS_ROOT legs 2 and 3 (spec §Interface Contract). SDD_PLANS_DIR is UNSET
    # for all four and $HOME points at an empty sandbox, so each case can only
    # pass through the leg it names: deleting the git-root leg or the
    # ~/.claude/plans leg from goalforge-plans-root.sh turns one of these red.
    local hs="$d/home"
    mkdir -p "$hs/.claude/plans/f" "$hs/.claude/notplans"
    git init -q "$d/leg2repo" 2>/dev/null
    mkdir -p "$d/leg2repo/plans/f" "$d/leg2repo/notplans"
    local lf
    for lf in "$d/leg2repo/plans/f" "$d/leg2repo/notplans" "$hs/.claude/plans/f" "$hs/.claude/notplans"; do
        printf -- "$oq" > "$lf/overview.md"
    done
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

    echo ""
    echo "Results: $p passed, $f failed"
    [[ "$f" -eq 0 ]]
}

# ── Argument parsing ────────────────────────────────────────────────────────
CHECK=""
SELFTEST=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-test) SELFTEST=1; shift ;;
        --check)     CHECK="${2:-}"; shift 2 ;;
        *)           shift ;;   # ignore unknown args (zero-breakage)
    esac
done

if [[ "$SELFTEST" -eq 1 ]]; then
    self_test
    exit $?
fi

if [[ -n "$CHECK" ]]; then
    unresolved_count "$CHECK"
    exit 0
fi

# Hook path: derive the →ready overview path from the PreToolUse Edit event.
# The payload is slurped ONCE here so the bash prefilter can reject the
# overwhelming majority of Edits without spawning python at all; only a payload
# that survives it reaches the parser.
RAW="$(cat 2>/dev/null || true)"
[[ -n "$RAW" ]] || exit 0
prefilter "$RAW" || exit 0
FILE="$(printf '%s' "$RAW" | parse_stdin)" || true
[[ -z "${FILE:-}" ]] && exit 0   # not a →ready overview edit → never block
# Fast path: a →ready edit outside every resolved plans root is not ours.
goalforge_under_plans_root "$FILE" || exit 0

do_check "$FILE"
rc=$?
if [[ "$rc" -eq 2 ]]; then
    n="$(unresolved_count "$FILE")"
    echo "goalforge-open-questions-gate: BLOCK — $FILE has $n unresolved open question(s); '→ ready' refused." >&2
    echo "Resolve via goalforge-harden (the interview plugin engine), or mark each bullet in '## Open Questions' resolved ([resolved] | [assumption] | [deferred] | ~~…~~)." >&2
    exit 2
fi
exit 0
