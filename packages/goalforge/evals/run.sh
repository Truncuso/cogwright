#!/usr/bin/env bash
# Eval harness for the goalforge overview skill.
# Checks skill structure and content correctness without invoking a model.
# Exit 0 = all pass. Exit non-zero = failures found.

set -euo pipefail

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

echo "=== goalforge SKILL.md eval harness ==="
echo ""

# ── Trigger tests ────────────────────────────────────────────────────────────
echo "[ Trigger tests ]"

# T1: description contains an "explain SDD" trigger phrase
grep -q "explain SDD" "$SKILL_MD" \
  && check "description includes 'explain SDD' trigger" "pass" \
  || check "description includes 'explain SDD' trigger" "fail"

# T2: description contains anti-trigger (do NOT use to run the chain)
grep -q "Do NOT" "$SKILL_MD" \
  && check "description includes anti-trigger for chain execution" "pass" \
  || check "description includes anti-trigger for chain execution" "fail"

# T3: name field is exactly 'goalforge'
grep -q "^name: goalforge$" "$SKILL_MD" \
  && check "name field is 'goalforge'" "pass" \
  || check "name field is 'goalforge'" "fail"

echo ""

# ── Functional tests ─────────────────────────────────────────────────────────
echo "[ Functional tests ]"

# F1: redirect stub covers all 6 chain step names (old->new map in SKILL.md
# or references/alias-map.md) — stub contract per wp-02 gate check (3)
ALIAS_MAP="$SKILL_DIR/references/alias-map.md"
STEPS="sdd-capture sdd-spec sdd-decompose sdd-harden sdd-execute sdd-verify"
STEPS_OK="pass"
for step in $STEPS; do
  grep -q "$step" "$SKILL_MD" "$ALIAS_MAP" 2>/dev/null || STEPS_OK="fail"
done
check "all 6 chain step names covered by redirect stub/alias-map" "$STEPS_OK"

# F2: every old name maps to a goalforge-* target in the alias map
MAP_OK="pass"
for step in $STEPS; do
  new="goalforge-${step#sdd-}"
  grep -q "$new" "$SKILL_MD" "$ALIAS_MAP" 2>/dev/null || MAP_OK="fail"
done
check "alias map carries goalforge-* targets for all 6 steps" "$MAP_OK"

# F3: SKILL.md states LOCAL authority over the cogwright plugin export
grep -Eq 'LOCAL authority|authoritative' "$SKILL_MD" \
  && check "SKILL.md states local authority" "pass" \
  || check "SKILL.md states local authority" "fail"

# F4: references/schema.md and references/templates/ mentioned
grep -q "references/schema.md" "$SKILL_MD" \
  && check "references/schema.md mentioned" "pass" \
  || check "references/schema.md mentioned" "fail"

# F5: local script authority — every goalforge-*.sh/.py script is executable
SHIM_OK="pass"
for shim in "$SKILL_DIR"/scripts/goalforge-*.sh; do
  [ -x "$shim" ] || SHIM_OK="fail"
done
check "all goalforge-*.sh scripts are executable" "$SHIM_OK"

# F6: Referenced bundled files actually exist on disk
REFS_OK="pass"
for ref in \
  "$SKILL_DIR/references/schema.md" \
  "$SKILL_DIR/references/templates" \
  "$SKILL_DIR/references/specialist-map.yaml" \
  "$SKILL_DIR/scripts/goalforge-validate.sh" \
  "$SKILL_DIR/scripts/goalforge-goal-eval.py" \
  "$SKILL_DIR/scripts/goalforge-pick-agent.py"
do
  [ -e "$ref" ] || REFS_OK="fail"
done
check "all referenced bundled files exist on disk" "$REFS_OK"

# F7: Stop hook measurement present
grep -q "skill-measure.sh goalforge" "$SKILL_MD" \
  && check "Stop measurement hook present" "pass" \
  || check "Stop measurement hook present" "fail"

