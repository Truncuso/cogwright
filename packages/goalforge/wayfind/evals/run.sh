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
# The mutation pass itself is `evals/mutate.sh`, invoked at the END of a normal
# run (it re-enters this script once per mutation with a gutted SKILL_MD copy).
# WAYFIND_MUTATION_CHILD=1 suppresses that call in the child runs.
#
# COVERAGE MAP (wp-01 task-07 consolidation audit) — every new rule/assertion of
# this WP to the case that gates it:
#   audit-1  typed references[] + enum   → validate-map-invalid-reference-entry,
#                                          validate-map-bare-string-reference,
#                                          doc-references-canonical-citation,
#                                          doc-references-bare-string-lossy
#                                          (graduation-brief §3 enum: e2e.sh)
#   audit-2  ticket cross-field + NN     → validate-ticket-{resolved-no-resolution,
#                                          resolution-nn-mismatch,claim-half,
#                                          claim-half-mirror,filename-width,
#                                          filename-width-control},
#                                          doc-nn-width-cross-surface
#   audit-3  linkage + invocation point  → validate-linkage-* (6 cases),
#                                          validate-linkage-no-convergence,
#                                          doc-end-session-validators
#   audit-4  invocation surface          → doc-work-loop-plans-root,
#                                          doc-plans-root-citation (+ e2e.sh)
#   audit-9  two out-of-scope homes      → doc-out-of-scope-split
#   audit-10 claim-before-dispatch       → doc-claim-before-dispatch (prose only)
#   audit-11 scope discriminator         → doc-graduate-scope-discriminator
#   stream-1a `## Notes` override        → validate-map-invalid-notes-table,
#                                          doc-map-notes-section,
#                                          doc-dispatch-notes-override
#   stream-1b `## Resolution notes`      → doc-ticket-resolution-notes
#   stream-2  mid-loop fog moves         → doc-mid-loop-fog-moves,
#                                          doc-converged-not-no-fog
#   stream-3  fog precision / slicing /  → doc-fog-precision, doc-no-pre-slicing,
#             one-ticket-per-session       doc-one-ticket-per-session
#   package   version + prose budget     → skill-version, skill-line-budget
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

# Same, but ALSO captures the validator's stderr into ERR. Used where exit-code
# equality is too coarse to discriminate: an rc-only assertion passes even when
# the intended guard is deleted and bash itself errors out, so a case guarding a
# specific rule asserts that the rule's own message named the field and reason.
run_rc_err() { set +e; ERR="$(bash "$1" "$2" 2>&1 >/dev/null)"; RC=$?; set -e; }

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

# repaired_as / derived_as <fixture-basename> <intended-name> <sed-arg…> →
# prints the path. One mechanism (copy the fixture through a sed program), TWO
# polarities, named apart so a call site declares which one it is:
#
#   repaired_as — INVALID fixture, single offending field REPAIRED. The
#     mutate-one-field control: the copy must flip to exit 0, otherwise the
#     fixture fails for some OTHER reason and its invalid-case proves nothing.
#   derived_as  — VALID fixture, one field BROKEN (or a legal variant applied).
#     Generates a negative (or a second positive) without shipping another
#     artifact, keeping the on-disk fixture inventory minimal.
repaired_as() {
  local fx="$1" nm="$2"; shift 2
  local d; d="$(mktemp -d "$COPY_ROOT/XXXXXX")"
  sed "$@" "$ARTIFACTS/$fx" > "$d/$nm"
  printf '%s' "$d/$nm"
}
derived_as() { repaired_as "$@"; }

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

# --- mutate-one-field controls over every new INVALID fixture ----------------
# Each invalid fixture must fail for its INTENDED assertion and not incidentally.
# The width fixture already carries its control above (same content, conformant
# name → 0); the other five repair their single offending field and must flip to
# exit 0. The map fixtures keep their on-disk names (validate-map.sh has no
# filename check); the ticket ones stay under their intended names.
name=control-map-reference-entry-repaired
run_rc "$VALIDATE_MAP" "$(repaired_as map-invalid-reference-entry.md map.md \
  -e 's|^    type: url$|    type: url\n    locator: "Matt Pocock — wayfinder SKILL.md"|')"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "reference-entry fixture still fails once locator is supplied — it fails incidentally (got $RC)"

