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

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
