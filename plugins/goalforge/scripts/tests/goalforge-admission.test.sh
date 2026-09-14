#!/usr/bin/env bash
# goalforge-admission.test.sh — wp-06 provider admission (b1-b8).
#
# The admission table decides the resolver verdict for role `implement`:
# a foreign or local provider executes only when a row names its task class,
# its provider AND its model, with closed-kind evidence and a permission set.
#
#   b1 refused        b2 admitted       b3 six sabotage rows
#   b4 shipped-empty + no-flag + no-native-fallback (3 known-bads)
#   b5 model binding  b6 task class     b7 invariant text  b8 lint lists
#
# Every known-bad is an ANCHORED mutation (fixtures/admission/mutate.py) of a
# COPY of the package under a mktemp root — the shipped tree is never edited,
# except by b8's py_compile sabotage, which restores on every exit path.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$SD/../.." && pwd)"
PICK="$PKG/scripts/goalforge-pick-agent.py"
ADM="$PKG/scripts/goalforge-admission.py"
F="$SD/fixtures/admission"
MUTATE="$F/mutate.py"
PHRASE="$F/phrase.py"
RUN_SH="$PKG/evals/run.sh"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
LEDGER="$T/ledger/dispatch-decisions.jsonl"
export GOALFORGE_DISPATCH_LEDGER="$LEDGER"

jget()  { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1],""))' "$1"; }
lget()  { python3 -c 'import json,sys; print(json.loads(sys.stdin.readline()).get(sys.argv[1],""))' "$1"; }
rows()  { [[ -f "$LEDGER" ]] && wc -l < "$LEDGER" | tr -d ' ' || echo 0; }
reset() { rm -rf "$T/ledger"; }

# ── b1: refused — the WP's task class has no row ─────────────────────────
reset
OUT="$(python3 "$PICK" --task "$F/wp-code-sh.md" --role implement \
       --dispatch "$F/dispatch-ollama.yaml" --admitted "$F/admitted-ok.yaml" \
       --wp wp-fx 2>"$T/err")"
RC=$?
PROV="$(printf '%s' "$OUT" | jget provider)"
PO="$(printf '%s' "$OUT" | jget propose_only)"
REASON="$(printf '%s' "$OUT" | jget admission_reason)"
if [[ "$RC" -eq 0 && "$PROV" == "anthropic" && "$PO" == "False" ]] \
   && [[ "$REASON" == *"code/sh"* ]]; then
    ok "b1 refused: the native provider resolves, propose_only false, reason names code/sh"
else
    bad "b1 refused (rc=$RC, provider=$PROV, propose_only=$PO, reason=$REASON)"
fi
if [[ "$(rows)" == "1" ]]; then
    ok "b1 refused: exactly one ledger row"
else
    bad "b1 refused: exactly one ledger row (got $(rows))"
fi
WANT_SRC="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$F/admitted-ok.yaml")"
if [[ "$(lget decision <"$LEDGER")" == "refused" ]] \
   && [[ "$(lget task_class <"$LEDGER")" == "code/sh" ]] \
   && [[ "$(lget provider <"$LEDGER")" == "ollama" ]] \
   && [[ "$(lget model <"$LEDGER")" == "glm-5.3:cloud" ]] \
   && [[ -n "$(lget reason <"$LEDGER")" ]] \
   && [[ "$(lget admitted_source <"$LEDGER")" == "$WANT_SRC" ]] \
   && [[ "$(lget admitted_override <"$LEDGER")" == "True" ]]; then
    ok "b1 refused: the ledger row names the REFUSED provider/model, the task class, the fixture table and admitted_override true"
else
    bad "b1 refused ledger row: $(cat "$LEDGER")"
fi

# ── b2: admitted ─────────────────────────────────────────────────────────
reset
OUT="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-ollama.yaml" --admitted "$F/admitted-ok.yaml" \
       --wp wp-fx 2>"$T/err")"
