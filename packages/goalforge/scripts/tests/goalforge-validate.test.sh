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
mkschema6wp() { # $1=plans-root $2=feature $3=wp-slug $4=command-line (or "") $5=check-line (default: legacy check: "true"; "" = none) $6=register-line (default: register: production; "" = none) $7=schema_version (default 6) $8=strategy (default deterministic)
    mkdir -p "$1/$2/$3"
    local check_line="${5-    check: \"true\"}"
    local register_line="${6-register: production}"
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
schema_version: ${7:-6}
$register_line
task_type: code
goal:
  outcome: "the thing is done"
  verification:
    strategy: ${8:-deterministic}
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

# ── L0-2 (b4): register is required at schema_version >= 6 ──────────────────
# The two fixtures differ only in schema_version; both omit register and keep
# the helper's default legacy `check:` string.
REG6="$ROOT/schema6-no-register"; mkfeature "$REG6" feat
mkschema6wp "$REG6" feat wp-01-a "    command: \"true\"" "    check: \"true\"" ""
OUT="$(bash "$VALIDATE" --strict --show "$REG6" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && echo "$OUT" | grep -qF '`register:` is required at schema_version >= 6 (spike|production)'; then
    ok "schema6-no-register: ERROR naming register + --strict exit non-zero"
else
    bad "schema6-no-register: ERROR naming register + --strict exit non-zero (rc=$RC)"
    echo "${OUT:-<no output>}" | sed 's/^/        /'
fi

REG5="$ROOT/schema5-no-register"; mkfeature "$REG5" feat
mkschema6wp "$REG5" feat wp-01-a "    command: \"true\"" "    check: \"true\"" "" 5
assert_clean "schema5-no-register: absent register = production below schema 6, --strict exit 0" "$REG5"

# A present schema_version that is not a clean integer counts as current: a
# missing register is the same ERROR (matches pick-agent _register_required).
for SVBAD in 5.9 true v6 "[6]"; do
    RB="$ROOT/schemabad-no-register-$(echo "$SVBAD" | tr -c 'a-z0-9' '_')"; mkfeature "$RB" feat
    mkschema6wp "$RB" feat wp-01-a "    command: \"true\"" "    check: \"true\"" "" "$SVBAD"
    OUT="$(bash "$VALIDATE" --strict --show "$RB" 2>&1)"; RC=$?
    if [ "$RC" -ne 0 ] && echo "$OUT" | grep -qF '`register:` is required at schema_version >= 6 (spike|production)'; then
        ok "schema_version ${SVBAD} (not a clean integer), no register: register ERROR + --strict exit non-zero"
    else
        bad "schema_version ${SVBAD} (not a clean integer), no register: register ERROR + --strict exit non-zero (rc=$RC)"
        echo "${OUT:-<no output>}" | sed 's/^/        /'
    fi
done

# A YAML-null schema_version stays legacy: absent register = production.
RNULL="$ROOT/schemanull-no-register"; mkfeature "$RNULL" feat
mkschema6wp "$RNULL" feat wp-01-a "    command: \"true\"" "    check: \"true\"" "" "null"
assert_clean "schema_version null, no register: legacy, --strict exit 0" "$RNULL"

# ── L0-12 (b16): judge goal shape = command + check {artifact, rubric, block_on}
JUDGE_CHECK='    check:
      artifact: "findings.md"
      rubric: "rubric.md"
      block_on: [HIGH]'

J1="$ROOT/schema6-judge-command-and-check"; mkfeature "$J1" feat
mkschema6wp "$J1" feat wp-01-a "    command: \"bash evals/judge.sh\"" "$JUDGE_CHECK" "register: production" 6 judge
assert_clean "schema6-judge-command-and-check: validates clean" "$J1"

J2="$ROOT/schema6-judge-command-only"; mkfeature "$J2" feat
mkschema6wp "$J2" feat wp-01-a "    command: \"bash evals/judge.sh\"" "" "register: production" 6 judge
OUT="$(bash "$VALIDATE" --strict --show "$J2" 2>&1)"; RC=$?
if [ "$RC" -ne 0 ] && echo "$OUT" | grep -qF '`judge` goal `check` must be a mapping'; then
    ok "schema6-judge-command-only: ERROR naming the judge check mapping + --strict exit non-zero"
else
    bad "schema6-judge-command-only: ERROR naming the judge check mapping + --strict exit non-zero (rc=$RC)"
    echo "${OUT:-<no output>}" | sed 's/^/        /'
fi

J3="$ROOT/schema5-judge-check-no-command"; mkfeature "$J3" feat
mkschema6wp "$J3" feat wp-01-a "" "$JUDGE_CHECK" "" 5 judge
assert_clean "schema5-judge-check-no-command: no new error at schema 5" "$J3"

# Judge mapping integrity: each malformed field raises its existing error.
judge_bad() { # $1=label $2=check-lines $3=expected error literal
    local d="$ROOT/judge-bad-$1"; mkfeature "$d" feat
    mkschema6wp "$d" feat wp-01-a "    command: \"bash evals/judge.sh\"" "$2" "register: production" 6 judge
    local out rc
    out="$(bash "$VALIDATE" --strict --show "$d" 2>&1)"; rc=$?
    if [ "$rc" -ne 0 ] && echo "$out" | grep -qF -- "$3"; then
        ok "schema6-judge-$1: ERROR + --strict exit non-zero"
    else
        bad "schema6-judge-$1: ERROR + --strict exit non-zero (rc=$rc)"
        echo "${out:-<no output>}" | sed 's/^/        /'
    fi
}
judge_bad block_on-string '    check:
      artifact: "findings.md"
      rubric: "rubric.md"
      block_on: HIGH' '`judge` goal `check.block_on` must be a non-empty list'
judge_bad block_on-empty '    check:
      artifact: "findings.md"
      rubric: "rubric.md"
      block_on: []' '`judge` goal `check.block_on` must be a non-empty list'
judge_bad rubric-empty '    check:
      artifact: "findings.md"
      rubric: ""
      block_on: [HIGH]' '`judge` goal `check.rubric` is empty'

# ── L0-12 (b16): schema.md and the WP template document the judge shape ─────
REFS="$SD/../../references"
SCHEMA_MD="$REFS/schema.md"
TEMPLATE_MD="$REFS/templates/wp-overview.md"
doc_absent() { # $1=label $2=fixed-string $3=file
    if [ -f "$3" ] && ! grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1"; fi
}
doc_present_re() { # $1=label $2=ERE $3=file
    if grep -qE -- "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1"; fi
}
doc_absent "schema.md judge row no longer says the rubric is named in the command" \
    "named in the command's own rubric" "$SCHEMA_MD"
doc_present_re "schema.md judge row names check {artifact, rubric, block_on} and the block_on rule" \
    '^\| `judge` \|.*`check`.*`artifact`.*`rubric`.*`block_on`.*at or above a `block_on` severity' "$SCHEMA_MD"
doc_absent "schema.md goal-block check comment is no longer only a schema-5 alias" \
    "<schema-5 alias of command — WARN-only baseline compat>" "$SCHEMA_MD"
doc_present_re "schema.md goal-block check comment names the judge mapping" \
    '^ +check: .*\{artifact, rubric, block_on\}' "$SCHEMA_MD"
doc_present_re "schema.md integrity list carries the judge-mapping bullet" \
    '^- `strategy: judge` needs a `check` mapping `\{artifact, rubric, block_on\}`' "$SCHEMA_MD"
doc_present_re "schema.md register field comment: absent = production below schema 6" \
    '^register: spike\|production +# absent = production below schema 6; ERROR at$' "$SCHEMA_MD"
doc_present_re "schema.md register gate note: absent is an ERROR at schema_version >= 6" \
    '^ +# absent is an ERROR at schema_version >= 6\.$' "$SCHEMA_MD"
doc_present_re "template carries a judge comment line with {artifact, rubric, block_on}" \
    '^ *#.*judge.*\{artifact, rubric, block_on\}' "$TEMPLATE_MD"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
