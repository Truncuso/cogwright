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

Archived features are ALWAYS loaded (by directory existence under `_archived/`,
overview.md optional) so that edges pointing into the archive RESOLVE;
`--include-archived` is render-only -- it decides whether archived features get
their own register row / tier slot. Edges whose endpoint resolves to neither a
live nor an archived feature are reported as DANGLING, never dropped silently.

Usage:
  goalforge-plan-index.py [--plans-root <root>] [--include-archived] [-o <file>]
  (no -o => writes <PLANS_ROOT>/INDEX.md; '-' => stdout)

Exit: 0 ok (clean DAG) | 2 usage | 3 no features found | 4 cycle detected
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

DEP_KINDS = {"follows", "depends_on"}  # target must precede this feature
INV_KINDS = {"enables", "blocks"}      # this feature precedes target
# Same set as goalforge-validate.sh / goalforge-stamp-tables.sh / goalforge-status.sh
ARCHIVE_DIRS = ("_archived", "_archive")


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


def _dep_slug(raw) -> str:
    """Normalize one edge target. Mirrors goalforge-validate.sh resolve_dep_slug:
    unwrap nested 1-elem lists (`[[x]]` parses to `[['x']]`), strip the
    `[[wikilink]]` brackets and surrounding quotes."""
    while isinstance(raw, list):
        if not raw:
            return ""
        raw = raw[0]
    return re.sub(r"^\[\[|\]\]$", "", str(raw)).strip().strip("'\"")


def _rel_pairs(r: dict):
    """Yield (kind, raw_target) for one `relationships:` item.

    Canonical vocabulary (schema.md, and what goalforge-validate.sh reads) is a
    list of SINGLE-KEY mappings -- `- depends_on: [[other]]`. Also accepted:
    the explicit `{kind|type, feature|target}` mapping form. A `note:` key is
    metadata, never an edge.
    """
    if "target" in r or "feature" in r:
        kind = r.get("kind", r.get("type", ""))
        yield str(kind).strip(), r.get("target", r.get("feature"))
        return
    for k, v in r.items():
        if k == "note":
            continue
        yield str(k).strip(), v


def _norm_edges(feat: str, rels) -> list[tuple[str, str]]:
    """Return forward edges (A -> B = A precedes B) for one feature's rels."""
    edges: list[tuple[str, str]] = []
    if not isinstance(rels, list):
        return edges
    for r in rels:
        if not isinstance(r, dict):
            continue
        for kind, raw in _rel_pairs(r):
            if kind not in DEP_KINDS and kind not in INV_KINDS:
                continue
            # a list value declares several targets: `- requires: [a, b]`
            raws = raw if isinstance(raw, list) else [raw]
            for one in raws:
                target = _dep_slug(one)
                if not target:
                    continue
                if kind in DEP_KINDS:
                    edges.append((target, feat))
                else:
                    edges.append((feat, target))
    return edges


def _read_fm(path: Path) -> dict:
    return _load_yaml(_split_frontmatter(path.read_text(encoding="utf-8", errors="replace")))


def collect(root: Path) -> tuple[dict, list, list]:
    """Return ({feature: {status,title,archived}}, [forward edges], [dangling edges]).

    Archived features are ALWAYS collected so edges into the archive resolve --
    an archived feature is a completed dependency, not a missing one. Presence is
    keyed on DIRECTORY existence under `_archived/` (overview.md is optional:
    legacy archived features predate it); non-directory entries are ignored.
    A live feature always wins over an archived homonym.
    """
    feats: dict = {}
    edges: list[tuple[str, str]] = []
    for ov in sorted(root.glob("*/overview.md")):
        feats_name = ov.parent.name
        fm = _read_fm(ov)
        name = str(fm.get("feature") or fm.get("name") or feats_name).strip()
        feats[name] = {
            "status": str(fm.get("status", "?")).strip(),
            "title": str(fm.get("title", "")).strip(),
            "archived": False,
        }
        edges.extend(_norm_edges(name, fm.get("relationships")))
    for arch_name in ARCHIVE_DIRS:
        arch = root / arch_name
        if not arch.is_dir():
            continue
        for entry in sorted(arch.iterdir()):
            if entry.name.startswith((".", "_")):
                continue  # infrastructure dirs (e.g. _scratch), not archived features
            if not entry.is_dir():
                continue
            ov = entry / "overview.md"
            fm = _read_fm(ov) if ov.is_file() else {}
            name = str(fm.get("feature") or entry.name).strip()
            if name and name not in feats:
                feats[name] = {
                    "status": "archived",
                    "title": str(fm.get("title", "")).strip(),
                    "archived": True,
                }
    # an edge whose endpoint is no known feature (live or archived) is DANGLING
    dangling = [(a, b) for (a, b) in edges if a not in feats or b not in feats]
    edges = [(a, b) for (a, b) in edges if a in feats and b in feats]
    return feats, sorted(set(edges)), sorted(set(dangling))


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


