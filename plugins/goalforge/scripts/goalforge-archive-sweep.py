#!/usr/bin/env python3
"""goalforge-archive-sweep.py — pre/post-archive hygiene sweep for ONE feature.

Deterministic, READ-ONLY scan of everything that still points at a feature
about to be (or just) archived. Emits a typed JSON report plus a human
summary; it NEVER edits anything — every finding is a proposal for the
owning thread (cross-owned files are listed with their owner, not touched).

Categories:
  ideas         plans/ideas/*.md referencing the feature; terminal ideas
                (promoted/dropped/superseded/archived) -> action: idea-archive,
                live ideas -> action: triage
  feature_refs  other features'/WPs' files referencing <slug>/ — listed with
                the owning feature; never edited here
  handoffs      docs/handoffs/ handoffs at status: ready referencing the
                feature (archived handoffs excluded)
  memory        .memory/ fact files + MEMORY.md pointer lines referencing the
                feature — candidates for a propose-only RESOLVED rewrite
  findings_open the feature's own findings.md unresolved items
                (`- [ ]` checkboxes) — blockers that should be resolved or
                explicitly carried before archiving

Usage:
  goalforge-archive-sweep.py <feature> [--plans-root R] [--docs-root D]
                             [--memory-root M] [--json] [--gate]

Exit: 0 ok | 2 --gate set and findings_open is non-empty | 3 feature not found
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

TERMINAL_IDEA_STATUSES = {"promoted", "dropped", "superseded", "archived"}
OPEN_ITEM_RE = re.compile(r"^\s*-\s*\[ \]\s*(.+)$")


def frontmatter(path: Path) -> dict:
    """Minimal frontmatter reader: `key: value` lines between --- fences."""
    try:
        lines = path.read_text(encoding="utf-8").split("\n")
    except OSError:
        return {}
    if not lines or lines[0].strip() != "---":
        return {}
    fm = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$", line)
        if m:
            fm[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return fm


def mentions(path: Path, slug: str) -> list[tuple[int, str]]:
    """1-indexed (line, text) pairs REFERENCING the feature: a `<slug>/` path
    ref or a `[[<slug>]]` wikilink. Bare-name mentions are deliberately NOT
    matched — for a feature named after a common phrase (agent-dispatch) they
    are almost all prose noise (live run 2026-07-16: 208 memory 'hits')."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return []
    path_needle = slug + "/"
    link_needle = "[[" + slug + "]]"
    out = []
    for i, line in enumerate(text.split("\n"), 1):
        if path_needle in line or link_needle in line:
            out.append((i, line.strip()))
    return out


def path_mentions(path: Path, slug: str) -> list[tuple[int, str]]:
    """Only `<slug>/` PATH references (the kind that dangles after the move)."""
    return [(n, t) for n, t in mentions(path, slug) if slug + "/" in t]


def sweep_ideas(plans: Path, slug: str) -> list[dict]:
    out = []
    ideas = plans / "ideas"
    if not ideas.is_dir():
        return out
    for f in sorted(ideas.glob("*.md")):
        if not mentions(f, slug):
            continue
        fm = frontmatter(f)
        status = fm.get("status", "")
        terminal = status in TERMINAL_IDEA_STATUSES
        out.append({
            "name": fm.get("name", f.stem),
            "path": str(f),
            "status": status,
            "terminal": terminal,
            "action": "idea-archive" if terminal else "triage",
        })
    return out


def sweep_feature_refs(plans: Path, slug: str) -> list[dict]:
    out = []
    for top in sorted(plans.iterdir()):
        if not top.is_dir() or top.name in {slug, "ideas", "_archived"} \
                or top.name.startswith("."):
            continue
        for f in sorted(top.rglob("*.md")):
            for line_no, text in path_mentions(f, slug):
                out.append({
                    "owner": top.name,
                    "path": str(f),
                    "line": line_no,
                    "text": text,
                })
    return out


