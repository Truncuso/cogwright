#!/usr/bin/env bash
# evals/data-contract/run.sh — wp-11 plan-index.json data-contract fixtures.
#
# Proves the index-only contract (event log is OUT OF SCOPE, cut 2026-07-13):
#   (a) byte-identical plan-index.json across two runs over an unchanged root
#   (b) schema-valid output (all documented fields present + correctly typed)
#   (c) a feature with 2+ WPs and a cross-WP depends_on edge round-trips it
#   (d) the generator run with --self-test exits 0
set -euo pipefail

: "${COGWRIGHT_ROOT:=$HOME/10_projects/cogwright}"
GEN="$COGWRIGHT_ROOT/plugins/goalforge/scripts/goalforge-plan-index-json"
EVAL_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURE_ROOT="$EVAL_DIR/fixtures"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== goalforge data-contract: plan-index.json fixtures ==="

if [ ! -x "$GEN" ] && ! command -v python3 >/dev/null 2>&1; then
  fail "generator not executable and python3 unavailable: $GEN"
  echo ""; echo "Results: $PASS passed, $FAIL failed"; exit 1
fi

# Interpreter-agnostic invocation: prefer the shebang-executable path directly,
# fall back to python3 for sandboxes whose allowlist blocks the bare name.
run_gen() {
  # exec-bit is part of the contract (goal check d: shebang-executable); python3 stays
  # only as a sandbox-allowlist workaround and must never mask a missing exec bit.
  [ -x "$GEN" ] || { echo "FAIL: generator not executable: $GEN" >&2; exit 1; }
  if "$GEN" --help >/dev/null 2>&1; then "$GEN" "$@"; else python3 "$GEN" "$@"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── (a) idempotency: two runs over the unchanged fixture root, byte-identical ──
run_gen --plans-root "$FIXTURE_ROOT" -o "$TMP/run1.json" >/dev/null 2>&1
run_gen --plans-root "$FIXTURE_ROOT" -o "$TMP/run2.json" >/dev/null 2>&1
if [ -f "$TMP/run1.json" ] && cmp -s "$TMP/run1.json" "$TMP/run2.json"; then
  pass "byte-identical plan-index.json across two runs (idempotency)"
else
  fail "plan-index.json differs between runs (or was not written)"
fi

# ── (b) schema + (c) cross-WP depends_on round-trip (single python assertion) ─
if python3 - "$TMP/run1.json" <<'PY'
import json, sys
idx = json.load(open(sys.argv[1]))
assert isinstance(idx["schema_version"], int), "schema_version not int"
assert isinstance(idx["generated_from"], str), "generated_from not str"
assert isinstance(idx["features"], list) and idx["features"], "features empty"
feat = next(f for f in idx["features"] if f["name"] == "tmpfeat")
assert isinstance(feat["status"], str)
assert feat["route"] == "standard", f'feature route projected wrong: {feat["route"]}'
wps = {w["id"]: w for w in feat["wps"]}
assert len(wps) == 2, f"expected 2 WPs, got {len(wps)}"
for w in wps.values():
    assert isinstance(w["id"], str)
    assert isinstance(w["status"], str)
    assert isinstance(w["depends_on"], list)
    assert isinstance(w["goal_digest"], str)
    assert isinstance(w["tasks"], list)
    for t in w["tasks"]:
        assert isinstance(t["id"], str)
        assert isinstance(t["status"], str)
        assert isinstance(t["task_route"], str)
        assert "route" not in t, "task node must use task_route, never route"
# cross-WP depends_on round-trips unchanged
assert wps["wp-02-beta"]["depends_on"] == ["wp-01-alpha"], wps["wp-02-beta"]["depends_on"]
assert wps["wp-01-alpha"]["depends_on"] == []
# goal_digest populated (12-hex) for a WP carrying a goal block
gd = wps["wp-01-alpha"]["goal_digest"]
assert len(gd) == 12 and all(c in "0123456789abcdef" for c in gd), f"bad goal_digest: {gd!r}"
# task nodes present with task_route
troutes = sorted(t["task_route"] for t in wps["wp-02-beta"]["tasks"])
assert troutes == ["api", "code"], troutes
PY
then
  pass "schema-valid output (fields present + typed)"
  pass "cross-WP depends_on edge round-trips unchanged"
else
  fail "schema validation / depends_on round-trip failed"
fi

# ── (d) generator --self-test exits 0 ─────────────────────────────────────────
if run_gen --self-test >/dev/null 2>&1; then
  pass "generator --self-test exits 0"
else
  fail "generator --self-test did not exit 0"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
