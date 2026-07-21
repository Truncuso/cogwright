#!/usr/bin/env bash
# brief-staleness.sh — pre-consumption staleness re-validation for a briefed task
# (goalforge wp-06 task-04). The brief is IMMUTABLE after authoring (A-FOLD); this
# script NEVER edits it. It compares the brief's recorded staleness anchors against
# current repo state and, on drift, records a re-brief request in the TASK's
# checkpoint block — it does not touch the brief and does not mutate task status.
#
# Usage:
#   brief-staleness.sh <wp-dir> <task-slug>
#       <wp-dir>/brief-<task-slug>.md is the brief; <wp-dir>/<task-slug>.md the task.
#   brief-staleness.sh --self-test
#
# Anchors live in the brief's `## References` table, one per row `| <left> | <recorded> |`:
#   - a file anchor  `path:line`  → recorded value is the git blob SHA of the file;
#     current value = `git hash-object <path>` (working-tree content).
#   - the goal anchor `goal:<wp>`  → recorded value is the WP goal-hash;
#     current value = `goalforge-goal-hash.sh <wp-dir>`.
# File paths resolve relative to <wp-dir> first, else as given (repo-relative from CWD).
#
# Exit: 0 = FRESH (matching anchors — safe to consume the brief).
#       3 = STALE (>=1 anchor drifted — a re-brief request was recorded; do NOT consume).
#       1 = usage / IO error (missing brief, unparseable table).
# Prints a machine verdict line `verdict: FRESH|STALE` plus per-anchor drift reasons.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOAL_HASH_SH="$SCRIPT_DIR/../scripts/goalforge-goal-hash.sh"

