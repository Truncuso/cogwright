#!/usr/bin/env python3
"""goalforge-plan-index.py -- derive plans/INDEX.md from feature-overview frontmatter.

Harvests each <PLANS_ROOT>/<feature>/overview.md frontmatter (status + typed
`relationships:` edges) and emits a single INDEX.md: a feature register, a
cross-feature dependency DAG normalized to forward edges, topological build-order
tiers, plus cycle and orphan detection. The frontmatter is the single source of
truth -- the index is DERIVED, never hand-synced (idea:
sdd-plan-index-and-portfolio-housekeeping).

Edge normalization (all -> "A must come before B"):
  B follows A      => A -> B
  B depends_on A   => A -> B
  A enables B      => A -> B
`part_of` is recorded as a grouping note, not a build-order edge.

Usage:
  goalforge-plan-index.py [--plans-root <root>] [--include-archived] [-o <file>]
  (no -o => writes <PLANS_ROOT>/INDEX.md; '-' => stdout)

Exit: 0 ok (clean DAG) | 2 usage | 3 no features found | 4 cycle detected
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

DEP_KINDS = {"follows", "depends_on"}  # target must precede this feature
INV_KINDS = {"enables"}                # this feature precedes target


def _split_frontmatter(text: str) -> str:
    """Return the YAML frontmatter block (between the first two '---' lines)."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return ""
    out: list[str] = []
    for line in lines[1:]:
        if line.strip() == "---":
            break
        out.append(line)
    return "\n".join(out)


def _load_yaml(block: str) -> dict:
    try:
        import yaml  # type: ignore

        data = yaml.safe_load(block)
        return data if isinstance(data, dict) else {}
    except Exception:
        return _mini_parse(block)


def _mini_parse(block: str) -> dict:
    """Tolerant fallback parser for the exact overview schema (no PyYAML).

    Handles top-level scalars and a `relationships:` list of `{kind, feature}`
    mappings -- enough to build the index without a YAML dependency.
    """
    data: dict = {}
    rels: list[dict] = []
    in_rels = False
    cur: dict | None = None
    for raw in block.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip())
        s = raw.strip()
        if indent == 0 and s.endswith(":") and s[:-1] == "relationships":
            in_rels = True
            continue
        if indent == 0 and ":" in s:
            in_rels = False
            k, _, v = s.partition(":")
            data[k.strip()] = v.strip()
            continue
        if in_rels:
            if s.startswith("- "):
                if cur:
                    rels.append(cur)
                cur = {}
                s = s[2:].strip()
            if cur is not None and ":" in s:
                k, _, v = s.partition(":")
                cur[k.strip()] = v.strip()
    if cur:
        rels.append(cur)
    if rels:
        data["relationships"] = rels
    return data


def _norm_edges(feat: str, rels) -> list[tuple[str, str]]:
    """Return forward edges (A -> B = A precedes B) for one feature's rels."""
    edges: list[tuple[str, str]] = []
    if not isinstance(rels, list):
        return edges
    for r in rels:
        if not isinstance(r, dict):
            continue
        kind = str(r.get("kind", "")).strip()
        target = str(r.get("feature", "")).strip().strip("[]")
        if not target:
            continue
        if kind in DEP_KINDS:
            edges.append((target, feat))
        elif kind in INV_KINDS:
            edges.append((feat, target))
    return edges


def collect(root: Path, include_archived: bool) -> tuple[dict, list]:
    """Return ({feature: {status,title}}, [forward edges])."""
    feats: dict = {}
    edges: list[tuple[str, str]] = []
    for ov in sorted(root.glob("*/overview.md")):
        feats_name = ov.parent.name
        fm = _load_yaml(_split_frontmatter(ov.read_text(encoding="utf-8", errors="replace")))
        name = str(fm.get("feature") or fm.get("name") or feats_name).strip()
        feats[name] = {
            "status": str(fm.get("status", "?")).strip(),
            "title": str(fm.get("title", "")).strip(),
        }
        edges.extend(_norm_edges(name, fm.get("relationships")))
    if include_archived:
        arch = root / "_archived"
        for ov in sorted(arch.glob("*/overview.md")) if arch.is_dir() else []:
            name = ov.parent.name
            fm = _load_yaml(_split_frontmatter(ov.read_text(encoding="utf-8", errors="replace")))
            feats[str(fm.get("feature") or name).strip()] = {
                "status": "archived",
                "title": str(fm.get("title", "")).strip(),
            }
    # keep only edges whose endpoints are known features
    edges = [(a, b) for (a, b) in edges if a in feats and b in feats]
    return feats, sorted(set(edges))


