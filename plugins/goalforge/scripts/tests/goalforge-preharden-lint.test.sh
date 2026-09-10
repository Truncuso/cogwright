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

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
