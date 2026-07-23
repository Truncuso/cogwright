#!/usr/bin/env bash
# goalforge-archive-batch.sh — loop-safe batch archive. Finds every archive-ready
# feature (goalforge-completed.sh), reconciles it (goalforge-hygiene.sh --apply), and
# archives it (goalforge-archive.sh), committing per feature.
#
# Usage:  goalforge-archive-batch.sh [--show] [--apply] [--plans-root <root>]
#   default : PREVIEW — list what WOULD be archived; writes nothing; loop-safe.
#   --apply : the human gate — reconcile + archive each eligible feature.
#
# Safety / loop properties:
#   - SKIPS any completed feature with PRE-EXISTING uncommitted/untracked changes
#     (git status --porcelain non-empty) — never sweeps another flow's WIP into a
#     commit. (This is what protects e.g. an untracked render-pipe-tables/.)
#   - Per-feature transactional: a failure on one feature is reported and the
#     batch continues; non-zero exit if any feature failed.
#   - Idempotent: an archived feature leaves the detector's set, so a re-run is a
#     no-op for it. Preview writes nothing, safe under /loop and cron.
#
# Order is mandatory: reconcile + commit BEFORE archive, because the pre-commit
# hook requires the whole touched feature 0-ERROR — a drifted completed feature
# would otherwise block its own archive commit.

set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SD/goalforge-completed.sh"
HYGIENE="$SD/goalforge-hygiene.sh"
ARCHIVE="$SD/goalforge-archive.sh"
ENSURE="$SD/goalforge-ensure-committed.sh"

SHOW=0
APPLY=0
ROOT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --show)        SHOW=1; shift ;;
        --apply)       APPLY=1; shift ;;
        --plans-root)  ROOT="$2"; shift 2 ;;
        -*)            echo "sdd-archive-batch: unknown flag: $1" >&2; exit 2 ;;
        *)             ROOT="$1"; shift ;;
    esac
done

if [[ -z "$ROOT" ]]; then
    if [[ -n "${SDD_PLANS_DIR:-}" ]]; then ROOT="$SDD_PLANS_DIR"
    else
        GR=$(git rev-parse --show-toplevel 2>/dev/null) || true
        if [[ -n "${GR:-}" && -d "$GR/plans" ]]; then ROOT="$GR/plans"
        elif [[ -d "$(pwd)/plans" ]]; then ROOT="$(pwd)/plans"
        else ROOT="$HOME/.claude/plans"; fi
    fi
fi
ROOT="$(cd "$ROOT" && pwd)"
REPO="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || true)"

if [[ "$APPLY" -eq 1 && -z "$REPO" ]]; then
    echo "sdd-archive-batch: --apply needs a git repo (commits per feature); $ROOT is not in one." >&2
    exit 2
fi

# ── Detect + classify ────────────────────────────────────────────────────────
mapfile -t SLUGS < <(bash "$DETECT" "$ROOT" 2>/dev/null || true)

ELIGIBLE=()
SKIPPED=()
for slug in "${SLUGS[@]}"; do
    [[ -z "$slug" ]] && continue
    if [[ -n "$REPO" ]]; then
        dirty="$(git -C "$REPO" status --porcelain -- "$ROOT/$slug" 2>/dev/null)"
        if [[ -n "$dirty" ]]; then
            SKIPPED+=("$slug")
            continue
        fi
    fi
    ELIGIBLE+=("$slug")
done

ne=${#ELIGIBLE[@]}
ns=${#SKIPPED[@]}

# ── Preview (default) — writes nothing ───────────────────────────────────────
if [[ "$APPLY" -eq 0 ]]; then
    echo "archive-batch: $ne ready, $ns skipped (uncommitted) — re-run with --apply"
    if [[ "$SHOW" -eq 1 ]]; then
        for slug in "${ELIGIBLE[@]}"; do
            echo "  ready:   $(bash "$HYGIENE" "$ROOT/$slug" 2>&1 | head -1)"
        done
        for slug in "${SKIPPED[@]}"; do
            echo "  skipped: $slug (pre-existing uncommitted/untracked changes)"
        done
    fi
    exit 0
fi

# ── Apply — reconcile + archive each eligible feature, per-feature transactional
archive_one() {  # $1 = slug
    local slug="$1"
    bash "$HYGIENE" "$ROOT/$slug" --apply >/dev/null 2>&1 || return 1
    if [[ -n "$(git -C "$REPO" status --porcelain -- "$ROOT/$slug" 2>/dev/null)" ]]; then
        git -C "$REPO" add -- "$ROOT/$slug" || return 1
        git -C "$REPO" commit -q -m "chore($slug): reconcile before archive" || return 1
    fi
    bash "$ARCHIVE" "$slug" --plans-root "$ROOT" >/dev/null 2>&1 || return 1
    git -C "$REPO" add -A -- "$ROOT/$slug" "$ROOT/_archived/$slug" || return 1
    git -C "$REPO" commit -q -m "chore($slug): archive completed feature" || return 1
    bash "$ENSURE" "$ROOT/_archived/$slug" >/dev/null 2>&1 || return 1
    return 0
}

failures=0
for slug in "${ELIGIBLE[@]}"; do
    if archive_one "$slug"; then
        echo "  archived: $slug"
    else
        echo "  FAILED:   $slug (left in place; re-run to retry)" >&2
        failures=$((failures + 1))
    fi
done

echo "archive-batch: archived $((ne - failures))/$ne, $failures failed, $ns skipped"
[[ "$failures" -gt 0 ]] && exit 1
exit 0
