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
# Mutations run in parallel (bounded by WAYFIND_MUTATE_JOBS, default CPU count
# capped at 8), each in its own $WORK/<case-name>/ dir; results are reported in
# MUTATIONS order. A child that dies without a verdict counts as a failure.
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
  # learning goals: one marker per surface, each unique to the ONE line that
  # carries its rule, so the five mutants stay independent. `| task | learning`
  # hits only the chart step 2 enum (the dispatch row reads `| learning | HITL |`
  # and the candidate JSON has no spaces around its pipes), and `**default
  # none**` is bolded only in the Dispatch-step opt-in rule.
  'doc-learning-map-section|## Learning goals'
  'doc-learning-ticket-type-enum|| task | learning'
  'doc-learning-blind-spot-candidate|knowledge-gap signal'
  'doc-learning-dispatch-row|| learning | HITL |'
  'doc-learning-opt-in|**default none**'
  # graduated end state: each marker is unique to the ONE line its check reads —
  # the chart-flow yaml enum line, the close-chart edge-list line, and the
  # Discovery stdout enum literal.
  'doc-map-enum-graduated|status: charting | working | graduated'
  'doc-close-chart-graduated-edge|at chart completion; `working → graduated`'
  'doc-stdout-enum-no-graduated|"status": working|charting, "frontier"'
  'doc-auto-phase-graduated-terminal|`status: graduated` is terminal'
  'doc-graduate-step6-three-keys|6. **`wayfind/` stays in place**'
)

# One mutation, run in its own work dir so concurrent children never share a
# mutant path. Writes exactly one verdict file on completion; a child that dies
# before writing it is reported as a crash (never a pass) by the collector.
run_one() {
  local name="$1" marker="$2" dir="$WORK/$1"
  mkdir -p "$dir"

  # a marker that no longer exists makes the mutation vacuous (it would delete
  # nothing and the case would pass on an UNMUTATED file) — that is a failure.
  if ! grep -qF -- "$marker" "$SKILL_SRC"; then
    printf 'FAIL\tmarker not present in SKILL.md — mutation is vacuous: %s\n' "$marker" > "$dir/verdict"
    return 0
  fi

  grep -vF -- "$marker" "$SKILL_SRC" > "$dir/SKILL.md" || true

  local rc
  set +e
  WAYFIND_MUTATION_CHILD=1 SKILL_MD="$dir/SKILL.md" bash "$RUN_SH" > "$dir/out" 2>&1
  rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    printf 'FAIL\trun.sh still PASSED with the rule removed — the case is not load-bearing\n' > "$dir/verdict.tmp"
  elif ! grep -qF -- "FAIL [$name]" "$dir/out"; then
    printf 'FAIL\trun.sh failed (rc=%s) but NOT on [%s] — the mutation broke something else\n' "$rc" "$name" > "$dir/verdict.tmp"
  else
    printf 'ok\n' > "$dir/verdict.tmp"
  fi
  mv "$dir/verdict.tmp" "$dir/verdict"
}

# Bounded concurrency (CI budget: spec D4 keeps the eval-suites step under 60s).
# WAYFIND_MUTATE_JOBS overrides; default is the CPU count capped at 8.
jobs_max="${WAYFIND_MUTATE_JOBS:-}"
if [ -z "$jobs_max" ]; then
  jobs_max="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  [ "$jobs_max" -gt 8 ] && jobs_max=8
fi
case "$jobs_max" in
  ''|*[!0-9]*|0) printf 'mutate.sh: WAYFIND_MUTATE_JOBS must be a positive integer, got %s\n' "$jobs_max" >&2; exit 2 ;;
esac

running=0
for m in "${MUTATIONS[@]}"; do
  if [ "$running" -ge "$jobs_max" ]; then
    wait -n || true
    running=$((running - 1))
  fi
  run_one "${m%%|*}" "${m#*|}" &
  running=$((running + 1))
done
wait || true

# Collect in MUTATIONS order so the report is deterministic.
for m in "${MUTATIONS[@]}"; do
  name="${m%%|*}"
  verdict_file="$WORK/$name/verdict"
  if [ ! -f "$verdict_file" ]; then
    fail "$name" "mutation child crashed before writing a verdict"
    continue
  fi
  IFS=$'\t' read -r status msg < "$verdict_file" || true
  if [ "$status" = "ok" ]; then pass "$name"
  else fail "$name" "${msg:-malformed verdict}"; fi
done

if [ "$fail_count" -eq 0 ]; then
  printf '\nmutate.sh: ALL %d mutations detected\n' "${#MUTATIONS[@]}"
  exit 0
fi
printf '\nmutate.sh: %d mutation(s) UNDETECTED:%s\n' "$fail_count" "$failed_names" >&2
exit 1
