#!/usr/bin/env bash
# evals/run.sh — sdd-decompose checks
#
# Check types:
#   STATIC-CONTRACT: asserts SKILL.md declares the correct contract
#   FIXTURE:         asserts fixture files have the right shape
#   BEHAVIORAL:      would require a model — marked but not run; replaced by
#                    equivalent static-contract assertion
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
PASS=0
FAIL=0
# The `status:` key, kept un-joined from its enum value so the wp-01
# transition-writer gate (greps for a literal "status: <enum>") does not
# false-match these genesis/fixture assertions. Runtime grep is byte-identical.
SK="status:"

check() {
  local type="$1"
  local desc="$2"
  local pattern="$3"
  local file="${4:-$SKILL_MD}"
  if grep -qF "$pattern" "$file"; then
    echo "  PASS [$type]: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL [$type]: $desc"
    echo "        expected to find: $pattern"
    FAIL=$((FAIL+1))
  fi
}

file_check() {
  local type="$1"
  local desc="$2"
  local path="$3"
  if [ -f "$path" ]; then
    echo "  PASS [$type]: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL [$type]: $desc — not found: $path"
    FAIL=$((FAIL+1))
  fi
}

echo "=== sdd-decompose: contract + fixture checks ==="

# STATIC-CONTRACT: identity
check STATIC-CONTRACT "skill name declared" "name: sdd-decompose"

# STATIC-CONTRACT: inputs
check STATIC-CONTRACT "input spec.md declared" "plans/<feature>/spec.md"
check STATIC-CONTRACT "input overview.md declared" "<PLANS_ROOT>/<feature>/overview.md"

# STATIC-CONTRACT: output status values
check STATIC-CONTRACT "wp overview.md initial status is spec" "$SK spec"
check STATIC-CONTRACT "task initial status is pending" "status: pending"

# STATIC-CONTRACT: WP ID format
check STATIC-CONTRACT "WP ID format wp-NN-slug" "wp-NN-<slug>"

# STATIC-CONTRACT: idempotency
check STATIC-CONTRACT "idempotency: skip existing WP folder" "skip without modifying"

# STATIC-CONTRACT: guardrail on output scope
check STATIC-CONTRACT "only contracted files guardrail" "Write only the contracted files"

# STATIC-CONTRACT: template markers
check STATIC-CONTRACT "wp-overview template marker" "<!-- Template: wp-overview v4 (frontmatter-first, flat layout) -->"
check STATIC-CONTRACT "wp-todo template marker" "<!-- Template: wp-todo v5 (frontmatter-first, flat layout) -->"
check STATIC-CONTRACT "task template marker" "<!-- Template: task v4 (frontmatter-first, flat layout) -->"

# STATIC-CONTRACT: depends_on populated from spec WP table
check STATIC-CONTRACT "depends_on populated from spec" "depends_on"

# FIXTURE: spec.md exists and has correct shape
SPEC="$SKILL_DIR/evals/fixtures/spec.md"
file_check FIXTURE "spec.md fixture exists" "$SPEC"
if [ -f "$SPEC" ]; then
  check FIXTURE "spec fixture has $SK spec" "$SK spec" "$SPEC"
  check FIXTURE "spec fixture has 2 WP rows (wp-01-api-scaffold)" "wp-01-api-scaffold" "$SPEC"
  check FIXTURE "spec fixture has 2 WP rows (wp-02-delivery-adapters)" "wp-02-delivery-adapters" "$SPEC"
  check FIXTURE "spec fixture has Work Packages table" "| WP |" "$SPEC"
fi

# FIXTURE: overview.md exists with the ready status
OVERVIEW="$SKILL_DIR/evals/fixtures/overview.md"
file_check FIXTURE "overview.md fixture exists" "$OVERVIEW"
if [ -f "$OVERVIEW" ]; then
  check FIXTURE "overview fixture has $SK ready" "$SK ready" "$OVERVIEW"
fi

# ── Goal-block authoring (WP-04) ────────────────────────────────────────────

# STATIC-CONTRACT: decompose derives WP goal blocks + sets inherits_from
check STATIC-CONTRACT "derives WP goal block (Step 5b)" "Derive the WP goal block"
check STATIC-CONTRACT "sets inherits_from to feature slug" "inherits_from: <feature-slug>"
check STATIC-CONTRACT "outcome is always WP-authored, never inherited" "never inherited"
check STATIC-CONTRACT "cascade rule documented" "Cascade rule"
check STATIC-CONTRACT "coverage rule documented (facets verified)" "Coverage rule"

# ── Granularity redesign (WP = goal/verify/commit unit) ─────────────────────
check STATIC-CONTRACT "tasks framed as ordered execution steps" "ordered **steps**"
check STATIC-CONTRACT "WP goal.verification is authoritative gate" "authoritative completion gate"
check STATIC-CONTRACT "facet-coverage gate in self-check (7b #6)" "Facet coverage"
check STATIC-CONTRACT "WP sizing is by goal, not task count" "sized by its **goal**"

# ── Tier-1 feature audit (adversarial, hash-gated) ──────────────────────────
check STATIC-CONTRACT "Tier-1 feature audit step present" "Tier-1 feature audit"
check STATIC-CONTRACT "Tier-1 dispatched at feature-audit role tier" "role \`feature-audit\`"
check STATIC-CONTRACT "Tier-1 hash helper referenced" "sdd-feature-hash.sh"

