#!/usr/bin/env bash
#
# run.sh — the wp-02 deterministic gate for the wayfind skill.
#
# Aggregates three families of checks, each a named case (ok / FAIL):
#   1. Validator behaviour over the artifacts/ fixtures (valid→0, invalid→1,
#      documented-template-with-comments→0).
#   2. Contract-documentation greps over SKILL.md (the skill documents its
#      contract — chart/work/graduate flows, blind-spot propose-only, quiz-back
#      gate, ordered graduation, ticket_type dispatch table, no-fog early exit,
#      the frontier-JSON-consuming work loop). The graduate-flow contract checks
#      are SCOPED to the graduate-flow section slice, not the whole file, so a
#      gutted graduate flow cannot pass on a stray mention elsewhere.
#   3. Trigger evals over the frontmatter `description` STRING only — static,
#      offline-deterministic content checks (no live model calls).
#
# All paths resolve relative to THIS script (BASH_SOURCE), never cwd.
#
# SCOPE (wp-02 only): this harness does NOT invoke wayfind-frontier.sh
# --self-test (wp-01's gate) or any e2e.sh (wp-03's gate).
#
# Testability: SKILL_MD env var overrides the SKILL.md path (used by the
# negative-control mutation test). Defaults to the sibling skill's SKILL.md.
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
ARTIFACTS="$EVALS_DIR/fixtures/artifacts"

VALIDATE_MAP="$SCRIPTS_DIR/validate-map.sh"
VALIDATE_TICKET="$SCRIPTS_DIR/validate-ticket.sh"
SKILL_MD="${SKILL_MD:-$SKILL_DIR/SKILL.md}"

# --- case-runner scaffolding (style donor: wayfind-frontier.sh --self-test) --
fail_count=0
failed_names=""
fail() { printf 'FAIL [%s]: %s\n' "$1" "$2" >&2; fail_count=$((fail_count + 1)); failed_names="${failed_names} $1"; }
pass() { printf 'ok   [%s]\n' "$1"; }

contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac }

# grep the SKILL.md file, case-insensitive, fixed-string.
skgrep() { grep -qiF -- "$1" "$SKILL_MD"; }

# print the SKILL.md region between two case-insensitive header markers
# (START inclusive-exclusive of END); END empty ⇒ to EOF.
section() {
  awk -v s="$1" -v e="$2" '
    BEGIN{IGNORECASE=1; inx=0}
    { if (index(tolower($0), tolower(s))) {inx=1}
      else if (e!="" && index(tolower($0), tolower(e))) {inx=0}
      if (inx) print }
  ' "$SKILL_MD"
}

# lowercase a blob (so `contains` can match case-insensitively within a slice).
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# 1-indexed line of first case-insensitive fixed-substring match; 0 if none.
line_of() {
  awk -v pat="$1" 'BEGIN{IGNORECASE=1} index($0,pat){print NR; exit}' "$SKILL_MD"
}

# ============================================================================
# Family 1 — validator behaviour over fixtures
# ============================================================================
run_rc() { set +e; bash "$1" "$2" >/dev/null 2>&1; RC=$?; set -e; }

name=validate-map-valid
run_rc "$VALIDATE_MAP" "$ARTIFACTS/map-valid.md"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 on map-valid.md, got $RC"

# invalid fixtures must exit EXACTLY 1 (contract violation) — not any non-zero.
# rc 2 is fail-close (missing/unreadable fixture) and would mask a real bug.
name=validate-map-invalid
run_rc "$VALIDATE_MAP" "$ARTIFACTS/map-invalid.md"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on map-invalid.md, got $RC"

name=validate-ticket-valid
run_rc "$VALIDATE_TICKET" "$ARTIFACTS/ticket-valid.md"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 on ticket-valid.md, got $RC"

name=validate-ticket-invalid
run_rc "$VALIDATE_TICKET" "$ARTIFACTS/ticket-invalid.md"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on ticket-invalid.md, got $RC"

# the documented spec templates carrying their inline `#` comments must VALIDATE
# (quote-aware trailing-comment strip → real values behind the comments).
name=validate-map-template-comments
run_rc "$VALIDATE_MAP" "$ARTIFACTS/map-template-comments.md"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 on map-template-comments.md, got $RC"

name=validate-ticket-template-comments
run_rc "$VALIDATE_TICKET" "$ARTIFACTS/ticket-template-comments.md"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 on ticket-template-comments.md, got $RC"

# ============================================================================
# Family 2 — contract-documentation checks over SKILL.md
# ============================================================================
name=doc-chart-flow
skgrep "chart flow" && pass "$name" || fail "$name" "SKILL.md missing 'chart flow' section"

name=doc-work-flow
skgrep "work flow" && pass "$name" || fail "$name" "SKILL.md missing 'work flow' section"

name=doc-graduate-flow
skgrep "graduate flow" && pass "$name" || fail "$name" "SKILL.md missing 'graduate flow' section"

