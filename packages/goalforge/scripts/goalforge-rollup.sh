#!/usr/bin/env bash
# sdd-rollup.sh — derive a feature-level todo.md rollup from authoritative
#                 wp-*/overview.md status: frontmatter.
#
# Usage:
#   sdd-rollup.sh <feature-dir>
#
# Reads (NEVER writes to these):
#   <feature-dir>/overview.md                 — feature name:, title:
#   <feature-dir>/wp-*/overview.md            — name:, title:, status:, stage_updated:
#   <feature-dir>/wp-*/todo.md                — ## Open Items and ## Blocked On bullets
#
# Writes exactly one file:
#   <feature-dir>/todo.md                     — generated: true rollup
#
# Clobber guard: if <feature-dir>/todo.md already exists WITHOUT
# `generated: true` in its frontmatter, it is a hand-maintained file this
# script does not own — the rollup REFUSES to overwrite it, warns on stderr,
# and exits 0 (never blocks the calling transition). Move the hand content
# aside (e.g. open-items.md) to adopt the generated rollup.
#
# Idempotent: running twice back-to-back produces a byte-identical file.
# updated: is the MAX stage_updated across WP overviews (ISO date compare),
#   never the wall-clock date — guarantees idempotency.
#
# Exit 0 on success. Exit non-zero only on a genuinely unreadable feature dir.

set -uo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: sdd-rollup.sh <feature-dir>" >&2
    exit 1
fi

FEATURE_DIR="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1")"

if [[ ! -d "$FEATURE_DIR" ]]; then
    echo "ERROR: feature dir not found: $FEATURE_DIR" >&2
    exit 1
fi

FEATURE_OVERVIEW="${FEATURE_DIR}/overview.md"
if [[ ! -f "$FEATURE_OVERVIEW" ]]; then
    echo "ERROR: feature overview.md not found: $FEATURE_OVERVIEW" >&2
    exit 1
fi

OUTPUT="${FEATURE_DIR}/todo.md"

# ── Delegate all YAML-aware logic to Python ──────────────────────────────────

python3 - "$FEATURE_DIR" "$OUTPUT" <<'PYEOF'
import sys
import os
import re
import datetime
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not available. Install with: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)

feature_dir = Path(sys.argv[1])
output_path = Path(sys.argv[2])

# ── Clobber guard: never overwrite a hand-maintained todo.md ─────────────────
# A pre-existing todo.md without `generated: true` frontmatter is not ours.
if output_path.exists():
    try:
        head = output_path.read_text(encoding='utf-8')[:2000]
    except OSError:
        head = ''
    if not re.search(r'^generated:\s*true\s*$', head, re.MULTILINE):
        print(f"WARN: {output_path} exists and is not generated (no "
              f"'generated: true' frontmatter) — refusing to overwrite a "
              f"hand-maintained file. Move its content aside (e.g. "
              f"open-items.md) to adopt the generated rollup.", file=sys.stderr)
        sys.exit(0)

# ── Frontmatter parser ────────────────────────────────────────────────────────

def parse_frontmatter(path: Path):
    """Return (fm_dict, body_lines) or (None, []) on failure.
    fm_dict has string values (quotes stripped).
    body_lines is the list of lines after the closing --- separator."""
    try:
        text = path.read_text(encoding='utf-8')
    except OSError:
        return None, []
    lines = text.split('\n')
    if not lines or lines[0].strip() != '---':
        return None, []
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            end = i
            break
    if end is None:
        return None, []
    fm_text = '\n'.join(lines[1:end])
    try:
        fm = yaml.safe_load(fm_text) or {}
    except yaml.YAMLError:
        return None, []
    # Normalise all scalar values to strings, strip surrounding quotes.
    # PyYAML parses bare YYYY-MM-DD values as datetime.date — convert those too.
    for k, v in list(fm.items()):
        if v is None:
            fm[k] = ''
        elif isinstance(v, (datetime.date, datetime.datetime)):
            fm[k] = v.isoformat()[:10]
        elif isinstance(v, (bool, int, float)):
            fm[k] = str(v)
        elif isinstance(v, str):
            fm[k] = v.strip().strip("'\"")
    body_lines = lines[end + 1:]
    return fm, body_lines

# ── Feature overview ──────────────────────────────────────────────────────────

feature_ov = feature_dir / 'overview.md'
feat_fm, _ = parse_frontmatter(feature_ov)
if feat_fm is None:
    print(f"ERROR: cannot parse {feature_ov}", file=sys.stderr)
    sys.exit(1)

feature_name  = feat_fm.get('name', feature_dir.name)
feature_title = feat_fm.get('title', feature_name)
feature_updated = feat_fm.get('updated') or feat_fm.get('created') or ''

# ── Collect WP dirs (sorted lexically for determinism) ───────────────────────

wp_dirs = sorted(
    [d for d in feature_dir.iterdir()
     if d.is_dir() and re.match(r'^wp-\d+', d.name)],
    key=lambda d: d.name
)

