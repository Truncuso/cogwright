#!/usr/bin/env bash
# goalforge-frontmatter-touch.sh — PostToolUse hook for Write|Edit.
#
# Reads the edited file path from the hook payload (stdin JSON).
# If the path is under a resolved PLANS_ROOT and ends in .md, bumps
# `updated:` (and `stage_updated:` if present) in the frontmatter
# to today's date (YYYY-MM-DD). Idempotent: no write if already today.
# Only touches the frontmatter block (between the first two --- lines).
# No-op silently for non-plans paths or non-.md files.
#
# PLANS_ROOT resolution ($SDD_PLANS_DIR → <git-root>/plans → ~/.claude/plans)
# is owned by the sourced goalforge-plans-root.sh — never re-implemented here.
#
# Discipline:
#   - Never breaks the session: every failure path exits 0.
#   - Never mutates files outside a resolved PLANS_ROOT.
#   - No write when values are already current.
#
# Usage:
#   <PostToolUse JSON on stdin> | goalforge-frontmatter-touch.sh
#   goalforge-frontmatter-touch.sh --self-test

set -uo pipefail

# readlink -f so the dotfiles install route (a symlink in ~/.claude/hooks/
# pointing into the package) still finds the sibling helper.
HOOK_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")" && pwd)"
SELF="$HOOK_DIR/$(basename "${BASH_SOURCE[0]}")"
# shellcheck source=./goalforge-plans-root.sh
. "$HOOK_DIR/goalforge-plans-root.sh" 2>/dev/null || {
    echo "goalforge-frontmatter-touch: goalforge-plans-root.sh not found beside the hook — skipping (zero-breakage)" >&2
    exit 0
}

TODAY=$(date +%F)

