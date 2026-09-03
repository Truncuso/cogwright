#!/usr/bin/env bash
# trigger-run.sh — goalforge's caller for the SHARED trigger-eval runner.
#
# This package does NOT own a trigger-eval engine. The engine lives in the
# dotfiles corpus at scripts/skill-trigger-runner/ (knowledge home:
# scripts/skill-trigger-runner/README.md there); this file only resolves it,
# points it at THIS package, and degrades to a measured gap when it is absent.
#
# Resolution order:
#   1. $SKILL_TRIGGER_RUNNER — an explicit override. AUTHORITATIVE: if it is set
#      and is not executable, this script reports a gap rather than silently
#      falling back to a different engine. A confounded run is worse than none.
#   2. ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/skill-trigger-run.sh — the
#      install anchor, never the maintainer's checkout.
#   3. neither → one `gap:` line, coverage=skipped, exit 0 (zero-breakage).
#
# A skipped run is NEVER a pass. It prints a `gap:` marker and, when --report is
# given, writes a report whose "coverage" is "skipped" and whose "gap" is true,
# so coverage is measured rather than asserted (design risk 7 / ruling A7).
#
# Usage: trigger-run.sh [--dry-run] [--trials k] [--report <path>] [...]
#        trigger-run.sh --list-suites
#        trigger-run.sh --suite <name> [--trials k] [--report <path>] [...]
#        trigger-run.sh --all [--trials k] [...]
#   Every other argument is forwarded to the runner unchanged. --tree defaults to
#   this package root (a relative climb from $0); pass --tree yourself to override.
#
# TWO PATHS, and they are not the same thing:
#
#   the CENSUS   — `--dry-run` with no --cases. Full-tree discovery, 13 canonical
#                  files. Under a nested package "has evals/evals.json" is a
#                  case-file LOCATION CONVENTION, not a selectability claim
#                  (doctrine H1), so this counts material; it never scores it.
#   the SCORING  — `--cases`-driven, one run per REACHABLE entry. Skill discovery
#                  walks one level deep, so only those entries are on the model's
#                  selection surface.
#
# The roster of both lives in evals/suites.txt — DATA, one row per name, read by
# --list-suites / --suite / --all. It is not duplicated here; add a child or a
# command without a row there and evals/selection.test.sh goes red.
#
# --commands puts the command basenames on the selection surface; --with-siblings
# installs each negative's backticked owner so the model has a real alternative
# to pick rather than abstaining. EVERY runnable suite needs --commands, not just
# the command-owned ones: sibling resolution matches a skill dir by its DIRECTORY
# basename, and four owners this material cites — `goalforge-run`, `spec`,
# `plan`, `implement` — reach the surface only as commands/<name>.md (the
# goalforge-run skill dir is run/, and plan/implement own no dir at all). Omit
# --commands and those negatives have no alternative owner installed, so the
# model abstains and the oracle fails them. The `goalforge` front door is never
# installable as a sibling — it IS the --tree root, never walked as a subdir —
# so no negative may cite it as its owner. suites.txt carries the --commands
# column for exactly this reason.
#
# Two rules govern the case material on this surface, and they are twins:
#
#   an owner must be INSTALLABLE   — every negative's backticked owner is a real
#                                    alternative the runner can put on the
#                                    surface, or the model can only abstain;
#   an argument must be LITERAL    — every positive's argument appears IN the
#                                    prompt as a plans/ path, a wp-NN id, or a
#                                    backticked feature/WP name.
#
# The second follows from this surface: cwd is an empty temp dir, --tools is
# Skill only, and there is no Read. A prompt that points at its argument
# deictically ("the current feature's spec", "the work package I just finished")
# names nothing the model can resolve, so it asks for the argument and emits no
# Skill call — an abstain that measures the harness, not the description. The
# 2026-09-02 baseline abstained on 16 of 20 positives for exactly this reason.
#
# Case material — the 3/3 bar, installable owners, literal positive arguments,
# and negative phrasing the converter preserves — is gated offline by
# evals/selection.test.sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$HERE/.." && pwd)"
SUITES_FILE="$HERE/suites.txt"

# --- suites.txt: the roster, as data ----------------------------------------
# Emits "name cases commands status" per non-comment, non-blank row.
suite_rows() {
    [ -r "$SUITES_FILE" ] || { printf 'gap: %s missing — no suite roster\n' "$SUITES_FILE" >&2; return 1; }
    awk 'NF && $1 !~ /^#/ { print $1, $2, $3, $4 }' "$SUITES_FILE"
}

# --- pull the suite-selection flags out of the forwarded args ----------------
mode="passthrough"
want_suite=""
FORWARD=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --list-suites) mode="list" ;;
        --all)         mode="all" ;;
        --suite)       mode="suite"; want_suite="${2:?--suite needs a name}"; shift ;;
        --suite=*)     mode="suite"; want_suite="${1#--suite=}" ;;
        *)             FORWARD+=("$1") ;;
    esac
    shift
