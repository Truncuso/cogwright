#!/usr/bin/env bash
# evals/retrospective/run.sh — WP-15 retrospective-stage verification suite.
#
# The WP goal.verification entry point. AGGREGATES the per-task case units under
# cases/*.sh (authored by tasks 01-03) into the full gate suite (a)-(h). Each
# case unit is hermetic, offline, and self-isolating (mktemp fixtures) — this
# harness invokes them, it does not re-implement their assertions.
#
#   (a) goalforge-issue capture + emitter-absent AND emitter-reject zero-breakage
#         → `goalforge-issue --self-test`
#   (b) distiller golden-report byte-idempotency                → cases/distiller.sh
#   (c) routing-table correctness + learning-routing citation   → cases/distiller.sh
#   (d) empty/absent log empty-report                           → cases/distiller.sh
#   (e) propose-only tree-diff (only improvement-report.md)     → cases/distiller.sh
#   (f) torn-tail trailing-line skip                            → cases/distiller.sh
#   (g) handoff park-render includes/omits the section          → cases/park-render.sh
#   (h) run.sh --self-test                                      → this file
#
# Usage:
#   run.sh                 run the full suite (cases a-g), exit 0 iff all green
#   run.sh --case <name>   run ONE case unit by basename (e.g. distiller, park-render)
#   run.sh --self-test     preflight: fixtures present, scripts executable,
#                          golden parses/matches, hermetic SDD_PLANS_DIR isolation
#                          (never mutates the live plans/, .memory/, or trace logs)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES="$HERE/cases"
SCRIPTS="$(cd "$HERE/../../scripts" && pwd)"
ISSUE="$SCRIPTS/goalforge-issue"
RETRO="$SCRIPTS/goalforge-retrospect"
FIXTURES="$CASES/fixtures"
GOLDEN="$FIXTURES/golden/improvement-report.md"
SAMPLE_LOG="$FIXTURES/sample-feature/trace-events.jsonl"

fails=0
ok()   { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }
chk()  { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# --- case (a): the helper's own hermetic self-test ---------------------------
run_helper_selftest() {
  printf '== case (a) goalforge-issue --self-test ==\n'
  if "$ISSUE" --self-test; then ok "goalforge-issue --self-test"; else fail "goalforge-issue --self-test"; fi
}

# --- run one case unit by basename -------------------------------------------
run_case() {
  local name="$1" unit="$CASES/$1.sh"
  if [ ! -f "$unit" ]; then fail "case unit missing: $name"; return; fi
  printf '== case unit: %s ==\n' "$name"
  if bash "$unit"; then ok "case unit passed: $name"; else fail "case unit failed: $name"; fi
}

# --- --self-test: preflight + hermetic golden check --------------------------
self_test() {
  printf '== run.sh --self-test ==\n'

  # scripts executable
  chk "goalforge-issue executable"      "[ -x '$ISSUE' ]"
  chk "goalforge-retrospect executable" "[ -x '$RETRO' ]"
  chk "goalforge-trace-read present"    "[ -f '$SCRIPTS/goalforge-trace-read' ]"

  # case units present + executable
  for u in distiller park-render; do
    chk "case unit present: $u" "[ -f '$CASES/$u.sh' ]"
  done

  # fixtures present
  chk "sample fixture log present" "[ -f '$SAMPLE_LOG' ]"
  chk "golden report present"      "[ -f '$GOLDEN' ]"
  chk "golden parses (has contracted sections)" \
    "grep -qF '## Bottlenecks' '$GOLDEN' && grep -qF '## Routed Proposals' '$GOLDEN'"

  # hermetic: distill the fixture under an SDD_PLANS_DIR-style temp feature dir,
  # never touching the live plans/, .memory/, or trace logs.
  local tmp before_plans
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/plans/sample-feature"
  export SDD_PLANS_DIR="$tmp/plans"
  cp "$SAMPLE_LOG" "$tmp/plans/sample-feature/trace-events.jsonl"

  "$RETRO" "$tmp/plans/sample-feature" >/dev/null 2>&1 || true
  chk "distill produced a report in the temp feature dir" \
    "[ -f '$tmp/plans/sample-feature/improvement-report.md' ]"
  # golden match modulo the header line (line 1 carries the feature-dir basename)
  chk "distilled body byte-matches the golden (modulo header)" \
    "diff -q <(tail -n +2 '$GOLDEN') <(tail -n +2 '$tmp/plans/sample-feature/improvement-report.md') >/dev/null"
  # byte-idempotent second run
  cp "$tmp/plans/sample-feature/improvement-report.md" "$tmp/first.md"
  "$RETRO" "$tmp/plans/sample-feature" >/dev/null 2>&1 || true
  chk "distill byte-idempotent (self-test)" \
    "diff -q '$tmp/first.md' '$tmp/plans/sample-feature/improvement-report.md' >/dev/null"

  # live-tree isolation: no report artifact leaked into the repo's plans tree
  chk "no live plans/ mutation (isolation held)" \
    "[ ! -e '$HERE/../../../../plans/goalforge/wp-15-retrospective-stage/improvement-report.md' ]"

  unset SDD_PLANS_DIR
  rm -rf "$tmp"
}

# --- arg dispatch ------------------------------------------------------------
case "${1:-}" in
  --self-test)
    self_test
    ;;
  --case)
    [ -n "${2:-}" ] || { printf 'run.sh: --case requires a name\n' >&2; exit 2; }
    run_case "$2"
    ;;
  '')
    run_helper_selftest
    for u in distiller park-render; do run_case "$u"; done
    ;;
  *)
    printf 'run.sh: unknown argument: %s\n' "$1" >&2
    exit 2
    ;;
esac

if [ "$fails" -ne 0 ]; then
  printf 'run.sh: FAIL (%d)\n' "$fails" >&2
  exit 1
fi
printf 'run.sh: PASS\n'
