#!/usr/bin/env bash
# evals/trace-substrate/cases/transition-wiring.sh — task-03 hermetic case.
#
# Proves goalforge-transition.sh emits typed trace events through the validating
# emitter, OUTSIDE its flock-9 critical section, without changing transition
# behavior. Self-contained: builds a scratch plans tree, drives one WP-level and
# one feature-level transition, and asserts:
#   - a wp.status_changed row appears (WP target) and validates against the schema
#   - a feature.status_changed row appears (feature target) and validates
#   - a commit.linked row appears when a commit hash is recorded
#   - each emitted row validates against the JSON Schema embedded in
#     references/trace-events.md
#   - ZERO-BREAKAGE: with the emitter pointed at an absent path, the transition
#     still exits 0 and mutates status (an emit failure never blocks the chain)
#
# Standalone — the unit's run.sh (task-05) aggregates cases; this does NOT depend
# on it. Exit 0 = pass, non-zero = fail.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../../../scripts" && pwd)"
TRANSITION="$SCRIPTS/goalforge-transition.sh"
EMIT="$SCRIPTS/goalforge-trace-emit"

t_pass=0; t_fail=0
ok() { echo "  PASS: $1"; t_pass=$((t_pass+1)); }
no() { echo "  FAIL: $1"; t_fail=$((t_fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PLANS="$TMP/plans"
FEAT="$PLANS/tfeat"
WP="$FEAT/wp-01-x"
mkdir -p "$WP"

cat > "$FEAT/overview.md" <<'EOF'
---
name: tfeat
title: trace-wiring fixture feature
status: executing
created: 2026-07-19
feature: tfeat
work_packages: [wp-01-x]
---

# fixture feature
EOF

cat > "$WP/overview.md" <<'EOF'
---
name: wp-01-x
title: trace-wiring WP
status: spec
stage_updated: 2026-07-19
severity: LOW
parallel: false
depends_on: []
plan: tfeat
---

# fixture wp
EOF

cat > "$WP/task-01-x.md" <<'EOF'
---
name: task-01-x
title: noop
status: pending
verify: "true"
---

# noop
EOF

echo "=== transition-wiring case ==="

# Validate a JSONL log against the embedded schema (reusing the emitter's own
# validator + schema loader) and require >=1 row of the requested type.
# Args: <log> <type> → exit 0 iff >=1 row of <type> present AND every row valid.
_check_type() {
    python3 - "$EMIT" "$1" "$2" <<'PY'
import sys, json
from importlib.machinery import SourceFileLoader
emit_path, log_path, want = sys.argv[1], sys.argv[2], sys.argv[3]
mod = SourceFileLoader("emit", emit_path).load_module()
schema = mod.load_schema()
try:
    rows = [json.loads(ln) for ln in open(log_path, encoding="utf-8") if ln.strip()]
except FileNotFoundError:
    print("no log"); sys.exit(1)
bad = [r for r in rows if mod._validate(r, schema)]
if bad:
    print("invalid rows:", bad[:1]); sys.exit(1)
if not any(r.get("type") == want for r in rows):
    print("no row of type", want); sys.exit(1)
sys.exit(0)
PY
}

LOG="$FEAT/trace-events.jsonl"

# ── WP-level transition spec→hardened → wp.status_changed emitted + valid ──────
bash "$TRANSITION" "$WP" hardened --reason "fwd" >/dev/null 2>&1
if [[ -f "$LOG" ]] && _check_type "$LOG" wp.status_changed >/dev/null 2>&1; then
    ok "WP transition emits a schema-valid wp.status_changed row"
else
    no "WP transition should emit a schema-valid wp.status_changed row"
fi

# commit.linked appears when a commit hash is recorded. The scratch tree is not a
# git repo, so COMMIT resolves empty and NO commit.linked row is emitted — make it
# a real repo so a commit hash is recorded, then drive another WP transition.
git -C "$FEAT" init -q 2>/dev/null || true
git -C "$FEAT" add -A >/dev/null 2>&1 || true
git -C "$FEAT" -c user.email=e@x -c user.name=n commit -qm init >/dev/null 2>&1 || true
bash "$TRANSITION" "$WP" spec --reason "reopen" >/dev/null 2>&1
if _check_type "$LOG" commit.linked >/dev/null 2>&1; then
    ok "WP transition in a git repo emits a schema-valid commit.linked row"
else
    no "WP transition in a git repo should emit a commit.linked row"
fi

# ── FEATURE-level transition executing→completed → feature.status_changed ──────
bash "$TRANSITION" "$FEAT" completed --reason "done" >/dev/null 2>&1
if _check_type "$LOG" feature.status_changed >/dev/null 2>&1; then
    ok "feature transition emits a schema-valid feature.status_changed row"
else
    no "feature transition should emit a schema-valid feature.status_changed row"
fi

# ── ZERO-BREAKAGE: emitter pointed at an absent path → transition still exits 0 ─
ZB="$TMP/zb"; ZBF="$ZB/zfeat"; ZWP="$ZBF/wp-01-z"
mkdir -p "$ZWP"
cat > "$ZBF/overview.md" <<'EOF'
---
name: zfeat
title: zero-breakage fixture
status: executing
created: 2026-07-19
feature: zfeat
work_packages: [wp-01-z]
---
EOF
cat > "$ZWP/overview.md" <<'EOF'
---
name: wp-01-z
title: zero-breakage WP
status: spec
stage_updated: 2026-07-19
severity: LOW
parallel: false
depends_on: []
plan: zfeat
---
EOF
cat > "$ZWP/task-01-z.md" <<'EOF'
---
name: task-01-z
title: noop
status: pending
verify: "true"
---
EOF
set +e
GOALFORGE_TRACE_EMIT="$TMP/does-not-exist/goalforge-trace-emit" \
    bash "$TRANSITION" "$ZWP" hardened --reason "fwd" >/dev/null 2>&1
zb_rc=$?
set -e
zb_status="$(grep -m1 '^status:' "$ZWP/overview.md" | sed 's/status:[[:space:]]*//')"
if [[ "$zb_rc" -eq 0 && "$zb_status" == "hardened" ]]; then
    ok "zero-breakage: absent emitter → transition still exits 0 and mutates status"
else
    no "zero-breakage: transition should exit 0 + mutate status with an absent emitter (rc=$zb_rc status=$zb_status)"
fi

echo ""
echo "Results: $t_pass passed, $t_fail failed"
[[ "$t_fail" -eq 0 ]]