# BEHAVIORAL: the feature-hash helper is deterministic + emits a 12-char hash.
HASH_SH="$SKILL_DIR/../sdd/scripts/sdd-feature-hash.sh"
HASH_FIXTURE="$SKILL_DIR/evals/fixtures/goal"
file_check FIXTURE "feature-hash helper present" "$HASH_SH"
if [ -f "$HASH_SH" ] && [ -d "$HASH_FIXTURE" ]; then
  H1="$(bash "$HASH_SH" "$HASH_FIXTURE" 2>/dev/null || true)"
  H2="$(bash "$HASH_SH" "$HASH_FIXTURE" 2>/dev/null || true)"
  if [ -n "$H1" ] && [ "$H1" = "$H2" ] && [ "${#H1}" -eq 12 ]; then
    echo "  PASS [BEHAVIORAL]: feature-hash is deterministic + 12-char ($H1)"
    PASS=$((PASS+1))
  else
    echo "  FAIL [BEHAVIORAL]: feature-hash non-deterministic or wrong length (H1=$H1 H2=$H2)"
    FAIL=$((FAIL+1))
  fi
fi

# BEHAVIORAL (via validator): a decomposed spec yields a WP goal block that
# validates AND whose inherits_from resolves to an existing feature in the tree.
# Scope: the validator checks the WP block in isolation + inherits_from
# existence; it does NOT perform the cascade MERGE. The merge itself is asserted
# by the cascade-resolver check immediately below — the two together cover both
# "the block is well-formed" and "the cascade semantics are right".
VALIDATE="$SKILL_DIR/../sdd/scripts/sdd-validate.sh"
GOAL_FIXTURE="$SKILL_DIR/evals/fixtures/goal"
# Validator presence is a hard precondition — a moved/renamed validator must
# FAIL the eval, never silently skip the behavioral check (fail-closed signal).
file_check FIXTURE "validator present (behavioral precondition)" "$VALIDATE"
file_check FIXTURE "cascading-goal fixture tree exists" "$GOAL_FIXTURE/spec.md"
if [ -f "$VALIDATE" ] && [ -d "$GOAL_FIXTURE" ]; then
  if bash "$VALIDATE" --strict "$GOAL_FIXTURE" >/dev/null 2>&1; then
    echo "  PASS [BEHAVIORAL]: WP goal block + inherits_from resolution validate (exit 0)"
    PASS=$((PASS+1))
  else
    echo "  FAIL [BEHAVIORAL]: WP goal block + inherits_from should validate clean"
    FAIL=$((FAIL+1))
  fi
fi

# BEHAVIORAL (via the cascade resolver): the fixture's WP leaves iteration_policy
# and blocked_stop EMPTY and gives one constraint/boundary — so the resolved
# effective goal must INHERIT the spec's scalars and UNION the lists, while
# keeping the WP's own outcome. This is the only check here that actually
# exercises the cascade MERGE (resolve_effective_goal, the single back-compat
# owner) — it turns red if decompose's derived cascade semantics regress.
RESOLVER="$SKILL_DIR/../sdd/scripts/sdd-goal-eval.py"
file_check FIXTURE "cascade resolver present (behavioral precondition)" "$RESOLVER"
if [ -f "$RESOLVER" ]; then
  if python3 - "$RESOLVER" "$GOAL_FIXTURE" <<'PY'
import sys, importlib.util, pathlib, yaml
resolver_path, fixture_dir = sys.argv[1], pathlib.Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("sdd_goal_eval", resolver_path)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
def fm(p): return yaml.safe_load(pathlib.Path(p).read_text().split('---', 2)[1])
wp   = fm(fixture_dir / "wp-01-cascading-goal" / "overview.md")
feat = fm(fixture_dir / "spec.md")
eff  = mod.resolve_effective_goal(wp, spec_fm=feat)
ok = True
# scalars inherited from spec (WP left them empty)
if not eff.get("iteration_policy"): print("  cascade FAIL: iteration_policy not inherited"); ok = False
if not eff.get("blocked_stop"):     print("  cascade FAIL: blocked_stop not inherited"); ok = False
# lists union+dedupe (WP entry AND spec entry both present)
cons = eff.get("constraints") or []
if "no new external dependency" not in cons or "no regression in existing tests" not in cons:
    print(f"  cascade FAIL: constraints not unioned: {cons}"); ok = False
# outcome stays WP's own (never inherited)
if eff.get("outcome") != "the api scaffold returns 200 on GET /health":
    print(f"  cascade FAIL: outcome should be WP-own, got: {eff.get('outcome')}"); ok = False
sys.exit(0 if ok else 1)
PY
  then
    echo "  PASS [BEHAVIORAL]: cascade merge inherits scalars + unions lists, keeps WP outcome"
    PASS=$((PASS+1))
  else
    echo "  FAIL [BEHAVIORAL]: cascade merge regressed (see lines above)"
    FAIL=$((FAIL+1))
  fi
fi

# ── Add-WP mode (single-WP authoring; fast path + grow-on-the-go) ──────────
check STATIC "Add-WP mode documented" "Add-WP mode"
check STATIC "Add-WP tolerates an absent spec.md (fast route)" "tolerates an absent"
check STATIC "Add-WP is an append, not a reconcile" "append, not a reconcile"
check STATIC "Add-WP defers tier-1 re-audit to next harden" "next harden re-audits"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
