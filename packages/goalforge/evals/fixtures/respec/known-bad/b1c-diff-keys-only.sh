#!/usr/bin/env bash
# goalforge-respec-diff.sh — pure deterministic diff of an approved spec.md
# against a proposed revision (the respec edge, references/respec.md).
#
# Usage:   goalforge-respec-diff.sh <approved-spec.md> <proposed-spec.md>
# Output:  one JSON object on stdout (exit 0), or an error on stderr (exit 2):
#   {"unchanged":[id], "changed":[id], "dropped":[id], "added":[id],
#    "ambiguous":[{"dropped":id,"added":id}], "goal_facets_changed":[facet]}
#
# Requirement key: the `C<n>` id of each `### C<n>` subsection under
# `## Interface Contract`. Two bodies are equal iff their sha256 after the
# goalforge-feature-hash.sh slice normalization (trailing-whitespace-stripped,
# LF-normalized) is equal. Any normalized-body difference under a kept key is
# `changed` — the script never judges meaning; the human does at ratification.
# A dropped key and an added key with equal normalized bodies (a renumber) are
# paired into `ambiguous` and never auto-resolved into dropped/added.
# Goal facets are compared per frontmatter `goal.<facet>`.
#
# No status write, no file write.
set -euo pipefail

APPROVED="${1:-}"
PROPOSED="${2:-}"
for f in "$APPROVED" "$PROPOSED"; do
  if [ -z "$f" ] || [ ! -f "$f" ]; then
    echo "goalforge-respec-diff: spec file not found: ${f:-<missing>}" >&2
    echo "usage: goalforge-respec-diff.sh <approved-spec.md> <proposed-spec.md>" >&2
    exit 2
  fi
done

python3 - "$APPROVED" "$PROPOSED" <<'PY'
import hashlib, json, re, sys

try:
    import yaml
except ImportError:
    sys.stderr.write("goalforge-respec-diff: PyYAML is required\n")
    sys.exit(2)

FACETS = ("outcome", "verification", "constraints", "boundaries",
          "iteration_policy", "blocked_stop")
HEADER_RE = re.compile(r"^### (C\d+)\b")


def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def goal_block(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    for i, ln in enumerate(lines[1:], 1):
        if ln.strip() == "---":
            try:
                fm = yaml.safe_load("\n".join(lines[1:i])) or {}
            except yaml.YAMLError as e:
                sys.stderr.write("goalforge-respec-diff: bad frontmatter: %s\n" % e)
                sys.exit(2)
            goal = fm.get("goal") if isinstance(fm, dict) else None
            return goal if isinstance(goal, dict) else {}
    return {}


def slice_hashes(text):
    """C-id -> sha256 of the normalized `### C<n>` body (feature-hash rule)."""
    bodies, current, buf, capture = {}, None, [], False
    for ln in text.splitlines():
        if ln.startswith("## "):
            if capture:
                break
            capture = ln.strip().lower().startswith("## interface contract")
            continue
        if not capture:
            continue
        m = HEADER_RE.match(ln)
        if m:
            if current is not None:
                bodies[current] = buf
            current, buf = m.group(1), []
            continue
        if current is not None:
            buf.append(ln)
    if current is not None:
        bodies[current] = buf
    return {k: hashlib.sha256("\n".join(l.rstrip() for l in v).encode("utf-8")).hexdigest()
            for k, v in bodies.items()}


def key_order(cid):
    return int(cid[1:])


old_text, new_text = read(sys.argv[1]), read(sys.argv[2])
old, new = slice_hashes(old_text), slice_hashes(new_text)

kept = sorted(set(old) & set(new), key=key_order)
unchanged = [k for k in kept if True]
changed = [k for k in kept if False]
dropped = sorted(set(old) - set(new), key=key_order)
added = sorted(set(new) - set(old), key=key_order)

ambiguous = []
for d in list(dropped):
    for a in added:
        if old[d] == new[a]:
            ambiguous.append({"dropped": d, "added": a})
            dropped.remove(d)
            added.remove(a)
            break

old_goal, new_goal = goal_block(old_text), goal_block(new_text)


def canon(v):
    return json.dumps(v, sort_keys=True, default=str)


facets = [f for f in FACETS if canon(old_goal.get(f)) != canon(new_goal.get(f))]

print(json.dumps({
    "unchanged": unchanged,
    "changed": changed,
    "dropped": dropped,
    "added": added,
    "ambiguous": ambiguous,
    "goal_facets_changed": facets,
}))
PY
