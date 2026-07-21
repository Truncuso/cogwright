#!/usr/bin/env bash
# sdd-rewire-impact.sh — migration rewire-impact scan + post-move dangling gate.
#
# Usage:
#   sdd-rewire-impact.sh [--root <dir>] <path>              # BEFORE a move: list references
#   sdd-rewire-impact.sh --post-move [--root <dir>] <path>  # AFTER a move: dangling-ref gate
#   sdd-rewire-impact.sh --deletion-advisory [--root <dir>] <path>  # DELETION: non-blocking
#                                                           #   advisory, refs split live vs
#                                                           #   test-only (exit 0 always)
#   sdd-rewire-impact.sh --self-test
#
# Args:
#   <path>          Repo-relative path being moved (matched as a FIXED string,
#                   so `skills/x/old.sh` also matches `~/.claude/skills/x/old.sh`).
#   --post-move     Gate mode: ERROR (exit 1) if any reference to <path> remains.
#   --root <dir>    Search root (default: git toplevel of CWD, else CWD).
#
# Behavior:
#   scan (default)  Lists every reference (file:line:content) to <path> via
#                   ripgrep if available, else `grep -rInF`. Always exits 0 —
#                   finding references before a move is the expected result.
#   --post-move     Greps for the OLD <path> after the move + rewire. Any
#                   remaining reference is a dangling ref → prints them and
#                   exits 1. Clean (zero) → exits 0.
#
#   Exit codes: 0 = clean (scan, or gate with no dangling refs); 1 = dangling
#   references remain (--post-move only); 2 = internal/search error. Diagnostics
#   and the dangling listing print to stderr.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

usage() {
    sed -n '2,25p' "$SELF" | sed 's/^# \{0,1\}//'
}

# ── Collect references ────────────────────────────────────────────────────────
# Echo `file:line:content` for every fixed-string reference to <needle> under
# <root>. ripgrep if available, else `grep -rInF --exclude-dir=.git`.
#
# COVERAGE PARITY (load-bearing for the gate): rg by default skips .gitignored
# AND hidden (dot) paths; the grep fallback skips neither. A dangling reference
# living in a gitignored dir (tmp/, build/) or a hidden dir is STILL a dangling
# reference — missing it is a false-clean, the dangerous direction for a
# migration gate. So pass `--no-ignore --hidden` to make rg search everything
# grep does, and `--glob '!.git'` to re-exclude the git dir (matching grep's
# `--exclude-dir=.git`). Both then exit 0 on match, 1 on no-match (NOT an error
# here), >1 on a real search error — only the last propagates (→ exit 2).
collect_refs() {
    local needle="$1" root="$2" rc=0
    if command -v rg >/dev/null 2>&1; then
        rg --no-heading --line-number --fixed-strings --color=never \
           --no-ignore --hidden --glob '!.git' -- "$needle" "$root" || rc=$?
    else
        grep -rInF --exclude-dir=.git -- "$needle" "$root" || rc=$?
    fi
    [[ "$rc" -gt 1 ]] && return "$rc"
    return 0
}

# ── Scan (before move) ────────────────────────────────────────────────────────
do_scan() {
    local target="$1" root="$2" out n=0
    if ! out="$(collect_refs "$target" "$root")"; then
        echo "ERROR: reference search failed for '$target' under '$root'" >&2
        return 2
    fi
    if [[ -n "$out" ]]; then
        n="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
        printf '%s\n' "$out"
    else
        # Zero refs is legal (nothing to rewire) but a frequent symptom of a
        # mistyped needle — warn on stderr before any rewire work begins.
        echo "WARN: 0 references to '$target' under '$root' — double-check the path/needle is correct before rewiring." >&2
    fi
    echo "Found $n reference(s) to '$target' under '$root'."
    return 0
}

# ── Post-move dangling-reference gate ─────────────────────────────────────────
do_post_move() {
    local target="$1" root="$2" out n=0
    if ! out="$(collect_refs "$target" "$root")"; then
        echo "ERROR: reference search failed for '$target' under '$root'" >&2
        return 2
    fi
    if [[ -n "$out" ]]; then
        n="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
        printf '%s\n' "$out" >&2
        echo "ERROR: $n dangling reference(s) to '$target' remain after move — rewire them before completing the migration." >&2
        return 1
    fi
    echo "OK: no dangling references to '$target' remain under '$root'."
    return 0
}

# ── Deletion advisory (non-blocking) ──────────────────────────────────────────
# Lists references to <path> classified LIVE vs TEST-ONLY and ALWAYS exits 0.
# For a *.py target it also searches the best-effort dotted-module forms
# (a/b/c.py -> a.b.c, c) so dynamic importlib.import_module("a.b.c") importers the
# fixed-path grep misses still surface. Advisory only — the operator decides; the
# scan / --post-move gates are untouched.
_dotted_forms() {
    local p="$1"
    [[ "$p" == *.py ]] || return 0
    local mod="${p%.py}"
    mod="${mod#./}"; mod="${mod#src/}"   # strip common source roots
    local dotted="${mod//\//.}"          # a/b/c -> a.b.c
    local base="${dotted##*.}"           # bare module name
    printf '%s\n' "$dotted"
    [[ "$base" != "$dotted" ]] && printf '%s\n' "$base"
}