def render(root: Path, feats: dict, visible: dict, edges: list, tier_list: list,
           cycle: list, dangling: list) -> str:
    """Render INDEX.md. `feats` is every resolvable node (incl. archived);
    `visible` is the subset that gets rows/tiers (all of `feats` under
    --include-archived, the live features otherwise)."""
    dep_of: dict = {f: [] for f in feats}
    for a, b in edges:
        dep_of[b].append(a)
    L = []
    L.append("# Plans -- Index & Dependency Graph (DERIVED)")
    L.append("")
    L.append("- **Status:** reference (generated by `goalforge-plan-index.py`)")
    L.append(f"- **Features:** {len(visible)}  |  **edges:** {len(edges)}"
             + (f"  |  **dangling:** {len(dangling)}" if dangling else ""))
    L.append("")
    L.append("> Generated from each `overview.md` `relationships:` frontmatter -- DO NOT hand-edit;")
    L.append("> re-run the generator. Edges normalized to forward (A -> B = A precedes B).")
    L.append("")
    L.append("## Feature register")
    L.append("")
    L.append("| Feature | Status | depends on (precedes it) |")
    L.append("|---------|--------|--------------------------|")
    for f in sorted(visible):
        deps = ", ".join(f"{d} (archived)" if feats[d]["archived"] else d
                         for d in sorted(dep_of[f])) or "--"
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
    orphans = sorted([f for f in visible
                      if not dep_of[f] and all(f != a for a, _ in edges)])
    if orphans:
        L.append("## Orphans (no edges in or out)")
        L.append("")
        L.append(", ".join(orphans))
        L.append("")
    if dangling:
        L.append("## Dangling edges (target resolves to no feature)")
        L.append("")
        L.append("Neither a live feature nor an archived one -- fix the `relationships:`")
        L.append("frontmatter (typo, renamed feature, or a plan that was deleted rather")
        L.append("than archived).")
        L.append("")
        for a, b in dangling:
            missing = " + ".join(x for x in (a, b) if x not in feats)
            L.append(f"- `{a}` -> `{b}` (missing: {missing})")
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
        print(f"goalforge-plan-index: plans root not found: {root}", file=sys.stderr)
        return 2

    feats, edges, dangling = collect(root)
    # --include-archived is RENDER-only: archived nodes always participate in edge
    # resolution above, and only get their own row/tier slot when asked for.
    visible = {f: v for f, v in feats.items() if args.include_archived or not v["archived"]}
    if not visible:
        print(f"goalforge-plan-index: no features under {root}", file=sys.stderr)
        return 3
    tier_list, cycle = tiers(visible, [(a, b) for (a, b) in edges
                                       if a in visible and b in visible])
    out = render(root, feats, visible, edges, tier_list, cycle, dangling)

    dest = args.output or str(root / "INDEX.md")
    if dest == "-":
        sys.stdout.write(out)
    else:
        Path(dest).write_text(out, encoding="utf-8")
        print(f"goalforge-plan-index: wrote {dest} ({len(visible)} features, {len(edges)} edges"
              + (f", {len(dangling)} dangling" if dangling else "") + ")",
              file=sys.stderr)
    return 4 if cycle else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
