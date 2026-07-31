#!/usr/bin/env bash
#
# run.sh — the wp-02 deterministic gate for the wayfind skill.
#
# Aggregates three families of checks, each a named case (ok / FAIL):
#   1. Validator behaviour over the artifacts/ fixtures (valid→0, invalid→1,
#      documented-template-with-comments→0). Ticket fixtures run through the
#      copy-harness below — validate-ticket.sh checks the FILENAME, so each
#      fixture is copied under its INTENDED `ticket-NN-<slug>.md` name first.
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
VALIDATE_LINKAGE="$SCRIPTS_DIR/validate-linkage.sh"
LINKAGE="$EVALS_DIR/fixtures/linkage"
FRONTIER="$SCRIPTS_DIR/wayfind-frontier.sh"
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

# --- artifact copy-harness ---------------------------------------------------
# validate-ticket.sh checks the FILENAME (`ticket-NN-<slug>.md`, NN >= 2 digits)
# and NO artifact fixture on disk carries a conformant name — the fixture names
# are cited across the audit trail and stay as they are. So every ticket fixture
# is copied into a fresh temp dir under its INTENDED name before the validator
# is invoked; the intended name is what the case is actually asserting about.
COPY_ROOT="$(mktemp -d)"
trap 'rm -rf "$COPY_ROOT"' EXIT

# copy_as <fixture-basename> <intended-name> → prints the copied path
copy_as() {
  local d; d="$(mktemp -d "$COPY_ROOT/XXXXXX")"
  cp "$ARTIFACTS/$1" "$d/$2"
  printf '%s' "$d/$2"
}

name=validate-map-valid
run_rc "$VALIDATE_MAP" "$ARTIFACTS/map-valid.md"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 on map-valid.md, got $RC"

# invalid fixtures must exit EXACTLY 1 (contract violation) — not any non-zero.
# rc 2 is fail-close (missing/unreadable fixture) and would mask a real bug.
name=validate-map-invalid
run_rc "$VALIDATE_MAP" "$ARTIFACTS/map-invalid.md"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on map-invalid.md, got $RC"

# --- map contract: references[] / context_pointers / `## Notes` -------------
# One INVALID fixture per new assertion — a valid fixture alone cannot prove an
# assertion fires. Each must exit EXACTLY 1 (contract violation), never 2.
name=validate-map-invalid-reference-entry
run_rc "$VALIDATE_MAP" "$ARTIFACTS/map-invalid-reference-entry.md"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on a typed references[] entry missing locator, got $RC"

name=validate-map-invalid-context-pointers
run_rc "$VALIDATE_MAP" "$ARTIFACTS/map-invalid-context-pointers.md"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on context_pointers carrying an empty string, got $RC"

name=validate-map-invalid-notes-table
run_rc "$VALIDATE_MAP" "$ARTIFACTS/map-invalid-notes-table.md"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on a non-pinned-shape ## Notes table, got $RC"

# references[] entry form (ii) — a bare `- <string>` — is LEGAL and unchecked
# beyond non-emptiness (it reads as {locator: <string>}, lossy but legal).
# Asserted POSITIVELY on a map whose references[] carries ONLY the bare form, so
# map-valid.md's typed-form extension cannot mask a regression here.
name=validate-map-bare-string-reference
BARE_MAP="$(mktemp -d)/map.md"
cat > "$BARE_MAP" <<'EOF'
---
type: wayfind-map
status: working
destination: "Legacy map whose references[] carries only bare-string entries"
created: 2026-07-16
context_pointers: []
references:
  - plans/ideas/payments-rearchitecture.md
---

## Destination

Form (ii) legality regression fixture.
EOF
run_rc "$VALIDATE_MAP" "$BARE_MAP"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 on a bare-string references[] entry, got $RC"
rm -rf "$(dirname "$BARE_MAP")"

name=validate-ticket-valid
run_rc "$VALIDATE_TICKET" "$(copy_as ticket-valid.md ticket-01-valid.md)"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 on ticket-valid.md (as ticket-01-valid.md), got $RC"

name=validate-ticket-invalid
run_rc "$VALIDATE_TICKET" "$(copy_as ticket-invalid.md ticket-02-invalid.md)"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on ticket-invalid.md (as ticket-02-invalid.md), got $RC"

# --- ticket cross-field assertions ------------------------------------------
# One INVALID fixture per new assertion, each copied under its intended name and
# each required to exit EXACTLY 1 (contract violation), never 2 (fail-close).
name=validate-ticket-resolved-no-resolution
run_rc "$VALIDATE_TICKET" "$(copy_as ticket-invalid-resolved-no-resolution.md ticket-11-resolved-no-resolution.md)"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on status: resolved with resolution: null, got $RC"

