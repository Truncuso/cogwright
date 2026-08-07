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

# F14: spike-spec fragment + wiring pointers (durable feature facts only).
# Asserts the fragment exists with its five H2s and both greppable anchors, and
# that the EXACT full pointer string is present at every wiring site: 6 fidelity
# routing rows (window delimited by the routing-table stage labels, never
# absolute line numbers), the interview escape hatch, and decompose §Prototype
# WPs. Validator --self-test is covered transitively via F9 → evals/schema-v5.
# No plans/ path and no repo-root climb: $SKILL_DIR resolution only.
SPIKE_SPEC_OK="pass"
SPIKE_SPEC="$SKILL_DIR/prototype/references/spike-spec.md"
SPIKE_PTR='~/.claude/skills/goalforge/prototype/references/spike-spec.md'
if [ -f "$SPIKE_SPEC" ]; then
  SPIKE_H2=$(grep -c '^## ' "$SPIKE_SPEC" || true)
  [ "$SPIKE_H2" -eq 5 ] || SPIKE_SPEC_OK="fail"
  # Names, not just count: decompose/SKILL.md stamps four of these by NAME —
  # a renamed H2 would silently desync that instruction with the count green.
  for h in 'Design Question' 'Trigger Evidence' 'Success Criteria' 'Branch' 'Expected Findings Shape'; do
    grep -qxF "## $h" "$SPIKE_SPEC" || SPIKE_SPEC_OK="fail"
  done
  grep -qF 'spikes/' "$SPIKE_SPEC" || SPIKE_SPEC_OK="fail"
  grep -qiF 'not stamped' "$SPIKE_SPEC" || SPIKE_SPEC_OK="fail"
  FID_PTR_COUNT=$(awk '/^\| stage \/ surface \| hook \|/{f=1} f&&/^## /{exit} f' \
    "$SKILL_DIR/references/fidelity.md" | grep -cF "$SPIKE_PTR" || true)
  [ "$FID_PTR_COUNT" -eq 6 ] || SPIKE_SPEC_OK="fail"
  # Each window is captured into a variable BEFORE grepping it: `awk … | grep -q`
  # under `set -o pipefail` lets grep exit on first match, SIGPIPE the awk, and
  # turn a SUCCESSFUL match into a pipeline failure. TRAP: the opener regex and
  # the window-terminating heading test run on the SAME record, so the anchor
  # phrase must never appear IN a heading — 'Escape hatch' / 'Prototype WPs'
  # capitalised inside a `## `/`### ` line would empty the window and red F14.
  IV_WIN=$(awk '/Escape hatch/{f=1} f&&/^## /{exit} f' "$SKILL_DIR/interview/SKILL.md" || true)
  grep -qF "$SPIKE_PTR" <<<"$IV_WIN" || SPIKE_SPEC_OK="fail"
  DEC_WIN=$(awk '/Prototype WPs/{f=1} f&&/^### /{exit} f' "$SKILL_DIR/decompose/SKILL.md" || true)
  grep -qF "$SPIKE_PTR" <<<"$DEC_WIN" || SPIKE_SPEC_OK="fail"
else
  SPIKE_SPEC_OK="fail"
fi
check "spike-spec fragment + wiring pointers present (6 fidelity rows, interview, decompose)" "$SPIKE_SPEC_OK"

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
# Mutation coverage for this block: evals/interview-mutations.sh (run by the
# WP verification check; not auto-invoked here to avoid recursion).
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
  && check "interview/SKILL.md does not fork the interview plugin engine's stopping logic" "pass" \
  || check "interview/SKILL.md does not fork the interview plugin engine's stopping logic" "fail"

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

