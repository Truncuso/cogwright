#!/usr/bin/env bash
# goalforge-admission.test.sh — wp-06 provider admission (b1-b8).
#
# The admission table decides the resolver verdict for role `implement`:
# a foreign or local provider executes only when a row names its task class,
# its provider AND its model, with closed-kind evidence and a permission set —
# and binds the leaf executable that row's evidence was gathered against.
#
#   b1 refused        b2 admitted       b3 sabotage rows
#   b4 shipped-empty + no-flag + no-native-fallback (3 known-bads)
#   b5 model binding  b6 task class     b7 invariant text  b8 lint lists
#   fix lap: S-1 derived kind (loader / resolution / fallback), S-2 leaf
#   binding (repoint, stale hash, unreadable, missing key), S-3 duplicate
#   provider names, S-13 --admitted containment + S-9 relative source
#
# Every known-bad is an ANCHORED mutation (fixtures/admission/mutate.py) of a
# COPY of the package under a mktemp root — the shipped tree is never written
# to, b8's py_compile sabotage included (it runs the COPY's evals/run.sh).
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
# S-13's symlink-escape case needs a link INSIDE the package root; it is named
# here so the trap removes it even on an interrupted run (the tracked tree is
# otherwise never written to).
LINK="$F/admitted-symlink-escape.yaml"
trap 'rm -rf "$T"; rm -f "$LINK"' EXIT
LEDGER="$T/ledger/dispatch-decisions.jsonl"
export GOALFORGE_DISPATCH_LEDGER="$LEDGER"

# An admission row BINDS the leaf executable (S-2): the verdict hashes the file
# at `$CLAUDE_CONFIG_DIR/<providers[].leaf>`. Point that root at a temp corpus
# carrying the fixture leaf, so no case depends on the host's own corpus.
export CLAUDE_CONFIG_DIR="$T/cfg"
LEAF_REL="skills/agent-dispatch/ollama/scripts/headless_dispatch"
mkdir -p "$CLAUDE_CONFIG_DIR/$(dirname "$LEAF_REL")"
cp "$F/leaf/headless_dispatch" "$CLAUDE_CONFIG_DIR/$LEAF_REL"

# `admitted_source` is package-relative, never the absolute host path (S-9).
FIXTURE_SRC="scripts/tests/fixtures/admission/admitted-ok.yaml"
SHIPPED_SRC="references/admitted-providers.yaml"

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
EP="$(printf '%s' "$OUT" | jget endpoint)"
EG="$(printf '%s' "$OUT" | jget egress)"
if [[ "$RC" -eq 0 && "$PROV" == "anthropic" && "$PO" == "False" ]] \
   && [[ "$REASON" == *"code/sh"* ]]; then
    ok "b1 refused: the native provider resolves, propose_only false, reason names code/sh"
else
    bad "b1 refused (rc=$RC, provider=$PROV, propose_only=$PO, reason=$REASON)"
fi
# V-2: the refused row's leaf endpoint / egress class must not survive the
# fallback — the resolution would otherwise declare an in-session native
# dispatch as an egressing leaf one.
if [[ "$EP" == "session" && "$EG" == "none" ]]; then
    ok "b1 refused: the fallback resolution declares endpoint session / egress none"
else
    bad "b1 refused: fallback endpoint/egress (endpoint=$EP, egress=$EG, want session/none)"
fi
if [[ "$(rows)" == "1" ]]; then
    ok "b1 refused: exactly one ledger row"
else
    bad "b1 refused: exactly one ledger row (got $(rows))"
fi
WANT_SRC="$FIXTURE_SRC"
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
# V-2: an admitted leaf dispatch declares what it is — endpoint leaf, and an
# egress class other than `none`.
EP="$(printf '%s' "$OUT" | jget endpoint)"
EG="$(printf '%s' "$OUT" | jget egress)"
if [[ "$EP" == "leaf" && "$EG" != "none" ]]; then
    ok "b2 admitted: the resolution declares endpoint leaf and a non-none egress class ($EG)"