name=validate-ticket-resolution-nn-mismatch
run_rc "$VALIDATE_TICKET" "$(copy_as ticket-invalid-resolution-nn-mismatch.md ticket-12-nn-mismatch.md)"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on a resolution pointer NN != filename NN, got $RC"

name=validate-ticket-claim-half
run_rc "$VALIDATE_TICKET" "$(copy_as ticket-invalid-claim-half.md ticket-13-claim-half.md)"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on claimed_by set with claimed_at null, got $RC"

# the MIRROR direction (claimed_at set, claimed_by null) — generated from the
# same fixture rather than shipped as an eighth artifact file, so the fixture
# inventory stays at the seven the WP budgets.
name=validate-ticket-claim-half-mirror
MIRROR_DIR="$(mktemp -d "$COPY_ROOT/XXXXXX")"
sed -e 's/^claimed_by: .*/claimed_by: null/' -e 's/^claimed_at: .*/claimed_at: 2026-07-31/' \
  "$ARTIFACTS/ticket-invalid-claim-half.md" > "$MIRROR_DIR/ticket-14-claim-half-mirror.md"
run_rc "$VALIDATE_TICKET" "$MIRROR_DIR/ticket-14-claim-half-mirror.md"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on claimed_at set with claimed_by null, got $RC"

# --- filename width, both directions ----------------------------------------
# The width fixture must fail for its single-digit NN and for NOTHING else, so
# the SAME content copied under a conformant name must exit 0. Without the
# second half the case cannot distinguish a width violation from an incidental
# frontmatter defect.
name=validate-ticket-filename-width
run_rc "$VALIDATE_TICKET" "$(copy_as ticket-invalid-filename-width.md ticket-1-width.md)"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on a single-digit NN filename, got $RC"

name=validate-ticket-filename-width-control
run_rc "$VALIDATE_TICKET" "$(copy_as ticket-invalid-filename-width.md ticket-14-width.md)"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "width fixture failed under a CONFORMANT name — it fails incidentally, not on NN width (got $RC)"

# the documented spec templates carrying their inline `#` comments must VALIDATE
# (quote-aware trailing-comment strip → real values behind the comments).
name=validate-map-template-comments
run_rc "$VALIDATE_MAP" "$ARTIFACTS/map-template-comments.md"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 on map-template-comments.md, got $RC"

name=validate-ticket-template-comments
run_rc "$VALIDATE_TICKET" "$(copy_as ticket-template-comments.md ticket-03-template-comments.md)"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 on ticket-template-comments.md (as ticket-03-template-comments.md), got $RC"

# --- validate-linkage.sh over the linkage fixture tree ----------------------
# Cross-file invariants: every resolved ticket is pointed at from map
# `## Decisions so far`; no pointer targets an open ticket; every `resolution:`
# target file exists. `empty` exits 0 — the DELIBERATE divergence from the
# frontier's zero-tickets fail-close (nothing to link is not a structural error).
for lk in "ok 0" "missing-map-pointer 1" "pointer-to-open 1" "missing-findings 1" \
          "empty 0" "no-wayfind-subdir 2"; do
  set -- $lk
  name="validate-linkage-$1"
  run_rc "$VALIDATE_LINKAGE" "$LINKAGE/$1"
  [ "$RC" -eq "$2" ] && pass "$name" || fail "$name" "expected exit $2 on fixtures/linkage/$1, got $RC"
done

# NEGATIVE CONTROL: the linkage validator must never fork the frontier's sole
# authority over convergence — no `converged` key, no convergence claim, on
# either stream, in the clean case or the violating one.
name=validate-linkage-no-convergence
lk_out=""
for lk in ok missing-map-pointer empty; do
  set +e; lk_out="$lk_out$(bash "$VALIDATE_LINKAGE" "$LINKAGE/$lk" 2>&1)"; set -e
done
if printf '%s' "$lk_out" | grep -qi 'converg'; then
  fail "$name" "validate-linkage.sh output claims/reports convergence: $lk_out"
else pass "$name"; fi

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

# --- map contract prose, section-sliced -------------------------------------
# chart step 1 owns the map frontmatter + body-section list; chart step 2 owns
# the ticket body sections. Slice each rule to the step it constrains — a
# presence-anywhere grep would pass on a mention in the wrong flow.
chart1="$(section '1. Write `map.md`' '2. Seed initial tickets')"
chart1_lc="$(lc "$chart1")"
chart2="$(section '2. Seed initial tickets' '3. Dispatched blind-spot pass')"
chart2_lc="$(lc "$chart2")"

# references[] CITES the canonical typed shape; it is never redefined in-skill.
name=doc-references-canonical-citation
if contains "$chart1_lc" 'idea/references/provenance-mapping.md' \
   && contains "$chart1_lc" 'locator' \
   && contains "$chart1_lc" 'conversation'; then pass "$name"