name=control-map-context-pointers-repaired
run_rc "$VALIDATE_MAP" "$(repaired_as map-invalid-context-pointers.md map.md \
  -e 's|^  - ""$|  - src/billing/**|')"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "context_pointers fixture still fails once the empty entry is non-empty — it fails incidentally (got $RC)"

name=control-map-notes-table-repaired
run_rc "$VALIDATE_MAP" "$(repaired_as map-invalid-notes-table.md map.md \
  -e 's@^| ticket_type | model | effort |$@| ticket_type | machinery | model | effort |@' \
  -e 's@^|---|---|---|$@|---|---|---|---|@' \
  -e 's@^| research | opus | medium |$@| research | research-analyst | opus | medium |@')"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "## Notes fixture still fails once the table is the pinned 4-column shape — it fails incidentally (got $RC)"

name=control-ticket-resolved-no-resolution-repaired
run_rc "$VALIDATE_TICKET" "$(repaired_as ticket-invalid-resolved-no-resolution.md ticket-11-resolved-no-resolution.md \
  -e 's|^resolution: null$|resolution: ./findings/ticket-11.md|')"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "resolved-no-resolution fixture still fails once resolution is set — it fails incidentally (got $RC)"

name=control-ticket-resolution-nn-mismatch-repaired
run_rc "$VALIDATE_TICKET" "$(repaired_as ticket-invalid-resolution-nn-mismatch.md ticket-12-nn-mismatch.md \
  -e 's|^resolution: ./findings/ticket-07.md$|resolution: ./findings/ticket-12.md|')"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "nn-mismatch fixture still fails once the pointer NN matches the filename — it fails incidentally (got $RC)"

name=control-ticket-claim-half-repaired
run_rc "$VALIDATE_TICKET" "$(repaired_as ticket-invalid-claim-half.md ticket-13-claim-half.md \
  -e 's|^claimed_at: null$|claimed_at: 2026-07-31|')"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "claim-half fixture still fails once both claim fields are set — it fails incidentally (got $RC)"

# --- ticket fan-out (`fan_out: N`) ------------------------------------------
# Three fixtures for the two halves of the rule (legal type, legal value) plus
# the positive. Same discipline as every other artifact case: invalid fixtures
# exit EXACTLY 1, and each carries a mutate-one-field control proving it fails
# for its INTENDED violation and nothing else. Contract: references/ticket-fanout.md §1.
name=validate-ticket-fan-out-valid
run_rc "$VALIDATE_TICKET" "$(copy_as ticket-valid-fan-out.md ticket-21-fan-out.md)"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 on fan_out: 3 on a research ticket, got $RC"

name=validate-ticket-fan-out-non-research
run_rc "$VALIDATE_TICKET" "$(copy_as ticket-invalid-fan-out-non-research.md ticket-22-fan-out-non-research.md)"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on fan_out on a non-research ticket, got $RC"

name=validate-ticket-fan-out-value
run_rc "$VALIDATE_TICKET" "$(copy_as ticket-invalid-fan-out-value.md ticket-23-fan-out-value.md)"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on fan_out: 1 (one probe is not a fan-out), got $RC"

# the non-integer half of the value rule, generated from the VALID fixture
# rather than shipped as a fourth artifact — the inventory stays at three.
# rc ALONE is not discriminating here. Delete the digit guard and the `-ge`
# test below still exits 1 with a typed message — bash's `[` returns 2 on a
# non-integer operand, which trips the same `|| bad`. What the guard actually
# buys is a CLEAN stderr, so both value cases assert the validator's own typed
# message (field + reason) AND the absence of bash's raw arithmetic complaint.
name=validate-ticket-fan-out-non-integer
run_rc_err "$VALIDATE_TICKET" "$(derived_as ticket-valid-fan-out.md ticket-24-fan-out-non-integer.md \
  -e 's|^fan_out: 3$|fan_out: many|')"
