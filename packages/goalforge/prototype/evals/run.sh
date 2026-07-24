#!/usr/bin/env bash
#
# run.sh — deterministic structure harness for the prototype skill (wp-05).
#
# Verifies the POST-SWEEP structure: a thin SKILL.md that carries the hard-gate
# contract + close-out (retention) wiring and LINKS three branch reference
# files, whose per-branch discipline now lives in references/{LOGIC,UI,PERF}.md.
#
# Families of named cases (ok / FAIL), aggregate exit:
#   1. references/{LOGIC,UI,PERF}.md exist AND are linked from SKILL.md.
#   2. SKILL.md hard-gate contract (one question, success criteria, declared
#      spike register, prototype/-only never-commit carve-out, keep-answer/
#      delete-code, branch selector, execution modes + explicit dispatch,
#      independent verification, findings-as-data, gotchas).
#   3. SKILL.md close-out wiring: goalforge-prototype-retain.sh + prototype_path
#      + retention + Run Log.
#   4. Branch-reference discipline: the checks for content that MOVED off
#      SKILL.md into its reference file (logic: pure module + terminal harness +
#      one command; ui: structurally-different variants + variant switcher;
#      perf: correctness gate + scaling curve + median + worth-it verdict).
#   5. PERF.md baseline-reference terms: baseline / cost function /
#      optimization target / algorithm comparison.
#   6. A mutation negative-control: a temp copy of SKILL.md with one required
#      contract line removed must make this harness FAIL — paired with a
#      positive-control (unmutated copy, same REF_DIR) that must PASS, so the
#      removed line is provably the only variable.
#
# Offline-reproducible: grep/test over files only — NEVER executes the live
# retention script against the real repo.
#
# Testability: SKILL_MD env var overrides the SKILL.md path; REF_DIR overrides
# the references/ dir (defaults to SKILL_MD's dirname + /references) — both used
# by the negative-control, which points SKILL_MD at a mutated copy while keeping
# REF_DIR on the real references so only the mutation can cause the failure.
# PROTOTYPE_EVAL_NEG guards the self-invoke so the child does not recurse.
#
# Exit codes:
#   0  every case passed
#   1  one or more cases failed (each failing case name is printed)
#
set -u

