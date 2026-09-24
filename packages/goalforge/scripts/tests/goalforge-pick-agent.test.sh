#!/usr/bin/env bash
# goalforge-pick-agent.test.sh — sabotage pairs for the execute/SKILL.md §3
# dispatch invocation and for wp-03/T2's dispatch.yaml resolution (b1, b2).
#
#   known-good: a schema-6 fixture overview.md with NO `complexity:` key
#               -> exit 0, stdout is JSON with `model` + `effort`.
#   known-bad:  a fixture missing the required `register:` C2 field on a
#               `by_register` stage row -> exit 2.
#
# Provider fall-through is driven by `--simulate-leaf "<exit>[:<reason>]"`
# (repeatable, one per provider attempt) against
# scripts/tests/fixtures/dispatch/dispatch-default.yaml, whose preference
# order is anthropic (native) -> stub-a (local) -> stub-b (foreign). No leaf
# is ever executed here, and GOALFORGE_DISPATCH_LEDGER is pinned to a
# mktemp -d root so no run touches the live propose-only ledger.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$SD/../.." && pwd)"
SCRIPT="$PKG/scripts/goalforge-pick-agent.py"
FIXTURES="$PKG/evals/fixtures/pick-agent"
DISPATCH_FIXTURES="$SD/fixtures/dispatch"
DISPATCH="$DISPATCH_FIXTURES/dispatch-default.yaml"
SKILL_MD="$PKG/execute/SKILL.md"
WP="$FIXTURES/schema6-no-complexity.md"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export GOALFORGE_DISPATCH_LEDGER="$T/ledger/dispatch-decisions.jsonl"

# jq-free JSON field read: prints .<key> of one JSON object on stdin.
jget() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1],""))' "$1"; }

# derive the flag set from execute/SKILL.md's fenced invocation line itself,
# instead of hardcoding it, so drift between the doc and this test cannot go
# unnoticed (wp-01 round 2, gate B LOW finding).
DOC_LINE="$(grep -m1 'goalforge-pick-agent.py' "$SKILL_MD")"
if [[ -z "$DOC_LINE" ]]; then
    bad "execute/SKILL.md names goalforge-pick-agent.py (no fenced invocation found)"
else
    ok "execute/SKILL.md names goalforge-pick-agent.py"
fi
DOC_FLAGS="$(printf '%s\n' "$DOC_LINE" | grep -oE -- '--[a-zA-Z-]+' | sort -u)"
if printf '%s\n' "$DOC_FLAGS" | grep -qx -- '--task' \
   && printf '%s\n' "$DOC_FLAGS" | grep -qx -- '--role'; then
    ok "execute/SKILL.md's invocation carries --task and --role (flags: $(printf '%s' "$DOC_FLAGS" | tr '\n' ' '))"
else
    bad "execute/SKILL.md's invocation missing --task/--role (flags: $(printf '%s' "$DOC_FLAGS" | tr '\n' ' '))"
fi
if printf '%s\n' "$DOC_LINE" | grep -qE -- '--role[[:space:]]+implement\b'; then
    ok "execute/SKILL.md's invocation pins --role implement"
else
    bad "execute/SKILL.md's invocation does not pin --role implement (line: $DOC_LINE)"
fi

# known-good — run with the flags DOC_LINE just proved (not a hardcoded
# duplicate): --task <fixture> --role implement.
OUT="$(python3 "$SCRIPT" --task "$WP" --role implement 2>"$T/err")"
RC=$?
if [[ "$RC" -eq 0 ]] \
   && echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "model" in d and "effort" in d' 2>/dev/null; then
    ok "no-complexity-key fixture: exit 0, JSON with model+effort (out=$OUT)"
else
    bad "no-complexity-key fixture: exit 0, JSON with model+effort (rc=$RC, out=$OUT, err=$(cat "$T/err"))"
fi

