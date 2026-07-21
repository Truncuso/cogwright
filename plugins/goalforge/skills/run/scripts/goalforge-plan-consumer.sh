#!/usr/bin/env bash
# goalforge-plan-consumer.sh — deterministic execution_plan CONSUMER (the WP-04 boundary).
#
# Reads the `execution_plan:` block from a feature overview.md frontmatter and
# turns it into an ordered list of step BATCHES (each batch = list of
# concurrently-runnable chain steps), carrying each member's dispatch mode and
# OPAQUE tier hints. The runner is a plan CONSUMER only — it NEVER invokes the
# route classifier (goalforge-route.sh) itself.
#
# task-01 (this file) owns: parse steps/dispatch/parallel/tiers, normalize
# parallel groups into batches, run the semantic-consistency validation pass,
# and expose `--emit-batches`. Later tasks layer dispatch resolution (task-02)
# and the absent-block legacy fallback (task-03) on top.
#
# task-03 adds `--route <overview.md>`: reports the effective route. An absent
# execution_plan: block falls back to the frontmatter `route:` or the canonical
# `standard` default (legacy route + when_route fallback role). An absent block
# also yields the full legacy step list, all inline, no parallel batching —
# byte-identical to the pre-plan-consumer runner.
#
# task-02 adds `--dispatch-of <step>`: resolves a single step's dispatch mode
# (inline|agent) SOLELY from the parsed plan -- the consumer's stub dispatch log.
# The runner branches on this value (agent => Agent-tool dispatch path; inline =>
# run in the runner's own context); no step re-derives its own dispatch mode
# independently of the parsed plan [D-SEAMS]. Absent-block / unspecified steps
# resolve to the legacy all-inline default.
#
# Semantic-consistency validation [D-PINS] — any violation is a HARD, non-silent
# failure (exit non-zero), never a silent fallback:
#   * every execution_plan.steps member resolves to a chain.yaml step basename
#   * the selected steps form a satisfiable, contiguous path (consecutive in
#     canonical chain order — no interior gaps, strictly increasing)
#   * every execution_plan.dispatch / .parallel key is a subset of steps
#   * steps are consistent with route (fast route ⇒ steps ⊆ fast-path steps)
#   * .tiers are captured as OPAQUE hints only — tier resolution is wp-05's;
#     confidence is intentionally NOT consulted here
#
# Usage:
#   goalforge-plan-consumer.sh --emit-batches <overview.md>
#
# --emit-batches has NO side effects: it validates then prints the batch plan.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAIN_YAML="$SCRIPT_DIR/../chain.yaml"

usage() {
  echo "usage: goalforge-plan-consumer.sh --emit-batches <overview.md>" >&2
  echo "       goalforge-plan-consumer.sh --dispatch-of <step> <overview.md>" >&2
  echo "       goalforge-plan-consumer.sh --route <overview.md>" >&2
  exit 2
}

MODE="${1:-}"
STEP=""
case "$MODE" in
  --emit-batches)
    OVERVIEW="${2:-}"
    ;;
  --dispatch-of)
    STEP="${2:-}"
    OVERVIEW="${3:-}"
    [ -n "$STEP" ] || usage
    ;;
  --route)
    OVERVIEW="${2:-}"
    ;;
  *)
    usage
    ;;
esac
[ -n "$OVERVIEW" ] || usage
[ -f "$OVERVIEW" ] || { echo "goalforge-plan-consumer: overview not found: $OVERVIEW" >&2; exit 1; }
[ -f "$CHAIN_YAML" ] || { echo "goalforge-plan-consumer: chain.yaml not found: $CHAIN_YAML" >&2; exit 1; }

# The python core does frontmatter + chain parse, validation, and batch
# normalization. It emits one `batch N: a[,b,...]` line per batch on success,
# or a single clear error line to stderr + non-zero exit on any violation.
python3 - "$CHAIN_YAML" "$OVERVIEW" "$MODE" "$STEP" <<'PY'
import sys, re, yaml

chain_path, overview_path, mode = sys.argv[1], sys.argv[2], sys.argv[3]
step_arg = sys.argv[4] if len(sys.argv) > 4 else ""

# dispatch values the plan may declare; the runner honors ONLY these.
VALID_DISPATCH = {"inline", "agent"}

def die(msg, code=3):
    sys.stderr.write(f"goalforge-plan-consumer: {msg}\n")
    sys.exit(code)

# --- canonical chain step basenames, in order ---
try:
    chain = yaml.safe_load(open(chain_path)) or {}
except Exception as e:
    die(f"failed to parse chain.yaml: {e}", 1)
chain_steps = []
for step in (chain.get("steps") or []):
    skill = (step or {}).get("skill")
    if skill:
        chain_steps.append(skill.split("/")[-1])
if not chain_steps:
    die("no steps found in chain.yaml", 1)
chain_index = {name: i for i, name in enumerate(chain_steps)}

# fast-path steps (route: fast has no spec.md and replaces harden with gates)
FAST_STEPS = {"capture", "decompose", "execute", "verify"}

# --- read frontmatter from overview.md ---
text = open(overview_path).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
if not m:
    die(f"no YAML frontmatter found in {overview_path}", 1)