def sweep_handoffs(docs: Path, slug: str) -> list[dict]:
    out = []
    handoffs = docs / "handoffs"
    if not handoffs.is_dir():
        return out
    for f in sorted(handoffs.rglob("*.md")):
        if "_archived" in f.parts:
            continue
        fm = frontmatter(f)
        if fm.get("status") != "ready":
            continue
        if not mentions(f, slug):
            continue
        out.append({
            "slug": fm.get("slug", f.parent.name),
            "path": str(f),
            "status": "ready",
        })
    return out


def sweep_memory(memory: Path, slug: str) -> list[dict]:
    out = []
    if not memory.is_dir():
        return out
    for f in sorted(memory.rglob("*.md")):
        hits = mentions(f, slug)
        if not hits:
            continue
        if f.name == "MEMORY.md":
            for line_no, text in hits:
                out.append({"kind": "pointer", "path": str(f),
                            "line": line_no, "text": text})
        else:
            out.append({"kind": "fact", "path": str(f),
                        "line": hits[0][0], "text": hits[0][1]})
    return out


def sweep_findings_open(plans: Path, slug: str) -> list[dict]:
    out = []
    feat = plans / slug
    for f in sorted(feat.rglob("findings.md")):
        try:
            lines = f.read_text(encoding="utf-8").split("\n")
        except OSError:
            continue
        for i, line in enumerate(lines, 1):
            m = OPEN_ITEM_RE.match(line)
            if m:
                out.append({"path": str(f), "line": i, "text": m.group(1)})
    return out


def human_summary(slug: str, cats: dict) -> str:
    lines = [f"archive hygiene sweep — {slug}"]
    label = {
        "ideas": "ideas referencing feature",
        "feature_refs": "cross-feature path refs (owned elsewhere — propose only)",
        "handoffs": "ready handoffs referencing feature",
        "memory": "memory facts/pointers referencing feature",
        "findings_open": "OPEN findings items in the feature itself",
    }
    for key, items in cats.items():
        lines.append(f"  {label[key]}: {len(items)}")
        for it in items:
            loc = it.get("path", "")
            if "line" in it:
                loc += f":{it['line']}"
            detail = it.get("action") or it.get("owner") or it.get("slug") \
                or it.get("kind") or ""
            lines.append(f"    - {loc}" + (f"  [{detail}]" if detail else ""))
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("feature")
    ap.add_argument("--plans-root", default=os.path.expanduser("~/.claude/plans"))
    ap.add_argument("--docs-root", default=None,
                    help="default: <plans-root>/../docs")
    ap.add_argument("--memory-root", default=None,
                    help="default: <plans-root>/../.memory")
    ap.add_argument("--json", action="store_true",
                    help="emit the typed JSON report on stdout")
    ap.add_argument("--gate", action="store_true",
                    help="exit 2 when the feature has open findings items")
    args = ap.parse_args()

    plans = Path(args.plans_root).resolve()
    base = plans.parent
    docs = Path(args.docs_root).resolve() if args.docs_root else base / "docs"
    memory = Path(args.memory_root).resolve() if args.memory_root else base / ".memory"
    slug = args.feature

    if not (plans / slug / "overview.md").is_file():
        print(f"archive-sweep: feature not found: {plans / slug}", file=sys.stderr)
        return 3

    cats = {
        "ideas": sweep_ideas(plans, slug),
        "feature_refs": sweep_feature_refs(plans, slug),
        "handoffs": sweep_handoffs(docs, slug),
        "memory": sweep_memory(memory, slug),
        "findings_open": sweep_findings_open(plans, slug),
    }
    report = {
        "feature": slug,
        "plans_root": str(plans),
        "categories": cats,
        "summary": {k: len(v) for k, v in cats.items()},
        "propose_only": True,
    }

    if args.json:
        print(json.dumps(report, indent=2))
        print(human_summary(slug, cats), file=sys.stderr)
    else:
        print(human_summary(slug, cats))

    if args.gate and cats["findings_open"]:
        print(f"archive-sweep GATE: {len(cats['findings_open'])} open findings "
              f"item(s) — resolve or explicitly carry them before archiving.",
              file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