if [ "$RC" -eq 1 ] && contains "$(lc "$ERR")" 'fan_out' && contains "$(lc "$ERR")" 'expected an integer' \
   && ! contains "$ERR" 'integer expression expected'; then pass "$name"
else fail "$name" "expected exit 1 with only the typed fan_out message on a non-integer value, got rc=$RC stderr='$ERR'"; fi

# the out-of-range half of the same guard: a digit run too long for a signed
# 64-bit integer is rejected by SHAPE, before `-ge` ever sees the operand.
name=validate-ticket-fan-out-overlong
run_rc_err "$VALIDATE_TICKET" "$(derived_as ticket-valid-fan-out.md ticket-26-fan-out-overlong.md \
  -e 's|^fan_out: 3$|fan_out: 99999999999999999999|')"
if [ "$RC" -eq 1 ] && contains "$(lc "$ERR")" 'fan_out' && contains "$(lc "$ERR")" 'expected an integer' \
   && ! contains "$ERR" 'integer expression expected'; then pass "$name"
else fail "$name" "expected exit 1 with only the typed fan_out message on an out-of-range value, got rc=$RC stderr='$ERR'"; fi

name=control-ticket-fan-out-non-research-repaired
run_rc "$VALIDATE_TICKET" "$(repaired_as ticket-invalid-fan-out-non-research.md ticket-22-fan-out-non-research.md \
  -e 's|^ticket_type: grilling$|ticket_type: research|')"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "fan-out-non-research fixture still fails once ticket_type is research — it fails incidentally (got $RC)"

name=control-ticket-fan-out-value-repaired
run_rc "$VALIDATE_TICKET" "$(repaired_as ticket-invalid-fan-out-value.md ticket-23-fan-out-value.md \
  -e 's|^fan_out: 1$|fan_out: 2|')"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "fan-out-value fixture still fails once fan_out is 2 — it fails incidentally (got $RC)"

# ABSENCE is valid on EVERY type — fan_out is opt-in and never required. Proven
# by stripping the field from the valid fixture AND by every pre-existing ticket
# fixture above, none of which carries it.
name=validate-ticket-fan-out-absent
run_rc "$VALIDATE_TICKET" "$(derived_as ticket-valid-fan-out.md ticket-25-fan-out-absent.md \
  -e '/^fan_out: 3$/d')"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 with fan_out absent on a research ticket, got $RC"

# --- learning goals (opt-in `## Learning goals` + `ticket_type: learning`) ---
# The new enum value relaxes nothing, so the ticket half is proven by a POSITIVE
# (a learning ticket validates) plus a NEGATIVE that an existing rule still
# fires on it (`mode` is task-only). The map half proves the section rule in
# both directions plus ABSENCE. Contract: references/learning-goals.md §2-§3.
name=validate-ticket-learning-valid
run_rc "$VALIDATE_TICKET" "$(copy_as ticket-valid-learning.md ticket-31-learning.md)"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 on ticket_type: learning, got $RC"

name=validate-ticket-learning-mode
run_rc "$VALIDATE_TICKET" "$(copy_as ticket-invalid-learning-mode.md ticket-32-learning-mode.md)"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on mode: HITL on a learning ticket (mode is task-only), got $RC"

name=control-ticket-learning-mode-repaired
run_rc "$VALIDATE_TICKET" "$(repaired_as ticket-invalid-learning-mode.md ticket-32-learning-mode.md \
  -e '/^mode: HITL$/d')"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "learning-mode fixture still fails once mode is dropped — it fails incidentally (got $RC)"

