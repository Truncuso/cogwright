#!/usr/bin/env bash
# recap.sh — maintain a living recap.md per SDD feature
#
# Subcommands:
#   init <recap-path> <feature-slug>
#   append-task <recap-path> <wp-slug> <task-slug> <result>
#   append-loopback <recap-path> <wp-slug> <iter> <reason> [task-slug]
#   finalize <recap-path> <wp-slug> <green|yellow|red> <summary>
#   rollup <recap-path>
#   --self-test
#
# All subcommands are idempotent. Paths resolved via python3 realpath.
# Exit 0 on success, non-zero on error.

set -euo pipefail

# ── Helpers ──────────────────────────────────────────────────────────────────

realpath_py() {
  python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1"
}

# Get short commit hash; falls back to '-' outside a git repo.
git_short_hash() {
  local dir="${1:-.}"
  git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "-"
}

die() { echo "ERROR: $*" >&2; exit 1; }

# ── Subcommand: init ──────────────────────────────────────────────────────────
# init <recap-path> <feature-slug>
# Create the recap.md header. No-op (byte-identical) if the file already exists.
cmd_init() {
  [[ $# -ge 2 ]] || die "init requires <recap-path> <feature-slug>"
  local recap_path
  recap_path="$(realpath_py "$1")"
  local feature_slug="$2"

  if [[ -f "$recap_path" ]]; then
    # Already exists — idempotency: do nothing.
    return 0
  fi

  mkdir -p "$(dirname "$recap_path")"
  cat > "$recap_path" <<EOF
# Recap — ${feature_slug}

<!-- maintained by sdd-recap (scripts/recap.sh); do not hand-edit -->
EOF
}

# ── Subcommand: append-task ───────────────────────────────────────────────────
# append-task <recap-path> <wp-slug> <task-slug> <result>
# Add or UPDATE the task row under the WP section. OPTIONAL live-progress only —
# the authoritative trace is one row per WP (see record-wp). The task table has
# NO commit column: the commit is recorded at WP altitude (the Status line), which
# is the direct answer to "trace too many commits".
# Same task-slug in the same WP = one row updated in place, never duplicated.
cmd_append_task() {
  [[ $# -ge 4 ]] || die "append-task requires <recap-path> <wp-slug> <task-slug> <result>"
  local recap_path wp_slug task_slug result
  recap_path="$(realpath_py "$1")"
  wp_slug="$2"
  task_slug="$3"
  result="$4"

  [[ -f "$recap_path" ]] || die "recap file not found: $recap_path"

  python3 - "$recap_path" "$wp_slug" "$task_slug" "$result" <<'PYEOF'
import sys
from pathlib import Path

recap_path = Path(sys.argv[1])
wp_slug    = sys.argv[2]
task_slug  = sys.argv[3]
result     = sys.argv[4]

text = recap_path.read_text(encoding='utf-8')
lines = text.split('\n')

wp_header = f"## {wp_slug}"
table_header = "| Task | Result |"
table_sep    = "|------|--------|"
new_row      = f"| {task_slug} | {result} |"

# Find WP section start
wp_idx = None
for i, line in enumerate(lines):
    if line.strip() == wp_header:
        wp_idx = i
        break

if wp_idx is None:
    # WP section does not exist — append it before ## Feature rollup (if present)
    # or at end of file.
    rollup_idx = None
    for i, line in enumerate(lines):
        if line.strip() == "## Feature rollup":
            rollup_idx = i
            break

    new_section = [
        "",
        wp_header,
        "",
        table_header,
        table_sep,
        new_row,
        "",
    ]

    if rollup_idx is not None:
        # Insert before the rollup section (keep a blank line separation)
        lines = lines[:rollup_idx] + new_section + lines[rollup_idx:]
    else:
        lines = lines + new_section
    recap_path.write_text('\n'.join(lines), encoding='utf-8')
    sys.exit(0)

# WP section exists — find or create the table, then add/update row
# Scan from wp_idx forward until we hit the next ## section or EOF
section_end = len(lines)
for i in range(wp_idx + 1, len(lines)):
    if lines[i].startswith("## ") and i != wp_idx:
        section_end = i
        break

section = lines[wp_idx:section_end]

# Find table header within section
tbl_hdr_idx = None
for j, l in enumerate(section):
    if l.strip() == table_header:
        tbl_hdr_idx = j
        break

if tbl_hdr_idx is None:
    # No table yet — insert after wp_header blank line
    section = [section[0], "", table_header, table_sep, new_row, ""] + section[1:]
    lines = lines[:wp_idx] + section + lines[section_end:]
    recap_path.write_text('\n'.join(lines), encoding='utf-8')
    sys.exit(0)

# Table exists — look for existing row with same task_slug
row_prefix = f"| {task_slug} |"
updated = False
for j in range(tbl_hdr_idx + 2, len(section)):
    l = section[j]
    if not l.startswith("|"):
        break
    if l.startswith(row_prefix):
        section[j] = new_row
        updated = True
        break

if not updated:
    # Insert new row after last table row
    insert_at = tbl_hdr_idx + 2
    while insert_at < len(section) and section[insert_at].startswith("|"):
        insert_at += 1
    section.insert(insert_at, new_row)

lines = lines[:wp_idx] + section + lines[section_end:]
recap_path.write_text('\n'.join(lines), encoding='utf-8')
PYEOF
}

# ── Subcommand: append-loopback ───────────────────────────────────────────────
# append-loopback <recap-path> <wp-slug> <iter> <reason> [task-slug]
cmd_append_loopback() {
  [[ $# -ge 4 ]] || die "append-loopback requires <recap-path> <wp-slug> <iter> <reason> [task-slug]"
  local recap_path wp_slug iter reason task_slug
  recap_path="$(realpath_py "$1")"
  wp_slug="$2"
  iter="$3"
  reason="$4"
  task_slug="${5:-}"

  [[ -f "$recap_path" ]] || die "recap file not found: $recap_path"

  python3 - "$recap_path" "$wp_slug" "$iter" "$reason" "$task_slug" <<'PYEOF'
import sys
from pathlib import Path

recap_path = Path(sys.argv[1])
wp_slug    = sys.argv[2]
iter_n     = sys.argv[3]
reason     = sys.argv[4]
task_slug  = sys.argv[5]

text  = recap_path.read_text(encoding='utf-8')
lines = text.split('\n')

wp_header = f"## {wp_slug}"
lb_header = "Loop-backs:"

if task_slug:
    entry = f"- iter {iter_n}: {reason} (re-executed {task_slug})"
else:
    entry = f"- iter {iter_n}: {reason}"

# Locate WP section
wp_idx = None
for i, line in enumerate(lines):
    if line.strip() == wp_header:
        wp_idx = i
        break

if wp_idx is None:
    print(f"WARNING: WP section '{wp_slug}' not found; skipping loop-back", file=sys.stderr)
    sys.exit(0)

# Find section end
section_end = len(lines)
for i in range(wp_idx + 1, len(lines)):
    if lines[i].startswith("## ") and i != wp_idx:
        section_end = i
        break

section = lines[wp_idx:section_end]

# Find or create Loop-backs: block
lb_idx = None
for j, l in enumerate(section):
    if l.strip() == lb_header:
        lb_idx = j
        break

if lb_idx is None:
    # Insert Loop-backs block before Status: line or before end of section
    status_j = None
    for j, l in enumerate(section):
        if l.startswith("Status:"):
            status_j = j
            break
    if status_j is not None:
        section = section[:status_j] + [lb_header, entry, ""] + section[status_j:]
    else:
        # Find end of table rows
        insert_j = len(section)
        in_table = False
        for j, l in enumerate(section):
            if l.startswith("| Task |"):
                in_table = True
            if in_table and l.startswith("|"):
                insert_j = j + 1
        section = section[:insert_j] + ["", lb_header, entry] + section[insert_j:]
else:
    # Upsert by iter key: replace an existing entry for the same iter (so a
    # re-run with identical args is a no-op), else append after the last entry.
    iter_prefix = f"- iter {iter_n}:"
    insert_j = lb_idx + 1
    replaced = False
    while insert_j < len(section) and section[insert_j].startswith("- "):
        if section[insert_j].startswith(iter_prefix):
            section[insert_j] = entry
            replaced = True
            break
        insert_j += 1
    if not replaced:
        section.insert(insert_j, entry)

lines = lines[:wp_idx] + section + lines[section_end:]
recap_path.write_text('\n'.join(lines), encoding='utf-8')
PYEOF
}

# ── Subcommand: finalize ──────────────────────────────────────────────────────
# finalize <recap-path> <wp-slug> <green|yellow|red> <summary>
cmd_finalize() {
  [[ $# -ge 4 ]] || die "finalize requires <recap-path> <wp-slug> <green|yellow|red> <summary>"
  local recap_path wp_slug color summary
  recap_path="$(realpath_py "$1")"
  wp_slug="$2"
  color="$3"
  summary="$4"

  [[ -f "$recap_path" ]] || die "recap file not found: $recap_path"
  [[ "$color" =~ ^(green|yellow|red)$ ]] || die "color must be green, yellow, or red"
  [[ -n "$summary" ]] || die "summary must not be empty"

  python3 - "$recap_path" "$wp_slug" "$color" "$summary" <<'PYEOF'
import sys
from pathlib import Path

recap_path = Path(sys.argv[1])
wp_slug    = sys.argv[2]
color      = sys.argv[3]
summary    = sys.argv[4]

text  = recap_path.read_text(encoding='utf-8')
lines = text.split('\n')

wp_header  = f"## {wp_slug}"
status_line = f"Status: {color} — {summary}"

# Locate WP section
wp_idx = None
for i, line in enumerate(lines):
    if line.strip() == wp_header:
        wp_idx = i
        break

if wp_idx is None:
    print(f"WARNING: WP section '{wp_slug}' not found", file=sys.stderr)
    sys.exit(1)

# Find section end
section_end = len(lines)
for i in range(wp_idx + 1, len(lines)):
    if lines[i].startswith("## ") and i != wp_idx:
        section_end = i
        break

section = lines[wp_idx:section_end]

# Find existing Status: line
status_j = None
for j, l in enumerate(section):
    if l.startswith("Status:"):
        status_j = j
        break

if status_j is not None:
    section[status_j] = status_line
else:
    # Append before blank trailing lines
    # Strip trailing blanks from section, append status, add blank
    while section and section[-1].strip() == "":
        section.pop()
    section.append("")
    section.append(status_line)

lines = lines[:wp_idx] + section + lines[section_end:]
recap_path.write_text('\n'.join(lines), encoding='utf-8')
PYEOF
}

# ── Subcommand: record-wp ─────────────────────────────────────────────────────
# record-wp <recap-path> <wp-slug> <green|yellow|red> <wp-commit> <summary> [task-slug ...]
# The authoritative one-row-per-WP record: ensures the WP section + task rows
# exist, then writes the Status line carrying the SINGLE WP commit at WP altitude
# (Status: <color> — <commit> — <summary>). Idempotent. Optional task-slug args
# upsert their rows (result `ok`) so the WP can be recorded in one call without
# prior live-progress append-task calls.
cmd_record_wp() {
  [[ $# -ge 5 ]] || die "record-wp requires <recap-path> <wp-slug> <color> <wp-commit> <summary> [task-slug ...]"
  local recap_path wp_slug color commit summary
  recap_path="$(realpath_py "$1")"
  wp_slug="$2"
  color="$3"
  commit="$4"
  summary="$5"
  shift 5
  [[ -f "$recap_path" ]] || die "recap file not found: $recap_path"
  [[ "$color" =~ ^(green|yellow|red)$ ]] || die "color must be green, yellow, or red"
  [[ -n "$summary" ]] || die "summary must not be empty"
  [[ -n "$commit" ]] || commit="-"

  python3 - "$recap_path" "$wp_slug" "$color" "$commit" "$summary" "$@" <<'PYEOF'
import sys
from pathlib import Path

recap_path = Path(sys.argv[1])
wp_slug    = sys.argv[2]
color      = sys.argv[3]
commit     = sys.argv[4]
summary    = sys.argv[5]
task_slugs = sys.argv[6:]

text  = recap_path.read_text(encoding='utf-8')
lines = text.split('\n')

wp_header    = f"## {wp_slug}"
table_header = "| Task | Result |"
table_sep    = "|------|--------|"
status_line  = f"Status: {color} — {commit} — {summary}"

# Ensure WP section exists (create before ## Feature rollup or at EOF).
def find_wp():
    for i, l in enumerate(lines):
        if l.strip() == wp_header:
            return i
    return None

if find_wp() is None:
    rollup_idx = None
    for i, l in enumerate(lines):
        if l.strip() == "## Feature rollup":
            rollup_idx = i
            break
    new_section = ["", wp_header, "", table_header, table_sep, ""]
    if rollup_idx is not None:
        lines[:] = lines[:rollup_idx] + new_section + lines[rollup_idx:]
    else:
        lines[:] = lines + new_section

wp_idx = find_wp()
section_end = len(lines)
for i in range(wp_idx + 1, len(lines)):
    if lines[i].startswith("## ") and i != wp_idx:
        section_end = i
        break
section = lines[wp_idx:section_end]

# Ensure a table header exists in the section.
tbl_hdr_idx = next((j for j, l in enumerate(section) if l.strip() == table_header), None)
if tbl_hdr_idx is None:
    section = [section[0], "", table_header, table_sep, ""] + section[1:]
    tbl_hdr_idx = 2

# Upsert each task row (result ok), never duplicating.
for task_slug in task_slugs:
    row = f"| {task_slug} | ok |"
    prefix = f"| {task_slug} |"
    found = False
    for j in range(tbl_hdr_idx + 2, len(section)):
        if not section[j].startswith("|"):
            break
        if section[j].startswith(prefix):
            section[j] = row
            found = True
            break
    if not found:
        insert_at = tbl_hdr_idx + 2
        while insert_at < len(section) and section[insert_at].startswith("|"):
            insert_at += 1
        section.insert(insert_at, row)

# Upsert the Status line (one per WP).
status_j = next((j for j, l in enumerate(section) if l.startswith("Status:")), None)
if status_j is not None:
    section[status_j] = status_line
else:
    while section and section[-1].strip() == "":
        section.pop()
    section.append("")
    section.append(status_line)

lines[:] = lines[:wp_idx] + section + lines[section_end:]
recap_path.write_text('\n'.join(lines), encoding='utf-8')
PYEOF
  echo "sdd-recap: record-wp ${wp_slug}: Status: ${color} — ${commit} — ${summary} (${recap_path})"
}

# ── Subcommand: rollup ────────────────────────────────────────────────────────
# rollup <recap-path>
# Regenerate ## Feature rollup from per-WP Status lines.
cmd_rollup() {
  [[ $# -ge 1 ]] || die "rollup requires <recap-path>"
  local recap_path
  recap_path="$(realpath_py "$1")"
  [[ -f "$recap_path" ]] || die "recap file not found: $recap_path"

  python3 - "$recap_path" <<'PYEOF'
import sys
import re
from pathlib import Path

recap_path = Path(sys.argv[1])
text  = recap_path.read_text(encoding='utf-8')
lines = text.split('\n')

# Collect WP Status lines (exclude ## Feature rollup pseudo-section)
green = yellow = red = 0
for line in lines:
    if line.startswith("Status:"):
        m = re.match(r"Status:\s*(green|yellow|red)\s*—", line)
        if m:
            c = m.group(1)
            if c == "green":   green  += 1
            elif c == "yellow": yellow += 1
            elif c == "red":    red    += 1

total = green + yellow + red
rollup_body = f"## Feature rollup\n\n- {green} green, {yellow} yellow, {red} red (of {total} WPs)"

# Remove existing ## Feature rollup section (everything from that header to EOF)
rollup_idx = None
for i, line in enumerate(lines):
    if line.strip() == "## Feature rollup":
        rollup_idx = i
        break

if rollup_idx is not None:
    lines = lines[:rollup_idx]

# Strip trailing blank lines, then append rollup
while lines and lines[-1].strip() == "":
    lines.pop()

new_text = '\n'.join(lines) + "\n\n" + rollup_body + "\n"
recap_path.write_text(new_text, encoding='utf-8')
PYEOF
}

# ── Subcommand: --self-test ───────────────────────────────────────────────────
cmd_self_test() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  # Set up a minimal git repo so git_short_hash works
  git -C "$tmpdir" init -q
  git -C "$tmpdir" config user.email "test@test.com"
  git -C "$tmpdir" config user.name "Test"
  touch "$tmpdir/placeholder"
  git -C "$tmpdir" add placeholder
  git -C "$tmpdir" commit -q -m "init"

  local recap="$tmpdir/recap.md"
  local PASS=0 FAIL=0

  assert() {
    local desc="$1" cond="$2"
    if eval "$cond"; then
      echo "  PASS: $desc"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: $desc"
      FAIL=$((FAIL + 1))
    fi
  }

  echo "=== sdd-recap: --self-test ==="

  # 1. init creates file
  bash "$0" init "$recap" "my-feature"
  assert "init creates recap.md" "[[ -f '$recap' ]]"
  assert "init writes feature slug header" "grep -qF '# Recap — my-feature' '$recap'"
  assert "init writes maintenance comment" "grep -qF 'maintained by sdd-recap' '$recap'"

  # 2. init twice = no-op (idempotency)
  local before after
  before="$(cat "$recap")"
  bash "$0" init "$recap" "my-feature"
  after="$(cat "$recap")"
  assert "init idempotency (double-init = byte-identical)" "[[ '$before' == '$after' ]]"

  # 3. append-task creates WP section and task row
  bash "$0" append-task "$recap" "wp-01" "task-a" "ok"
  assert "append-task creates WP section" "grep -qF '## wp-01' '$recap'"
  assert "append-task writes task row" "grep -qF '| task-a |' '$recap'"
  assert "append-task writes result ok" "grep -qF '| ok |' '$recap'"

  # 4. append-task idempotency (same task twice = one row)
  bash "$0" append-task "$recap" "wp-01" "task-a" "ok"
  local count
  count="$(grep -c '| task-a |' "$recap")"
  assert "append-task idempotency (no duplicate rows)" "[[ '$count' == '1' ]]"

  # 5. append-task second task in same WP
  bash "$0" append-task "$recap" "wp-01" "task-b" "ok"
  assert "append-task second task in same WP" "grep -qF '| task-b |' '$recap'"

  # 6. append-loopback creates Loop-backs block
  bash "$0" append-loopback "$recap" "wp-01" "2" "test-failure" "task-b"
  assert "append-loopback creates Loop-backs header" "grep -qF 'Loop-backs:' '$recap'"
  assert "append-loopback records iter and reason" "grep -qF 'iter 2: test-failure (re-executed task-b)' '$recap'"

  # 6b. append-loopback idempotency (same iter twice = upsert, not duplicated)
  bash "$0" append-loopback "$recap" "wp-01" "2" "test-failure" "task-b"
  local lb_count
  lb_count="$(grep -c '^- iter 2:' "$recap")"
  assert "append-loopback idempotency (single entry per iter)" "[[ '$lb_count' == '1' ]]"

  # 7. finalize writes Status line
  bash "$0" finalize "$recap" "wp-01" "yellow" "completed with retries"
  assert "finalize writes Status line" "grep -qF 'Status: yellow — completed with retries' '$recap'"

  # 8. finalize idempotency (update in place, not duplicated)
  bash "$0" finalize "$recap" "wp-01" "green" "all tasks ok"
  local status_count
  status_count="$(grep -c '^Status:' "$recap")"
  assert "finalize idempotency (single Status line per WP)" "[[ '$status_count' == '1' ]]"
  assert "finalize updates Status color" "grep -qF 'Status: green — all tasks ok' '$recap'"

  # 9. second WP
  bash "$0" append-task "$recap" "wp-02" "task-x" "ok"
  bash "$0" finalize "$recap" "wp-02" "green" "clean pass"

  # 10. rollup counts WPs
  bash "$0" rollup "$recap"
  assert "rollup section created" "grep -qF '## Feature rollup' '$recap'"
  assert "rollup counts green WPs" "grep -qF '2 green' '$recap'"
  assert "rollup counts 0 red" "grep -qF '0 red' '$recap'"
  assert "rollup total is 2" "grep -qF 'of 2 WPs' '$recap'"

  # 11. rollup idempotency
  bash "$0" rollup "$recap"
  local rollup_count
  rollup_count="$(grep -c '## Feature rollup' "$recap")"
  assert "rollup idempotency (single rollup section)" "[[ '$rollup_count' == '1' ]]"

  # 12. task table has NO commit column (commit moved to WP altitude)
  assert "task table is 2-col (no Commit column)" "grep -qF '| Task | Result |' '$recap'"
  assert "old 3-col Commit table header absent" "! grep -qF '| Task | Commit | Result |' '$recap'"

  # 13. record-wp: one-call WP record with commit on the Status line
  bash "$0" record-wp "$recap" "wp-03" "green" "abc1234" "single-call WP record" "task-p" "task-q"
  assert "record-wp creates WP section" "grep -qF '## wp-03' '$recap'"
  assert "record-wp upserts task rows" "grep -qF '| task-p | ok |' '$recap'"
  assert "record-wp commit on Status line" "grep -qF 'Status: green — abc1234 — single-call WP record' '$recap'"
  # 13b. record-wp confirms success on stdout (silent-success ergonomics fix)
  assert "record-wp prints success confirmation" "bash '$0' record-wp '$recap' 'wp-03' 'green' 'abc1234' 'single-call WP record' | grep -qF 'record-wp wp-03'"

  # 14. record-wp idempotency (single Status line, no duplicate rows)
  bash "$0" record-wp "$recap" "wp-03" "green" "abc1234" "single-call WP record" "task-p" "task-q"
  local wp3_status wp3_taskp
  wp3_status="$(grep -c 'single-call WP record' "$recap")"
  wp3_taskp="$(grep -c '| task-p |' "$recap")"
  assert "record-wp idempotency (single Status line)" "[[ '$wp3_status' == '1' ]]"
  assert "record-wp idempotency (no duplicate task row)" "[[ '$wp3_taskp' == '1' ]]"

  # 15. rollup still parses the commit-bearing Status line
  bash "$0" rollup "$recap"
  assert "rollup counts the record-wp WP (3 green)" "grep -qF '3 green' '$recap'"

  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  if [[ "$FAIL" -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
[[ $# -ge 1 ]] || { echo "Usage: recap.sh <subcommand> [args...]" >&2; exit 1; }

case "$1" in
  init)            shift; cmd_init "$@" ;;
  append-task)     shift; cmd_append_task "$@" ;;
  append-loopback) shift; cmd_append_loopback "$@" ;;
  finalize)        shift; cmd_finalize "$@" ;;
  record-wp)       shift; cmd_record_wp "$@" ;;
  rollup)          shift; cmd_rollup "$@" ;;
  --self-test)     cmd_self_test ;;
  *) die "Unknown subcommand: $1" ;;
esac
