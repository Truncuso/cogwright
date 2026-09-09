#!/usr/bin/env bash
# goalforge-pick-agent.test.sh — sabotage pair for the execute/SKILL.md §3
# dispatch invocation (gateB CRITICAL #1/#2, gateC HIGH T17).
#
# Runs the EXACT command string execute/SKILL.md documents:
#   python3 goalforge-pick-agent.py --task <wp>/overview.md --role implement
#
#   known-good: a schema-6 fixture overview.md with NO `complexity:` key
#               (schema 6 never had one — wp-01/T17 removed the input path
#               entirely) -> exit 0, stdout is JSON with `model` + `effort`.
#   known-bad:  a fixture missing the required `register:` C2 field
#               -> exit 2.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$SD/.." && pwd)/goalforge-pick-agent.py"
FIXTURES="$(cd "$SD/../../evals/fixtures/pick-agent" && pwd)"
SKILL_MD="$(cd "$SD/../../execute" && pwd)/SKILL.md"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

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
OUT="$(python3 "$SCRIPT" --task "$FIXTURES/schema6-no-complexity.md" --role implement 2>/tmp/goalforge-pick-agent-test-$$.err)"
RC=$?
if [[ "$RC" -eq 0 ]] \
   && echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "model" in d and "effort" in d' 2>/dev/null; then
    ok "no-complexity-key fixture: exit 0, JSON with model+effort (out=$OUT)"
else
    bad "no-complexity-key fixture: exit 0, JSON with model+effort (rc=$RC, out=$OUT, err=$(cat /tmp/goalforge-pick-agent-test-$$.err))"
fi

# known-bad ---------------------------------------------------------------
OUT2="$(python3 "$SCRIPT" --task "$FIXTURES/no-register.md" --role implement 2>&1)"
RC2=$?
if [[ "$RC2" -eq 2 ]]; then
    ok "missing register: exit 2 (out=$OUT2)"
else
    bad "missing register: exit 2 (rc=$RC2, out=$OUT2)"
fi

rm -f /tmp/goalforge-pick-agent-test-$$.err

echo
echo "goalforge-pick-agent.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