# the `## Notes` ticket_type enum was WIDENED to accept `learning` (an override
# row may target any type the dispatch table carries). A widening is only proven
# by a POSITIVE that the old enum rejected, paired with a NEGATIVE showing the
# enum still rejects a type that is not in it — otherwise "accepts learning" is
# indistinguishable from "accepts anything".
name=validate-map-notes-learning-override
run_rc "$VALIDATE_MAP" "$ARTIFACTS/map-valid-notes-learning-override.md"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 on a ## Notes override row targeting ticket_type learning, got $RC"

name=validate-map-notes-bogus-ticket-type
run_rc "$VALIDATE_MAP" "$(derived_as map-valid-notes-learning-override.md map.md \
  -e 's@^| learning | interview | main | n/a |$@| coaching | interview | main | n/a |@')"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on a ## Notes override row with a ticket_type outside the enum, got $RC"

name=validate-map-learning-goals-valid
run_rc "$VALIDATE_MAP" "$ARTIFACTS/map-valid-learning-goals.md"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 on a well-formed ## Learning goals section, got $RC"

name=validate-map-invalid-learning-goals
run_rc "$VALIDATE_MAP" "$ARTIFACTS/map-invalid-learning-goals.md"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on a non-kebab-case ## Learning goals slug, got $RC"

name=control-map-learning-goals-repaired
run_rc "$VALIDATE_MAP" "$(repaired_as map-invalid-learning-goals.md map.md \
  -e 's|^- PG_Isolation_Levels: |- pg-isolation-levels: |')"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "learning-goals fixture still fails once the slug is kebab-case — it fails incidentally (got $RC)"

# a row that carries a slug and no objective is the OTHER half of the row rule,
# generated from the VALID fixture rather than shipped as a third map artifact.
# The row fails the SHAPE match (the trimmed line has nothing after the colon) —
# there is no separate empty-objective branch to reach, which is why the case is
# named for the missing objective and not for a blank one.
name=validate-map-learning-goals-objective-missing
run_rc "$VALIDATE_MAP" "$(derived_as map-valid-learning-goals.md map.md \
  -e 's|^- pg-isolation-levels: .*$|- pg-isolation-levels:|')"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on a ## Learning goals row with no objective, got $RC"

# the section carries ROWS AND NOTHING ELSE: a prose line inside it is a
# contract violation, the same posture ## Notes takes toward non-table content.
# Contract: references/learning-goals.md §2.
name=validate-map-learning-goals-prose-line
run_rc "$VALIDATE_MAP" "$(derived_as map-valid-learning-goals.md map.md \
  -e '/^- rate-limiter-semantics: /i\
These two goals both block the retry decision.')"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on a ## Learning goals section carrying a prose line, got $RC"

# a present-but-row-less section is invalid: an empty section should have been
# left out entirely (same posture as the ## Notes present-but-tableless rule).
name=validate-map-learning-goals-no-rows
run_rc "$VALIDATE_MAP" "$(derived_as map-valid-learning-goals.md map.md \
  -e '/^- rate-limiter-semantics: /d' -e '/^- pg-isolation-levels: /d')"
[ "$RC" -eq 1 ] && pass "$name" || fail "$name" "expected exit 1 on a ## Learning goals section carrying no rows, got $RC"

# ABSENCE is valid on EVERY map — learning is opt-in and no map before this
# section existed carries one. Proven by stripping the section from the valid
# fixture AND by every other map fixture above, none of which has one.
name=validate-map-learning-goals-absent
run_rc "$VALIDATE_MAP" "$(derived_as map-valid-learning-goals.md map.md \
  -e '/^## Learning goals$/d' -e '/^- rate-limiter-semantics: /d' -e '/^- pg-isolation-levels: /d')"
[ "$RC" -eq 0 ] && pass "$name" || fail "$name" "expected exit 0 with the ## Learning goals section absent, got $RC"

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
# The package version is asserted HERE and nowhere else in the harness — a
# batch of 4 streams + 7 audit items is a minor bump, and an unasserted version
# silently drifts from the contract it names.
name=skill-version
if grep -qE '^[[:space:]]+version: 0\.3\.0$' "$SKILL_MD"; then pass "$name"
else fail "$name" "SKILL.md frontmatter does not read metadata.version: 0.3.0"; fi

