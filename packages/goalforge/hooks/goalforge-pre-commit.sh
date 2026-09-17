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
#
# The DEFAULT validator address is script-relative, never an author install
# path and never an environment variable: this runs as a GIT hook, in whatever
# environment the invoking tool happens to carry, so a stale or poisoned
# ${CLAUDE_PLUGIN_ROOT} would silently point the gate at a nonexistent
# validator and disable it. readlink -f resolves the dotfiles route, where the
# file installed as .git/hooks/pre-commit (or under ~/.claude/hooks/) is a
# symlink into the package — so package, plugin and symlink routes all land on
# their own scripts/goalforge-validate.sh with no rewrite and no PRESERVE
# exception. GOALFORGE_VALIDATE_SCRIPT stays as the single, test-only override.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")")" && pwd)"
# Split deliberately: the generator's class-ii rewrite matches a literal
# `$SCRIPT_DIR/..` immediately followed by `/scripts` and would re-introduce the
# ${CLAUDE_PLUGIN_ROOT} leg in the generated copy. Naming the parent dir first
# keeps that literal out of the file (comment included), so the package and
# plugin trees stay byte-identical here.
GF_HOME="$SCRIPT_DIR/.."
# goalforge_emit_gate_result (sourced below) addresses goalforge-trace-emit
# relative to $HOOK_DIR — the name every other goalforge hook binds.
# shellcheck disable=SC2034  # read by the sourced goalforge_emit_gate_result
HOOK_DIR="$SCRIPT_DIR"

# Sourced for goalforge_plans_roots — the ONE place that knows a plans tree
# kept as its own git repo (leg 2b) makes the git root ITSELF the plans root.
# Zero-breakage: missing file → the leg-2b case below is simply never
# detected (git root != "plans" root, so the plain plans/<feature>/ predicate
# still runs unchanged).
# shellcheck disable=SC1091
[[ -r "$SCRIPT_DIR/goalforge-plans-root.sh" ]] && source "$SCRIPT_DIR/goalforge-plans-root.sh"

# ── human_required set-once invariant (ticket-72) ──────────────────────────────
# goalforge-single-writer.sh enforces human_required monotonicity on TOOL writes
# only — its PreToolUse matcher is Edit|Write|MultiEdit|ctx_patch|ctx_call. A
# `sed -i` (or any other Bash rewrite) of a WP overview.md never reaches that
# matcher, so the field can be cleared silently and committed. The two
# predicates below are DELIBERATE DUPLICATES of their twins in
# goalforge-single-writer.sh (`hr_is_null`, and `extract_frontmatter` +
# `extract_value` collapsed into one reader): that hook runs its main body on
# load and cannot be sourced, and a shared module for three lines of predicate
# buys indirection, not safety. Keep the null semantics of the two in lockstep.

# True (empty string or the literal unquoted "null") iff $1 is human_required's
# unset state.  Twin: goalforge-single-writer.sh `hr_is_null`.
_gf_hr_is_null() {
    local v="$1"
    [ -z "$v" ] || [ "$v" = "null" ]
}

# Prints the trimmed, unquoted value of the first `human_required:` line inside
# $1's frontmatter region (strictly between the first two `---` fence lines), or
# empty when there is no CLOSED frontmatter block or no such line. Scoping to
# the frontmatter is what keeps a prose line mentioning human_required out of
# scope.  Twin: goalforge-single-writer.sh `extract_frontmatter` + `extract_value`.
_gf_hr_value() {
    printf '%s\n' "$1" | awk '
        /^---$/ { f++; if (f == 2) { closed = 1; exit } ; next }
        f == 1 && !got && /^[[:space:]]*human_required:/ {
            v = $0
            sub(/^[[:space:]]*human_required:[[:space:]]*/, "", v)
            sub(/^["'"'"']/, "", v); sub(/["'"'"']$/, "", v); sub(/[[:space:]]+$/, "", v)
            got = 1
        }
        END { if (closed && got) print v }
    '
}

