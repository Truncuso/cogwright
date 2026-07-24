#!/usr/bin/env bash
# goalforge-prototype-retain.test.sh — offline behavioral tests for the retain script.
#
# Drives the REAL goalforge-prototype-retain.sh inside throwaway `git init`
# fixtures (never the live repo). Ignore behavior is asserted via ACTUAL git
# commands — `git check-ignore -q` and `git status --porcelain` — not by parsing
# `.gitignore` text; text asserts appear only as secondary checks.
#
# Cases:
#   discard  folder created, default `*` ignore, no un-ignore lines; probe file
#            is ignored (check-ignore rc 0) and absent from git status.
#   keep     git-identical to discard (ignored in place); JSON tier=keep.
#   share    un-ignore lines present, gitignore_updated=true; probe file NOT
#            ignored (check-ignore rc 1), visible to git status and addable.
#   share re-run  .gitignore byte-identical, gitignore_updated=false, share
#            behavior still holds (idempotency).
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RETAIN="$SD/../goalforge-prototype-retain.sh"
PASS=0; FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
assert() { if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }

FEATURE="feat-x"; SLUG="proto-y"
REL="prototype/$FEATURE/$SLUG"

PARENT="$(mktemp -d)"
trap 'rm -rf "$PARENT"' EXIT

mkrepo() { # $1=name -> prints repo path
    local d="$PARENT/$1"
    mkdir -p "$d"
    git -C "$d" init -q
    git -C "$d" config user.email "test@example.com"
    git -C "$d" config user.name "test"
    printf '%s' "$d"
}

# ── Case: discard ────────────────────────────────────────────────────────────
D="$(mkrepo discard)"; cd "$D"
OUT="$("$RETAIN" "$FEATURE" "$SLUG" discard)"
echo "$OUT" | grep -q '"tier":"discard"'; assert "discard: JSON tier=discard" $?
[[ -d "$REL" ]]; assert "discard: folder created" $?
touch "$REL/probe.txt"
git check-ignore -q "$REL/probe.txt"; assert "discard: probe ignored (check-ignore rc 0)" $?
if git status --porcelain | grep -q "$REL"; then bad "discard: path absent from git status"; else ok "discard: path absent from git status"; fi
grep -qxF '*' prototype/.gitignore; assert "discard: default '*' present (secondary)" $?
if grep -qF "!$FEATURE/" prototype/.gitignore; then bad "discard: no un-ignore lines (secondary)"; else ok "discard: no un-ignore lines (secondary)"; fi

# ── Case: keep (git-identical to discard) ────────────────────────────────────
K="$(mkrepo keep)"; cd "$K"
OUT="$("$RETAIN" "$FEATURE" "$SLUG" keep)"
echo "$OUT" | grep -q '"tier":"keep"'; assert "keep: JSON tier=keep" $?
[[ -d "$REL" ]]; assert "keep: folder created" $?
touch "$REL/probe.txt"
git check-ignore -q "$REL/probe.txt"; assert "keep: probe ignored (check-ignore rc 0)" $?
if git status --porcelain | grep -q "$REL"; then bad "keep: path absent from git status"; else ok "keep: path absent from git status"; fi

# ── Case: share ──────────────────────────────────────────────────────────────
S="$(mkrepo share)"; cd "$S"
OUT="$("$RETAIN" "$FEATURE" "$SLUG" share)"
echo "$OUT" | grep -q '"tier":"share"'; assert "share: JSON tier=share" $?
echo "$OUT" | grep -q '"gitignore_updated":true'; assert "share: gitignore_updated=true" $?
touch "$REL/probe.txt"
if git check-ignore -q "$REL/probe.txt"; then bad "share: probe NOT ignored (check-ignore rc 1)"; else ok "share: probe NOT ignored (check-ignore rc 1)"; fi
git status --porcelain -uall | grep -q "$REL/probe.txt"; assert "share: path visible to git status" $?
git add "$REL/probe.txt" 2>/dev/null; git diff --cached --name-only | grep -q "$FEATURE"; assert "share: path is addable (staged)" $?
grep -qxF "!$FEATURE/" prototype/.gitignore; assert "share: '!$FEATURE/' line present (secondary)" $?
grep -qxF "!$FEATURE/$SLUG/**" prototype/.gitignore; assert "share: deep un-ignore line present (secondary)" $?

# ── Case: share re-run (idempotency) ─────────────────────────────────────────
BEFORE="$(cat prototype/.gitignore)"
BEFORE_LINES="$(wc -l < prototype/.gitignore)"
OUT2="$("$RETAIN" "$FEATURE" "$SLUG" share)"
AFTER="$(cat prototype/.gitignore)"
AFTER_LINES="$(wc -l < prototype/.gitignore)"
[[ "$BEFORE" == "$AFTER" ]]; assert "share re-run: .gitignore byte-identical" $?
[[ "$BEFORE_LINES" == "$AFTER_LINES" ]]; assert "share re-run: no duplicate lines" $?
echo "$OUT2" | grep -q '"gitignore_updated":false'; assert "share re-run: gitignore_updated=false" $?
if git check-ignore -q "$REL/probe.txt"; then bad "share re-run: probe still NOT ignored"; else ok "share re-run: probe still NOT ignored"; fi

# ── Error path: invalid tier (zero-breakage) ─────────────────────────────────
ET="$(mkrepo err-tier)"; cd "$ET"
OUT="$("$RETAIN" "$FEATURE" "$SLUG" bogus 2>err.log)"; RC=$?
[[ "$RC" -eq 0 ]]; assert "invalid tier: exit 0" $?
[[ -z "$OUT" ]]; assert "invalid tier: no JSON on stdout" $?
grep -q 'invalid tier' err.log; assert "invalid tier: stderr note present" $?

# ── Error path: missing args (zero-breakage) ─────────────────────────────────
EM="$(mkrepo err-missing)"; cd "$EM"
OUT="$("$RETAIN" onlyone 2>err.log)"; RC=$?
[[ "$RC" -eq 0 ]]; assert "missing args: exit 0" $?
[[ -z "$OUT" ]]; assert "missing args: no JSON on stdout" $?

# ── Error path: traversal slug (must not escape prototype/ tree) ──────────────
EP="$(mkrepo err-traversal)"; cd "$EP"
OUT="$("$RETAIN" '../../pwned' "$SLUG" keep 2>err.log)"; RC=$?
[[ "$RC" -eq 0 ]]; assert "traversal: exit 0" $?
[[ -z "$OUT" ]]; assert "traversal: no JSON on stdout" $?
if [[ -e "$PARENT/pwned" ]]; then bad "traversal: no dir created outside prototype/ tree"; else ok "traversal: no dir created outside prototype/ tree"; fi
if [[ -e "prototype/.gitignore" ]]; then bad "traversal: .gitignore unchanged (not created)"; else ok "traversal: .gitignore unchanged (not created)"; fi

# ── Hygiene: executable bit (subagent-rewrite gotcha) ────────────────────────
[[ -x "$RETAIN" ]]; assert "goalforge-prototype-retain.sh keeps executable bit" $?

echo
echo "goalforge-prototype-retain.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
