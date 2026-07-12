#!/usr/bin/env bash
# sdd-onboard evals/run.sh — deterministic eval harness
# Exit 0 = all pass, exit 1 = one or more failures.
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SKILL_DIR/scripts/sdd-onboard.sh"
SKILL_MD="$SKILL_DIR/SKILL.md"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

cleanup() {
    [[ -n "${TMPDIR1:-}" ]] && rm -rf "$TMPDIR1"
    [[ -n "${TMPDIR2:-}" ]] && rm -rf "$TMPDIR2"
}
trap cleanup EXIT

echo "=== sdd-onboard evals ==="
echo ""

# ── Trigger 1: SKILL.md description carries onboard trigger phrases ───────────
echo "[trigger-1] SKILL.md description has onboard trigger phrases"
for phrase in "onboard this repo to SDD" "set up the SDD chain here" "install the SDD git hook" "scaffold plans/"; do
    if grep -qF "$phrase" "$SKILL_MD"; then
        pass "description contains '$phrase'"
    else
        fail "description missing '$phrase'"
    fi
done

echo ""

# ── Trigger 2: SKILL.md has ## Gotchas section ────────────────────────────────
echo "[trigger-2] SKILL.md has ## Gotchas section"
if grep -qE '^## Gotchas' "$SKILL_MD"; then
    pass "## Gotchas section present"
else
    fail "## Gotchas section missing"
fi

echo ""

# ── Trigger 3 (negative): description field must NOT reference legacy GSD surface
# The Gotchas section may name these things in a negative/warning context; the
# frontmatter description is the trigger surface that must stay clean.
echo "[trigger-3] SKILL.md description field does NOT reference legacy GSD surface"
# Extract frontmatter (between first and second ---), then isolate description value
FRONTMATTER=$(awk '/^---$/{c++; if(c==2) exit} c==1' "$SKILL_MD")
DESCRIPTION=$(printf '%s\n' "$FRONTMATTER" | awk '/^description:/{p=1} p && /^[a-z]/ && !/^description:/{p=0} p{print}')
for term in "GitHub issues" "triage label" "10-state"; do
    if printf '%s\n' "$DESCRIPTION" | grep -qiF "$term"; then
        fail "description field must NOT contain '$term'"
    else
        pass "description field has no mention of '$term'"
    fi
done

echo ""

# ── Functional 1: bootstrap a fresh temp repo ─────────────────────────────────
echo "[functional-1] sdd-onboard.sh bootstraps a fresh temp repo"
TMPDIR1=$(mktemp -d)
git -C "$TMPDIR1" init -q

if bash "$SCRIPT" "$TMPDIR1" >/dev/null 2>&1; then
    true
else
    fail "sdd-onboard.sh exited non-zero on fresh repo"
fi

if [[ -d "$TMPDIR1/plans" ]]; then
    pass "plans/ exists after onboarding"
else
    fail "plans/ missing after onboarding"
fi

if [[ -f "$TMPDIR1/.git/hooks/pre-commit" ]]; then
    pass ".git/hooks/pre-commit exists"
else
    fail ".git/hooks/pre-commit missing"
fi

if grep -qF '# >>> sdd-pre-commit >>>' "$TMPDIR1/.git/hooks/pre-commit" 2>/dev/null; then
    pass "pre-commit contains sdd-pre-commit marker"
else
    fail "pre-commit missing sdd-pre-commit marker"
fi

if [[ -f "$TMPDIR1/CLAUDE.md" ]]; then
    pass "CLAUDE.md exists after onboarding"
else
    fail "CLAUDE.md missing after onboarding"
fi

SDD_COUNT=$(grep -c '## SDD' "$TMPDIR1/CLAUDE.md" 2>/dev/null || echo 0)
if [[ "$SDD_COUNT" -eq 1 ]]; then
    pass "CLAUDE.md has exactly one ## SDD block"
else
    fail "CLAUDE.md has $SDD_COUNT '## SDD' occurrences (expected 1)"
fi

echo ""

# ── Functional 2: idempotency ─────────────────────────────────────────────────
echo "[functional-2] second run is idempotent"
TMPDIR2=$(mktemp -d)
git -C "$TMPDIR2" init -q

bash "$SCRIPT" "$TMPDIR2" >/dev/null 2>&1

# Capture state after first run
HOOK_SUM_1=$(sha256sum "$TMPDIR2/.git/hooks/pre-commit" 2>/dev/null | awk '{print $1}')

# Second run
bash "$SCRIPT" "$TMPDIR2" >/dev/null 2>&1

HOOK_SUM_2=$(sha256sum "$TMPDIR2/.git/hooks/pre-commit" 2>/dev/null | awk '{print $1}')
if [[ "$HOOK_SUM_1" == "$HOOK_SUM_2" ]]; then
    pass "pre-commit file byte-identical after second run"
else
    fail "pre-commit file changed after second run (idempotency broken)"
fi

SDD_COUNT2=$(grep -c '## SDD' "$TMPDIR2/CLAUDE.md" 2>/dev/null || echo 0)
if [[ "$SDD_COUNT2" -eq 1 ]]; then
    pass "CLAUDE.md has exactly one '## SDD' block after second run"
else
    fail "CLAUDE.md has $SDD_COUNT2 '## SDD' occurrences after second run (expected 1)"
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