# F8: canonical role→tier map eval passes (deterministic, no network)
if python3 "$SKILL_DIR/scripts/goalforge-pick-agent.py" --test-tiers >/dev/null 2>&1; then
  check "role→tier map invariants pass (goalforge-pick-agent --test-tiers)" "pass"
else
  check "role→tier map invariants pass (goalforge-pick-agent --test-tiers)" "fail"
fi

# F9: schema-v5 fixture eval harness passes (deterministic, no network)
if bash "$SKILL_DIR/evals/schema-v5/run.sh" >/dev/null 2>&1; then
  check "schema-v5 fixture eval harness passes (evals/schema-v5/run.sh)" "pass"
else
  check "schema-v5 fixture eval harness passes (evals/schema-v5/run.sh)" "fail"
fi

# F11: wave-route fixture eval harness passes (deterministic, no network)
if bash "$SKILL_DIR/evals/wave-route/run.sh" >/dev/null 2>&1; then
  check "wave-route fixture eval harness passes (evals/wave-route/run.sh)" "pass"
else
  check "wave-route fixture eval harness passes (evals/wave-route/run.sh)" "fail"
fi

# F13: preharden-lint self-test passes (deterministic, no network)
if bash "$SKILL_DIR/scripts/goalforge-preharden-lint.sh" --self-test >/dev/null 2>&1; then
  check "preharden-lint self-test passes (scripts/goalforge-preharden-lint.sh)" "pass"
else
  check "preharden-lint self-test passes (scripts/goalforge-preharden-lint.sh)" "fail"
fi

# F12: brief-stage fixture eval harness passes (deterministic, no network)
if bash "$SKILL_DIR/evals/brief-stage/run.sh" >/dev/null 2>&1; then
  check "brief-stage fixture eval harness passes (evals/brief-stage/run.sh)" "pass"
else
  check "brief-stage fixture eval harness passes (evals/brief-stage/run.sh)" "fail"
fi

# F10: doc-level restatements of TIER_DISPATCH match the code (drift pin —
# this drift occurred twice in the tiered-dispatch-routing feature's history).
DOC_PIN_OK="pass"
CANON=$(python3 - "$SKILL_DIR/scripts/goalforge-pick-agent.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("m", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
td = m.TIER_DISPATCH
print(", ".join(f"{t} → {d['model']}@{d['effort']}" for t, d in td.items()))
print(f"{m.TIER_DISPATCH['medium']['model']}@{m.TIER_DISPATCH['medium']['effort']}")
PYEOF
) || DOC_PIN_OK="fail"
if [ "$DOC_PIN_OK" = "pass" ]; then
  CANON_LINE=$(echo "$CANON" | sed -n 1p)     # e.g. low → sonnet@low, medium → opus@low, high → opus@high
  MEDIUM_DISPATCH=$(echo "$CANON" | sed -n 2p) # e.g. opus@low (wp-harden-delta/semi claim)
  # Canonical prose restatement site must match the code values verbatim.
  grep -qF "\`low → sonnet@low\`, \`medium → opus@low\`, \`high → opus@high\`" \
    "$SKILL_DIR/execute/references/dispatch-resolution.md" \
    && [ "$CANON_LINE" = "low → sonnet@low, medium → opus@low, high → opus@high" ] \
    || DOC_PIN_OK="fail"
  # pre-harden-review.md's wp-harden-delta claim must match resolve_dispatch(medium).
  grep -qF "\`${MEDIUM_DISPATCH}\`" "$SKILL_DIR/harden/references/pre-harden-review.md" \
    || DOC_PIN_OK="fail"
  # The retired haiku/sonnet/opus complexity prose must not resurface in schema.md.
  grep -qE '`low` → Haiku|low → haiku' "$SKILL_DIR/references/schema.md" && DOC_PIN_OK="fail"
  # CLAUDE.md P5 digest restates the tier values — pin them too (user decision
  # 2026-07-09). Guarded by the CANON_LINE equality above: if TIER_DISPATCH
  # changes, that check fails first and these greps must be updated with it.
  # $HOME/.claude/CLAUDE.md, not $SKILL_DIR/../..: the skills dir may be a
  # symlink into this package (wp-18 contributor mode) and a relative climb
  # resolves physically into the cogwright repo, where no CLAUDE.md exists.
  CLAUDE_MD="${CLAUDE_MD_OVERRIDE:-$HOME/.claude/CLAUDE.md}"
  { [ -f "$CLAUDE_MD" ] \
      && grep -qF "sonnet/low" "$CLAUDE_MD" \
      && grep -qE 'opus at low|opus@low|opus/low' "$CLAUDE_MD" \
      && grep -qF "opus/high" "$CLAUDE_MD"; } \
    || DOC_PIN_OK="fail"
