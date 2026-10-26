#!/usr/bin/env bash
# goalforge-hygiene.sh — validator-health advisory for ONE feature. wp-01 T10:
# the rollup-reconcile leg (goalforge-rollup.sh todo.md regeneration) and the
# commit-hash advisory are retired — todo.md rollup is retired (C6) and
# schema-6 has no per-task `commit:` field to advise on (see
# goalforge-validate.sh header). This script's only remaining legitimate job
# is running the validator over the feature and reporting what it finds —
# truthfully: it never claims to have reconciled anything.
#
# Usage:  goalforge-hygiene.sh <feature-dir> [--show] [--apply]
#   default : one-line validator-issue count.
#             --show adds the full validator --show output.
#   --apply : accepted for caller compatibility (goalforge-archive-batch.sh);
#             there is nothing left to fix here — always a truthful no-op.
#   exit    : 0 normally; non-zero only on a hard error (feature dir missing).

set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$SD/goalforge-validate.sh"

SHOW=0
APPLY=0
FEATURE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --show)  SHOW=1; shift ;;
        --apply) APPLY=1; shift ;;
        -*)      echo "goalforge-hygiene: unknown flag: $1" >&2; exit 2 ;;
        *)       FEATURE="$1"; shift ;;
    esac
done

if [[ -z "$FEATURE" || ! -d "$FEATURE" ]]; then
    echo "goalforge-hygiene: feature dir not found: ${FEATURE:-<none>}" >&2
    exit 2
fi

FEATURE="$(cd "$FEATURE" && pwd)"          # absolute
slug="$(basename "$FEATURE")"
root="$(dirname "$FEATURE")"

if [[ "$APPLY" -eq 1 ]]; then
    echo "goalforge-hygiene $slug: nothing to reconcile (rollup retired, C6)"
    exit 0
fi

# ── Validator-health advisory (the one legitimate job left) ──────────────────
validate_out="$(bash "$VALIDATE" --feature "$slug" --strict --show "$root" 2>&1)"
issue_count="$(printf '%s\n' "$validate_out" | grep -cE '^(ERROR|WARN)' || true)"

if [[ "$issue_count" -eq 0 ]]; then
    echo "goalforge-hygiene $slug: clean (0 validator issues)"
else
    echo "goalforge-hygiene $slug: $issue_count validator issue(s)"
    [[ "$SHOW" -eq 0 ]] && echo "  (run --show for detail)"
fi

if [[ "$SHOW" -eq 1 ]]; then
    echo "  validate (advisory):"
    printf '%s\n' "$validate_out" | sed 's/^/    /'
fi

exit 0