# The graduate flow's own gates must live INSIDE the graduate-flow slice — a
# blind-spot/propose-only or quiz-back mention elsewhere (e.g. the chart flow)
# must NOT satisfy these. Slice = 'graduate flow' … 'Constraints (inline)'.
grad="$(section 'graduate flow' 'Constraints (inline)')"
grad_lc="$(lc "$grad")"

name=doc-blind-spot-propose-only
if contains "$grad_lc" "blind-spot" && contains "$grad_lc" "propose-only"; then pass "$name"
else fail "$name" "graduate flow slice missing blind-spot re-check + propose-only contract"; fi

name=doc-quiz-back-gate
if contains "$grad_lc" "quiz-back"; then pass "$name"
else fail "$name" "graduate flow slice missing quiz-back gate"; fi

# graduation ordered sequence: converged precondition must appear BEFORE the
# user-confirms-transfer step within the graduate flow.
name=doc-graduation-ordered
pre_ln="$(line_of 'Precondition')"
xfer_ln="$(line_of 'confirms transfer')"
if contains "$grad" 'strictly ordered' \
   && [ "$pre_ln" -gt 0 ] && [ "$xfer_ln" -gt 0 ] && [ "$pre_ln" -lt "$xfer_ln" ]; then
  pass "$name"
else
  fail "$name" "graduation not shown as ordered with converged-precondition before transfer (pre=$pre_ln xfer=$xfer_ln)"
fi

name=doc-ticket-type-dispatch
if skgrep "ticket_type" && skgrep "research" && skgrep "grilling" \
   && skgrep "prototype" && skgrep "task"; then pass "$name"
else fail "$name" "SKILL.md missing ticket_type dispatch table rows"; fi

name=doc-no-fog-early-exit
if skgrep "No-fog" && skgrep "goalforge-capture"; then pass "$name"
else fail "$name" "SKILL.md missing no-fog early exit straight to goalforge-capture"; fi

# work loop consumes wayfind-frontier.sh stdout JSON: the work section must
# reference the script AND the JSON field names frontier + converged.
name=doc-work-loop-frontier-json
work="$(section 'work flow' 'graduate flow')"
if contains "$work" 'wayfind-frontier.sh' \
   && contains "$work" 'frontier' && contains "$work" 'converged'; then
  pass "$name"
else
  fail "$name" "work section does not show the frontier-script JSON-consuming loop"
fi

# the work loop must pass the <PLANS_ROOT>-resolved effort dir to the frontier
# script — scoped to the work-flow slice, not presence-anywhere — and no
# cwd-relative `plans/<effort-slug>` may survive anywhere in SKILL.md.
name=doc-work-loop-plans-root
if contains "$work" 'wayfind-frontier.sh <PLANS_ROOT>/<effort-slug>' \
   && ! grep -qF -- 'plans/<effort-slug>' "$SKILL_MD"; then
  pass "$name"
else
  fail "$name" "work flow does not pass <PLANS_ROOT>/<effort-slug> to the frontier script (or a cwd-relative plans/<effort-slug> survives)"
fi

# <PLANS_ROOT> is CITED from the goalforge schema, never re-invented here.
name=doc-plans-root-citation
if skgrep 'goalforge/references/schema.md' && skgrep 'PLANS_ROOT resolution' \
   && skgrep 'SDD_PLANS_DIR'; then pass "$name"
else fail "$name" "SKILL.md does not cite schema.md §PLANS_ROOT resolution"; fi

# ============================================================================
# Family 3 — trigger evals over the frontmatter description STRING only
# ============================================================================
# Extract the description block: from the `description:` key up to the next
# top-level frontmatter key (argument-hint:), lowercased into one blob.
DESC="$(awk '
  /^description:/{f=1; next}
  /^[a-zA-Z_-]+:/{ if(f) f=0 }
  f{print}
' "$SKILL_MD" | tr "[:upper:]" "[:lower:]" | tr -s "[:space:]" " ")"

name=trigger-positive-chart-foggy
if contains "$DESC" "chart this foggy effort" \
   || { contains "$DESC" "chart" && contains "$DESC" "foggy"; }; then pass "$name"
else fail "$name" "description lacks the 'chart this foggy effort' trigger phrase"; fi

name=trigger-positive-decision-map
if contains "$DESC" "multi-session decision map"; then pass "$name"
else fail "$name" "description lacks the 'multi-session decision map' trigger phrase"; fi

name=trigger-negative-skip-clause
if contains "$DESC" "skip" && contains "$DESC" "goalforge-capture" \
   && { contains "$DESC" "already clear" || contains "$DESC" "one session"; }; then pass "$name"
else fail "$name" "description lacks a SKIP clause routing the clear one-session case to goalforge-capture"; fi

# ============================================================================
# aggregate
# ============================================================================
if [ "$fail_count" -eq 0 ]; then
  printf '\nrun.sh: ALL PASS\n'
  exit 0
fi
printf '\nrun.sh: %d case(s) FAILED:%s\n' "$fail_count" "$failed_names" >&2
exit 1