# the resolution names ONE roster agent and carries the dispatch.yaml keys.
OUT="$(python3 "$SCRIPT" --task "$WP" --role implement --dispatch "$DISPATCH" 2>"$T/err")"
RC=$?
AGENT="$(printf '%s' "$OUT" | jget agent 2>/dev/null)"
if [[ "$RC" -eq 0 ]] && [[ -f "$PKG/agents/implementer.md" ]] \
   && grep -qx "name: $AGENT" "$PKG/agents/implementer.md"; then
    ok "resolution names a roster agent from agents/ (agent=$AGENT)"
else
    bad "resolution names a roster agent from agents/ (rc=$RC, agent=$AGENT, out=$OUT)"
fi
MISSING=""
for k in agent expertise provider endpoint egress propose_only model effort role; do
    printf '%s' "$OUT" | python3 -c 'import json,sys; sys.exit(0 if sys.argv[1] in json.load(sys.stdin) else 1)' "$k" \
        || MISSING="$MISSING $k"
done
if [[ -z "$MISSING" ]]; then
    ok "resolution carries every contracted key (agent/expertise/provider/endpoint/egress/propose_only/model/effort/role)"
else
    bad "resolution missing key(s):$MISSING (out=$OUT)"
fi

# known-bad ---------------------------------------------------------------
OUT2="$(python3 "$SCRIPT" --task "$FIXTURES/no-register.md" --role implement 2>&1)"
RC2=$?
if [[ "$RC2" -eq 2 ]]; then
    ok "missing register: exit 2 (out=$OUT2)"
else
    bad "missing register: exit 2 (rc=$RC2, out=$OUT2)"
fi

# ── row-equality (b1) ────────────────────────────────────────────────────
# The resolution's model/effort/endpoint equal the fixture's stage row.
WANT="$(python3 -c '
import sys, yaml
row = yaml.safe_load(open(sys.argv[1]))["stages"][sys.argv[2]]
print(row["model"], row["effort"], row["endpoint"])' "$DISPATCH" judge)"
GOT="$(python3 "$SCRIPT" --task "$WP" --role judge --dispatch "$DISPATCH" 2>"$T/err" \
       | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["model"], d["effort"], d["endpoint"])')"
if [[ "$GOT" == "$WANT" ]]; then
    ok "row-equality: --role judge resolves to the fixture stage row ($GOT)"
else
    bad "row-equality: --role judge got '$GOT', want '$WANT'"
fi

# ── provider fall-through (b1) ───────────────────────────────────────────
PROV="$(python3 "$SCRIPT" --task "$WP" --role judge --dispatch "$DISPATCH" \
        --simulate-leaf 1 --simulate-leaf 0 2>"$T/err" | jget provider)"
if [[ "$PROV" == "stub-a" ]]; then
    ok "leaf exit 1 falls through to the next configured provider (provider=$PROV)"
else
    bad "leaf exit 1 falls through to the next configured provider (got '$PROV', want stub-a)"
fi

PROV="$(python3 "$SCRIPT" --task "$WP" --role judge --dispatch "$DISPATCH" \
        --simulate-leaf 4:plan_quota_exhausted --simulate-leaf 0 2>"$T/err" | jget provider)"
if [[ "$PROV" == "stub-a" ]]; then
    ok "exit 4 plan_quota_exhausted falls through (no inner envelope) (provider=$PROV)"
else
    bad "exit 4 plan_quota_exhausted falls through (got '$PROV', want stub-a)"
fi

# ── keep-on-overspend (b1) ───────────────────────────────────────────────
OUT="$(python3 "$SCRIPT" --task "$WP" --role judge --dispatch "$DISPATCH" \
       --simulate-leaf 4:budget_exceeded 2>"$T/err")"
PROV="$(printf '%s' "$OUT" | jget provider)"
if [[ "$PROV" == "anthropic" ]] && grep -q '"type": *"dispatch.warn"' "$T/err"; then
    ok "exit 4 budget_exceeded keeps the provider and prints a dispatch.warn row"
