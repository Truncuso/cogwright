#!/usr/bin/env bash
# goalforge-evals-coverage.test.sh — evals/run.sh suite discovery (L0-4, D4).
#
# b7  every <child>/evals/run.sh, evals/<suite>/run.sh and evals/*.test.sh is
#     run by evals/run.sh or on its EXCLUDED list; strays are reported; an
#     EXCLUDED entry naming a missing file fails.
# b25 validate-plugins.yml carries the --suites-only step as a non-comment run:
#     line; a copy with it commented out fails naming the step.
# b27 --suites-only runs the discovered suites plus this test and skips the
#     scripts/tests and hooks/tests globs; a sabotaged copy that stops skipping
#     them fails the case; a failing stub suite makes the run exit non-zero.
#
# Never runs --suites-only on the real tree: that mode runs this test, so the
# call would recurse. Every run below is in a temp tree whose copy of this test
# is a stub. Hermetic: temp dirs under $TMPDIR, removed by the EXIT trap.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$HERE/../.." && pwd)"
REPO="$(cd "$PKG/../.." && pwd)"
RUNNER="$PKG/evals/run.sh"
WORKFLOW="$REPO/.github/workflows/validate-plugins.yml"
CI_STEP='run: bash packages/goalforge/evals/run.sh --suites-only'

WORK="$(mktemp -d "${TMPDIR:-/tmp}/goalforge-evals-coverage.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Suite paths a run reports on a PASS/FAIL line, sorted and unique.
reported_suites() {
  sed -nE 's/^  (PASS|FAIL): ([^ ]+(run\.sh|\.test\.sh))$/\2/p' "$1" | sort -u
}

stub() { # <path> <exit code>
  mkdir -p "$(dirname "$1")"
  printf '#!/usr/bin/env bash\necho "stub %s"\nexit %s\n' "$1" "$2" > "$1"
  chmod +x "$1"
}

# A fixture package: a copy of evals/run.sh plus stub suites for the three
# discovery globs, the two strays, the excluded file (a stub that would fail if
# run), one stub per gate-test glob, and the stub coverage test.
make_fixture() {
  local t="$1"
  mkdir -p "$t/evals"
  cp "${2:-$RUNNER}" "$t/evals/run.sh"
  stub "$t/alpha/evals/run.sh" 0
  stub "$t/beta/evals/run.sh" 0
  stub "$t/evals/sib/run.sh" 0
  stub "$t/evals/sel.test.sh" 0
  stub "$t/stray/evals/run.sh" 0
  stub "$t/evals/x.test.sh" 0
  stub "$t/evals/convert-canonical.test.sh" 1
  stub "$t/scripts/tests/x.test.sh" 0
  stub "$t/hooks/tests/y.test.sh" 0
  stub "$t/scripts/tests/goalforge-evals-coverage.test.sh" 0
}

FIXTURE_SUITES="alpha/evals/run.sh beta/evals/run.sh evals/sib/run.sh evals/sel.test.sh stray/evals/run.sh evals/x.test.sh scripts/tests/goalforge-evals-coverage.test.sh"

# 0 iff a --suites-only output names every fixture suite (strays included) and
# neither gate-test stub nor the excluded file.
suites_only_contract() {
  local out="$1" s got
  got="$(reported_suites "$out")"
  for s in $FIXTURE_SUITES; do
    grep -qxF "$s" <<<"$got" || { echo "missing $s"; return 1; }
  done
  for s in scripts/tests/x.test.sh hooks/tests/y.test.sh evals/convert-canonical.test.sh; do
    grep -qxF "$s" <<<"$got" && { echo "ran $s"; return 1; }
  done
  return 0
}

echo "=== goalforge-evals-coverage.test.sh ==="

# ── b27 + b7: --suites-only in the fixture tree ─────────────────────────────
F="$WORK/fixture"
make_fixture "$F"
bash "$F/evals/run.sh" --suites-only > "$WORK/fixture.out" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && why="$(suites_only_contract "$WORK/fixture.out")"; then
  pass "--suites-only runs every discovered suite (both strays included) and the coverage test, skips scripts/tests and hooks/tests and the excluded file"
else
  fail "--suites-only contract in the fixture tree (rc=$rc, ${why:-})"
  sed 's/^/        /' "$WORK/fixture.out"
fi

# Sabotage: a copy whose --suites-only also runs the gate-test globs.
S="$WORK/sabotage"
sed 's/^  run_discovered_suites   # suites-only$/  run_discovered_suites; run_gate_tests/' "$RUNNER" > "$WORK/run.sabotaged.sh"
if cmp -s "$RUNNER" "$WORK/run.sabotaged.sh"; then
  fail "known-bad: sabotage anchor '  run_discovered_suites   # suites-only' not found in evals/run.sh"
else
  make_fixture "$S" "$WORK/run.sabotaged.sh"
  bash "$S/evals/run.sh" --suites-only > "$WORK/sabotage.out" 2>&1
  if suites_only_contract "$WORK/sabotage.out" >/dev/null; then
    fail "known-bad: a --suites-only that runs the gate-test globs should fail the contract"
  else
    pass "known-bad: a --suites-only that runs the gate-test globs fails the contract"
  fi
fi

