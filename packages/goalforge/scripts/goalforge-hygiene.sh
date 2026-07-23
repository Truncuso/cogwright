#!/usr/bin/env bash
# goalforge-hygiene.sh — unified per-feature reconcile. Makes ONE feature internally
# consistent: stamp status tables + regenerate the todo rollup. Reports drift
# terse by default; --apply fixes it. It STOPS before archive — never moves a
# feature, never calls goalforge-archive. Composes only the existing goalforge scripts.
#
# Usage:  goalforge-hygiene.sh <feature-dir> [--show] [--apply]
#   default : DRY-RUN. One-line drift verdict (fixable drift = tables + rollup).
#             --show adds the validator health + commit-hash advisory.
#   --apply : run goalforge-stamp-tables.sh + goalforge-rollup.sh to fix drift (idempotent).
#   exit    : 0 normally; non-zero only on a hard error (feature dir missing).

set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$SD/goalforge-stamp-tables.sh"
ROLLUP="$SD/goalforge-rollup.sh"
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

# ── --apply: fix tables + rollup (both idempotent) ───────────────────────────
if [[ "$APPLY" -eq 1 ]]; then
    bash "$STAMP" "$FEATURE" >/dev/null 2>&1 || true
    bash "$ROLLUP" "$FEATURE" >/dev/null 2>&1 || true
    echo "goalforge-hygiene $slug: reconciled (tables + rollup stamped)"
    exit 0
fi

# ── Dry-run drift detection ──────────────────────────────────────────────────
drift_items=()

# 1. Status tables stale?  (goalforge-stamp-tables.sh --check exits 1 when stale)
if ! bash "$STAMP" --check "$FEATURE" >/dev/null 2>&1; then
    drift_items+=("tables")
fi

# 2. Rollup stale?  Regenerate into a throwaway copy and diff — never mutates the
#    real tree during a dry-run. goalforge-rollup embeds the absolute feature path in a
#    `Regenerate:` comment, which differs between the temp copy and the real dir;
#    normalize that volatile line so only real content drift counts.
tmpd="$(mktemp -d)"
cp -r "$FEATURE" "$tmpd/f" 2>/dev/null || true
bash "$ROLLUP" "$tmpd/f" >/dev/null 2>&1 || true
_norm() { sed -E 's#(Regenerate: (sdd|goalforge)-rollup\.sh ).*#\1<PATH>#'; }
if [[ -f "$tmpd/f/todo.md" ]]; then
    if [[ ! -f "$FEATURE/todo.md" ]] \
       || ! diff <(_norm < "$tmpd/f/todo.md") <(_norm < "$FEATURE/todo.md") >/dev/null 2>&1; then
        drift_items+=("rollup")
    fi
fi
rm -rf "$tmpd"

n=${#drift_items[@]}
if [[ "$n" -eq 0 ]]; then
    echo "goalforge-hygiene $slug: clean"
else
    joined="$(printf '%s, ' "${drift_items[@]}")"; joined="${joined%, }"
    echo "goalforge-hygiene $slug: $n drift ($joined) — run --apply to fix${SHOW:+}"
    [[ "$SHOW" -eq 0 ]] && echo "  (run --show for detail)"
fi

# ── --show: advisory detail (validator health + commit-hash) ─────────────────
if [[ "$SHOW" -eq 1 ]]; then
    echo "  validate (advisory):"
    bash "$VALIDATE" --feature "$slug" --strict --show "$root" 2>&1 | sed 's/^/    /'
    # commit-hash advisory — report-only, NEVER a gate (the pre-commit hook must
    # not use --require-commit; see schema.md).
    missing="$(bash "$VALIDATE" --feature "$slug" --require-commit --show "$root" 2>&1 \
                 | grep -c 'missing .commit' || true)"
    echo "  commit-hash advisory: $missing verified task(s) missing commit:"
fi

exit 0
