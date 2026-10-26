#!/usr/bin/env bash
# goalforge-frontmatter-touch.test.sh — sabotage pair for
# goalforge-frontmatter-touch.sh. Fixtures live under
# packages/goalforge/evals/fixtures/hooks/goalforge-frontmatter-touch/ — never
# inline here. Hermetic: everything happens in a mktemp dir; nothing is ever
# written into a real plans/ tree.
#
# DEVIATION FROM THE LITERAL ticket-74 exit-2/exit-0 PAIR SHAPE: this hook is
# a PostToolUse cosmetic bump, not a gate — its own header states "Never
# breaks the session: every failure path exits 0" (zero-breakage by design; it
# never blocks a tool call, so it never has an exit-2 path to sabotage-test).
# Changing that contract is out of this task's scope. The pair here instead
# tests the hook's ONE observable effect — did `stage_updated:` get bumped —
# against a fixture that SHOULD be bumped (stale) and one that SHOULD NOT
# (already current, idempotence). Both invocations still assert exit 0, since
# that is the hook's only correct exit code in either case.
set -uo pipefail

HD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HD/goalforge-frontmatter-touch.sh"
FIX="$HD/../evals/fixtures/hooks/goalforge-frontmatter-touch"
TODAY="$(date +%F)"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

setup_case() { # <label> <fixture-file> -> echoes the overview.md path it created
    local label="$1" fixture="$2" root dst
    root="$WORK/$label"
    mkdir -p "$root/plans/feat"
    dst="$root/plans/feat/overview.md"
    sed "s/__TODAY__/$TODAY/" "$fixture" > "$dst"
    printf '%s' "$dst"
}

payload() { # <file path>
    command jq -n --arg fp "$1" '{tool_name:"Edit", tool_input:{file_path:$fp}}'
}

# ── "known-bad" (stale): stage_updated: is stale -> must be bumped, exit 0 ──
stale="$(setup_case stale "$FIX/stale-overview.md")"
OUT="$(payload "$stale" | SDD_PLANS_DIR="$WORK/stale/plans" bash "$HOOK" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$OUT" ] && grep -q "stage_updated: $TODAY" "$stale"; then
    ok "stale fixture -> exit 0, stage_updated: bumped to $TODAY"
else
    bad "stale fixture -> exit $rc, bump check failed ($(cat "$stale"))"
fi

# ── "known-good" (current): stage_updated: already today -> no write, exit 0 ─
current="$(setup_case current "$FIX/current-overview.md")"
before="$(cat "$current")"
OUT="$(payload "$current" | SDD_PLANS_DIR="$WORK/current/plans" bash "$HOOK" 2>&1)"; rc=$?
after="$(cat "$current")"
if [ "$rc" -eq 0 ] && [ -z "$OUT" ] && [ "$before" = "$after" ]; then
    ok "already-current fixture -> exit 0, no write (idempotent)"
else
    bad "already-current fixture -> exit $rc, unexpected rewrite (before='$before' after='$after')"
fi

# ── the hook's own internal self-test still passes ──────────────────────────
rc=0; bash "$HOOK" --self-test >"$WORK/selftest.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "--self-test passes (exit 0)" \
    || bad "--self-test exit $rc; $(cat "$WORK/selftest.out")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