fi
check "doc restatements of TIER_DISPATCH match code (drift pin)" "$DOC_PIN_OK"

# ── Fidelity ladder tests ────────────────────────────────────────────────────
echo ""
echo "[ Fidelity ladder tests ]"

FIDELITY_MD="$SKILL_DIR/references/fidelity.md"

# F1: the canonical ladder reference exists
[ -f "$FIDELITY_MD" ] \
  && check "references/fidelity.md exists" "pass" \
  || check "references/fidelity.md exists" "fail"

# F2: all three ladder rungs are named
if [ -f "$FIDELITY_MD" ] \
  && grep -qE '^1\. \*\*Discussion' "$FIDELITY_MD" \
  && grep -qE '^2\. \*\*Interview' "$FIDELITY_MD" \
  && grep -qE '^3\. \*\*Prototype' "$FIDELITY_MD"; then
  check "fidelity.md names all three rungs (discussion/interview/prototype)" "pass"
else
  check "fidelity.md names all three rungs (discussion/interview/prototype)" "fail"
fi

# F3: the canonical trigger criterion has its own section
{ [ -f "$FIDELITY_MD" ] && grep -qE '^## Trigger' "$FIDELITY_MD"; } \
  && check "fidelity.md carries a ## Trigger section" "pass" \
  || check "fidelity.md carries a ## Trigger section" "fail"

# F4: the issue/open-question routing rule has its own section
{ [ -f "$FIDELITY_MD" ] && grep -qE '^## issue-routing' "$FIDELITY_MD"; } \
  && check "fidelity.md carries a ## issue-routing section" "pass" \
  || check "fidelity.md carries a ## issue-routing section" "fail"

# F5-F9: every stage skill links the ladder rather than restating it
for STAGE in capture spec harden decompose execute; do
  grep -q "fidelity.md" "$SKILL_DIR/$STAGE/SKILL.md" \
    && check "$STAGE/SKILL.md links references/fidelity.md" "pass" \
    || check "$STAGE/SKILL.md links references/fidelity.md" "fail"
done

# F10: spec carries BOTH fidelity hooks (Step 2 blocked-section spike +
# the goal.outcome facet flag) — deleting either must fail this check.
[ "$(grep -c 'fidelity.md' "$SKILL_DIR/spec/SKILL.md" || true)" -ge 2 ] \
  && check "spec/SKILL.md carries both fidelity hooks (>=2 links)" "pass" \
  || check "spec/SKILL.md carries both fidelity hooks (>=2 links)" "fail"


# ── Interview specialization tests ─────────────────────────────────────────────────────────
echo ""
echo "[ Interview specialization tests ]"

INTERVIEW_MD="$SKILL_DIR/interview/SKILL.md"
HARDEN_MD="$SKILL_DIR/harden/SKILL.md"

# I1: interview/SKILL.md exists
[ -f "$INTERVIEW_MD" ] \
  && check "interview/SKILL.md exists" "pass" \
  || check "interview/SKILL.md exists" "fail"

