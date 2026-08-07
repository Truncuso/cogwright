#!/usr/bin/env bash
# goalforge-frontmatter-touch.sh — PostToolUse hook for Write|Edit.
#
# Reads the edited file path from the hook payload (stdin JSON).
# If the path is under ~/.claude/plans/**/ and ends in .md, bumps
# `updated:` (and `stage_updated:` if present) in the frontmatter
# to today's date (YYYY-MM-DD). Idempotent: no write if already today.
# Only touches the frontmatter block (between the first two --- lines).
# No-op silently for non-plans paths or non-.md files.
#
# Discipline:
#   - Never breaks the session: every failure path exits 0.
#   - Never mutates files outside ~/.claude/plans/.
#   - No write when values are already current.

set -uo pipefail

PLANS_ROOT="${HOME}/.claude/plans"
TODAY=$(date +%F)

# ── Parse payload ──────────────────────────────────────────────────────────

HOOK_INPUT=$(cat 2>/dev/null || true)
[ -n "$HOOK_INPUT" ] || exit 0

FILE_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '
  .tool_input.file_path // .tool_input.path // ""
' 2>/dev/null) || exit 0

[ -n "$FILE_PATH" ] || exit 0

# ── Guard: must be under PLANS_ROOT and end in .md ─────────────────────────

# Resolve to absolute path
case "$FILE_PATH" in
  /*) ;;
  "~/"*) FILE_PATH="${HOME}/${FILE_PATH#\~/}" ;;
  *) exit 0 ;;
esac

# Canonicalise (strip ../ etc) without requiring the file to already exist
REAL_PATH=$(python3 -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$FILE_PATH" 2>/dev/null) || exit 0
REAL_PLANS=$(python3 -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$PLANS_ROOT" 2>/dev/null) || exit 0

case "$REAL_PATH" in
  "${REAL_PLANS}/"*.md) ;;  # under plans root, .md — proceed
  *) exit 0 ;;
esac

[ -f "$REAL_PATH" ] || exit 0

# ── Bump frontmatter dates ─────────────────────────────────────────────────

python3 - "$REAL_PATH" "$TODAY" <<'PYEOF'
import sys
import re

path = sys.argv[1]
today = sys.argv[2]

with open(path, 'r', encoding='utf-8') as fh:
    content = fh.read()

# Locate frontmatter: must start at line 0 with ---
lines = content.split('\n')
if not lines or lines[0].strip() != '---':
    sys.exit(0)

# Find closing ---
end_idx = None
for i in range(1, len(lines)):
    if lines[i].strip() == '---':
        end_idx = i
        break

if end_idx is None:
    sys.exit(0)

fm_lines = lines[1:end_idx]
changed = False

updated_re = re.compile(r'^(updated:\s*)(.+)$')
stage_re   = re.compile(r'^(stage_updated:\s*)(.+)$')

new_fm = []
for line in fm_lines:
    m = updated_re.match(line)
    if m:
        if m.group(2).strip() != today:
            line = m.group(1) + today
            changed = True
        new_fm.append(line)
        continue
    m = stage_re.match(line)
    if m:
        if m.group(2).strip() != today:
            line = m.group(1) + today
            changed = True
        new_fm.append(line)
        continue
    new_fm.append(line)

if not changed:
    sys.exit(0)

new_content = '\n'.join(['---'] + new_fm + lines[end_idx:])
with open(path, 'w', encoding='utf-8') as fh:
    fh.write(new_content)
PYEOF
