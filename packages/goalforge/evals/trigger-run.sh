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
#   Every argument is forwarded to the runner unchanged. --tree defaults to this
#   package root (a relative climb from $0); pass --tree yourself to override.
#
# Selection suites: the four reachable COMMANDS (/spec /plan /implement /verify)
# own no skill dir, so their cases live in evals/selection/<name>.json — outside
# discovery, which keeps --dry-run at 13 canonical files. Run one per file:
#
#   ./trigger-run.sh --cases evals/selection/spec.json \
#       --commands "$(dirname "$0")/../commands" --with-siblings --trials 3
#
# --commands puts the command basenames on the selection surface (a suite whose
# skill_name names a command needs it); --with-siblings installs each negative's
# backticked owner so the model has a real alternative to pick rather than
# abstaining. The two skill-owned entries (goalforge, goalforge-run) are
# discovered normally and need only --with-siblings. Case material — the 3/3 bar
# and owner resolution — is gated offline by evals/selection.test.sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$HERE/.." && pwd)"

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
if [ "$have_tree" -eq 1 ]; then
    exec bash "$RUNNER" "$@"
else
    exec bash "$RUNNER" --tree "$PKG_ROOT" "$@"
fi
