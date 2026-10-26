#!/usr/bin/env bash
# goalforge-feature-hash.sh — deterministic hash of a WP's CONTRACT SLICE.
#
# wp-01 (T5) narrows this from a whole-feature structure+goals hash to a
# per-WP hash over only the `## Interface Contract` subsections the WP
# frontmatter's `contract_slice:` list names (C1-C7, spec.md Interface
# Contract). Re-audit is now scoped to the contract text a WP actually
# depends on, not the whole feature's WP graph — a sibling WP's goal edit
# no longer trips this hash.
#
# The hash covers exactly:
#   1. the WP's `contract_slice:` list (sorted, as recorded)
#   2. for each named slice id (e.g. `C2`), the body of the spec.md
#      `### C<n> — ...` subsection under `## Interface Contract`
#      (trailing-ws-stripped, LF-normalized)
#
# Usage:   goalforge-feature-hash.sh <wp-dir>
# Output:  the 12-char hex hash on stdout (exit 0), or an error on stderr (exit 2).
# Zero-breakage: a WP with no `contract_slice:` or no spec.md still hashes
# (over whatever exists), so callers never crash on a partially-decomposed
# feature or a fast-path WP with no spec.md.
set -euo pipefail

WP_DIR="${1:-}"
if [ -z "$WP_DIR" ] || [ ! -d "$WP_DIR" ]; then
  echo "goalforge-feature-hash: WP dir not found: ${WP_DIR:-<missing>}" >&2
  exit 2
fi
OVERVIEW="$WP_DIR/overview.md"
if [ ! -f "$OVERVIEW" ]; then
  echo "goalforge-feature-hash: overview.md not found under $WP_DIR" >&2
  exit 2
fi

python3 - "$WP_DIR" "$OVERVIEW" <<'PY'
import hashlib, re, sys
from pathlib import Path

wp_dir = Path(sys.argv[1])
overview_path = Path(sys.argv[2])
feature_dir = wp_dir.parent
spec_path = feature_dir / "spec.md"


def frontmatter_lines(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return []
    for i, ln in enumerate(lines[1:], 1):
        if ln.strip() == "---":
            return lines[1:i]
    return []


def norm(lines):
    return "\n".join(l.rstrip() for l in lines)


def extract_contract_slice(fm_lines):
    """Best-effort: parse a `contract_slice: [C1, C2]` inline list (sorted)."""
    for ln in fm_lines:
        s = ln.strip()
        if s.startswith("contract_slice:"):
            val = s[len("contract_slice:"):].strip()
            val = val.strip("[]")
            items = [x.strip().strip("'\"") for x in val.split(",") if x.strip()]
            return sorted(items)
    return []


def interface_contract_body(spec_text):
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
    return out


def slice_bodies(ic_lines):
    """Map slice id (e.g. 'C2') -> its `### C2 — ...` subsection body."""
    bodies = {}
    current_id, buf = None, []
    header_re = re.compile(r"^### (C\d+)\b")
    for ln in ic_lines:
        m = header_re.match(ln)
        if m:
            if current_id is not None:
                bodies[current_id] = buf
            current_id = m.group(1)
            buf = []
            continue
        if current_id is not None:
            buf.append(ln)
    if current_id is not None:
        bodies[current_id] = buf
    return bodies


overview_text = overview_path.read_text(encoding="utf-8")
fm = frontmatter_lines(overview_text)
slice_ids = extract_contract_slice(fm)

parts = ["SLICE\n" + "\n".join(slice_ids)]

if spec_path.is_file():
    ic_lines = interface_contract_body(spec_path.read_text(encoding="utf-8"))
    bodies = slice_bodies(ic_lines)
    for sid in slice_ids:
        parts.append(f"{sid}\n" + norm(bodies.get(sid, [])))

canonical = "\n\x1e\n".join(parts)  # record-separator joins; stable across runs
print(hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:12])
PY