else
    bad "exit 4 budget_exceeded keeps the provider + WARN (provider='$PROV', err=$(cat "$T/err"))"
fi

# ── escalation when the preference order is exhausted (b1) ───────────────
OUT="$(python3 "$SCRIPT" --task "$WP" --role judge --dispatch "$DISPATCH" \
       --simulate-leaf 1 --simulate-leaf 1 --simulate-leaf 1 2>&1)"
RC=$?
if [[ "$RC" -eq 1 ]] && grep -q 'ESCALATION REQUIRED' <<<"$OUT"; then
    ok "every provider exhausted: exit 1 + ESCALATION REQUIRED"
else
    bad "every provider exhausted: exit 1 + ESCALATION REQUIRED (rc=$RC, out=$OUT)"
fi

# ── propose-only ledger row (b1) ─────────────────────────────────────────
rm -rf "$T/ledger"
OUT="$(python3 "$SCRIPT" --task "$WP" --role second_opinion --wp wp-99-fixture \
       --dispatch "$DISPATCH" 2>"$T/err")"
RC=$?
PO="$(printf '%s' "$OUT" | jget propose_only)"
if [[ "$RC" -eq 0 ]] && [[ "$PO" == "True" ]] \
   && [[ -f "$GOALFORGE_DISPATCH_LEDGER" ]] \
   && grep -q '"decision": *"propose-only"' "$GOALFORGE_DISPATCH_LEDGER" \
   && grep -q '"provider": *"stub-a"' "$GOALFORGE_DISPATCH_LEDGER"; then
    ok "non-native provider resolves propose-only and appends one ledger row"
else
    bad "non-native provider propose-only + ledger row (rc=$RC, propose_only='$PO', ledger=$(cat "$GOALFORGE_DISPATCH_LEDGER" 2>&1))"