# I10: engine-drift guard -- cross-boundary dependency on the interview
# plugin engine's consumed contract tokens. Version-globbed cache path (never
# a pinned version). Hard-fails when this repo's marketplace lists the
# interview plugin; WARN-skips only on installs without it.
ENGINE_MD="$(ls "$HOME"/.claude/plugins/cache/cogwright/interview/*/engine.md 2>/dev/null | sort -V | tail -1 || true)"
MARKETPLACE_JSON="$SKILL_DIR/../../.claude-plugin/marketplace.json"
if [ -n "$ENGINE_MD" ] && [ -f "$ENGINE_MD" ]; then
  { grep -q "HANDOFF_SUGGESTION" "$ENGINE_MD" && grep -q "high-fidelity" "$ENGINE_MD"; } \
    && check "interview plugin engine.md still exposes consumed contract tokens" "pass" \
    || check "interview plugin engine.md still exposes consumed contract tokens" "fail"
elif grep -q '"name": "interview"' "$MARKETPLACE_JSON" 2>/dev/null; then
  check "interview plugin engine.md resolvable (marketplace lists interview)" "fail"
else
  echo "  WARN: interview plugin engine.md absent -- skipping engine-drift guard (plugin not installed)"
fi


# ── wp-07 conformance tests ─────────────────────────────────────────────
# Re-asserts the facts wp-07 establishes (tasks 01-03) so they survive the WP.
echo ""
echo "[ wp-07 conformance tests ]"

WAYFIND_MD="$SKILL_DIR/wayfind/SKILL.md"

# C1: every child SKILL.md carries a nested metadata.skill-kind (18 children)
SKILL_KIND_COUNT="$(grep -lE '^  skill-kind: (capability|preference)$' "$SKILL_DIR"/*/SKILL.md 2>/dev/null | wc -l || true)"
[ "$SKILL_KIND_COUNT" -eq 18 ] \
  && check "all 18 child SKILL.md files declare metadata.skill-kind" "pass" \
  || check "all 18 child SKILL.md files declare metadata.skill-kind (got $SKILL_KIND_COUNT)" "fail"

# C2: wayfind/SKILL.md carries a metadata block with a nested semver version
{ [ -f "$WAYFIND_MD" ] && grep -q '^metadata:$' "$WAYFIND_MD" \
    && grep -qE '^  version: [0-9]+\.[0-9]+\.[0-9]+$' "$WAYFIND_MD"; } \
  && check "wayfind/SKILL.md has metadata: with nested semver version:" "pass" \
  || check "wayfind/SKILL.md has metadata: with nested semver version:" "fail"

# C3: wayfind/SKILL.md carries the required Gotchas section
{ [ -f "$WAYFIND_MD" ] && grep -q '^## Gotchas$' "$WAYFIND_MD"; } \
  && check "wayfind/SKILL.md has a ## Gotchas section" "pass" \
  || check "wayfind/SKILL.md has a ## Gotchas section" "fail"

# C4: parent SKILL.md carries the co-tenancy note naming both non-chain tenants
# (anchored to the note line itself, not presence-anywhere — WP-gate F2)
grep -qE '^Note: `prototype/` and `wayfind/` are non-chain tenants' "$SKILL_MD" \
  && check "parent SKILL.md co-tenancy note names prototype/ and wayfind/" "pass" \
  || check "parent SKILL.md co-tenancy note names prototype/ and wayfind/" "fail"

# C5: NEGATIVE -- non-chain tenants must NOT appear as Children-table rows
# (backticks optional so an unbackticked row cannot slip past — WP-gate F2)
grep -qE '^\| *`?(prototype|wayfind)`? *\|' "$SKILL_MD" \
  && check "parent SKILL.md Children table has no prototype/wayfind row" "fail" \
  || check "parent SKILL.md Children table has no prototype/wayfind row" "pass"

# C6: Children table stays at exactly 15 chain-stage rows (catches a
# prototype/wayfind row added in ANY form, backticked or not — WP-gate F2)
CHILD_ROW_COUNT="$(grep -c '^| `goalforge-' "$SKILL_MD" || true)"
[ "$CHILD_ROW_COUNT" -eq 15 ] \
  && check "parent SKILL.md Children table has exactly 15 chain-stage rows" "pass" \
  || check "parent SKILL.md Children table has exactly 15 chain-stage rows (got $CHILD_ROW_COUNT)" "fail"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
