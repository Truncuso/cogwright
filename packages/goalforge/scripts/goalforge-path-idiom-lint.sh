#!/usr/bin/env bash
# goalforge-path-idiom-lint.sh — one path idiom across the goalforge package's
# markdown (skills, references, commands, agents).
#
# The sanctioned idiom for a package file is `${CLAUDE_PLUGIN_ROOT}/<dir>/...`
# (braced). goalforge-generate.sh leaves it verbatim in the plugin artifact,
# so the source and the shipped text read the same. Checks:
#
#   PI1  a literal author install path `~/.claude/skills/goalforge/...` — only
#        resolves on the author's machine layout.
#   PI2  a second spelling of the sanctioned root: unbraced `$CLAUDE_PLUGIN_ROOT`
#        where `${CLAUDE_PLUGIN_ROOT}` applies.
#   PI3  an absolute home path (`/home/<user>/`, `/Users/<user>/`) inside a
#        fenced bash/sh/shell/zsh code block — a command that runs on one
#        machine only.
#
# Scope: each argument is a file or a directory. A directory is scanned for
# `*.md` recursively, skipping `evals/fixtures/` and `tests/fixtures/` (those
# hold deliberate known-bad copies); a file argument is always scanned.
#
# Usage: goalforge-path-idiom-lint.sh <file-or-dir>...
# Output: one line per finding on stdout — `<file>:<line>: [PIn] <message>`.
# Exit: 0 clean; 1 one or more findings; 2 usage error or unreadable input.
# Offline, deterministic, no LLM.
set -uo pipefail

[ "$#" -gt 0 ] || { echo "usage: goalforge-path-idiom-lint.sh <file-or-dir>..." >&2; exit 2; }

files=()
for arg in "$@"; do
    if [ -d "$arg" ]; then
        while IFS= read -r -d '' f; do files+=("$f"); done < <(
            find "$arg" -type f -name '*.md' \
                -not -path '*/evals/fixtures/*' -not -path '*/tests/fixtures/*' -print0 | sort -z)
    elif [ -f "$arg" ] && [ -r "$arg" ]; then
        files+=("$arg")
    else
        echo "goalforge-path-idiom-lint: not a readable file or directory: $arg" >&2
        exit 2
    fi
done

findings=0
for f in "${files[@]}"; do
    out="$(awk -v file="$f" '
        /^[[:space:]]*(```|~~~)/ {
            if (fence) { fence = 0; shell = 0 }
            else { fence = 1; shell = ($0 ~ /^[[:space:]]*(```|~~~)[[:space:]]*(bash|sh|shell|zsh)[[:space:]]*$/) }
            next
        }
        index($0, "~/.claude/skills/goalforge") {
            printf "%s:%d: [PI1] literal author install path ~/.claude/skills/goalforge — use ${CLAUDE_PLUGIN_ROOT}/\n", file, NR
        }
        /\$CLAUDE_PLUGIN_ROOT/ {
            printf "%s:%d: [PI2] unbraced $CLAUDE_PLUGIN_ROOT — the sanctioned idiom is ${CLAUDE_PLUGIN_ROOT}\n", file, NR
        }
        fence && shell && /(^|[^[:alnum:]_.~$}])\/(home|Users)\/[^\/[:space:]]+\// {
            printf "%s:%d: [PI3] absolute home path inside a fenced shell block\n", file, NR
        }
    ' "$f")"
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
        findings=$((findings + $(printf '%s\n' "$out" | wc -l)))
    fi
done

[ "$findings" -eq 0 ]