else
    bad "b2 admitted endpoint/egress (endpoint=$EP, egress=$EG, want leaf/non-none)"
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
    "bad-self-report.yaml|evidence.kind" \
    "bad-permission-set-string.yaml|permission_set" \
    "bad-missing-leaf.yaml|leaf"; do
    FILE="${pair%%|*}"; KEY="${pair##*|}"
    ERR="$(python3 "$ADM" --table "$F/$FILE" 2>&1)"
    RC=$?
    if [[ "$RC" -eq 2 && "$ERR" == *"row 0"* && "$ERR" == *"'$KEY'"* ]]; then
        ok "b3 $FILE: exit 2 naming row 0 and key '$KEY'"
    else
        bad "b3 $FILE: exit 2 naming row 0 and key '$KEY' (rc=$RC, err=$ERR)"
    fi
done

# A table the CALLER named must EXIST (V-5): a typo'd override silently
# becoming an empty table would refuse everything at exit 0 and stamp a
# nonexistent admitted_source on the ledger row.
ERR="$(python3 "$ADM" --table "$F/no-such-table.yaml" 2>&1)"
RC=$?
if [[ "$RC" -eq 2 && "$ERR" == *"not found"* ]]; then
    ok "b3 explicit table: a named table that does not exist is exit 2, not an empty table"
else
    bad "b3 explicit table: want exit 2 naming 'not found' (rc=$RC, err=$ERR)"
fi
ERR="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-ollama.yaml" --admitted "$F/no-such-table.yaml" 2>&1)"
RC=$?
if [[ "$RC" -eq 2 && "$ERR" == *"not found"* ]]; then
    ok "b3 explicit table: --admitted on a missing path is exit 2 from pick-agent too"
else
    bad "b3 explicit table: --admitted missing path (rc=$RC, err=$ERR)"
fi

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
# V-6: "no foreign provider survives in the result" asserted on the PARSED
# object — every value except the two keys whose job is to name the refused
# row must be free of the foreign provider's name.
LEAK="$(printf '%s' "$OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
named = ("admission_reason", "refused_provider")
print(",".join(k for k, v in d.items()
               if k not in named and "stub-b" in json.dumps(v)))' 2>/dev/null)"
NOFLAG_OK=0
if [[ "$RC" -eq 0 ]] \
   && [[ "$(printf '%s' "$OUT" | jget provider)" == "anthropic" ]] \
   && [[ "$(printf '%s' "$OUT" | jget propose_only)" == "False" ]] \
   && [[ "$GOT_ME" == "$BASE_ME" ]] \
   && [[ -z "$LEAK" ]]; then
    NOFLAG_OK=1
fi
if [[ "$NOFLAG_OK" -eq 1 ]]; then
    ok "b4 no-flag: the foreign provider is refused and the native one resolves at the stage row's native band ($GOT_ME), propose_only false, no key but the refusal record names stub-b"
else
    bad "b4 no-flag (rc=$RC, got='$GOT_ME', want='$BASE_ME', leak='$LEAK', out=$OUT)"
fi
EP="$(printf '%s' "$OUT" | jget endpoint)"
EG="$(printf '%s' "$OUT" | jget egress)"
if [[ "$EP" == "session" && "$EG" == "none" ]]; then
    ok "b4 no-flag: the fallback resolution declares endpoint session / egress none"
else
    bad "b4 no-flag fallback endpoint/egress (endpoint=$EP, egress=$EG, want session/none)"
fi
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
# $1 = mutation name. Sets the GLOBAL $MUT to the mutated pick-agent and
# returns 0, or clears it, reports on stderr and returns 1. Never called in a
# command substitution: a drifted anchor must reach the PARENT shell's counters
# (V-3 — the FAIL of a dead known-bad used to die in the subshell and the
# suite still exited 0).
kb_pick() {
    local dest="$KB/scripts/goalforge-pick-agent.py"
    MUT=""
    if ! python3 "$MUTATE" "$1" "$PICK" "$dest" 2>"$T/mut.err"; then
        echo "  mutation $1 failed: $(cat "$T/mut.err")" >&2
        return 1
    fi
    MUT="$dest"
}

# Oracle integrity: the harness's own failure path is exercised before the
# known-bads rest on it. Under the old command-substitution shape $MUT held the
# swallowed diagnostic instead of being empty.
if kb_pick __no_such_anchor__ 2>/dev/null; then
    bad "harness: a nonexistent mutation anchor must not report success"
elif [[ -n "$MUT" ]]; then
    bad "harness: a failed mutation left MUT set to '$MUT' (the diagnostic was swallowed)"
