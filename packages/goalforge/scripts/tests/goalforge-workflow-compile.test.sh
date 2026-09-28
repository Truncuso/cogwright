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
# red() mutates replica sources in place and restores them: no bytecode cache
# may outlive a mutant (a same-size, same-second restore would reuse it).
export PYTHONDONTWRITEBYTECODE=1
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
# wp-08 — ADMITTED execution (b1-b3, b5-b8, b10-b16)
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

# mk_replica <dir> git|nogit|nohook [empty] — a temp copy of packages/goalforge/
# whose canonical references/admitted-providers.yaml holds b1's admitting
# fixture (`empty`: the shipped EMPTY table stays, so an attack is the only
# admitting route); `git` also inits, commits once and installs the goalforge
# pre-commit; `nohook` inits and commits with no pre-commit installed.
mk_replica() {
    mkdir -p "$1"
    cp -r "$PKG/." "$1/"
    find "$1" -name __pycache__ -type d -prune -exec rm -rf {} +
    rm -rf "$1/run"
    [ "${3:-}" = empty ] \
        || cp "$1/scripts/tests/fixtures/admission/admitted-ok/references/admitted-providers.yaml" "$1/references/admitted-providers.yaml"
    # b13 (iii): a table committed now and deleted by a later commit. Every
    # admitting fixture sits at a path ending references/admitted-providers.yaml
    # (T12), so the HEAD read's guard-set match passes and the case reaches
    # the check it exists to exercise.
    mkdir -p "$1/scripts/tests/fixtures/admission/admitted-absent/references"
    cp "$1/scripts/tests/fixtures/admission/admitted-ok/references/admitted-providers.yaml" "$1/scripts/tests/fixtures/admission/admitted-absent/references/admitted-providers.yaml"
    [ "$2" = nogit ] && return 0
    "${GITQ[@]}" -C "$1" init -q
    "${GITQ[@]}" -C "$1" add -A
    "${GITQ[@]}" -C "$1" commit -qm "replica"
    [ "$2" = nohook ] && return 0
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
    rm -rf "${T:?}/$name"   # a re-run (red()) never reads a stale earlier output
    env "$@" python3 "$SEAM" compile "$RCOMPILE" "$table" "$T/$name.spy" -- \
        "$WPA" --dispatch "$dispatch" --expertise "$EXPERTISE" --out "$T/$name" \
        >"$T/$name.out" 2>"$T/$name.err"
    RC=$?
}
err_has() { grep -qF -- "$2" "$T/$1.err"; }