usage() { sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

revalidate() {
    local WP_DIR="$1" TASK_SLUG="$2"
    WP_DIR="$(cd "$WP_DIR" && pwd)"
    local BRIEF="$WP_DIR/brief-$TASK_SLUG.md"
    local TASK="$WP_DIR/$TASK_SLUG.md"
    [[ -f "$BRIEF" ]] || { echo "ERROR: brief not found: $BRIEF" >&2; return 1; }
    [[ -f "$TASK"  ]] || { echo "ERROR: task not found: $TASK" >&2; return 1; }

    # Current WP goal-hash (best-effort; empty if the WP has no goal block).
    local CUR_GOAL_HASH=""
    CUR_GOAL_HASH="$(bash "$GOAL_HASH_SH" "$WP_DIR" 2>/dev/null || true)"

    python3 - "$BRIEF" "$TASK" "$WP_DIR" "$CUR_GOAL_HASH" <<'PY'
import sys, os, re, subprocess, datetime
brief, task, wp_dir, cur_goal_hash = sys.argv[1:5]

lines = open(brief, encoding="utf-8").read().split("\n")

# Slice the `## References` section (up to the next `## ` heading).
start = None
for i, ln in enumerate(lines):
    if re.match(r"^##\s+References\b", ln):
        start = i + 1; break
if start is None:
    sys.stderr.write("ERROR: brief has no `## References` section: %s\n" % brief)
    sys.exit(1)
end = len(lines)
for i in range(start, len(lines)):
    if re.match(r"^##\s+", lines[i]):
        end = i; break

def git_hash_object(path):
    return subprocess.run(["git", "hash-object", path],
                          capture_output=True, text=True, check=True).stdout.strip()

drift = []
anchors = 0
for ln in lines[start:end]:
    s = ln.strip()
    if not s.startswith("|"):
        continue
    cells = [c.strip() for c in s.strip("|").split("|")]
    if len(cells) < 2:
        continue
    left, recorded = cells[0], cells[1]
    # Skip the markdown table header + separator rows.
    if set(recorded) <= set("-: ") or left.lower() in ("file:line", "file", "reference", "anchor"):
        continue
    anchors += 1
    if left.startswith("goal:"):
        cur = cur_goal_hash
        if cur != recorded:
            drift.append("goal-hash %s: recorded=%s current=%s" % (left, recorded, cur or "<none>"))
    else:
        path = left.split(":", 1)[0]
        cand = os.path.join(wp_dir, path)
        resolved = cand if os.path.exists(cand) else path
        if not os.path.exists(resolved):
            drift.append("file %s: MISSING (recorded=%s)" % (path, recorded))
            continue
        try:
            cur = git_hash_object(resolved)
        except subprocess.CalledProcessError as e:
            drift.append("file %s: hash-object failed (%s)" % (path, e.stderr.strip()))
            continue
        if cur != recorded:
            drift.append("blob %s: recorded=%s current=%s" % (path, recorded, cur))

if anchors == 0:
    sys.stderr.write("ERROR: brief `## References` has no staleness anchors: %s\n" % brief)
    sys.exit(1)

if not drift:
    print("verdict: FRESH")
    print("anchors: %d checked, 0 drifted" % anchors)
    sys.exit(0)

# STALE — record a re-brief request in the TASK checkpoint block (the brief is
# immutable; the staleness result records to the task, never the brief).
today = datetime.date.today().isoformat()
reason = "; ".join(drift)
note = ("rebrief_requested: true  # %s brief-staleness: %s\n" % (today, reason))

t_lines = open(task, encoding="utf-8").read().split("\n")
hdr = None
for i, ln in enumerate(t_lines):
    if re.match(r"^##\s+Checkpoint\b", ln):
        hdr = i; break
if hdr is None:
    t_lines += ["", "## Checkpoint (goalforge-execute state)", "",
                "checkpoint:", "  " + note.rstrip()]
else:
    # Insert the marker as the first indented line after the `checkpoint:` key,
    # or immediately after the heading if no checkpoint: key is present yet.
    ins = None
    for j in range(hdr + 1, len(t_lines)):
        if re.match(r"^checkpoint:\s*$", t_lines[j]):
            ins = j + 1; break
        if re.match(r"^##\s+", t_lines[j]):
            break
    if ins is None:
        t_lines.insert(hdr + 1, "  " + note.rstrip())
    else:
        t_lines.insert(ins, "  " + note.rstrip())

out = "\n".join(t_lines)
d = os.path.dirname(os.path.abspath(task))
import tempfile
fd, tmp = tempfile.mkstemp(dir=d, suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(out)
    os.replace(tmp, task)
except Exception:
    try: os.unlink(tmp)
    except OSError: pass
    raise

print("verdict: STALE")
for d_ in drift:
    print("drift: " + d_)
print("recorded re-brief request in %s checkpoint block" % os.path.basename(task))
sys.exit(3)
PY
}

main() {
    case "${1:-}" in
        --self-test) self_test ;;
        -h|--help|"") usage; [[ -z "${1:-}" ]] && exit 1 || exit 0 ;;
        *)
            [[ $# -eq 2 ]] || { echo "ERROR: expected <wp-dir> <task-slug>" >&2; usage; exit 1; }
            revalidate "$1" "$2"
            ;;
    esac
}

# ── Self-test (offline, deterministic) ───────────────────────────────────────
self_test() {
    local d rc out
    d="$(mktemp -d)"; trap "rm -rf '$d'" EXIT
    local WP="$d/wp-01-st"; mkdir -p "$WP/src"
    printf 'def a():\n    return 1\n' > "$WP/src/a.py"
    local SHA; SHA="$(git hash-object "$WP/src/a.py")"
    cat > "$WP/overview.md" <<EOF
---
name: wp-01-st
status: ready
goal:
  outcome: "fixture"
EOF
    local GH; GH="$(bash "$GOAL_HASH_SH" "$WP" 2>/dev/null || true)"
    cat > "$WP/brief-task-01-st.md" <<EOF
---
task: task-01-st
created: 2026-07-19
brief_tier: opus@high
---
## References
| file:line | git blob SHA |
| --- | --- |
| src/a.py:1 | $SHA |
| goal:wp-01-st | $GH |
EOF
    cat > "$WP/task-01-st.md" <<EOF
---
name: task-01-st
status: briefed
complexity: medium
---
## Goal
fixture
EOF
    # FRESH path.
    set +e; out="$(revalidate "$WP" "task-01-st")"; rc=$?; set -e
    if [[ "$rc" -ne 0 ]] || ! grep -q "verdict: FRESH" <<<"$out"; then
        echo "SELFTEST FAIL: expected FRESH (rc=$rc)"; echo "$out"; return 1
    fi
    # Drift the file → STALE.
    printf 'def a():\n    return 2\n' > "$WP/src/a.py"
    set +e; out="$(revalidate "$WP" "task-01-st")"; rc=$?; set -e
    if [[ "$rc" -ne 3 ]] || ! grep -q "verdict: STALE" <<<"$out"; then
        echo "SELFTEST FAIL: expected STALE rc=3 (rc=$rc)"; echo "$out"; return 1
    fi
    grep -q "rebrief_requested: true" "$WP/task-01-st.md" || {
        echo "SELFTEST FAIL: re-brief request not recorded in task checkpoint"; return 1; }
    echo "SELFTEST PASS: FRESH→exit0, drift→STALE exit3 + checkpoint recorded"
    return 0
}

main "$@"