fi
# the live ledger default must never be the path a test wrote to.
if [[ "$GOALFORGE_DISPATCH_LEDGER" == "$T"/* ]]; then
    ok "ledger pinned under the test's mktemp root (live ledger untouched)"
else
    bad "ledger pinned under the test's mktemp root (got $GOALFORGE_DISPATCH_LEDGER)"
fi

# ── b2: no provider is named in any SKILL.md or roster agent ─────────────
# Exactly that file set — references/dispatch.yaml is DATA and is not in it.
PROVIDER_HITS="$(find "$PKG" -name SKILL.md -print0 2>/dev/null \
                 | xargs -0 grep -rlE 'ollama|deepseek|codex|zai|openrouter|moonshot|nvidia' 2>/dev/null || true)"
AGENT_HITS="$(grep -rlE 'ollama|deepseek|codex|zai|openrouter|moonshot|nvidia' "$PKG"/agents/*.md 2>/dev/null || true)"
HITS="$(printf '%s\n%s' "$PROVIDER_HITS" "$AGENT_HITS" | grep -v '^$' || true)"
if [[ -z "$HITS" ]]; then
    ok "no provider name in any SKILL.md or agents/*.md (b2)"
else
    bad "provider name leaked into: $(printf '%s' "$HITS" | tr '\n' ' ')"
fi

# retired input: specialist-map.yaml must be gone (wp-03/T2).
if [[ ! -f "$PKG/references/specialist-map.yaml" ]]; then
    ok "references/specialist-map.yaml retired by wp-03"
else
    bad "references/specialist-map.yaml retired by wp-03 (still present)"
fi

# ── wp-08 b4: --test-tiers applies the EXISTENTIAL admission rule ────────
# --test-tiers has no WP and so no task class: a non-native implement row
# passes iff SOME admission row, for ANY task class, binds its (provider,
# model, leaf, current leaf_sha256, max_egress >= egress). Run in process
# through fixtures/admission/tiers_seam.py, which patches the dispatch
# loader's path and goalforge_admission.ADMITTED_PATH — no CLI flag.
TIERS="$SD/fixtures/admission/tiers_seam.py"
ADM_FX="$SD/fixtures/admission"
D_ADM="$DISPATCH_FIXTURES/dispatch-admitted.yaml"
export CLAUDE_CONFIG_DIR="$T/cfg"
LEAF_REL="skills/agent-dispatch/ollama/scripts/headless_dispatch"
mkdir -p "$CLAUDE_CONFIG_DIR/$(dirname "$LEAF_REL")"
cp "$ADM_FX/leaf/headless_dispatch" "$CLAUDE_CONFIG_DIR/$LEAF_REL"

tiers() { # <name> <dispatch|-> <table|-> -> RC; $T/<name>.out (stdout+stderr)
    python3 "$TIERS" "$SCRIPT" "$2" "$3" >"$T/$1.out" 2>&1
    RC=$?
}
impl_fails() { grep "FAIL: .*stage 'implement'" "$T/$1.out" || true; }

tiers b4-i - -
if [[ "$RC" -eq 0 ]] && grep -q "all role→tier invariants pass" "$T/b4-i.out"; then
    ok "b4(i) shipped dispatch.yaml + shipped (empty) table: --test-tiers passes (native implement row)"
else
    bad "b4(i) shipped config (rc=$RC): $(cat "$T/b4-i.out")"
fi
tiers b4-ii "$D_ADM" "$ADM_FX/admitted-ok.yaml"
if [[ "$RC" -eq 0 && -z "$(impl_fails b4-ii)" ]]; then
    ok "b4(ii) a foreign implement row + an admitting table: no implement failure"
else
    bad "b4(ii) admitted row flagged: $(impl_fails b4-ii)"
fi
tiers b4-iii "$D_ADM" "$ADM_FX/admitted-leaf-stale-hash.yaml"
if [[ "$RC" -ne 0 ]] && impl_fails b4-iii | grep -q "hashes to"; then
    ok "b4(iii) a stale leaf_sha256 FLAGS the implement row naming the leaf hash mismatch"
else
    bad "b4(iii) stale hash (rc=$RC): $(impl_fails b4-iii)"
fi
tiers b4-iv "$D_ADM" "$ADM_FX/admitted-empty.yaml"
if [[ "$RC" -ne 0 ]] && impl_fails b4-iv | grep -qF "(*, ollama, glm-5.3:cloud)" \
   && ! grep -q "not 'native'" "$T/b4-iv.out"; then
    ok "b4(iv) an empty table FLAGS the row naming the missing (*, provider, model) — not the pre-wp-08 \"not 'native'\" text"
else
    bad "b4(iv) empty table (rc=$RC): $(cat "$T/b4-iv.out")"
fi
tiers b4-v "$D_ADM" "$ADM_FX/admitted-other-model.yaml"
if [[ "$RC" -ne 0 ]] && impl_fails b4-v | grep -qF "(*, ollama, glm-5.3:cloud)"; then
    ok "b4(v) the same provider admitted for another model only FLAGS the row"
else
    bad "b4(v) other model (rc=$RC): $(impl_fails b4-v)"
fi
tiers b4-vi "$D_ADM" "$ADM_FX/admitted-code-sh.yaml"
if [[ "$RC" -eq 0 && -z "$(impl_fails b4-vi)" ]]; then
    ok "b4(vi) an admission for another task class only (code/sh) suffices — existential rule"
else
    bad "b4(vi) other task class flagged: $(impl_fails b4-vi)"
fi
tiers b4-vii "$D_ADM" "$ADM_FX/admitted-egress-diff-only.yaml"
if [[ "$RC" -ne 0 ]] && impl_fails b4-vii | grep -q "egress incoherent"; then
    ok "b4(vii) max_egress below the row's egress FLAGS the row naming the egress incoherence"
else
    bad "b4(vii) egress (rc=$RC): $(impl_fails b4-vii)"
fi

echo
echo "goalforge-pick-agent.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
