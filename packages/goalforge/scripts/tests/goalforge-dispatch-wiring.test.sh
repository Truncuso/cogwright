#!/usr/bin/env bash
# goalforge-dispatch-wiring.test.sh — b8: the SKILL.md/chain.yaml wiring that
# binds execute to the dispatch config, the Workflow compiler, and the plugin
# mirror is asserted as content, not assumed.
#
#   known-good : the live package subtree satisfies every wiring assertion.
#   known-bad  : for EACH required string, a mktemp copy of the four wiring
#                files with that string stripped fails the same checker.
#
# The checker is a function over a root dir, so the known-good and every
# sabotage copy run the identical code path. Nothing is written outside the
# one mktemp -d.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$SD/../.." && pwd)"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# The four wiring files, relative to the package root.
WIRING_FILES=(
    execute/SKILL.md
    run/SKILL.md
    run/chain.yaml
    decompose/SKILL.md
)

# Required literal strings, as "<relative file>|<string>" pairs. Each one is
# independently sabotaged below.
REQUIRED=(
    "execute/SKILL.md|goalforge-workflow-compile.py"
    "execute/SKILL.md|Expertise refs"
    "execute/SKILL.md|dispatch.completed"
    "execute/SKILL.md|tokens"
    "execute/SKILL.md|tool_uses"
    "execute/SKILL.md|plugins/goalforge/"
    "execute/SKILL.md|regenerate"
    "run/SKILL.md|run/workflows/"
    "run/chain.yaml|run/workflows/"
)

# name_of <file> -> the frontmatter/chain `name:` value
name_of() { grep -m1 '^name:' "$1" 2>/dev/null | sed 's/^name:[[:space:]]*//'; }

# check_tree <root> -> 0 when every wiring assertion holds, 1 otherwise.
# Prints one line per violation.
check_tree() {
    local root="$1" rc=0 pair f s

    for pair in "${REQUIRED[@]}"; do
        f="${pair%%|*}"; s="${pair#*|}"
        if ! grep -qF -- "$s" "$root/$f" 2>/dev/null; then
            echo "    missing in $f: $s"; rc=1
        fi
    done

    # execute/SKILL.md line budget
    local lines
    lines="$(wc -l < "$root/execute/SKILL.md" 2>/dev/null || echo 99999)"
    if [[ "$lines" -gt 120 ]]; then
        echo "    execute/SKILL.md is $lines lines (max 120)"; rc=1
    fi

    # `name:` equals the directory basename
    local d
    for d in decompose execute run; do
        if [[ "$(name_of "$root/$d/SKILL.md")" != "$d" ]]; then
            echo "    $d/SKILL.md name: != $d"; rc=1
        fi
    done

    return "$rc"
}

# --- known-good: the live tree -----------------------------------------------
echo "known-good: live package tree"
if out="$(check_tree "$PKG")"; then
    ok "live tree satisfies every dispatch-wiring assertion"
else
    bad "live tree satisfies every dispatch-wiring assertion"
    echo "$out"
fi

# --- known-bad: one sabotaged copy per required string ------------------------
echo "known-bad: one string removed per copy"
i=0
for pair in "${REQUIRED[@]}"; do
    f="${pair%%|*}"; s="${pair#*|}"
    i=$((i+1))
    root="$T/sabotage-$i"
    for wf in "${WIRING_FILES[@]}"; do
        mkdir -p "$root/$(dirname "$wf")"
        cp "$PKG/$wf" "$root/$wf"
    done
    # strip every occurrence of the required string from its file
    python3 - "$root/$f" "$s" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace(sys.argv[2], ""))
PY
    if check_tree "$root" >/dev/null; then
        bad "sabotage: $f without '$s' is rejected"
    else
        ok "sabotage: $f without '$s' is rejected"
    fi
done

# --- known-bad: over the line budget and a renamed skill ----------------------
root="$T/sabotage-lines"
for wf in "${WIRING_FILES[@]}"; do
    mkdir -p "$root/$(dirname "$wf")"
    cp "$PKG/$wf" "$root/$wf"
done
for _ in $(seq 1 25); do echo "padding" >> "$root/execute/SKILL.md"; done
if check_tree "$root" >/dev/null; then
    bad "sabotage: execute/SKILL.md over 120 lines is rejected"
else
    ok "sabotage: execute/SKILL.md over 120 lines is rejected"
fi

root="$T/sabotage-name"
for wf in "${WIRING_FILES[@]}"; do
    mkdir -p "$root/$(dirname "$wf")"
    cp "$PKG/$wf" "$root/$wf"
done
sed -i '0,/^name:/s/^name:.*/name: goalforge-execute/' "$root/execute/SKILL.md"
if check_tree "$root" >/dev/null; then
    bad "sabotage: execute/SKILL.md name: != basename is rejected"
else
    ok "sabotage: execute/SKILL.md name: != basename is rejected"
fi

echo
echo "goalforge-dispatch-wiring.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