# ── Self-test ──────────────────────────────────────────────────────────────
# Runs BEFORE stdin is slurped below: this hook otherwise blocks in `cat`, so a
# --self-test invocation from a terminal or a CI step would hang.
self_test() {
    local p=0 f=0 d pos_out neg_out pos_rc neg_rc
    ok() { echo "  PASS: $1"; p=$((p+1)); }
    no() { echo "  FAIL: $1"; f=$((f+1)); }

    echo "=== goalforge-frontmatter-touch.sh --self-test ==="
    d="$(mktemp -d)"
    mkdir -p "$d/plans/f" "$d/elsewhere"

    # PLANS_ROOT resolution pair (spec §Interface Contract): the SAME stale
    # frontmatter is bumped under $SDD_PLANS_DIR and left untouched outside
    # every resolved root. Driven through a SUBPROCESS so the real stdin entry
    # point is covered.
    printf -- '---\nupdated: 1999-01-01\n---\nbody\n' > "$d/plans/f/overview.md"
    printf -- '---\nupdated: 1999-01-01\n---\nbody\n' > "$d/elsewhere/overview.md"
    payload() { # <file path>
        python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1]}}))' "$1"
    }

    pos_out="$(payload "$d/plans/f/overview.md" | SDD_PLANS_DIR="$d/plans" bash "$SELF" 2>&1)"; pos_rc=$?
    if grep -q "updated: $TODAY" "$d/plans/f/overview.md"; then
        ok "under \$SDD_PLANS_DIR -> updated: bumped to $TODAY"
    else
        no "under \$SDD_PLANS_DIR should bump updated: (rc=$pos_rc, out='$pos_out')"
    fi

    neg_out="$(payload "$d/elsewhere/overview.md" | SDD_PLANS_DIR="$d/plans" bash "$SELF" 2>&1)"; neg_rc=$?
    if [ "$neg_rc" = 0 ] && [ -z "$neg_out" ] && grep -q 'updated: 1999-01-01' "$d/elsewhere/overview.md"; then
        ok "outside every plans root -> silent exit-0 fast path, file untouched"
    else
        no "outside every plans root should fast-path silently (rc=$neg_rc, out='$neg_out')"
    fi

    # Idempotence: a second run over an already-current file changes nothing.
    local before after
    before="$(cat "$d/plans/f/overview.md")"
    payload "$d/plans/f/overview.md" | SDD_PLANS_DIR="$d/plans" bash "$SELF" >/dev/null 2>&1
    after="$(cat "$d/plans/f/overview.md")"
    [ "$before" = "$after" ] && ok "already-current file -> no write (idempotent)" \
        || no "already-current file was rewritten"

    # Zero-breakage: empty stdin exits 0.
    printf '' | bash "$SELF" >/dev/null 2>&1
    [ $? -eq 0 ] && ok "empty payload -> exit 0 (zero-breakage)" || no "empty payload should exit 0"

    # Zero-breakage on the WRITE: an unwritable target must exit 0, silently,
    # with the file left alone — the bump is best-effort, never a hard failure.
    local ro_out ro_rc
    printf -- '---\nupdated: 1999-01-01\n---\nbody\n' > "$d/plans/f/readonly.md"
    chmod a-w "$d/plans/f/readonly.md"
    if [ "$(id -u)" = 0 ]; then
        ok "unwritable target -> exit 0 silent (skipped: running as root, chmod is not enforced)"
    else
        ro_out="$(payload "$d/plans/f/readonly.md" | SDD_PLANS_DIR="$d/plans" bash "$SELF" 2>&1)"; ro_rc=$?
        if [ "$ro_rc" = 0 ] && [ -z "$ro_out" ] && grep -q 'updated: 1999-01-01' "$d/plans/f/readonly.md"; then
            ok "unwritable target -> exit 0 silent, file untouched"
        else
            no "unwritable target should exit 0 silently (rc=$ro_rc, out='$ro_out')"
        fi
    fi
    chmod u+w "$d/plans/f/readonly.md"

    # Zero-breakage on the INTERPRETER: python3 absent from PATH must exit 0.
    # The sandbox PATH carries only the other commands the hook needs, so the
    # run reaches the frontmatter step and dies there rather than short-circuiting
    # somewhere harmless earlier.
    local sb="$d/bin" c np_out np_rc
    mkdir -p "$sb"
    for c in bash readlink dirname basename date cat jq git grep sed; do
        ln -sf "$(command -v "$c" 2>/dev/null)" "$sb/$c" 2>/dev/null || true
    done
    printf -- '---\nupdated: 1999-01-01\n---\nbody\n' > "$d/plans/f/nopy.md"
    np_out="$(payload "$d/plans/f/nopy.md" | PATH="$sb" SDD_PLANS_DIR="$d/plans" bash "$SELF" 2>&1)"; np_rc=$?
    { [ "$np_rc" = 0 ] && grep -q 'updated: 1999-01-01' "$d/plans/f/nopy.md"; } \
        && ok "python3 missing from PATH -> exit 0 (zero-breakage)" \
        || no "python3 missing from PATH should exit 0 (rc=$np_rc, out='$np_out')"
    # Positive control for the case above: the SAME sandbox PATH plus python3
    # does bump the file — proving the run reaches the frontmatter step and is
    # not short-circuiting on some earlier missing command.
    ln -sf "$(command -v python3)" "$sb/python3" 2>/dev/null || true
    payload "$d/plans/f/nopy.md" | PATH="$sb" SDD_PLANS_DIR="$d/plans" bash "$SELF" >/dev/null 2>&1
    grep -q "updated: $TODAY" "$d/plans/f/nopy.md" \
        && ok "sandbox PATH + python3 -> bumped (control: the interpreter step is reached)" \
        || no "sandbox PATH + python3 should bump (control)"

    # PLANS_ROOT legs 2 and 3 (spec §Interface Contract). SDD_PLANS_DIR is UNSET
    # for all four and $HOME points at an empty sandbox, so each case can only
    # pass through the leg it names: deleting the git-root leg or the
    # ~/.claude/plans leg from goalforge-plans-root.sh turns one of these red.
    local hs="$d/home" lf
    mkdir -p "$hs/.claude/plans/f" "$hs/.claude/notplans"
    git init -q "$d/leg2repo" 2>/dev/null
    mkdir -p "$d/leg2repo/plans/f" "$d/leg2repo/notplans"
    for lf in "$d/leg2repo/plans/f" "$d/leg2repo/notplans" "$hs/.claude/plans/f" "$hs/.claude/notplans"; do
        printf -- '---\nupdated: 1999-01-01\n---\nbody\n' > "$lf/overview.md"
    done
    leg() { # <label> <overview path> <engage|silent>
        local out rc
        out="$(payload "$2" | env -u SDD_PLANS_DIR HOME="$hs" bash "$SELF" 2>&1)"; rc=$?
        if [ "$3" = engage ]; then
            { [ "$rc" = 0 ] && [ -z "$out" ] && grep -q "updated: $TODAY" "$2"; } \
                && ok "$1" || no "$1 (rc=$rc, out='$out')"
        else
            { [ "$rc" = 0 ] && [ -z "$out" ] && grep -q 'updated: 1999-01-01' "$2"; } \
                && ok "$1" || no "$1 (rc=$rc, out='$out')"
        fi
    }
    leg "leg 2: <git-root>/plans/** -> updated: bumped"             "$d/leg2repo/plans/f/overview.md"   engage
    leg "leg 2 negative: same git repo outside plans/ -> untouched" "$d/leg2repo/notplans/overview.md"  silent
    leg "leg 3: \$HOME/.claude/plans/** -> updated: bumped"         "$hs/.claude/plans/f/overview.md"   engage
    leg "leg 3 negative: \$HOME/.claude outside plans/ -> untouched" "$hs/.claude/notplans/overview.md" silent

    rm -rf "$d"
    echo ""
    echo "Results: $p passed, $f failed"
    [ "$f" -eq 0 ]
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

