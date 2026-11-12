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
# Two lessons from verify round 1 shape this file:
#
#   V1 — the fixture plans tree used to be called `plans/`, which the repo's
#   .gitignore matches at ANY path segment, so most of it never entered the
#   commit and the hook quietly resolved the USER'S live plans tree instead.
#   The tree is now `plans-root/` (no `plans` segment anywhere), the copied
#   fixture is ASSERTED complete before a single case runs, and the "explicit
#   but missing SDD_PLANS_DIR prints nothing" case pins the hook behaviour
#   that made the silent fall-through possible.
#
#   V2 — the privacy and line-cap assertions used to be applied to literal
#   strings written here, so they could not fail against the hook. They are
#   now applied to the output of SABOTAGE COPIES of the hook itself: a copy
#   that injects an absolute home path and an e-mail into the block, the same
#   copy with the scrub removed, and a copy with the line cap and the
#   MAX_FEATURES break removed run against a 20-feature fixture. The real hook
#   must clean/cap; each sabotage must go red.
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

# ── fixture precondition (V1): the copy must be COMPLETE before any case ───
# A half-committed fixture tree is exactly what made the round-1 suite read the
# user's real plans/ tree while reporting 16/16 green. Every expected file is
# named; a missing one aborts the suite instead of degrading it.
[ -d "$FIX" ] || { echo "  FAIL: fixture root missing: $FIX"; echo "Results: 0 passed, 1 failed"; exit 1; }
mkdir -p "$WORK/fixture"
cp -r "$FIX/." "$WORK/fixture/"

EXPECTED_FIXTURE_FILES="
plans-root/feat-alpha/overview.md
plans-root/feat-alpha/wp-01/overview.md
plans-root/feat-alpha/wp-02/overview.md
plans-root/effort-map/wayfind/ticket-01-first.md
plans-root/effort-map/wayfind/ticket-02-second.md
plans-root/effort-map/wayfind/map.md
wayfind-cases/effort-blocked/wayfind/map.md
wayfind-cases/effort-blocked/wayfind/ticket-01-root.md
wayfind-cases/effort-blocked/wayfind/ticket-02-child.md
wayfind-cases/effort-blocked/wayfind/ticket-03-grandchild.md
wayfind-cases/effort-graduated/wayfind/map.md
wayfind-cases/effort-graduated/wayfind/ticket-01-leftover.md
wayfind-cases/effort-nomap/wayfind/ticket-01-orphan.md
wayfind-cases/effort-comment/wayfind/map.md
wayfind-cases/effort-comment/wayfind/ticket-01-one.md
wayfind-cases/effort-crlf/wayfind/map.md
wayfind-cases/effort-crlf/wayfind/ticket-01-one.md
wayfind-cases/effort-charting/wayfind/map.md
wayfind-cases/effort-charting/wayfind/ticket-01-one.md
handoffs/feat-alpha/2026-01-01-handoff.md
handoffs/other/2026-01-01-handoff.md
"
MISSING=""
for rel in $EXPECTED_FIXTURE_FILES; do
    [ -f "$WORK/fixture/$rel" ] || MISSING="$MISSING $rel"
done
if [ -n "$MISSING" ]; then
    echo "  FAIL: the copied fixture root is incomplete —$MISSING"
    echo "        (a gitignored fixture path is the round-1 V1 defect; check"
    echo "         git check-ignore -v on $FIX)"
    echo ""
    echo "Results: 0 passed, 1 failed"
    exit 1
fi
ok "copied fixture root is complete (21 files, no gitignored segment)"

PLANS="$WORK/fixture/plans-root"
HANDOFFS="$WORK/fixture/handoffs"
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

run_hook_on() { # <hook> <plans root> <handoffs root>
    SDD_PLANS_DIR="$2" GOALFORGE_HANDOFFS_DIR="$3" bash "$1" </dev/null 2>&1
}
run_on() { run_hook_on "$HOOK" "$1" "$2"; }

# ── populated fixture root ─────────────────────────────────────────────────
OUT="$(run_on "$PLANS" "$HANDOFFS")"; rc=$?
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
OUT_EMPTY="$(run_on "$WORK/empty" "$HANDOFFS")"; rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$OUT_EMPTY" ]; } && ok "empty plans root -> silent, exit 0" \
    || bad "empty plans root -> exit $rc out='$OUT_EMPTY'"

