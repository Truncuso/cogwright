#!/usr/bin/env bash
# run.sh — deterministic eval suite for the goalforge workflow-authoring skill
# (capture a completed goalforge-chain run into a NAMED declarative execution_plan
# route the runner consumes UNMODIFIED).
#
# Drives the REAL pipeline end-to-end over a declarative fixture trace:
#   distill (workflow-authoring/scripts/distill)  — step-graph from the trace,
#   render  (workflow-authoring/scripts/render)   — named execution_plan route,
#   goalforge-plan-consumer.sh (run/scripts/…)    — the UNMODIFIED consumer.
# No live model calls, no Workflow tool, no network — purely offline shell/python.
#
# Cases (WP goal.verification a-g):
#   (a) the skill emits a named declarative execution_plan route file (name,
#       ordered steps ⊆ chain.yaml basenames, per-step dispatch, parallel groups,
#       opaque tiers, provenance pointer)
#   (b) the emitted route includes a Mermaid step-graph from the same step graph
#   (c) the emitted execution_plan block, loaded on a fixture feature overview.md,
#       drives through goalforge-plan-consumer.sh --emit-batches UNMODIFIED and
#       selects the captured steps/dispatch/parallel groups (the round-trip)
#   (d) byte-determinism — the route + Mermaid strip ALL non-deterministic fields
#       (seq, ts, session, model, provider, agent) and two runs are byte-identical
#   (e) the goalforge-trace-read helper honours the wp-14 read contract — a torn
#       trailing line is skipped and schema_version selects the parse branch
#   (f) all fixtures are declarative artifacts only — the harness NEVER invokes
#       the Workflow tool (nor any network / model call)
#   (g) run.sh --self-test exits 0 (the component self-tests hold)
#
# Exit 0 only when every assertion passes; prints the first failure otherwise.
set -uo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOALFORGE="$(cd "$SUITE_DIR/../.." && pwd)"
DISTILL="$GOALFORGE/workflow-authoring/scripts/distill"
RENDER="$GOALFORGE/workflow-authoring/scripts/render"
HELPER="$GOALFORGE/scripts/goalforge-trace-read"
CONSUMER="$GOALFORGE/run/scripts/goalforge-plan-consumer.sh"
FIX="$SUITE_DIR/fixtures"
TRACE="$FIX/completed-chain/trace-events.jsonl"

fail=0
pass()  { printf 'PASS  %s\n' "$1"; }
fault() { printf 'FAIL  %s\n' "$1" >&2; fail=1; }

assert_eq() {   # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then pass "$1"; else
    fault "$1"; printf '        expected: %q\n        actual:   %q\n' "$2" "$3" >&2
  fi
}
assert_ok() {   # <label> <rc>
  if [ "$2" -eq 0 ]; then pass "$1"; else fault "$1 (rc=$2)"; fi
}
assert_absent() {  # <label> <string> (fail if non-empty)
  if [ -z "$2" ]; then pass "$1"; else
    fault "$1"; printf '        found: %s\n' "$2" >&2
  fi
}

for f in "$DISTILL" "$RENDER" "$HELPER" "$CONSUMER" "$TRACE"; do
  [ -e "$f" ] || { echo "run.sh: required path missing: $f" >&2; exit 1; }
done

# ─────────────────────────────────────────────────────────────────────────────
# --self-test: assert the component self-tests hold (case g).
# ─────────────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--self-test" ]; then
  echo "=== workflow-authoring eval — self-test (component invariants) ==="
  python3 "$HELPER" --self-test  >/dev/null 2>&1; assert_ok "(g) goalforge-trace-read --self-test" $?
  python3 "$DISTILL" --self-test >/dev/null 2>&1; assert_ok "(g) distill --self-test" $?
  python3 "$RENDER" --self-test  >/dev/null 2>&1; assert_ok "(g) render --self-test" $?
  echo "---"
  if [ "$fail" -eq 0 ]; then echo "workflow-authoring self-test: ALL PASS"; exit 0
  else echo "workflow-authoring self-test: FAILURES above" >&2; exit 1; fi
fi

echo "=== workflow-authoring eval suite (cases a-g) ==="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ─────────────────────────────────────────────────────────────────────────────
# (a) emit a named declarative execution_plan route file from the fixture trace.
# ─────────────────────────────────────────────────────────────────────────────
python3 "$RENDER" --trace "$TRACE" --name captured-eval --out-dir "$TMP" >/dev/null 2>"$TMP/render.err"
ROUTE="$TMP/captured-eval.md"
assert_ok "(a) render --trace emits a route file" $([ -f "$ROUTE" ] && echo 0 || echo 1)
assert_ok "(a) route carries an execution_plan: block" \
  $(grep -q '^execution_plan:' "$ROUTE" && echo 0 || echo 1)
assert_ok "(a) route carries a name: field" \
  $(grep -q '^name: captured-eval$' "$ROUTE" && echo 0 || echo 1)
assert_ok "(a) route carries a provenance: pointer to the trace" \
  $(grep -q '^provenance: completed-chain/trace-events.jsonl$' "$ROUTE" && echo 0 || echo 1)
assert_ok "(a) route carries an opaque tiers map" \
  $(grep -q 'tiers: {}' "$ROUTE" && echo 0 || echo 1)

# ─────────────────────────────────────────────────────────────────────────────
# (b) the route includes a Mermaid step-graph derived from the same step graph.
# ─────────────────────────────────────────────────────────────────────────────
assert_ok "(b) route includes a mermaid fence" \
  $(grep -q '```mermaid' "$ROUTE" && echo 0 || echo 1)