# red <label> <why|-> <replica file>:<mutation>... -- <case fn> [args...]
# A known-bad: applies each named fixtures/admission/mutate.py mutation to the
# REPLICA's copy of the file, runs the case function in a subshell (its ok/bad
# lines captured, its counters discarded) and restores every file. The
# known-bad counts only when the case goes RED — and, with <why>, only when a
# FAIL line carries that substring (so it is red for the stated reason).
RED_N=0
red() {
    local label="$1" why="$2" out="" f applied=1; shift 2
    local files=()
    while [ "$1" != "--" ]; do
        f="${RED_ROOT:-$R}/${1%%:*}"
        RED_N=$((RED_N+1))
        cp "$f" "$T/red-$RED_N.orig"
        files+=("$f" "$T/red-$RED_N.orig")
        if ! python3 "$ADM_FX/mutate.py" "${1#*:}" "$T/red-$RED_N.orig" "$f" 2>"$T/red.err"; then
            bad "known-bad $label: mutation ${1#*:} did not apply ($(cat "$T/red.err"))"
            applied=0
        fi
        shift
    done
    shift
    [ "$applied" -eq 1 ] && out="$("$@" 2>&1)"
    # Reverse order: two mutations of ONE file restore to the original last.
    for ((f = ${#files[@]} - 2; f >= 0; f -= 2)); do cp "${files[f+1]}" "${files[f]}"; done
    [ "$applied" -eq 1 ] || return 0
    [ -n "${COMPILE_TEST_VERBOSE:-}" ] && printf '%s\n' "$out" | sed 's/^/    | /'
    if ! grep -q '^  FAIL: ' <<<"$out"; then
        bad "known-bad stays green: $label"; printf '%s\n' "$out" | sed 's/^/    /'
    elif [ "$why" != - ] && ! grep '^  FAIL: ' <<<"$out" | grep -qF -- "$why"; then
        bad "known-bad red, but not for '$why': $label"; printf '%s\n' "$out" | sed 's/^/    /'
    elif [ "$why" != - ]; then
        ok "known-bad red: $label (why: $why)"
    else
        ok "known-bad red: $label"
    fi
}

# --- b1 / b5 / b6(ii) / b8: the admitted compile --------------------------------
rm -rf "$T/ledger"
HOST_LEDGER="$CLAUDE_CONFIG_DIR/data/dispatch-decisions.jsonl"
HOST_BEFORE="$(sha256sum "$HOST_LEDGER" 2>/dev/null || echo absent)"
seam_compile b1 "$RFX/admitted-ok/references/admitted-providers.yaml" "$D_ADM"
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
if [ "$(grep -cxF "admitted table: $RFX/admitted-ok/references/admitted-providers.yaml" "$T/b1.err")" = "1" ]; then
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
   && [ "$(lget admitted_source <"$GOALFORGE_DISPATCH_LEDGER")" = "scripts/tests/fixtures/admission/admitted-ok/references/admitted-providers.yaml" ] \
   && [ "$(lget brief_source <"$GOALFORGE_DISPATCH_LEDGER")" = "head" ]; then
    ok "b8/b16(i) exactly ONE ledger row: admitted, the fixture's provider/model/task_class/evidence_ref, override false, admitted_source = the patched fixture literal, brief_source head (tracked overview)"
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
b3_case b3-none-vs-full      admitted-egress-none/references/admitted-providers.yaml      dispatch-admitted-egress-full.yaml      2 none full
b3_case b3-diffonly-vs-overview admitted-egress-diff-only/references/admitted-providers.yaml dispatch-admitted.yaml              2 diff-only overview
b3_case b3-equal-overview    admitted-ok/references/admitted-providers.yaml               dispatch-admitted.yaml                  0
b3_case b3-full-vs-diffonly  admitted-egress-full/references/admitted-providers.yaml      dispatch-admitted-egress-diff-only.yaml 0

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
seam_compile b11-admitted "$RFX/admitted-fable/references/admitted-providers.yaml" "$FIXTURES/dispatch-admitted-fable.yaml"
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
    GOALFORGE_ADMITTED="$RFX/admitted-ok/references/admitted-providers.yaml" GOALFORGE_ADMITTED_PATH="$RFX/admitted-ok/references/admitted-providers.yaml" \
    GOALFORGE_ADMISSION_TABLE="$RFX/admitted-ok/references/admitted-providers.yaml"
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
# Rule (c) (T8): a symlink AT the entry path or anywhere under the entry's real
# parent tree is refused; a symlinked ancestor above the leaf root is resolved.
# The mutated copies sit INSIDE the leaf root but OUTSIDE the entry's own
# directory tree (pinned placement, C4/O3/S7).
# (x) N1 lap 7: the entry file -> an in-root symlink to a byte-identical copy
# whose sibling lib/ file (at the copy's location) is then changed. A walk of
# the declared directory would pass and exec the copy.
case_b12_x() {
    local evil="$CLAUDE_CONFIG_DIR/evil-copy"
    mkdir -p "$evil"
    cp -r "$ADM_FX/leaf/." "$evil/"
    printf '# attacker lib\n' >> "$evil/lib/common.sh"
    rm -f "$LEAF_FILE"
    ln -s "$evil/$(basename "$LEAF_FILE")" "$LEAF_FILE"
    closure_case "x) entry -> in-root symlink to a byte-identical copy whose lib/ sibling differs" "is a symlink"
    rm -rf "$evil"
}
# (xi) the closure sibling -> an in-root symlink to a byte-identical copy.
case_b12_xi() {
    local evil="$CLAUDE_CONFIG_DIR/evil-sibling"
    mkdir -p "$evil"
    cp "$LEAF_DIR/helper.sh" "$evil/helper.sh"
    rm -f "$LEAF_DIR/helper.sh"
    ln -s "$evil/helper.sh" "$LEAF_DIR/helper.sh"
    closure_case "xi) closure sibling -> in-root symlink to a byte-identical copy" "is a symlink"
    rm -rf "$evil"
}
# (xii) known-good: the leaf root reached through a symlinked ancestor
# (CLAUDE_CONFIG_DIR itself a symlink), no symlink inside the closure.
case_b12_xii() {
    rm -f "$MARK" "$T/cfg-link"
    ln -s "$CLAUDE_CONFIG_DIR" "$T/cfg-link"
    ( cd "$R" && CLAUDE_CONFIG_DIR="$T/cfg-link" LEAF_MARKER="$MARK" LEAF_EXIT=7 bash -c "$CALL" ) \
        >/dev/null 2>"$T/wrap.err"
    RC=$?
    if [ "$RC" -eq 7 ] && [ -f "$MARK" ]; then
        ok "b12(xii) leaf root through a symlinked ancestor -> the leaf runs, exit status the leaf's (7)"
    else
        bad "b12(xii) symlinked-ancestor leaf root (rc=$RC, marker=$([ -f "$MARK" ] && echo yes || echo no)): $(cat "$T/wrap.err")"
    fi
    rm -f "$T/cfg-link"
}
case_b12_x
case_b12_xi
case_b12_xii
ADM_PY=scripts/goalforge-admission.py
# (n) the full lap-7 N1 code: RED on (x) because the leaf RAN (marker written).
red "b12(n) lap-7 N1 code (no entry check, declared-dir walk, out-of-root-only walker)" \
    "marker=yes" "$ADM_PY:n1-lap7" -- case_b12_x
# (l) a rule (c) refusing only out-of-root symlinks: marker-RED on (xi).
red "b12(l) walker refusing only out-of-root symlinks" "marker=yes" \
    "$ADM_PY:walker-out-of-root-only" -- case_b12_xi
# (m) a refusal of any abspath != realpath, ancestors included: RED on (xii).
red "b12(m) refusal of a symlinked ancestor above the leaf root" "b12(xii)" \
    "$ADM_PY:refuse-symlinked-ancestor" -- case_b12_xii

# T9 (no-discriminator, structural): the entry is resolved ONCE, by the caller.
case_t9() {
    local line
    line="$(python3 "$ADM_FX/structural.py" closure-single-realpath "$R/$ADM_PY")"
    case "$line" in ok*) ok "${line#ok }" ;; *) bad "${line#bad }" ;; esac
}
case_t9
red "T9 closure_mismatch resolving the entry again" "T9 structural" \
    "$ADM_PY:closure-realpath-entry" -- case_t9

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
# b16 (iii): a plans root outside any git work tree: exit 2 naming the missing
# work tree, fail closed (an agent-resolved reading, OQ11 (2)).
mkdir -p "$T/nogit/plans/wp"
cp "$WPA" "$T/nogit/plans/wp/overview.md"
WPA_SAVE="$WPA"; WPA="$T/nogit/plans/wp/overview.md"
seam_compile b14-nogit "$RFX/admitted-ok/references/admitted-providers.yaml" "$D_ADM"
WPA="$WPA_SAVE"
if [ "$RC" -eq 2 ] && err_has b14-nogit "leaf brief" && err_has b14-nogit "outside a git work tree" \
   && [ ! -f "$T/nogit/plans/wp/leaf-brief.txt" ] && [ ! -f "$T/b14-nogit/wp-fx-admitted.js" ]; then
    ok "b16(iii) a WP outside a git work tree -> exit 2 naming the missing work tree, nothing written"
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
printf '# edited after commit\n' >> "$RFX/admitted-ok/references/admitted-providers.yaml"
seam_compile b13-i "$RFX/admitted-ok/references/admitted-providers.yaml" "$D_ADM"
b13_expect b13-i "differs from git show HEAD"
# (iv) the same edit, with GIT_DIR / GIT_WORK_TREE pointing at a forged
# repository whose HEAD holds the edited bytes: scrubbed, so still a mismatch
# against the REAL replica.
FORGED_GIT="$T/forged.git"
"${GITQ[@]}" init -q --bare "$FORGED_GIT"
"${GITQ[@]}" --git-dir="$FORGED_GIT" --work-tree="$R" add scripts/tests/fixtures/admission/admitted-ok/references/admitted-providers.yaml
"${GITQ[@]}" --git-dir="$FORGED_GIT" --work-tree="$R" commit -qm forged
seam_compile b13-iv "$RFX/admitted-ok/references/admitted-providers.yaml" "$D_ADM" GIT_DIR="$FORGED_GIT" GIT_WORK_TREE="$R"
b13_expect b13-iv "differs from git show HEAD"
"${GITQ[@]}" -C "$R" checkout -q -- scripts/tests/fixtures/admission/admitted-ok/references/admitted-providers.yaml
# (ii) a repository-free replica: no .git anywhere above it.
R2="$T/nogit/replica"
mk_replica "$R2" nogit
RCOMPILE_SAVE="$RCOMPILE"; RCOMPILE="$R2/scripts/goalforge-workflow-compile.py"
seam_compile b13-ii "$R2/scripts/tests/fixtures/admission/admitted-ok/references/admitted-providers.yaml" "$D_ADM"
RCOMPILE="$RCOMPILE_SAVE"
if [ -z "$(git -C "$R2" rev-parse --show-toplevel 2>/dev/null)" ]; then
    b13_expect b13-ii "outside a git work tree"
    err_has b13-ii "failed CLOSED" && ok "b13 b13-ii states it failed CLOSED" || bad "b13 b13-ii states it failed CLOSED"
else
    bad "b13 (ii) setup: $R2 sits inside a git work tree"
fi
# (iii) absent from HEAD: committed, the deletion committed, then rewritten.
"${GITQ[@]}" -C "$R" rm -q scripts/tests/fixtures/admission/admitted-absent/references/admitted-providers.yaml
( cd "$R" && "${GITQ[@]}" commit -qm "drop admitted-absent" </dev/null >/dev/null 2>&1 )
mkdir -p "$RFX/admitted-absent/references"
cp "$RFX/admitted-ok/references/admitted-providers.yaml" "$RFX/admitted-absent/references/admitted-providers.yaml"
seam_compile b13-iii "$RFX/admitted-absent/references/admitted-providers.yaml" "$D_ADM"
b13_expect b13-iii "absent from HEAD"
rm -f "$RFX/admitted-absent/references/admitted-providers.yaml"
# (v) a THIRD whole replica with NO goalforge pre-commit, compiled by its own
# scripts (v13: a nested repository inside PKG_ROOT is now refused by the
# table binding before _guard_reason, b15 v-a), so the unguarded-repository
# reason fires on the package's own work tree.
R3="$T/replica3"
mk_replica "$R3" nohook
case_b13_v() {
    local RCOMPILE="$R3/scripts/goalforge-workflow-compile.py"
    local WPA="$R3/scripts/tests/fixtures/dispatch/wp-admitted.md"
    seam_compile b13-v "$R3/scripts/tests/fixtures/admission/admitted-ok/references/admitted-providers.yaml" "$D_ADM"
    b13_expect b13-v "unguarded"
}
case_b13_v
# T12 known-bad: the guard-set match kept, the guarded-repository check dropped.
RED_ROOT="$R3" red "T12 compile keeping the guard-set match but dropping _guard_reason" "b13 b13-v" \
    "$ADM_PY:drop-guard-reason" -- case_b13_v
# (vi) a FOURTH whole replica whose pre-commit carries the installer's marker
# block but invokes a STUB goalforge-pre-commit.sh outside PKG_ROOT/hooks/.
R4="$T/replica4"
mk_replica "$R4" nohook
mkdir -p "$T/stub-hooks"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/stub-hooks/goalforge-pre-commit.sh"
printf '#!/usr/bin/env bash\n# >>> sdd-pre-commit >>>\nbash "%s" || exit $?\n# <<< sdd-pre-commit <<<\n' \
    "$T/stub-hooks/goalforge-pre-commit.sh" > "$R4/.git/hooks/pre-commit"
chmod +x "$R4/.git/hooks/pre-commit"
case_b13_vi() {
    local RCOMPILE="$R4/scripts/goalforge-workflow-compile.py"
    local WPA="$R4/scripts/tests/fixtures/dispatch/wp-admitted.md"
    seam_compile b13-vi "$R4/scripts/tests/fixtures/admission/admitted-ok/references/admitted-providers.yaml" "$D_ADM"
    b13_expect b13-vi "unguarded"
}
case_b13_vi
# (vii-a) a forged GLOBAL core.hooksPath in the redirected temp home.
mkdir -p "$T/home-forged/.config" "$T/elsewhere-hooks"
printf '[core]\n\thooksPath = %s\n' "$T/elsewhere-hooks" > "$T/home-forged/.gitconfig"
seam_compile b13-viia "$RFX/admitted-ok/references/admitted-providers.yaml" "$D_ADM" HOME="$T/home-forged" XDG_CONFIG_HOME="$T/home-forged/.config"
b13_expect b13-viia "global core.hooksPath is set"
if ! err_has b13-viia "unguarded"; then ok "b13 (vii-a) reason is distinct from the unguarded-repository reason"; else bad "b13 (vii-a) reused the unguarded reason"; fi
# (vii-b) the same redirection with a CLEAN .gitconfig admits.
mkdir -p "$T/home-clean/.config"
printf '[user]\n\tname = fixture\n' > "$T/home-clean/.gitconfig"
seam_compile b13-viib "$RFX/admitted-ok/references/admitted-providers.yaml" "$D_ADM" HOME="$T/home-clean" XDG_CONFIG_HOME="$T/home-clean/.config"
if [ "$RC" -eq 0 ] && [ -f "$T/b13-viib/wp-fx-admitted.js" ]; then
    ok "b13 (vii-b) a clean redirected home admits exactly as b1"
else
    bad "b13 (vii-b) clean-config control (rc=$RC): $(cat "$T/b13-viib.err")"
fi
# The pre-v10 b13 (viii) case (a symlinked canonical table refused as "a symlink
# or resolves through one") is RETIRED (T10, C3/S5): v10 resolves the table
# once and refuses a real path outside the guard set instead — b15 (iii)/(iv).

# --- b15: the HEAD read under symlinks — ONE resolution, physical toplevel -------
# The table path is resolved exactly once, by the caller; the byte read, the
# HEAD read and the guard check share that one real path; the rel is taken
# against the physical --show-toplevel and must FULLY match the pre-commit
# guard's set (?:.*/)?references/admitted-providers\.yaml.
TBL=references/admitted-providers.yaml
CANON="$R/$TBL"
# hcommit <path>... — commit into the replica HEADLESS, around the installed
# goalforge pre-commit (the attacker's move the HEAD binding must not trust).
hcommit() {
    "${GITQ[@]}" -C "$R" add -- "$@"
    "${GITQ[@]}" -C "$R" -c core.hooksPath=/dev/null commit -qm "headless" </dev/null >/dev/null 2>&1
}
canon_link() { rm -f "$CANON"; ln -s "$1" "$CANON"; }
canon_restore() { rm -f "$CANON"; "${GITQ[@]}" -C "$R" checkout -q -- "$TBL"; }
b15_refused() { # <name> <substring>
    if [ "$RC" -eq 2 ] && err_has "$1" "$2" && [ ! -f "$T/$1/wp-fx-admitted.js" ]; then
        ok "b15 $1 -> exit 2 ($2)"
    else
        bad "b15 $1 -> exit 2 ($2) (rc=$RC): $(cat "$T/$1.err")"
    fi
}
# (i)/(ii) known-good: the committed replica reached through a symlinked parent
# (the LOGICAL path is passed; PKG_ROOT is resolved in production, so this is
# the only way the ancestor case is exercised, O7).
RLINK="$T/replica-link"
ln -s "$R" "$RLINK"
case_b15_i() {
    local RCOMPILE="$RLINK/scripts/goalforge-workflow-compile.py"
    local WPA="$RLINK/scripts/tests/fixtures/dispatch/wp-admitted.md"
    seam_compile b15-i "$RLINK/scripts/tests/fixtures/admission/admitted-ok/$TBL" "$D_ADM"
    if [ "$RC" -eq 0 ] && [ -f "$T/b15-i/wp-fx-admitted.js" ]; then
        ok "b15(i) a committed table reached through a symlinked ancestor admits exactly as b1"
    else
        bad "b15(i) symlinked-ancestor table (rc=$RC): $(cat "$T/b15-i.err")"
    fi
    "${GITQ[@]}" -C "$R" show HEAD:scripts/tests/fixtures/dispatch/wp-admitted.md > "$T/b15-head.md"
    if [ "$RC" -eq 0 ] && cmp -s "$R/scripts/tests/fixtures/dispatch/leaf-brief.txt" "$T/b15-head.md"; then
        ok "b15(ii) a tracked overview reached through a symlinked ancestor: brief = git show HEAD:<physical rel>"
    else
        bad "b15(ii) symlinked-ancestor overview brief (rc=$RC)"
    fi
}
case_b15_i
PICK_PY=scripts/goalforge-pick-agent.py
COMPILE_PY=scripts/goalforge-workflow-compile.py
# (a) the lap-7 code: a logical path reaches the table binding / the overview's
# HEAD read, which refuse any path whose abspath differs from its realpath —
# RED on (i) and (ii).
red "b15(a) lap-7 abspath-vs-realpath refusal" "b15(i)" \
    "$ADM_PY:lap7-head-refusal" "$ADM_PY:lap7-table-refusal" \
    "$COMPILE_PY:brief-abspath" -- case_b15_i
red "b15(a) lap-7 abspath-vs-realpath refusal, overview" "b15(ii)" \
    "$ADM_PY:lap7-head-refusal" "$COMPILE_PY:brief-abspath" -- case_b15_i
# (b) rel = relpath(abspath(path), physical --show-toplevel) — RED on (i).
red "b15(b) table rel from the logical path against the physical toplevel" "b15(i)" \
    "$ADM_PY:table-rel-logical" -- case_b15_i

# setup_commit <repo> <path>... — an admitting / guard-set-matching SETUP
# commit made around the installed guard with core.hooksPath=/dev/null (setup
# only, never a weakened hook); preflight: git show HEAD:<path> returns the
# working-tree bytes, or the harness fails loudly.
setup_commit() {
    local repo="$1" p; shift
    "${GITQ[@]}" -C "$repo" add -- "$@"
    "${GITQ[@]}" -C "$repo" -c core.hooksPath=/dev/null commit -qm "setup" </dev/null >/dev/null 2>&1
    for p in "$@"; do
        if [ -f "$repo/$p" ] && ! cmp -s <("${GITQ[@]}" -C "$repo" show "HEAD:$p" 2>/dev/null) "$repo/$p"; then
            bad "setup preflight: git show HEAD:$p in $repo does not return the intended bytes"
        fi
    done
}
b15_rej() { # <name> — no workflow written, compile refused
    [ "$RC" -eq 2 ] && [ ! -f "$T/$1/wp-fx-admitted.js" ]
}
INSIDE="is a symlink located inside the package work tree"

# (iii) the canonical table -> a symlink to a headless-committed evil/ table.
mkdir -p "$R/evil"
cp "$RFX/admitted-ok/$TBL" "$R/evil/admitted-providers.yaml"
hcommit evil/admitted-providers.yaml
case_b15_iii() {
    canon_link ../evil/admitted-providers.yaml
    seam_compile b15-iii - "$D_ADM"
    b15_refused b15-iii "$INSIDE"
    canon_restore
}
# (iv) references/ -> a symlink to a headless-committed evil2/ directory.
cp -r "$R/references" "$R/evil2"
hcommit evil2
case_b15_iv() {
    mv "$R/references" "$T/references.real"
    ln -s evil2 "$R/references"
    seam_compile b15-iv - "$D_ADM"
    b15_refused b15-iv "$INSIDE"
    rm -f "$R/references"
    mv "$T/references.real" "$R/references"
}
case_b15_iii
case_b15_iv

# (v-a) the seam pointed DIRECTLY at an admitting table committed in a
# SEPARATE, GUARDED repository nested inside PKG_ROOT (git init one level above
# its own references/; admitting commit first, goalforge pre-commit installed
# after): its own HEAD would admit and its own guard pass, but the binding's
# git calls run at the package's top level, where the rel is absent from HEAD.
mkdir -p "$R/nested/references"
cp "$RFX/admitted-ok/$TBL" "$R/nested/$TBL"
"${GITQ[@]}" -C "$R/nested" init -q
setup_commit "$R/nested" "$TBL"
env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    bash "$R/scripts/goalforge-install-hooks.sh" "$R/nested" >/dev/null
case_b15_va() {
    seam_compile b15-va "$R/nested/$TBL" "$D_ADM"
    b15_refused b15-va "absent from HEAD"
}
case_b15_va
# (d) git anchored at the resolved table's own directory (the 03dcf88
# anchoring) — RED on (v-a) (compile rc 0); (v-b) below.
red "b15(d) table binding anchored at the table's own directory, (v-a)" "b15 b15-va" \
    "$ADM_PY:anchor-at-table-dir" -- case_b15_va

# (vi) the seam DIRECTLY at a headless-committed guard-set-looking name whose
# final byte is a newline (refused by the control-character check).
NL_DIR="$R/evil3/references"
mkdir -p "$NL_DIR"
cp "$RFX/admitted-ok/$TBL" "$NL_DIR/admitted-providers.yaml"$'\n'
hcommit "evil3/references/admitted-providers.yaml"$'\n'
case_b15_vi() {
    seam_compile b15-vi "$NL_DIR/admitted-providers.yaml"$'\n' "$D_ADM"
    b15_refused b15-vi "HEAD binding refused"
}
# (vii) the seam DIRECTLY at evilreferences/ — a whole-string match refuses it.
mkdir -p "$R/evilreferences"
cp "$RFX/admitted-ok/$TBL" "$R/evilreferences/admitted-providers.yaml"
hcommit evilreferences/admitted-providers.yaml
case_b15_vii() {
    seam_compile b15-vii "$R/evilreferences/admitted-providers.yaml" "$D_ADM"
    b15_refused b15-vii "outside the guarded set"
}
# (xiv) the seam DIRECTLY at evil<TAB>/references/admitted-providers.yaml: a
# rel re.fullmatch admits (`.` matches a tab); only the control-character
# refusal rejects it.
TAB_DIR="$R/evil"$'\t'"/references"
mkdir -p "$TAB_DIR"
cp "$RFX/admitted-ok/$TBL" "$TAB_DIR/admitted-providers.yaml"
hcommit "evil"$'\t'"/references/admitted-providers.yaml"
case_b15_xiv() {
    seam_compile b15-xiv "$TAB_DIR/admitted-providers.yaml" "$D_ADM"
    b15_refused b15-xiv "control character"
}
if "${GITQ[@]}" -C "$R" cat-file -e "HEAD:evil3/references/admitted-providers.yaml"$'\n' 2>/dev/null \
   && "${GITQ[@]}" -C "$R" cat-file -e HEAD:evilreferences/admitted-providers.yaml 2>/dev/null \
   && "${GITQ[@]}" -C "$R" cat-file -e HEAD:evil/admitted-providers.yaml 2>/dev/null \
   && "${GITQ[@]}" -C "$R" cat-file -e HEAD:evil2/admitted-providers.yaml 2>/dev/null \
   && "${GITQ[@]}" -C "$R" cat-file -e "HEAD:evil"$'\t'"/references/admitted-providers.yaml" 2>/dev/null; then
    ok "b15 setup: the attacker tables are committed headless (evil/, evil2/, newline name, evilreferences/, TAB name)"
else
    bad "b15 setup: an attacker table is not in the replica's HEAD"
fi
case_b15_vi
case_b15_vii
case_b15_xiv
# (c) single-condition: no fullmatch, control-character refusal kept — RED on (vii).
red "b15(c) no guard-set fullmatch" "b15 b15-vii" "$ADM_PY:no-guard-set" -- case_b15_vii
# (e) historical regression lock: re.search + `$` AND no control-char check — RED on (vi).
red "b15(e) guard-set re.search with a trailing \$, no control-char check" "b15 b15-vi" \
    "$ADM_PY:guard-set-search-dollar" -- case_b15_vi
# (f) unanchored re.search + \Z — RED on (vii).
red "b15(f) guard-set unanchored re.search + \\Z" "b15 b15-vii" \
    "$ADM_PY:guard-set-search-z" -- case_b15_vii
# (l) control-character refusal dropped, fullmatch kept — RED on (xiv).
red "b15(l) no control-character refusal" "b15 b15-xiv" \
    "$ADM_PY:no-control-char" -- case_b15_xiv

# --- b15 (ix)-(xiii), (xv), (v-b): H1-v8 attacks on an EMPTY-table replica -------
# The replica's setup commit holds the shipped EMPTY table at the canonical
# path (admitting fixtures only at their T12 paths), so each attack is the only
# admitting route. Each runs the compile AND the wrapper call verbatim with the
# leaf marker checked.
RA="$T/replica-attack"
mk_replica "$RA" git empty
RA_CANON="$RA/$TBL"
ADMIT_SRC="$RA/scripts/tests/fixtures/admission/admitted-ok/$TBL"
printf 'attack brief\n' > "$T/attack-brief.txt"
RA_CALL="scripts/goalforge-leaf-exec.sh code/py ollama glm-5.3:cloud < $T/attack-brief.txt"
if cmp -s <("${GITQ[@]}" -C "$RA" show "HEAD:$TBL") "$PKG/$TBL" \
   && cmp -s <("${GITQ[@]}" -C "$RA" show "HEAD:scripts/tests/fixtures/admission/admitted-ok/$TBL") "$ADMIT_SRC" \
   && ! cmp -s "$PKG/$TBL" "$ADMIT_SRC"; then
    ok "b15 attack setup: HEAD holds the shipped empty table at the canonical path, the admitting fixture at its T12 path"
else
    bad "b15 attack setup: the attack replica's HEAD is not as pinned"
fi
ra_canon_link() { rm -f "$RA_CANON"; ln -s "$1" "$RA_CANON"; }
ra_canon_restore() { rm -f "$RA_CANON"; "${GITQ[@]}" -C "$RA" checkout -q -- "$TBL"; }
# attack <name> <label> <compile substring|-> <wrapper substring>
attack() {
    local RCOMPILE="$RA/scripts/goalforge-workflow-compile.py"
    local WPA="$RA/scripts/tests/fixtures/dispatch/wp-admitted.md" crc good=1
    seam_compile "$1" - "$D_ADM"; crc=$RC
    rm -f "$MARK"
    ( cd "$RA" && LEAF_MARKER="$MARK" LEAF_EXIT=7 bash -c "$RA_CALL" ) >/dev/null 2>"$T/$1.wrap.err"
    RC=$?
    [ "$crc" -eq 2 ] && [ ! -f "$T/$1/wp-fx-admitted.js" ] || good=0
    [ "$3" = - ] || err_has "$1" "$3" || good=0
    [ "$RC" -eq 2 ] && [ ! -f "$MARK" ] && grep -qF -- "$4" "$T/$1.wrap.err" || good=0
    if [ "$good" -eq 1 ]; then
        ok "b15 $1 $2 -> compile exit 2, wrapper exit 2, leaf marker absent"
    else
        bad "b15 $1 $2 (compile rc=$crc, wrapper rc=$RC, marker=$([ -f "$MARK" ] && echo yes || echo no)): $(cat "$T/$1.err" "$T/$1.wrap.err")"
    fi
}
# evil_commit <parent|-> — a commit of HEAD's tree with the canonical table
# admitting, built with hash-object + commit-tree; no ref moves.
evil_commit() {
    local idx="$T/evil.idx" blob tree
    rm -f "$idx"
    blob="$("${GITQ[@]}" -C "$RA" hash-object -w "$ADMIT_SRC")"
    env GIT_INDEX_FILE="$idx" "${GITQ[@]}" -C "$RA" read-tree HEAD
    env GIT_INDEX_FILE="$idx" "${GITQ[@]}" -C "$RA" update-index --cacheinfo "100644,$blob,$TBL"
    tree="$(env GIT_INDEX_FILE="$idx" "${GITQ[@]}" -C "$RA" write-tree)"
    if [ "$1" = - ]; then
        "${GITQ[@]}" -C "$RA" commit-tree "$tree" -m evil
    else
        "${GITQ[@]}" -C "$RA" commit-tree "$tree" -p "$1" -m evil
    fi
}

# (ix) the canonical table -> a FILE symlink to the committed admitting fixture.
case_b15_ix() {
    ra_canon_link ../scripts/tests/fixtures/admission/admitted-ok/references/admitted-providers.yaml
    attack b15-ix "canonical table -> committed fixture (file symlink)" "$INSIDE" "$INSIDE"
    ra_canon_restore
}
# (x) references/ -> a DIRECTORY symlink to the committed fixture's references/.
case_b15_x() {
    mv "$RA/references" "$T/ra-references.real"
    ln -s scripts/tests/fixtures/admission/admitted-ok/references "$RA/references"
    attack b15-x "references/ -> committed fixture directory (dir symlink)" "$INSIDE" "$INSIDE"
    rm -f "$RA/references"
    mv "$T/ra-references.real" "$RA/references"
}
# (xi) revocation replay: an admitting canonical table committed, then revoked
# (the empty table committed back); a linked worktree at the pre-revocation
# commit supplies the bytes through a canonical-table symlink.
cp "$ADMIT_SRC" "$RA_CANON"
setup_commit "$RA" "$TBL"
PRE_REVOKE="$("${GITQ[@]}" -C "$RA" rev-parse HEAD)"
cp "$PKG/$TBL" "$RA_CANON"
setup_commit "$RA" "$TBL"
rm -f "$MARK"
( cd "$RA" && LEAF_MARKER="$MARK" bash -c "$RA_CALL" ) >/dev/null 2>"$T/revoked.wrap.err"
if [ "$?" -eq 2 ] && [ ! -f "$MARK" ]; then
    ok "b15(xi) control: after the revocation commit the wrapper alone exits 2, leaf NOT executed"
else
    bad "b15(xi) control: the revoked table still runs the leaf: $(cat "$T/revoked.wrap.err")"
fi
"${GITQ[@]}" -C "$RA" worktree add -q --detach "$RA/.wt-old" "$PRE_REVOKE" >/dev/null 2>&1
case_b15_xi() {
    ra_canon_link ../.wt-old/references/admitted-providers.yaml
    attack b15-xi "revocation replay through a linked worktree at the pre-revocation commit" "$INSIDE" "$INSIDE"
    ra_canon_restore
}
# (xii) an unguarded commit-tree commit (no branch moves) checked out as a
# linked worktree .wt inside PKG_ROOT; the canonical table links into it.
EVIL_SHA="$(evil_commit HEAD)"
"${GITQ[@]}" -C "$RA" worktree add -q --detach "$RA/.wt" "$EVIL_SHA" >/dev/null 2>&1
case_b15_xii() {
    ra_canon_link ../.wt/references/admitted-providers.yaml
    attack b15-xii "commit-tree linked worktree" "$INSIDE" "$INSIDE"
    ra_canon_restore
}
# (xiii) a fresh repository OUTSIDE PKG_ROOT: table committed first, the
# goalforge marker hook written afterwards; the canonical table links to it.
OUTREPO="$T/outrepo"
mkdir -p "$OUTREPO/references"
cp "$ADMIT_SRC" "$OUTREPO/$TBL"
"${GITQ[@]}" -C "$OUTREPO" init -q
setup_commit "$OUTREPO" "$TBL"
printf '#!/usr/bin/env bash\n# >>> sdd-pre-commit >>>\nbash "%s" || exit $?\n# <<< sdd-pre-commit <<<\n' \
    "$(realpath "$RA")/hooks/goalforge-pre-commit.sh" > "$OUTREPO/.git/hooks/pre-commit"
chmod +x "$OUTREPO/.git/hooks/pre-commit"
case_b15_xiii() {
    ra_canon_link "$OUTREPO/$TBL"
    attack b15-xiii "out-of-root repository behind a canonical-table symlink" - "$INSIDE"
    ra_canon_restore
}
if cmp -s <("${GITQ[@]}" -C "$RA" show "$PRE_REVOKE:$TBL") "$ADMIT_SRC" \
   && cmp -s <("${GITQ[@]}" -C "$RA" show "$EVIL_SHA:$TBL") "$ADMIT_SRC" \
   && cmp -s "$RA/.wt/$TBL" "$ADMIT_SRC" && cmp -s "$RA/.wt-old/$TBL" "$ADMIT_SRC" \
   && [ "$("${GITQ[@]}" -C "$RA" rev-parse HEAD)" != "$EVIL_SHA" ]; then
    ok "b15 attack setup: pre-revocation and commit-tree commits admit, worktrees checked out, the branch never at the commit-tree commit"
else
    bad "b15 attack setup: a linked worktree or its commit is not as pinned"
fi
case_b15_ix
case_b15_x
case_b15_xi
case_b15_xii
case_b15_xiii
# (v-b) the seam DIRECTLY (no symlink) at .wt's table: the rel .wt/references/…
# is absent from the package HEAD, since git runs at the package's top level.
case_b15_vb() {
    local RCOMPILE="$RA/scripts/goalforge-workflow-compile.py"
    local WPA="$RA/scripts/tests/fixtures/dispatch/wp-admitted.md"
    seam_compile b15-vb "$RA/.wt/$TBL" "$D_ADM"
    b15_refused b15-vb "absent from HEAD"
}
case_b15_vb
RED_ROOT="$RA" red "b15(d) table binding anchored at the table's own directory, (v-b)" "b15 b15-vb" \
    "$ADM_PY:anchor-at-table-dir" -- case_b15_vb

# (xv) replace objects, no symlink and no worktree; the branch ref never moves.
case_b15_xva() {
    local old blob
    old="$("${GITQ[@]}" -C "$RA" rev-parse "HEAD:$TBL")"
    blob="$("${GITQ[@]}" -C "$RA" hash-object -w "$ADMIT_SRC")"
    "${GITQ[@]}" -C "$RA" replace "$old" "$blob"
    cp "$ADMIT_SRC" "$RA_CANON"
    attack b15-xva "git replace <HEAD table blob> <admitting blob>" "differs from git show HEAD" "differs from git show HEAD"
    "${GITQ[@]}" -C "$RA" replace -d "$old" >/dev/null
    ra_canon_restore
}
case_b15_xvb() {
    local head evil
    head="$("${GITQ[@]}" -C "$RA" rev-parse HEAD)"
    evil="$(evil_commit -)"
    "${GITQ[@]}" -C "$RA" replace "$head" "$evil"
    cp "$ADMIT_SRC" "$RA_CANON"
    "${GITQ[@]}" -C "$RA" add -- "$TBL"
    if [ -z "$("${GITQ[@]}" -C "$RA" status --short --untracked-files=no)" ]; then
        ok "b15(xv-b) setup: git status is clean under the replaced HEAD"
    else
        bad "b15(xv-b) setup: git status is not clean: $("${GITQ[@]}" -C "$RA" status --short --untracked-files=no)"
    fi
    attack b15-xvb "git replace <HEAD> <admitting commit>" "differs from git show HEAD" "differs from git show HEAD"
    "${GITQ[@]}" -C "$RA" replace -d "$head" >/dev/null
    "${GITQ[@]}" -C "$RA" reset -q -- "$TBL"
    ra_canon_restore
}
case_b15_xva
case_b15_xvb

# Known-bads, RED by compile rc 0 plus the wrapper marker written (g, h, i, m)
# or by the marker alone (k).
for c in ix x xi xii; do
    RED_ROOT="$RA" red "b15(g) historical lock: the 03dcf88 binding, ($c)" "marker=yes" \
        "$ADM_PY:binding-03dcf88" -- "case_b15_$c"
done
RED_ROOT="$RA" red "b15(h) a walk refusing a symlink only at the table file" "marker=yes" \
    "$ADM_PY:walk-file-only" -- case_b15_x
for c in ix x; do
    RED_ROOT="$RA" red "b15(i) the walk replaced by one full realpath, ($c)" "marker=yes" \
        "$ADM_PY:walk-full-realpath" -- "case_b15_$c"
done
RED_ROOT="$RA" red "b15(k) verify_leaf binding as the 03dcf88 wrapper did" "marker=yes" \
    "$ADM_PY:verify-leaf-own-binding" -- case_b15_xiii
RED_ROOT="$RA" red "b15(m) _git_env without GIT_NO_REPLACE_OBJECTS, (xv-a)" "marker=yes" \
    "$ADM_PY:no-replace-flag" -- case_b15_xva
RED_ROOT="$RA" red "b15(m) _git_env without GIT_NO_REPLACE_OBJECTS, (xv-b)" "marker=yes" \
    "$ADM_PY:no-replace-flag" -- case_b15_xvb

# Structural (T13): table-anchor and shared-binding, each with its mutant.
structural_case() { # <mode>
    local line
    while IFS= read -r line; do
        case "$line" in ok*) ok "${line#ok }" ;; *) bad "${line#bad }" ;; esac
    done < <(python3 "$ADM_FX/structural.py" "$1" "$R/$ADM_PY")
}
case_table_anchor() { structural_case table-anchor; }
case_shared_binding() { structural_case shared-binding; }
case_table_anchor
case_shared_binding
red "b15(d) structural: the HEAD read anchored at the table's directory" "table-anchor" \
    "$ADM_PY:anchor-at-table-dir" -- case_table_anchor