# ── V1: an EXPLICIT but missing SDD_PLANS_DIR prints nothing ───────────────
# It must never fall through to <git-root>/plans — that fall-through is how the
# round-1 suite ended up reading the user's live plans tree.
OUT_MISSING="$(run_on "$WORK/no-such-plans-root" "$HANDOFFS")"; rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$OUT_MISSING" ]; } \
    && ok "explicit-but-missing SDD_PLANS_DIR -> silent, exit 0" \
    || bad "missing SDD_PLANS_DIR fell through to another root: exit $rc out='$OUT_MISSING'"

# ── kill switch ────────────────────────────────────────────────────────────
OUT_OFF="$(SDD_PLANS_DIR="$PLANS" GOALFORGE_SESSION_START=0 bash "$HOOK" </dev/null 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$OUT_OFF" ]; } && ok "GOALFORGE_SESSION_START=0 -> silent, exit 0" \
    || bad "kill switch -> exit $rc out='$OUT_OFF'"

# ── V4: completed/archived features never occupy a MAX_FEATURES slot ───────
# 8 completed features alphabetically BEFORE one active feature: without the
# skip, the cap fills with finished work and the active feature is evicted.
V4="$WORK/v4/plans-root"
for i in 1 2 3 4 5 6 7 8; do
    mkdir -p "$V4/aa-done-$i/wp-01"
    printf -- '---\nstatus: completed\n---\n' > "$V4/aa-done-$i/overview.md"
    printf -- '---\nstatus: verified\n---\n'  > "$V4/aa-done-$i/wp-01/overview.md"
done
mkdir -p "$V4/zz-active/wp-01"
printf -- '---\nstatus: active\n---\n' > "$V4/zz-active/overview.md"
printf -- '---\nstatus: ready\n---\n'  > "$V4/zz-active/wp-01/overview.md"

OUT_V4="$(run_on "$V4" "$WORK/empty")"
case "$OUT_V4" in *"zz-active: wp-01 [ready]"*) ok "the active feature survives 8 completed ones" ;;
    *) bad "active feature evicted by completed features: '$OUT_V4'" ;; esac
case "$OUT_V4" in *aa-done-*) bad "a completed feature was printed: '$OUT_V4'" ;;
    *) ok "no completed feature is printed" ;; esac

# ── wayfind counts come from the PARSED frontier JSON, over live maps only ──
# Each case root = the active feature + effort-map (working, 2 open, 2 on the
# frontier) + one case effort, so the line is exact and the case effort's
# contribution is the difference from 2/2.
wayfind_root() { # <case name> [case effort] -> prints a fresh plans root
    local r="$WORK/wf-$1/plans-root"
    mkdir -p "$r"
    cp -r "$PLANS/feat-alpha" "$PLANS/effort-map" "$r/"
    [ -z "${2:-}" ] || cp -r "$WORK/fixture/wayfind-cases/$2" "$r/"
    printf '%s' "$r"
}
wayfind_line() { grep '^  wayfind: ' <<<"$1"; }

OUT_WF="$(run_on "$(wayfind_root base)" "$WORK/empty")"
[ "$(wayfind_line "$OUT_WF")" = "  wayfind: 2 open, 2 on the frontier" ] \
    && ok "effort-map (working) -> 2 open, 2 on the frontier" \
    || bad "effort-map counts wrong: '$(wayfind_line "$OUT_WF")'"

# blocked tickets and their waiting_on ids are NOT frontier entries: +3 open, +1.
OUT_WF="$(run_on "$(wayfind_root blocked effort-blocked)" "$WORK/empty")"
[ "$(wayfind_line "$OUT_WF")" = "  wayfind: 5 open, 3 on the frontier" ] \
    && ok "blocked tickets -> frontier counts len(frontier) only" \
    || bad "blocked-ticket counts wrong (want 5 open, 3 on the frontier): '$(wayfind_line "$OUT_WF")'"

# a graduated map contributes 0 to both counts, open tickets notwithstanding.
OUT_WF="$(run_on "$(wayfind_root graduated effort-graduated)" "$WORK/empty")"
[ "$(wayfind_line "$OUT_WF")" = "  wayfind: 2 open, 2 on the frontier" ] \
    && ok "graduated map -> contributes 0 to open and frontier" \
    || bad "graduated-map counts wrong (want 2 open, 2 on the frontier): '$(wayfind_line "$OUT_WF")'"

