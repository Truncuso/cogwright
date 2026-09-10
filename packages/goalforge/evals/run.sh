#!/usr/bin/env bash
# Eval harness for the goalforge package — the single entrypoint (ticket-23).
# Asserts the spec.md goal.verification.behaviors (b1-b8) plus the surviving
# structural checks on the package's own SKILL.md files. Exit 0 = all pass.

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
PASS=0
FAIL=0

check() {
  local desc="$1"
  local result="$2"
  if [ "$result" = "pass" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== goalforge package eval harness ==="
echo ""

# ── b4: fixture immutability manifest (taken first, compared last) ──────────
# No test may write into the checked-in evals/fixtures/ tree; the lint tests
# emit gate.result rows and must copy their fixtures to a temp dir first.
FIXTURE_DIR="$SKILL_DIR/evals/fixtures"
FIXTURE_MANIFEST_BEFORE="$(mktemp)"
fixture_manifest() {
  ( cd "$FIXTURE_DIR" 2>/dev/null && find . -type f | sort | xargs -r sha256sum ) 2>/dev/null
}
fixture_manifest > "$FIXTURE_MANIFEST_BEFORE"

# ── Trigger tests ────────────────────────────────────────────────────────────
echo "[ Trigger tests ]"

grep -q "explain SDD" "$SKILL_MD" \
  && check "description includes 'explain SDD' trigger" "pass" \
  || check "description includes 'explain SDD' trigger" "fail"

# Anti-trigger for chain execution — phrasing has drifted from the original
# "Do NOT" pin (SKILL.md now reads "Not for RUNNING the chain"); either form
# satisfies the intent this check guards.
grep -Eq 'Do NOT|Not for RUNNING' "$SKILL_MD" \
  && check "description includes anti-trigger for chain execution" "pass" \
  || check "description includes anti-trigger for chain execution" "fail"

grep -q "^name: goalforge$" "$SKILL_MD" \
  && check "name field is 'goalforge'" "pass" \
  || check "name field is 'goalforge'" "fail"

echo ""

# ── Functional tests ─────────────────────────────────────────────────────────
echo "[ Functional tests ]"

ALIAS_MAP="$SKILL_DIR/references/alias-map.md"
STEPS="sdd-capture sdd-spec sdd-decompose sdd-harden sdd-execute sdd-verify"

STEPS_OK="pass"
for step in $STEPS; do
  grep -q "$step" "$SKILL_MD" "$ALIAS_MAP" 2>/dev/null || STEPS_OK="fail"
done
check "all 6 chain step names covered by redirect stub/alias-map" "$STEPS_OK"

MAP_OK="pass"
for step in $STEPS; do
  new="goalforge-${step#sdd-}"
  grep -q "$new" "$SKILL_MD" "$ALIAS_MAP" 2>/dev/null || MAP_OK="fail"
done
check "alias map carries goalforge-* targets for all 6 steps" "$MAP_OK"

grep -Eq 'LOCAL authority|authoritative' "$SKILL_MD" \
  && check "SKILL.md states local authority" "pass" \
  || check "SKILL.md states local authority" "fail"

grep -q "references/schema.md" "$SKILL_MD" \
  && check "references/schema.md mentioned" "pass" \
  || check "references/schema.md mentioned" "fail"

SHIM_OK="pass"
for shim in "$SKILL_DIR"/scripts/goalforge-*.sh; do
  [ -x "$shim" ] || SHIM_OK="fail"
done
check "all goalforge-*.sh scripts are executable" "$SHIM_OK"

REFS_OK="pass"
for ref in \
  "$SKILL_DIR/references/schema.md" \
  "$SKILL_DIR/references/templates" \
  "$SKILL_DIR/references/dispatch.yaml" \
  "$SKILL_DIR/references/expertise-map.yaml" \
  "$SKILL_DIR/scripts/goalforge-validate.sh" \
  "$SKILL_DIR/scripts/goalforge-goal-eval.py" \
  "$SKILL_DIR/scripts/goalforge-pick-agent.py"
do
  [ -e "$ref" ] || REFS_OK="fail"
done
check "all referenced bundled files exist on disk" "$REFS_OK"

# retired skill-measure hook must be ABSENT (measurement is global via
# skill-usage.sh + ledger/events streams)
grep -q "skill-measure.sh" "$SKILL_MD" \
  && check "retired skill-measure hook absent" "fail" \
  || check "retired skill-measure hook absent" "pass"

if python3 "$SKILL_DIR/scripts/goalforge-pick-agent.py" --test-tiers >/dev/null 2>&1; then
  check "role→tier map invariants pass (goalforge-pick-agent --test-tiers)" "pass"
else
  check "role→tier map invariants pass (goalforge-pick-agent --test-tiers)" "fail"
fi

if bash "$SKILL_DIR/scripts/goalforge-preharden-lint.sh" --self-test >/dev/null 2>&1; then
  check "preharden-lint self-test passes (scripts/goalforge-preharden-lint.sh)" "pass"
else
  check "preharden-lint self-test passes (scripts/goalforge-preharden-lint.sh)" "fail"
fi

echo ""

# ── Fidelity ladder tests ────────────────────────────────────────────────────
echo "[ Fidelity ladder tests ]"

FIDELITY_MD="$SKILL_DIR/references/fidelity.md"

[ -f "$FIDELITY_MD" ] \
  && check "references/fidelity.md exists" "pass" \
  || check "references/fidelity.md exists" "fail"

if [ -f "$FIDELITY_MD" ] \
  && grep -qE '^1\. \*\*Discussion' "$FIDELITY_MD" \
  && grep -qE '^2\. \*\*Interview' "$FIDELITY_MD" \
  && grep -qE '^3\. \*\*Prototype' "$FIDELITY_MD"; then
  check "fidelity.md names all three rungs (discussion/interview/prototype)" "pass"
else
  check "fidelity.md names all three rungs (discussion/interview/prototype)" "fail"
fi

{ [ -f "$FIDELITY_MD" ] && grep -qE '^## Trigger' "$FIDELITY_MD"; } \
  && check "fidelity.md carries a ## Trigger section" "pass" \
  || check "fidelity.md carries a ## Trigger section" "fail"

# Only capture/spec still link the ladder in prose; the slimmed
# decompose/harden/execute/verify skills route gates through code (C3), not a
# fidelity-ladder cross-reference — checking them here would pin a shape wp-01
# deliberately removed.
for STAGE in capture spec; do
  grep -q "fidelity.md" "$SKILL_DIR/$STAGE/SKILL.md" \
    && check "$STAGE/SKILL.md links references/fidelity.md" "pass" \
    || check "$STAGE/SKILL.md links references/fidelity.md" "fail"
done

[ "$(grep -c 'fidelity.md' "$SKILL_DIR/spec/SKILL.md" || true)" -ge 2 ] \
  && check "spec/SKILL.md carries both fidelity hooks (>=2 links)" "pass" \
  || check "spec/SKILL.md carries both fidelity hooks (>=2 links)" "fail"

echo ""

# ── wp-07 conformance tests ─────────────────────────────────────────────────
# Re-asserts the facts wp-07 establishes (tasks 01-03) so they survive later WPs.
echo "[ wp-07 conformance tests ]"

WAYFIND_MD="$SKILL_DIR/wayfind/SKILL.md"

[ -f "$WAYFIND_MD" ] \
  && check "wayfind/SKILL.md exists" "pass" \
  || check "wayfind/SKILL.md exists" "fail"

SKILL_KIND_COUNT="$(grep -lE '^  skill-kind: (capability|preference)$' "$SKILL_DIR"/*/SKILL.md 2>/dev/null | wc -l || true)"
[ "$SKILL_KIND_COUNT" -eq 13 ] \
  && check "all 13 child SKILL.md files declare metadata.skill-kind" "pass" \
  || check "all 13 child SKILL.md files declare metadata.skill-kind (got $SKILL_KIND_COUNT)" "fail"

{ [ -f "$WAYFIND_MD" ] && grep -q '^metadata:$' "$WAYFIND_MD" \
    && grep -qE '^  version: [0-9]+\.[0-9]+\.[0-9]+$' "$WAYFIND_MD"; } \
  && check "wayfind/SKILL.md has metadata: with nested semver version:" "pass" \
  || check "wayfind/SKILL.md has metadata: with nested semver version:" "fail"

{ [ -f "$WAYFIND_MD" ] && grep -q '^## Gotchas$' "$WAYFIND_MD"; } \
  && check "wayfind/SKILL.md has a ## Gotchas section" "pass" \
  || check "wayfind/SKILL.md has a ## Gotchas section" "fail"

# Co-tenancy note names both non-chain tenants (wording drifted from the
# original "Note: ..." pin to a plain sentence — match the surviving phrase).
grep -qF '`prototype/` and `wayfind/` are non-chain tenants' "$SKILL_MD" \
  && check "parent SKILL.md co-tenancy note names prototype/ and wayfind/" "pass" \
  || check "parent SKILL.md co-tenancy note names prototype/ and wayfind/" "fail"

# NEGATIVE -- non-chain tenants must NOT appear as Children-table rows
grep -qE '^\| *`?(prototype|wayfind)`? *\|' "$SKILL_MD" \
  && check "parent SKILL.md Children table has no prototype/wayfind row" "fail" \
  || check "parent SKILL.md Children table has no prototype/wayfind row" "pass"

CHILD_ROW_COUNT="$(grep -c '^| `goalforge-' "$SKILL_MD" || true)"
[ "$CHILD_ROW_COUNT" -eq 11 ] \
  && check "parent SKILL.md Children table has exactly 11 chain-stage rows" "pass" \
  || check "parent SKILL.md Children table has exactly 11 chain-stage rows (got $CHILD_ROW_COUNT)" "fail"

echo ""

# ── b5: core stage SKILL.md size budget ─────────────────────────────────────
echo "[ b5: SKILL.md line budgets ]"

for STAGE in decompose harden execute verify; do
  LC="$(wc -l < "$SKILL_DIR/$STAGE/SKILL.md" 2>/dev/null || echo 999999)"
  [ "$LC" -le 120 ] \
    && check "$STAGE/SKILL.md <= 120 lines (got $LC)" "pass" \
    || check "$STAGE/SKILL.md <= 120 lines (got $LC)" "fail"
done

# b5: name: equals the directory basename (ticket-79 option 1) for the three
# stage children wp-02 renames. wp-04 lands the remainder.
for STAGE in harden verify capture; do
  if grep -q "^name: ${STAGE}$" "$SKILL_DIR/$STAGE/SKILL.md" 2>/dev/null; then
    check "$STAGE/SKILL.md name: == directory basename" "pass"
  else
    check "$STAGE/SKILL.md name: == directory basename (got $(grep -m1 '^name:' "$SKILL_DIR/$STAGE/SKILL.md" 2>/dev/null))" "fail"
  fi
done

# b5: C6 retired the feature todo.md rollup — capture may not cite it anywhere,
# frontmatter description included.
TODO_HITS="$(grep -c 'todo\.md' "$SKILL_DIR/capture/SKILL.md" 2>/dev/null || true)"
[ "${TODO_HITS:-1}" -eq 0 ] \
  && check "capture/SKILL.md carries zero todo.md citations" "pass" \
  || check "capture/SKILL.md carries zero todo.md citations (got $TODO_HITS)" "fail"

echo ""

# ── stage child eval suites (decompose/harden/execute/verify/run) ──────────
# Each rewritten stage skill (wp-01-slim-core) owns its own C1-C7 contract
# checks; a red child suite must turn this top-level harness red too.
echo "[ stage child eval suites ]"

for stage in capture decompose harden execute verify run; do
  f="$SKILL_DIR/$stage/evals/run.sh"
  [ -f "$f" ] || continue
  if bash "$f" >/tmp/goalforge-run-sh-$$.out 2>&1; then
    check "$stage/evals/run.sh" "pass"
  else
    check "$stage/evals/run.sh" "fail"
    sed 's/^/        /' "/tmp/goalforge-run-sh-$$.out"
  fi
  rm -f "/tmp/goalforge-run-sh-$$.out"
done

echo ""

# ── sibling eval suites (wave-route, schema-v5, selection) ─────────────────
# Owned evals/ suites that sit beside the stage children above, not inside
# them — same "a red child must redden this harness" contract (wp-01 round 2,
# gate B/C new findings).
echo "[ sibling eval suites (wave-route, schema-v5, selection) ]"

for f in "$SKILL_DIR/evals/wave-route/run.sh" "$SKILL_DIR/evals/schema-v5/run.sh" "$SKILL_DIR/evals/selection.test.sh"; do
  [ -f "$f" ] || continue
  label="evals/$(basename "$(dirname "$f")")/$(basename "$f")"
  [ "$(basename "$f")" = "selection.test.sh" ] && label="evals/selection.test.sh"
  if bash "$f" >/tmp/goalforge-run-sh-$$.out 2>&1; then
    check "$label" "pass"
  else
    check "$label" "fail"
    sed 's/^/        /' "/tmp/goalforge-run-sh-$$.out"
  fi
  rm -f "/tmp/goalforge-run-sh-$$.out"
done

echo ""

# ── b3: every gate sabotage-test pair exits clean (discovered by glob) ──────
echo "[ b3: gate sabotage-test pairs (hooks/tests, scripts/tests) ]"

run_test_file() {
  local f="$1" label="$2"
  if bash "$f" >/tmp/goalforge-run-sh-$$.out 2>&1; then
    check "$label" "pass"
  else
    check "$label" "fail"
    sed 's/^/        /' "/tmp/goalforge-run-sh-$$.out"
  fi
  rm -f "/tmp/goalforge-run-sh-$$.out"
}

for f in "$SKILL_DIR"/hooks/tests/*.test.sh "$SKILL_DIR"/scripts/tests/*.test.sh; do
  [ -f "$f" ] || continue
  run_test_file "$f" "${f#"$SKILL_DIR"/}"
done

if python3 "$SKILL_DIR/scripts/tests/test_goalforge_archive_sweep.py" >/tmp/goalforge-run-sh-$$.out 2>&1; then
  check "scripts/tests/test_goalforge_archive_sweep.py" "pass"
else
  check "scripts/tests/test_goalforge_archive_sweep.py" "fail"
  sed 's/^/        /' "/tmp/goalforge-run-sh-$$.out"
fi
rm -f "/tmp/goalforge-run-sh-$$.out"

echo ""

# ── b3: package-level lint/type/compile gates ────────────────────────────────
echo "[ b3: package lint/type/compile gates ]"

if python3 -m py_compile "$SKILL_DIR/scripts/goalforge-pick-agent.py" "$SKILL_DIR/scripts/goalforge-plan-index.py" 2>/tmp/goalforge-run-sh-$$.out; then
  check "python3 -m py_compile goalforge-pick-agent.py goalforge-plan-index.py" "pass"
else
  check "python3 -m py_compile goalforge-pick-agent.py goalforge-plan-index.py" "fail"
  sed 's/^/        /' "/tmp/goalforge-run-sh-$$.out"
fi
rm -f "/tmp/goalforge-run-sh-$$.out"

if bash -n "$SKILL_DIR/scripts/goalforge-status.sh" 2>/tmp/goalforge-run-sh-$$.out; then
  check "bash -n goalforge-status.sh" "pass"
else
  check "bash -n goalforge-status.sh" "fail"
  sed 's/^/        /' "/tmp/goalforge-run-sh-$$.out"
fi
rm -f "/tmp/goalforge-run-sh-$$.out"

if python3 "$SKILL_DIR/scripts/goalforge-pick-agent.py" --test-tiers >/tmp/goalforge-run-sh-$$.out 2>&1; then
  check "python3 goalforge-pick-agent.py --test-tiers" "pass"
else
  check "python3 goalforge-pick-agent.py --test-tiers" "fail"
  sed 's/^/        /' "/tmp/goalforge-run-sh-$$.out"
fi
rm -f "/tmp/goalforge-run-sh-$$.out"

if command -v ruff >/dev/null 2>&1; then
  if ruff check --select F,E9,B "$SKILL_DIR/scripts/goalforge-pick-agent.py" >/tmp/goalforge-run-sh-$$.out 2>&1; then
    check "ruff check --select F,E9,B goalforge-pick-agent.py" "pass"
  else
    check "ruff check --select F,E9,B goalforge-pick-agent.py" "fail"
    sed 's/^/        /' "/tmp/goalforge-run-sh-$$.out"
  fi
  rm -f "/tmp/goalforge-run-sh-$$.out"
else
  echo "  WARN: ruff not installed -- skipping ruff gate"
fi

if command -v pyright >/dev/null 2>&1; then
  PYRIGHT_CFG="/tmp/goalforge-run-sh-pyrightconfig-$$.json"
  cat > "$PYRIGHT_CFG" <<'EOF'
{
  "reportUnreachable": "warning",
  "reportUnusedVariable": "warning"
}
EOF
  if pyright -p "$PYRIGHT_CFG" "$SKILL_DIR/scripts/goalforge-pick-agent.py" >/tmp/goalforge-run-sh-$$.out 2>&1; then
    check "pyright (reportUnreachable/reportUnusedVariable=warning) goalforge-pick-agent.py" "pass"
  else
    check "pyright (reportUnreachable/reportUnusedVariable=warning) goalforge-pick-agent.py" "fail"
    sed 's/^/        /' "/tmp/goalforge-run-sh-$$.out"
  fi
  rm -f "$PYRIGHT_CFG" "/tmp/goalforge-run-sh-$$.out"
else
  echo "  WARN: pyright not installed -- skipping pyright gate"
fi

echo ""

# ── b1/b2: trace replay BUILT at test time, not a static fixture ────────────
# A static JSONL fixture never exercises goalforge-execute / goalforge-verify —
# sabotaging either SKILL.md would leave the harness green. Instead drive the
# REAL emitters (goalforge-trace-emit + the hook helper
# goalforge_emit_gate_result from hooks/goalforge-plans-root.sh) against a
# throwaway temp feature dir, then assert over the PRODUCED file.
echo "[ b1/b2: execute+verify trace replay (built at test time) ]"

TMP_TRACE_DIR="$(mktemp -d)"
B_FEATURE_DIR="$TMP_TRACE_DIR/plans/wp01-trace-check"
B_WP_DIR="$B_FEATURE_DIR/wp-01-example"
mkdir -p "$B_WP_DIR"
cat > "$B_WP_DIR/overview.md" <<'EOF'
---
name: wp-01-example
schema_version: 6
status: spec
---
EOF

(
  export SDD_PLANS_DIR="$TMP_TRACE_DIR/plans"
  export HOOK_DIR="$SKILL_DIR/hooks"
  emit() { python3 "$SKILL_DIR/scripts/goalforge-trace-emit" --feature-dir "$B_FEATURE_DIR" --event "$1" >/dev/null; }
  emit '{"type":"dispatch.launched","wp":"wp-01-example","model":"sonnet","provider":"anthropic","agent":"implement","effort":"medium"}'
  emit '{"type":"dispatch.completed","wp":"wp-01-example","agent":"implement","outcome":"ok","exit_code":0,"tokens":1234,"tool_uses":5,"session":"test"}'
  ( source "$SKILL_DIR/hooks/goalforge-plans-root.sh"; goalforge_emit_gate_result A pass "deterministic gate green" "$B_WP_DIR/overview.md" )
  ( source "$SKILL_DIR/hooks/goalforge-plans-root.sh"; goalforge_emit_gate_result B pass "review clean" "$B_WP_DIR/overview.md" )
  ( source "$SKILL_DIR/hooks/goalforge-plans-root.sh"; goalforge_emit_gate_result C pass "goal judge: all facets met, no shim" "$B_WP_DIR/overview.md" )
  emit '{"type":"commit.linked","wp":"wp-01-example","commit":"deadbee","actor":"goalforge-execute"}'
  emit '{"type":"second_opinion.skipped","wp":"wp-01-example","reason":"headless_dispatch not present"}'
  emit '{"type":"wp.verified","wp":"wp-01-example","reason":"Gates A/B/C passed"}'
) >/tmp/goalforge-run-sh-$$.out 2>&1 || true

B_TRACE="$B_FEATURE_DIR/trace-events.jsonl"

if [ -f "$B_TRACE" ] && "$SKILL_DIR/scripts/goalforge-trace-read" "$B_TRACE" >/tmp/goalforge-run-sh-$$.out 2>&1; then
  check "produced trace-events.jsonl reads clean (strict schema_version parse)" "pass"
else
  check "produced trace-events.jsonl reads clean (strict schema_version parse)" "fail"
  sed 's/^/        /' "/tmp/goalforge-run-sh-$$.out" 2>/dev/null
fi
rm -f "/tmp/goalforge-run-sh-$$.out"

COMMIT_LINKED_COUNT="$(grep -c '"type":"commit.linked"' "$B_TRACE" 2>/dev/null || echo 0)"
[ "$COMMIT_LINKED_COUNT" -eq 1 ] \
  && check "exactly one commit.linked row in the produced trace" "pass" \
  || check "exactly one commit.linked row in the produced trace (got $COMMIT_LINKED_COUNT)" "fail"

DISPATCH_OK="pass"
grep -q '"type":"dispatch.launched"' "$B_TRACE" 2>/dev/null || DISPATCH_OK="fail"
grep -q '"type":"dispatch.completed"' "$B_TRACE" 2>/dev/null || DISPATCH_OK="fail"
check "produced trace carries dispatch.launched/dispatch.completed rows" "$DISPATCH_OK"

GATE_OK="pass"
for G in A B C; do
  N="$(grep -c "\"type\":\"gate.result\".*\"gate\":\"$G\"" "$B_TRACE" 2>/dev/null || echo 0)"
  [ "$N" -eq 1 ] || GATE_OK="fail"
done
check "exactly one gate.result per gate A, B, C in the produced trace" "$GATE_OK"

SO_COUNT="$(grep -cE '"type":"second_opinion\.(ok|skipped)"' "$B_TRACE" 2>/dev/null || echo 0)"
if [ "$SO_COUNT" -eq 1 ] && grep -qE '"type":"second_opinion\.(ok|skipped)".*"reason":"[^"]+"' "$B_TRACE" 2>/dev/null; then
  check "exactly one second_opinion.{ok|skipped} row carrying a reason" "pass"
else
  check "exactly one second_opinion.{ok|skipped} row carrying a reason (got $SO_COUNT)" "fail"
fi

if [ -n "$(find "$TMP_TRACE_DIR" -name 'task-*.md' 2>/dev/null)" ]; then
  check "no task-*.md files under the temp plan dir" "fail"
else
  check "no task-*.md files under the temp plan dir" "pass"
fi

rm -rf "$TMP_TRACE_DIR"

# b1 oracle over the LIVE (non-archived) plan tree, per spec.md: `! find plans
# -name task-*.md` excluding plans/_archived and plans/archive.
LIVE_TASK_FILES="$(find "$SKILL_DIR/../.." -path '*/plans/*' -name 'task-*.md' 2>/dev/null \
  | grep -v '/plans/_archived/' | grep -v '/plans/archive/' || true)"
if [ -z "$LIVE_TASK_FILES" ]; then
  check "no task-*.md under the live (non-archived) plans tree" "pass"
else
  check "no task-*.md under the live (non-archived) plans tree" "fail"
  printf '%s\n' "$LIVE_TASK_FILES" | sed 's/^/        /'
fi

echo ""

# ── b4: fixture manifest comparison ────────────────────────────────────────
echo "[ b4: evals/fixtures/ immutability ]"
FIXTURE_MANIFEST_AFTER="$(mktemp)"
fixture_manifest > "$FIXTURE_MANIFEST_AFTER"
if diff -u "$FIXTURE_MANIFEST_BEFORE" "$FIXTURE_MANIFEST_AFTER" > /tmp/goalforge-fixture-diff-$$.out 2>&1; then
  check "evals/fixtures/ unchanged across the run (sha256 manifest)" "pass"
else
  check "evals/fixtures/ unchanged across the run (sha256 manifest)" "fail"
  echo "        a fixture file changed, appeared, or vanished:"
  sed 's/^/        /' /tmp/goalforge-fixture-diff-$$.out
fi
rm -f "$FIXTURE_MANIFEST_BEFORE" "$FIXTURE_MANIFEST_AFTER" "/tmp/goalforge-fixture-diff-$$.out"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