red "b15(k) structural: verify_leaf with its own table resolution" "shared-binding" \
    "$ADM_PY:verify-leaf-own-binding" -- case_shared_binding

# (viii) the WP overview.md itself a symlink to ANOTHER repository's tracked
# overview: accepted (C8) — brief = the target's HEAD bytes, written beside it.
OTHER="$T/other-repo"
mkdir -p "$OTHER/wp" "$T/overview-link"
cp "$WPA" "$OTHER/wp/overview.md"
"${GITQ[@]}" -C "$OTHER" init -q
"${GITQ[@]}" -C "$OTHER" add wp/overview.md
"${GITQ[@]}" -C "$OTHER" commit -qm other
printf '\nWORKING-TREE EDIT IN THE OTHER REPO\n' >> "$OTHER/wp/overview.md"
ln -s "$OTHER/wp/overview.md" "$T/overview-link/overview.md"
WPA_SAVE="$WPA"; WPA="$T/overview-link/overview.md"
seam_compile b15-viii "$RFX/admitted-ok/$TBL" "$D_ADM"
WPA="$WPA_SAVE"
"${GITQ[@]}" -C "$OTHER" show HEAD:wp/overview.md > "$T/other-head.md"
if [ "$RC" -eq 0 ] && cmp -s "$OTHER/wp/leaf-brief.txt" "$T/other-head.md" \
   && [ ! -e "$T/overview-link/leaf-brief.txt" ]; then
    ok "b15(viii) a symlinked overview.md -> exit 0, brief = the target repo's HEAD bytes, written in the target's directory"