# Prose budget as an ASSERTION, not an inspection: SKILL.md is always-loaded, so
# growth is a real cost. Ceiling 385 = 361 (0.2.0 as-built: 301 baseline + 60)
# + 8 (0.3.0 ticket fan-out) + 12 (0.3.0 learning goals) + 4 slack.
# An unmeasured budget is not a constraint.
name=skill-line-budget
sk_lines="$(wc -l < "$SKILL_MD")"
if [ "$sk_lines" -le 385 ]; then pass "$name"
else fail "$name" "SKILL.md is $sk_lines lines, over the 385 ceiling (361 as-built at 0.2.0 + 8 fan-out + 12 learning + 4 slack)"; fi

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

# audit-11: the scope discriminator. Convergence resolves every task ticket, so
# "resolved" alone cannot select scope bullets — the graduate-flow slice must
# state POSITIVELY that only a resolution which is a decision about future work
# becomes scope, and that executed work is reported as completed work. Scoped to
# the slice so a mention in graduation-brief.md or elsewhere cannot satisfy it.
name=doc-graduate-scope-discriminator
if contains "$grad_lc" 'decision about future work' \
   && contains "$grad_lc" 'completed work' \
   && contains "$grad_lc" 'never as scope'; then
  pass "$name"
else
  fail "$name" "graduate flow slice missing the completed-work vs scope-bullet discriminator"
fi

name=doc-ticket-type-dispatch
if skgrep "ticket_type" && skgrep "research" && skgrep "grilling" \
   && skgrep "prototype" && skgrep "task"; then pass "$name"
else fail "$name" "SKILL.md missing ticket_type dispatch table rows"; fi

# The Dispatch step must POINT AT the per-effort override, not just define it in
# chart step 1 — a dispatcher reading only the work flow would otherwise apply
# the default table blind. Sliced to Dispatch: the chart-step-1 definition (or
# any mention elsewhere) must NOT satisfy this.
name=doc-dispatch-notes-override
dispatch_lc="$(lc "$(section '**Dispatch** per' '**Resolve** —')")"
if contains "$dispatch_lc" '## notes' && contains "$dispatch_lc" 'full row'; then
  pass "$name"
else
  fail "$name" "work-flow Dispatch slice does not say a map ## Notes row replaces the full row below"
fi

# wp-08 preset wiring, section-sliced. The pre-existing legs around it assert
# only tokens that were ALREADY in the wp-05 placeholder prose ('quiz-back',
# 'teach-back', the bare ticket_type names), so they were green before the
# rewiring and stay green if it is removed — they measure nothing about it.
# These two pin the `preset:` literals themselves, in the Dispatch slice, so
# unwiring wayfind from the interview engine is a suite failure.
name=doc-dispatch-preset-wiring
missing=""
contains "$dispatch_lc" 'preset: wayfind-probe' || missing="$missing grilling-preset"
contains "$dispatch_lc" 'preset: teach-back'    || missing="$missing learning-preset"
if [ -z "$missing" ]; then pass "$name"
else fail "$name" "work-flow Dispatch table rows not wired to their interview presets:$missing"; fi

name=doc-quiz-back-gate-preset
if contains "$grad_lc" 'preset: quiz-back'; then pass "$name"
else fail "$name" "graduate flow quiz-back gate not wired to \`preset: quiz-back\` (the bare 'quiz-back' token doc-quiz-back-gate matches is satisfied by the findings/quiz-back.md filename)"; fi

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