else
    ok "harness: a drifted known-bad anchor fails in the PARENT shell and yields no mutant"
fi

reset
if kb_pick skip-admission-no-flag; then
    OUT="$(python3 "$MUT" --task "$F/wp-code-py.md" --role implement \
           --dispatch "$F/dispatch-foreign-native-fallback.yaml" 2>/dev/null)"
    if [[ "$(printf '%s' "$OUT" | jget provider)" != "anthropic" ]] \
       || [[ "$(printf '%s' "$OUT" | jget propose_only)" != "False" ]]; then
        ok "b4 known-bad 1: a no-flag path that skips admission makes the no-flag case red"
    else
        bad "b4 known-bad 1: a no-flag path that skips admission still passes (out=$OUT)"
    fi
else
    bad "b4 known-bad 1: mutation anchor missing ($(cat "$T/mut.err"))"
fi

reset
if kb_pick keep-refused-provider; then
    OUT="$(python3 "$MUT" --task "$F/wp-code-py.md" --role implement \
           --dispatch "$F/dispatch-foreign-native-fallback.yaml" 2>/dev/null)"
    if [[ "$(printf '%s' "$OUT" | jget provider)" != "anthropic" ]]; then
        ok "b4 known-bad 2: a refused branch that keeps the foreign provider makes the no-flag case red"
    else
        bad "b4 known-bad 2: a refused branch that keeps the foreign provider still passes (out=$OUT)"
    fi
else
    bad "b4 known-bad 2: mutation anchor missing ($(cat "$T/mut.err"))"
fi

reset
if kb_pick no-native-keeps-foreign; then
    ERR="$(python3 "$MUT" --task "$F/wp-code-py.md" --role implement \
           --dispatch "$F/dispatch-no-native.yaml" 2>&1)"
    RC=$?
    if [[ "$RC" -ne 2 || "$ERR" != *"no native provider for fallback"* ]]; then
        ok "b4 known-bad 3: resolving the refused row when no native row exists makes the no-native case red"
    else
        bad "b4 known-bad 3: resolving the refused row still exits 2 with the message (rc=$RC)"
    fi
else
    bad "b4 known-bad 3: mutation anchor missing ($(cat "$T/mut.err"))"
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

# ── b5 (V-1/V-2): a stage row that cannot describe a real leaf dispatch ──
# The model handed to the admission check is the admission KEY, and the row's
# endpoint/egress are copied into the resolution. A Claude tier, an in-session
# endpoint or `egress: none` on a leaf provider is refused BEFORE the table is
# consulted — even when a table row would otherwise match exactly.
reset
OUT="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-ollama-tier.yaml" \
       --admitted "$F/admitted-claude-tier.yaml" --wp wp-fx 2>/dev/null)"
RC=$?
REASON="$(printf '%s' "$OUT" | jget admission_reason)"
if [[ "$RC" -eq 0 ]] \
   && [[ "$(printf '%s' "$OUT" | jget provider)" == "anthropic" ]] \
   && [[ "$(printf '%s' "$OUT" | jget admission_decision)" == "refused" ]] \
   && [[ "$REASON" == *"Claude tier"* && "$REASON" == *"sonnet"* ]]; then
    ok "b5 model key: a Claude tier as the provider's model is refused even when a table row names that tier"
else
    bad "b5 model key (rc=$RC, provider=$(printf '%s' "$OUT" | jget provider), reason=$REASON)"
fi

reset
OUT="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-ollama-egress-none.yaml" \
       --admitted "$F/admitted-ok.yaml" --wp wp-fx 2>/dev/null)"
RC=$?
REASON="$(printf '%s' "$OUT" | jget admission_reason)"
if [[ "$RC" -eq 0 ]] \
   && [[ "$(printf '%s' "$OUT" | jget provider)" == "anthropic" ]] \
   && [[ "$(printf '%s' "$OUT" | jget admission_decision)" == "refused" ]] \
   && [[ "$REASON" == *"egress"* ]]; then
    ok "b5 egress coherence: an otherwise-matching row declaring egress none is refused, never admitted as a non-egressing leaf dispatch"
else
    bad "b5 egress coherence (rc=$RC, provider=$(printf '%s' "$OUT" | jget provider), reason=$REASON)"
fi

