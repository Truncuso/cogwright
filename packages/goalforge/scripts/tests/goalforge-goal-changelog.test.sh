#!/usr/bin/env bash
# goalforge-goal-changelog.test.sh — sabotage pair for goalforge-goal-changelog.sh
# (G4 changelog append, gateC finding b3: "b3 gap: a retained G4 gate script has
# no sabotage pair and is not exercised by evals/run.sh").
#
# Drives the REAL goalforge-goal-changelog.sh over a throwaway COPY of the
# evals/fixtures/goal-changelog/ WP fixture (never mutates the fixture itself,
# never a live plans/ tree).
#
#   known-good : append with a valid facet exits 0 and appends exactly one row.
#   known-bad  : append with an invalid facet exits non-zero and writes nothing
#                (fixture copy byte-identical before/after).
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHANGELOG="$SD/../goalforge-goal-changelog.sh"
FIXTURE="$SD/../../evals/fixtures/goal-changelog/wp-01-fixture"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ── known-good: a valid-facet append exits 0 and appends exactly one row ────
WP="$T/wp-01-good"
cp -r "$FIXTURE" "$WP"

OUT="$(bash "$CHANGELOG" append "$WP" outcome "old outcome" "new outcome" --reason "known-good fixture append")"
RC=$?
N_ROWS="$(grep -Ec '^- v[0-9]+ ' "$WP/overview.md" || true)"
if [[ "$RC" -eq 0 ]] && echo "$OUT" | grep -q '^append: v1 facet=outcome' \
   && [[ "$N_ROWS" -eq 1 ]] \
   && grep -Eq '^- v1 [0-9]{4}-[0-9]{2}-[0-9]{2} facet=outcome old outcome→new outcome; reason: known-good fixture append$' "$WP/overview.md"; then
    ok "known-good: valid-facet append exits 0 and appends exactly one row"
else
    bad "known-good: valid-facet append exits 0 and appends exactly one row (rc=$RC, rows=$N_ROWS, out=$OUT)"
fi

# ── known-bad: an invalid facet exits non-zero and writes nothing ──────────
WP2="$T/wp-01-bad"
cp -r "$FIXTURE" "$WP2"
BEFORE_SHA="$(sha256sum "$WP2/overview.md" | awk '{print $1}')"

bash "$CHANGELOG" append "$WP2" not-a-real-facet "old" "new" --reason "should never write" >/tmp/gcl-bad.out 2>&1
RC2=$?
AFTER_SHA="$(sha256sum "$WP2/overview.md" | awk '{print $1}')"
if [[ "$RC2" -ne 0 ]] && [[ "$BEFORE_SHA" == "$AFTER_SHA" ]] && grep -q "invalid facet" /tmp/gcl-bad.out; then
    ok "known-bad: invalid facet exits non-zero and writes nothing (byte-identical file)"
else
    bad "known-bad: invalid facet exits non-zero and writes nothing (rc=$RC2, before=$BEFORE_SHA, after=$AFTER_SHA)"
fi
rm -f /tmp/gcl-bad.out

# ── fixture itself is untouched by either run (both were copies) ───────────
if [[ -f "$FIXTURE/overview.md" ]] && ! grep -q '^- v1 ' "$FIXTURE/overview.md"; then
    ok "source fixture untouched (append operated on a temp copy)"
else
    bad "source fixture untouched (append operated on a temp copy)"
fi

echo
echo "goalforge-goal-changelog.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