# --- ticket fan-out prose, section-sliced -----------------------------------
# Two INDEPENDENT surfaces carry the rule and each gets its own case: chart
# step 2 owns the frontmatter FIELD (an author reading the template must see
# where `fan_out` is legal), the work-flow Dispatch step owns the BEHAVIOUR (a
# dispatcher must see the surface pick and the reference). A mention in the
# other slice must NOT satisfy either case.
name=doc-ticket-fan-out-schema
missing=""
contains "$chart2"    'fan_out:'                       || missing="$missing field"
contains "$chart2_lc" 'only on ticket_type: research'  || missing="$missing research-only"
contains "$chart2"    '>= 2'                           || missing="$missing min-value"
contains "$chart2_lc" 'optional'                       || missing="$missing stated-as-optional"
if [ -z "$missing" ]; then pass "$name"
else fail "$name" "chart step 2 ticket frontmatter block missing the fan_out field rules:$missing"; fi

# The dispatch-surface rule is CITED from dispatch-resolution.md via the
# reference, never restated as a second authority in SKILL.md — so this case
# asserts the surface DISCRIMINATOR (uniform effort → Agent, mixed → Workflow)
# plus the pointer that carries the full contract.
name=doc-fan-out-dispatch-surface
missing=""
contains "$dispatch_lc" 'fan_out'                      || missing="$missing field"
contains "$dispatch_lc" 'ticket fan-out'               || missing="$missing variant-name"
contains "$dispatch_lc" 'propose-only'                 || missing="$missing propose-only"
contains "$dispatch_lc" 'agent tool'                   || missing="$missing agent-surface"
contains "$dispatch_lc" 'workflow tool'                || missing="$missing workflow-surface"
contains "$dispatch_lc" 'efforts mix'                  || missing="$missing surface-discriminator"
contains "$dispatch_lc" 'references/ticket-fanout.md'  || missing="$missing contract-pointer"
if [ -z "$missing" ]; then pass "$name"
else fail "$name" "work-flow Dispatch slice missing the ticket fan-out surface rule and/or contract pointer:$missing"; fi

# chart step 3 (blind-spot triage) and the whole work flow, lowercased. SHARED
# by the learning-goals cases below and the fog-semantics cases further down.
chart3="$(section '3. Dispatched blind-spot pass' '4. Close chart')"
chart3_lc="$(lc "$chart3")"
work_lc="$(lc "$work")"

# --- learning goals prose, section-sliced ------------------------------------
# Four INDEPENDENT surfaces carry the learning contract and each gets its own
# case: chart step 1 owns the map SECTION, chart step 2 owns the ENUM value, the
# blind-spot triage step owns the CANDIDATE extension, and the work-flow
# Dispatch step owns the dispatch ROW plus the opt-in rule. A mention in another
# slice must NOT satisfy any of them. Contract: references/learning-goals.md.
name=doc-learning-map-section
missing=""
# the VALIDATED shape is `- <slug>: <objective>`; the `(why: …)` tail is a
# documented CONVENTION (references/learning-goals.md §2 owns it), so the case
# asserts the validated shape and that the tail is labelled as convention —
# never that SKILL.md restates the tail as if it were part of the shape.
contains "$chart1"    '## Learning goals'      || missing="$missing section-name"
contains "$chart1"    '- <slug>: <objective>'  || missing="$missing row-format"
contains "$chart1_lc" 'kebab-case'             || missing="$missing slug-case"
contains "$chart1_lc" 'convention'             || missing="$missing why-tail-is-convention"
contains "$chart1_lc" 'optional'               || missing="$missing stated-as-optional"
if [ -z "$missing" ]; then pass "$name"
else fail "$name" "chart step 1 map body-section list missing the OPTIONAL ## Learning goals section:$missing"; fi

name=doc-learning-ticket-type-enum
if contains "$chart2" 'ticket_type: research | grilling | prototype | task | learning'; then pass "$name"
else fail "$name" "chart step 2 ticket frontmatter block does not carry learning in the ticket_type enum"; fi

