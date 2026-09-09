#!/usr/bin/env bash
# goalforge-section-lint.test.sh — sabotage pair for goalforge-section-lint.sh
# (ticket-74 shape: known-bad exits 2, known-good exits 0). Fixtures live under
# packages/goalforge/evals/fixtures/section-lint/ — never inline here.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SD/../goalforge-section-lint.sh"
FIX="$SD/../../evals/fixtures/section-lint"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# ── known-good: exact C1 8-section shape -> exit 0 ──────────────────────────
bash "$LINT" "$FIX/good-overview.md" >/tmp/sl-good.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    ok "known-good overview -> exit 0"
else
    bad "known-good overview -> exit $rc (want 0)"
    sed 's/^/        /' /tmp/sl-good.out
fi

# ── known-bad: extra '## Notes' section -> exit 2, reason on stderr ─────────
OUT="$(bash "$LINT" "$FIX/bad-extra-section.md" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$OUT" | grep -qi 'notes'; then
    ok "extra-section fixture -> exit 2 naming the offending section"
else
    bad "extra-section fixture -> exit 2 naming the offending section (rc=$rc)"
    printf '%s' "$OUT" | sed 's/^/        /'
fi

# ── missing-section fixture (no '## Goal Changelog') -> exit 2 ──────────────
OUT="$(bash "$LINT" "$FIX/bad-missing-section.md" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then
    ok "missing-section fixture -> exit 2"
else
    bad "missing-section fixture -> exit 2 (rc=$rc)"
    printf '%s' "$OUT" | sed 's/^/        /'
fi

# ── zero-H2 fixture -> exit 2, reason names the missing C1 sections ─────────
OUT="$(bash "$LINT" "$FIX/bad-zero-sections.md" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$OUT" | grep -qi 'missing C1 H2 section' && ! printf '%s' "$OUT" | grep -qi 'disallowed H2 section(s): $'; then
    ok "zero-H2 fixture -> exit 2, reports missing sections (not empty disallowed list)"
else
    bad "zero-H2 fixture -> exit 2, reports missing sections (rc=$rc)"
    printf '%s' "$OUT" | sed 's/^/        /'
fi

# ── sabotage: jq masked off PATH -> gate.result still written via python3 ───
JQ_STUB_DIR="$(mktemp -d)"
cat > "$JQ_STUB_DIR/jq" <<'EOF'
#!/usr/bin/env bash
echo "jq: masked for test" >&2
exit 127
EOF
chmod +x "$JQ_STUB_DIR/jq"
FEAT_DIR="$(mktemp -d)"
mkdir -p "$FEAT_DIR/wp-jq-mask"
cp "$FIX/good-overview.md" "$FEAT_DIR/wp-jq-mask/overview.md"
PATH="$JQ_STUB_DIR:$PATH" bash "$LINT" "$FEAT_DIR/wp-jq-mask/overview.md" >/tmp/sl-jqmask.out 2>&1
rc=$?
TRACE="$FEAT_DIR/trace-events.jsonl"
if [ "$rc" -eq 0 ] && [ -f "$TRACE" ] && grep -q '"gate":"section-lint"' "$TRACE" 2>/dev/null; then
    ok "jq masked off PATH -> gate.result row still written (python3, no jq dependency)"
else
    bad "jq masked off PATH -> gate.result row still written (rc=$rc, trace=$TRACE)"
    [ -f "$TRACE" ] && sed 's/^/        /' "$TRACE"
    cat /tmp/sl-jqmask.out | sed 's/^/        /'
fi
rm -rf "$JQ_STUB_DIR" "$FEAT_DIR"

# ── internal error: nonexistent file -> exit 2, never a silent pass ─────────
bash "$LINT" "$FIX/does-not-exist.md" >/dev/null 2>/tmp/sl-missing.err
rc=$?
if [ "$rc" -eq 2 ]; then
    ok "nonexistent overview -> exit 2 (fail closed)"
else
    bad "nonexistent overview -> exit 2 (fail closed) (rc=$rc)"
fi

# ── usage error: no argument -> exit 2 ───────────────────────────────────────
bash "$LINT" >/dev/null 2>/dev/null
rc=$?
if [ "$rc" -eq 2 ]; then
    ok "no argument -> exit 2 (usage error)"
else
    bad "no argument -> exit 2 (usage error) (rc=$rc)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
