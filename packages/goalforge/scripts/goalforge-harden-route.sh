#!/usr/bin/env bash
# goalforge-harden-route.sh — route a WP's pre-harden review by complexity.
#
# Usage:
#   goalforge-harden-route.sh <wp-path>
#   goalforge-harden-route.sh --self-test
#
# Args:
#   <wp-path>  Work-package directory (overview.md + task-*.md), inside a feature dir.
#
# Behavior:
#   Delegates classification to goalforge-wp-complexity.sh <wp-path> and maps its verdict
#   to the pre-harden review route (sdd-harden/SKILL.md Step 0a):
#     complex -> "panel"        convene skills/adjudication/panel + dissent ledger
#     simple  -> "single-pass"  the standing single read-only review sub-agent
#
# Output:
#   Single-line JSON:
#   {"route":"panel"|"single-pass","verdict":"complex"|"simple","tripped":["S1",...]}
#
#   `tripped` is carried through so the caller can record WHY a WP took the panel
#   route (which signals fired) in findings.md, without re-classifying.
#
#   Exit 0 on success. Exit 1 on errors (stderr).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
COMPLEXITY="$SCRIPT_DIR/goalforge-wp-complexity.sh"

usage() {
    sed -n '2,25p' "$SELF" | sed 's/^# \{0,1\}//'
}

# ── Route WP ──────────────────────────────────────────────────────────────────
route_wp() {
    local wp="$1"
    [[ -f "$COMPLEXITY" ]] \
        || { echo "ERROR: goalforge-wp-complexity.sh not found at $COMPLEXITY" >&2; exit 1; }
    local cj
    cj="$(bash "$COMPLEXITY" "$wp")" \
        || { echo "ERROR: goalforge-wp-complexity.sh failed for $wp" >&2; exit 1; }
    COMPLEXITY_JSON="$cj" python3 - <<'PY'
import json, os, sys
try:
    data = json.loads(os.environ["COMPLEXITY_JSON"])
except Exception as e:
    sys.stderr.write("ERROR: cannot parse complexity JSON: %s\n" % e); sys.exit(1)
verdict = data.get("verdict")
if verdict not in ("complex", "simple"):
    sys.stderr.write("ERROR: unexpected complexity verdict: %r\n" % verdict); sys.exit(1)
route = "panel" if verdict == "complex" else "single-pass"
print(json.dumps({
    "route": route,
    "verdict": verdict,
    "tripped": data.get("tripped", []),
}))
PY
}

# ── Self-test ─────────────────────────────────────────────────────────────────
_ST_TMP=""
self_test() {
    local t_pass=0 t_fail=0 d

    _ST_TMP="$(mktemp -d)"
    trap '[[ -n "${_ST_TMP:-}" ]] && rm -rf "$_ST_TMP"' EXIT
    d="$_ST_TMP"

    local ok no
    ok() { echo "$1: PASS"; t_pass=$((t_pass+1)); }
    no() { echo "$1: FAIL — $2"; t_fail=$((t_fail+1)); }

    echo "=== goalforge-harden-route.sh --self-test ==="

    # ── complex fixture → panel (S1 severity HIGH) ────────────────────────────
    # Fixtures mirror the REAL WP frontmatter shape (severity top-level, sibling
    # to name/status) — a wrong-shape fixture would validate a structure the
    # classifier does not read (the task-01 self-test-vs-real-schema lesson).
    mkdir -p "$d/feat-c/wp-01-complex"
    cat > "$d/feat-c/wp-01-complex/overview.md" << 'EOF'
---
name: wp-01-complex
status: spec
severity: HIGH
boundaries: []
---
EOF
    local rc route_c verdict_c
    rc="$(bash "$SELF" "$d/feat-c/wp-01-complex")"
    route_c="$(echo "$rc"   | command jq -r '.route')"
    verdict_c="$(echo "$rc" | command jq -r '.verdict')"
    if [[ "$route_c" == "panel" && "$verdict_c" == "complex" ]]; then
        ok "complex-routes-to-panel"
    else
        no "complex-routes-to-panel" "route=$route_c verdict=$verdict_c"
    fi

    # ── simple fixture → single-pass (no signal trips) ────────────────────────
    mkdir -p "$d/feat-s/wp-01-simple"
    cat > "$d/feat-s/wp-01-simple/overview.md" << 'EOF'
---
name: wp-01-simple
status: spec
severity: LOW
boundaries: []
---
EOF
    cat > "$d/feat-s/wp-01-simple/task-01-s.md" << 'EOF'
---
complexity: low
depends_on: []
---
EOF
    local rs route_s verdict_s
    rs="$(bash "$SELF" "$d/feat-s/wp-01-simple")"
    route_s="$(echo "$rs"   | command jq -r '.route')"
    verdict_s="$(echo "$rs" | command jq -r '.verdict')"
    if [[ "$route_s" == "single-pass" && "$verdict_s" == "simple" ]]; then
        ok "simple-routes-to-single-pass"
    else
        no "simple-routes-to-single-pass" "route=$route_s verdict=$verdict_s"
    fi

    echo ""
    echo "Results: $t_pass passed, $t_fail failed"
    [[ "$t_fail" -eq 0 ]]
}

# ── Argument parsing ──────────────────────────────────────────────────────────
SELFTEST=0
POS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-test) SELFTEST=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        --*)         echo "ERROR: unknown flag: $1" >&2; exit 1 ;;
        *)           POS+=("$1"); shift ;;
    esac
done

if [[ "$SELFTEST" -eq 1 ]]; then
    self_test
    exit $?
fi

if [[ "${#POS[@]}" -lt 1 ]]; then
    echo "ERROR: usage: goalforge-harden-route.sh <wp-path>" >&2
    exit 1
fi

WP_PATH="$(cd "${POS[0]}" 2>/dev/null && pwd)" \
    || { echo "ERROR: wp-path not found: ${POS[0]}" >&2; exit 1; }

route_wp "$WP_PATH"
