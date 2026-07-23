#!/usr/bin/env bash
# goalforge-pre-commit.sh — git pre-commit hook.
#
# Blocks a commit that leaves a touched SDD feature with a
# goalforge-validate --strict ERROR.  Zero-breakage on every other path:
#   - no staged paths under plans/<feature>/ → exit 0 (silent)
#   - goalforge-validate.sh not found / not executable → exit 0 + stderr notice
#   - any internal error in this hook → exit 0 (never break commit flow)
#
# The hook uses --strict ONLY (never --require-commit); commit-hash
# recording is enforced at goalforge-verify time, not here.
#
# Env override (tests): GOALFORGE_VALIDATE_SCRIPT — path to goalforge-validate.sh.

_goalforge_pre_commit_main() {
    set -uo pipefail

    local VALIDATE_SCRIPT="${GOALFORGE_VALIDATE_SCRIPT:-$HOME/.claude/skills/goalforge/scripts/goalforge-validate.sh}"

    # ── Zero-breakage: validator absent or not executable ──────────────────
    if [[ ! -e "$VALIDATE_SCRIPT" ]]; then
        echo "goalforge-pre-commit: goalforge-validate.sh not found at $VALIDATE_SCRIPT — SDD checks skipped" >&2
        exit 0
    fi
    if [[ ! -x "$VALIDATE_SCRIPT" ]]; then
        echo "goalforge-pre-commit: goalforge-validate.sh not executable at $VALIDATE_SCRIPT — SDD checks skipped" >&2
        exit 0
    fi

    # ── Get repo root; not in a git repo → silent pass ─────────────────────
    local REPO_ROOT
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

    # ── Get staged files ───────────────────────────────────────────────────
    local STAGED
    STAGED=$(git diff --cached --name-only 2>/dev/null) || exit 0
    [[ -z "$STAGED" ]] && exit 0

    # ── Extract touched feature dirs ───────────────────────────────────────
    # A staged path contains a plans/<feature>/ segment anywhere, e.g.:
    #   claude/plans/my-feature/wp-01/task.md   →   <repo>/claude/plans/my-feature
    #   plans/my-feature/wp-01/task.md           →   <repo>/plans/my-feature
    local -A _seen
    local -a TOUCHED_FEATURES
    TOUCHED_FEATURES=()

    local staged_path feat_dir
    while IFS= read -r staged_path; do
        [[ -z "$staged_path" ]] && continue
        # Group 1 = everything up to and including "plans"
        # Group 3 = the feature name (first path component after plans/)
        if [[ "$staged_path" =~ ^(([^/]*/)*plans)/([^/]+)/ ]]; then
            # Archived plans are frozen historical records — never strict-validate
            # them on commit (they predate the current schema). Matches the
            # validator's full-tree _archived/_archive skip.
            if [[ "${BASH_REMATCH[3]}" == "_archived" || "${BASH_REMATCH[3]}" == "_archive" ]]; then
                continue
            fi
            feat_dir="${REPO_ROOT}/${BASH_REMATCH[1]}/${BASH_REMATCH[3]}"
            if [[ -z "${_seen[$feat_dir]:-}" ]]; then
                _seen["$feat_dir"]=1
                TOUCHED_FEATURES+=("$feat_dir")
            fi
        fi
    done <<< "$STAGED"

    [[ ${#TOUCHED_FEATURES[@]} -eq 0 ]] && exit 0

    # ── Validate each touched feature; collect failures ────────────────────
    local -a FAILED_DIRS FAILED_OUTPUT
    FAILED_DIRS=()
    FAILED_OUTPUT=()

    local out feat_slug plans_root
    for feat_dir in "${TOUCHED_FEATURES[@]}"; do
        # Feature dir might not exist on disk (e.g., staged deletion) → skip
        [[ ! -d "$feat_dir" ]] && continue
        # Validate the WHOLE plans tree but gate only on THIS feature's errors
        # (--feature <slug> <plans-root>). A bare-subtree validate (--strict
        # "$feat_dir") rglobs only the feature, so its name_index never sees a
        # sibling feature — a legitimate cross-feature relationship/inherits_from
        # edge then false-errors ("target not found"). Full walk resolves those;
        # the --feature filter keeps the gate scoped to the staged feature.
        feat_slug=$(basename "$feat_dir")
        plans_root=$(dirname "$feat_dir")
        out=$("$VALIDATE_SCRIPT" --strict --feature "$feat_slug" "$plans_root" 2>&1) && continue
        FAILED_DIRS+=("$feat_dir")
        FAILED_OUTPUT+=("$out")
    done

    [[ ${#FAILED_DIRS[@]} -eq 0 ]] && exit 0

    # ── Block the commit ───────────────────────────────────────────────────
    {
        echo "goalforge-pre-commit: BLOCKED — SDD integrity error(s) in staged feature(s):"
        local i name first_err
        for i in "${!FAILED_DIRS[@]}"; do
            name=$(basename "${FAILED_DIRS[$i]}")
            echo ""
            echo "  Feature: $name"
            first_err=$(printf '%s\n' "${FAILED_OUTPUT[$i]}" | grep '^ERROR' | head -1) || true
            [[ -n "${first_err:-}" ]] && echo "  $first_err"
        done
        echo ""
        echo "  Fix: goalforge-rollup.sh <feature-dir>          — regenerate status tables"
        echo "       goalforge-validate.sh --strict <feature-dir>  — show all errors"
    } >&2
    exit 1
}

# ── Zero-breakage outer wrapper ────────────────────────────────────────────────
# Run main logic in a subshell; only propagate exit 1 (intentional block).
# Any unexpected internal error (unbound variable, subprocess crash, etc.)
# becomes exit 0 — never break the user's commit flow over a hook bug.
( _goalforge_pre_commit_main "$@" )
_goalforge_ec=$?
if [[ $_goalforge_ec -eq 1 ]]; then
    exit 1
fi
exit 0