assert_ok "(b) mermaid is a flowchart step-graph" \
  $(grep -q 'flowchart TD' "$ROUTE" && echo 0 || echo 1)
assert_ok "(b) mermaid labels the captured dispatch modes" \
  $(grep -q 'execute (agent)' "$ROUTE" && grep -q 'harden (inline)' "$ROUTE" && echo 0 || echo 1)
assert_ok "(b) mermaid carries the batch-to-batch edges" \
  $(grep -q 'harden --> execute' "$ROUTE" && grep -q 'execute --> verify' "$ROUTE" && echo 0 || echo 1)

# ─────────────────────────────────────────────────────────────────────────────
# (c) round-trip: the emitted route loads UNMODIFIED through the consumer as a
#     feature overview.md frontmatter, selecting the captured batches.
# ─────────────────────────────────────────────────────────────────────────────
# The route file's YAML frontmatter IS a valid feature overview frontmatter for
# the consumer (execution_plan: block present); copy it UNMODIFIED to overview.md.
cp "$ROUTE" "$TMP/overview.md"
c_out="$(bash "$CONSUMER" --emit-batches "$TMP/overview.md" 2>"$TMP/consumer.err")"; c_rc=$?
assert_eq "(c) consumer accepts the emitted route (exit 0)" "0" "$c_rc"
assert_eq "(c) round-trip selects 3 singleton batches" "3" "$(echo "$c_out" | grep -c '^batch ')"
assert_eq "(c) batch 1 = harden"  "batch 1: harden"  "$(echo "$c_out" | sed -n '1p')"
assert_eq "(c) batch 2 = execute" "batch 2: execute" "$(echo "$c_out" | sed -n '2p')"
assert_eq "(c) batch 3 = verify"  "batch 3: verify"  "$(echo "$c_out" | sed -n '3p')"
# dispatch modes survive the round-trip verbatim from the captured trace.
assert_eq "(c) dispatch harden => inline"  "inline" "$(bash "$CONSUMER" --dispatch-of harden  "$TMP/overview.md")"
assert_eq "(c) dispatch execute => agent"  "agent"  "$(bash "$CONSUMER" --dispatch-of execute "$TMP/overview.md")"
assert_eq "(c) dispatch verify => inline"  "inline" "$(bash "$CONSUMER" --dispatch-of verify  "$TMP/overview.md")"

# ─────────────────────────────────────────────────────────────────────────────
# (d) byte-determinism: two captures over the same trace are byte-identical, and
#     the route strips ALL non-deterministic trace fields.
# ─────────────────────────────────────────────────────────────────────────────
python3 "$RENDER" --trace "$TRACE" --name captured-eval --stdout > "$TMP/r1" 2>/dev/null
python3 "$RENDER" --trace "$TRACE" --name captured-eval --stdout > "$TMP/r2" 2>/dev/null
if cmp -s "$TMP/r1" "$TMP/r2"; then pass "(d) two renders byte-identical"; else fault "(d) two renders differ"; fi
# The step-graph itself is byte-identical across two distils.
python3 "$DISTILL" --trace "$TRACE" > "$TMP/g1" 2>/dev/null
python3 "$DISTILL" --trace "$TRACE" > "$TMP/g2" 2>/dev/null
if cmp -s "$TMP/g1" "$TMP/g2"; then pass "(d) two distils byte-identical"; else fault "(d) two distils differ"; fi
# No stripped non-deterministic field leaks into the emitted route.
LEAK="$(grep -Eo '80ec009c|implementer|anthropic|"seq"|09:00:00|schema_version' "$ROUTE" || true)"
assert_absent "(d) no non-deterministic field (session/agent-id/provider/model/seq/ts/schema) leaks into route" "$LEAK"

# ─────────────────────────────────────────────────────────────────────────────
# (e) the shared goalforge-trace-read helper honours the wp-14 read contract.
# ─────────────────────────────────────────────────────────────────────────────
python3 "$HELPER" --self-test >/dev/null 2>&1; assert_ok "(e) goalforge-trace-read --self-test (torn-tail + schema_version)" $?
# End-to-end proof over THIS fixture: the trace ends in a torn trailing line, yet
# the distiller (via the helper) still recovers exactly the 3 chain steps.
e_steps="$(python3 "$DISTILL" --trace "$TRACE" 2>/dev/null | grep -o '"steps":\[[^]]*\]')"
assert_eq "(e) torn-tail fixture still distils the 3 steps" '"steps":["harden","execute","verify"]' "$e_steps"

# ─────────────────────────────────────────────────────────────────────────────
# (f) declarative-only: the harness + fixtures NEVER invoke the Workflow tool,
#     the Anthropic API, or any network / live-model call.
# ─────────────────────────────────────────────────────────────────────────────
# Scoped to the fixture tree (the declarative artifacts). Match invocation
# patterns only — the fixture legitimately carries "anthropic" as a captured
# provider VALUE (data, not a call), which none of these patterns match.
FORBID='api\.anthropic|curl |wget |claude -p|WorkflowRun|Workflow tool|messages\.create|--dangerously'
WF_HITS="$(grep -REl "$FORBID" "$FIX" 2>/dev/null || true)"
assert_absent "(f) all fixtures are declarative — no Workflow-tool / network / model-call invocation" "$WF_HITS"
# The captured route also carries no live-invocation directive.
assert_absent "(f) emitted route is a declarative artifact (no invocation)" \
  "$(grep -REl "$FORBID" "$TMP/captured-eval.md" 2>/dev/null || true)"

echo "---"
if [ "$fail" -eq 0 ]; then
  echo "workflow-authoring eval suite: ALL PASS"
  exit 0
else
  echo "workflow-authoring eval suite: FAILURES above" >&2
  exit 1
fi