try:
    fm = yaml.safe_load(m.group(1)) or {}
except Exception as e:
    die(f"failed to parse frontmatter: {e}", 1)

route = fm.get("route")            # may be None => standard (legacy fallback; all steps allowed)
plan = fm.get("execution_plan")

# --- --route: report the effective route (task-03).
# block-absent => legacy route + when_route fallback: the frontmatter `route:`,
# or the canonical `standard` default when unset. block-present => steps are the
# sole authority, but the reported route is still the frontmatter value (or the
# `standard` default). when_route is retired to this fallback-only role.
if mode == "--route":
    print(route if route else "standard")
    sys.exit(0)

# --- absent block: legacy fallback (standard route, all-inline). ---
# Full legacy step list, one step per batch (all inline, no parallel batching),
# byte-identical to the pre-plan-consumer runner behavior.
if plan is None:
    if mode == "--dispatch-of":
        if step_arg not in chain_index:
            die(f"--dispatch-of step '{step_arg}' does not resolve to a chain.yaml step basename", 3)
        # legacy fallback is all-inline
        print("inline")
        sys.exit(0)
    for i, name in enumerate(chain_steps, 1):
        print(f"batch {i}: {name}")
    sys.exit(0)

if not isinstance(plan, dict):
    die("execution_plan: block is malformed (expected a mapping)", 3)

steps = plan.get("steps")
if not isinstance(steps, list) or not steps or not all(isinstance(s, str) for s in steps):
    die("execution_plan.steps must be a non-empty list of step names", 3)

dispatch = plan.get("dispatch") or {}
parallel = plan.get("parallel")
tiers = plan.get("tiers") or {}     # OPAQUE hints — parsed, never resolved here
if not isinstance(dispatch, dict):
    die("execution_plan.dispatch must be a mapping", 3)
if not isinstance(tiers, dict):
    die("execution_plan.tiers must be a mapping", 3)

# --- validation: every steps member resolves to a chain basename ---
for s in steps:
    if s not in chain_index:
        die(f"execution_plan.steps member '{s}' does not resolve to a chain.yaml step basename", 3)

# --- validation: satisfiable, contiguous path (consecutive in chain order) ---
idxs = [chain_index[s] for s in steps]
for a, b in zip(idxs, idxs[1:]):
    if b != a + 1:
        die(f"execution_plan.steps is not a contiguous/satisfiable path "
            f"(canonical order gap between '{chain_steps[a]}' and '{chain_steps[b]}')", 3)

steps_set = set(steps)

# --- validation: dispatch keys ⊆ steps, values ∈ {inline, agent} ---
for k, v in dispatch.items():
    if k not in steps_set:
        die(f"execution_plan.dispatch names step '{k}' absent from steps", 3)
    if v not in VALID_DISPATCH:
        die(f"execution_plan.dispatch['{k}'] = '{v}' is not one of {sorted(VALID_DISPATCH)}", 3)

# --- validation: parallel members ⊆ steps ---
if parallel is not None:
    if not isinstance(parallel, list):
        die("execution_plan.parallel must be a list of groups", 3)
    for grp in parallel:
        if not isinstance(grp, list) or not grp:
            die("each execution_plan.parallel group must be a non-empty list", 3)
        for member in grp:
            if member not in steps_set:
                die(f"execution_plan.parallel names step '{member}' absent from steps", 3)
    # partition: parallel groups must COVER every steps member exactly once.
    # Without this a group can silently omit a step (dropped from execution) or
    # duplicate one across groups (dispatched twice), or parallel: [] can drop
    # ALL steps — every such case is a HARD, non-silent failure [D-PINS].
    flat = [member for grp in parallel for member in grp]
    dupes = sorted({m for m in flat if flat.count(m) > 1})
    if dupes:
        die(f"execution_plan.parallel duplicates step(s) {dupes} across groups "
            f"(each steps member must appear in exactly one group)", 3)
    uncovered = sorted(steps_set - set(flat))
    if uncovered:
        die(f"execution_plan.parallel omits step(s) {uncovered} "
            f"(parallel groups must cover every steps member)", 3)

# --- validation: steps consistent with route ---
if route == "fast":
    bad = steps_set - FAST_STEPS
    if bad:
        die(f"route: fast is inconsistent with steps {sorted(bad)} (not fast-path steps)", 3)

# --- --dispatch-of: resolve one step's dispatch mode from the parsed plan ---
# Resolution reads ONLY the parsed plan: dispatch.get(step) with the legacy
# all-inline default. No step re-derives its own mode independently [D-SEAMS].
if mode == "--dispatch-of":
    if step_arg not in steps_set:
        die(f"--dispatch-of step '{step_arg}' is not a selected execution_plan.steps member", 3)
    print(dispatch.get(step_arg, "inline"))
    sys.exit(0)

# --- normalize parallel groups into ordered batches ---
if parallel is not None:
    batches = [list(grp) for grp in parallel]
else:
    batches = [[s] for s in steps]   # no parallel => one step per batch, in order

for i, batch in enumerate(batches, 1):
    print(f"batch {i}: {','.join(batch)}")
PY