RC=$?
if [[ "$RC" -eq 0 ]] \
   && [[ "$(printf '%s' "$OUT" | jget provider)" == "ollama" ]] \
   && [[ "$(printf '%s' "$OUT" | jget propose_only)" == "False" ]] \
   && [[ "$(printf '%s' "$OUT" | jget model)" == "glm-5.3:cloud" ]] \
   && [[ -n "$(printf '%s' "$OUT" | jget evidence_ref)" ]] \
   && [[ "$(printf '%s' "$OUT" | jget permission_set)" == "['read', 'write']" ]]; then
    ok "b2 admitted: the foreign provider resolves with the row's model, evidence ref and permission set"
else
    bad "b2 admitted (rc=$RC, out=$OUT)"
fi
GOT_C="$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("containment"), sort_keys=True))')"
WANT_C="$(python3 -c '
import json, sys, yaml
text = open(sys.argv[1], encoding="utf-8").read().split("---")[1]
fm = yaml.safe_load(text)
print(json.dumps({"commit": False, "owned_files": fm["owned_files"],
                  "verification_command": fm["goal"]["verification"]["command"]},
                 sort_keys=True))' "$F/wp-code-py.md")"
if [[ "$GOT_C" == "$WANT_C" ]]; then
    ok "b2 admitted: the containment block is byte-equal to the WP fixture"
else
    bad "b2 containment: got $GOT_C, want $WANT_C"
fi
WARNS="$(grep -c 'declared, not enforced' "$T/err")"
if [[ "$WARNS" == "1" ]]; then
    ok "b2 admitted: exactly one stderr WARN says containment and permission_set are declared, not enforced"
else
    bad "b2 admitted WARN count=$WARNS (err=$(cat "$T/err"))"
fi
if [[ "$(rows)" == "1" ]] \
   && [[ "$(lget decision <"$LEDGER")" == "admitted" ]] \
   && [[ -n "$(lget evidence_ref <"$LEDGER")" ]] \
   && [[ "$(lget admitted_source <"$LEDGER")" == "$WANT_SRC" ]] \
   && [[ "$(lget admitted_override <"$LEDGER")" == "True" ]]; then
    ok "b2 admitted: exactly one ledger row carrying the evidence ref, the fixture table and admitted_override true"
else
    bad "b2 admitted ledger (rows=$(rows)): $(cat "$LEDGER" 2>&1)"
fi

# ── b3: six sabotage rows ────────────────────────────────────────────────
for pair in \
    "bad-missing-task-class.yaml|task_class" \
    "bad-missing-provider.yaml|provider" \
    "bad-missing-model.yaml|model" \
    "bad-missing-evidence.yaml|evidence" \
    "bad-missing-permission-set.yaml|permission_set" \
    "bad-self-report.yaml|evidence.kind"; do
    FILE="${pair%%|*}"; KEY="${pair##*|}"
    ERR="$(python3 "$ADM" --table "$F/$FILE" 2>&1)"
    RC=$?
    if [[ "$RC" -eq 2 && "$ERR" == *"row 0"* && "$ERR" == *"'$KEY'"* ]]; then
        ok "b3 $FILE: exit 2 naming row 0 and key '$KEY'"
    else
        bad "b3 $FILE: exit 2 naming row 0 and key '$KEY' (rc=$RC, err=$ERR)"
    fi
done

# ── b4: the shipped table, the no-flag path, and the no-native fallback ──
if python3 "$ADM" >/dev/null 2>&1 \
   && [[ "$(python3 "$ADM" 2>/dev/null)" == "admission table OK: 0 row(s)" ]]; then
    ok "b4 shipped-empty: the shipped admitted-providers.yaml loads clean and admits nobody"
else
    bad "b4 shipped-empty: the shipped table must load at exit 0 with 0 rows ($(python3 "$ADM" 2>&1))"
fi

# The oracle for "the implement STAGE row's model/effort resolved as for a
# native provider": the SAME by_register row on the native provider.
BASE="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
        --dispatch "$F/dispatch-native-baseline.yaml" 2>/dev/null)"
BASE_ME="$(printf '%s' "$BASE" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["model"], d["effort"])')"

