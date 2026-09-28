#!/usr/bin/env bash
# goalforge-preharden-lint.test.sh — sabotage pairs for V5 (WP-altitude
# command-shape lint + section-lint call, ticket-73/spec C3 G2) added on top
# of goalforge-preharden-lint.sh's existing P1/V1-V4 family. Fixtures live
# under packages/goalforge/evals/fixtures/preharden-lint/ — never inline.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SD/../goalforge-preharden-lint.sh"
# The lint writes a gate.result row into <feature-dir>/trace-events.jsonl, so it
# must never run against the checked-in fixture tree (evals/run.sh asserts the
# fixture sha256 manifest is unchanged). Copy to a temp dir and run there.
FIX_SRC="$SD/../../evals/fixtures/preharden-lint"
FIX_TMP_ROOT="$(mktemp -d)"
FIX="$FIX_TMP_ROOT/preharden-lint"
mkdir -p "$FIX"
cp -R "$FIX_SRC/." "$FIX/"
# Clean up the temp root by its own name — never a path derived from $FIX, so a
# later edit to FIX can never turn this into an rm -rf of the fixture tree.
trap 'rm -rf "$FIX_TMP_ROOT"' EXIT
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# ── known-good: schema-6, command-shaped, exact C1 sections -> exit 0 ───────
OUT="$(bash "$LINT" "$FIX/good-wp" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    ok "good-wp (schema-6, command-shaped, C1 sections) -> exit 0"
else
    bad "good-wp -> exit 0 (rc=$rc)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

# ── known-bad: schema-6, prose verification.command -> exit 2 ───────────────
OUT="$(bash "$LINT" "$FIX/bad-command-wp" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$OUT" | grep -qi 'V5'; then
    ok "bad-command-wp (prose command) -> exit 2, V5 finding"
else
    bad "bad-command-wp -> exit 2, V5 finding (rc=$rc)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

# ── known-bad: schema-6, command-shaped, extra H2 section -> exit 2 ─────────
OUT="$(bash "$LINT" "$FIX/extra-section-wp" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then
    ok "extra-section-wp -> exit 2 (section-lint call surfaces through V5)"
else
    bad "extra-section-wp -> exit 2 (rc=$rc)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

# ── schema-5 baseline: prose check: -> WARN only, never ERROR (exit != 2) ───
OUT="$(bash "$LINT" "$FIX/schema5-baseline-wp" 2>&1)"; rc=$?
if [ "$rc" -ne 2 ]; then
    ok "schema5-baseline-wp -> ratchet WARN, never ERROR (rc=$rc, not 2)"
else
    bad "schema5-baseline-wp -> ratchet WARN, never ERROR (rc=$rc)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

# ── known-bad: schema-6 behavior pinned to a live corpus root ──────────────
# b2's wording is taken from the wp-02-agent-roster expertise-map behavior that
# shipped red on a fresh clone: it resolves against ${CLAUDE_CONFIG_DIR:-$HOME/.claude}
# and names no shipped fixture root.
OUT="$(bash "$LINT" "$FIX/v6-live-root-wp" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] \
   && printf '%s' "$OUT" | grep -q 'WARN \[V6\] v6-live-root-wp: b2: oracle resolves against a live corpus root with no shipped fixture root'; then
    ok "v6-live-root-wp -> WARN V6 (heuristic, never ERROR)"
else
    bad "v6-live-root-wp -> WARN V6 (rc=$rc)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

# ── known-good: the SAME live-root literal, but a shipped fixture root is named.
# Exercises the exemption conjunct: deleting `&& ! grep fixture-tokens` from the
# lint must turn this case red.
OUT="$(bash "$LINT" "$FIX/v6-live-root-exempt-wp" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$OUT" | grep -q '\[V6\]'; then
    ok "v6-live-root-exempt-wp -> no V6 line (fixture-root exemption applies)"
else
    bad "v6-live-root-exempt-wp -> no V6 line (rc=$rc)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

# ── good-wp emits no V6 line (behaviors[] empty -> skipped silently) ───────
OUT="$(bash "$LINT" "$FIX/good-wp" 2>&1)"
if ! printf '%s' "$OUT" | grep -q '\[V6\]'; then
    ok "good-wp emits no V6 line"
else
    bad "good-wp emits no V6 line"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

# ── existing P1/V1-V4 self-test must stay green (non-regression) ────────────
if bash "$LINT" --self-test >/tmp/phl-selftest.out 2>&1; then
    ok "existing --self-test (P1/V1-V4) stays green"
