#!/usr/bin/env bash
# goalforge-path-idiom-lint.sh — one path idiom across the goalforge package's
# markdown (skills, references, commands, agents).
#
# The sanctioned idiom for a package file is `${CLAUDE_PLUGIN_ROOT}/<dir>/...`
# (braced). goalforge-generate.sh leaves it verbatim in the plugin artifact,
# so the source and the shipped text read the same. Checks:
#
#   PI1  a literal author install path `~/.claude/skills/<pkg>/...` with
#        <pkg> = goalforge — only resolves on the author's machine layout. The
#        literal is assembled from two parts below so goalforge-generate.sh's
#        install-path rewrite cannot turn it into the sanctioned idiom in the
#        shipped plugin copy.
#   PI2  a second spelling of the sanctioned root: unbraced `$CLAUDE_PLUGIN_ROOT`
#        where `${CLAUDE_PLUGIN_ROOT}` applies.
#   PI3  an absolute home path (`/home/<user>/`, `/Users/<user>/`) inside a
#        fenced bash/sh/shell/zsh code block — a command that runs on one
#        machine only.
#
# Scope: each argument is a file or a directory. A directory is scanned for
# `*.md` recursively (a symlinked start directory and symlinked `*.md` files
# included), pruning `evals/fixtures/` and `tests/fixtures/` (those hold
# deliberate known-bad copies); a directory with no `*.md` to scan is an error,
# not a clean pass. A file argument is always scanned.
#
# `--fenced-only` (first argument) restricts every check to fenced code blocks.
# The pre-harden lint uses it on WP planning docs, where prose legitimately
# quotes the forbidden spellings.
#
# Usage: goalforge-path-idiom-lint.sh [--fenced-only] <file-or-dir>...
# Output: one line per finding on stdout — `<file>:<line>: [PIn] <message>`.
# Exit: 0 clean; 1 one or more findings; 2 usage error or unreadable input — an
# argument that is not a readable file or directory, a directory `find` cannot
# fully walk, or a scanned file `awk` cannot read (never a silent exit 0).
# Offline, deterministic, read-only, no LLM.
set -uo pipefail

fenced_only=0
[ "${1:-}" = --fenced-only ] && { fenced_only=1; shift; }
[ "$#" -gt 0 ] || { echo "usage: goalforge-path-idiom-lint.sh [--fenced-only] <file-or-dir>..." >&2; exit 2; }

listing="$(mktemp)" || exit 2
trap 'rm -f "$listing"' EXIT

files=()
for arg in "$@"; do
    if [ -d "$arg" ]; then
        # find's status is checked (a pipeline or process substitution would hide it).
        if ! find -H "$arg" \( -path '*/evals/fixtures' -o -path '*/tests/fixtures' \) -prune \
                -o -name '*.md' -xtype f -print0 >"$listing"; then
            echo "goalforge-path-idiom-lint: cannot scan directory: $arg" >&2
            exit 2
        fi
        if [ ! -s "$listing" ]; then
            echo "goalforge-path-idiom-lint: no *.md to scan under directory: $arg" >&2
            exit 2
        fi
        while IFS= read -r -d '' f; do files+=("$f"); done < <(sort -z "$listing")
    elif [ -f "$arg" ] && [ -r "$arg" ]; then
        files+=("$arg")
    else
        echo "goalforge-path-idiom-lint: not a readable file or directory: $arg" >&2
        exit 2
    fi
done

# Split so the generator's author-install-path rewrite cannot match it.
pi1_lit='~/.claude/skills/'; pi1_lit+=goalforge

findings=0
for f in "${files[@]}"; do
    out="$(awk -v file="$f" -v fo="$fenced_only" -v pi1="$pi1_lit" '
        /^[[:space:]]*(```|~~~)/ {
            if (fence) { fence = 0; shell = 0 }
            else { fence = 1; shell = ($0 ~ /^[[:space:]]*(```|~~~)[[:space:]]*(bash|sh|shell|zsh)[[:space:]]*$/) }
            next
        }
        (fence || !fo) && index($0, pi1) {
            printf "%s:%d: [PI1] literal author install path %s — use ${CLAUDE_PLUGIN_ROOT}/\n", file, NR, pi1
        }
        (fence || !fo) && /\$CLAUDE_PLUGIN_ROOT/ {
            printf "%s:%d: [PI2] unbraced $CLAUDE_PLUGIN_ROOT — the sanctioned idiom is ${CLAUDE_PLUGIN_ROOT}\n", file, NR
        }
        fence && shell && /(^|[^[:alnum:]_.~$}])\/(home|Users)\/[^\/[:space:]]+\// {
            printf "%s:%d: [PI3] absolute home path inside a fenced shell block\n", file, NR
        }
    ' "$f")" || { echo "goalforge-path-idiom-lint: cannot read file: $f" >&2; exit 2; }
    if [ -n "$out" ]; then
        printf '%s\n' "$out"
        findings=$((findings + $(printf '%s\n' "$out" | wc -l)))
    fi
done

[ "$findings" -eq 0 ]