# the blind-spot pass MAY return a learning candidate, on a knowledge-gap signal
# only, and it stays propose-only + user-triaged like every other candidate.
name=doc-learning-blind-spot-candidate
missing=""
contains "$chart3"    'task|learning'          || missing="$missing candidate-enum"
contains "$chart3_lc" 'knowledge-gap signal'   || missing="$missing gap-signal-condition"
contains "$chart3_lc" 'never auto-created'     || missing="$missing never-auto-created"
if [ -z "$missing" ]; then pass "$name"
else fail "$name" "chart step 3 slice missing the learning blind-spot candidate extension:$missing"; fi

name=doc-learning-dispatch-row
missing=""
contains "$dispatch_lc" '| learning | hitl |'  || missing="$missing row"
contains "$dispatch_lc" 'teach-back'           || missing="$missing machinery"
contains "$dispatch_lc" 'main session'         || missing="$missing not-dispatched"
if [ -z "$missing" ]; then pass "$name"
else fail "$name" "work-flow Dispatch table missing the learning row (HITL teach-back in the main session):$missing"; fi

# THE load-bearing rule: opt-in, default none, two user-gated entry paths, never
# auto-created — plus the resolution semantics and the contract pointer.
name=doc-learning-opt-in
missing=""
contains "$dispatch_lc" 'default none'                   || missing="$missing default-none"
contains "$dispatch_lc" 'explicit user declaration'      || missing="$missing entry-path-1"
contains "$dispatch_lc" 'blind-spot candidate'           || missing="$missing entry-path-2"
contains "$dispatch_lc" 'never auto-created'             || missing="$missing no-auto-creation"
contains "$dispatch_lc" 'learned enough to'              || missing="$missing resolution-semantics"
contains "$dispatch_lc" 'references/learning-goals.md'   || missing="$missing contract-pointer"
if [ -z "$missing" ]; then pass "$name"
else fail "$name" "work-flow Dispatch slice missing the learning opt-in/default-none rule:$missing"; fi

# --- fog semantics, section-sliced ------------------------------------------
# Three INDEPENDENT rules (fog precision, no pre-slicing, one ticket per
# session) get three INDEPENDENT cases, never one bundle — plus the two-homes
# split and the rewritten Gotcha. Each is scoped to the flow slice that owns it;
# the triage step owns the two out-of-scope homes, the work loop owns the
# mid-loop moves, and a mention in the wrong flow must NOT satisfy the case.
# (chart3 / chart3_lc / work_lc are sliced once, above the learning cases.)

# The two out-of-scope homes are NOT interchangeable: the map body section is
# inert to the frontier, the ticket status is dependency-satisfying.
name=doc-out-of-scope-split
missing=""
contains "$chart3"    '## Out of scope'        || missing="$missing map-section-home"
contains "$chart3"    'status: out-of-scope'   || missing="$missing ticket-status-home"
contains "$chart3_lc" 'never-ticketed'         || missing="$missing never-ticketed"
contains "$chart3_lc" 'inert to the frontier'  || missing="$missing section-inert"
contains "$chart3_lc" 'dependency-satisfying'  || missing="$missing dep-satisfying"
contains "$chart3_lc" "depends_on"             || missing="$missing cannot-satisfy-dependent"
if [ -z "$missing" ]; then pass "$name"
else fail "$name" "chart step 3 slice does not disambiguate the two out-of-scope homes:$missing"; fi

# JUDGMENT-SHAPED RULE: this case asserts the rule TEXT is present in its slice.
# It CANNOT assert the judgment ("is this candidate statable-but-not-answerable?")
# was actually applied — no deterministic check can. Stated so no task over-promises.
name=doc-fog-precision
if contains "$chart3_lc" 'statable now but not answerable now' \
   && contains "$chart3" 'references/fog-precision.md'; then pass "$name"
else fail "$name" "chart step 3 slice missing the fog-precision rule and/or its rationale pointer"; fi