done
set -- ${FORWARD[@]+"${FORWARD[@]}"}

if [ "$mode" = "list" ]; then
    printf '%-16s %-32s %-10s %s\n' NAME CASES COMMANDS STATUS
    suite_rows | while read -r name cases cmds status; do
        printf '%-16s %-32s %-10s %s\n' "$name" "$cases" "$cmds" "$status"
    done
    exit 0
fi

# --- resolve the runner -----------------------------------------------------
RUNNER=""
LOOKED_IN=""
if [ -n "${SKILL_TRIGGER_RUNNER:-}" ]; then
    LOOKED_IN="\$SKILL_TRIGGER_RUNNER=$SKILL_TRIGGER_RUNNER"
    [ -x "$SKILL_TRIGGER_RUNNER" ] && RUNNER="$SKILL_TRIGGER_RUNNER"
else
    CANDIDATE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/skill-trigger-run.sh"
    LOOKED_IN="$CANDIDATE"
    { [ -x "$CANDIDATE" ] || [ -r "$CANDIDATE" ]; } && RUNNER="$CANDIDATE"
fi

# --- scan forwarded args for --tree / --report ------------------------------
have_tree=0
report_path=""
next_is_report=0
for arg in "$@"; do
    if [ "$next_is_report" -eq 1 ]; then report_path="$arg"; next_is_report=0; continue; fi
    case "$arg" in
        --tree|--tree=*) have_tree=1 ;;
        --report) next_is_report=1 ;;
        --report=*) report_path="${arg#--report=}" ;;
    esac
done

# --- gap path: one marker line, coverage=skipped, exit 0 --------------------
if [ -z "$RUNNER" ]; then
    printf 'gap: shared trigger runner not found (%s) — coverage=skipped, nothing measured\n' "$LOOKED_IN" >&2
    if [ -n "$report_path" ]; then
        mkdir -p "$(dirname "$report_path")"
        cat >"$report_path" <<EOF
{
  "schema_version": "1",
  "tree": "$PKG_ROOT",
  "mode": "skipped",
  "coverage": "skipped",
  "gap": true,
  "gap_reason": "shared trigger runner not found",
  "looked_in": "$LOOKED_IN",
  "files_found": 0,
  "files_canonical": 0,
  "shape_errors": [],
  "cases": [],
  "summary": {"cases": 0, "positive_cases": 0, "negative_cases": 0}
}
EOF
    fi
    exit 0
fi

# --- run: forward every argument, defaulting --tree to this package ---------
# The runner's exit code is passed through untouched. 2 (shape errors) is the
# expected RED baseline while this package's 13 evals.json files are still in
# the pre-canonical dialect; it is a real failure, not a plumbing problem.
run_runner() {
    if [ "$have_tree" -eq 1 ]; then
        bash "$RUNNER" "$@"
    else
        bash "$RUNNER" --tree "$PKG_ROOT" "$@"
    fi
}

# --- suite dispatch: --cases-driven, one run per reachable entry -------------
run_suite() {
    local name="$1" cases="$2" cmds="$3" status="$4"; shift 4
    if [ "$cases" = "-" ]; then
        printf 'gap: suite %s is %s — no cases file yet, nothing measured\n' "$name" "$status" >&2
        return 0
    fi
    local extra=(--cases "$PKG_ROOT/$cases")
    [ "$cmds" = "-" ] || extra+=(--commands "$PKG_ROOT/$cmds")
    printf '== suite %s (%s) ==\n' "$name" "$cases" >&2
    run_runner "${extra[@]}" "$@"
}

case "$mode" in
    suite)
        row="$(suite_rows | awk -v n="$want_suite" '$1 == n { print; exit }')"
        [ -n "$row" ] || { printf 'error: no suite %s in %s\n' "$want_suite" "$SUITES_FILE" >&2; exit 2; }
        # shellcheck disable=SC2086
        set -- $row "$@"
        name="$1" cases="$2" cmds="$3" status="$4"; shift 4
        run_suite "$name" "$cases" "$cmds" "$status" "$@"
        exit $?
        ;;
    all)
        if [ -n "$report_path" ]; then
            printf 'error: --report writes one file; --all runs many suites. Use --suite <name> --report <path>.\n' >&2
            exit 2
        fi
        worst=0
        while read -r name cases cmds status; do
            [ "$status" = "run" ] || continue
            run_suite "$name" "$cases" "$cmds" "$status" "$@" || worst=$?
        done < <(suite_rows)
        exit "$worst"
        ;;
esac

if [ "$have_tree" -eq 1 ]; then
    exec bash "$RUNNER" "$@"
else
    exec bash "$RUNNER" --tree "$PKG_ROOT" "$@"
fi
