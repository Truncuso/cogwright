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
# The AUTHORITATIVE command file is the in-repo, hand-authored
# plugins/goalforge/commands/wayfind.md (generator PRESERVE list) — NOT the
# dotfiles mirror. The repo's own gate must not depend on a file in another
# repo, so there is no $HOME in this default. evals/ is package-only (the
# generator does not ship it into plugins/), so SKILL_DIR is always
# <repo>/packages/goalforge/wayfind and the climb is unconditional.
# WAYFIND_CMD_MD overrides it — a caller-facing testability override; before
# negative-control-command-plans-root below there was no consumer at all.
CMD_MD="${WAYFIND_CMD_MD:-$SKILL_DIR/../../../plugins/goalforge/commands/wayfind.md}"
BRIEF_MD="${WAYFIND_BRIEF_MD:-$SKILL_DIR/references/graduation-brief.md}"

# --- case-runner scaffolding ------------------------------------------------
fail_count=0
failed_names=""
fail() { printf 'FAIL [%s]: %s\n' "$1" "$2" >&2; fail_count=$((fail_count + 1)); failed_names="${failed_names} $1"; }
pass() { printf 'ok   [%s]\n' "$1"; }

contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac }

# lowercase a file's content into one blob (case-insensitive substring checks)
lc_file() { tr '[:upper:]' '[:lower:]' < "$1" | tr -s '[:space:]' ' '; }
# lowercase a string (for slice-scoped, case-insensitive substring checks)
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

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
  # portable in-place edit: rewrite the status line, and null the resolution
  # pointer with it — validate-ticket.sh pins `status: resolved` ⇔ non-null
  # `resolution` in BOTH directions, so an open ticket still carrying its
  # findings pointer is itself a contract violation and would fail the
  # still-validates assertion below for a reason unrelated to convergence.
  tmp_tk="$(mktemp)"
  sed -e 's/^status: resolved$/status: open/' -e 's|^resolution: .*|resolution: null|' \
    "$FLIP" > "$tmp_tk" && mv "$tmp_tk" "$FLIP"
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
# Case: command-plans-root — the authoritative command file passes the
# <PLANS_ROOT>-resolved effort dir to the frontier script, and no cwd-relative
# `plans/<effort-slug>` survives. Mentioning PLANS_ROOT is NOT enough: the
# frontier invocation itself must carry it as the argument.
# ============================================================================
cmd_plans_root_ok() {
  local f="$1"
  grep -q 'PLANS_ROOT' "$f" || return 1
  grep -q 'wayfind-frontier\.sh <PLANS_ROOT>/<effort-slug>' "$f" || return 1
  if grep -q 'plans/<effort-slug>' "$f"; then return 1; fi
  return 0
}

name=command-plans-root
if [ ! -f "$CMD_MD" ]; then fail "$name" "command file not found: $CMD_MD"
elif cmd_plans_root_ok "$CMD_MD"; then pass "$name"
else fail "$name" "command file does not pass <PLANS_ROOT>/<effort-slug> to the frontier script: $CMD_MD"; fi

# ============================================================================
# Case: negative-control-command-plans-root — command-plans-root alone is
# presence-only and would pass on any file that happens to carry the token.
# Copy the authoritative file, rewrite the resolved effort-dir argument back to
# the cwd-relative form (the exact regression), and assert the check FAILS.
# The copy KEEPS a PLANS_ROOT mention, so a lax grep-for-the-word check cannot
# satisfy this case.
# ============================================================================
name=negative-control-command-plans-root
if [ ! -f "$CMD_MD" ]; then fail "$name" "command file not found: $CMD_MD"
else
  TMP_CMD="$(mktemp -d)"
  trap 'rm -rf "$TMP_EFFORT" "$TMP_CMD"' EXIT
  sed 's|<PLANS_ROOT>/<effort-slug>|plans/<effort-slug>|g' "$CMD_MD" > "$TMP_CMD/wayfind.md"
  # (the check is invoked directly on the copy; WAYFIND_CMD_MD stays the
  # caller-facing override that points the WHOLE harness at another file.)
  if cmd_plans_root_ok "$TMP_CMD/wayfind.md"; then
    fail "$name" "stripped command copy still passed the <PLANS_ROOT> contract check"
  else
    pass "$name"
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
  # §2 must carry the completed-work vs scope-bullet discriminator (audit-11):
  # convergence resolves every task ticket, so a §2 selecting scope on
  # "resolved" alone hands executed work to goalforge-decompose as scope. Scoped
  # to the §2 slice — the discriminator has to live where the brief is composed.
  brief_s2="$(lc "$(awk '/^## 2\./,/^## 3\./' "$BRIEF_MD")")"
  contains "$brief_s2" "completed work" || missing="$missing s2-completed-work"
  contains "$brief_s2" "decision about future work" \
                                        || missing="$missing s2-scope-discriminator"
  # §2 must also carry the `Learning goals:` subsection alongside the other
  # brief subsections, WITH its two load-bearing properties: the subsection is
  # omitted when the map has none (learning is opt-in, default none), and an
  # unresolved goal is reported as unresolved rather than dropped. Scoped to §2
  # — the subsection has to live where the brief is composed, and a mention in
  # references/learning-goals.md cannot satisfy it.
  contains "$brief_s2" "learning goals" || missing="$missing s2-learning-goals"
  contains "$brief_s2" "unresolved"     || missing="$missing s2-learning-unresolved"
  contains "$brief_s2" "omit"           || missing="$missing s2-learning-opt-in-omission"
  # §3's reference `type` vocabulary must be the CANONICAL enum, not the
  # divergent subset `file | repo | video | url` — that subset rejects
  # `type: session`, which the first flight and the idea stub both use. Scoped
  # to the §3 slice: a `session` mention elsewhere in the brief cannot satisfy
  # it, and the superseded subset string must be GONE from the slice.
  brief_s3="$(awk '/^## 3\./,/^## 4\./' "$BRIEF_MD")"
  contains "$(lc "$brief_s3")" "session"   || missing="$missing s3-canonical-enum"
  case "$brief_s3" in
    *"file | repo | video | url"*) missing="$missing s3-divergent-enum-survives" ;;
  esac
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
