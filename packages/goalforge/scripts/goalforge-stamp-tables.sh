#!/usr/bin/env bash
# goalforge-stamp-tables.sh — sync SDD status tables to frontmatter truth (lossless).
#
# Usage:
#   goalforge-stamp-tables.sh <feature-dir>      # one feature
#   goalforge-stamp-tables.sh --all <plans-root> # every feature under <plans-root>
#   goalforge-stamp-tables.sh --check <target>   # dry-run: exit 1 if any table is stale
#
# For the feature-overview `## Work Packages` table and each WP-overview
# `## Tasks` table, this rewrites ONLY the Status cell of each data row — the one
# column goalforge-validate.sh actually checks — to the referenced file's `status:`
# frontmatter (the single source of truth). Rows whose id resolves to no file
# (e.g. table-only tasks that were never expanded into task-NN files) are LEFT
# UNTOUCHED and reported on stderr — never dropped: the table may be the only
# home that data has. Status values are simple enums, so this is idempotent and
# safe. Everything else is preserved byte-for-byte: titles (free text that may
# contain `|`), prose preambles before the table, UNKNOWN extra columns (e.g. a
# `Tasks` count), backtick formatting, column count, and all non-table content.
# It never creates a table section and never adds rows (stamp-on-create lives in
# goalforge-decompose).
#
# Locates the table the same way goalforge-validate.sh's parse_status_table does — the
# first table under the header with a `Status` column and a wp/task id column —
# so a regenerated table always satisfies the validator.
set -euo pipefail

MODE="single"
case "${1:-}" in
    --all)   MODE="all";   shift ;;
    --check) MODE="check"; shift ;;
esac
TARGET="${1:?usage: goalforge-stamp-tables.sh [--all|--check] <feature-dir|plans-root>}"
TARGET="$(cd "$TARGET" && pwd)"

python3 - "$MODE" "$TARGET" <<'PY'
import sys, re, pathlib

mode, target = sys.argv[1], pathlib.Path(sys.argv[2])
ARCHIVE = {'_archived', '_archive'}

def parse_fm(path):
    """Top-level scalar frontmatter keys only (skips nested/indented blocks)."""
    try:
        text = path.read_text(encoding='utf-8')
    except OSError:
        return None
    if not text.startswith('---'):
        return {}
    lines = text.split('\n')
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == '---'), None)
    if end is None:
        return {}
    fm = {}
    for ln in lines[1:end]:
        if not ln or ln[0] in ' \t#':
            continue
        m = re.match(r'^([A-Za-z0-9_-]+):\s?(.*)$', ln)
        if m:
            fm[m.group(1)] = m.group(2).strip().strip('\'"')
    return fm

def numkey(name):
    m = re.search(r'-(\d+)', name)
    return (int(m.group(1)) if m else 9999, name)

def clean(cell):
    return cell.strip().strip('`').strip()

def _table_at(lines, i):
    """If lines[i] is a markdown table header row + separator, return
    (header_idx, first_data_idx, end_idx); else None."""
    if i + 1 >= len(lines):
        return None
    head, sep = lines[i].strip(), lines[i + 1].strip()
    if head.startswith('|') and sep.startswith('|') and not (set(sep) - set('|-: ')):
        k = i + 2
        while k < len(lines) and lines[k].strip().startswith('|'):
            k += 1
        return (i, i + 2, k)
    return None

def _sig_match(lines, hidx, id_headers):
    """True if the table header row has a Status column AND an id column in
    `id_headers` — the signature of a status table we own."""
    cols = [clean(c).lower() for c in cells_of(lines[hidx])]
    return 'status' in cols and any(c in id_headers for c in cols)

def find_table(lines, header, id_headers=None):
    """(header_idx, first_data_idx, end_idx) of the status table to stamp, or None.
    First tries the table under `## header` (scanning past prose, stopping at the
    next header). If that section is absent and `id_headers` is given, falls back
    to the first table whose columns match the status+id signature — WP-overview
    task tables in practice carry no `## Tasks` header. Code fences are skipped so
    a pipe-shaped line inside a ``` block is never mistaken for the table."""
    hi = next((i for i, ln in enumerate(lines)
               if re.match(r'^#{2,}\s+' + re.escape(header) + r'\s*$', ln)), None)
    if hi is not None:
        i = hi + 1
        while i + 1 < len(lines):
            if re.match(r'^#{1,6}\s+\S', lines[i]):
                break
            loc = _table_at(lines, i)
            if loc:
                return loc
            i += 1
    if id_headers is None:
        return None
    in_fence = False
    i = 0
    while i < len(lines):
        s = lines[i].lstrip()
        if s.startswith('```') or s.startswith('~~~'):
            in_fence = not in_fence
            i += 1
            continue
        if not in_fence:
            loc = _table_at(lines, i)
            if loc:
                if _sig_match(lines, loc[0], id_headers):
                    return loc
                i = loc[2]
                continue
        i += 1
    return None