# ── fix lap: the admission TRUST boundary (S-1, S-2, S-3, S-13) ──────────
# Three holes an admitted verdict used to rest on: a provider row that DECLARES
# `kind: native` (skipping the table outright), an admitted triple whose leaf
# executable was swapped underneath it, and an `--admitted` table read from an
# arbitrary path. Every case below resolves at exit 0 on the pre-fix code.

# S-1, loader leg: a native row carrying a leaf poisons the whole dispatch file.
ERR="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-native-with-leaf.yaml" 2>&1)"
RC=$?
if [[ "$RC" -eq 2 && "$ERR" == *"kind 'native' but carries leaf"* ]]; then
    ok "S-1 loader: a providers row declaring kind native while carrying a leaf is refused at load"
else
    bad "S-1 loader: want exit 2 naming the row (rc=$RC, err=$ERR)"
fi

# S-1, resolution leg: every row is coherent on its own; the STAGE row sends
# the native provider through a leaf. Admission never sees it.
ERR="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-native-endpoint-leaf.yaml" 2>&1)"
RC=$?
if [[ "$RC" -eq 2 && "$ERR" == *"endpoint 'leaf'"* && "$ERR" == *"anthropic"* ]]; then
    ok "S-1 resolution: a native provider on an endpoint: leaf stage row is refused, never admitted unchecked"
else
    bad "S-1 resolution: want exit 2 naming the row (rc=$RC, err=$ERR)"
fi

# S-1, fallback leg: the refusal's fallback target is chosen BY `kind`, so it
# is derived the same way. Reachable through the library entry point only —
# `load_dispatch` refuses such a file before `resolve_stage` ever sees it.
OUT="$(python3 "$F/fallback_target.py" "$PICK" 2>&1)"
if [[ "$OUT" == "REFUSED no coherent native provider for fallback:"* ]]; then
    ok "S-1 fallback: an incoherent native fallback target fails closed instead of resolving"
else
    bad "S-1 fallback: want REFUSED naming the incoherent target (got: $OUT)"
fi

# S-3: two rows, one name — `provider_row` would resolve the first and the
# second would be live configuration nothing reads.
ERR="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-dup-names.yaml" 2>&1)"
RC=$?
if [[ "$RC" -eq 2 && "$ERR" == *"duplicate provider name 'ollama'"* ]]; then
    ok "S-3 duplicate provider names are refused at load, not silently first-match resolved"
else
    bad "S-3 duplicate provider names (rc=$RC, err=$ERR)"
fi

# S-2a: the admitted TRIPLE is untouched; the row's leaf names another binary.
reset
OUT="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-ollama.yaml" \
       --admitted "$F/admitted-leaf-repoint.yaml" --wp wp-fx 2>/dev/null)"
REASON="$(printf '%s' "$OUT" | jget admission_reason)"
if [[ "$(printf '%s' "$OUT" | jget provider)" == "anthropic" ]] \
   && [[ "$(printf '%s' "$OUT" | jget admission_decision)" == "refused" ]] \
   && [[ "$REASON" == *"repointed leaf"* ]]; then
    ok "S-2 leaf repoint: an admitted (task_class, provider, model) triple does not carry over to another executable"
else
    bad "S-2 leaf repoint (provider=$(printf '%s' "$OUT" | jget provider), reason=$REASON)"
fi

# S-2b: same leaf path, different content than the evidence was gathered on.
reset
OUT="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-ollama.yaml" \
       --admitted "$F/admitted-leaf-stale-hash.yaml" --wp wp-fx 2>/dev/null)"
REASON="$(printf '%s' "$OUT" | jget admission_reason)"
if [[ "$(printf '%s' "$OUT" | jget provider)" == "anthropic" ]] \
   && [[ "$(printf '%s' "$OUT" | jget admission_decision)" == "refused" ]] \
   && [[ "$REASON" == *"hashes to"* ]]; then
    ok "S-2 stale hash: a leaf whose content no longer matches leaf_sha256 is refused"
else
    bad "S-2 stale hash (provider=$(printf '%s' "$OUT" | jget provider), reason=$REASON)"
fi

