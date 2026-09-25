#!/usr/bin/env bash
# goalforge-workflow-compile.test.sh — b3 sabotage pair for the checklist ->
# Workflow-script compiler (scripts/goalforge-workflow-compile.py).
#
#   known-good : scripts/tests/fixtures/dispatch/wp-compile.md (11 items, three
#                {files:} groups; A and B disjoint, C overlaps A, parallel: true)
#                compiles to two parallel nodes of 3-5 items, one pipeline stage
#                after them, and gates B/C carrying the fixture dispatch file's
#                model/effort. Gate A and the SECOND OPINION are deterministic
#                legs: log() lines naming goal.verification.command and
#                scripts/goalforge-second-opinion.sh, never agent() nodes — so
#                no agent node carries a non-Claude model id (the second
#                opinion's row runs on a non-native provider). The script opens
#                with `export const meta`, calls only
#                agent|parallel|pipeline|phase|log, and parses as ESM.
#   known-bad  : (1) a mktemp copy of the fixture whose overlapping {files:} set
#                is made disjoint MUST change the compiled graph;
#                (2) a compiled script with a forbidden call MUST fail the
#                allowed-call assertion;
#                (3) malformed YAML frontmatter MUST exit 2, the documented
#                code, not crash with an uncaught parser error;
#                (4) an EMPTY --expertise map MUST empty the emitted
#                "Expertise refs:" line — proof the compiler reads the seam and
#                not the live, sibling-owned references/expertise-map.yaml; a
#                missing --expertise path MUST exit 2.
#
# Every model/effort and expertise value comes from a fixture under
# fixtures/dispatch/ — never from references/dispatch.yaml or
# references/expertise-map.yaml, which other work packages own and rewrite.
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
EXPERTISE="$FIXTURES/expertise-compile.yaml"
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

# Hermetic environment for EVERY compile, wrapper and installer invocation
# (wp-08, G3r5): a fresh empty home (git reads global config from HOME and
# XDG_CONFIG_HOME, which survive the compiler's GIT_* scrub), a pinned leaf
# root, and a temp dispatch ledger — no case reads or writes host state.
export HOME="$T/home"
export XDG_CONFIG_HOME="$T/home/.config"
export CLAUDE_CONFIG_DIR="$T/cfg"
export GOALFORGE_DISPATCH_LEDGER="$T/ledger/dispatch-decisions.jsonl"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$CLAUDE_CONFIG_DIR"

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
if python3 "$COMPILE" "$WP_FIXTURE" --dispatch "$DISPATCH" --expertise "$EXPERTISE" --out "$OUT" >"$T/stdout" 2>"$T/stderr"; then
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
[ "$AGENTS" -eq 5 ] \
    && ok "5 agent nodes (3 batches + gates B/C; gate A and the second opinion are deterministic legs)" \
    || bad "5 agent nodes (got $AGENTS)"

# gate A is a log() line naming the WP's verification command — never an agent().
grep -q 'label: "gate A"' "$SCRIPT" \
    && bad "gate A must not be an agent node (it is deterministic)" \
    || ok "gate A is not an agent node"
grep -q 'log("gate A is deterministic .* no agent node; run: bash scripts/tests/goalforge-workflow-compile.test.sh");$' "$SCRIPT" \
    && ok "gate A log() names goal.verification.command" \
    || bad "gate A log() names goal.verification.command"

# N2: the second opinion is a leaf leg, not an agent node — its dispatch row
# runs on a non-native provider, so its `model` is a PROVIDER model id.
grep -q 'label: "second opinion"' "$SCRIPT" \
    && bad "the second opinion must not be an agent node (non-native provider model)" \
    || ok "the second opinion is not an agent node"
grep -q 'log("the second opinion is a leaf leg .* no agent node; run: scripts/goalforge-second-opinion.sh' "$SCRIPT" \
    && ok "second-opinion log() names scripts/goalforge-second-opinion.sh" \
    || bad "second-opinion log() names scripts/goalforge-second-opinion.sh"

# N2 INVARIANT: no agent node in a compiled script carries a non-Claude model
# id. The allowed set is the Claude tier vocabulary the Agent/Workflow tool
# dispatches natively; anything else (e.g. `glm-5.3:cloud`) is undispatchable.
non_claude_models() { # $1 = compiled script -> prints offending model literals
    grep -o 'agent({[^}]*model: "[^"]*"' "$1" \
        | grep -o 'model: "[^"]*"' | sort -u \
        | grep -vE 'model: "(sonnet|opus|haiku|fable)"' || true
}
assert_claude_models() { # $1 = script  $2 = label
    local offenders
    offenders="$(non_claude_models "$1")"
    if [ -z "$offenders" ]; then
        ok "no agent node carries a non-Claude model id ($2)"
    else
        bad "no agent node carries a non-Claude model id ($2; offenders: $(echo "$offenders" | tr '\n' ' '))"
    fi
}
assert_claude_models "$SCRIPT" "fixture dispatch"

# --- the SHIPPED references/dispatch.yaml — present in EVERY clone (R3-2) -----
# The hermetic fixture's rows are all native, so the assertion above cannot
# fail on it. The production config is where a real provider model id lives
# (the second_opinion row), and references/dispatch.yaml ships inside the
# package — so this run happens in a tree with no plans/ too. It is the one
# case here whose input is a live file rather than a fixture; that file is
# wp-03-owned package config, not the plans/ tree, so it changes only when this
# WP changes it.
SHIPPED_DISPATCH="$SD/../../references/dispatch.yaml"
if python3 "$COMPILE" "$WP_FIXTURE" --dispatch "$SHIPPED_DISPATCH" \
        --expertise "$EXPERTISE" --out "$T/shipped" >/dev/null 2>"$T/shipped.err"; then
    ok "the fixture WP compiles against the shipped references/dispatch.yaml"
    assert_claude_models "$T/shipped/wp-fixture-compile.js" "shipped references/dispatch.yaml"
else
    bad "the fixture WP compiles against the shipped references/dispatch.yaml"
    cat "$T/shipped.err"
fi

# --- known-bad 5 (R3-1): an agent-node role on a NON-NATIVE row -> exit 2 -----
# dispatch-nonnative-implement.yaml puts the `implement` row (which the
# compiler emits as agent() nodes) on the local stub provider with the
# provider-shaped model id `glm-5.3:cloud`. Before the provider-kind check the
# compiler exited 0 and emitted three agent({model: "glm-5.3:cloud"}) nodes.
# Since wp-08 a non-native implement row is decided by the SHIPPED admission
# table (empty), so the refusal names the missing admission.
NONNATIVE="$FIXTURES/dispatch-nonnative-implement.yaml"
python3 "$COMPILE" "$WP_FIXTURE" --dispatch "$NONNATIVE" --expertise "$EXPERTISE" \
    --out "$T/nonnative" >/dev/null 2>"$T/nonnative.err"
