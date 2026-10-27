#!/usr/bin/env bash
# goalforge-plans-root.test.sh — sabotage pair for the SOURCED helper
# goalforge-plans-root.sh, focused on goalforge_emit_gate_result /
# goalforge_wp_for (T22: gate.result now carries wp/gate/result/reason, wp
# derived from the plan file path — the fix this test pins). Fixtures live
# under packages/goalforge/evals/fixtures/hooks/goalforge-plans-root/ — never
# inline here. Hermetic: everything happens in a mktemp dir; nothing is ever
# written into a real plans/ tree.
#
# DEVIATION FROM THE LITERAL ticket-74 exit-2/exit-0 PAIR SHAPE: this file is
# a sourced bash library, not a standalone hook invoked by the tool harness —
# it is documented ZERO-BREAKAGE ("no function here exits, blocks, or writes
# outside stdout"), so it never has an exit-2 path of its own to sabotage-test.
# The pair here instead tests goalforge_emit_gate_result's ONE observable
# effect — did a schema-valid gate.result row land in trace-events.jsonl —
# against a case that SHOULD emit (a file resolved under a plans root, inside
# a WP dir) and one that SHOULD NOT (a file outside every plans root, where
# emission must degrade to a silent no-op rather than erroring).
set -uo pipefail

HD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$HD/goalforge-plans-root.sh"
FIX="$HD/../evals/fixtures/hooks/goalforge-plans-root"
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# shellcheck disable=SC1090
. "$HELPER"
HOOK_DIR="$HD"   # goalforge_emit_gate_result locates goalforge-trace-emit via $HOOK_DIR

# ── known-good: file inside a WP dir under a resolved plans root -> row emitted,
#    wp derived as the WP dir basename, schema-valid ────────────────────────
good_root="$WORK/good/plans"
mkdir -p "$good_root/feat/wp-03"
good_file="$good_root/feat/wp-03/overview.md"
cp "$FIX/wp-overview.md" "$good_file"

SDD_PLANS_DIR="$good_root" goalforge_emit_gate_result "plans-root-test" "pass" "smoke" "$good_file"
trace="$good_root/feat/trace-events.jsonl"
if [ -f "$trace" ] && command jq -e \
    'select(.type=="gate.result" and .gate=="plans-root-test" and .result=="pass" and .wp=="wp-03" and .reason=="smoke")' \
    "$trace" >/dev/null 2>&1; then
    ok "known-good (WP-scoped file) -> gate.result{wp:wp-03} emitted, schema-valid"
else
    bad "known-good -> row missing/malformed ($(cat "$trace" 2>/dev/null))"
fi

# ── known-good, feature-level: file directly in the feature dir -> wp is the
#    feature slug (mirrors goalforge-transition.sh's FEATURE_DIR basename) ──
featlvl_root="$WORK/featlvl/plans"
mkdir -p "$featlvl_root/feat2"
featlvl_file="$featlvl_root/feat2/overview.md"
cp "$FIX/wp-overview.md" "$featlvl_file"
SDD_PLANS_DIR="$featlvl_root" goalforge_emit_gate_result "plans-root-test" "fail" "smoke2" "$featlvl_file"
trace2="$featlvl_root/feat2/trace-events.jsonl"
if [ -f "$trace2" ] && command jq -e \
    'select(.type=="gate.result" and .result=="fail" and .wp=="feat2")' \
    "$trace2" >/dev/null 2>&1; then
    ok "known-good (feature-level file) -> gate.result{wp:feat2} emitted, schema-valid"
else
    bad "known-good (feature-level) -> row missing/malformed ($(cat "$trace2" 2>/dev/null))"
fi

# ── known-bad: file outside every plans root -> no feature dir resolvable ->
#    degrade-not-block: function returns 0, no trace file created anywhere ──
outside_dir="$WORK/outside"
mkdir -p "$outside_dir"
outside_file="$outside_dir/overview.md"
cp "$FIX/wp-overview.md" "$outside_file"
rc=0
( SDD_PLANS_DIR="$WORK/good/plans" goalforge_emit_gate_result "plans-root-test" "fail" "smoke3" "$outside_file" ) || rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$outside_dir/trace-events.jsonl" ]; then
    ok "known-bad (file outside every plans root) -> no-op, no trace file, no error"
else
    bad "known-bad (outside plans root) -> unexpected rc=$rc or stray trace file"
fi

# ── sabotage: jq masked off PATH -> gate.result row still written via python3
jqmask_root="$WORK/jqmask/plans"
mkdir -p "$jqmask_root/feat3/wp-05"
jqmask_file="$jqmask_root/feat3/wp-05/overview.md"
cp "$FIX/wp-overview.md" "$jqmask_file"
JQ_STUB_DIR="$(mktemp -d)"
cat > "$JQ_STUB_DIR/jq" <<'EOF'
#!/usr/bin/env bash
echo "jq: masked for test" >&2
exit 127
EOF
chmod +x "$JQ_STUB_DIR/jq"
( PATH="$JQ_STUB_DIR:$PATH" SDD_PLANS_DIR="$jqmask_root" goalforge_emit_gate_result "plans-root-test" "pass" "smoke4" "$jqmask_file" )
trace4="$jqmask_root/feat3/trace-events.jsonl"
if [ -f "$trace4" ] && grep -q '"gate":"plans-root-test"' "$trace4" 2>/dev/null && grep -q '"wp":"wp-05"' "$trace4" 2>/dev/null; then
    ok "jq masked off PATH -> gate.result row still written (python3, no jq dependency)"
else
    bad "jq masked off PATH -> gate.result row still written ($(cat "$trace4" 2>/dev/null))"
fi
rm -rf "$JQ_STUB_DIR"

# ── regression: an early-returning root lookup must not EPIPE its producer.
#    A match on the FIRST root ($SDD_PLANS_DIR) returns before the producer has
#    printed the $HOME leg. Streamed through `< <(...)`, that last printf hits a
#    closed pipe; with SIGPIPE inherited as ignored (as on the CI runner) bash
#    prints "printf: write error: Broken pipe" instead of dying silently. The
#    child bash inherits SIG_IGN from `trap '' PIPE` and cannot un-ignore it, so
#    this reproduces the CI condition on any machine.
epipe_root="$WORK/epipe/plans"
mkdir -p "$epipe_root/feat4/wp-01"
epipe_file="$epipe_root/feat4/wp-01/overview.md"
epipe_err="$( (trap '' PIPE; HOME="$WORK/epipe-home" SDD_PLANS_DIR="$epipe_root" bash -c '
    . "$1" || exit 9
    goalforge_under_plans_root "$2" || exit 3
    goalforge_feature_dir_for "$2" >/dev/null || exit 4
' _ "$HELPER" "$epipe_file") 2>&1 >/dev/null)"; epipe_rc=$?
if [ "$epipe_rc" -eq 0 ] && [ -z "$epipe_err" ]; then
    ok "SIGPIPE ignored + first-root match -> resolves, stderr empty (no EPIPE)"
else
    bad "SIGPIPE ignored + first-root match -> rc=$epipe_rc stderr='$epipe_err'"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