def cells_of(row):
    """Split a row into inner cells, preserving each cell's spacing."""
    parts = row.split('|')
    if parts and parts[0].strip() == '':
        parts = parts[1:]
    if parts and parts[-1].strip() == '':
        parts = parts[:-1]
    return parts

def set_cell(cell, value):
    """Replace a cell's value, preserving backtick wrapping + single-space pad.
    A literal `|` would break the row on re-parse, so encode it as the HTML
    entity (renders as a pipe). Status enums never contain `|`; this is defensive."""
    value = str(value).replace('|', '&#124;')
    s = cell.strip()
    wrap = len(s) >= 2 and s.startswith('`') and s.endswith('`')
    return ' %s ' % (('`%s`' % value) if wrap else value)

def regen_one(path, header, id_headers, resolve):
    """Update each row's Status cell to frontmatter `status:` + drop orphan rows in
    the table under `## header`. resolve(row_id) -> status str | None. Returns new
    file text if it changed, else None."""
    text = path.read_text(encoding='utf-8')
    lines = text.split('\n')
    loc = find_table(lines, header, id_headers)
    if loc is None:
        return None
    hidx, first, end = loc
    headers = [clean(c).lower() for c in cells_of(lines[hidx])]
    if 'status' not in headers:
        return None
    id_idx = next((j for j, h in enumerate(headers) if h in id_headers), None)
    if id_idx is None:
        return None
    status_idx = headers.index('status')

    new_rows = []
    for r in range(first, end):
        cells = cells_of(lines[r])
        if len(cells) <= max(id_idx, status_idx):
            new_rows.append(lines[r])                  # malformed — leave as-is
            continue
        row_id = clean(cells[id_idx])
        if not row_id:
            continue                                   # drop empty-id placeholder
        status = resolve(row_id)
        if status is None:
            # No backing file (table-only row, or a genuinely removed id).
            # The table may be the only home this data has — keep, warn.
            print(f"WARN: {path}: row '{row_id}' has no backing file — "
                  f"left untouched", file=sys.stderr)
            new_rows.append(lines[r])
            continue
        if status_idx != id_idx:
            cells[status_idx] = set_cell(cells[status_idx], status)
        new_rows.append('|' + '|'.join(cells) + '|')

    new_block = lines[:first] + new_rows + lines[end:]
    new_text = '\n'.join(new_block)
    return new_text if new_text != text else None

def task_resolver(wp_dir):
    def resolve(row_id):
        m = re.match(r'(task-\d+)', row_id)
        if not m:
            return None
        files = [t for t in wp_dir.glob('task-*.md') if t.name.startswith(m.group(1))]
        if not files:
            return None
        fm = parse_fm(files[0])
        return fm.get('status', '') if fm is not None else None
    return resolve

def wp_resolver(feature_dir):
    def resolve(row_id):
        ov = feature_dir / row_id / 'overview.md'
        if not ov.exists():
            m = re.match(r'(wp-\d+)', row_id)
            cand = ([d for d in feature_dir.glob('wp-*')
                     if d.is_dir() and d.name.startswith(m.group(1))] if m else [])
            if not cand:
                return None
            ov = cand[0] / 'overview.md'
        fm = parse_fm(ov)
        return fm.get('status', '') if fm is not None else None
    return resolve

def stamp_feature(feature_dir, check):
    changed = []
    ov = feature_dir / 'overview.md'
    if ov.exists():
        new = regen_one(ov, 'Work Packages', {'wp', 'work package'}, wp_resolver(feature_dir))
        if new is not None:
            changed.append(ov)
            if not check:
                ov.write_text(new, encoding='utf-8')
    for wp in sorted((d for d in feature_dir.glob('wp-*') if d.is_dir()),
                     key=lambda p: numkey(p.name)):
        wov = wp / 'overview.md'
        if not wov.exists():
            continue
        new = regen_one(wov, 'Tasks', {'task'}, task_resolver(wp))
        if new is not None:
            changed.append(wov)
            if not check:
                wov.write_text(new, encoding='utf-8')
    return changed

def is_feature(d):
    return d.is_dir() and d.name not in ARCHIVE and not d.name.startswith('_') \
        and (d / 'overview.md').exists()

if mode == 'single':
    features = [target]
else:
    features = ([target] if is_feature(target)
                else [d for d in sorted(target.iterdir()) if is_feature(d)])

changed = []
for f in features:
    changed += stamp_feature(f, check=(mode == 'check'))

if mode == 'check':
    if changed:
        print(f"STALE: {len(changed)} table(s) differ from frontmatter:")
        for p in changed:
            print(f"  {p}")
        sys.exit(1)
    print("OK: all status tables match frontmatter.")
    sys.exit(0)

for p in changed:
    print(f"stamped {p}")
print(f"goalforge-stamp-tables: {len(changed)} table(s) regenerated.")
PY