else
    bad "b15(viii) symlinked overview (rc=$RC): $(cat "$T/b15-viii.err")"
fi

# single-resolution (named structural test, TABLE path only; no discriminator
# for the swap race, which no deterministic case can show).
case_single_resolution() {
    local line
    while IFS= read -r line; do
        case "$line" in ok*) ok "${line#ok }" ;; *) bad "${line#bad }" ;; esac
    done < <(python3 "$ADM_FX/structural.py" single-resolution "$R/$ADM_PY")
}
case_single_resolution
red "single-resolution: the guard check re-resolving the table" "single-resolution" \
    "$ADM_PY:resolve-table-dir" -- case_single_resolution

# --- b16: the brief source — HEAD when tracked, else the working tree -----------
# Tracked = in the index of the repository enclosing the overview's REAL path.
last_ledger() { tail -1 "$GOALFORGE_DISPATCH_LEDGER" | lget "$1"; }
brief_compile() { # <name> <overview>  -> RC, the brief file beside the overview
    local WPA="$2"
    seam_compile "$1" "$RFX/admitted-ok/$TBL" "$D_ADM"
}
# (i) tracked and committed.
case_b16_i() {
    brief_compile b16-i "$WPA"
    "${GITQ[@]}" -C "$R" show HEAD:scripts/tests/fixtures/dispatch/wp-admitted.md > "$T/b16-head.md"
    if [ "$RC" -eq 0 ] && cmp -s "$(dirname "$WPA")/leaf-brief.txt" "$T/b16-head.md" \
       && [ "$(last_ledger brief_source)" = "head" ]; then
        ok "b16(i) a tracked overview -> brief = git show HEAD:<overview>, ledger brief_source: head"
    else
        bad "b16(i) tracked overview (rc=$RC, brief_source=$(last_ledger brief_source)): $(cat "$T/b16-i.err")"
    fi
}
# (ii) the replica's .gitignore ignores plans/ and plans/ has no repository.
printf 'plans/\n' >> "$R/.gitignore"
mkdir -p "$R/plans/feat/wp"
cp "$WPA" "$R/plans/feat/wp/overview.md"
printf '\nIGNORED WORKING-TREE OVERVIEW\n' >> "$R/plans/feat/wp/overview.md"
case_b16_ii() {
    local ov="$R/plans/feat/wp/overview.md" call
    brief_compile b16-ii "$ov"
    call="$(leg_field "$T/b16-ii/wp-fx-admitted.js" wrapper_call 2>/dev/null)"
    rm -f "$MARK"
    [ -n "$call" ] && ( cd "$R" && LEAF_MARKER="$MARK" bash -c "$call" ) >/dev/null 2>"$T/wrap.err"
    if [ "$RC" -eq 0 ] && cmp -s "$R/plans/feat/wp/leaf-brief.txt" "$ov" \
       && [ "$(last_ledger brief_source)" = "worktree" ] && [ -f "$MARK" ]; then
        ok "b16(ii) a gitignored overview -> exit 0, brief = working-tree bytes, brief_source: worktree, the leaf runs"
    else
        bad "b16(ii) gitignored overview (rc=$RC, brief_source=$(last_ledger brief_source), marker=$([ -f "$MARK" ] && echo yes || echo no)): $(cat "$T/b16-ii.err" "$T/wrap.err" 2>/dev/null)"
    fi
}
# (iv) staged but never committed: tracked, absent from HEAD -> exit 2.
mkdir -p "$R/staged/wp"
cp "$WPA" "$R/staged/wp/overview.md"
"${GITQ[@]}" -C "$R" add staged/wp/overview.md
case_b16_iv() {
    brief_compile b16-iv "$R/staged/wp/overview.md"
    if [ "$RC" -eq 2 ] && err_has b16-iv "leaf brief" && err_has b16-iv "absent from HEAD" \
       && [ ! -f "$T/b16-iv/wp-fx-admitted.js" ]; then
        ok "b16(iv) a staged, never-committed overview -> exit 2 (tracked, HEAD read fails closed)"
    else
        bad "b16(iv) staged overview (rc=$RC): $(cat "$T/b16-iv.err")"
    fi
}
# (vi) untracked, not ignored, inside the work tree.
mkdir -p "$R/untracked/wp"
cp "$WPA" "$R/untracked/wp/overview.md"
case_b16_vi() {
    brief_compile b16-vi "$R/untracked/wp/overview.md"
    if [ "$RC" -eq 0 ] && cmp -s "$R/untracked/wp/leaf-brief.txt" "$R/untracked/wp/overview.md" \
       && [ "$(last_ledger brief_source)" = "worktree" ]; then
        ok "b16(vi) an untracked overview -> exit 0, working-tree bytes, brief_source: worktree"
    else
        bad "b16(vi) untracked overview (rc=$RC, brief_source=$(last_ledger brief_source)): $(cat "$T/b16-vi.err")"
    fi
}
case_b16_i
case_b16_ii
case_b16_iv
case_b16_vi
red "b16(a) a compile that always reads HEAD" "b16(ii)" "$COMPILE_PY:brief-always-head" -- case_b16_ii
red "b16(b) a compile that always reads the working tree" "b16(i)" "$COMPILE_PY:brief-always-worktree" -- case_b16_i
red "b16(c) a ledger row with no brief_source, (i)" "b16(i)" "$PICK_PY:brief-source-dropped" -- case_b16_i
red "b16(c) a ledger row with no brief_source, (ii)" "b16(ii)" "$PICK_PY:brief-source-dropped" -- case_b16_ii
red "b16(d) a worktree fallback on any HEAD-read failure" "b16(iv)" "$COMPILE_PY:brief-fail-open" -- case_b16_iv
# (v) cogwright's layout: plans/ ignored by the outer repo but its OWN nested
# repository tracks the overview -> the NESTED repository's HEAD, brief_source head.
"${GITQ[@]}" -C "$R/plans" init -q
"${GITQ[@]}" -C "$R/plans" add feat/wp/overview.md
"${GITQ[@]}" -C "$R/plans" commit -qm plans
"${GITQ[@]}" -C "$R/plans" show HEAD:feat/wp/overview.md > "$T/b16-nested-head.md"
printf '\nUNCOMMITTED EDIT IN THE NESTED PLANS REPO\n' >> "$R/plans/feat/wp/overview.md"
case_b16_v() {
    brief_compile b16-v "$R/plans/feat/wp/overview.md"
    if [ "$RC" -eq 0 ] && cmp -s "$R/plans/feat/wp/leaf-brief.txt" "$T/b16-nested-head.md" \
       && [ "$(last_ledger brief_source)" = "head" ]; then
        ok "b16(v) a nested plans/ repository tracking the overview -> the NESTED HEAD bytes, brief_source: head"
    else
        bad "b16(v) nested plans repository (rc=$RC, brief_source=$(last_ledger brief_source)): $(cat "$T/b16-v.err")"
    fi
}
case_b16_v
red "b16(e) tracked-ness asked of the OUTER repository" "b16(v)" "$ADM_PY:brief-outer-repo" -- case_b16_v
rm -rf "$R/plans" "$R/untracked"
"${GITQ[@]}" -C "$R" rm -q --cached staged/wp/overview.md
rm -rf "$R/staged"
"${GITQ[@]}" -C "$R" checkout -q -- .gitignore 2>/dev/null || rm -f "$R/.gitignore"
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