# a wayfind dir with no map.md contributes 0 to both counts.
OUT_WF="$(run_on "$(wayfind_root nomap effort-nomap)" "$WORK/empty")"
[ "$(wayfind_line "$OUT_WF")" = "  wayfind: 2 open, 2 on the frontier" ] \
    && ok "no map.md -> contributes 0 to open and frontier" \
    || bad "no-map counts wrong (want 2 open, 2 on the frontier): '$(wayfind_line "$OUT_WF")'"

# the hook reads a map's status the way validate-map.sh does: a trailing
# ` # comment` (the SKILL.md template carries one), CRLF line endings and a
# quoted value all leave a live map live. Each adds 1 open, 1 on the frontier;
# the charting map pins the `charting` arm of the live-status filter.
for wc in comment crlf charting; do
    OUT_WF="$(run_on "$(wayfind_root "$wc" "effort-$wc")" "$WORK/empty")"
    [ "$(wayfind_line "$OUT_WF")" = "  wayfind: 3 open, 3 on the frontier" ] \
        && ok "map status ($wc) -> counted as a live map" \
        || bad "map status ($wc) counts wrong (want 3 open, 3 on the frontier): '$(wayfind_line "$OUT_WF")'"
done

# spec D8: an effort whose frontier output does not parse into a list counts 0
# and the others still count. (i) a stub frontier script, beside a copy of the
# hook, prints a string `frontier` for effort-comment only and runs the real
# script for effort-map: want 3 open (2 + 1), 2 on the frontier (effort-map's
# 2 + 0) — len("abcdefg") would give 9, dropping the frontier count "3 open".
# (ii) a python3 that is present but fails: every parse fails, so 0.
NL="$WORK/nonlist"
mkdir -p "$NL/hooks" "$NL/wayfind/scripts"
cp "$HD"/goalforge-*.sh "$NL/hooks/"
{ printf '#!/usr/bin/env bash\n'
  printf 'case "$(basename "$1")" in\n'
  printf '  effort-comment) printf '"'"'%%s\\n'"'"' '"'"'{"frontier": "abcdefg"}'"'"' ;;\n'
  printf '  *) exec bash %q "$@" ;;\n' "$HD/../wayfind/scripts/wayfind-frontier.sh"
  printf 'esac\n'
} > "$NL/wayfind/scripts/wayfind-frontier.sh"
OUT_WF="$(run_hook_on "$NL/hooks/goalforge-session-start.sh" "$(wayfind_root nonlist effort-comment)" "$WORK/empty")"
[ "$(wayfind_line "$OUT_WF")" = "  wayfind: 3 open, 2 on the frontier" ] \
    && ok "non-list frontier -> that effort counts 0, the others still count" \
    || bad "non-list frontier (want '  wayfind: 3 open, 2 on the frontier'): '$(wayfind_line "$OUT_WF")'"

FP="$WORK/failpy-bin"
mkdir -p "$FP"
for c in bash readlink dirname basename sed head grep wc cat tr date mktemp rm sort; do
    ln -sf "$(command -v "$c")" "$FP/$c"
done
printf '#!/bin/sh\nexit 1\n' > "$FP/python3"; chmod +x "$FP/python3"
FP_ROOT="$(wayfind_root failpy)"
OUT_WF="$(PATH="$FP" SDD_PLANS_DIR="$FP_ROOT" GOALFORGE_HANDOFFS_DIR="$WORK/empty" bash "$HOOK" </dev/null 2>&1)"
[ "$(wayfind_line "$OUT_WF")" = "  wayfind: 2 open, 0 on the frontier" ] \
    && ok "failing python3 parse -> every effort counts 0 on the frontier" \
    || bad "failing python3 parse (want '  wayfind: 2 open, 0 on the frontier'): '$(wayfind_line "$OUT_WF")'"

# python3 absent: the wayfind line is omitted and the hook still exits 0. The
# sandbox PATH carries the other commands the hook and the frontier script use;
# the positive control adds python3 back and must print the line, so the run is
# not short-circuiting on some other missing command.
SB="$WORK/sandbox-bin"
mkdir -p "$SB"
for c in bash readlink dirname basename sed head grep wc cat tr date mktemp rm sort; do
    ln -sf "$(command -v "$c")" "$SB/$c"
