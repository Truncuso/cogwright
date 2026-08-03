#!/usr/bin/env bash
# goalforge-frontier.sh — harden-frontier scheduler for an SDD feature.
#
# Usage:
#   goalforge-frontier.sh <feature-path>     emit frontier JSON on stdout (schema below)
#   goalforge-frontier.sh --self-test
#
# Reads each <feature-path>/wp-*/overview.md frontmatter (status, depends_on,
# parallel) and emits a single JSON object:
#   {"hardenable": ["<wp-slug>", ...],
#    "blocked":    [{"wp": "<wp-slug>", "waiting_on": ["<dep-slug>", ...]}, ...],
#    "deadlock":   true|false}
#
# Definitions (deterministic):
#   hardenable — WP status == spec AND every depends_on slug resolves to a sibling
#                WP with status in {verified, archived} (harden threshold = deps all
#                dep-satisfying, distinct from the execute threshold of ready+).
#   blocked    — WP status == spec with >=1 depends_on not yet dep-satisfying;
#                waiting_on lists exactly those not-yet-dep-satisfying dep slugs.
#   deadlock   — hardenable empty AND >=1 WP non-terminal (spec|hardened) AND no WP
#                in-flight toward verification (none at hardened|ready|executing).
#
# `parallel` is metadata for the caller's wave scheduling; it NEVER filters the
# hardenable set. This script NEVER writes any file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

usage() {
    sed -n '2,22p' "$SELF" | sed 's/^# \{0,1\}//'
}

