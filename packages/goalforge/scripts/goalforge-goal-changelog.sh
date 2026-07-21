#!/usr/bin/env bash
# sdd-goal-changelog.sh — the single mechanism for logging a goal change.
#
# Usage:
#   sdd-goal-changelog.sh append <wp-path> <facet> <old> <new> --reason "<text>"
#   sdd-goal-changelog.sh --self-test
#
# Appends one versioned row to the `## Goal Changelog` section of
# `<wp-path>/overview.md`, using the task-01 row schema:
#   - v<N> <date> facet=<facet> <old>→<new>; reason: <text>
# `<N>` is monotonic (highest existing v<N> + 1; first row = v1). `<date>` is
# today in UTC (YYYY-MM-DD). `<facet>` ∈
#   outcome | verification | constraints | boundaries | iteration_policy | blocked_stop
#
# Guarantees:
#   1. Append-only — prior rows are never rewritten or deleted.
#   2. Idempotent  — if the LATEST row already records the identical
#      (facet, old, new) change, the append is a no-op (no duplicate row, no
#      version bump).
# The write is atomic (mktemp → os.replace).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

FACETS=(outcome verification constraints boundaries iteration_policy blocked_stop)

usage() {
    sed -n '2,12p' "$SELF" | sed 's/^# \{0,1\}//'
}

# ── Resolve a WP path (dir or overview.md) to its overview.md ────────────────
resolve_overview() {
    local WP_PATH="$1" OVERVIEW
    if [[ -d "$WP_PATH" ]]; then
        OVERVIEW="$(cd "$WP_PATH" && pwd)/overview.md"
    elif [[ -f "$WP_PATH" ]]; then
        OVERVIEW="$(cd "$(dirname "$WP_PATH")" && pwd)/$(basename "$WP_PATH")"
    else
        echo "ERROR: wp-path not found: $WP_PATH" >&2; return 1
    fi
    [[ -f "$OVERVIEW" ]] || { echo "ERROR: overview.md not found: $OVERVIEW" >&2; return 1; }
    printf '%s\n' "$OVERVIEW"
}

# ── The append: monotonic version + idempotency + atomic rewrite ─────────────
do_append() {
    # args: overview facet old new reason today
    python3 - "$@" <<'PY'
import sys, re, os, tempfile
overview, facet, old, new, reason, today = sys.argv[1:7]

text = open(overview, encoding="utf-8").read()
lines = text.split("\n")

# Locate the "## Goal Changelog" section.
hdr = None
for i, ln in enumerate(lines):
    if re.match(r"^##\s+Goal Changelog\s*$", ln):
        hdr = i; break
if hdr is None:
    sys.stderr.write("ERROR: no '## Goal Changelog' section in %s\n" % overview)
    sys.exit(1)

# The section runs from hdr+1 to the next "## " heading (or EOF).
sec_end = len(lines)
for i in range(hdr + 1, len(lines)):
    if re.match(r"^##\s+\S", lines[i]):
        sec_end = i; break

# Parse existing rows in file order.
row_re = re.compile(
    r"^-\s+v(\d+)\s+\d{4}-\d{2}-\d{2}\s+facet=(\S+)\s+(.*?)→(.*?);\s+reason:\s*(.*)$"
)
rows = []           # (version:int, facet, old, new)
last_content = hdr  # last non-blank line index in the section
for i in range(hdr + 1, sec_end):
    if lines[i].strip() != "":
        last_content = i
    m = row_re.match(lines[i].rstrip())
    if m:
        rows.append((int(m.group(1)), m.group(2), m.group(3), m.group(4)))

# Idempotency: identical to the LATEST recorded change ⇒ no-op.
if rows:
    lver, lfacet, lold, lnew = rows[-1]
    if (lfacet, lold, lnew) == (facet, old, new):
        print("noop: identical to latest row (v%d)" % lver)
        sys.exit(0)

nextv = max((r[0] for r in rows), default=0) + 1
new_row = "- v%d %s facet=%s %s→%s; reason: %s" % (
    nextv, today, facet, old, new, reason)

# Append-only: insert after the last non-blank line of the section.
lines.insert(last_content + 1, new_row)
out = "\n".join(lines)

d = os.path.dirname(os.path.abspath(overview))
fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(out)
    os.replace(tmp, overview)
except Exception:
    try: os.unlink(tmp)
    except OSError: pass
    raise

print("append: v%d facet=%s %s→%s" % (nextv, facet, old, new))
PY
}