def tiers(feats: dict, edges: list) -> tuple[list, list]:
    """Kahn topological tiers. Returns (tiers, remaining-cycle-nodes)."""
    indeg = {f: 0 for f in feats}
    adj: dict = {f: [] for f in feats}
    for a, b in edges:
        adj[a].append(b)
        indeg[b] += 1
    layer = sorted([f for f in feats if indeg[f] == 0])
    out: list[list[str]] = []
    seen = 0
    while layer:
        out.append(layer)
        seen += len(layer)
        nxt: set = set()
        for f in layer:
            for b in adj[f]:
                indeg[b] -= 1
                if indeg[b] == 0:
                    nxt.add(b)
        layer = sorted(nxt)
    remaining = sorted([f for f in feats if indeg[f] > 0]) if seen < len(feats) else []
    return out, remaining


def render(root: Path, feats: dict, edges: list, tier_list: list, cycle: list) -> str:
    dep_of: dict = {f: [] for f in feats}
    for a, b in edges:
        dep_of[b].append(a)
    L = []
    L.append("# Plans -- Index & Dependency Graph (DERIVED)")
    L.append("")
    L.append("- **Status:** reference (generated by `goalforge-plan-index.py`)")
    L.append(f"- **Features:** {len(feats)}  |  **edges:** {len(edges)}")
    L.append("")
    L.append("> Generated from each `overview.md` `relationships:` frontmatter -- DO NOT hand-edit;")
    L.append("> re-run the generator. Edges normalized to forward (A -> B = A precedes B).")
    L.append("")
    L.append("## Feature register")
    L.append("")
    L.append("| Feature | Status | depends on (precedes it) |")
    L.append("|---------|--------|--------------------------|")
    for f in sorted(feats):
        deps = ", ".join(sorted(dep_of[f])) or "--"
        L.append(f"| {f} | {feats[f]['status']} | {deps} |")
    L.append("")
    L.append("## Build order (dependency tiers)")
    L.append("")
    if tier_list:
        for i, layer in enumerate(tier_list):
            L.append(f"- **Tier {i}:** {' / '.join(layer)}")
    else:
        L.append("- (no features)")
    L.append("")
    if cycle:
        L.append("## WARNING -- dependency cycle")
        L.append("")
        L.append("These features form a cycle (not topologically orderable): "
                 + ", ".join(cycle))
        L.append("")
    orphans = sorted([f for f in feats
                      if not dep_of[f] and all(f != a for a, _ in edges)])
    if orphans:
        L.append("## Orphans (no edges in or out)")
        L.append("")
        L.append(", ".join(orphans))
        L.append("")
    return "\n".join(L) + "\n"


def main(argv) -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--plans-root", default="")
    ap.add_argument("--include-archived", action="store_true")
    ap.add_argument("-o", "--output", default="")
    args = ap.parse_args(argv)

    root = args.plans_root or os.environ.get("SDD_PLANS_DIR", "")
    if not root:
        gr = os.popen("git rev-parse --show-toplevel 2>/dev/null").read().strip()
        if gr and (Path(gr) / "plans").is_dir():
            root = str(Path(gr) / "plans")
        elif (Path.cwd() / "plans").is_dir():
            root = str(Path.cwd() / "plans")
        else:
            root = str(Path.home() / ".claude" / "plans")
    root = Path(root).resolve()
    if not root.is_dir():
        print(f"sdd-plan-index: plans root not found: {root}", file=sys.stderr)
        return 2

    feats, edges = collect(root, args.include_archived)
    if not feats:
        print(f"sdd-plan-index: no features under {root}", file=sys.stderr)
        return 3
    tier_list, cycle = tiers(feats, edges)
    out = render(root, feats, edges, tier_list, cycle)

    dest = args.output or str(root / "INDEX.md")
    if dest == "-":
        sys.stdout.write(out)
    else:
        Path(dest).write_text(out, encoding="utf-8")
        print(f"sdd-plan-index: wrote {dest} ({len(feats)} features, {len(edges)} edges)",
              file=sys.stderr)
    return 4 if cycle else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
