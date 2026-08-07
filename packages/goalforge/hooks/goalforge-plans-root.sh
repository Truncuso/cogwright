#!/usr/bin/env bash
# goalforge-plans-root.sh — SOURCED helper: the ONE PLANS_ROOT resolution used
# by every goalforge hook fast path.
#
# Resolution order (spec §Interface Contract, "PLANS_ROOT resolution"):
#   1. $SDD_PLANS_DIR          (explicit override; smoke/test harnesses set it)
#   2. <git-root>/plans        (git root of the EDITED file, not of $PWD)
#   3. $HOME/.claude/plans     (the global plans root)
#
# A hardcoded `$HOME/.claude/plans`-only resolution is a defect — no hook may
# re-implement this; source this file and call `goalforge_under_plans_root`.
#
# Layout-independent by construction: this file is sourced from the hook's OWN
# directory after `readlink -f` on ${BASH_SOURCE[0]}, so the package, plugin and
# dotfiles-symlink install routes all find it beside the hook that needs it.
#
# ZERO-BREAKAGE: no function here exits, blocks, or writes outside stdout.
# `goalforge_under_plans_root` returns 1 (not under a plans root) on any doubt —
# a hook's fast path must fall silent, never block, when resolution fails.

# Normalise an ABSOLUTE path: drop `.` and empty segments, resolve `..`
# lexically. Pure bash — no python3/realpath dependency on the fast path, which
# runs on every Edit/Write in the session. A relative path is returned verbatim
# (callers reject those before comparing).
goalforge_normpath() {
    local p="${1:-}" out="" seg
    case "$p" in /*) ;; *) printf '%s' "$p"; return 0 ;; esac
    set -f                       # a path segment must never glob-expand below
    local IFS=/
    for seg in $p; do
        case "$seg" in
            ''|.) continue ;;
            ..)   out="${out%/*}" ;;
            *)    out="$out/$seg" ;;
        esac
    done
    set +f
    printf '%s' "${out:-/}"
}

# Print the candidate plans roots, in spec order, one per line.
# $1 (optional): the file being judged — its directory anchors the git-root leg.
goalforge_plans_roots() {
    local file="${1:-}" gitroot
    [ -n "${SDD_PLANS_DIR:-}" ] && printf '%s\n' "$SDD_PLANS_DIR"
    if [ -n "$file" ]; then
        gitroot="$(git -C "$(dirname -- "$file")" rev-parse --show-toplevel 2>/dev/null)" || gitroot=""
        [ -n "$gitroot" ] && printf '%s\n' "$gitroot/plans"
    fi
    [ -n "${HOME:-}" ] && printf '%s\n' "$HOME/.claude/plans"
    return 0
}

# True (0) iff $1 is, or lives under, one of the resolved plans roots.
# `~/`-prefixed and absolute paths are accepted; anything else is not a path
# this hook can judge, so it is treated as out of scope.
goalforge_under_plans_root() {
    local file="${1:-}" root
    [ -n "$file" ] || return 1
    case "$file" in
        /*) ;;
        "~/"*) file="${HOME:-}/${file#\~/}" ;;
        *) return 1 ;;
    esac
    file="$(goalforge_normpath "$file")"
    while IFS= read -r root; do
        [ -n "$root" ] || continue
        root="$(goalforge_normpath "$root")"
        case "$file" in "$root"|"$root"/*) return 0 ;; esac
    done < <(goalforge_plans_roots "$file")
    return 1
}