_is_test_ref() {
    # arg: a "file:line:content" ref line. True iff the file path looks like a test.
    local file="${1%%:*}" basef
    basef="${file##*/}"
    [[ "$file" == */tests/* || "$file" == */test/* \
       || "$file" == tests/* || "$file" == test/* \
       || "$basef" == test_* || "$basef" == *_test.* ]]
}

do_deletion_advisory() {
    local target="$1" root="$2" all="" out form line live="" test_refs="" ln tn
    out="$(collect_refs "$target" "$root")" || true
    [[ -n "$out" ]] && all+="$out"$'\n'
    while IFS= read -r form; do
        [[ -z "$form" ]] && continue
        out="$(collect_refs "$form" "$root")" || true
        [[ -n "$out" ]] && all+="$out"$'\n'
    done < <(_dotted_forms "$target")
    all="$(printf '%s' "$all" | grep -v '^$' | sort -u || true)"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if _is_test_ref "$line"; then test_refs+="$line"$'\n'; else live+="$line"$'\n'; fi
    done <<< "$all"
    ln="$(printf '%s' "$live" | grep -c . || true)"
    tn="$(printf '%s' "$test_refs" | grep -c . || true)"
    echo "live importers ($ln):"
    if [[ -n "$live" ]]; then printf '%s' "$live"; else echo "  (none)"; fi
    echo "test-only importers ($tn):   # ADVISORY — orphan candidates, non-blocking"
    if [[ -n "$test_refs" ]]; then printf '%s' "$test_refs"; else echo "  (none)"; fi
    return 0
}

# ── Self-test ─────────────────────────────────────────────────────────────────
_ST_TMP=""
self_test() {
    local t_pass=0 t_fail=0 d
    local _OUT _RC

    _ST_TMP="$(mktemp -d)"
    trap '[[ -n "${_ST_TMP:-}" ]] && rm -rf "$_ST_TMP"' EXIT
    d="$_ST_TMP"

    ok() { echo "$1: PASS"; t_pass=$((t_pass+1)); }
    no() { echo "$1: FAIL — $2"; t_fail=$((t_fail+1)); }

    # run_cap <args...> — capture stdout+stderr in _OUT, exit code in _RC; never aborts.
    run_cap() {
        if _OUT="$("$@" 2>&1)"; then _RC=0; else _RC=$?; fi
    }

    echo "=== sdd-rewire-impact.sh --self-test ==="

    # ── Seed a repo-like fixture mirroring a real move ────────────────────────
    # A module at lib/old-module.sh referenced by 3 callers; one unrelated file.
    mkdir -p "$d/lib"
    cat > "$d/lib/old-module.sh" << 'EOF'
#!/usr/bin/env bash
say() { echo "hello from module"; }
EOF
    cat > "$d/caller-a.sh" << 'EOF'
#!/usr/bin/env bash
source lib/old-module.sh
say
EOF
    cat > "$d/caller-b.sh" << 'EOF'
#!/usr/bin/env bash
bash lib/old-module.sh --check
EOF
    cat > "$d/doc.md" << 'EOF'
# Module docs
The entrypoint lives at `lib/old-module.sh` — see it for details.
EOF
    cat > "$d/unrelated.sh" << 'EOF'
#!/usr/bin/env bash
echo "no references here"
EOF

    # ── F1: scan BEFORE move lists all 3 references ───────────────────────────
    run_cap bash "$SELF" --root "$d" "lib/old-module.sh"
    if [[ "$_RC" -eq 0 ]] \
        && grep -q "caller-a.sh" <<<"$_OUT" \
        && grep -q "caller-b.sh" <<<"$_OUT" \
        && grep -q "doc.md" <<<"$_OUT" \
        && grep -q "Found 3 reference" <<<"$_OUT"; then
        ok "F1-scan-lists-refs"
    else
        no "F1-scan-lists-refs" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi

    # ── F2: simulate move leaving ONE dangling ref → post-move ERRORs ─────────
    mv "$d/lib/old-module.sh" "$d/lib/new-module.sh"
    # rewire caller-a + doc, but FORGET caller-b (the dangling reference).
    cat > "$d/caller-a.sh" << 'EOF'
#!/usr/bin/env bash
source lib/new-module.sh
say
EOF
    cat > "$d/doc.md" << 'EOF'
# Module docs
The entrypoint lives at `lib/new-module.sh` — see it for details.
EOF
    run_cap bash "$SELF" --post-move --root "$d" "lib/old-module.sh"
    # Exit MUST be exactly 1 (dangling), not 2 (search error) — proves the split.
    if [[ "$_RC" -eq 1 ]] \
        && grep -q "caller-b.sh" <<<"$_OUT" \
        && grep -q "dangling" <<<"$_OUT"; then
        ok "F2-post-move-dangling-errors"
    else
        no "F2-post-move-dangling-errors" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi

    # ── F3: clean move (rewire the last ref) → post-move exit 0 ───────────────
    cat > "$d/caller-b.sh" << 'EOF'
#!/usr/bin/env bash
bash lib/new-module.sh --check
EOF
    run_cap bash "$SELF" --post-move --root "$d" "lib/old-module.sh"
    if [[ "$_RC" -eq 0 ]] && grep -q "no dangling references" <<<"$_OUT"; then
        ok "F3-clean-move-exit0"
    else
        no "F3-clean-move-exit0" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi

    # ── F4: scan a path with zero references → exit 0, count 0 ────────────────
    run_cap bash "$SELF" --root "$d" "lib/never-existed.sh"
    if [[ "$_RC" -eq 0 ]] && grep -q "Found 0 reference" <<<"$_OUT"; then
        ok "F4-zero-refs-exit0"
    else
        no "F4-zero-refs-exit0" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi

    # ── F5: dangling ref in a GITIGNORED dir AND a HIDDEN dir is still caught ──
    # rg skips both by default → would false-clean the gate; --no-ignore --hidden
    # must restore parity with the grep fallback. git-init so rg honors .gitignore
    # (best-effort: without git the ignored dir is just a normal dir, still found;
    # the hidden-dir leg always exercises --hidden regardless of git).
    local g="$d/ignore-case"
    mkdir -p "$g/build" "$g/.cache"
    git init -q "$g" >/dev/null 2>&1 || true
    printf 'build/\n' > "$g/.gitignore"
    printf 'bash lib/old-module.sh --check\n'   > "$g/build/legacy.sh"   # gitignored
    printf 'source lib/old-module.sh\n'         > "$g/.cache/legacy2.sh" # hidden dir
    run_cap bash "$SELF" --post-move --root "$g" "lib/old-module.sh"
    if [[ "$_RC" -eq 1 ]] \
        && grep -q "build/legacy.sh" <<<"$_OUT" \
        && grep -q ".cache/legacy2.sh" <<<"$_OUT"; then
        ok "F5-gitignored-hidden-still-caught"
    else
        no "F5-gitignored-hidden-still-caught" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi

    # ── F6: deletion-advisory classifies live vs test-only and exits 0 ────────
    # A *.py target imported dynamically by its dotted form: one live caller, one
    # test. The fixed-path grep alone would miss both (they use the dotted module,
    # not the file path) — the dotted-form derivation must surface them.
    local da="$d/adv"
    mkdir -p "$da/pkg" "$da/tests"
    printf 'from pkg.mod import x\n'        > "$da/live_caller.py"
    printf 'import_module("pkg.mod")\n'     > "$da/tests/test_mod.py"
    run_cap bash "$SELF" --deletion-advisory --root "$da" "pkg/mod.py"
    if [[ "$_RC" -eq 0 ]] \
        && grep -q "live importers" <<<"$_OUT" \
        && grep -q "live_caller.py" <<<"$_OUT" \
        && grep -q "test-only importers" <<<"$_OUT" \
        && grep -q "test_mod.py" <<<"$_OUT"; then
        ok "F6-deletion-advisory-classifies"
    else
        no "F6-deletion-advisory-classifies" "rc=$_RC out=$(printf '%s' "$_OUT" | tr '\n' '|')"
    fi

    echo ""
    echo "Results: $t_pass passed, $t_fail failed"
    [[ "$t_fail" -eq 0 ]]
}

# ── Argument parsing ──────────────────────────────────────────────────────────
SELFTEST=0
POSTMOVE=0
DELADVISORY=0
ROOT=""
POS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-test)         SELFTEST=1; shift ;;
        --post-move)         POSTMOVE=1; shift ;;
        --deletion-advisory) DELADVISORY=1; shift ;;
        --root)      shift; ROOT="${1:-}"
                     [[ -n "$ROOT" ]] || { echo "ERROR: --root needs a directory" >&2; exit 1; }
                     shift ;;
        -h|--help)   usage; exit 0 ;;
        --*)         echo "ERROR: unknown flag: $1" >&2; exit 1 ;;
        *)           POS+=("$1"); shift ;;
    esac
done

if [[ "$SELFTEST" -eq 1 ]]; then
    self_test
    exit $?
fi

if [[ "${#POS[@]}" -lt 1 ]]; then
    echo "ERROR: usage: sdd-rewire-impact.sh [--post-move] [--root <dir>] <path>" >&2
    exit 1
fi

TARGET="${POS[0]}"

# Resolve search root: explicit --root, else git toplevel of CWD, else CWD.
if [[ -z "$ROOT" ]]; then
    if ! ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"; then
        ROOT="$PWD"
    fi
fi
[[ -d "$ROOT" ]] || { echo "ERROR: search root not found: $ROOT" >&2; exit 1; }

if [[ "$POSTMOVE" -eq 1 ]]; then
    do_post_move "$TARGET" "$ROOT"
elif [[ "$DELADVISORY" -eq 1 ]]; then
    do_deletion_advisory "$TARGET" "$ROOT"
else
    do_scan "$TARGET" "$ROOT"
fi