# --- b12 (xiii): an in-root intermediate symlinked directory on the LEAF path ----
# Rule (c) (OQ11 item 3): <leaf root>/alias -> <leaf root>/real sits BETWEEN the
# leaf root and the entry's directory; the row names alias/<entry dir>/<entry>,
# its closure keyed by the real path, committed in the replica's canonical
# table as setup (core.hooksPath=/dev/null). Known-good: the leaf runs. Last in
# the file: the re-pinned canonical table no longer matches the dispatch row.
mkdir -p "$CLAUDE_CONFIG_DIR/real/$(dirname "$LEAF_REL")"
cp -r "$ADM_FX/leaf/." "$CLAUDE_CONFIG_DIR/real/$(dirname "$LEAF_REL")/"
chmod +x "$CLAUDE_CONFIG_DIR/real/$LEAF_REL"
ln -s real "$CLAUDE_CONFIG_DIR/alias"
python3 -c '
import sys, yaml
path, leaf = sys.argv[1], sys.argv[2]
data = yaml.safe_load(open(path, encoding="utf-8"))
for row in data["admitted"]:
    row["leaf"] = "alias/" + leaf
    row["leaf_closure"] = {"real/" + k: v for k, v in row["leaf_closure"].items()}
open(path, "w", encoding="utf-8").write(yaml.safe_dump(data, sort_keys=False))
' "$CANON" "$LEAF_REL"
setup_commit "$R" "$TBL"
case_b12_xiii() {
    rm -f "$MARK"
    ( cd "$R" && LEAF_MARKER="$MARK" LEAF_EXIT=7 bash -c "$CALL" ) >/dev/null 2>"$T/wrap.err"
    RC=$?
    if [ "$RC" -eq 7 ] && [ -f "$MARK" ]; then
        ok "b12(xiii) an in-root symlinked directory between the leaf root and the entry's directory is resolved -> the leaf runs (7)"
    else
        bad "b12(xiii) in-root intermediate directory symlink (rc=$RC, marker=$([ -f "$MARK" ] && echo yes || echo no)): $(cat "$T/wrap.err")"
    fi
}
case_b12_xiii
# (o) a rule (c) refusing that intermediate directory symlink — marker-RED on (xiii).
red "b12(o) rule (c) refusing an in-root intermediate directory symlink" "b12(xiii)" \
    "$ADM_PY:leaf-refuse-intermediate-dir" -- case_b12_xiii

echo
echo "goalforge-workflow-compile.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
