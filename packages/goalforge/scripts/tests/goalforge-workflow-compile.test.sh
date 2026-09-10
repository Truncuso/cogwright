#!/usr/bin/env bash
# goalforge-workflow-compile.test.sh — b3 sabotage pair for the checklist ->
# Workflow-script compiler (scripts/goalforge-workflow-compile.py).
#
#   known-good : scripts/tests/fixtures/dispatch/wp-compile.md (11 items, three
#                {files:} groups; A and B disjoint, C overlaps A, parallel: true)
#                compiles to two parallel nodes of 3-5 items, one pipeline stage
#                after them, gates B/C and one second-opinion node carrying the
#                fixture dispatch file's model/effort (gate A is deterministic:
#                a log() line naming goal.verification.command, never an agent),
#                a script that opens with
#                `export const meta`, calls only agent|parallel|pipeline|phase|log,
#                and parses as ESM.
#   known-bad  : (1) a mktemp copy of the fixture whose overlapping {files:} set
#                is made disjoint MUST change the compiled graph;
#                (2) a compiled script with a forbidden call MUST fail the
#                allowed-call assertion;
#                (3) malformed YAML frontmatter MUST exit 2, the documented
#                code, not crash with an uncaught parser error.
#
# TOOL REQUIREMENT (deliberately NOT the skip-on-absent pattern run.sh uses for
# ruff): the parse check is the only oracle for "this is real JS", so with
# neither node nor bun on PATH this file exits 2 instead of passing.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPILE="$SD/../goalforge-workflow-compile.py"
FIXTURES="$SD/fixtures/dispatch"
WP_FIXTURE="$FIXTURES/wp-compile.md"
DISPATCH="$FIXTURES/dispatch-default.yaml"
REAL_WP="$SD/../../../../plans/goalforge-overhaul/wp-03-dispatch-routing/overview.md"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if command -v node >/dev/null 2>&1; then
    PARSER="node"
elif command -v bun >/dev/null 2>&1; then
    PARSER="bun"
else
    echo "goalforge-workflow-compile.test.sh: neither node nor bun on PATH;" \
         "the b3 parse check cannot run. Install one — this is a requirement," \
         "not a skip." >&2
    exit 2
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

parse_check() { # $1 = script path
    local m="$T/parse-$RANDOM.mjs"
    cp "$1" "$m"
    if [ "$PARSER" = "node" ]; then
        node --check "$m" >/dev/null 2>&1
    else
        bun build --no-bundle "$m" >/dev/null 2>&1
    fi
}

# Every identifier immediately followed by `(`, outside string literals and
# line comments, must be one of these five. The whitelist is the emitted
# script's whole call vocabulary — the compiler emits no control flow, no
# built-ins, and no imports, so nothing else is legal.
allowed_calls() { # $1 = script path -> prints offending identifiers
    python3 - "$1" <<'PY'
import re, sys
ALLOWED = {"agent", "parallel", "pipeline", "phase", "log"}
src = open(sys.argv[1], encoding="utf-8").read()
src = re.sub(r'"(?:\\.|[^"\\])*"', '""', src)   # drop string literals
src = src.replace("export default", "")         # a keyword, not a call
src = re.sub(r'//[^\n]*', '', src)              # drop line comments
names = set(re.findall(r'([A-Za-z_$][A-Za-z0-9_$]*)\s*\(', src))
print("\n".join(sorted(names - ALLOWED)))
PY
}

# --- known-good: compile the fixture -----------------------------------------
OUT="$T/good"
if python3 "$COMPILE" "$WP_FIXTURE" --dispatch "$DISPATCH" --out "$OUT" >"$T/stdout" 2>"$T/stderr"; then
    ok "fixture compiles (exit 0)"
else
    bad "fixture compiles (exit 0)"; cat "$T/stderr"
fi
SCRIPT="$OUT/wp-fixture-compile.js"

if [ -f "$SCRIPT" ]; then ok "wrote <wp-name>.js"; else bad "wrote <wp-name>.js"; fi
grep -q 'Workflow({scriptPath: "' "$T/stdout" \
    && ok "prints the Workflow invocation hint" \
    || bad "prints the Workflow invocation hint"

[ -f "$SCRIPT" ] || { echo; echo "goalforge-workflow-compile.test.sh: $PASS passed, $((FAIL+1)) failed"; exit 1; }