# ── Emit frontier JSON for one feature dir ──────────────────────────────────
frontier() {
    python3 - "$1" <<'PY'
import sys, re, json
from pathlib import Path
try:
    import yaml
except ImportError:
    sys.stderr.write("ERROR: PyYAML not available (pip3 install pyyaml)\n"); sys.exit(1)

feature_dir = Path(sys.argv[1])
if not feature_dir.is_dir():
    sys.stderr.write("ERROR: feature dir not found: %s\n" % feature_dir); sys.exit(1)

def parse_fm(path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i; break
    if end is None:
        return None
    try:
        fm = yaml.safe_load("\n".join(lines[1:end])) or {}
    except yaml.YAMLError:
        return None
    return fm if isinstance(fm, dict) else None

def norm_slug(raw):
    """Strip [[wikilink]] wrappers + surrounding quotes from a dep ref."""
    return re.sub(r"^\[\[|\]\]$", "", str(raw)).strip().strip("'\"")

# Collect WP dirs (sorted by folder name for deterministic output).
wp_dirs = sorted([d for d in feature_dir.iterdir()
                  if d.is_dir() and re.match(r"^wp-\d+", d.name)],
                 key=lambda d: d.name)

wps = []                 # (slug, status, [dep_slug, ...])
status_by_slug = {}
for d in wp_dirs:
    ov = d / "overview.md"
    if not ov.exists():
        continue
    fm = parse_fm(ov)
    if fm is None:
        continue
    slug = str(fm.get("name") or d.name).strip()
    status = str(fm.get("status", "")).strip()
    deps_raw = fm.get("depends_on") or []
    if not isinstance(deps_raw, list):
        deps_raw = [deps_raw]
    deps = [norm_slug(x) for x in deps_raw if norm_slug(x)]
    wps.append((slug, status, deps))
    status_by_slug[slug] = status
    status_by_slug[d.name] = status     # also resolvable by folder name

# A dep counts as satisfied when it resolves to a sibling at one of these
# statuses. `archived` is a second WP terminal set only by an out-of-band edit —
# no goalforge script writes it to a WP (references/state-machine.md) — and it
# satisfies a dependency exactly as `verified` does.
DEP_SATISFIED = ("verified", "archived")

hardenable = []
blocked = []
for slug, status, deps in wps:
    if status != "spec":
        continue
    unverified = [dep for dep in deps if status_by_slug.get(dep) not in DEP_SATISFIED]
    if not unverified:
        hardenable.append(slug)
    else:
        blocked.append({"wp": slug, "waiting_on": unverified})

all_statuses = [s for (_sl, s, _d) in wps]
hardenable_empty = (len(hardenable) == 0)
has_nonterminal = any(s in ("spec", "hardened") for s in all_statuses)
has_inflight = any(s in ("hardened", "ready", "executing") for s in all_statuses)
deadlock = bool(hardenable_empty and has_nonterminal and not has_inflight)

hardenable.sort()
blocked.sort(key=lambda b: b["wp"])

print(json.dumps({"hardenable": hardenable, "blocked": blocked, "deadlock": deadlock}))
PY
}

# ── Self-test ────────────────────────────────────────────────────────────────
_ST_TMP=""
self_test() {
    local t_pass=0 t_fail=0 d out h dl b
    _ST_TMP="$(mktemp -d)"
    trap '[[ -n "${_ST_TMP:-}" ]] && rm -rf "$_ST_TMP"' EXIT
    d="$_ST_TMP"

    mkwp() {  # $1 feature-dir  $2 wp-slug(=folder)  $3 status  $4 depends_on-yaml
        mkdir -p "$1/$2"
        cat > "$1/$2/overview.md" <<EOF
---
name: $2
title: $2
status: $3
stage_updated: 2026-06-23
severity: LOW
parallel: false
depends_on: $4
plan: $(basename "$1")
---

# $2
EOF
    }

    local ok no
    ok() { echo "$1: PASS"; t_pass=$((t_pass+1)); }
    no() { echo "$1: FAIL"; t_fail=$((t_fail+1)); }

    echo "=== goalforge-frontier.sh --self-test ==="

    # (1) linear chain: wp-01-a verified, wp-02-b spec deps [wp-01-a] → hardenable [wp-02-b]
    mkwp "$d/linear" wp-01-a verified "[]"
    mkwp "$d/linear" wp-02-b spec     "[wp-01-a]"
    out="$(bash "$SELF" "$d/linear")"
    h="$(echo "$out" | command jq -c '.hardenable')"
    if [[ "$h" == '["wp-02-b"]' ]]; then
        ok "linear-chain"
    else
        no "linear-chain (hardenable=$h)"
    fi

    # (2) parallel frontier: wp-01-a verified; wp-02-b + wp-03-c spec deps [wp-01-a]
    mkwp "$d/parallel" wp-01-a verified "[]"
    mkwp "$d/parallel" wp-02-b spec     "[wp-01-a]"
    mkwp "$d/parallel" wp-03-c spec     "[wp-01-a]"
    out="$(bash "$SELF" "$d/parallel")"
    h="$(echo "$out" | command jq -c '.hardenable | sort')"
    if [[ "$h" == '["wp-02-b","wp-03-c"]' ]]; then
        ok "parallel-frontier"
    else
        no "parallel-frontier (hardenable=$h)"
    fi

    # (3) unverified-deps exclusion: dep at `ready` (not verified) → excluded + blocked
    mkwp "$d/unverified" wp-01-a ready "[]"
    mkwp "$d/unverified" wp-02-b spec  "[wp-01-a]"
    out="$(bash "$SELF" "$d/unverified")"
    h="$(echo "$out" | command jq -c '.hardenable')"
    if [[ "$h" == '[]' ]] \
       && echo "$out" | command jq -e '.blocked[] | select(.wp=="wp-02-b") | .waiting_on==["wp-01-a"]' >/dev/null; then
        ok "unverified-deps-excluded"
    else
        no "unverified-deps-excluded (hardenable=$h blocked=$(echo "$out" | command jq -c '.blocked'))"
    fi

    # (4) deadlock: 2-WP cycle → hardenable [], deadlock true
    mkwp "$d/deadlock" wp-01-a spec "[wp-02-b]"
    mkwp "$d/deadlock" wp-02-b spec "[wp-01-a]"
    out="$(bash "$SELF" "$d/deadlock")"
    h="$(echo "$out" | command jq -c '.hardenable')"
    dl="$(echo "$out" | command jq -c '.deadlock')"
    if [[ "$h" == '[]' && "$dl" == 'true' ]]; then
        ok "deadlock-cycle"
    else
        no "deadlock-cycle (hardenable=$h deadlock=$dl)"
    fi

    # (5) archived dep satisfies: wp-01-a archived, wp-02-b spec deps [wp-01-a]
    #     → hardenable [wp-02-b], blocked []. `archived` is the second WP
    #     terminal and is dep-satisfying exactly as `verified`.
    mkwp "$d/archdep" wp-01-a archived "[]"
    mkwp "$d/archdep" wp-02-b spec     "[wp-01-a]"
    out="$(bash "$SELF" "$d/archdep")"
    h="$(echo "$out" | command jq -c '.hardenable')"
    b="$(echo "$out" | command jq -c '.blocked')"
    if [[ "$h" == '["wp-02-b"]' && "$b" == '[]' ]]; then
        ok "archived-dep-satisfies"
    else
        no "archived-dep-satisfies (hardenable=$h blocked=$b)"
    fi

    echo ""
    echo "Results: $t_pass passed, $t_fail failed"
    [[ "$t_fail" -eq 0 ]]
}

# ── Argument parsing ─────────────────────────────────────────────────────────
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
    echo "ERROR: usage: goalforge-frontier.sh <feature-path>" >&2
    exit 1
fi

FEATURE_DIR="$(cd "${POS[0]}" 2>/dev/null && pwd)" \
    || { echo "ERROR: feature path not found: ${POS[0]}" >&2; exit 1; }

frontier "$FEATURE_DIR"