else
    bad "existing --self-test (P1/V1-V4) stays green"
    sed 's/^/        /' /tmp/phl-selftest.out
fi

# ── V7/V8 + V2 git whitelist (wp-11 b2) ─────────────────────────────────────
# These WP fixtures are written here, one condition per known-bad, into a temp
# git repo (V7 resolves revisions against the WP's own repository). The
# evals/fixtures/preharden-lint/ tree is outside wp-11's owned files.
W="$FIX_TMP_ROOT/v78"
mkdir -p "$W"
mkwp() {  # $1 name, $2 goal.constraints flow list ('' = none), $3 task verify body ('' = no task)
    mkdir -p "$W/$1"
    {
        printf -- '---\nname: %s\nstatus: spec\nsha: 0123abc\ngoal:\n  outcome: "fixture"\n' "$1"
        printf '  verification:\n    strategy: deterministic\n    command: "bash run.sh"\n'
        [ -z "$2" ] || printf '  constraints: %s\n' "$2"
        printf -- '---\n\n## Goal\n\nfixture T1\n'
    } >"$W/$1/overview.md"
    [ -z "$3" ] || printf -- '---\nname: task-01-a\nverify: |\n  %s\n---\nbody\n' "$3" >"$W/$1/task-01-a.md"
}
mkwp v7-failing-gate   '' "test -f no-such-file.txt"
mkwp v7-bad-revision   '' "git rev-parse --verify deadbeefdeadbeefdeadbeef^{commit}"
mkwp v8-placeholder    '["baseline pinned at <base_sha>"]' ''
mkwp v8-missing-artifact '["the contract in `docs/no-such-contract.md` stays unchanged"]' ''
mkwp v2-git-external   '["baseline pinned at <sha>, contract `overview.md`"]' \
    "grep -q T1 overview.md
  git rev-parse --verify --quiet HEAD"
git -C "$W" init -q && git -C "$W" add -A \
    && git -C "$W" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm fixture \
    || bad "v78 fixture repo could not be committed"

v78() {  # $1 lint, $2 wp, $3 want rc, $4 want check id ('' = no finding)
    local out rc
    out="$(bash "$1" "$W/$2" 2>&1)"; rc=$?
    [ "$rc" -eq "$3" ] || { echo "rc=$rc want $3: $out"; return 1; }
    if [ -n "$4" ]; then
        printf '%s' "$out" | grep -q "ERROR \[$4\] $2" || { echo "no [$4] line: $out"; return 1; }
    else
        ! printf '%s' "$out" | grep -qE '^(WARN|ERROR) ' || { echo "unexpected finding: $out"; return 1; }
    fi
}
for c in "v7-failing-gate 2 V7" "v7-bad-revision 2 V7" "v8-placeholder 2 V8" "v8-missing-artifact 2 V8" "v2-git-external 0 -"; do
    set -- $c; id="$3"; [ "$id" = - ] && id=""
    if r="$(v78 "$LINT" "$1" "$2" "$id")"; then ok "$1 -> exit $2${id:+, $id finding}"
    else bad "$1 -> exit $2${id:+, $id finding}"; printf '%s\n' "$r" | sed 's/^/        /'; fi
done
OUT="$(bash "$LINT" "$W/v7-bad-revision" 2>&1)"
if printf '%s' "$OUT" | grep -q 'ERROR \[V7\] v7-bad-revision: .*unresolvable revision'; then
    ok "v7-bad-revision names the unresolvable revision"
else bad "v7-bad-revision names the unresolvable revision"; fi
for c in V7 V8; do
    grep -q "^#   $c " "$LINT" && ok "script header names $c in its check list" || bad "script header names $c"
done
grep -qE '^# Exit: .*' "$LINT" && sed -n '/^# Exit:/,/^# Offline/p' "$LINT" | grep -q 'V7' \
    && sed -n '/^# Exit:/,/^# Offline/p' "$LINT" | grep -q 'V8' \
    && ok "exit-code contract names V7 and V8" || bad "exit-code contract names V7 and V8"
# A judge/human strategy exempts V7 (OQ4): the failing gate under strategy judge.
cp -R "$W/v7-failing-gate" "$W/v7-judge-exempt"
sed -i 's/strategy: deterministic/strategy: judge/' "$W/v7-judge-exempt/overview.md"
if r="$(v78 "$LINT" v7-judge-exempt 0 "")"; then ok "v7-judge-exempt (strategy: judge) -> V7 not run, exit 0"
else bad "v7-judge-exempt -> exit 0"; printf '%s\n' "$r" | sed 's/^/        /'; fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