NN_EXIT=$?
NN_SCRIPT="$T/nonnative/wp-fixture-compile.js"
if [ "$NN_EXIT" -eq 2 ] && [ ! -f "$NN_SCRIPT" ] && grep -q "missing admission (" "$T/nonnative.err"; then
    ok "an agent-node role on a non-native provider row -> exit 2, nothing emitted"
else
    bad "an agent-node role on a non-native provider row -> exit 2, nothing emitted (exit $NN_EXIT)"
    cat "$T/nonnative.err"
    # If it DID compile, name the undispatchable model ids it emitted.
    [ -f "$NN_SCRIPT" ] && assert_claude_models "$NN_SCRIPT" "non-native implement row"
fi

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
if python3 "$COMPILE" "$SAB_WP" --dispatch "$DISPATCH" --expertise "$EXPERTISE" --out "$SAB_OUT" >/dev/null 2>"$T/sab-stderr"; then
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

# No case here reads the live plans/ tree. The former "real wp-03 overview"
# smoke did, with no --dispatch and no --expertise, so its three inputs were
# all mutable live state: one run in eleven reported 84/1 while a fix lap was
# rewriting overview.md and commit 5922eb7 was editing references/dispatch.yaml
# (verify round 3, 2026-09-13). A suite whose declared strategy is
# `deterministic` cannot read files another process is writing.
# Its two distinct coverages both survive hermetically above: a real-shaped WP
# compiles (wp-compile.md, 11 items in three {files:} groups) and the SHIPPED
# references/dispatch.yaml is asserted to emit only Claude model ids (the
# in-package compile + assert_claude_models pair). A snapshot fixture is NOT
# the fix: packages/goalforge/ ships publicly and plans/ prose is private.

# --- known-bad 4 (N4): the expertise map is a SEAM, not live sibling data -----
# An EMPTY --expertise map must change the emitted "Expertise refs:" line. If
# the compiler still read references/expertise-map.yaml, the line would be
# identical and this assertion would fail.
EMPTY_EXP="$T/expertise-empty.yaml"
printf 'by_extension: {}\nby_tag: {}\nby_task_type: {}\n' > "$EMPTY_EXP"
if python3 "$COMPILE" "$WP_FIXTURE" --dispatch "$DISPATCH" --expertise "$EMPTY_EXP" \
        --out "$T/noexp" >/dev/null 2>"$T/noexp.err"; then
    if grep -q 'Expertise refs: (none)' "$T/noexp/wp-fixture-compile.js" \
       && ! grep -q 'Expertise refs: rules/common/coding-style.md' "$T/noexp/wp-fixture-compile.js"; then
        ok "--expertise is the only expertise source (an empty map empties the refs line)"
    else
        bad "--expertise is the only expertise source (an empty map empties the refs line)"
        grep -o 'Expertise refs: [^\\]*' "$T/noexp/wp-fixture-compile.js" | head -1
    fi
else
    bad "--expertise is the only expertise source (compile with an empty map failed)"
    cat "$T/noexp.err"
fi

# A missing --expertise path is a usage error, not a silent empty bundle.
python3 "$COMPILE" "$WP_FIXTURE" --dispatch "$DISPATCH" \
    --expertise "$T/absent-expertise.yaml" --out "$T/absent" >/dev/null 2>"$T/absent.err"
ABSENT_EXIT=$?
if [ "$ABSENT_EXIT" -eq 2 ] && grep -q 'expertise map not found' "$T/absent.err"; then
    ok "a missing --expertise path -> exit 2, never a silent empty bundle"
else
    bad "a missing --expertise path -> exit 2, never a silent empty bundle (exit $ABSENT_EXIT)"
    cat "$T/absent.err"
fi

# --- known-bad 3: malformed frontmatter exits 2 (documented code), not 1 ------
BADFM="$T/wp-bad-frontmatter.md"
{ echo '---'; echo 'name: wp-bad'; echo 'owned_files: [unclosed'; echo '---';
  echo; echo '## Checklist'; } > "$BADFM"
python3 "$COMPILE" "$BADFM" --dispatch "$DISPATCH" --expertise "$EXPERTISE" --out "$T/badfm" >/dev/null 2>"$T/badfm.err"
BADFM_EXIT=$?
if [ "$BADFM_EXIT" -eq 2 ] && grep -q 'malformed YAML frontmatter' "$T/badfm.err"; then
    ok "malformed frontmatter -> exit 2 with a stderr message"
else
    bad "malformed frontmatter -> exit 2 with a stderr message (exit $BADFM_EXIT)"
    cat "$T/badfm.err"
fi

# =============================================================================
# wp-08 — ADMITTED execution (b1-b3, b5-b8, b10-b14)
# =============================================================================
# A non-native implement row compiles iff the DEFAULT admission table admits
# it. Every case below drives that table through the ONE in-process seam,
# `goalforge_admission.ADMITTED_PATH` (fixtures/admission/compile_seam.py),
# against a HERMETIC COMMITTED REPLICA of this package (U3): the compiler binds
# an admitting table to `git show HEAD:<path>` in a goalforge-guarded repository,
# so the admitting fixtures must be committed — in the replica, never in the
# checked-in tree, which no case writes. No case skips the HEAD binding.
PKG="$(cd "$SD/../.." && pwd)"
ADM_FX="$SD/fixtures/admission"
SEAM="$ADM_FX/compile_seam.py"
PROBE="$FIXTURES/workflow_probe.mjs"
CHECK="$FIXTURES/check_admitted.py"
# WPA (the admitted WP fixture) is the REPLICA's copy, set below: the compile
# writes its leaf brief beside it from `git show HEAD:<overview>` (H2).
D_ADM="$FIXTURES/dispatch-admitted.yaml"
LEAF_REL="skills/agent-dispatch/ollama/scripts/headless_dispatch"
KEY_TRIPLE="(code/py, ollama, glm-5.3:cloud)"
GITQ=(env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git
      -c user.name=goalforge-fixture -c user.email=fixture@example.invalid
      -c commit.gpgsign=false)