reset
OUT="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-foreign-native-fallback.yaml" --wp wp-fx 2>"$T/err")"
RC=$?
GOT_ME="$(printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["model"], d["effort"])' 2>/dev/null)"
NOFLAG_OK=0
if [[ "$RC" -eq 0 ]] \
   && [[ "$(printf '%s' "$OUT" | jget provider)" == "anthropic" ]] \
   && [[ "$(printf '%s' "$OUT" | jget propose_only)" == "False" ]] \
   && [[ "$GOT_ME" == "$BASE_ME" ]] \
   && [[ "$OUT" != *"stub-b\": \"provider"* ]]; then
    NOFLAG_OK=1
fi
if [[ "$NOFLAG_OK" -eq 1 ]]; then
    ok "b4 no-flag: the foreign provider is refused and the native one resolves at the stage row's native band ($GOT_ME), propose_only false"
else
    bad "b4 no-flag (rc=$RC, got='$GOT_ME', want='$BASE_ME', out=$OUT)"
fi
SHIPPED_SRC="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "$PKG/references/admitted-providers.yaml")"
if [[ "$(rows)" == "1" ]] \
   && [[ "$(lget decision <"$LEDGER")" == "refused" ]] \
   && [[ "$(lget provider <"$LEDGER")" == "stub-b" ]] \
   && [[ "$(lget admitted_source <"$LEDGER")" == "$SHIPPED_SRC" ]] \
   && [[ "$(lget admitted_override <"$LEDGER")" == "False" ]]; then
    ok "b4 no-flag: one ledger row names the refused foreign provider, the SHIPPED table and admitted_override false"
else
    bad "b4 no-flag ledger (rows=$(rows)): $(cat "$LEDGER" 2>&1)"
fi

reset
ERR="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-no-native.yaml" 2>&1)"
RC=$?
if [[ "$RC" -eq 2 && "$ERR" == *"no native provider for fallback"* ]]; then
    ok "b4 no-native-fallback: exit 2 naming 'no native provider for fallback'"
else
    bad "b4 no-native-fallback: exit 2 + message (rc=$RC, out=$ERR)"
fi

# known-bads: a mutated COPY of the package must make the case above RED.
KB="$T/kb"
mkdir -p "$KB"
cp -r "$PKG/scripts" "$PKG/references" "$PKG/agents" "$KB/"
rm -rf "$KB/scripts/__pycache__"
kb_pick() {  # $1 = mutation name -> path to the mutated pick-agent
    local dest="$KB/scripts/goalforge-pick-agent.py"
    cp "$PICK" "$dest.orig"
    if ! python3 "$MUTATE" "$1" "$PICK" "$dest" 2>"$T/mut.err"; then
        bad "known-bad $1: mutation anchor missing ($(cat "$T/mut.err"))"
        return 1
    fi
    printf '%s' "$dest"
}

reset
if MUT="$(kb_pick skip-admission-no-flag)"; then
    OUT="$(python3 "$MUT" --task "$F/wp-code-py.md" --role implement \
           --dispatch "$F/dispatch-foreign-native-fallback.yaml" 2>/dev/null)"
    if [[ "$(printf '%s' "$OUT" | jget provider)" != "anthropic" ]] \
       || [[ "$(printf '%s' "$OUT" | jget propose_only)" != "False" ]]; then
        ok "b4 known-bad 1: a no-flag path that skips admission makes the no-flag case red"
    else
        bad "b4 known-bad 1: a no-flag path that skips admission still passes (out=$OUT)"
    fi
fi

reset
if MUT="$(kb_pick keep-refused-provider)"; then
    OUT="$(python3 "$MUT" --task "$F/wp-code-py.md" --role implement \
           --dispatch "$F/dispatch-foreign-native-fallback.yaml" 2>/dev/null)"
    if [[ "$(printf '%s' "$OUT" | jget provider)" != "anthropic" ]]; then
        ok "b4 known-bad 2: a refused branch that keeps the foreign provider makes the no-flag case red"
    else
        bad "b4 known-bad 2: a refused branch that keeps the foreign provider still passes (out=$OUT)"
    fi
fi