# ── Parse payload ──────────────────────────────────────────────────────────

HOOK_INPUT=$(cat 2>/dev/null || true)
[ -n "$HOOK_INPUT" ] || exit 0

FILE_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '
  .tool_input.file_path // .tool_input.path // ""
' 2>/dev/null) || exit 0

[ -n "$FILE_PATH" ] || exit 0

# ── Guard: must be under a resolved PLANS_ROOT and end in .md ──────────────

# Resolve to absolute path
case "$FILE_PATH" in
  /*) ;;
  "~/"*) FILE_PATH="${HOME}/${FILE_PATH#\~/}" ;;
  *) exit 0 ;;
esac

REAL_PATH="$(goalforge_normpath "$FILE_PATH")"
case "$REAL_PATH" in *.md) ;; *) exit 0 ;; esac
goalforge_under_plans_root "$REAL_PATH" || exit 0

[ -f "$REAL_PATH" ] || exit 0

# ── Bump frontmatter dates ─────────────────────────────────────────────────

# ZERO-BREAKAGE on the terminating statement: this is the LAST command, so its
# status is the hook's. `2>/dev/null` keeps a traceback out of the session
# transcript and `|| exit 0` covers everything an in-python guard cannot — a
# missing/broken python3 (127), a signal, an unforeseen exception.
python3 - "$REAL_PATH" "$TODAY" 2>/dev/null <<'PYEOF' || exit 0
import sys
import re

path = sys.argv[1]
today = sys.argv[2]

# A read this hook cannot perform is not the session's problem: bail silently.
try:
    with open(path, 'r', encoding='utf-8') as fh:
        content = fh.read()
except OSError:
    sys.exit(0)

# Locate frontmatter: must start at line 0 with ---
lines = content.split('\n')
if not lines or lines[0].strip() != '---':
    sys.exit(0)

# Find closing ---
end_idx = None
for i in range(1, len(lines)):
    if lines[i].strip() == '---':
        end_idx = i
        break

if end_idx is None:
    sys.exit(0)

fm_lines = lines[1:end_idx]
changed = False

updated_re = re.compile(r'^(updated:\s*)(.+)$')
stage_re   = re.compile(r'^(stage_updated:\s*)(.+)$')

new_fm = []
for line in fm_lines:
    m = updated_re.match(line)
    if m:
        if m.group(2).strip() != today:
            line = m.group(1) + today
            changed = True
        new_fm.append(line)
        continue
    m = stage_re.match(line)
    if m:
        if m.group(2).strip() != today:
            line = m.group(1) + today
            changed = True
        new_fm.append(line)
        continue
    new_fm.append(line)

if not changed:
    sys.exit(0)

new_content = '\n'.join(['---'] + new_fm + lines[end_idx:])
# An unwritable target (read-only file, read-only mount) must never surface as
# a failing PostToolUse hook — the bump is best-effort by design.
try:
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(new_content)
except OSError:
    sys.exit(0)
PYEOF
exit 0