# System git config cannot be redirected once the compiler scrubs GIT_*: a set
# system core.hooksPath would turn every admitting case red for a host reason.
# FAIL loudly — never skip (G3r5).
if SYS_HP="$(env -u GIT_CONFIG_NOSYSTEM git config --system --get core.hooksPath 2>/dev/null)"; then
    echo "goalforge-workflow-compile.test.sh: system git config sets core.hooksPath" \
         "($SYS_HP); the wp-08 admitted cases cannot run hermetically. Unset it." >&2
    exit 2
fi

# The pinned leaf root: the fixture leaf under the temp CLAUDE_CONFIG_DIR.
mkdir -p "$CLAUDE_CONFIG_DIR/$(dirname "$LEAF_REL")"
cp -r "$ADM_FX/leaf/." "$CLAUDE_CONFIG_DIR/$(dirname "$LEAF_REL")/"
chmod +x "$CLAUDE_CONFIG_DIR/$LEAF_REL"
LEAF_FILE="$CLAUDE_CONFIG_DIR/$LEAF_REL"
LEAF_ORIG="$T/leaf.orig"
cp "$LEAF_FILE" "$LEAF_ORIG"

# mk_replica <dir> git|nogit — a temp copy of packages/goalforge/ whose
# canonical references/admitted-providers.yaml holds b1's admitting fixture;
# `git` also inits, commits once and installs the goalforge pre-commit.
mk_replica() {
    mkdir -p "$1"
    cp -r "$PKG/." "$1/"
    find "$1" -name __pycache__ -type d -prune -exec rm -rf {} +
    rm -rf "$1/run"
    cp "$1/scripts/tests/fixtures/admission/admitted-ok.yaml" "$1/references/admitted-providers.yaml"
    # b13 (iii): a table committed now and deleted by a later commit.
    cp "$1/scripts/tests/fixtures/admission/admitted-ok.yaml" "$1/scripts/tests/fixtures/admission/admitted-absent.yaml"
    [ "$2" = git ] || return 0
    "${GITQ[@]}" -C "$1" init -q
    "${GITQ[@]}" -C "$1" add -A
    "${GITQ[@]}" -C "$1" commit -qm "replica"
    env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        bash "$1/scripts/goalforge-install-hooks.sh" "$1" >/dev/null
}
R="$T/replica"
mk_replica "$R" git
RFX="$R/scripts/tests/fixtures/admission"
RCOMPILE="$R/scripts/goalforge-workflow-compile.py"
WPA="$R/scripts/tests/fixtures/dispatch/wp-admitted.md"
if [ -x "$R/.git/hooks/pre-commit" ] && [ -n "$("${GITQ[@]}" -C "$R" rev-parse HEAD 2>/dev/null)" ]; then
    ok "setup: committed package replica with the goalforge pre-commit installed"
else
    bad "setup: committed package replica with the goalforge pre-commit installed"
fi

# seam_compile <name> <table|-> <dispatch> [env assignments...] — runs the
# replica's compiler in-process; sets RC, writes $T/<name>.err, out $T/<name>/.
seam_compile() {
    local name="$1" table="$2" dispatch="$3"; shift 3
    env "$@" python3 "$SEAM" compile "$RCOMPILE" "$table" "$T/$name.spy" -- \
        "$WPA" --dispatch "$dispatch" --expertise "$EXPERTISE" --out "$T/$name" \
        >"$T/$name.out" 2>"$T/$name.err"
    RC=$?
}
err_has() { grep -qF -- "$2" "$T/$1.err"; }

# --- b1 / b5 / b6(ii) / b8: the admitted compile --------------------------------
rm -rf "$T/ledger"
HOST_LEDGER="$CLAUDE_CONFIG_DIR/data/dispatch-decisions.jsonl"
HOST_BEFORE="$(sha256sum "$HOST_LEDGER" 2>/dev/null || echo absent)"
seam_compile b1 "$RFX/admitted-ok.yaml" "$D_ADM"
B1_JS="$T/b1/wp-fx-admitted.js"
if [ "$RC" -eq 0 ] && [ -f "$B1_JS" ]; then
    ok "b1 admitted: compile exits 0 and writes the workflow"
else
    bad "b1 admitted: compile exits 0 and writes the workflow (rc=$RC)"; cat "$T/b1.err"
fi
if [ -f "$B1_JS" ]; then
    cp "$B1_JS" "$T/b1.mjs"
    node "$PROBE" "$T/b1.mjs" 0 >"$T/b1.probe0" 2>"$T/b1.probe0.err"
    node "$PROBE" "$T/b1.mjs" 1 >"$T/b1.probe1" 2>"$T/b1.probe1.err"
    while IFS= read -r line; do
        case "$line" in
            "ok "*)  ok "b1 ${line#ok }" ;;
            *)       bad "b1 ${line#bad }" ;;
        esac
    done < <(python3 "$CHECK" "$T/b1.probe0" "$T/b1.probe1" code/py ollama glm-5.3:cloud 2>&1)
    OFF="$(allowed_calls "$B1_JS")"
    [ -z "$OFF" ] && ok "b1 admitted script calls only agent|parallel|pipeline|phase|log" \
                  || bad "b1 admitted script calls only agent|parallel|pipeline|phase|log (offenders: $OFF)"
    parse_check "$B1_JS" && ok "b1 admitted script parses as ESM ($PARSER)" \
                         || bad "b1 admitted script parses as ESM ($PARSER)"
    assert_claude_models "$B1_JS" "admitted leg"