# fog is worked mid-loop, not only at chart time and the graduate gates.
name=doc-mid-loop-fog-moves
missing=""
contains "$work_lc" 'mid-loop fog moves'          || missing="$missing header"
contains "$work_lc" 'exposes fresh unknowns'      || missing="$missing surface-new-tickets"
contains "$work_lc" 'not yet specified'           || missing="$missing graduate-fog"
contains "$work_lc" 're-scope'                    || missing="$missing rescope"
if [ -z "$missing" ]; then pass "$name"
else fail "$name" "work-flow slice missing the three mid-loop fog moves:$missing"; fi

name=doc-no-pre-slicing
if contains "$work_lc" 'no pre-slicing' && contains "$work_lc" 'before it is picked'; then pass "$name"
else fail "$name" "work-flow slice missing the no-pre-slicing rule"; fi

# a DEFAULT with a NAMED exception list — asserting the default alone would pass
# on a hard rule, which the WP explicitly does not ship (no machine check exists).
name=doc-one-ticket-per-session
missing=""
# the rule phrase in FULL — a bare 'one ticket' also matches the End-the-session
# handoff sentence ("only when ONE ticket's resolution is mid-flight"), which the
# mutation pass caught: the case survived deletion of the rule it guards.
contains "$work_lc" 'one ticket per session'      || missing="$missing rule"
contains "$work_lc" 'default'                     || missing="$missing stated-as-default"
contains "$work_lc" 'ticket_type: research'       || missing="$missing research-exception"
contains "$work_lc" 'trivially-coupled'           || missing="$missing coupled-exception"
contains "$work_lc" 'no machine check'            || missing="$missing no-machine-check"
if [ -z "$missing" ]; then pass "$name"
else fail "$name" "work-flow slice missing one-ticket-per-session as a DEFAULT + named exceptions:$missing"; fi

# The converged≠no-fog Gotcha must COMPOSE with the mid-loop moves. The negative
# grep is the load-bearing half: the superseded phrasing implied fog is handled
# only at chart time and the graduate gates, which now contradicts the work flow.
name=doc-converged-not-no-fog
gotchas="$(section '## Gotchas' '## Dependencies')"
gotchas_lc="$(lc "$gotchas")"
missing=""
contains "$gotchas_lc" 'is not "no fog left"'     || missing="$missing headline"
contains "$gotchas_lc" 'continuously'             || missing="$missing continuous-handling"
contains "$gotchas_lc" 'mid-loop fog moves'       || missing="$missing composes-with-moves"
contains "$gotchas_lc" 'last net'                 || missing="$missing gates-are-last-net"
if contains "$gotchas_lc" 'that is exactly why graduate is gated'; then
  missing="$missing SUPERSEDED-PHRASING-STILL-PRESENT"
fi
if [ -z "$missing" ]; then pass "$name"
else fail "$name" "Gotchas slice: converged-vs-fog not rewritten to compose with the mid-loop moves:$missing"; fi

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
# Family 4 — negative-control mutation pass (delegated to evals/mutate.sh)
# ============================================================================
# Each Family 2 case must FAIL when its rule is deleted from its slice. mutate.sh
# re-enters THIS script once per mutation with a gutted SKILL_MD copy, so the
# child runs are suppressed via WAYFIND_MUTATION_CHILD to avoid recursion. It is
# part of gate (1): a green run.sh means the prose cases are load-bearing.
if [ -z "${WAYFIND_MUTATION_CHILD:-}" ]; then
  name=mutation-negative-control
  set +e; bash "$EVALS_DIR/mutate.sh" > /dev/null 2>&1; RC=$?; set -e
  if [ "$RC" -eq 0 ]; then pass "$name"
  else fail "$name" "evals/mutate.sh reports undetected mutation(s) — re-run 'bash evals/mutate.sh' for the list (rc=$RC)"; fi
fi

# ============================================================================
# aggregate
# ============================================================================
if [ "$fail_count" -eq 0 ]; then
  printf '\nrun.sh: ALL PASS\n'
  exit 0
fi
printf '\nrun.sh: %d case(s) FAILED:%s\n' "$fail_count" "$failed_names" >&2
exit 1