reset
if MUT="$(kb_pick no-native-keeps-foreign)"; then
    ERR="$(python3 "$MUT" --task "$F/wp-code-py.md" --role implement \
           --dispatch "$F/dispatch-no-native.yaml" 2>&1)"
    RC=$?
    if [[ "$RC" -ne 2 || "$ERR" != *"no native provider for fallback"* ]]; then
        ok "b4 known-bad 3: resolving the refused row when no native row exists makes the no-native case red"
    else
        bad "b4 known-bad 3: resolving the refused row still exits 2 with the message (rc=$RC)"
    fi
fi

# ── b5: admission binds (task_class, provider, MODEL) ────────────────────
reset
OUT="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-ollama-qwen.yaml" --admitted "$F/admitted-ok.yaml" 2>/dev/null)"
REASON="$(printf '%s' "$OUT" | jget admission_reason)"
if [[ "$(printf '%s' "$OUT" | jget provider)" == "anthropic" ]] \
   && [[ "$REASON" == *"glm-5.3:cloud"* && "$REASON" == *"qwen3-coder:cloud"* ]]; then
    ok "b5 model binding: the same provider on another model is refused, the reason naming both model ids"
else
    bad "b5 model binding (provider=$(printf '%s' "$OUT" | jget provider), reason=$REASON)"
fi

# ── b6: the deterministic task class ─────────────────────────────────────
for pair in "wp-tie-a|code/py" "wp-tie-b|code/py" "wp-no-ext|code/-" \
            "wp-dominant|code/py"; do
    FX="${pair%%|*}"; WANT="${pair##*|}"
    GOT="$(python3 "$ADM" --task-class "$F/$FX.md" 2>&1)"
    if [[ "$GOT" == "$WANT" ]]; then
        ok "b6 $FX -> $WANT"
    else
        bad "b6 $FX -> $WANT (got '$GOT')"
    fi
done

# ── b7: the invariant-text ratchet ───────────────────────────────────────
# (i) one zero-hit grep per retired phrase, over its own file.
while IFS='|' read -r rel phrase; do
    [[ -z "$rel" ]] && continue
    if [[ "$(python3 "$PHRASE" "$PKG/$rel" "$phrase")" == "0" ]]; then
        ok "b7 retired: '$phrase' is gone from $rel"
    else
        bad "b7 retired: '$phrase' still present in $rel"
    fi
done <<'TABLE'
references/schema.md|is ALWAYS propose-only
references/dispatch.yaml|kind != native is ALWAYS propose-only
execute/references/dispatch-resolution.md|is propose-only and appends one row
execute/references/dispatch-resolution.md|admits only the native provider
execute/references/dispatch-resolution.md|Always propose-only.
scripts/goalforge-pick-agent.py|admitted for the native provider only
scripts/goalforge-pick-agent.py|the only admitted kind is
scripts/goalforge-pick-agent.py|Append one propose-only decision row
TABLE

# (ii) every rewritten site carries the one replacement literal.
while IFS='|' read -r rel want; do
    [[ -z "$rel" ]] && continue
    GOT="$(python3 "$PHRASE" "$PKG/$rel" "admission table decides the resolver verdict")"
    if [[ "$GOT" -ge "$want" ]]; then
        ok "b7 present: $rel carries the replacement literal $GOT>=$want time(s)"
    else
        bad "b7 present: $rel carries the replacement literal $GOT time(s), want >=$want"
    fi
done <<'TABLE'
references/schema.md|1
references/dispatch.yaml|2
execute/references/dispatch-resolution.md|3
scripts/goalforge-pick-agent.py|2
TABLE
if [[ "$(python3 "$PHRASE" "$PICK" "dispatch decision row (propose-only | admitted | refused)")" -ge 1 ]]; then
    ok "b7 present: the ledger writer's docstring names all three decisions"
else
    bad "b7 present: the ledger writer's docstring names all three decisions"
fi

# (iii) no site claims the COMPILER admits anything.
B7_FILES=(references/schema.md references/dispatch.yaml
          execute/references/dispatch-resolution.md scripts/goalforge-pick-agent.py)
NEG_HITS=""
for lit in "compiler admits" "compile admits" "--test-tiers admits"; do
    for rel in "${B7_FILES[@]}"; do
        [[ "$(python3 "$PHRASE" "$PKG/$rel" "$lit")" != "0" ]] && NEG_HITS="$NEG_HITS $rel:'$lit'"
    done
