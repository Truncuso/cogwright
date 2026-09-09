#!/usr/bin/env bash
# goalforge-validate.test.sh — offline behavioral tests for the dependency
# readiness gates in goalforge-validate.sh (plus the matching frontier reading
# of the same fixture, so the two gates are asserted to agree).
#
# Drives the REAL goalforge-validate.sh / goalforge-frontier.sh over throwaway
# fixture trees (never the live plans root) and asserts on their ACTUAL emitted
# output — never on a restatement of their logic.
#
# Every "should be accepted" case asserts POSITIVELY (validator ran + reported
# zero errors + exited 0 under --strict). A bare grep for the ABSENCE of a
# diagnostic would also pass when the validator never ran at all, or when the
# diagnostic string is merely renamed — that is a tautological assertion.
#
# Cases:
#   ready-WP-with-archived-dep     A WP at `ready` whose depends_on target is at
#                                  `archived` must validate clean. `archived` is
#                                  the second WP terminal and is dep-satisfying
#                                  exactly as `verified`.
#   archived-dep-hardenable        The same fixture read through the frontier:
#                                  the `spec` WP depending on the `archived` WP
#                                  must appear in `hardenable[]`.
#   ready-WP-with-spec-dep         Negative control: the same WP with its dep at
#                                  `spec` MUST still raise the readiness ERROR
#                                  (the gate was widened, not removed).
#   task-dep-implemented-ok        Non-regression control on an UNCHANGED gate:
#                                  the TASK dep check keeps its own satisfied
#                                  set (READY_PLUS plus implemented/verified),
#                                  so a task at `in-progress` whose dep task is
#                                  `implemented` still validates clean. Green in
#                                  both trees by construction — it guards the
#                                  WP-level widening from leaking sideways, it
#                                  is not a red-before-green proof.
#   task-dep-pending-errors        Negative control for the TASK gate: a task at
#                                  `in-progress` whose dep task is `pending`
#                                  MUST still raise its task dep ERROR.
#
# wp-01 T10: the commit-gate exemption cases (commit-exempt-accepted,
# commit-missing-still-errors, commit-exempt-empty-errors,
# commit-exempt-with-hash-errors) are retired along with the validator's
# `commit_exempt:` leg — schema-6 has no per-task `commit:` field.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$SD/../goalforge-validate.sh"
FRONTIER="$SD/../goalforge-frontier.sh"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

mkfeature() { # $1=plans-root $2=feature
    mkdir -p "$1/$2"
    cat > "$1/$2/overview.md" <<EOF
---
name: $2
title: $2
status: active
created: 2026-08-03
feature: $2
work_packages: []
relationships: []
sources: []
---

# $2
EOF
}

mkwp() { # $1=plans-root $2=feature $3=wp-slug $4=status $5=depends_on-yaml
    mkdir -p "$1/$2/$3"
    cat > "$1/$2/$3/overview.md" <<EOF
---
name: $3
title: $3
status: $4
stage_updated: 2026-08-03
severity: LOW
parallel: false
depends_on: $5
plan: $2
relationships: []
sources: []
---

# $3
EOF
}

mktask() { # $1=plans-root $2=feature $3=wp-slug $4=task $5=status $6=deps $7=extra-body
    cat > "$1/$2/$3/$4.md" <<EOF
---
name: $4
title: $4
status: $5
depends_on: $6
---

# $4

${7:-}
EOF
}

# Positive assertion that a fixture validates clean.
#   --quiet ALWAYS prints its count-bearing summary line, so requiring that line
#     proves the validator actually RAN — an unlaunchable validator yields an
#     empty $OUT and this fails loudly instead of silently passing.
#   --strict is what makes an ERROR non-zero; plain runs exit 0 even with errors,
#     so an unqualified "exits 0" check would prove nothing.
#   (--quiet short-circuits to exit 0 before the strict gate, so the two flags
#    cannot be folded into one invocation — hence two runs.)
assert_clean() { # $1=label $2=plans-root
    local out rc
    out="$(bash "$VALIDATE" --quiet "$2" 2>&1)"
    if ! echo "$out" | grep -q 'goalforge-validate.*: 0 error(s)'; then
        bad "$1"
        echo "${out:-<no output — validator did not run>}" | sed 's/^/        /'
        bash "$VALIDATE" --show "$2" 2>&1 | grep '^ERROR' | sed 's/^/        /'
        return
    fi
    bash "$VALIDATE" --strict --show "$2" >/dev/null 2>&1; rc=$?
    if [ "$rc" -ne 0 ]; then
        bad "$1 (--strict exit $rc, expected 0)"
        return
    fi
    ok "$1"
}

# ── Fixture: a `ready` WP and a `spec` WP both depending on an `archived` WP ──
A="$ROOT/archived-dep"; mkfeature "$A" feat
mkwp "$A" feat wp-01-a archived "[]"
mkwp "$A" feat wp-02-b ready    "[wp-01-a]"
mkwp "$A" feat wp-03-c spec     "[wp-01-a]"

# ── Case: ready-WP-with-archived-dep ────────────────────────────────────────
assert_clean "ready-WP-with-archived-dep: validates clean (0 errors, --strict exit 0)" "$A"

