#!/usr/bin/env bash
#
# mutate.sh — negative control for run.sh's Family 2 (SKILL.md prose) cases.
#
# A Family 2 case is only load-bearing if it FAILS when its rule is removed from
# the slice it guards. A case that passes on a gutted SKILL.md certifies nothing.
# This harness is the executable form of that check: for each new prose rule it
# deletes the rule's marker line(s) from a TEMP copy of SKILL.md, re-runs run.sh
# against the copy via the `SKILL_MD` env override, and asserts that
#   (a) run.sh exits non-zero, and
#   (b) the FAILING case list names the case that owns that rule.
#
# (b) is the load-bearing half: without it a mutation that broke some unrelated
# case would read as a pass.
#
# Recursion guard: run.sh invokes this script at the end of a normal run, and
# this script invokes run.sh once per mutation. `WAYFIND_MUTATION_CHILD=1` is
# exported into every child run.sh, which then skips its mutate.sh call.
#
# Usage:  bash evals/mutate.sh          # exit 0 all mutations detected, 1 otherwise
#
# All paths resolve relative to THIS script (BASH_SOURCE), never cwd.

set -euo pipefail

src="${BASH_SOURCE[0]}"
while [ -h "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"; case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
EVALS_DIR="$(cd -P "$(dirname "$src")" && pwd)"
SKILL_DIR="$(cd -P "$EVALS_DIR/.." && pwd)"
RUN_SH="$EVALS_DIR/run.sh"
SKILL_SRC="${SKILL_MD:-$SKILL_DIR/SKILL.md}"

fail_count=0
failed_names=""
fail() { printf 'FAIL [mutate:%s]: %s\n' "$1" "$2" >&2; fail_count=$((fail_count + 1)); failed_names="${failed_names} $1"; }
pass() { printf 'ok   [mutate:%s]\n' "$1"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# One entry per NEW Family 2 case: <case-name>|<marker>. The marker is a
# fixed string; every SKILL.md line containing it is deleted from the copy.
# A mutation may collaterally break other cases — only the named one is asserted.
MUTATIONS=(
  'doc-plans-root-citation|§PLANS_ROOT resolution'
  'doc-work-loop-plans-root|wayfind-frontier.sh <PLANS_ROOT>/<effort-slug>'
  'doc-references-canonical-citation|idea/references/provenance-mapping.md'
  'doc-references-bare-string-lossy|LOSSILY'
  # the marker below is itself pipe-delimited; the split takes the FIRST `|`
  # only (`${m%%|*}` / `${m#*|}`), so the table row survives intact.
  'doc-map-notes-section|| ticket_type | machinery | model | effort |'
  'doc-ticket-resolution-notes|## Resolution notes'
  'doc-nn-width-cross-surface|at least two digits'
  'doc-claim-before-dispatch|MANDATORY before dispatch or resolve'
  'doc-end-session-validators|validate-linkage.sh'
  'doc-out-of-scope-split|never-ticketed'
  'doc-fog-precision|statable now but not answerable now'
  'doc-mid-loop-fog-moves|Mid-loop fog moves'
  'doc-no-pre-slicing|No pre-slicing'
  'doc-one-ticket-per-session|One ticket per session'
  'doc-converged-not-no-fog|is not "no fog left"'
  'doc-graduate-scope-discriminator|decision about future work'
  # ticket fan-out: one marker per surface. `# fan_out:` is unique to the chart
  # step 2 frontmatter comment line (the Dispatch note writes `fan_out: N`
  # inline, without the leading `# `), so the two mutants stay independent.
  'doc-ticket-fan-out-schema|# fan_out:'
  'doc-fan-out-dispatch-surface|references/ticket-fanout.md'
)

for m in "${MUTATIONS[@]}"; do
  name="${m%%|*}"
  marker="${m#*|}"

  # a marker that no longer exists makes the mutation vacuous (it would delete
  # nothing and the case would pass on an UNMUTATED file) — that is a failure.
  if ! grep -qF -- "$marker" "$SKILL_SRC"; then
    fail "$name" "marker not present in SKILL.md — mutation is vacuous: $marker"
    continue
  fi

  mutant="$WORK/SKILL.md"
  grep -vF -- "$marker" "$SKILL_SRC" > "$mutant" || true

  set +e
  out="$(WAYFIND_MUTATION_CHILD=1 SKILL_MD="$mutant" bash "$RUN_SH" 2>&1)"
  rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    fail "$name" "run.sh still PASSED with the rule removed — the case is not load-bearing"
  elif ! printf '%s' "$out" | grep -qF -- "FAIL [$name]"; then
    fail "$name" "run.sh failed (rc=$rc) but NOT on [$name] — the mutation broke something else"
  else
    pass "$name"
  fi
done

if [ "$fail_count" -eq 0 ]; then
  printf '\nmutate.sh: ALL %d mutations detected\n' "${#MUTATIONS[@]}"
  exit 0
fi
printf '\nmutate.sh: %d mutation(s) UNDETECTED:%s\n' "$fail_count" "$failed_names" >&2
exit 1
