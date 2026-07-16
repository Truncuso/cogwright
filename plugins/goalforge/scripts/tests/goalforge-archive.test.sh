#!/usr/bin/env bash
# goalforge-archive.test.sh — behavioral regression tests for goalforge-archive.sh.
# Runs the REAL script against throwaway fixture plans trees (never the live
# ~/.claude/plans/). Validator is stubbed via the GOALFORGE_VALIDATE seam so
# each case isolates archive logic from validator behavior.
#
# Cases:
#   1 strand-bug regression: --strict-refs refusal (exit 6) leaves overview.md
#     byte-identical (status: completed intact)      [live repro 2026-07-16]
#   2 ref-gate classification: prose-only mention does NOT refuse under
#     --strict-refs; hard locator ref DOES (exit 6)
#   3 validator failure (exit 5) rolls frontmatter edits back
#   4 destination collision pre-checks BEFORE any write (exit 4, file untouched)
#   5 happy path: completed → archived + moved to _archived/
#   6 --supersedes writes both edges + archives both
#   7 --relocate moves a stranded archived feature (no frontmatter edit)
#   8 hygiene: production scripts keep their executable bit

set -uo pipefail
SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE="$SD/../goalforge-archive.sh"
PASS=0; FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
assert() { # $1=desc $2=condition-result(0/1 via $?)
    if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi
}

mk_feature() { # $1=root $2=slug $3=status
    mkdir -p "$1/$2"
    cat > "$1/$2/overview.md" <<EOF
---
name: $2
status: $3
updated: 2026-07-01
relationships: []
---
# $2
Body of $2.
EOF
}

run_archive() { # all args forwarded; validator stubbed to pass
    GOALFORGE_VALIDATE=/bin/true "$ARCHIVE" "$@"
}

# ── Case 1: strand-bug regression ────────────────────────────────────────────
T=$(mktemp -d); mk_feature "$T/plans" feat-a completed
mkdir -p "$T/plans/other"
echo 'locator: "plans/feat-a/overview.md"' > "$T/plans/other/overview.md"
before=$(cat "$T/plans/feat-a/overview.md")
run_archive feat-a --strict-refs --plans-root "$T/plans" >/dev/null 2>&1
rc=$?
[[ $rc -eq 6 ]]; assert "strict-refs refusal exits 6" $?
after=$(cat "$T/plans/feat-a/overview.md")
[[ "$before" == "$after" ]]; assert "strand-bug: refusal leaves overview.md byte-identical (status: completed intact)" $?
[[ -d "$T/plans/feat-a" && ! -e "$T/plans/_archived/feat-a" ]]; assert "strand-bug: feature not moved on refusal" $?
rm -rf "$T"

# ── Case 2: hard vs prose classification ─────────────────────────────────────
T=$(mktemp -d); mk_feature "$T/plans" feat-b completed
mkdir -p "$T/plans/other"
echo 'We discussed the feat-b/ layout in standup.' > "$T/plans/other/notes.md"
run_archive feat-b --strict-refs --plans-root "$T/plans" >/dev/null 2>&1
[[ $? -eq 0 ]]; assert "prose-only mention does not gate under --strict-refs" $?
rm -rf "$T"

T=$(mktemp -d); mk_feature "$T/plans" feat-c completed
mkdir -p "$T/plans/other"
echo 'See [the findings](../feat-c/findings.md) for detail.' > "$T/plans/other/notes.md"
run_archive feat-c --strict-refs --plans-root "$T/plans" >/dev/null 2>&1
[[ $? -eq 6 ]]; assert "markdown link target ref gates under --strict-refs (exit 6)" $?
rm -rf "$T"

# ── Case 3: validator failure rolls back ─────────────────────────────────────
T=$(mktemp -d); mk_feature "$T/plans" feat-d completed
before=$(cat "$T/plans/feat-d/overview.md")
GOALFORGE_VALIDATE=/bin/false "$ARCHIVE" feat-d --plans-root "$T/plans" >/dev/null 2>&1
rc=$?
[[ $rc -eq 5 ]]; assert "validator failure exits 5" $?
after=$(cat "$T/plans/feat-d/overview.md")
[[ "$before" == "$after" ]]; assert "validator failure rolls frontmatter edits back" $?
rm -rf "$T"

# ── Case 4: destination collision pre-check ──────────────────────────────────
T=$(mktemp -d); mk_feature "$T/plans" feat-e completed
mkdir -p "$T/plans/_archived/feat-e"
before=$(cat "$T/plans/feat-e/overview.md")
run_archive feat-e --plans-root "$T/plans" >/dev/null 2>&1
rc=$?
[[ $rc -eq 4 ]]; assert "destination collision exits 4" $?
after=$(cat "$T/plans/feat-e/overview.md")
[[ "$before" == "$after" ]]; assert "collision pre-check runs before any write (file untouched)" $?
rm -rf "$T"

# ── Case 5: happy path ───────────────────────────────────────────────────────
T=$(mktemp -d); mk_feature "$T/plans" feat-f completed
run_archive feat-f --plans-root "$T/plans" >/dev/null 2>&1
[[ $? -eq 0 ]]; assert "happy path exits 0" $?
grep -q '^status: archived' "$T/plans/_archived/feat-f/overview.md" 2>/dev/null
assert "happy path: status archived + moved to _archived/" $?
rm -rf "$T"

# ── Case 6: supersedes both edges ────────────────────────────────────────────
T=$(mktemp -d); mk_feature "$T/plans" feat-new completed; mk_feature "$T/plans" feat-old completed
run_archive feat-new --supersedes feat-old --plans-root "$T/plans" >/dev/null 2>&1
[[ $? -eq 0 ]]; assert "supersedes archive exits 0" $?
grep -q 'supersedes: \[\[feat-old\]\]' "$T/plans/_archived/feat-new/overview.md" 2>/dev/null
assert "supersedes edge written on new feature" $?
grep -q 'superseded_by: \[\[feat-new\]\]' "$T/plans/_archived/feat-old/overview.md" 2>/dev/null
assert "superseded_by edge written on old feature (both archived)" $?
rm -rf "$T"

# ── Case 7: relocate stranded archived feature ───────────────────────────────
T=$(mktemp -d); mk_feature "$T/plans" feat-g archived
before=$(cat "$T/plans/feat-g/overview.md")
run_archive feat-g --relocate --plans-root "$T/plans" >/dev/null 2>&1
[[ $? -eq 0 ]]; assert "relocate exits 0" $?
after=$(cat "$T/plans/_archived/feat-g/overview.md" 2>/dev/null)
[[ "$before" == "$after" ]]; assert "relocate is move-only (no frontmatter edit)" $?
rm -rf "$T"

# ── Case 8: executable bits (subagent-rewrite gotcha) ────────────────────────
[[ -x "$ARCHIVE" ]]; assert "goalforge-archive.sh keeps executable bit" $?

echo
echo "goalforge-archive.test.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
