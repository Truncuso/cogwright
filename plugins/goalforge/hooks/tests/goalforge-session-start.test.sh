#!/usr/bin/env bash
# goalforge-session-start.test.sh — sabotage pair for
# goalforge-session-start.sh (b5).
#
# Hermetic: the shipped fixtures under
# evals/fixtures/hooks/goalforge-session-start/ are COPIED into a mktemp root
# first (the checked-in fixture tree is immutable — evals/run.sh compares a
# sha256 manifest across the run), and every case drives the real hook entry
# point with SDD_PLANS_DIR / GOALFORGE_HANDOFFS_DIR pointed at the copy.
#
# The two known-bads are block-shaped rather than hook-shaped, because the
# properties under test are properties OF THE BLOCK: a 16-line block must fail
# the line cap, and a block carrying an expanded absolute home path must fail
# the privacy check. Running those literals through the same assertions is
# what proves the assertions can fail.
set -uo pipefail

HD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HD/goalforge-session-start.sh"
FIX="$HD/../evals/fixtures/hooks/goalforge-session-start"
MAX_LINES=15
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -d "$FIX" ] || { echo "  FAIL: fixture root missing: $FIX"; echo "Results: 0 passed, 1 failed"; exit 1; }
cp -r "$FIX/." "$WORK/fixture/"
mkdir -p "$WORK/empty"

# ── the two assertions under test, applied to any block on stdin ───────────
within_line_cap() { [ "$(grep -c . <<<"$1")" -le "$MAX_LINES" ]; }
privacy_clean() {
    case "$1" in
        *"${HOME:-/nonexistent-home}/"*) return 1 ;;   # expanded absolute home path
    esac
    grep -Eq '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+' <<<"$1" && return 1
    return 0
}

run_on() { # <plans root> <handoffs root>
    SDD_PLANS_DIR="$1" GOALFORGE_HANDOFFS_DIR="$2" bash "$HOOK" </dev/null 2>&1
}

# ── populated fixture root ─────────────────────────────────────────────────
OUT="$(run_on "$WORK/fixture/plans" "$WORK/fixture/handoffs")"; rc=$?
[ "$rc" -eq 0 ] && ok "populated root -> exit 0" || bad "populated root -> exit $rc"

case "$OUT" in *"feat-alpha"*) ok "names the active feature" ;;
    *) bad "feature missing from the block: '$OUT'" ;; esac
case "$OUT" in *"wp-02 [ready]"*) ok "names the frontier WP with its status" ;;
    *) bad "frontier WP + status missing: '$OUT'" ;; esac
case "$OUT" in *"handoffs ready: "*"feat-alpha"*) ok "names the ready handoff slug" ;;
    *) bad "ready handoff slug missing: '$OUT'" ;; esac
case "$OUT" in *"other"*) bad "a non-ready handoff leaked into the block" ;;
    *) ok "the claimed handoff is not listed" ;; esac
case "$OUT" in *"wayfind: "*open*) ok "carries the wayfind open/frontier counts" ;;
    *) bad "wayfind counts missing: '$OUT'" ;; esac
case "$OUT" in *route:*) ok "carries one routing line" ;;
    *) bad "routing line missing: '$OUT'" ;; esac

within_line_cap "$OUT" && ok "block is within the $MAX_LINES-line cap" \
    || bad "block exceeded $MAX_LINES lines"
privacy_clean "$OUT" && ok "block carries no absolute home path and no e-mail" \
    || bad "privacy leak in the block: '$OUT'"

# ── empty plans root -> prints nothing ─────────────────────────────────────
OUT_EMPTY="$(run_on "$WORK/empty" "$WORK/fixture/handoffs")"; rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$OUT_EMPTY" ]; } && ok "empty plans root -> silent, exit 0" \
    || bad "empty plans root -> exit $rc out='$OUT_EMPTY'"

# ── kill switch ────────────────────────────────────────────────────────────
OUT_OFF="$(SDD_PLANS_DIR="$WORK/fixture/plans" GOALFORGE_SESSION_START=0 bash "$HOOK" </dev/null 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$OUT_OFF" ]; } && ok "GOALFORGE_SESSION_START=0 -> silent, exit 0" \
    || bad "kill switch -> exit $rc out='$OUT_OFF'"

# ── known-bad 1: a 16-line block must fail the line cap ───────────────────
BAD16="$(seq 1 16)"
within_line_cap "$BAD16" && bad "sabotage NOT caught: a 16-line block passed the cap" \
    || ok "sabotage caught: 16-line block fails the $MAX_LINES-line cap"

# ── known-bad 2: an expanded home path must fail the privacy check ────────
BADHOME="goalforge orientation
  feat-alpha: ${HOME:-/nonexistent-home}/plans/feat-alpha/wp-02 [ready]"
privacy_clean "$BADHOME" && bad "sabotage NOT caught: absolute home path passed the privacy check" \
    || ok "sabotage caught: absolute home path fails the privacy check"

BADMAIL="goalforge orientation
  handoffs ready: feat-alpha (claimed by someone@example.com)"
privacy_clean "$BADMAIL" && bad "sabotage NOT caught: an e-mail passed the privacy check" \
    || ok "sabotage caught: an e-mail address fails the privacy check"

# ── the scrub is live, not vacuous: a plans root UNDER $HOME must come back
#    with `~` in place of the expanded path wherever a path is printed at all.
HOMEROOT="${HOME:-/nonexistent-home}/.goalforge-session-start-test.$$"
mkdir -p "$HOMEROOT/plans"
cp -r "$WORK/fixture/plans/." "$HOMEROOT/plans/"
OUT_HOME="$(run_on "$HOMEROOT/plans" "$WORK/fixture/handoffs")"
rm -rf "$HOMEROOT"
privacy_clean "$OUT_HOME" && ok "plans root under \$HOME -> still no absolute home path" \
    || bad "home path leaked for a plans root under \$HOME: '$OUT_HOME'"

# ── the hook's own self-test ──────────────────────────────────────────────
rc=0; bash "$HOOK" --self-test >"$WORK/selftest.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "--self-test passes (exit 0)" \
    || bad "--self-test exit $rc; $(cat "$WORK/selftest.out")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
