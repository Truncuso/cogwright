#!/usr/bin/env bash
# goalforge-launch-gate.test.sh — sabotage pair for goalforge-launch-gate.sh
# (b1, b2).
#
# Every case drives the REAL hook entry point: a PreToolUse payload on stdin,
# the quota read through the real adapter under GOALFORGE_QUOTA_FIXTURE, and
# the session marker pinned to a mktemp root so nothing is written under
# ${TMPDIR:-/tmp}/goalforge-launch-gate/.
#
# The known-bads this suite exists to catch:
#   - a gate that exits 0 below the threshold          -> "below -> exit 2"
#   - a gate that exits 2 when the fixture is absent   -> "absent -> exit 0"
#   - a gate that still blocks under GOALFORGE_LAUNCH_GATE=0 -> "disabled"
#   - a gate that prints the WARN on every run         -> "once per session"
#   - a gate that never re-WARNs after the marker is gone -> "fresh session"
# Each is asserted directly AND re-checked against a stubbed known-bad hook, so
# a green line here cannot come from an assertion that could not fail.
set -uo pipefail

HD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HD/goalforge-launch-gate.sh"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

printf '{"five_h_remaining_pct": 3, "seven_d_remaining_pct": 55}\n' > "$WORK/low.json"
printf '{"five_h_remaining_pct": 80, "seven_d_remaining_pct": 90}\n' > "$WORK/high.json"
printf 'this is not json\n' > "$WORK/garbage.json"

PAYLOAD='{"session_id":"sess-test","tool_name":"Agent","tool_input":{"description":"x"}}'

# run <hook> <fixture-path> <marker-dir> [extra env assignments...]
# echoes: "<rc>\n<combined output>"
run_hook() {
    local hook="$1" fixture="$2" marker="$3"; shift 3
    local out rc=0
    out="$(printf '%s' "$PAYLOAD" | env GOALFORGE_QUOTA_FIXTURE="$fixture" \
        GOALFORGE_LAUNCH_MARKER_DIR="$marker" "$@" bash "$hook" 2>&1)" || rc=$?
    printf '%s\n' "$rc"
    printf '%s' "$out"
}

rc_of()  { printf '%s' "$1" | head -n 1; }
out_of() { printf '%s' "$1" | tail -n +2; }

# ── b1 case 1: below the threshold -> exit 2, pct AND threshold on stderr ──
R="$(run_hook "$HOOK" "$WORK/low.json" "$WORK/m1")"
rc="$(rc_of "$R")"; out="$(out_of "$R")"
[ "$rc" = 2 ] && ok "below threshold -> exit 2" || bad "below threshold -> exit $rc (want 2)"
case "$out" in *"3%"*) ok "block names the remaining percentage" ;;
    *) bad "block does not name the remaining percentage: '$out'" ;; esac
case "$out" in *"10%"*) ok "block names the threshold" ;;
    *) bad "block does not name the threshold: '$out'" ;; esac

# ── b1 case 2: above the threshold -> exit 0, silent ───────────────────────
R="$(run_hook "$HOOK" "$WORK/high.json" "$WORK/m2")"
rc="$(rc_of "$R")"; out="$(out_of "$R")"
{ [ "$rc" = 0 ] && [ -z "$out" ]; } && ok "above threshold -> exit 0, silent" \
    || bad "above threshold -> exit $rc out='$out'"

# ── b1 case 3: fixture absent, and fixture unparseable -> exit 0, silent ───
R="$(run_hook "$HOOK" "$WORK/does-not-exist.json" "$WORK/m3")"
rc="$(rc_of "$R")"; out="$(out_of "$R")"
{ [ "$rc" = 0 ] && [ -z "$out" ]; } && ok "absent quota source -> exit 0, silent" \
    || bad "absent quota source -> exit $rc out='$out'"

R="$(run_hook "$HOOK" "$WORK/garbage.json" "$WORK/m3b")"
rc="$(rc_of "$R")"; out="$(out_of "$R")"
{ [ "$rc" = 0 ] && [ -z "$out" ]; } && ok "unparseable quota source -> exit 0, silent" \
    || bad "unparseable quota source -> exit $rc out='$out'"

# ── b1 case 4: threshold override moves the verdict ────────────────────────
R="$(run_hook "$HOOK" "$WORK/high.json" "$WORK/m4" GOALFORGE_LAUNCH_THRESHOLD_PCT=95)"
[ "$(rc_of "$R")" = 2 ] && ok "threshold override 95 blocks an 80% reading" \
    || bad "threshold override ignored (rc=$(rc_of "$R"))"

# ── b1 case 5 (T3b removal drill): the kill switch ─────────────────────────
R="$(run_hook "$HOOK" "$WORK/low.json" "$WORK/m5" GOALFORGE_LAUNCH_GATE=0)"
rc="$(rc_of "$R")"; out="$(out_of "$R")"
{ [ "$rc" = 0 ] && [ -z "$out" ]; } \
    && ok "GOALFORGE_LAUNCH_GATE=0 under threshold -> exit 0, silent" \
    || bad "kill switch did not disable the gate (rc=$rc out='$out')"

