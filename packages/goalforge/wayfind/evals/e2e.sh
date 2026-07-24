#!/usr/bin/env bash
#
# e2e.sh — the wp-03 deterministic gate for the wayfind skill.
#
# A fully offline, read-only end-to-end check of the graduation-precondition
# path — convergence over a converged fixture — plus command/brief contract
# presence. NEVER dispatches an agent or runs a live HITL graduation; the check
# is convergence + contract-documentation only.
#
# Named cases (ok / FAIL), aggregate exit (style donor: run.sh / frontier
# --self-test). All paths resolve relative to THIS script (BASH_SOURCE), never
# cwd.
#
# CONVERGED_FIXTURE env var overrides the effort-dir passed to the frontier
# script (used by the negative-control test, which points it at a mutated copy
# where one ticket is flipped to open so convergence fails).
#
# Exit codes:
#   0  every case passed
#   1  one or more cases failed (each failing case name is printed)
#
set -euo pipefail

# --- resolve paths relative to this script, following symlinks --------------
src="${BASH_SOURCE[0]}"
while [ -h "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"; case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
EVALS_DIR="$(cd -P "$(dirname "$src")" && pwd)"
SKILL_DIR="$(cd -P "$EVALS_DIR/.." && pwd)"
SCRIPTS_DIR="$SKILL_DIR/scripts"

FRONTIER="$SCRIPTS_DIR/wayfind-frontier.sh"
CONVERGED_FIXTURE="${CONVERGED_FIXTURE:-$EVALS_DIR/fixtures/converged}"
CMD_MD="${WAYFIND_CMD_MD:-$HOME/.claude/commands/wayfind.md}"
BRIEF_MD="${WAYFIND_BRIEF_MD:-$SKILL_DIR/references/graduation-brief.md}"

# --- case-runner scaffolding ------------------------------------------------
fail_count=0
failed_names=""
fail() { printf 'FAIL [%s]: %s\n' "$1" "$2" >&2; fail_count=$((fail_count + 1)); failed_names="${failed_names} $1"; }
pass() { printf 'ok   [%s]\n' "$1"; }

contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac }

# lowercase a file's content into one blob (case-insensitive substring checks)
lc_file() { tr '[:upper:]' '[:lower:]' < "$1" | tr -s '[:space:]' ' '; }

# ============================================================================
# Case: frontier-converged — the graduation precondition.
# Run the frontier script over the converged fixture; assert exit 0 AND
# stdout carries "converged": true AND an empty frontier.
# ============================================================================
name=frontier-converged
set +e
OUT="$(bash "$FRONTIER" "$CONVERGED_FIXTURE" 2>/dev/null)"; RC=$?
set -e
if [ "$RC" -ne 0 ]; then fail "$name" "frontier exit $RC != 0 over $CONVERGED_FIXTURE"
elif ! contains "$OUT" '"converged": true'; then fail "$name" "converged not true: $OUT"
elif ! contains "$OUT" '"frontier": []'; then fail "$name" "frontier not empty: $OUT"
else pass "$name"; fi

# ============================================================================
# Case: negative-control-non-converged — the real negative control.
# frontier-converged alone can be defeated by a stub frontier that always
# prints converged:true. This case copies the converged fixture to a temp dir,
# flips ONE resolved ticket to open (frontmatter stays valid), runs the SAME
# frontier over it, and asserts exit 0 AND "converged": false AND a NON-empty
# frontier. A stub that hard-codes converged:true cannot satisfy this, so the
# pair pins the frontier's real convergence logic in BOTH directions.
# ============================================================================
name=negative-control-non-converged
TMP_EFFORT="$(mktemp -d)"
trap 'rm -rf "$TMP_EFFORT"' EXIT
cp -R "$CONVERGED_FIXTURE/." "$TMP_EFFORT/"
# flip exactly one resolved ticket to open, keeping the frontmatter valid.
FLIP=""
for tk in "$TMP_EFFORT"/wayfind/ticket-*.md; do
  if grep -q '^status: resolved' "$tk"; then FLIP="$tk"; break; fi
done
if [ -z "$FLIP" ]; then
  fail "$name" "no resolved ticket to flip in $CONVERGED_FIXTURE"
