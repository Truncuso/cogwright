#!/usr/bin/env bash
# goalforge-goal-hash.sh — the SINGLE hash authority for a WP goal block.
#
# Usage:
#   goalforge-goal-hash.sh <wp-path>            print sha256[:12] of the goal: block
#   goalforge-goal-hash.sh --record <wp-path>   compute it + write goal_approved_version:
#   goalforge-goal-hash.sh --self-test
#
# Goal block = the lines from the top-level `goal:` key up to (not including) the
# next top-level frontmatter key (`^[a-z_][a-z0-9_]*:`, no leading whitespace),
# within the `---` fence. Normalized before hashing: per-line TRAILING whitespace
# stripped, line endings normalized to `\n`; leading indentation is significant
# and preserved.
#
# This is the ONE place the goal-block hash is defined. goalforge-harden (--record) and
# goalforge-validate (recompute-and-compare) BOTH shell out to it — the hash is NEVER
# reimplemented elsewhere, so the record and recompute paths can never diverge.
#
# Exit: 0 success. 3 when <wp-path> has no goal: block (prints nothing to stdout).
#       1 on usage / IO error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

usage() {
    sed -n '2,17p' "$SELF" | sed 's/^# \{0,1\}//'
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

# ── Compute the goal-block hash (stdout = 12 hex chars; exit 3 = no block) ────
hash_block() {
    python3 - "$1" <<'PY'
import sys, re, hashlib
overview = sys.argv[1]
text = open(overview, encoding="utf-8").read()
text = text.replace("\r\n", "\n").replace("\r", "\n")   # normalize line endings
lines = text.split("\n")

if not lines or lines[0].strip() != "---":
    sys.exit(3)
end = None
for i in range(1, len(lines)):
    if lines[i].strip() == "---":
        end = i; break
if end is None:
    sys.exit(3)

# Top-level `goal:` key inside the fence.
start = None
for i in range(1, end):
    if re.match(r"^goal:", lines[i]):
        start = i; break
if start is None:
    sys.exit(3)

# The block runs to the next top-level key (no leading space) or the fence.
stop = end
for i in range(start + 1, end):
    if re.match(r"^[a-z_][a-z0-9_]*:", lines[i]):
        stop = i; break

# Normalize: strip per-line trailing whitespace; keep leading indentation.
block = "\n".join(ln.rstrip() for ln in lines[start:stop])
print(hashlib.sha256(block.encode("utf-8")).hexdigest()[:12])
PY
}

# ── --record: write the hash into goal_approved_version: (atomic) ────────────
record() {
    local OVERVIEW="$1" H rc
    set +e; H="$(hash_block "$OVERVIEW")"; rc=$?; set -e
    if [[ "$rc" -ne 0 ]]; then
        echo "ERROR: cannot --record: no goal: block in $OVERVIEW" >&2
        exit "$rc"
    fi
    python3 - "$OVERVIEW" "$H" <<'PY'
import sys, os, re, tempfile
overview, value = sys.argv[1], sys.argv[2]
text = open(overview, encoding="utf-8").read()
lines = text.split("\n")
if not lines or lines[0].strip() != "---":
    sys.stderr.write("ERROR: no frontmatter in %s\n" % overview); sys.exit(1)
end = None
for i in range(1, len(lines)):
    if lines[i].strip() == "---":
        end = i; break
if end is None:
    sys.stderr.write("ERROR: unterminated frontmatter in %s\n" % overview); sys.exit(1)

# Quote the value so an all-digit / leading-zero hash is never YAML-coerced to int.
new_line = 'goal_approved_version: "%s"' % value
replaced = False
for i in range(1, end):
    if re.match(r"^goal_approved_version:", lines[i]):
        lines[i] = new_line; replaced = True; break
if not replaced:
    lines.insert(end, new_line)        # before the closing fence — outside the goal block

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
print('recorded: goal_approved_version="%s" in %s' % (value, os.path.basename(overview)))
PY
}

# ── Self-test ────────────────────────────────────────────────────────────────
_ST_TMP=""
self_test() {
    local t_pass=0 t_fail=0 d h_a h_b h_b2 h_a2
    _ST_TMP="$(mktemp -d)"
    trap '[[ -n "${_ST_TMP:-}" ]] && rm -rf "$_ST_TMP"' EXIT
    d="$_ST_TMP"
    mkdir -p "$d/wp-01-a" "$d/wp-01-b"

    _fixture() {  # $1 = overview path, $2 = outcome text
        cat > "$1" <<EOF
---
name: $(basename "$(dirname "$1")")
title: hash fixture
status: ready
stage_updated: 2026-06-23
severity: LOW
parallel: false
depends_on: []
plan: tmpfeat
task_type: code
goal:
  outcome: "$2"
  verification:
    strategy: deterministic
    check: "true"
  constraints: []
  boundaries: []
  iteration_policy: "retry until green"
  blocked_stop: "halt after 3 tries"
inherits_from: null
goal_approved_version: null
---

# fixture
EOF
    }

    local ok no
    ok() { echo "$1: PASS"; t_pass=$((t_pass+1)); }
    no() { echo "$1: FAIL"; t_fail=$((t_fail+1)); }

    echo "=== goalforge-goal-hash.sh --self-test ==="

    # (a) identical goal blocks in two files hash identically
    _fixture "$d/wp-01-a/overview.md" "the thing is done"
    _fixture "$d/wp-01-b/overview.md" "the thing is done"
    h_a="$(bash "$SELF" "$d/wp-01-a")"
    h_b="$(bash "$SELF" "$d/wp-01-b")"
    if [[ -n "$h_a" && "$h_a" == "$h_b" ]]; then
        ok "identical-block-hashes-equal"
    else
        no "identical-block-hashes-equal ($h_a vs $h_b)"
    fi

    # (b) a one-character goal change changes the hash
    _fixture "$d/wp-01-b/overview.md" "the thing is donE"
    h_b2="$(bash "$SELF" "$d/wp-01-b")"
    if [[ -n "$h_b2" && "$h_b2" != "$h_a" ]]; then
        ok "one-char-change-changes-hash"
    else
        no "one-char-change-changes-hash"
    fi

    # (c) --record then a re-print round-trips (record does not change the hash)
    bash "$SELF" --record "$d/wp-01-a" >/dev/null
    h_a2="$(bash "$SELF" "$d/wp-01-a")"
    if [[ "$h_a2" == "$h_a" ]] && grep -q "goal_approved_version: \"$h_a\"" "$d/wp-01-a/overview.md"; then
        ok "record-roundtrip"
    else
        no "record-roundtrip"
    fi

    echo ""
    echo "Results: $t_pass passed, $t_fail failed"
    [[ "$t_fail" -eq 0 ]]
}

# ── Argument parsing ─────────────────────────────────────────────────────────
RECORD=0
SELFTEST=0
POS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --record)    RECORD=1; shift ;;
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
    echo "ERROR: usage: goalforge-goal-hash.sh [--record] <wp-path>" >&2
    exit 1
fi

OVERVIEW="$(resolve_overview "${POS[0]}")"

if [[ "$RECORD" -eq 1 ]]; then
    record "$OVERVIEW"
else
    set +e; H="$(hash_block "$OVERVIEW")"; rc=$?; set -e
    if [[ "$rc" -ne 0 ]]; then
        [[ "$rc" -eq 3 ]] && echo "ERROR: no goal: block in $OVERVIEW" >&2
        exit "$rc"
    fi
    printf '%s\n' "$H"
fi