# ── b2: the WARN prints once per session ───────────────────────────────────
M="$WORK/session-marker"
R1="$(run_hook "$HOOK" "$WORK/low.json" "$M")"
R2="$(run_hook "$HOOK" "$WORK/low.json" "$M")"
o1="$(out_of "$R1")"; o2="$(out_of "$R2")"
case "$o1" in *WARN*) ok "run 1 prints the WARN" ;; *) bad "run 1 printed no WARN: '$o1'" ;; esac
[ "$(rc_of "$R1")" = 2 ] && [ "$(rc_of "$R2")" = 2 ] \
    && ok "both runs still exit 2" || bad "a repeat run stopped blocking"
case "$o2" in *WARN*) bad "run 2 re-printed the WARN: '$o2'" ;; *) ok "run 2 prints no WARN" ;; esac
case "$o2" in *BLOCK*) ok "run 2 still prints the one-line BLOCK" ;;
    *) bad "run 2 printed no BLOCK line: '$o2'" ;; esac

rm -rf "$M"
R3="$(run_hook "$HOOK" "$WORK/low.json" "$M")"
case "$(out_of "$R3")" in *WARN*) ok "marker removed (fresh session) -> WARN prints again" ;;
    *) bad "no WARN after the marker was removed" ;; esac

# ── sabotage: each known-bad hook must fail the assertion that covers it ───

# The stubs live in a COPY of the hooks dir, not in $WORK's root: the hook
# resolves its quota adapter beside itself, and a stub with no sibling adapter
# would read an unknown quota and exit 0 for the wrong reason — every sabotage
# case would then "pass" without testing anything.
STUBDIR="$WORK/hooks"
mkdir -p "$STUBDIR"
cp "$HD"/goalforge-*.sh "$STUBDIR/"

sabotage() { # <label> <sed program> <check: below|absent|disabled|once>
    local label="$1" prog="$2" kind="$3" stub="$STUBDIR/bad-$3.sh" r o c
    sed "$prog" "$HOOK" > "$stub"
    case "$kind" in
        below)    r="$(run_hook "$stub" "$WORK/low.json" "$WORK/s1")"; c="$(rc_of "$r")"
                  [ "$c" != 2 ] && ok "sabotage caught: $label" || bad "sabotage NOT caught: $label" ;;
        absent)   r="$(run_hook "$stub" "$WORK/does-not-exist.json" "$WORK/s2")"; c="$(rc_of "$r")"
                  [ "$c" != 0 ] && ok "sabotage caught: $label" || bad "sabotage NOT caught: $label" ;;
        disabled) r="$(run_hook "$stub" "$WORK/low.json" "$WORK/s3" GOALFORGE_LAUNCH_GATE=0)"
                  c="$(rc_of "$r")"; o="$(out_of "$r")"
                  { [ "$c" != 0 ] || [ -n "$o" ]; } && ok "sabotage caught: $label" \
                      || bad "sabotage NOT caught: $label" ;;
        once)     rm -rf "$WORK/s4"
                  run_hook "$stub" "$WORK/low.json" "$WORK/s4" >/dev/null
                  r="$(run_hook "$stub" "$WORK/low.json" "$WORK/s4")"; o="$(out_of "$r")"
                  case "$o" in *WARN*) ok "sabotage caught: $label" ;;
                      *) bad "sabotage NOT caught: $label" ;; esac ;;
    esac
}

# exits 0 below the threshold (the gate stops gating)
sabotage "gate exits 0 below the threshold" \
    's#\[ "\$PCT" -ge "\$THRESHOLD" \] && exit 0#exit 0#' below
# blocks when the quota is unknown (an unreadable source refusing the work)
sabotage "gate exits 2 when the quota source is absent" \
    's#\*\[!0-9\]\*) exit 0 ;;#*[!0-9]*) exit 2 ;;#' absent
# ignores the kill switch
sabotage "gate ignores GOALFORGE_LAUNCH_GATE=0" \
    's#\[ "\${GOALFORGE_LAUNCH_GATE:-1}" = "0" \] && exit 0#:#' disabled
# WARNs on every run
sabotage "gate re-prints the WARN every run" \
    's#^if \[ ! -f "\$MARKER" \]; then#if true; then#' once

# ── the hook's own self-test ───────────────────────────────────────────────
rc=0; bash "$HOOK" --self-test >"$WORK/selftest.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "--self-test passes (exit 0)" \
    || bad "--self-test exit $rc; $(cat "$WORK/selftest.out")"

# ── the adapter's own self-test (b1's quota source seam) ───────────────────
rc=0; bash "$HD/goalforge-quota-read.sh" --self-test >"$WORK/quota.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "goalforge-quota-read.sh --self-test passes" \
    || bad "quota adapter self-test exit $rc; $(cat "$WORK/quota.out")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