head -1 "$SCRIPT" | grep -q '^export const meta = {' \
    && ok "first line is export const meta" \
    || bad "first line is export const meta"

# --- node count and sizes ----------------------------------------------------
AGENTS=$(grep -c 'agent({' "$SCRIPT")
[ "$AGENTS" -eq 6 ] \
    && ok "6 agent nodes (3 batches + gates B/C + second opinion; gate A is deterministic)" \
    || bad "6 agent nodes (got $AGENTS)"

# gate A is a log() line naming the WP's verification command — never an agent().
grep -q 'label: "gate A"' "$SCRIPT" \
    && bad "gate A must not be an agent node (it is deterministic)" \
    || ok "gate A is not an agent node"
grep -q 'log("gate A is deterministic .* no agent node; run: bash scripts/tests/goalforge-workflow-compile.test.sh");$' "$SCRIPT" \
    && ok "gate A log() names goal.verification.command" \
    || bad "gate A log() names goal.verification.command"

BATCHES=$(grep -c 'label: "batch-' "$SCRIPT")
[ "$BATCHES" -eq 3 ] && ok "3 batch nodes (A, B, C)" || bad "3 batch nodes (got $BATCHES)"

# every batch prompt carries the resolved roster persona AND expertise bundle
PERSONAS=$(grep -c 'Persona: agents/implementer.md' "$SCRIPT")
[ "$PERSONAS" -eq "$BATCHES" ] \
    && ok "every batch prompt names the roster persona path" \
    || bad "every batch prompt names the roster persona path (got $PERSONAS of $BATCHES)"
REFS=$(grep -c 'Expertise refs: rules/common/coding-style.md' "$SCRIPT")
[ "$REFS" -eq "$BATCHES" ] \
    && ok "every batch prompt names the resolved expertise refs" \
    || bad "every batch prompt names the resolved expertise refs (got $REFS of $BATCHES)"

SIZES=$(grep -o '\[[0-9]* items\]' "$SCRIPT" | grep -o '[0-9]*')
BADSIZE=0
for s in $SIZES; do [ "$s" -ge 3 ] && [ "$s" -le 5 ] || BADSIZE=1; done
[ "$BADSIZE" -eq 0 ] && ok "every node size within 3-5 ($(echo "$SIZES" | tr '\n' ' '))" \
                     || bad "every node size within 3-5 ($(echo "$SIZES" | tr '\n' ' '))"

# --- edge kinds --------------------------------------------------------------
grep -q 'parallel(\[' "$SCRIPT" && ok "emits parallel([" || bad "emits parallel(["
grep -q 'return pipeline(' "$SCRIPT" && ok "emits pipeline(" || bad "emits pipeline("

PAR_LINE=$(grep -n 'parallel(\[' "$SCRIPT" | head -1 | cut -d: -f1)
C_LINE=$(grep -n 'label: "batch-3' "$SCRIPT" | head -1 | cut -d: -f1)
if [ -n "$PAR_LINE" ] && [ -n "$C_LINE" ] && [ "$C_LINE" -gt "$PAR_LINE" ]; then
    ok "overlapping group C is a pipeline stage after the parallel stage"
else
    bad "overlapping group C is a pipeline stage after the parallel stage"
fi

# --- gates carry the fixture's model/effort ----------------------------------
gate_row() { grep -o "label: \"$1\", phase: \"gates\", model: \"[a-z]*\", effort: \"[a-z]*\"" "$SCRIPT"; }
check_gate() { # $1 label $2 model $3 effort
    if [ "$(gate_row "$1")" = "label: \"$1\", phase: \"gates\", model: \"$2\", effort: \"$3\"" ]; then
        ok "$1 node at $2/$3 from the dispatch fixture"
    else
        bad "$1 node at $2/$3 from the dispatch fixture (got: $(gate_row "$1"))"
    fi
}
check_gate "gate B" opus high          # wp-verify row
check_gate "gate C" opus high          # judge row
check_gate "second opinion" opus low   # second_opinion row (stub provider)

# --- allowed-call assertion ---------------------------------------------------
OFFENDERS="$(allowed_calls "$SCRIPT")"
[ -z "$OFFENDERS" ] \
    && ok "calls only agent|parallel|pipeline|phase|log" \
    || bad "calls only agent|parallel|pipeline|phase|log (offenders: $(echo "$OFFENDERS" | tr '\n' ' '))"

