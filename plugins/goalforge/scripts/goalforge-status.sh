#!/usr/bin/env bash
# goalforge-status.sh — read-only tree printer: feature → WPs → tasks.
#
# Usage:
#   goalforge-status.sh [--feature <slug>] [--json] [<plans-dir>]
#
# Prints a status-annotated tree of the plans directory by reading
# frontmatter `status:` fields. Replaces gsd-stats and folder-ls.
# With --json, emits the same feature→WP→task tree as deterministic JSON
# (the Plan-IR producer surface; no timestamps, stable ordering).
# Read-only: never writes any file.

set -uo pipefail

PLANS_DIR=""
FEATURE_FILTER=""
JSON_OUT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --feature) FEATURE_FILTER="$2"; shift 2 ;;
        --json)    JSON_OUT=1; shift ;;
        -*)        echo "Unknown flag: $1" >&2; exit 1 ;;
        *)         PLANS_DIR="$1"; shift ;;
    esac
done

# Resolve PLANS_DIR when no explicit arg was given:
#   1. SDD_PLANS_DIR env var
#   2. <git-toplevel>/plans/ if inside a git repo, or <CWD>/plans/ if plans/ exists
#   3. ~/.claude/plans (global fallback)
if [[ -z "$PLANS_DIR" ]]; then
    if [[ -n "${SDD_PLANS_DIR:-}" ]]; then
        PLANS_DIR="$SDD_PLANS_DIR"
    else
        GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || true
        if [[ -n "$GIT_ROOT" ]]; then
            PLANS_DIR="${GIT_ROOT}/plans"
        elif [[ -d "$(pwd)/plans" ]]; then
            PLANS_DIR="$(pwd)/plans"
        else
            PLANS_DIR="${HOME}/.claude/plans"
        fi
    fi
fi

PLANS_DIR=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$PLANS_DIR" 2>/dev/null) || exit 1

if [ ! -d "$PLANS_DIR" ]; then
    echo "ERROR: plans dir not found: $PLANS_DIR" >&2
    exit 1
fi

python3 - "$PLANS_DIR" "$FEATURE_FILTER" "$JSON_OUT" <<'PYEOF'
import sys
import os
import re
import json
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not available. Install with: pip3 install pyyaml", file=sys.stderr)
    sys.exit(1)

plans_dir      = Path(sys.argv[1])
feature_filter = sys.argv[2]  # empty string = no filter
json_out       = sys.argv[3] == '1'

# ── ANSI color codes ────────────────────────────────────────────────────────

RESET  = '\033[0m'
BOLD   = '\033[1m'
DIM    = '\033[2m'

STATUS_COLOR = {
    'draft':      '\033[90m',   # dark grey
    'spec':       '\033[36m',   # cyan
    'hardened':   '\033[34m',   # blue
    'ready':      '\033[32m',   # green
    'executing':  '\033[33m',   # yellow
    'verified':   '\033[92m',   # bright green
    'archived':   '\033[90m',   # dark grey
    'pending':    '\033[90m',   # dark grey
    'briefed':    '\033[36m',   # cyan
    'in-progress':'\033[33m',   # yellow
    'active':     '\033[33m',   # yellow
    'completed':  '\033[92m',   # bright green
}

STATUS_SYMBOL = {
    'draft':       '○',
    'spec':        '◐',
    'hardened':    '◑',
    'ready':       '●',
    'executing':   '▶',
    'verified':    '✓',
    'archived':    '⌀',
    'pending':     '○',
    'briefed':     '◐',
    'in-progress': '▶',
    'active':      '▶',
    'completed':   '✓',
}

def colorize(status):
    color = STATUS_COLOR.get(status, '')
    sym   = STATUS_SYMBOL.get(status, '?')
    return f"{color}{sym} {status}{RESET}"

# ── Frontmatter parser ──────────────────────────────────────────────────────

