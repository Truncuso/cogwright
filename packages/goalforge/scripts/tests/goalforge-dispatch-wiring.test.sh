#!/usr/bin/env bash
# goalforge-dispatch-wiring.test.sh — b8: the SKILL.md/chain.yaml wiring that
# binds execute to the dispatch config, the Workflow compiler, and the plugin
# mirror is asserted as content, not assumed.
#
#   known-good : the live package subtree satisfies every wiring assertion.
#   known-bad  : for EACH required string, a mktemp copy of the wiring files
#                with that string stripped fails the same checker.
#   plugin tree: b9 — every SKILL.md invocation of an unprefixed scripts/ path
#                resolves under plugins/goalforge/, and every tests-dir mention
#                in the shipped SKILL.md, README.md and hooks/README.md says
#                `maintainer tree`. A separate checker over a plugin root, never
#                inside check_tree (the sabotage roots copy only WIRING_FILES).
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

# The wiring files, relative to the package root.
WIRING_FILES=(
    execute/SKILL.md
    run/SKILL.md
    run/chain.yaml
    decompose/SKILL.md
    verify/SKILL.md
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
    "verify/SKILL.md|plugins/goalforge/"
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
    if [[ "$lines" -gt 125 ]]; then
        echo "    execute/SKILL.md is $lines lines (max 125)"; rc=1
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

# --- known-good: an unmodified copy of the wiring files -----------------------
root="$T/known-good-copy"
for wf in "${WIRING_FILES[@]}"; do
    mkdir -p "$root/$(dirname "$wf")"
    cp "$PKG/$wf" "$root/$wf"
done
if out="$(check_tree "$root")"; then
    ok "unmodified WIRING_FILES copy satisfies every dispatch-wiring assertion"
else
    bad "unmodified WIRING_FILES copy satisfies every dispatch-wiring assertion"
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
    bad "sabotage: execute/SKILL.md over 125 lines is rejected"
else
    ok "sabotage: execute/SKILL.md over 125 lines is rejected"
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

# --- b9: plugin-tree checker ---------------------------------------------------
PLUGIN="$(cd "$PKG/../.." && pwd)/plugins/goalforge"

# check_plugin <plugin root> -> 0 when the shipped tree invokes only scripts it
# ships and marks every tests-dir mention `maintainer tree`; 1 otherwise.
# An invocation is a runner-prefixed path (`bash`, `sh`, `./`) anywhere, or a
# path that starts a command line inside a fenced code block. A path behind
# ${CLAUDE_PLUGIN_ROOT} is not a scripts/ path; a bare mention is not scanned.
check_plugin() {
    python3 - "$1" <<'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
rc = 0
RUNNER = re.compile(r"(?:(?<![\w/.-])(?:bash|sh)\s+|(?<![\w/.}-])\./)(scripts/[\w./-]*[\w-])")
FENCED = re.compile(r"^\s*(?:\$\s+)?(scripts/[\w./-]*[\w-])")
for skill in sorted(root.rglob("SKILL.md")):
    fenced = False
    for n, line in enumerate(skill.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        paths = RUNNER.findall(line) + (FENCED.findall(line) if fenced else [])
        for p in paths:
            if not (root / p).exists():
                print("    %s:%d invokes %s, not shipped in the plugin"
                      % (skill.relative_to(root), n, p))
                rc = 1
for rel in ("SKILL.md", "README.md", "hooks/README.md"):
    f = root / rel
    if not f.is_file():
        print("    %s: missing" % rel)
        rc = 1
        continue
    for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
        if "tests/" in line and "maintainer tree" not in line:
            print("    %s:%d names a tests dir without `maintainer tree`" % (rel, n))
            rc = 1
sys.exit(rc)
PY
}

# copy_plugin <dest> — full copy of the shipped plugin tree.
copy_plugin() { mkdir -p "$1"; cp -R "$PLUGIN/." "$1"; }

echo "b9: plugin tree"
if out="$(check_plugin "$PLUGIN")"; then
    ok "plugins/goalforge invokes only shipped scripts; tests dirs say maintainer tree"
else
    bad "plugins/goalforge invokes only shipped scripts; tests dirs say maintainer tree"
    echo "$out"
fi

# Sabotage 1: restore the old unconditional step 6.3 line in the plugin copy.
# The arm asserts the rewrite landed (a conditional 6.3 generate line exists to
# replace) and that the checker then rejects the tree.
root="$T/plugin-old-6-3"
copy_plugin "$root"
if python3 - "$root/skills/execute/SKILL.md" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
old = "3. Run `bash scripts/goalforge-generate.sh` from the repo root to regenerate the"
new, n = re.subn(r"(?m)^3\. .*goalforge-generate\.sh.*$", old, s, count=1)
if n != 1 or new == s:
    sys.exit(1)
p.write_text(new, encoding="utf-8")
PY
then
    if check_plugin "$root" >/dev/null; then
        bad "sabotage: plugin step 6.3 running bash scripts/goalforge-generate.sh is rejected"
    else
        ok "sabotage: plugin step 6.3 running bash scripts/goalforge-generate.sh is rejected"
    fi
else
    bad "sabotage: plugin step 6.3 holds a conditional generate line to replace"
fi

# Sabotage 2: drop every `maintainer tree` wording from the three prose files.
# The arm asserts there was wording to drop, then that the checker rejects.
root="$T/plugin-no-maintainer"
copy_plugin "$root"
if python3 - "$root" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
hits = 0
for rel in ("SKILL.md", "README.md", "hooks/README.md"):
    p = root / rel
    s = p.read_text(encoding="utf-8")
    hits += s.count("maintainer tree")
    p.write_text(s.replace("maintainer tree", ""), encoding="utf-8")
sys.exit(0 if hits else 1)
PY
then
    if check_plugin "$root" >/dev/null; then
        bad "sabotage: plugin prose without 'maintainer tree' is rejected"
    else
        ok "sabotage: plugin prose without 'maintainer tree' is rejected"
    fi
else
    bad "sabotage: plugin prose carries 'maintainer tree' wording to drop"
fi

echo
echo "goalforge-dispatch-wiring.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