_goalforge_pre_commit_main() {
    set -uo pipefail

    local VALIDATE_SCRIPT="${GOALFORGE_VALIDATE_SCRIPT:-$GF_HOME/scripts/goalforge-validate.sh}"

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
    # A SECOND layout (goalforge-plans-root.sh leg 2b): a plans tree kept as
    # its OWN git repo has no `plans/` segment at all — REPO_ROOT already IS
    # the plans root, so staged paths are rooted directly at the feature, e.g.:
    #   my-feature/wp-01/task.md                 →   <repo>/my-feature
    local plans_root_is_self=0
    if declare -f goalforge_plans_roots >/dev/null 2>&1; then
        local _pr
        while IFS= read -r _pr; do
            [[ "$_pr" == "$REPO_ROOT" ]] && plans_root_is_self=1
        done < <(goalforge_plans_roots "$REPO_ROOT/x")
    fi

    local -A _seen
    local -a TOUCHED_FEATURES STAGED_OVERVIEWS
    TOUCHED_FEATURES=()
    STAGED_OVERVIEWS=()

    local staged_path feat_dir feat_slug
    while IFS= read -r staged_path; do
        [[ -z "$staged_path" ]] && continue
        feat_slug=""
        if [[ "$staged_path" =~ ^(([^/]*/)*plans)/([^/]+)/ ]]; then
            # Group 1 = everything up to and including "plans"
            # Group 3 = the feature name (first path component after plans/)
            feat_slug="${BASH_REMATCH[3]}"
            feat_dir="${REPO_ROOT}/${BASH_REMATCH[1]}/${feat_slug}"
        elif [[ $plans_root_is_self -eq 1 && "$staged_path" =~ ^([^/]+)/ ]]; then
            feat_slug="${BASH_REMATCH[1]}"
            feat_dir="${REPO_ROOT}/${feat_slug}"
        else
            continue
        fi
        # Archived plans are frozen historical records — never strict-validate
        # them on commit (they predate the current schema). Matches the
        # validator's full-tree _archived/_archive skip.
        if [[ "$feat_slug" == "_archived" || "$feat_slug" == "_archive" ]]; then
            continue
        fi
        if [[ -z "${_seen[$feat_dir]:-}" ]]; then
            _seen["$feat_dir"]=1
            TOUCHED_FEATURES+=("$feat_dir")
        fi
        # Overview files carry the WP frontmatter the human_required invariant
        # below reads. Collected from THIS loop so both checks share one
        # plans-layout predicate and one _archived skip.
        [[ "$(basename -- "$staged_path")" == "overview.md" ]] && STAGED_OVERVIEWS+=("$staged_path")
    done <<< "$STAGED"

    [[ ${#TOUCHED_FEATURES[@]} -eq 0 ]] && exit 0

    # ── human_required is set-once: reject any commit that weakens it ──────
    # Runs BEFORE schema validation: a weakened human_required is a policy
    # breach, not a schema error, and the commit must die on it either way.
    local -a HR_VIOLATIONS
    HR_VIOLATIONS=()
    local ov head_text idx_text oldval newval
    for ov in "${STAGED_OVERVIEWS[@]:+${STAGED_OVERVIEWS[@]}}"; do
        # No index blob = staged deletion. Removing a whole WP file is an
        # archive/move operation, not a field weakening — out of scope here.
        idx_text=$(git show ":$ov" 2>/dev/null) || continue
        # No HEAD blob = new file -> there is no prior value to weaken.
        head_text=$(git show "HEAD:$ov" 2>/dev/null) || continue
        oldval="$(_gf_hr_value "$head_text")"
        # Unset in HEAD -> null -> "<reason>" is the one sanctioned transition.
        _gf_hr_is_null "$oldval" && continue
        newval="$(_gf_hr_value "$idx_text")"
        if [[ "$oldval" == "$newval" ]]; then
            goalforge_emit_gate_result "human-required-monotonic" "pass" \
                "human_required unchanged" "$REPO_ROOT/$ov"
            continue
        fi
        HR_VIOLATIONS+=("$ov|$oldval|$newval")
        goalforge_emit_gate_result "human-required-monotonic" "fail" \
            "human_required weakened: '$oldval' -> '${newval:-<absent>}'" "$REPO_ROOT/$ov"
    done

    if [[ ${#HR_VIOLATIONS[@]} -gt 0 ]]; then
        {
            echo "goalforge-pre-commit: BLOCKED — human_required is set-once (ticket-72); this commit weakens it:"
            local v vfile vold vnew
            for v in "${HR_VIOLATIONS[@]}"; do
                vfile="${v%%|*}"
                vnew="${v#*|}"; vold="${vnew%%|*}"; vnew="${vnew#*|}"
                echo ""
                echo "  File:  $vfile"
                echo "    HEAD:  human_required: $vold"
                echo "    index: human_required: ${vnew:-<absent>}"
            done
            echo ""
            echo "  Only null -> \"<reason>\" is allowed. Restore the reason; clearing it is the human's call, not an agent's."
        } >&2
        exit 2
    fi

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
        echo "  Fix: goalforge-validate.sh --strict <feature-dir>  — show all errors"
    } >&2
    exit 1
}

# ── Zero-breakage outer wrapper ────────────────────────────────────────────────
# Run main logic in a subshell; only propagate the INTENTIONAL block codes —
# 1 (schema error) and 2 (human_required weakened). Any unexpected internal
# error (unbound variable, subprocess crash, etc.) becomes exit 0 — never break
# the user's commit flow over a hook bug.
( _goalforge_pre_commit_main "$@" )
_goalforge_ec=$?
if [[ $_goalforge_ec -eq 1 || $_goalforge_ec -eq 2 ]]; then
    exit "$_goalforge_ec"
fi
exit 0