def parse_frontmatter(path: Path):
    try:
        text = path.read_text(encoding='utf-8')
    except OSError:
        return {}
    lines = text.split('\n')
    if not lines or lines[0].strip() != '---':
        return {}
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            end = i
            break
    if end is None:
        return {}
    try:
        return yaml.safe_load('\n'.join(lines[1:end])) or {}
    except yaml.YAMLError:
        return {}

# ── Tree traversal → in-memory model ─────────────────────────────────────────

def as_list(v):
    """Coerce a frontmatter scalar/None/list into a list of strings."""
    if v is None:
        return []
    if isinstance(v, (list, tuple)):
        return [str(x) for x in v]
    return [str(v)]

# Each feature is a sub-directory of plans_dir
feature_dirs = sorted(
    d for d in plans_dir.iterdir()
    if d.is_dir() and not d.name.startswith('.')
)

features = []  # the model both renderers read from

for feat_dir in feature_dirs:
    feat_overview = feat_dir / 'overview.md'
    feat_fm = parse_frontmatter(feat_overview) if feat_overview.exists() else {}
    feat_name = feat_fm.get('name', feat_dir.name)

    # Apply feature filter (matches frontmatter name OR directory name)
    if feature_filter and feat_name != feature_filter and feat_dir.name != feature_filter:
        continue

    work_packages = []
    wp_dirs = sorted(
        d for d in feat_dir.iterdir()
        if d.is_dir() and re.match(r'^wp-\d+', d.name)
    )
    for wp_dir in wp_dirs:
        wp_overview = wp_dir / 'overview.md'
        wp_fm = parse_frontmatter(wp_overview) if wp_overview.exists() else {}

        tasks = []
        for t in sorted(wp_dir.glob('task-*.md')):
            t_fm = parse_frontmatter(t)
            tasks.append({
                'slug':   t_fm.get('name', t.stem),
                'title':  t_fm.get('title', ''),
                'status': t_fm.get('status', '?'),
            })

        work_packages.append({
            'slug':       wp_fm.get('name', wp_dir.name),
            'title':      wp_fm.get('title', ''),
            'status':     wp_fm.get('status', '?'),
            'depends_on': as_list(wp_fm.get('depends_on')),  # list of WP slugs
            'parallel':   bool(wp_fm.get('parallel', False)),  # boolean: may run in parallel
            'tasks':      tasks,
        })

    features.append({
        'slug':         feat_name,
        'title':        feat_fm.get('title', ''),
        'status':       feat_fm.get('status', '?'),
        'workPackages': work_packages,
    })

# ── JSON renderer (Plan-IR producer surface) ─────────────────────────────────

if json_out:
    print(json.dumps({
        'planIrVersion': '0.1',
        'plansDir':      str(plans_dir),
        'features':      features,
    }, indent=2, ensure_ascii=False))
    sys.exit(0)

# ── Tree renderer (human, ANSI) ──────────────────────────────────────────────

if not feature_dirs:
    print(f"(no feature directories found in {plans_dir})")
    sys.exit(0)

if feature_filter and not features:
    print(f"(no feature matching '{feature_filter}' found in {plans_dir})")
    sys.exit(1)

for feat in features:
    label = f"{BOLD}{feat['slug']}{RESET}"
    if feat['title']:
        label += f"  {DIM}{feat['title']}{RESET}"
    print(f"\n{label}")
    print(f"  status: {colorize(feat['status'])}")

    for wp in feat['workPackages']:
        label = f"{wp['slug']}"
        if wp['title']:
            label += f"  {DIM}{wp['title']}{RESET}"
        print(f"  ├─ {label}")
        print(f"  │   status: {colorize(wp['status'])}")

        tasks = wp['tasks']
        for i, t in enumerate(tasks):
            connector = '└─' if i == len(tasks) - 1 else '├─'
            t_label = t['slug']
            if t['title']:
                t_label += f"  {DIM}{t['title']}{RESET}"
            print(f"  │   {connector} {t_label}")
            print(f"  │   {'   ' if i == len(tasks) - 1 else '│  '}  status: {colorize(t['status'])}")
PYEOF
