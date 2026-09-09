#!/usr/bin/env bash
# goalforge-plans-root.sh — SOURCED helper: the ONE PLANS_ROOT resolution used
# by every goalforge hook fast path.
#
# Resolution order (spec §Interface Contract, "PLANS_ROOT resolution"):
#   1. $SDD_PLANS_DIR          (explicit override; smoke/test harnesses set it)
#   2. <git-root>/plans        (git root of the EDITED file, not of $PWD)
#   2b. <git-root>             when the git root IS itself named `plans` — a
#                              plans tree kept as its OWN git repo, nested in
#                              and gitignored by a public parent repo. Without
#                              this leg, leg 2 resolves to `<...>/plans/plans`
#                              and NO plan file in such a tree is ever in scope,
#                              silently disabling every goalforge hook there.
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
    local p="${1:-}" out="" seg noglob=0
    case "$p" in /*) ;; *) printf '%s' "$p"; return 0 ;; esac
    # A path segment must never glob-expand below — but this helper is SOURCED
    # into the caller's shell, so it restores the caller's `set -f` state rather
    # than blindly clearing it (a caller that runs noglob stays noglob).
    case "$-" in *f*) noglob=1 ;; esac
    set -f
    local IFS=/
    for seg in $p; do
        case "$seg" in
            ''|.) continue ;;
            ..)   out="${out%/*}" ;;
            *)    out="$out/$seg" ;;
        esac
    done
    [ "$noglob" -eq 1 ] || set +f
    printf '%s' "${out:-/}"
}

# Print the candidate plans roots, in spec order, one per line.
# $1 (optional): the file being judged — its directory anchors the git-root leg.
goalforge_plans_roots() {
    local file="${1:-}" gitroot
    [ -n "${SDD_PLANS_DIR:-}" ] && printf '%s\n' "$SDD_PLANS_DIR"
    if [ -n "$file" ]; then
        gitroot="$(git -C "$(dirname -- "$file")" rev-parse --show-toplevel 2>/dev/null)" || gitroot=""
        if [ -n "$gitroot" ]; then
            printf '%s\n' "$gitroot/plans"
            # Leg 2b — the plans tree is its own git repo, so the git root IS
            # the plans root and leg 2 above would look for `plans/plans`.
            case "${gitroot##*/}" in plans) printf '%s\n' "$gitroot" ;; esac
        fi
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

# Prints <root>/<feature-slug> for $1 (a path under a resolved plans root), or
# nothing if $1 does not resolve under any root. Used only to locate the
# feature dir's trace-events.jsonl for gate.result emission — never for
# scoping decisions (goalforge_under_plans_root owns that).
goalforge_feature_dir_for() {
    local file="${1:-}" root norm rest slug
    [ -n "$file" ] || return 1
    case "$file" in
        /*) ;;
        "~/"*) file="${HOME:-}/${file#\~/}" ;;
        *) return 1 ;;
    esac
    norm="$(goalforge_normpath "$file")"
    while IFS= read -r root; do
        [ -n "$root" ] || continue
        root="$(goalforge_normpath "$root")"
        case "$norm" in
            "$root"/*)
                rest="${norm#"$root"/}"
                slug="${rest%%/*}"
                [ -n "$slug" ] && printf '%s/%s\n' "$root" "$slug" && return 0
                ;;
        esac
    done < <(goalforge_plans_roots "$norm")
    return 1
}

# Prints the `wp` field value (trace-events.md schema) for $1, a file already
# known to resolve under a plans root via goalforge_feature_dir_for. `wp` names
# whichever directory OWNS the file: the first path segment under the feature
# dir (a WP dir basename, e.g. `wp-01`) when the file lives inside one, else
# the feature slug itself (basename of the feature dir) for a feature-level
# file (the feature's own overview.md/spec.md) — mirroring how
# goalforge-transition.sh derives `wp` (WP_DIR basename, or FEATURE_DIR
# basename for a feature-kind transition). Prints nothing on any doubt; the
# caller treats an empty wp as "cannot attribute" and skips emission.
goalforge_wp_for() {
    local file="${1:-}" feat_dir norm rest first
    [ -n "$file" ] || return 1
    feat_dir="$(goalforge_feature_dir_for "$file" 2>/dev/null)" || return 1
    [ -n "$feat_dir" ] || return 1
    norm="$(goalforge_normpath "$file")"
    feat_dir="$(goalforge_normpath "$feat_dir")"
    case "$norm" in
        "$feat_dir"/*) rest="${norm#"$feat_dir"/}" ;;
        *) return 1 ;;
    esac
    first="${rest%%/*}"
    if [ "$first" = "$rest" ]; then
        # File sits directly in the feature dir (e.g. overview.md, spec.md) ->
        # no owning WP subdirectory -> attribute to the feature itself.
        printf '%s' "$(basename -- "$feat_dir")"
    else
        printf '%s' "$first"
    fi
}

# Best-effort gate.result emission — NEVER affects the caller's exit code.
# $1 gate name, $2 result (pass|fail|warn — trace-events.md enum), $3 reason,
# $4 the file the hook judged. `wp` is derived here (never passed in) via
# goalforge_wp_for, per trace-events.md's `gate.result` contract (wp/gate/
# result/reason all required). Degrades silently: an unresolved feature dir,
# an undeterminable wp, a missing goalforge-trace-emit, or a rejected event
# (e.g. an event type this trace-events.md revision does not yet declare) is
# swallowed — this is a side-effect log call, not the hook's own guard
# decision.
goalforge_emit_gate_result() {
    local gate="$1" result="$2" reason="$3" file="${4:-}" feat_dir wp emit
    feat_dir="$(goalforge_feature_dir_for "$file" 2>/dev/null)" || return 0
    [ -n "$feat_dir" ] || return 0
    wp="$(goalforge_wp_for "$file" 2>/dev/null)" || return 0
    [ -n "$wp" ] || return 0
    emit="$HOOK_DIR/../scripts/goalforge-trace-emit"
    [ -x "$emit" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    GF_WP="$wp" GF_GATE="$gate" GF_RESULT="$result" GF_REASON="$reason" python3 -c '
import json, os, sys
sys.stdout.write(json.dumps({
    "type": "gate.result",
    "wp": os.environ["GF_WP"],
    "gate": os.environ["GF_GATE"],
    "result": os.environ["GF_RESULT"],
    "reason": os.environ["GF_REASON"],
}))
' 2>/dev/null | "$emit" --feature-dir "$feat_dir" >/dev/null 2>&1 || true
    return 0
}
