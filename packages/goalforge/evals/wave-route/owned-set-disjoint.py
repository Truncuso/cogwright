#!/usr/bin/env python3
"""Pairwise owned-set disjointness check for wave-route dispatch briefs.

Feature-level planning-fan-out safety primitive (wp-07 A-SEAM): given N
concurrent dispatch briefs, flag any two whose `owned:` sets collide. The
owned/off-limits fields, ownership rule, and return-as-DATA contract live in
skills/goalforge/references/dispatch-template.md — this script enforces the one
net-new invariant that file (declaration) cannot: pairwise disjointness across a
concurrent set. Enforcement is declaration-time only ([risk-accepted]); no
runtime write guard.

Collision is GLOB-SEMANTIC, not literal-string: owned-set entries are path
globs (`plans/feature-a/**`, or a bare file path), so two entries collide when
their covered path-trees overlap — equal prefixes, OR one prefix an ancestor of
the other (`plans/feature-a/**` covers `plans/feature-a/sub/**`). A literal
set-intersection would miss such nested-glob collisions; this check normalizes
each entry to its non-glob prefix and tests path-boundary containment both ways.

Usage:  owned-set-disjoint.py BRIEF ...   (2+ brief files)
Exit 0 + "DISJOINT" when every pair is disjoint; exit 1 + "OVERLAP ..." lines
naming each colliding pair and the colliding entries.
"""
import sys


def parse_owned(path):
    """Return the set of paths under a brief's top-level `owned:` block.

    Collects `- <path>` items following an `owned:` line, stopping at the next
    non-indented key. Inline `# ...` comments and surrounding whitespace are
    stripped.
    """
    owned = set()
    in_block = False
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            stripped = line.strip()
            if not in_block:
                if stripped == "owned:" or stripped.startswith("owned:"):
                    in_block = True
                continue
            # In block: a non-indented, non-empty line ends it (next top key).
            if line and not line[0].isspace():
                break
            if not stripped or stripped.startswith("#"):
                continue
            if stripped.startswith("-"):
                item = stripped[1:].strip()
                item = item.split("#", 1)[0].strip()  # drop inline comment
                if item:
                    owned.add(item)
    return owned


def glob_prefix(pattern):
    """Normalize a glob entry to the non-glob path prefix it covers.

    Strips trailing `**` / `/**` glob segments and surrounding slashes so
    `plans/feature-a/**` → `plans/feature-a` and a bare file path is returned
    unchanged. An empty result means the entry covers the whole tree (root).
    """
    p = pattern.strip().rstrip("/")
    while p.endswith("**"):
        p = p[:-2].rstrip("/")
    return p


def covers(ancestor, other):
    """True when path-prefix `ancestor` covers `other` (path-boundary aware)."""
    if ancestor == "":
        return True  # root prefix covers everything
    return other == ancestor or other.startswith(ancestor + "/")


def entries_collide(pat_a, pat_b):
    """True when two owned-set glob entries cover overlapping path-trees."""
    a, b = glob_prefix(pat_a), glob_prefix(pat_b)
    return covers(a, b) or covers(b, a)


def colliding_entries(set_a, set_b):
    """Return sorted "a≍b" strings for every cross-set colliding entry pair."""
    hits = set()
    for pa in set_a:
        for pb in set_b:
            if entries_collide(pa, pb):
                hits.add(f"{pa}~{pb}")
    return sorted(hits)


def main(argv):
    briefs = argv[1:]
    if len(briefs) < 2:
        print("usage: owned-set-disjoint.py BRIEF BRIEF [BRIEF ...]", file=sys.stderr)
        return 2
    sets = {p: parse_owned(p) for p in briefs}
    for p, s in sets.items():
        if not s:
            print(f"EMPTY owned-set in {p} (malformed brief)", file=sys.stderr)
            return 2
    overlaps = []
    names = list(sets)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            a, b = names[i], names[j]
            shared = colliding_entries(sets[a], sets[b])
            if shared:
                overlaps.append((a, b, shared))
    if overlaps:
        for a, b, shared in overlaps:
            print(f"OVERLAP {a} {b}: {' '.join(shared)}")
        return 1
    print("DISJOINT")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