# ── The `append` command ─────────────────────────────────────────────────────
append() {
    local WP_PATH="$1" FACET="$2" OLD="$3" NEW="$4"
    local OVERVIEW TODAY ok=0

    for f in "${FACETS[@]}"; do [[ "$f" == "$FACET" ]] && ok=1; done
    if [[ "$ok" -ne 1 ]]; then
        echo "ERROR: invalid facet '$FACET' (expected: ${FACETS[*]})" >&2; return 1
    fi
    if [[ -z "$REASON" ]]; then
        echo "ERROR: --reason is required" >&2; return 1
    fi

    OVERVIEW="$(resolve_overview "$WP_PATH")"
    TODAY="$(date -u +%F)"
    do_append "$OVERVIEW" "$FACET" "$OLD" "$NEW" "$REASON" "$TODAY"
}

# ── Self-test ────────────────────────────────────────────────────────────────
_ST_TMP=""
self_test() {
    local wp t_pass=0 t_fail=0
    _ST_TMP="$(mktemp -d)"
    trap '[[ -n "${_ST_TMP:-}" ]] && rm -rf "$_ST_TMP"' EXIT
    wp="$_ST_TMP/wp-01-x"
    mkdir -p "$wp"

    cat > "$wp/overview.md" <<'EOF'
---
name: wp-01-x
title: Self-test WP
status: ready
stage_updated: 2026-06-23
severity: LOW
parallel: false
depends_on: []
plan: tmpfeat
goal_approved_version: null
---

# self-test wp

## Goal Changelog

<!-- Append-only. Each row: - v<N> <date> facet=<facet> <old>→<new>; reason: <text> -->
EOF

    local ok no
    ok() { echo "$1: PASS"; t_pass=$((t_pass+1)); }
    no() { echo "$1: FAIL"; t_fail=$((t_fail+1)); }

    echo "=== sdd-goal-changelog.sh --self-test ==="

    # (a) first append creates v1
    bash "$SELF" append "$wp" outcome "old-A" "new-B" --reason "r1" >/dev/null 2>&1 || true
    if grep -Eq '^- v1 [0-9]{4}-[0-9]{2}-[0-9]{2} facet=outcome old-A→new-B; reason: r1$' "$wp/overview.md"; then
        ok "first-append"
    else
        no "first-append"
    fi

    # (b) a second different append increments to v2
    bash "$SELF" append "$wp" verification "old-X" "new-Y" --reason "r2" >/dev/null 2>&1 || true
    if grep -Eq '^- v2 [0-9]{4}-[0-9]{2}-[0-9]{2} facet=verification old-X→new-Y; reason: r2$' "$wp/overview.md"; then
        ok "second-append-increments"
    else
        no "second-append-increments"
    fi

    # (c) re-appending an identical change is a no-op (no v3, still 2 rows)
    bash "$SELF" append "$wp" verification "old-X" "new-Y" --reason "r2-again" >/dev/null 2>&1 || true
    local n_rows n_v3
    n_rows="$(grep -Ec '^- v[0-9]+ ' "$wp/overview.md" || true)"
    n_v3="$(grep -Ec '^- v3 ' "$wp/overview.md" || true)"
    if [[ "$n_rows" -eq 2 && "$n_v3" -eq 0 ]]; then
        ok "idempotent-reappend-noop"
    else
        no "idempotent-reappend-noop"
    fi

    echo ""
    echo "Results: $t_pass passed, $t_fail failed"
    [[ "$t_fail" -eq 0 ]]
}

# ── Argument parsing ─────────────────────────────────────────────────────────
REASON=""
SELFTEST=0
POS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-test) SELFTEST=1; shift ;;
        --reason)    REASON="${2:-}"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        --*)         echo "ERROR: unknown flag: $1" >&2; exit 1 ;;
        *)           POS+=("$1"); shift ;;
    esac
done

if [[ "$SELFTEST" -eq 1 ]]; then
    self_test
    exit $?
fi

if [[ "${#POS[@]}" -lt 1 || "${POS[0]}" != "append" ]]; then
    echo "ERROR: usage: sdd-goal-changelog.sh append <wp-path> <facet> <old> <new> --reason \"<text>\"" >&2
    exit 1
fi
if [[ "${#POS[@]}" -lt 5 ]]; then
    echo "ERROR: append needs <wp-path> <facet> <old> <new> --reason \"<text>\"" >&2
    exit 1
fi

append "${POS[1]}" "${POS[2]}" "${POS[3]}" "${POS[4]}"