fi
# LEG as data, straight from the emitted file (b5 needs leaf + leaf_sha256).
leg_field() { python3 -c '
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    if line.startswith("const LEG = "):
        print(json.loads(line[len("const LEG = "):].rstrip().rstrip(";"))[sys.argv[2]])
' "$1" "$2"; }

# b5: the emitted leaf resolves under the pinned leaf root, is executable, and
# its sha256 is the one emitted.
E_LEAF="$(leg_field "$B1_JS" leaf 2>/dev/null)"
E_SHA="$(leg_field "$B1_JS" leaf_sha256 2>/dev/null)"
if [ -n "$E_LEAF" ] && [ -f "$CLAUDE_CONFIG_DIR/$E_LEAF" ] && [ -x "$CLAUDE_CONFIG_DIR/$E_LEAF" ]; then
    ok "b5 the emitted leaf exists and is executable under the pinned leaf root ($E_LEAF)"
else
    bad "b5 the emitted leaf exists and is executable under the pinned leaf root (leaf='$E_LEAF')"
fi
if [ -n "$E_SHA" ] && [ "$E_SHA" = "$(sha256sum "$CLAUDE_CONFIG_DIR/$E_LEAF" 2>/dev/null | cut -d' ' -f1)" ]; then
    ok "b5 the emitted leaf_sha256 equals sha256sum of the resolved fixture leaf"
else
    bad "b5 the emitted leaf_sha256 equals sha256sum of the resolved fixture leaf (got '$E_SHA')"
fi

# b6 (ii): exactly one provenance line naming the patched default table.
if [ "$(grep -cxF "admitted table: $RFX/admitted-ok.yaml" "$T/b1.err")" = "1" ]; then
    ok "b6(ii) stderr carries ONE 'admitted table: <ADMITTED_PATH>' provenance line"
else
    bad "b6(ii) provenance line (stderr: $(cat "$T/b1.err"))"
fi

# b8: exactly one ledger row, through resolve_and_log (spy), with the pinned
# fields; the host-default ledger untouched.
lget() { python3 -c 'import json,sys; print(json.loads(sys.stdin.readline()).get(sys.argv[1],""))' "$1"; }
LROWS="$(wc -l < "$GOALFORGE_DISPATCH_LEDGER" 2>/dev/null | tr -d ' ' || echo 0)"
if [ "$LROWS" = "1" ] \
   && [ "$(lget decision <"$GOALFORGE_DISPATCH_LEDGER")" = "admitted" ] \
   && [ "$(lget provider <"$GOALFORGE_DISPATCH_LEDGER")" = "ollama" ] \
   && [ "$(lget model <"$GOALFORGE_DISPATCH_LEDGER")" = "glm-5.3:cloud" ] \
   && [ "$(lget task_class <"$GOALFORGE_DISPATCH_LEDGER")" = "code/py" ] \
   && [ "$(lget admitted_override <"$GOALFORGE_DISPATCH_LEDGER")" = "False" ] \
   && [ "$(lget evidence_ref <"$GOALFORGE_DISPATCH_LEDGER")" = "fixtures/admission#user-experience-2026-09-14" ] \
   && [ "$(lget admitted_source <"$GOALFORGE_DISPATCH_LEDGER")" = "scripts/tests/fixtures/admission/admitted-ok.yaml" ]; then
    ok "b8 exactly ONE ledger row: admitted, the fixture's provider/model/task_class/evidence_ref, override false, admitted_source = the patched fixture literal"
else
    bad "b8 ledger row (rows=$LROWS): $(cat "$GOALFORGE_DISPATCH_LEDGER" 2>&1)"
fi
SPY="$(cat "$T/b1.spy" 2>/dev/null)"
if [ "$SPY" = '{"calls": 1, "decisions": ["admitted"]}' ]; then
    ok "b8 the compile obtained the verdict through ONE resolve_and_log call (admission_decision admitted)"
else
    bad "b8 resolve_and_log spy (got: $SPY)"
fi
DEF_SRC="$(python3 "$SEAM" default-source "$R/scripts/goalforge-pick-agent.py")"
[ "$DEF_SRC" = "references/admitted-providers.yaml" ] \
    && ok "b8 unpatched resolve_admitted_path(None)[1] == references/admitted-providers.yaml" \
    || bad "b8 unpatched resolve_admitted_path(None)[1] (got '$DEF_SRC')"
[ "$(sha256sum "$HOST_LEDGER" 2>/dev/null || echo absent)" = "$HOST_BEFORE" ] \
    && ok "b8 the default-path ledger is untouched (writes go to the hermetic ledger only)" \
    || bad "b8 the default-path ledger changed"

# --- b6 (i): the CLI surface carries no admission-table option -------------------
CLI_SET="$(python3 "$SEAM" cli "$RCOMPILE" | tr '\n' ' ')"
if [ "$CLI_SET" = "--dispatch --expertise --help --out -h overview " ]; then
    ok "b6(i) positional dests ∪ option strings == {overview, --dispatch, --expertise, --out, -h, --help}"
else
    bad "b6(i) CLI surface (got: $CLI_SET)"
fi

# --- b2 / b7 (i): empty table -> missing admission, "admitted nothing" ----------
seam_compile b2 "$RFX/admitted-empty.yaml" "$D_ADM"
if [ "$RC" -eq 2 ] && err_has b2 "$KEY_TRIPLE" && err_has b2 "admitted nothing" \
   && [ ! -f "$T/b2/wp-fx-admitted.js" ]; then
    ok "b2/b7(i) empty table -> exit 2 naming $KEY_TRIPLE and 'admitted nothing', nothing emitted"
else
    bad "b2/b7(i) empty table (rc=$RC): $(cat "$T/b2.err")"
fi

# --- b7 (ii): unloadable table (malformed, nonexistent) -> distinct fail-closed --
printf 'admitted: [unclosed\n' > "$RFX/malformed.yaml"
for variant in malformed.yaml no-such-table.yaml; do
    seam_compile "b7-$variant" "$RFX/$variant" "$D_ADM"
    if [ "$RC" -eq 2 ] && err_has "b7-$variant" "$RFX/$variant" \
       && err_has "b7-$variant" "load failure, failed CLOSED" \
       && ! err_has "b7-$variant" "missing admission" && ! err_has "b7-$variant" "admitted nothing"; then
        ok "b7(ii) $variant -> exit 2 naming the path + load failure, failed CLOSED (never the empty-table reason)"
    else
        bad "b7(ii) $variant (rc=$RC): $(cat "$T/b7-$variant.err")"
    fi
done
rm -f "$RFX/malformed.yaml"

# --- b3: egress coherence = dispatch egress <= row max_egress --------------------
b3_case() { # <name> <table> <dispatch> <want rc> [levels...]
    local name="$1" table="$2" dispatch="$3" want="$4"; shift 4
    seam_compile "$name" "$RFX/$table" "$FIXTURES/$dispatch"
    local good=1 lvl
    [ "$RC" -eq "$want" ] || good=0
    if [ "$want" -eq 2 ]; then
        err_has "$name" "egress incoherent" || good=0
        for lvl in "$@"; do err_has "$name" "'$lvl'" || good=0; done
    fi
    if [ "$good" -eq 1 ]; then ok "b3 $name -> exit $want"; else bad "b3 $name -> exit $want (rc=$RC): $(cat "$T/$name.err")"; fi
}
b3_case b3-none-vs-full      admitted-egress-none.yaml      dispatch-admitted-egress-full.yaml      2 none full
b3_case b3-diffonly-vs-overview admitted-egress-diff-only.yaml dispatch-admitted.yaml              2 diff-only overview
b3_case b3-equal-overview    admitted-ok.yaml               dispatch-admitted.yaml                  0
b3_case b3-full-vs-diffonly  admitted-egress-full.yaml      dispatch-admitted-egress-diff-only.yaml 0

# --- b10: max_egress required + closed enum (loader substrings) ------------------
seam_compile b10-missing "$RFX/bad-missing-max-egress.yaml" "$D_ADM"
if [ "$RC" -eq 2 ] && err_has b10-missing "missing required key 'max_egress'" && ! err_has b10-missing "egress incoherent"; then
    ok "b10(i) no max_egress -> exit 2 \"missing required key 'max_egress'\", never the incoherence path"
else
    bad "b10(i) (rc=$RC): $(cat "$T/b10-missing.err")"
fi
seam_compile b10-enum "$RFX/bad-max-egress-enum.yaml" "$D_ADM"
if [ "$RC" -eq 2 ] && err_has b10-enum "max_egress 'wide' not in {none, diff-only, overview, full}" && ! err_has b10-enum "egress incoherent"; then
    ok "b10(ii) max_egress: wide -> exit 2 naming the closed enum, never the incoherence path"
else
    bad "b10(ii) (rc=$RC): $(cat "$T/b10-enum.err")"
fi
seam_compile b10-closure "$RFX/bad-missing-leaf-closure.yaml" "$D_ADM"
if [ "$RC" -eq 2 ] && err_has b10-closure "missing required key 'leaf_closure'" && ! err_has b10-closure "egress incoherent"; then
    ok "b10(iii) no leaf_closure -> exit 2 \"missing required key 'leaf_closure'\", never defaulted"
else
    bad "b10(iii) (rc=$RC): $(cat "$T/b10-closure.err")"
fi

# --- b11: fable is advisor-only on BOTH paths -------------------------------------
FABLE_MSG="fable is advisor-only, never an implementer"
seam_compile b11-admitted "$RFX/admitted-fable.yaml" "$FIXTURES/dispatch-admitted-fable.yaml"
if [ "$RC" -eq 2 ] && err_has b11-admitted "$FABLE_MSG" && ! err_has b11-admitted "missing admission"; then
    ok "b11(i) an ADMITTED (code/py, ollama, fable) row -> exit 2, fable advisor-only"
else
    bad "b11(i) (rc=$RC): $(cat "$T/b11-admitted.err")"
fi
seam_compile b11-native - "$FIXTURES/dispatch-native-fable.yaml"
if [ "$RC" -eq 2 ] && err_has b11-native "$FABLE_MSG" && ! err_has b11-native "missing admission"; then
    ok "b11(ii) a NATIVE implement row on fable -> exit 2, fable advisor-only"
else
    bad "b11(ii) (rc=$RC): $(cat "$T/b11-native.err")"
fi

# --- b6 (iii): competing table routes never reach the resolver --------------------
seam_compile b6-env "$RFX/admitted-empty.yaml" "$D_ADM" \
    GOALFORGE_ADMITTED="$RFX/admitted-ok.yaml" GOALFORGE_ADMITTED_PATH="$RFX/admitted-ok.yaml" \
    GOALFORGE_ADMISSION_TABLE="$RFX/admitted-ok.yaml"
if [ "$RC" -eq 2 ] && err_has b6-env "missing admission $KEY_TRIPLE"; then
    ok "b6(iii)(a) a GOALFORGE_ADMITTED*-style env var does not supply the table"
else
    bad "b6(iii)(a) env route (rc=$RC): $(cat "$T/b6-env.err")"
fi
seam_compile b6-key "$RFX/admitted-empty.yaml" "$FIXTURES/dispatch-admitted-path-key.yaml"
if [ "$RC" -eq 2 ] && err_has b6-key "missing admission $KEY_TRIPLE"; then
    ok "b6(iii)(b) an admission-path key in the dispatch file does not supply the table"
else
    bad "b6(iii)(b) dispatch-key route (rc=$RC): $(cat "$T/b6-key.err")"
fi

# --- b12: the leaf wrapper, run VERBATIM inside the replica -----------------------
WRAPPER_SRC="$PKG/scripts/goalforge-leaf-exec.sh"
CODE_LINES="$(grep -v '^[[:space:]]*#' "$WRAPPER_SRC")"
if grep -qF 'if [[ $# -ne 3 ]]; then' <<<"$CODE_LINES" \
   && grep -qF 'TABLE="$(dirname "$0")/../references/admitted-providers.yaml"' <<<"$CODE_LINES" \
   && [ "$(grep -c 'admitted-providers' <<<"$CODE_LINES")" = "1" ] \
   && ! grep -q 'GOALFORGE_' <<<"$CODE_LINES"; then
    ok "b12 structural: exactly three positionals, table ONLY \$(dirname \"\$0\")/../references/admitted-providers.yaml, no GOALFORGE_* read"
else
    bad "b12 structural assertion over scripts/goalforge-leaf-exec.sh"
fi
# The canonical-table compile (no seam: the wrapper subprocess cannot see one).
seam_compile b12 - "$D_ADM"
CALL="$(leg_field "$T/b12/wp-fx-admitted.js" wrapper_call 2>/dev/null)"
BRIEF="$(realpath "$(dirname "$WPA")")/leaf-brief.txt"
if [ "$RC" -eq 0 ] && [ "$CALL" = "scripts/goalforge-leaf-exec.sh code/py ollama glm-5.3:cloud < $BRIEF" ]; then
    ok "b12 the canonical-table compile emits the wrapper call keyed by the row"
else
    bad "b12 canonical-table compile (rc=$RC, call='$CALL'): $(cat "$T/b12.err")"
fi
MARK="$T/leaf-ran"
run_call() { # <extra argv string> -> RC, marker state, $T/wrap.err
    rm -f "$MARK"
    ( cd "$R" && LEAF_MARKER="$MARK" LEAF_EXIT=7 bash -c "$CALL$1" ) >/dev/null 2>"$T/wrap.err"
    RC=$?
}
run_call ""
if [ "$RC" -eq 7 ] && [ -f "$MARK" ]; then
    ok "b12(ii) leaf unchanged: the wrapper runs the leaf and returns its exit status (7)"
else
    bad "b12(ii) leaf unchanged (rc=$RC, marker=$([ -f "$MARK" ] && echo yes || echo no)): $(cat "$T/wrap.err")"
fi
printf '# edited after compile\n' >> "$LEAF_FILE"
run_call ""
if [ "$RC" -eq 2 ] && [ ! -f "$MARK" ] && grep -q "leaf_sha256 mismatch" "$T/wrap.err"; then
    ok "b12(i) leaf edited after compile -> exit 2 naming the leaf_sha256 mismatch, leaf NOT executed"
else
    bad "b12(i) (rc=$RC, marker=$([ -f "$MARK" ] && echo yes || echo no)): $(cat "$T/wrap.err")"
fi
FORGED="$(sha256sum "$LEAF_FILE" | cut -d' ' -f1)"
run_call " $FORGED"
if [ "$RC" -eq 2 ] && [ ! -f "$MARK" ]; then
    ok "b12(iii-a) leaf edited + forged sha as an extra argument -> exit 2, leaf NOT executed"
else
    bad "b12(iii-a) (rc=$RC, marker=$([ -f "$MARK" ] && echo yes || echo no)): $(cat "$T/wrap.err")"
fi
sed -i "s/leaf_sha256: .*/leaf_sha256: $FORGED/" "$R/references/admitted-providers.yaml"
run_call ""
if [ "$RC" -eq 2 ] && [ ! -f "$MARK" ] && grep -q "differs from git show HEAD" "$T/wrap.err"; then
    ok "b12(iii-b) leaf edited + working-tree table re-stamped (uncommitted) -> exit 2, HEAD-bound, leaf NOT executed"
else
    bad "b12(iii-b) (rc=$RC, marker=$([ -f "$MARK" ] && echo yes || echo no)): $(cat "$T/wrap.err")"
fi
"${GITQ[@]}" -C "$R" checkout -q -- references/admitted-providers.yaml
cp "$LEAF_ORIG" "$LEAF_FILE"
mkdir -p "$T/outside"
cp "$LEAF_ORIG" "$T/outside/headless_dispatch"
rm -f "$LEAF_FILE"
ln -s "$T/outside/headless_dispatch" "$LEAF_FILE"
run_call ""
if [ "$RC" -eq 2 ] && [ ! -f "$MARK" ] && grep -q "outside the leaf root" "$T/wrap.err"; then
    ok "b12(iv) leaf replaced by a symlink to a byte-identical copy outside the root -> exit 2, NOT executed"
else
    bad "b12(iv) (rc=$RC, marker=$([ -f "$MARK" ] && echo yes || echo no)): $(cat "$T/wrap.err")"
fi
rm -f "$LEAF_FILE"
cp "$LEAF_ORIG" "$LEAF_FILE"
chmod +x "$LEAF_FILE"

# b12 (v)-(ix): the leaf_closure — every regular file under the leaf's tree.
LEAF_DIR="$(dirname "$LEAF_FILE")"
restore_leaf_tree() { rm -rf "$LEAF_DIR"; mkdir -p "$LEAF_DIR"; cp -r "$ADM_FX/leaf/." "$LEAF_DIR/"; }
closure_case() { # <label> [rule substring]  (the tree was mutated just before)
    run_call ""
    if [ "$RC" -eq 2 ] && [ ! -f "$MARK" ] && grep -q "leaf_closure mismatch" "$T/wrap.err" \
       && grep -q "${2:-leaf_closure mismatch}" "$T/wrap.err"; then
        ok "b12($1) -> exit 2 naming the leaf_closure mismatch, leaf NOT executed"
    else
        bad "b12($1) (rc=$RC, marker=$([ -f "$MARK" ] && echo yes || echo no)): $(cat "$T/wrap.err")"
    fi
    restore_leaf_tree
}
printf '# edited after compile\n' >> "$LEAF_DIR/helper.sh"
closure_case "v) closure sibling changed"
rm -f "$LEAF_DIR/helper.sh"
closure_case "vi) closure sibling deleted"
cp "$LEAF_DIR/helper.sh" "$T/outside/helper.sh"
rm -f "$LEAF_DIR/helper.sh"
ln -s "$T/outside/helper.sh" "$LEAF_DIR/helper.sh"
closure_case "vii) closure sibling -> out-of-root symlink to a byte-identical copy"
printf '# unlisted\n' > "$LEAF_DIR/unlisted.sh"
closure_case "viii) unlisted file added under the leaf tree"
cp -r "$LEAF_DIR/lib" "$T/outside/lib"
rm -rf "$LEAF_DIR/lib"
ln -s "$T/outside/lib" "$LEAF_DIR/lib"
# Rule (d) by name: a walker that merely skipped the symlink would still exit 2
# (lib/common.sh then reads as missing), so the reason itself is pinned.
closure_case "ix) lib/ -> out-of-root directory symlink to a byte-identical copy" "symlink to a directory"
# (x) N1 lap 7: the entry file itself -> an IN-root symlink to a byte-identical
# copy whose sibling differs. The executed file's real parent is the tree that
# must match; a walk of the declared directory would pass and run the copy.
EVIL="$CLAUDE_CONFIG_DIR/evil-copy"
mkdir -p "$EVIL"
cp -r "$ADM_FX/leaf/." "$EVIL/"
printf '# attacker sibling\n' >> "$EVIL/helper.sh"
rm -f "$LEAF_FILE"
ln -s "$EVIL/$(basename "$LEAF_FILE")" "$LEAF_FILE"
closure_case "x) entry -> in-root symlink to a byte-identical copy whose sibling differs" "is a symlink"
rm -rf "$EVIL"

# --- b14: the leaf-interface v1 argv and the HEAD brief --------------------------
# The fixture leaf enforces §3 (exit 1 unless --model, --prompt, --output) and
# writes its argv, NUL-separated, to the marker; the emitted call line runs
# unchanged, its own `< <brief file>` redirect supplying stdin.
leaf_argv() { # <index> -> the leaf's argv[index] from the marker (raw bytes to stdout)
    python3 -c 'import sys; sys.stdout.buffer.write(open(sys.argv[1], "rb").read().split(b"\0")[int(sys.argv[2])])' "$MARK" "$1"
}
strip1() { python3 -c 'import sys; b = open(sys.argv[1], "rb").read(); sys.stdout.buffer.write(b[:-1] if b.endswith(b"\n") else b)' "$1"; }
rm -f "$MARK"
( cd "$R" && LEAF_MARKER="$MARK" bash -c "$CALL" ) >"$T/b14.out" 2>"$T/wrap.err"
RC=$?
"${GITQ[@]}" -C "$R" show "HEAD:scripts/tests/fixtures/dispatch/wp-admitted.md" > "$T/wp-head.md"
if [ "$RC" -eq 0 ] && [ -f "$MARK" ] \
   && [ "$(leaf_argv 0)" = "--model" ] && [ "$(leaf_argv 1)" = "glm-5.3:cloud" ] \
   && [ "$(leaf_argv 2)" = "--provider" ] && [ "$(leaf_argv 3)" = "ollama" ] \
   && [ "$(leaf_argv 4)" = "--prompt" ] && cmp -s <(leaf_argv 5) <(strip1 "$T/wp-head.md") \
   && [ "$(leaf_argv 6)" = "--output" ] && [[ "$(leaf_argv 7)" == /* ]] \
   && [ "$(python3 -c 'import sys; print(len(open(sys.argv[1], "rb").read().split(b"\0")))' "$MARK")" = "9" ]; then
    ok "b14(i) the leaf gets --model/--provider from the row, --prompt = the HEAD brief (modulo one newline), an absolute --output"
else
    bad "b14(i) leaf argv (rc=$RC): $(tr '\0' ' ' < "$MARK" 2>/dev/null | head -c 300) $(cat "$T/wrap.err")"
fi
if [ "$(cat "$T/b14.out")" = '{"schema_version": "1", "status": "ok", "model": "glm-5.3:cloud"}' ] && [ "$RC" -eq 0 ]; then
    ok "b14(i) the wrapper's stdout is the leaf's --output file and its exit status the leaf's"
else
    bad "b14(i) wrapper stdout (rc=$RC): $(cat "$T/b14.out")"
fi
cp "$BRIEF" "$T/brief.orig"
brief_case() { # <label> <want: run|refuse> <stderr substring>
    rm -f "$MARK"
    ( cd "$R" && LEAF_MARKER="$MARK" bash -c "$CALL" ) >/dev/null 2>"$T/wrap.err"
    RC=$?
    if [ "$2" = refuse ] && [ "$RC" -eq 2 ] && [ ! -f "$MARK" ] && grep -q "$3" "$T/wrap.err"; then
        ok "b14($1) -> exit 2 naming $3, leaf NOT executed"
    elif [ "$2" = run ] && [ "$RC" -eq 0 ] && [ -f "$MARK" ] && cmp -s <(leaf_argv 5) "$BRIEF"; then
        ok "b14($1) -> the leaf runs and --prompt carries every brief byte"
    else
        bad "b14($1) (rc=$RC, marker=$([ -f "$MARK" ] && echo yes || echo no)): $(cat "$T/wrap.err")"
    fi
}
head -c 102401 /dev/zero | tr '\0' a > "$BRIEF"
brief_case "ii) 102401-byte brief" refuse "brief cap"
head -c 102400 /dev/zero | tr '\0' a > "$BRIEF"
brief_case "iii) 102400-byte brief" run
printf 'a\0b' > "$BRIEF"
brief_case "iv) brief with a NUL byte" refuse "NUL"
cp "$T/brief.orig" "$BRIEF"
# (v) overview.md edited in the working tree, uncommitted, before the compile.
printf '\nUNCOMMITTED WORKING-TREE EDIT\n' >> "$WPA"
seam_compile b14v - "$D_ADM"
rm -f "$MARK"
( cd "$R" && LEAF_MARKER="$MARK" bash -c "$(leg_field "$T/b14v/wp-fx-admitted.js" wrapper_call)" ) >/dev/null 2>"$T/wrap.err"
if [ -f "$MARK" ] && cmp -s <(leaf_argv 5) <(strip1 "$T/wp-head.md") && cmp -s "$BRIEF" "$T/wp-head.md"; then
    ok "b14(v) --prompt is git show HEAD:<overview> (modulo one newline), not the uncommitted working-tree edit"
else
    bad "b14(v) HEAD brief (compile rc=$RC): $(cat "$T/b14v.err" "$T/wrap.err")"
fi
"${GITQ[@]}" -C "$R" checkout -q -- scripts/tests/fixtures/dispatch/wp-admitted.md
# A plans root outside any git work tree has no HEAD brief: exit 2, fail closed.
mkdir -p "$T/nogit/plans/wp"
cp "$WPA" "$T/nogit/plans/wp/overview.md"
WPA_SAVE="$WPA"; WPA="$T/nogit/plans/wp/overview.md"
seam_compile b14-nogit "$RFX/admitted-ok.yaml" "$D_ADM"
WPA="$WPA_SAVE"
if [ "$RC" -eq 2 ] && err_has b14-nogit "leaf brief" && err_has b14-nogit "outside a git work tree" \
   && [ ! -f "$T/nogit/plans/wp/leaf-brief.txt" ] && [ ! -f "$T/b14-nogit/wp-fx-admitted.js" ]; then
    ok "b14 a WP outside a git work tree -> exit 2 (no HEAD brief), nothing written"
else
    bad "b14 non-git plans root (rc=$RC): $(cat "$T/b14-nogit.err")"
fi

# --- b13: the admitting table must be the committed, guarded HEAD table ----------
b13_expect() { # <name> <substring>
    if [ "$RC" -eq 2 ] && err_has "$1" "$2" && ! err_has "$1" "missing admission"; then
        ok "b13 $1 -> exit 2 ($2)"
    else
        bad "b13 $1 -> exit 2 ($2) (rc=$RC): $(cat "$T/$1.err")"
    fi
}
# (i) edited after the replica's commit.
printf '# edited after commit\n' >> "$RFX/admitted-ok.yaml"
seam_compile b13-i "$RFX/admitted-ok.yaml" "$D_ADM"
b13_expect b13-i "differs from git show HEAD"
# (iv) the same edit, with GIT_DIR / GIT_WORK_TREE pointing at a forged
# repository whose HEAD holds the edited bytes: scrubbed, so still a mismatch
# against the REAL replica.
FORGED_GIT="$T/forged.git"
"${GITQ[@]}" init -q --bare "$FORGED_GIT"
"${GITQ[@]}" --git-dir="$FORGED_GIT" --work-tree="$R" add scripts/tests/fixtures/admission/admitted-ok.yaml
"${GITQ[@]}" --git-dir="$FORGED_GIT" --work-tree="$R" commit -qm forged
seam_compile b13-iv "$RFX/admitted-ok.yaml" "$D_ADM" GIT_DIR="$FORGED_GIT" GIT_WORK_TREE="$R"
b13_expect b13-iv "differs from git show HEAD"
"${GITQ[@]}" -C "$R" checkout -q -- scripts/tests/fixtures/admission/admitted-ok.yaml
# (ii) a repository-free replica: no .git anywhere above it.
R2="$T/nogit/replica"
mk_replica "$R2" nogit
RCOMPILE_SAVE="$RCOMPILE"; RCOMPILE="$R2/scripts/goalforge-workflow-compile.py"
seam_compile b13-ii "$R2/scripts/tests/fixtures/admission/admitted-ok.yaml" "$D_ADM"
RCOMPILE="$RCOMPILE_SAVE"
if [ -z "$(git -C "$R2" rev-parse --show-toplevel 2>/dev/null)" ]; then
    b13_expect b13-ii "outside a git work tree"
    err_has b13-ii "failed CLOSED" && ok "b13 b13-ii states it failed CLOSED" || bad "b13 b13-ii states it failed CLOSED"
else
    bad "b13 (ii) setup: $R2 sits inside a git work tree"
fi
# (iii) absent from HEAD: committed, the deletion committed, then rewritten.
"${GITQ[@]}" -C "$R" rm -q scripts/tests/fixtures/admission/admitted-absent.yaml
( cd "$R" && "${GITQ[@]}" commit -qm "drop admitted-absent" </dev/null >/dev/null 2>&1 )
cp "$RFX/admitted-ok.yaml" "$RFX/admitted-absent.yaml"
seam_compile b13-iii "$RFX/admitted-absent.yaml" "$D_ADM"
b13_expect b13-iii "absent from HEAD"
rm -f "$RFX/admitted-absent.yaml"
# (v) a nested `git init` over the table's directory, no goalforge pre-commit.
"${GITQ[@]}" -C "$RFX" init -q
"${GITQ[@]}" -C "$RFX" add admitted-ok.yaml
"${GITQ[@]}" -C "$RFX" commit -qm nested
seam_compile b13-v "$RFX/admitted-ok.yaml" "$D_ADM"
b13_expect b13-v "unguarded"
# (vi) the nested repository's pre-commit carries the installer's marker block,
# but it invokes a STUB goalforge-pre-commit.sh outside PKG_ROOT/hooks/.
mkdir -p "$T/stub-hooks"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/stub-hooks/goalforge-pre-commit.sh"
printf '#!/usr/bin/env bash\n# >>> sdd-pre-commit >>>\nbash "%s" || exit $?\n# <<< sdd-pre-commit <<<\n' \
    "$T/stub-hooks/goalforge-pre-commit.sh" > "$RFX/.git/hooks/pre-commit"
chmod +x "$RFX/.git/hooks/pre-commit"
seam_compile b13-vi "$RFX/admitted-ok.yaml" "$D_ADM"
b13_expect b13-vi "unguarded"
rm -rf "$RFX/.git"
# (vii-a) a forged GLOBAL core.hooksPath in the redirected temp home.
mkdir -p "$T/home-forged/.config" "$T/elsewhere-hooks"
printf '[core]\n\thooksPath = %s\n' "$T/elsewhere-hooks" > "$T/home-forged/.gitconfig"
seam_compile b13-viia "$RFX/admitted-ok.yaml" "$D_ADM" HOME="$T/home-forged" XDG_CONFIG_HOME="$T/home-forged/.config"
b13_expect b13-viia "global core.hooksPath is set"
if ! err_has b13-viia "unguarded"; then ok "b13 (vii-a) reason is distinct from the unguarded-repository reason"; else bad "b13 (vii-a) reused the unguarded reason"; fi
# (vii-b) the same redirection with a CLEAN .gitconfig admits.
mkdir -p "$T/home-clean/.config"
printf '[user]\n\tname = fixture\n' > "$T/home-clean/.gitconfig"
seam_compile b13-viib "$RFX/admitted-ok.yaml" "$D_ADM" HOME="$T/home-clean" XDG_CONFIG_HOME="$T/home-clean/.config"
if [ "$RC" -eq 0 ] && [ -f "$T/b13-viib/wp-fx-admitted.js" ]; then
    ok "b13 (vii-b) a clean redirected home admits exactly as b1"
else
    bad "b13 (vii-b) clean-config control (rc=$RC): $(cat "$T/b13-viib.err")"
fi
# (viii) N2 lap 7: the canonical table replaced, uncommitted, by a symlink to
# an admitting table committed at an UNGUARDED path. The HEAD read must be of
# the canonical path itself, so a symlinked table is refused outright.
mkdir -p "$R/evil"
cp "$RFX/admitted-ok.yaml" "$R/evil/admitted-providers.yaml"
"${GITQ[@]}" -C "$R" add evil/admitted-providers.yaml
( cd "$R" && "${GITQ[@]}" commit -qm "evil table" </dev/null >/dev/null 2>&1 )
"${GITQ[@]}" -C "$R" cat-file -e HEAD:evil/admitted-providers.yaml 2>/dev/null \
    && ok "b13 (viii) setup: the admitting table is committed at the unguarded evil/ path" \
    || bad "b13 (viii) setup: evil/admitted-providers.yaml not in HEAD"
rm -f "$R/references/admitted-providers.yaml"
ln -s ../evil/admitted-providers.yaml "$R/references/admitted-providers.yaml"
seam_compile b13-viii - "$D_ADM"
b13_expect b13-viii "is a symlink or resolves through one"
rm -f "$R/references/admitted-providers.yaml"
"${GITQ[@]}" -C "$R" checkout -q -- references/admitted-providers.yaml
# N5 lap 7: a pre-planted leaf-brief.txt symlink is removed, never followed —
# the compile creates the brief exclusively and the link's target is untouched.
BRIEF_PATH="$(realpath "$(dirname "$WPA")")/leaf-brief.txt"
printf 'VICTIM\n' > "$T/brief-victim"
rm -f "$BRIEF_PATH"
ln -s "$T/brief-victim" "$BRIEF_PATH"
seam_compile brief-link - "$D_ADM"
if [ "$RC" -eq 0 ] && [ "$(cat "$T/brief-victim")" = "VICTIM" ] && [ -f "$BRIEF_PATH" ] && [ ! -L "$BRIEF_PATH" ]; then
    ok "b14 a pre-planted leaf-brief.txt symlink is not followed (target untouched, brief a regular file)"
else
    bad "b14 pre-planted leaf-brief.txt symlink (rc=$RC, victim='$(cat "$T/brief-victim")'): $(cat "$T/brief-link.err")"
fi

echo
echo "goalforge-workflow-compile.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