# ── Case: archived-dep-hardenable ───────────────────────────────────────────
H="$(bash "$FRONTIER" "$A/feat" 2>/dev/null | jq -c '.hardenable' 2>/dev/null)"
if [ "$H" = '["wp-03-c"]' ]; then
    ok "archived-dep-hardenable: frontier lists wp-03-c as hardenable"
else
    bad "archived-dep-hardenable: frontier lists wp-03-c as hardenable (got hardenable=${H:-<none>})"
fi

# ── Case: ready-WP-with-spec-dep (negative control) ─────────────────────────
S="$ROOT/spec-dep"; mkfeature "$S" feat
mkwp "$S" feat wp-01-a spec  "[]"
mkwp "$S" feat wp-02-b ready "[wp-01-a]"
OUT="$(bash "$VALIDATE" --show "$S" 2>&1)"
if echo "$OUT" | grep -q 'depends_on: wp-01-a.*is `spec`'; then
    ok "ready-WP-with-spec-dep: readiness gate still fires"
else
    bad "ready-WP-with-spec-dep: readiness gate still fires"
fi

# ── Case: task-dep-implemented-ok ───────────────────────────────────────────
# `checkpoint:` in the body satisfies the unrelated executing-WP invariant, so
# the fixture is otherwise clean and the whole-tree assertion stays specific.
T="$ROOT/task-ok"; mkfeature "$T" feat
mkwp   "$T" feat wp-01-a executing "[]"
mktask "$T" feat wp-01-a task-01-first  implemented "[]" "checkpoint: 2026-08-03 fixture"
mktask "$T" feat wp-01-a task-02-second in-progress "[task-01-first]"
assert_clean "task-dep-implemented-ok: TASK gate unchanged, validates clean" "$T"

# ── Case: task-dep-pending-errors (negative control) ────────────────────────
P="$ROOT/task-bad"; mkfeature "$P" feat
mkwp   "$P" feat wp-01-a executing "[]"
mktask "$P" feat wp-01-a task-01-first  pending     "[]" "checkpoint: 2026-08-03 fixture"
mktask "$P" feat wp-01-a task-02-second in-progress "[task-01-first]"
OUT="$(bash "$VALIDATE" --show "$P" 2>&1)"
if echo "$OUT" | grep -q 'depends_on: task-01-first.*`pending`'; then
    ok "task-dep-pending-errors: TASK gate still fires"
else
    bad "task-dep-pending-errors: TASK gate still fires"
fi

# wp-01 T10: the commit-gate exemption fixtures (commit-exempt-accepted,
# commit-missing-still-errors, commit-exempt-empty-errors,
# commit-exempt-with-hash-errors) are retired along with goalforge-validate.sh's
# `commit_exempt:`/missing-`commit:` enforcement — schema-6 has no per-task
# `commit:` field to gate on (C1: no task-NN-*.md files).

# ── ticket-74 sabotage pair: schema_version:6 verification.command gate ─────
# known-bad: schema_version:6 WP with a goal: block but NO verification.command
# -> ERROR, --strict exit non-zero. known-good: same WP WITH verification.command
# -> --strict exit 0.
mkschema6wp() { # $1=plans-root $2=feature $3=wp-slug $4=command-line (or "") $5=check-line (default: legacy check: "true"; "" = none)
    mkdir -p "$1/$2/$3"
    local check_line="${5-    check: \"true\"}"
    cat > "$1/$2/$3/overview.md" <<EOF
---
name: $3
title: $3
status: hardened
stage_updated: 2026-08-03
severity: LOW
parallel: false
depends_on: []
plan: $2
schema_version: 6
task_type: code
goal:
  outcome: "the thing is done"
  verification:
    strategy: deterministic
$check_line
$4
  constraints: []
  boundaries: []
  iteration_policy: "retry until green"
  blocked_stop: "halt after 3 tries"
inherits_from: null
goal_approved_version: null
relationships: []
sources: []
---

# $3
EOF
}

# known-bad: no verification.command on a schema_version:6 WP
BAD6="$ROOT/schema6-missing-command"; mkfeature "$BAD6" feat
mkschema6wp "$BAD6" feat wp-01-a ""
OUT="$(bash "$VALIDATE" --strict --show "$BAD6" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && echo "$OUT" | grep -q 'goal.verification.command.*missing'; then
    ok "schema6-missing-command: known-bad -- ERROR + --strict exit non-zero"
else
    bad "schema6-missing-command: known-bad -- ERROR + --strict exit non-zero (rc=$RC)"
    echo "${OUT:-<no output>}" | sed 's/^/        /'
fi

# known-good: verification.command present on a schema_version:6 WP
GOOD6="$ROOT/schema6-with-command"; mkfeature "$GOOD6" feat
mkschema6wp "$GOOD6" feat wp-01-a "    command: \"true\""
assert_clean "schema6-with-command: known-good -- validates clean, --strict exit 0" "$GOOD6"

# known-good (C2): schema_version:6 WP with verification.command and NO legacy
# check: alias -- command is the check; must validate clean (found 2026-09-09
# decomposing goalforge-overhaul wp-02..05).
GOOD6NC="$ROOT/schema6-command-no-check"; mkfeature "$GOOD6NC" feat
mkschema6wp "$GOOD6NC" feat wp-01-a "    command: \"true\"" ""
assert_clean "schema6-command-no-check: known-good -- command without check: alias validates clean" "$GOOD6NC"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
