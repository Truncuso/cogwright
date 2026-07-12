#!/usr/bin/env bash
# evals/run.sh -- sdd-plan-index checks
#   STATIC-CONTRACT: SKILL.md declares the contract
#   BEHAVIORAL:      the generator's exit-code + render contract on fixtures
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
GEN="$HOME/.claude/skills/sdd/scripts/sdd-plan-index.py"
PASS=0; FAIL=0

check() {  # type desc pattern [file]
  local file="${4:-$SKILL_MD}"
  if grep -qF "$3" "$file"; then echo "  PASS [$1]: $2"; PASS=$((PASS+1))
  else echo "  FAIL [$1]: $2"; echo "        expected: $3"; FAIL=$((FAIL+1)); fi
}
ok() { if [ "$1" = "$2" ]; then echo "  PASS [BEHAVIORAL]: $3"; PASS=$((PASS+1));
       else echo "  FAIL [BEHAVIORAL]: $3 (got '$1' want '$2')"; FAIL=$((FAIL+1)); fi; }

echo "=== sdd-plan-index: contract + behavioral checks ==="
check STATIC-CONTRACT "skill name declared" "name: sdd-plan-index"
check STATIC-CONTRACT "version metadata present" "version: 1.0.0"
check STATIC-CONTRACT "derives a DAG / build order" "build-order"
check STATIC-CONTRACT "frontmatter is source of truth" "single source of truth"
check STATIC-CONTRACT "enables normalized to forward edge" "enables"
check STATIC-CONTRACT "exit 4 on cycle" "4"
check STATIC-CONTRACT "trigger: rebuild plans/INDEX.md" "rebuild plans/INDEX.md"

if [ -f "$GEN" ]; then
  # clean DAG: a -> b (b depends_on a) -> exit 0, b after a
  T="$(mktemp -d)"; mkdir -p "$T/plans/a" "$T/plans/b"
  printf -- '---\nfeature: a\nstatus: draft\n---\n' > "$T/plans/a/overview.md"
  printf -- '---\nfeature: b\nstatus: draft\nrelationships:\n  - kind: depends_on\n    feature: a\n---\n' > "$T/plans/b/overview.md"
  rc=0; python3 "$GEN" --plans-root "$T/plans" -o "$T/plans/INDEX.md" >/dev/null 2>&1 || rc=$?
  ok "$rc" 0 "clean DAG exits 0"
  if [ -f "$T/plans/INDEX.md" ]; then
    echo "  PASS [BEHAVIORAL]: INDEX.md written"; PASS=$((PASS+1))
    # b must appear in a later tier than a
    if grep -q 'Tier 0:.*a' "$T/plans/INDEX.md" && grep -q 'Tier 1:.*b' "$T/plans/INDEX.md"; then
      echo "  PASS [BEHAVIORAL]: topological tiers (a before b)"; PASS=$((PASS+1))
    else echo "  FAIL [BEHAVIORAL]: tiers wrong"; FAIL=$((FAIL+1)); fi
  else echo "  FAIL [BEHAVIORAL]: INDEX.md not written"; FAIL=$((FAIL+1)); fi
  rm -rf "$T"

  # cycle: a<->b -> exit 4 + WARNING
  C="$(mktemp -d)"; mkdir -p "$C/plans/a" "$C/plans/b"
  printf -- '---\nfeature: a\nstatus: draft\nrelationships:\n  - kind: depends_on\n    feature: b\n---\n' > "$C/plans/a/overview.md"
  printf -- '---\nfeature: b\nstatus: draft\nrelationships:\n  - kind: depends_on\n    feature: a\n---\n' > "$C/plans/b/overview.md"
  rc=0; out="$(python3 "$GEN" --plans-root "$C/plans" -o - 2>/dev/null)" || rc=$?
  ok "$rc" 4 "cycle exits 4"
  if echo "$out" | grep -q 'dependency cycle'; then echo "  PASS [BEHAVIORAL]: cycle WARNING rendered"; PASS=$((PASS+1))
  else echo "  FAIL [BEHAVIORAL]: no cycle warning"; FAIL=$((FAIL+1)); fi
  rm -rf "$C"

  # empty root -> exit 3
  E="$(mktemp -d)"; mkdir -p "$E/plans"
  rc=0; python3 "$GEN" --plans-root "$E/plans" -o - >/dev/null 2>&1 || rc=$?
  ok "$rc" 3 "no features exits 3"
  rm -rf "$E"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