done
if [[ -z "$NEG_HITS" ]]; then
    ok "b7 negative: no ratchet file claims the compiler or --test-tiers admits a non-native implement row"
else
    bad "b7 negative: positive-compile claim(s) present:$NEG_HITS"
fi

# The compile-level invariant R2-4 KEEPS must still be stated verbatim.
if [[ "$(python3 "$PHRASE" "$PKG/execute/references/dispatch-resolution.md" \
         "node the compiler emits ever carries a non-Claude model id.")" -ge 1 ]]; then
    ok "b7 kept: dispatch-resolution.md still states the compile-level invariant verbatim"
else
    bad "b7 kept: the compile-level invariant sentence is gone from dispatch-resolution.md"
fi

# ── b8: the lint lists in evals/run.sh ───────────────────────────────────
while IFS='|' read -r marker label; do
    [[ -z "$marker" ]] && continue
    if grep -n -- "$marker" "$RUN_SH" | grep -q 'goalforge-admission\.py'; then
        ok "b8 lint list: the $label invocation names goalforge-admission.py"
    else
        bad "b8 lint list: the $label invocation does NOT name goalforge-admission.py"
    fi
done <<'TABLE'
python3 -m py_compile "$SKILL_DIR|py_compile
ruff check --select F,E9,B "$SKILL_DIR|ruff
pyright -p "$PYRIGHT_CFG"|pyright
TABLE

for pair in 'run-sh-drop-ruff|ruff check --select F,E9,B "$SKILL_DIR|ruff' \
            'run-sh-drop-pycompile|python3 -m py_compile "$SKILL_DIR|py_compile'; do
    MUT_NAME="$(cut -d'|' -f1 <<<"$pair")"
    MARKER="$(cut -d'|' -f2 <<<"$pair")"
    LABEL="$(cut -d'|' -f3 <<<"$pair")"
    COPY="$T/run-$LABEL.sh"
    if python3 "$MUTATE" "$MUT_NAME" "$RUN_SH" "$COPY" 2>"$T/mut.err"; then
        if grep -n -- "$MARKER" "$COPY" | grep -q 'goalforge-admission\.py'; then
            bad "b8 known-bad $MUT_NAME: dropping the filename left the $LABEL grep green"
        else
            ok "b8 known-bad $MUT_NAME: dropping the filename makes the $LABEL grep red"
        fi
    else
        bad "b8 known-bad $MUT_NAME: mutation anchor missing ($(cat "$T/mut.err"))"
    fi
done

# The py_compile gate is UNCONDITIONAL (ruff/pyright WARN-skip when absent), so
# the listing is load-bearing there and a syntax error must redden run.sh
# itself. The nested run is guarded: the copy of this file it executes skips
# this case rather than recursing. The PARENT run that green-lit this file is
# the "still exits 0" half of the known-bads above.
if [[ -n "${GOALFORGE_ADMISSION_NESTED:-}" ]]; then
    echo "  SKIP: b8 py_compile sabotage (nested run)"
else
    cp "$ADM" "$T/admission.orig.py"
    restore() { cp "$T/admission.orig.py" "$ADM"; rm -rf "$PKG/scripts/__pycache__"; }
    trap 'restore; rm -rf "$T"' EXIT INT TERM
    if python3 "$MUTATE" syntax-error "$T/admission.orig.py" "$ADM" 2>"$T/mut.err"; then
        GOALFORGE_ADMISSION_NESTED=1 bash "$RUN_SH" >"$T/nested.out" 2>&1
        NRC=$?
        restore
        if [[ "$NRC" -ne 0 ]] && grep -q 'py_compile' "$T/nested.out"; then
            ok "b8 py_compile sabotage: a syntax error in goalforge-admission.py turns evals/run.sh RED (exit $NRC)"
        else
            bad "b8 py_compile sabotage: run.sh stayed green with a broken goalforge-admission.py (exit $NRC)"
        fi
    else
        bad "b8 py_compile sabotage: mutation anchor missing ($(cat "$T/mut.err"))"
    fi
    trap 'rm -rf "$T"' EXIT
fi

echo
echo "goalforge-admission.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