# --- resolve paths relative to THIS script, following symlinks ---------------
src="${BASH_SOURCE[0]}"
while [ -h "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"; case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
EVALS_DIR="$(cd -P "$(dirname "$src")" && pwd)"
SKILL_DIR="$(cd -P "$EVALS_DIR/.." && pwd)"

SKILL_MD="${SKILL_MD:-$SKILL_DIR/SKILL.md}"
REF_DIR="${REF_DIR:-$(cd -P "$(dirname "$SKILL_MD")" && pwd)/references}"
LOGIC_MD="$REF_DIR/LOGIC.md"
UI_MD="$REF_DIR/UI.md"
PERF_MD="$REF_DIR/PERF.md"

# --- case-runner scaffolding (style donor: wayfind/evals/run.sh) -------------
fail_count=0
failed_names=""
fail() { printf 'FAIL [%s]: %s\n' "$1" "$2" >&2; fail_count=$((fail_count + 1)); failed_names="${failed_names} $1"; }
pass() { printf 'ok   [%s]\n' "$1"; }

# check <name> <file> <case-insensitive-ERE>: PASS iff file exists and matches.
check() {
  if [ -f "$2" ] && grep -qiE -- "$3" "$2"; then
    pass "$1"
  else
    fail "$1" "$2 does not match /$3/"
  fi
}

# ============================================================================
# Family 1 — the three branch reference files exist AND are linked from SKILL.md
# ============================================================================
name=ref-logic-exists;  [ -f "$LOGIC_MD" ] && pass "$name" || fail "$name" "missing $LOGIC_MD"
name=ref-ui-exists;     [ -f "$UI_MD" ]    && pass "$name" || fail "$name" "missing $UI_MD"
name=ref-perf-exists;   [ -f "$PERF_MD" ]  && pass "$name" || fail "$name" "missing $PERF_MD"

check "ref-logic-linked" "$SKILL_MD" "LOGIC\.md"
check "ref-ui-linked"    "$SKILL_MD" "UI\.md"
check "ref-perf-linked"  "$SKILL_MD" "PERF\.md"

# ============================================================================
# Family 2 — SKILL.md hard-gate contract
# ============================================================================
check "frontmatter name"           "$SKILL_MD" "^name: prototype$"
check "hard-gates section"         "$SKILL_MD" "Contract \(hard gates\)"
check "one-question gate"          "$SKILL_MD" "One question"
check "success-criteria gate"      "$SKILL_MD" "Success criteria required"
check "declared spike register"    "$SKILL_MD" "Principle 2"
check "prototype-only carve-out"   "$SKILL_MD" "commits only under"
check "keep-answer-delete-code"    "$SKILL_MD" "delete the code"
check "worktree isolation"         "$SKILL_MD" "worktree"
check "findings-as-data boundary"  "$SKILL_MD" "typed data"
check "execution modes section"    "$SKILL_MD" "^## Execution modes"
check "explicit model+effort"      "$SKILL_MD" "Dispatch Routing Matrix"
check "independent verification"   "$SKILL_MD" "did not build"
check "absorb-through-review path" "$SKILL_MD" "production register"
check "gotchas section"            "$SKILL_MD" "^## Gotchas"

# ============================================================================
# Family 3 — SKILL.md close-out (retention) wiring
# ============================================================================
check "close-out retain script"    "$SKILL_MD" "goalforge-prototype-retain\.sh"
check "close-out prototype_path"    "$SKILL_MD" "prototype_path"
check "close-out retention tier"    "$SKILL_MD" "retention"
check "close-out run log"           "$SKILL_MD" "Run Log"

# ============================================================================
# Family 4 — branch-reference discipline (content that MOVED off SKILL.md)
# ============================================================================
check "logic: pure module"         "$LOGIC_MD" "pure module|pure logic module"
check "logic: terminal harness"    "$LOGIC_MD" "terminal harness"
check "logic: one command to run"  "$LOGIC_MD" "One command to run"

check "ui: structurally different" "$UI_MD"    "structurally different"
check "ui: variant switcher"       "$UI_MD"    "variant="

check "perf: correctness gate"     "$PERF_MD"  "correctness gate"
check "perf: scaling curve"        "$PERF_MD"  "scaling curve"
check "perf: median + spread"      "$PERF_MD"  "median"
check "perf: worth-it verdict"     "$PERF_MD"  "worth-it verdict"

# ============================================================================
# Family 5 — PERF.md baseline-reference terms
# ============================================================================
check "perf: baseline"             "$PERF_MD"  "baseline"
check "perf: cost function"        "$PERF_MD"  "cost function"
check "perf: optimization target"  "$PERF_MD"  "optimization target"
check "perf: algorithm comparison" "$PERF_MD"  "algorithm comparison"

# ============================================================================
# Family 6 — mutation negative-control (self-invoke; guarded against recursion)
# A green Family 2 can be defeated by a harness that never actually fails. This
# copies SKILL.md, strips ONE required contract line ("Success criteria
# required"), and re-invokes THIS harness pointed at the copy (REF_DIR kept on
# the real references so the reference families still pass). Paired with a
# positive-control over an UNMUTATED copy under the same REF_DIR — the positive
# must exit 0 and the negative must exit non-zero, so the removed line is
# provably the only variable that flips the result.
# ============================================================================
if [ -z "${PROTOTYPE_EVAL_NEG:-}" ]; then
  TMPD="$(mktemp -d)"
  trap 'rm -rf "$TMPD"' EXIT

  # positive control: verbatim copy must still pass under the same REF_DIR.
  cp "$SKILL_MD" "$TMPD/skill-ok.md"
  name=neg-control-positive
  PROTOTYPE_EVAL_NEG=1 SKILL_MD="$TMPD/skill-ok.md" REF_DIR="$REF_DIR" bash "$src" >/dev/null 2>&1
  pos_rc=$?
  [ "$pos_rc" -eq 0 ] && pass "$name" \
    || fail "$name" "unmutated copy failed (rc=$pos_rc) — control invalid, mutation not isolated"

  # negative control: same copy minus one required contract line must FAIL.
  grep -v "Success criteria required" "$SKILL_MD" > "$TMPD/skill-mutated.md"
  name=neg-control-mutation
  PROTOTYPE_EVAL_NEG=1 SKILL_MD="$TMPD/skill-mutated.md" REF_DIR="$REF_DIR" bash "$src" >/dev/null 2>&1
  neg_rc=$?
  [ "$neg_rc" -ne 0 ] && pass "$name" \
    || fail "$name" "SKILL.md missing 'Success criteria required' still passed — check cannot fail"
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