# --- parse check --------------------------------------------------------------
parse_check "$SCRIPT" \
    && ok "compiled script parses as ESM ($PARSER)" \
    || bad "compiled script parses as ESM ($PARSER)"

# --- known-bad 1: disjointness sabotage changes the graph ---------------------
SAB_WP="$T/wp-compile-sabotage.md"
sed 's|src/alpha/\([a-z]*\)\.ts, src/gamma|src/delta/\1.ts, src/gamma|' "$WP_FIXTURE" > "$SAB_WP"
if grep -q 'src/delta/one.ts' "$SAB_WP"; then
    ok "sabotage fixture built (group C made disjoint from A)"
else
    bad "sabotage fixture built (group C made disjoint from A)"
fi
SAB_OUT="$T/sabotage"
# The graph comparison below is only meaningful if the sabotage compile SUCCEEDS
# — a failed compile writes no file and would "differ" for the wrong reason.
if python3 "$COMPILE" "$SAB_WP" --dispatch "$DISPATCH" --out "$SAB_OUT" >/dev/null 2>"$T/sab-stderr"; then
    ok "sabotage fixture compiles (exit 0)"
else
    bad "sabotage fixture compiles (exit 0)"; cat "$T/sab-stderr"
fi
if ! diff -q "$SCRIPT" "$SAB_OUT/wp-fixture-compile.js" >/dev/null 2>&1; then
    ok "breaking {files:} disjointness changes the compiled graph"
else
    bad "breaking {files:} disjointness changes the compiled graph"
fi
SAB_C_LINE=$(grep -n 'label: "batch-3' "$SAB_OUT/wp-fixture-compile.js" | head -1 | cut -d: -f1)
SAB_PAR_END=$(grep -n '^    \]),' "$SAB_OUT/wp-fixture-compile.js" | head -1 | cut -d: -f1)
if [ -n "$SAB_C_LINE" ] && [ -n "$SAB_PAR_END" ] && [ "$SAB_C_LINE" -lt "$SAB_PAR_END" ]; then
    ok "with no overlap all three nodes land in ONE parallel stage"
else
    bad "with no overlap all three nodes land in ONE parallel stage"
fi

# --- known-bad 2: a forbidden call fails the allowed-call assertion -----------
FORBIDDEN="$T/forbidden.js"
sed 's|  return pipeline(|  fetch("http://example.invalid");\n  return pipeline(|' "$SCRIPT" > "$FORBIDDEN"
if [ -n "$(allowed_calls "$FORBIDDEN")" ]; then
    ok "a forbidden call is caught by the allowed-call assertion"
else
    bad "a forbidden call is caught by the allowed-call assertion"
fi

# --- smoke: the real wp-03 overview compiles (never into run/workflows/) ------
if [ -f "$REAL_WP" ]; then
    if python3 "$COMPILE" "$REAL_WP" --out "$T/real" >/dev/null 2>&1; then
        ok "real wp-03 overview compiles into a temp dir"
    else
        bad "real wp-03 overview compiles into a temp dir"
    fi
    parse_check "$T/real/wp-03-dispatch-routing.js" \
        && ok "real wp-03 compiled script parses as ESM" \
        || bad "real wp-03 compiled script parses as ESM"
else
    # Not a pass: the oracle did not run. Counted as neither pass nor fail.
    echo "  SKIP: real wp-03 overview absent ($REAL_WP) — smoke case not run"
fi

# --- known-bad 3: malformed frontmatter exits 2 (documented code), not 1 ------
BADFM="$T/wp-bad-frontmatter.md"
{ echo '---'; echo 'name: wp-bad'; echo 'owned_files: [unclosed'; echo '---';
  echo; echo '## Checklist'; } > "$BADFM"
python3 "$COMPILE" "$BADFM" --dispatch "$DISPATCH" --out "$T/badfm" >/dev/null 2>"$T/badfm.err"
BADFM_EXIT=$?
if [ "$BADFM_EXIT" -eq 2 ] && grep -q 'malformed YAML frontmatter' "$T/badfm.err"; then
    ok "malformed frontmatter -> exit 2 with a stderr message"
else
    bad "malformed frontmatter -> exit 2 with a stderr message (exit $BADFM_EXIT)"
    cat "$T/badfm.err"
fi

echo
echo "goalforge-workflow-compile.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