# I2: name field is pinned to 'goalforge-interview'
{ [ -f "$INTERVIEW_MD" ] && grep -q "^name: goalforge-interview$" "$INTERVIEW_MD"; } \
  && check "interview/SKILL.md name field is 'goalforge-interview'" "pass" \
  || check "interview/SKILL.md name field is 'goalforge-interview'" "fail"

# I3: escape-hatch phrase present (consumed by harden Step 1)
{ [ -f "$INTERVIEW_MD" ] && grep -qF "above discussion fidelity" "$INTERVIEW_MD"; } \
  && check "interview/SKILL.md carries the escape-hatch phrase" "pass" \
  || check "interview/SKILL.md carries the escape-hatch phrase" "fail"

# I4: high-fidelity token present -- the engine contract this wrapper consumes
{ [ -f "$INTERVIEW_MD" ] && grep -q "high-fidelity" "$INTERVIEW_MD"; } \
  && check "interview/SKILL.md carries the 'high-fidelity' token" "pass" \
  || check "interview/SKILL.md carries the 'high-fidelity' token" "fail"

# I5: links the canonical fidelity ladder rather than restating it
{ [ -f "$INTERVIEW_MD" ] && grep -q "fidelity.md" "$INTERVIEW_MD"; } \
  && check "interview/SKILL.md links references/fidelity.md" "pass" \
  || check "interview/SKILL.md links references/fidelity.md" "fail"

# I6: fork-guard -- must not reimplement the engine's stopping logic
{ [ -f "$INTERVIEW_MD" ] && ! grep -q "predictive-confidence stopping" "$INTERVIEW_MD"; } \
  && check "interview/SKILL.md does not fork interview-loop's stopping logic" "pass" \
  || check "interview/SKILL.md does not fork interview-loop's stopping logic" "fail"

# I7: harden/SKILL.md references goalforge-interview at least twice (call
# site + delegation description; a single stray mention isn't real wiring)
[ "$(grep -c "goalforge-interview" "$HARDEN_MD" 2>/dev/null || true)" -ge 2 ] \
  && check "harden/SKILL.md references goalforge-interview (>=2 mentions)" "pass" \
  || check "harden/SKILL.md references goalforge-interview (>=2 mentions)" "fail"

# I8: parent SKILL.md Children table carries the goalforge-interview row
grep -qF '`goalforge-interview`' "$SKILL_MD" \
  && check "parent SKILL.md Children table lists goalforge-interview" "pass" \
  || check "parent SKILL.md Children table lists goalforge-interview" "fail"

# I9: fidelity.md's escape-hatch row names goalforge-interview and carries no
# stale planned-marker (wiring, not a roadmap note)
{ [ -f "$FIDELITY_MD" ] && grep -qE '\| `goalforge-interview` escape hatch' "$FIDELITY_MD"; } \
  && ! grep -q "planned — wp-06" "$FIDELITY_MD" \
  && check "fidelity.md escape-hatch row wired, no planned-wp-06 marker" "pass" \
  || check "fidelity.md escape-hatch row wired, no planned-wp-06 marker" "fail"

# I10: engine-drift guard -- cross-boundary dependency on the global engine's
# consumed contract tokens. Skip with a WARN (not a FAIL) if the engine path
# is absent on this machine.
ENGINE_MD="$HOME/.claude/skills/interview-loop/SKILL.md"
if [ -f "$ENGINE_MD" ]; then
  { grep -q "HANDOFF_SUGGESTION" "$ENGINE_MD" && grep -q "high-fidelity" "$ENGINE_MD"; } \
    && check "engine interview-loop/SKILL.md still exposes consumed contract tokens" "pass" \
    || check "engine interview-loop/SKILL.md still exposes consumed contract tokens" "fail"
else
  echo "  WARN: $ENGINE_MD absent -- skipping engine-drift guard (foreign machine)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