done
WF_BASE="$(wayfind_root nopy)"
OUT_NOPY="$(PATH="$SB" SDD_PLANS_DIR="$WF_BASE" GOALFORGE_HANDOFFS_DIR="$WORK/empty" bash "$HOOK" </dev/null 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && case "$OUT_NOPY" in *"feat-alpha: wp-02 [ready]"*) true ;; *) false ;; esac \
    && [ -z "$(wayfind_line "$OUT_NOPY")" ]; } \
    && ok "python3 missing from PATH -> wayfind line omitted, exit 0" \
    || bad "python3 missing: want rc 0, the feature line and no wayfind line (rc=$rc): '$OUT_NOPY'"
ln -sf "$(command -v python3)" "$SB/python3"
OUT_PY="$(PATH="$SB" SDD_PLANS_DIR="$WF_BASE" GOALFORGE_HANDOFFS_DIR="$WORK/empty" bash "$HOOK" </dev/null 2>&1)"
[ "$(wayfind_line "$OUT_PY")" = "  wayfind: 2 open, 2 on the frontier" ] \
    && ok "sandbox PATH + python3 -> wayfind line printed (control)" \
    || bad "sandbox PATH + python3 should print the wayfind line (control): '$OUT_PY'"

# ── sabotage copies of the HOOK ────────────────────────────────────────────
# The stubs live in a COPY of the hooks dir: the hook sources
# goalforge-plans-root.sh from beside itself, and a stub without that sibling
# would exit 0 at line 1 and make every sabotage "pass" for the wrong reason.
STUBDIR="$WORK/hooks"
mkdir -p "$STUBDIR"
cp "$HD"/goalforge-*.sh "$STUBDIR/"

# Inject a privacy leak into build_block's output, BEFORE emit() sees it.
# `$HOME` stays literal in the stub and expands when the stub runs.
LEAK_PROG='\%echo "  route:%a\
    echo "  leak: $HOME/some/path someone@example.com"'
# Replace the whole scrub-and-cap pipeline with cat|head: privacy gone, cap kept.
NOSCRUB_PROG='/^    sed -e /,/^        | head/c\    cat | head -n "$MAX_LINES"'

sed "$LEAK_PROG" "$HOOK"                          > "$STUBDIR/leak.sh"
sed "$NOSCRUB_PROG" "$STUBDIR/leak.sh"            > "$STUBDIR/leak-noscrub.sh"
sed -e 's%| head -n "$MAX_LINES"%| cat%' \
    -e 's%\[ "$n" -ge "$MAX_FEATURES" \] && break%:%' "$HOOK" > "$STUBDIR/nocap.sh"
sed 's%if \[ -n "${SDD_PLANS_DIR:-}" \]; then%if false; then%' "$HOOK" > "$STUBDIR/fallthrough.sh"
sed 's%completed|archived) continue ;;%completed|archived) ;;%' "$HOOK" > "$STUBDIR/noskip.sh"
sed 's%\[ "$n" -ge "$MAX_FEATURES" \] && break%:%' "$HOOK" > "$STUBDIR/nobreak.sh"

for stub in leak leak-noscrub nocap fallthrough noskip nobreak; do
    bash -n "$STUBDIR/$stub.sh" || bad "sabotage stub $stub.sh is not valid bash"
done

# The sed programs above must actually have changed something — a sabotage that
# silently no-ops is a green line that tests nothing.
for stub in leak leak-noscrub nocap fallthrough noskip nobreak; do
    if cmp -s "$HOOK" "$STUBDIR/$stub.sh"; then
        bad "sabotage $stub.sh is identical to the hook (its sed program matched nothing)"
    else
        ok "sabotage $stub.sh differs from the hook"
    fi
done

# (i) the injected leak must be CLEANED by the real scrub
OUT_LEAK="$(run_hook_on "$STUBDIR/leak.sh" "$PLANS" "$HANDOFFS")"
case "$OUT_LEAK" in *"~/some/path"*) ok "the real scrub rewrites an injected \$HOME path to ~" ;;
    *) bad "injected leak line absent or unscrubbed: '$OUT_LEAK'" ;; esac
