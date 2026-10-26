#!/usr/bin/env bash
# goalforge-goal-hash.test.sh — ticket-74 sabotage pair for goalforge-goal-hash.sh
# (T10 narrow hash, b4) plus the goal-changelog append it composes with.
#
# Drives the REAL goalforge-goal-hash.sh and goalforge-goal-changelog.sh over
# throwaway mktemp WP fixtures (never a live plans/ tree).
#
#   known-bad  : editing prose OUTSIDE outcome:/verification: (e.g. adding a
#                `## Decisions` body section, or editing constraints:) still
#                leaves the goal_approved_version stamp valid against the
#                recomputed hash -- i.e. a hash MISMATCH here would be the
#                defect this pair guards against. Modeled as: hash UNCHANGED
#                (exit 0, same value) -- asserting the wrong outcome (hash
#                CHANGED) is the "exit 2" failure this pair must catch.
#   known-good : editing goal.outcome DOES change the hash (exit 0, new value).
#
# Also covers b4's changelog half: a changelog row is appended on a goal edit
# via goalforge-goal-changelog.sh (append + idempotent no-op).
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HASH="$SD/../goalforge-goal-hash.sh"
CHANGELOG="$SD/../goalforge-goal-changelog.sh"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

mk_wp() { # $1=wp-dir $2=outcome $3=extra-prose-section (or "")
    mkdir -p "$1"
    cat > "$1/overview.md" <<EOF
---
name: $(basename "$1")
title: hash fixture
status: hardened
stage_updated: 2026-09-09
severity: LOW
parallel: false
depends_on: []
plan: tmpfeat
task_type: code
goal:
  outcome: "$2"
  verification:
    strategy: deterministic
    check: "true"
  constraints: []
  boundaries: []
  iteration_policy: "retry until green"
  blocked_stop: "halt after 3 tries"
inherits_from: null
goal_approved_version: null
---

# fixture
${3:-}
EOF
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ── known-bad guard: prose-only edits (outside outcome/verification) leave the
#    hash BYTE-IDENTICAL -- b4's core claim. We assert the CORRECT behavior
#    (unchanged) and separately prove the pair is non-vacuous by showing an
#    outcome edit DOES move the hash (known-good below). ──────────────────────
WP="$T/wp-01-b4"
mk_wp "$WP" "the thing is done" ""
H_BEFORE="$(bash "$HASH" "$WP")"

# Edit ONLY prose outside goal.outcome/goal.verification: add a `## Decisions`
# body section and mutate constraints:/blocked_stop: (non-hashed facets).
sed -i 's/constraints: \[\]/constraints: ["no regressions"]/' "$WP/overview.md"
sed -i 's/blocked_stop: "halt after 3 tries"/blocked_stop: "halt after 5 tries"/' "$WP/overview.md"
printf '\n## Decisions\n\nprose-only change outside the goal block.\n' >> "$WP/overview.md"
H_AFTER_PROSE="$(bash "$HASH" "$WP")"

if [[ "$H_AFTER_PROSE" == "$H_BEFORE" ]]; then
    ok "known-good: prose/constraints/blocked_stop edit leaves hash unchanged (b4)"
else
    bad "known-good: prose/constraints/blocked_stop edit leaves hash unchanged (b4) ($H_BEFORE vs $H_AFTER_PROSE)"
fi

# ── known-bad (sabotage): editing goal.outcome MUST change the hash. A hash
#    implementation that failed to narrow correctly (or a regression that
#    hashed the whole file) would falsely report this as unchanged -- that
#    wrong outcome is what this case would catch. ─────────────────────────────
sed -i 's/outcome: "the thing is done"/outcome: "the thing is DONE differently"/' "$WP/overview.md"
H_AFTER_OUTCOME="$(bash "$HASH" "$WP")"
if [[ "$H_AFTER_OUTCOME" != "$H_BEFORE" ]]; then
    ok "known-good: editing goal.outcome changes the hash"
else
    bad "known-good: editing goal.outcome changes the hash (defect: hash did not move)"
fi

# ── known-bad exit check: a WP with no goal: block exits 3 (not 0) ───────────
NOGOAL="$T/wp-01-nogoal"
mkdir -p "$NOGOAL"
cat > "$NOGOAL/overview.md" <<'EOF'
---
name: wp-01-nogoal
title: no goal block
status: hardened
stage_updated: 2026-09-09
plan: tmpfeat
---

# no goal block
EOF
bash "$HASH" "$NOGOAL" >/dev/null 2>/tmp/gh-nogoal.err
RC=$?
if [[ "$RC" -eq 3 ]]; then
    ok "known-bad: no goal: block -> exit 3 (fail-closed, not silent 0)"
else
    bad "known-bad: no goal: block -> exit 3 (fail-closed, not silent 0) (rc=$RC)"
fi

# ── changelog half of b4: a goal edit is followed by an appended changelog row
#    (via the composing goalforge-goal-changelog.sh append), idempotent re-append ──
CL="$T/wp-01-cl"
mk_wp "$CL" "the changelog thing is done" ""
cat >> "$CL/overview.md" <<'EOF'

## Goal Changelog

<!-- Append-only. Each row: - v<N> <date> facet=<facet> <old>→<new>; reason: <text> -->
EOF
OUT="$(bash "$CHANGELOG" append "$CL" outcome "the changelog thing is done" "the changelog thing is REALLY done" --reason "b4 fixture edit")"
if echo "$OUT" | grep -q '^append: v1 facet=outcome' && grep -Eq '^- v1 .* facet=outcome' "$CL/overview.md"; then
    ok "known-good: changelog row appended on goal edit (v1)"
else
    bad "known-good: changelog row appended on goal edit (v1) (out=$OUT)"
fi

# re-appending the identical change is a no-op (no v2 row) -- guards against a
# duplicate-row regression that would spend the changelog's own budget.
OUT2="$(bash "$CHANGELOG" append "$CL" outcome "the changelog thing is done" "the changelog thing is REALLY done" --reason "again")"
N2="$(grep -Ec '^- v2 ' "$CL/overview.md" || true)"
if echo "$OUT2" | grep -q '^noop:' && [[ "$N2" -eq 0 ]]; then
    ok "known-bad guard: identical re-append is idempotent (no v2 row, no duplicate)"
else
    bad "known-bad guard: identical re-append is idempotent (no v2 row, no duplicate) (out=$OUT2, v2-rows=$N2)"
fi

echo
echo "goalforge-goal-hash.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