# ── Parse each WP ────────────────────────────────────────────────────────────

class WPInfo:
    __slots__ = ('name', 'title', 'status', 'stage_updated', 'open_items')
    def __init__(self, name, title, status, stage_updated, open_items):
        self.name = name
        self.title = title
        self.status = status
        self.stage_updated = stage_updated
        self.open_items = open_items  # list of strings (final bullet lines)

def collect_bullets(body_lines: list, heading: str, prefix: str = '') -> list:
    """Collect bullet lines under `heading` in `body_lines`.
    prefix is prepended to each bullet (e.g. 'Blocked: ').
    Returns lines starting with '- ' or '  - ' that are non-empty/non-placeholder."""
    collecting = False
    bullets = []
    heading_re = re.compile(r'^#{1,6}\s+' + re.escape(heading) + r'\s*$')
    next_heading_re = re.compile(r'^#{1,6}\s+')
    placeholder_re = re.compile(
        r'^\s*-\s*\(?\s*(none|nothing|n/?a)\s*\.?\)?\s*$', re.IGNORECASE
    )
    for line in body_lines:
        if heading_re.match(line.rstrip()):
            collecting = True
            continue
        if collecting:
            if next_heading_re.match(line) and not line.startswith('#' * 7):
                # Another heading ends the section
                break
            # Accept top-level bullets: '- ...' or '  - ...'
            if re.match(r'^( {0,3}-| {1,3} {0,2}-)\s+\S', line):
                stripped = line.strip()
                if placeholder_re.match(stripped):
                    continue
                # Normalise to a plain '- ...' bullet, optionally with prefix
                bullet_content = re.sub(r'^-\s+', '', stripped)
                bullets.append(f'- {prefix}{bullet_content}')
    return bullets

wps = []
for wp_dir in wp_dirs:
    ov_path = wp_dir / 'overview.md'
    if not ov_path.exists():
        continue
    ov_fm, _ = parse_frontmatter(ov_path)
    if ov_fm is None:
        continue

    wp_name         = ov_fm.get('name', wp_dir.name)
    wp_title        = ov_fm.get('title', wp_name)
    wp_status       = ov_fm.get('status', '')
    wp_stage_upd    = ov_fm.get('stage_updated', '')

    # Collect open items from WP todo.md (if present)
    open_bullets = []
    todo_path = wp_dir / 'todo.md'
    if todo_path.exists():
        _, todo_body = parse_frontmatter(todo_path)
        if todo_body is None:
            todo_body = []
        open_bullets += collect_bullets(todo_body, 'Open Items')
        open_bullets += collect_bullets(todo_body, 'Blocked On', prefix='Blocked: ')

    wps.append(WPInfo(
        name=wp_name,
        title=wp_title,
        status=wp_status,
        stage_updated=wp_stage_upd,
        open_items=open_bullets,
    ))

# ── Determine updated: date (MAX stage_updated, never wall-clock) ─────────────

def is_iso_date(s: str) -> bool:
    return bool(s and re.match(r'^\d{4}-\d{2}-\d{2}$', s))

candidate_dates = [w.stage_updated for w in wps if is_iso_date(w.stage_updated)]
if candidate_dates:
    updated_date = max(candidate_dates)
elif is_iso_date(feature_updated):
    updated_date = feature_updated
else:
    updated_date = ''

# ── Build ## Status Rollup table ──────────────────────────────────────────────

status_rows = []
for w in wps:
    status_rows.append(f'| {w.name} | {w.status} |')

status_table = (
    '| WP | Status |\n'
    '|---|---|\n'
    + '\n'.join(status_rows)
) if status_rows else '_(no work packages found)_'

# ── Build ## Open Items section ───────────────────────────────────────────────

open_sections = []
for w in wps:
    if w.open_items:
        open_sections.append(f'### {w.name}\n' + '\n'.join(w.open_items))

if open_sections:
    open_items_body = '\n\n'.join(open_sections)
else:
    open_items_body = '_No open items._'

# ── Assemble output ───────────────────────────────────────────────────────────

updated_line = f'updated: {updated_date}' if updated_date else 'updated: ""'

output_text = f"""\
---
name: {feature_name}-todo
title: {feature_title} — open items (auto-generated)
feature: {feature_name}
{updated_line}
generated: true
---

<!-- AUTO-GENERATED by sdd-rollup.sh — do not hand-edit. Status is DERIVED from each
     wp-*/overview.md status:. Regenerate: sdd-rollup.sh {feature_dir} -->

## Status Rollup

{status_table}

## Open Items

{open_items_body}
"""

# ── Write only if changed (supports idempotency check) ───────────────────────
try:
    existing = output_path.read_text(encoding='utf-8') if output_path.exists() else None
except OSError:
    existing = None

if existing != output_text:
    output_path.write_text(output_text, encoding='utf-8')

sys.exit(0)
PYEOF