# S-2c: the leaf must be READABLE where the provider row says it runs.
reset
mv "$CLAUDE_CONFIG_DIR/$LEAF_REL" "$CLAUDE_CONFIG_DIR/$LEAF_REL.away"
OUT="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-ollama.yaml" --admitted "$F/admitted-ok.yaml" 2>/dev/null)"
mv "$CLAUDE_CONFIG_DIR/$LEAF_REL.away" "$CLAUDE_CONFIG_DIR/$LEAF_REL"
if [[ "$(printf '%s' "$OUT" | jget provider)" == "anthropic" ]] \
   && [[ "$(printf '%s' "$OUT" | jget admission_reason)" == *"cannot be read"* ]]; then
    ok "S-2 missing leaf: an admitted row whose executable is absent is refused, not admitted unhashed"
else
    bad "S-2 missing leaf (provider=$(printf '%s' "$OUT" | jget provider), out=$OUT)"
fi

# S-13: `--admitted` is a test seam, not an arbitrary-file read. A table
# outside the package root (or the plans root) decides nothing.
cp "$F/admitted-ok.yaml" "$T/outside-table.yaml"
ERR="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-ollama.yaml" --admitted "$T/outside-table.yaml" 2>&1)"
RC=$?
if [[ "$RC" -eq 2 && "$ERR" == *"outside the package root"* ]]; then
    ok "S-13 override containment: an --admitted table outside the package root is refused"
else
    bad "S-13 override containment (rc=$RC, err=$ERR)"
fi

# Same containment, through a symlink INSIDE the package pointing out of it:
# the path is resolved before it is tested, so the link is not an escape.
ln -sfn "$T/outside-table.yaml" "$LINK"
ERR="$(python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
       --dispatch "$F/dispatch-ollama.yaml" --admitted "$LINK" 2>&1)"
RC=$?
rm -f "$LINK"
if [[ "$RC" -eq 2 && "$ERR" == *"outside the package root"* ]]; then
    ok "S-13 override containment: a symlink inside the package pointing out of it is refused too"
else
    bad "S-13 symlink escape (rc=$RC, err=$ERR)"
fi

# S-13: an active override is announced, and recorded package-relative (S-9).
reset
python3 "$PICK" --task "$F/wp-code-py.md" --role implement \
    --dispatch "$F/dispatch-ollama.yaml" --admitted "$F/admitted-ok.yaml" \
    --wp wp-fx >/dev/null 2>"$T/err"
if [[ "$(grep -c -- '--admitted override active' "$T/err")" == "1" ]] \
   && [[ "$(lget admitted_source <"$LEDGER")" == "$FIXTURE_SRC" ]]; then
    ok "S-13/S-9: the override WARNs once on stderr and the ledger records a package-relative source"
else
    bad "S-13/S-9 override WARN + source (err=$(cat "$T/err"), source=$(lget admitted_source <"$LEDGER"))"
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
# itself. The sabotage runs against a COPY of the whole package under $T and
# invokes that copy's evals/run.sh (run.sh derives SKILL_DIR from its own
# location): the tracked tree is never written to, so an interrupted or
# concurrent run can no longer leave a syntax-error source file behind (V-4).
# The nested run is guarded: the copy of this file it executes skips this case
# rather than recursing.
if [[ -n "${GOALFORGE_ADMISSION_NESTED:-}" ]]; then
    echo "  SKIP: b8 py_compile sabotage (nested run)"
else
    SBX="$T/pkg"
    rm -rf "$SBX"
    cp -r "$PKG" "$SBX"
    rm -rf "$SBX/scripts/__pycache__"
    if python3 "$MUTATE" syntax-error "$PKG/scripts/goalforge-admission.py" \
               "$SBX/scripts/goalforge-admission.py" 2>"$T/mut.err"; then
        GOALFORGE_ADMISSION_NESTED=1 bash "$SBX/evals/run.sh" >"$T/nested.out" 2>&1
        NRC=$?
        # V-7: the oracle is the FAILING py_compile check line, not the mere
        # mention of py_compile (which run.sh prints either way).
        if [[ "$NRC" -ne 0 ]] && grep -q '^  FAIL: python3 -m py_compile' "$T/nested.out"; then
            ok "b8 py_compile sabotage: a syntax error in goalforge-admission.py fails run.sh's py_compile gate (exit $NRC)"
        else
            bad "b8 py_compile sabotage: run.sh's py_compile gate stayed green with a broken goalforge-admission.py (exit $NRC)"
        fi
    else
        bad "b8 py_compile sabotage: mutation anchor missing ($(cat "$T/mut.err"))"
    fi
fi

echo
echo "goalforge-admission.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