# A failing stub suite makes the run exit non-zero and names it.
R="$WORK/red"
make_fixture "$R"
stub "$R/gamma/evals/run.sh" 1
bash "$R/evals/run.sh" --suites-only > "$WORK/red.out" 2>&1
rc=$?
if [ "$rc" -ne 0 ] && grep -qxF '  FAIL: gamma/evals/run.sh' "$WORK/red.out"; then
  pass "a failing stub suite makes --suites-only exit non-zero naming gamma/evals/run.sh"
else
  fail "a failing stub suite should exit non-zero naming gamma/evals/run.sh (rc=$rc)"
  sed 's/^/        /' "$WORK/red.out"
fi

# ── b7: a stale EXCLUDED entry fails, naming the missing path ──────────────
X="$WORK/stale"
make_fixture "$X"
rm -f "$X/evals/convert-canonical.test.sh"
bash "$X/evals/run.sh" --suites-only > "$WORK/stale.out" 2>&1
rc=$?
if [ "$rc" -ne 0 ] && grep -q '^  FAIL: .*evals/convert-canonical.test.sh' "$WORK/stale.out"; then
  pass "an EXCLUDED entry naming a missing file fails, naming evals/convert-canonical.test.sh"
else
  fail "a stale EXCLUDED entry should fail naming evals/convert-canonical.test.sh (rc=$rc)"
  sed 's/^/        /' "$WORK/stale.out"
fi

# ── b7: real tree — reported suites equal an independent find enumeration ──
# The package is mirrored into a temp dir; every run.sh / *.test.sh in the
# mirror except evals/run.sh itself becomes a passing stub (this test included,
# which stops the recursion; the real suites' own results are the job of the
# real --suites-only run, not of this name comparison).
# Oracle: every run.sh / *.test.sh in the mirror, minus the known non-suite
# locations (scripts/tests, hooks/tests, any cases/ dir, evals/run.sh) and the
# EXCLUDED paths read from the mirrored evals/run.sh, plus this test.
mirror_names_match() { # <mirror dir> <tag>; 0 iff reported == enumeration
  local m="$1" tag="$2" rc
  find "$m" -type f \( -name run.sh -o -name '*.test.sh' \) ! -path "$m/evals/run.sh" -print0 \
    | while IFS= read -r -d '' f; do stub "$f" 0; done
  bash "$m/evals/run.sh" --suites-only > "$WORK/$tag.out" 2>&1
  rc=$?
  sed -n '/^EXCLUDED=(/,/^)/s/^ *"\([^|"]*\)|.*/\1/p' "$m/evals/run.sh" > "$WORK/$tag.excluded"
  ( cd "$m" && find . -type f \( -name run.sh -o -name '*.test.sh' \) ) \
    | sed 's|^\./||' \
    | grep -vE '^(scripts/tests|hooks/tests)/|(^|/)cases/|^evals/run\.sh$' \
    | grep -vxF -f "$WORK/$tag.excluded" \
    | { cat; echo scripts/tests/goalforge-evals-coverage.test.sh; } | sort -u > "$WORK/$tag.want"
  reported_suites "$WORK/$tag.out" > "$WORK/$tag.got"
  [ "$rc" -eq 0 ] && diff -u "$WORK/$tag.want" "$WORK/$tag.got" > "$WORK/$tag.diff"
}

M="$WORK/mirror"
cp -R "$PKG" "$M"
if mirror_names_match "$M" mirror; then
  pass "real-tree mirror: --suites-only reports exactly the find enumeration ($(wc -l < "$WORK/mirror.want") suites)"
else
  fail "real-tree mirror: reported suites differ from the find enumeration"
  sed 's/^/        /' "$WORK/mirror.diff"
fi

# Known-bad: a suite in a fourth shape that no discovery glob matches.
M4="$WORK/mirror4"
cp -R "$PKG" "$M4"
stub "$M4/wayfind/evals/frontier.test.sh" 0
if mirror_names_match "$M4" mirror4; then
  fail "known-bad: an undiscovered wayfind/evals/frontier.test.sh should fail the name comparison"
elif grep -qxF -- '-wayfind/evals/frontier.test.sh' "$WORK/mirror4.diff"; then
  pass "known-bad: an undiscovered wayfind/evals/frontier.test.sh fails the name comparison, naming it"
else
  fail "known-bad: name comparison failed without naming wayfind/evals/frontier.test.sh"
  sed 's/^/        /' "$WORK/mirror4.diff"
fi

# ── b25: the CI step is a non-comment run: line ────────────────────────────
ci_step_present() {
  grep -v '^[[:space:]]*#' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -qxF "$CI_STEP"
}
if ci_step_present "$WORKFLOW"; then
  pass "validate-plugins.yml runs '$CI_STEP'"
else
  fail "validate-plugins.yml is missing the step '$CI_STEP'"
fi
sed "s|^\([[:space:]]*\)$CI_STEP|\1# $CI_STEP|" "$WORKFLOW" > "$WORK/workflow.commented.yml"
if cmp -s "$WORKFLOW" "$WORK/workflow.commented.yml"; then
  fail "known-bad: could not comment out the step in a copy (step line absent)"
elif ci_step_present "$WORK/workflow.commented.yml"; then
  fail "known-bad: a copy with the step commented out should fail"
else
  pass "known-bad: a copy with the step commented out fails, missing '$CI_STEP'"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
