"""Reference-token grammar for goalforge markdown — one definition, two anchors.

The same authored prose is checked in two trees: `scripts/goalforge-generate.sh`
extracts refs from the GENERATED plugin tree to emit
`plugins/goalforge/references/reference-manifest.json`, and `scripts/ci-lints.sh`
section `package-refs` extracts them from the authored package tree. The grammar
is defined here once so the two can never drift apart.

Grammar (spec goalforge-plugin-correctness §Interface Contract, pinned):
a ref is a backtick- or link-quoted path token starting with one of
REF_PREFIXES (package-side additionally SKILL_DIR_PREFIXES). The path is the
first whitespace-delimited field of the quoted span, so a quoted invocation
(`hooks/foo.sh --check`) still yields the path it names. A token carrying a
shell glob metacharacter (`*`, `?`, `[`) or a trailing `/` is a pattern or a
directory, not a ref.

Anchors: `${CLAUDE_PLUGIN_ROOT}` and `skills/` anchor at the tree root; any
other bare prefix inside a child skill resolves against the child dir first and
falls back to the tree root; `${CLAUDE_SKILL_DIR}` anchors at the child dir
(so `../x` climbs to the tree root).

CLI (used by ci-lints.sh):
    goalforge_refs.py scan --root <dir> --ignore <file> [--package]
prints one `<0|1>\t<from>::<path>` line per ref, 1 = the path exists.
"""
import argparse
import fnmatch
import os
import posixpath
import re
import sys

REF_PREFIXES = ("${CLAUDE_PLUGIN_ROOT}", "skills/", "scripts/",
                "references/", "hooks/", "commands/")
SKILL_DIR_PREFIXES = ("${CLAUDE_SKILL_DIR}", "$CLAUDE_SKILL_DIR")

_QUOTED_RE = re.compile(r"`([^`\n]+)`|\]\(([^)\s]+)\)")


def ref_tokens(text, prefixes=REF_PREFIXES):
    """Yield every path token in `text` per the pinned grammar."""
    for m in _QUOTED_RE.finditer(text):
        span = (m.group(1) if m.group(1) is not None else m.group(2)).strip()
        if not span.startswith(prefixes):
            continue
        tok = span.split()[0]
        if tok.endswith("/") or any(c in tok for c in "*?["):
            continue
        yield tok


def resolve_ref(root, child_rel, tok, skills_prefix="skills/"):
    """Root-relative target of `tok` named from a file owned by `child_rel`.

    `child_rel` is the root-relative directory of the source file's child skill
    (`skills/<child>` plugin-side, `<child>` package-side), or None for a file
    at the tree root. `skills_prefix` is where child skills live in this tree —
    `skills/` in the plugin, flat (``) in the package — so a `skills/<child>/x`
    token lands on the same file in both. Returns None when the token resolves
    outside the tree.
    """
    if tok.startswith(SKILL_DIR_PREFIXES):
        rest = tok.split("/", 1)[1] if "/" in tok else ""
        cands = ["%s/%s" % (child_rel, rest) if child_rel else rest]
    elif tok.startswith("${CLAUDE_PLUGIN_ROOT}"):
        cands = [tok[len("${CLAUDE_PLUGIN_ROOT}"):].lstrip("/")]
    elif tok.startswith("skills/"):
        cands = [skills_prefix + tok[len("skills/"):]]
    else:
        cands = ["%s/%s" % (child_rel, tok)] if child_rel else []
        cands.append(tok)
    fallback = None
    for cand in cands:
        norm = posixpath.normpath(cand)
        if norm in (".", "") or norm.startswith(".."):
            continue
        if os.path.exists(os.path.join(root, *norm.split("/"))):
            return norm
        fallback = norm
    return fallback


def load_ignore_list(path):
    """Deliberate exceptions — addresses outside the tree being checked.

    Applied at GENERATION time for the manifest, so the emitted file holds only
    refs expected to resolve and its consumers need no ignore-list of their own.
    """
    pats = []
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#"):
                    pats.append(line)
    except FileNotFoundError:
        pass
    return pats


def ignored(pats, *cands):
    for pat in pats:
        for cand in cands:
            if cand and (fnmatch.fnmatchcase(cand, pat) or cand.startswith(pat)):
                return True
    return False


def collect_refs(root, child_of, prefixes=REF_PREFIXES, ignore_pats=(),
                 skip_top=(), skills_prefix="skills/"):
    """Sorted, de-duplicated (from, path) refs over every `.md` under `root`.

    `child_of` maps a root-relative file path to its child-skill dir or None;
    `skip_top` names top-level entries to leave out of the walk entirely.
    """
    refs = set()
    for base, dirs, files in os.walk(root):
        rel_dir = os.path.relpath(base, root)
        top = rel_dir.split(os.sep)[0] if rel_dir != "." else ""
        if top in skip_top:
            dirs[:] = []
            continue
        for name in files:
            if not name.endswith(".md"):
                continue
            rel = os.path.relpath(os.path.join(base, name), root)
            rel = rel.replace(os.sep, "/")
            with open(os.path.join(base, name), encoding="utf-8",
                      newline="") as fh:
                text = fh.read()
            for tok in ref_tokens(text, prefixes):
                if ignored(ignore_pats, tok):
                    continue
                target = resolve_ref(root, child_of(rel), tok, skills_prefix)
                if target is None or ignored(ignore_pats, target):
                    continue
                refs.add((rel, target))
    return sorted(refs)


def plugin_child_of(rel):
    """Plugin tree: skills/<child>/... owns <child>."""
    parts = rel.split("/")
    return "skills/" + parts[1] if len(parts) >= 3 and parts[0] == "skills" else None


def package_child_of(root):
    """Package tree: a top-level dir holding a SKILL.md is a child skill."""
    children = {
        d for d in os.listdir(root)
        if os.path.isfile(os.path.join(root, d, "SKILL.md"))
    }

    def _of(rel):
        parts = rel.split("/")
        return parts[0] if len(parts) >= 2 and parts[0] in children else None

    return _of


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("command", choices=["scan"])
    ap.add_argument("--root", required=True)
    ap.add_argument("--ignore", default="")
    ap.add_argument("--package", action="store_true",
                    help="package-tree anchors + ${CLAUDE_SKILL_DIR} grammar")
    args = ap.parse_args(argv)

    root = args.root
    if not os.path.isdir(root):
        sys.stderr.write("goalforge_refs: not a directory: %s\n" % root)
        return 2
    pats = load_ignore_list(args.ignore) if args.ignore else []
    if args.package:
        prefixes = REF_PREFIXES + SKILL_DIR_PREFIXES
        child_of = package_child_of(root)
        skills_prefix = ""
    else:
        prefixes = REF_PREFIXES
        child_of = plugin_child_of
        skills_prefix = "skills/"
    for frm, path in collect_refs(root, child_of, prefixes, pats,
                                  skills_prefix=skills_prefix):
        exists = os.path.exists(os.path.join(root, *path.split("/")))
        sys.stdout.write("%d\t%s::%s\n" % (1 if exists else 0, frm, path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
