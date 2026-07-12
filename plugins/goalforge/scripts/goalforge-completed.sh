#!/usr/bin/env bash
# sdd-completed.sh — deterministic detector for archive-ready features.
#
# Emits every feature whose overview.md status is `completed` and that is NOT
# already under _archived/ — i.e. the set sdd-archive-batch.sh should reconcile
# and archive. Delegates all frontmatter reading to sdd-validate.sh
# (--list-status completed); it never parses YAML itself.
#
# Usage:  sdd-completed.sh [--show] [<plans-dir>]
#   stdout : archive-ready feature slugs, one per line (machine-readable).
#   stderr : terse one-line summary; --show also lists the slugs.
#   exit   : always 0 — this is a read-only query, never a gate.

set -euo pipefail

SHOW=0
PLANS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --show) SHOW=1; shift ;;
        -*)     echo "sdd-completed: unknown flag: $1" >&2; exit 0 ;;
        *)      PLANS="$1"; shift ;;
    esac
done

# Resolve plans dir (mirror sdd-validate.sh): arg → SDD_PLANS_DIR → git-root/plans
# → CWD/plans → ~/.claude/plans.
if [[ -z "$PLANS" ]]; then
    if [[ -n "${SDD_PLANS_DIR:-}" ]]; then
        PLANS="$SDD_PLANS_DIR"
    else
        GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || true
        if [[ -n "${GIT_ROOT:-}" && -d "${GIT_ROOT}/plans" ]]; then
            PLANS="${GIT_ROOT}/plans"
        elif [[ -d "$(pwd)/plans" ]]; then
            PLANS="$(pwd)/plans"
        else
            PLANS="${HOME}/.claude/plans"
        fi
    fi
fi

VALIDATOR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/goalforge-validate.sh"

# Best-effort: a missing validator / plans dir degrades to empty (exit 0), never
# crashes the caller.
slugs=""
if [[ -x "$VALIDATOR" ]]; then
    slugs="$("$VALIDATOR" --list-status completed "$PLANS" 2>/dev/null || true)"
fi

if [[ -n "$slugs" ]]; then
    printf '%s\n' "$slugs"
    n=$(printf '%s\n' "$slugs" | grep -c . || true)
else
    n=0
fi

if [[ "$SHOW" == "1" && "$n" -gt 0 ]]; then
    { echo "sdd-completed: $n archivable"; printf '  %s\n' $slugs; } >&2
else
    echo "sdd-completed: $n archivable (run --show to list)" >&2
fi

exit 0