privacy_clean "$OUT_LEAK" && ok "the real scrub cleans an injected home path and e-mail" \
    || bad "the real scrub let an injected leak through: '$OUT_LEAK'"

# (ii) the same leak with the scrub REMOVED must fail the privacy assertion
OUT_NOSCRUB="$(run_hook_on "$STUBDIR/leak-noscrub.sh" "$PLANS" "$HANDOFFS")"
privacy_clean "$OUT_NOSCRUB" \
    && bad "sabotage NOT caught: scrub removed, privacy assertion still passed: '$OUT_NOSCRUB'" \
    || ok "sabotage caught: scrub removed -> privacy assertion fails"

# (iii) 20 features: the real hook stays capped, the uncapped copy must not
BIG="$WORK/big/plans-root"
for i in $(seq -w 1 20); do
    mkdir -p "$BIG/feat-$i/wp-01"
    printf -- '---\nstatus: active\n---\n' > "$BIG/feat-$i/overview.md"
    printf -- '---\nstatus: ready\n---\n'  > "$BIG/feat-$i/wp-01/overview.md"
done
OUT_BIG="$(run_on "$BIG" "$WORK/empty")"
within_line_cap "$OUT_BIG" && ok "20 features -> real hook still within the $MAX_LINES-line cap" \
    || bad "20 features overflowed the cap: '$OUT_BIG'"
OUT_NOCAP="$(run_hook_on "$STUBDIR/nocap.sh" "$BIG" "$WORK/empty")"
within_line_cap "$OUT_NOCAP" \
    && bad "sabotage NOT caught: head + MAX_FEATURES break removed, cap assertion still passed" \
    || ok "sabotage caught: cap removed -> line-cap assertion fails"

# The cap has TWO independent mechanisms and the line count alone cannot tell
# them apart (8 features + 3 trailing lines never reaches 15), so each is
# asserted on its own — otherwise removing either one stays green.
#   MAX_FEATURES break: 20 features must yield exactly 8 feature lines.
N_FEAT="$(grep -c '^  feat-' <<<"$OUT_BIG")"
[ "$N_FEAT" -eq 8 ] && ok "MAX_FEATURES break is live (8 of 20 features listed)" \
    || bad "MAX_FEATURES break is not capping: $N_FEAT feature lines from 20 features"
#   head backstop: with the break removed it is the ONLY cap left, so the block
#   must come back truncated to exactly MAX_LINES.
OUT_NOBREAK="$(run_hook_on "$STUBDIR/nobreak.sh" "$BIG" "$WORK/empty")"
N_NOBREAK="$(grep -c . <<<"$OUT_NOBREAK")"
[ "$N_NOBREAK" -eq "$MAX_LINES" ] \
    && ok "head backstop is live (break removed -> truncated to $MAX_LINES lines)" \
    || bad "head backstop is not capping: $N_NOBREAK lines with the break removed"

# (iv) V1 sabotage: a hook that falls through an explicit-but-missing root
OUT_FT="$(run_hook_on "$STUBDIR/fallthrough.sh" "$WORK/no-such-plans-root" "$HANDOFFS")"
[ -n "$OUT_FT" ] \
    && ok "sabotage caught: fall-through on a missing explicit root reads another tree" \
    || bad "sabotage NOT caught: fall-through stub printed nothing (assertion may be vacuous)"

# (v) V4 sabotage: a hook that does not skip completed features
OUT_NOSKIP="$(run_hook_on "$STUBDIR/noskip.sh" "$V4" "$WORK/empty")"
case "$OUT_NOSKIP" in *"zz-active"*)
        bad "sabotage NOT caught: skip removed and the active feature still printed" ;;
    *)  ok "sabotage caught: skip removed -> completed features evict the active one" ;; esac

# ── the scrub is live, not vacuous: a plans root UNDER $HOME must come back
#    with `~` in place of the expanded path wherever a path is printed at all.
HOMEROOT="${HOME:-/nonexistent-home}/.goalforge-session-start-test.$$"
mkdir -p "$HOMEROOT/plans-root"
cp -r "$PLANS/." "$HOMEROOT/plans-root/"
OUT_HOME="$(run_on "$HOMEROOT/plans-root" "$HANDOFFS")"
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