else
  # portable in-place edit: rewrite the single status line.
  tmp_tk="$(mktemp)"
  sed 's/^status: resolved$/status: open/' "$FLIP" > "$tmp_tk" && mv "$tmp_tk" "$FLIP"
  # the mutated ticket must still validate (frontmatter kept valid).
  if ! bash "$SCRIPTS_DIR/validate-ticket.sh" "$FLIP" >/dev/null 2>&1; then
    fail "$name" "flipped ticket no longer validates: $FLIP"
  else
    set +e
    NOUT="$(bash "$FRONTIER" "$TMP_EFFORT" 2>/dev/null)"; NRC=$?
    set -e
    if [ "$NRC" -ne 0 ]; then fail "$name" "frontier exit $NRC != 0 over mutated copy"
    elif ! contains "$NOUT" '"converged": false'; then fail "$name" "converged not false after flip: $NOUT"
    elif contains "$NOUT" '"frontier": []'; then fail "$name" "frontier empty despite an open ticket: $NOUT"
    else pass "$name"; fi
  fi
fi

# ============================================================================
# Case: command-auto-phase — commands/wayfind.md documents the auto-phase
# branches (chart / work / offer-graduate) and convergence.
# ============================================================================
name=command-auto-phase
if [ ! -f "$CMD_MD" ]; then fail "$name" "command file not found: $CMD_MD"
else
  cmd_lc="$(lc_file "$CMD_MD")"
  # human-gate invariant: graduation is offered, never automatic. Require the
  # literal "never auto-graduate" OR "offers graduate" — a keyword-stuffed
  # command that merely mentions "graduate" without the gate must NOT pass.
  if ! { contains "$cmd_lc" "never auto-graduate" || contains "$cmd_lc" "offers graduate"; }; then
    fail "$name" "command missing the human-gate invariant (never auto-graduate / offers graduate)"
  elif contains "$cmd_lc" "auto-phase" \
     && contains "$cmd_lc" "chart" \
     && contains "$cmd_lc" "work" \
     && contains "$cmd_lc" "graduate" \
     && contains "$cmd_lc" "converged"; then
    pass "$name"
  else
    fail "$name" "command missing auto-phase chart/work/graduate/converged branches"
  fi
fi

# ============================================================================
# Case: brief-contract — references/graduation-brief.md documents the
# goalforge-capture brief composition (destination, decisions, scope bullets),
# the references→sources bridge + wayfind self-link, the adr-write
# three-condition gate, and the ends-at-overview.md boundary.
# ============================================================================
name=brief-contract
if [ ! -f "$BRIEF_MD" ]; then fail "$name" "brief file not found: $BRIEF_MD"
else
  brief_lc="$(lc_file "$BRIEF_MD")"
  missing=""
  # Anchor to the brief's actual SECTION HEADERS (structural markers), not bare
  # keyword presence — a keyword-stuffed one-liner lacks these headers and fails.
  contains "$brief_lc" "adr-write gate (before goalforge-capture)" \
                                           || missing="$missing §adr-write-gate"
  contains "$brief_lc" "goalforge-capture invocation brief" \
                                           || missing="$missing §invocation-brief"
  contains "$brief_lc" "provenance bridge" || missing="$missing §provenance-bridge"
  contains "$brief_lc" "boundary statement (where wayfind stops)" \
                                           || missing="$missing §boundary"
  # plus the load-bearing contract tokens the headers govern.
  { contains "$brief_lc" "references" && contains "$brief_lc" "sources"; } \
                                           || missing="$missing references-sources-bridge"
  contains "$brief_lc" "self-link"         || missing="$missing wayfind-self-link"
  contains "$brief_lc" "hard-to-reverse"   || missing="$missing hard-to-reverse"
  contains "$brief_lc" "surprising-without-context" || missing="$missing surprising"
  contains "$brief_lc" "real-trade-off"    || missing="$missing real-trade-off"
  contains "$brief_lc" "overview.md"       || missing="$missing ends-at-overview"
  if [ -z "$missing" ]; then pass "$name"
  else fail "$name" "brief missing contract elements:$missing"; fi
fi

# ============================================================================
# aggregate
# ============================================================================
if [ "$fail_count" -eq 0 ]; then
  printf '\ne2e.sh: ALL PASS\n'
  exit 0
fi
printf '\ne2e.sh: %d case(s) FAILED:%s\n' "$fail_count" "$failed_names" >&2
exit 1