else fail "$name" "chart step 1 does not cite provenance-mapping.md as the canonical references[] shape"; fi

# a bare-string entry is documented as LEGAL-but-lossy, not as broken.
name=doc-references-bare-string-lossy
if contains "$chart1_lc" 'lossily' || contains "$chart1_lc" 'lossy'; then pass "$name"
else fail "$name" "chart step 1 does not record that a bare-string references[] entry carries over lossily"; fi

# the map body-section list names `## Notes` and pins the override semantics:
# FULL ROW including machinery, and never retroactive to an in-flight dispatch.
name=doc-map-notes-section
if contains "$chart1" '## Notes' \
   && contains "$chart1" '| ticket_type | machinery | model | effort |' \
   && contains "$chart1_lc" 'full row' \
   && contains "$chart1_lc" 'including machinery' \
   && contains "$chart1_lc" 'retroactively'; then pass "$name"
else fail "$name" "chart step 1 map body-section list missing ## Notes / the pinned table / FULL-ROW-incl-machinery / not-retroactive rule"; fi

# the ticket body gains an OPTIONAL `## Resolution notes` home for mid-loop
# partial answers, so `## Question` is never rewritten to carry its own answer.
# --- ticket NN width + claim discipline, section-sliced ---------------------
# The Claim step owns claim-before-dispatch: a mandatory-claim sentence anywhere
# else in the file (or in the Gotchas) must NOT satisfy this.
name=doc-claim-before-dispatch
claim_lc="$(lc "$(section '**Claim** —' '**Dispatch** per')")"
if contains "$claim_lc" 'mandatory before dispatch or resolve'; then pass "$name"
else fail "$name" "work-flow Claim slice does not state that claiming is MANDATORY before dispatch or resolve"; fi

# Cross-surface NN-width consistency. The rule is pinned ONCE as an AUTHORING
# rule on exactly two surfaces (SKILL.md chart step 2, validate-ticket.sh's
# filename check); the two READERS stay tolerant. Asserting the same regex on
# all four would certify a pin that MUST NOT happen — so the reader assertions
# here are positive assertions that they were NOT tightened.
name=doc-nn-width-cross-surface
missing=""
contains "$chart2" 'ticket-[0-9]{2,}'      || missing="$missing skill-md-regex"
contains "$chart2_lc" 'at least two digits' || missing="$missing skill-md-statement"
grep -qF -- '^ticket-[0-9]{2,}-[a-z0-9-]+\.md$' "$VALIDATE_TICKET" \
                                           || missing="$missing validate-ticket-filename-check"
grep -qF -- 'at least two digits' "$VALIDATE_TICKET" \
                                           || missing="$missing validate-ticket-statement"
# tolerant readers, UNCHANGED (frontier L334, validate-ticket depends_on L159+)
grep -qF -- '^ticket-[0-9]+$' "$FRONTIER"  || missing="$missing frontier-reader-tightened"
grep -qF -- '^ticket-[0-9]+$' "$VALIDATE_TICKET" \
                                           || missing="$missing depends-on-reader-tightened"
grep -qiF -- 'deliberately tolerant' "$VALIDATE_TICKET" \
                                           || missing="$missing depends-on-rationale-comment"
# and never an exact-two pin anywhere (it would cap a map at 100 tickets):
# every `ticket-[0-9]{2…}` occurrence in the scripts must be the `{2,}` form.
if grep -oh 'ticket-\[0-9\]{2[^}]*}' "$VALIDATE_TICKET" "$FRONTIER" \
     | grep -qv 'ticket-\[0-9\]{2,}'; then missing="$missing exact-two-pin-present"; fi
if [ -z "$missing" ]; then pass "$name"
else fail "$name" "NN-width pin inconsistent across surfaces:$missing"; fi

# The End-the-session step is the FIRST validator invocation point the skill has
# ever had — all three validators are inert unless the flow runs them. Sliced to
# that step: a validator mention anywhere else must NOT satisfy this.
name=doc-end-session-validators
endsess_lc="$(lc "$(section '**End the session**' 'graduate flow')")"
missing=""
contains "$endsess_lc" 'validate-map.sh'     || missing="$missing validate-map"
contains "$endsess_lc" 'validate-ticket.sh'  || missing="$missing validate-ticket"
contains "$endsess_lc" 'validate-linkage.sh' || missing="$missing validate-linkage"
contains "$endsess_lc" 'before committing'   || missing="$missing fix-before-commit"
if [ -z "$missing" ]; then pass "$name"
else fail "$name" "End-the-session slice missing:$missing"; fi

name=doc-ticket-resolution-notes
if contains "$chart2" '## Resolution notes' \
   && contains "$chart2_lc" 'optional'; then pass "$name"
else fail "$name" "chart step 2 does not name the OPTIONAL ## Resolution notes ticket body section"; fi

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
