#!/usr/bin/env bash
# goalforge-feature-hash.sh — deterministic hash of a feature's STRUCTURE + GOALS.
#
# Single source of the Tier-1 feature-audit freshness key (schema.md §Tier-1
# feature audit). The hash covers exactly what warrants a re-audit:
#   1. sorted WP slugs
#   2. each WP's depends_on (sorted)
#   3. each WP's raw `goal:` block (trailing-ws-stripped, LF-normalized)
#   4. the spec's `## Interface Contract` section text
#
# Usage:   goalforge-feature-hash.sh <feature-dir>
# Output:  the 12-char hex hash on stdout (exit 0), or an error on stderr (exit 2).
# Zero-breakage: a feature with no WPs / no spec still hashes (over whatever
# exists), so callers never crash on a partially-decomposed feature.
set -euo pipefail

FEATURE_DIR="${1:-}"
if [ -z "$FEATURE_DIR" ] || [ ! -d "$FEATURE_DIR" ]; then
  echo "goalforge-feature-hash: feature dir not found: ${FEATURE_DIR:-<missing>}" >&2
  exit 2
fi

python3 - "$FEATURE_DIR" <<'PY'
import hashlib, sys
from pathlib import Path

feature_dir = Path(sys.argv[1])


def frontmatter_lines(text):
    """Return the lines between the first two '---' fences (the YAML block)."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return []
    for i, ln in enumerate(lines[1:], 1):
        if ln.strip() == "---":
            return lines[1:i]
    return []


def norm(lines):
    """Trailing-whitespace-stripped, LF-joined — matches goal_approved_version."""
    return "\n".join(l.rstrip() for l in lines)


def extract_goal_block(fm_lines):
    """Raw `goal:` block: from a top-level `goal:` key to the next top-level key."""
    out, in_block = [], False
    for ln in fm_lines:
        if ln.startswith("goal:"):
            in_block = True
            out.append(ln)
            continue
        if in_block:
            # a non-indented, non-blank line that is a new top-level key ends it
            if ln and not ln[0].isspace() and not ln.startswith("#"):
                break
            out.append(ln)
    return out


def extract_depends_on(fm_lines):
    """Best-effort: parse a `depends_on: [a, b]` inline list (sorted)."""
    for ln in fm_lines:
        s = ln.strip()
        if s.startswith("depends_on:"):
            val = s[len("depends_on:"):].strip()
            val = val.strip("[]")
            items = [x.strip().strip("'\"") for x in val.split(",") if x.strip()]
            return sorted(items)
    return []


def interface_contract(spec_text):
    """The `## Interface Contract` section body (until the next H2 / EOF)."""
    lines = spec_text.splitlines()
    out, capture = [], False
    for ln in lines:
        if ln.startswith("## "):
            if capture:
                break
            capture = ln.strip().lower().startswith("## interface contract")
            continue
        if capture:
            out.append(ln)
    return norm(out)


parts = []

wp_dirs = sorted(
    p for p in feature_dir.glob("wp-*") if (p / "overview.md").is_file()
)
parts.append("WPS\n" + "\n".join(p.name for p in wp_dirs))

for wp in wp_dirs:
    fm = frontmatter_lines((wp / "overview.md").read_text(encoding="utf-8"))
    parts.append(f"DEPENDS:{wp.name}\n" + "\n".join(extract_depends_on(fm)))
    parts.append(f"GOAL:{wp.name}\n" + norm(extract_goal_block(fm)))

spec = feature_dir / "spec.md"
if spec.is_file():
    parts.append("IFC\n" + interface_contract(spec.read_text(encoding="utf-8")))

canonical = "\n\x1e\n".join(parts)  # record-separator joins; stable across runs
print(hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:12])
PY
