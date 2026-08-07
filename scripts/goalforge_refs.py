"""Reference-token grammar for goalforge markdown — one definition, two anchors.

The same authored prose is checked in two trees: `scripts/goalforge-generate.sh`
extracts refs from the GENERATED plugin tree to emit
`plugins/goalforge/references/reference-manifest.json`, and `scripts/ci-lints.sh`
section `package-refs` extracts them from the authored package tree. The grammar
is defined here once so the two can never drift apart.

Grammar (spec goalforge-plugin-correctness §Interface Contract, pinned):
a ref is a path token inside a backtick- or link-quoted span. The span is split
into whitespace-delimited fields and EVERY field starting with one of
REF_PREFIXES (package-side additionally SKILL_DIR_PREFIXES) is a ref, so both a
quoted invocation (`hooks/foo.sh --check`) and an interpreter-prefixed one
(`bash ${CLAUDE_PLUGIN_ROOT}/scripts/x.sh --flag`) yield the path they name. A
token carrying a shell glob metacharacter (`*`, `?`, `[`) or a trailing `/` is a
pattern or a directory, not a ref.

Anchors: `${CLAUDE_PLUGIN_ROOT}` and `skills/` anchor at the tree root; any
other bare prefix inside a child skill resolves against the child dir first and
falls back to the tree root; `${CLAUDE_SKILL_DIR}` anchors at the child dir
(so `../x` climbs to the tree root). A token that normalizes OUTSIDE the tree
root is a violation, never a silent drop: it resolves to `<ESCAPE_MARKER>:<tok>`
so both consumers see it — the lint reports it as a dangling-style row, the
manifest emitter refuses to emit.

CLI (used by ci-lints.sh):
    goalforge_refs.py scan --root <dir> --ignore <file> [--package] [--skip-top a,b]
        prints one `<0|1>\t<from>::<path>` line per ref, 1 = the path exists.
    goalforge_refs.py ignores --root <dir> --ignore <file> [--package] [--skip-top a,b]
        prints one line per ignore entry that suppressed NOTHING in that scan
        (a dead entry — the scoped address it names no longer occurs).
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

# Resolution result for a token that climbs out of the tree being checked.
ESCAPE_MARKER = "!escape"

_QUOTED_RE = re.compile(r"`([^`\n]+)`|\]\(([^)\s]+)\)")


def ref_tokens(text, prefixes=REF_PREFIXES):
    """Yield every path token in `text` per the pinned grammar."""
    for m in _QUOTED_RE.finditer(text):
        span = (m.group(1) if m.group(1) is not None else m.group(2)).strip()
        for tok in span.split():
            if not tok.startswith(prefixes):
                continue
            if tok.endswith("/") or any(c in tok for c in "*?["):
                continue
            yield tok


def resolve_ref(root, child_rel, tok, skills_prefix="skills/"):
    """Root-relative target of `tok` named from a file owned by `child_rel`.

    `child_rel` is the root-relative directory of the source file's child skill
    (`skills/<child>` plugin-side, `<child>` package-side), or None for a file
    at the tree root. `skills_prefix` is where child skills live in this tree —
    `skills/` in the plugin, flat (``) in the package — so a `skills/<child>/x`
    token lands on the same file in both. A `${CLAUDE_PLUGIN_ROOT}/skills/<seg>`
    token re-anchors only when `<seg>` is really a child skill (`<seg>/SKILL.md`
    exists under `root`); otherwise it stays raw. A token that climbs out of
    the tree resolves to `<ESCAPE_MARKER>:<tok>` — a violation both consumers must see,
    never a silent drop. Returns None only for a degenerate token naming the
    tree root itself.
    """
    if tok.startswith(SKILL_DIR_PREFIXES):
        rest = tok.split("/", 1)[1] if "/" in tok else ""
        cands = ["%s/%s" % (child_rel, rest) if child_rel else rest]
    elif tok.startswith("${CLAUDE_PLUGIN_ROOT}"):
        rest = tok[len("${CLAUDE_PLUGIN_ROOT}"):].lstrip("/")
        # `${CLAUDE_PLUGIN_ROOT}/skills/<child>/x` names the same file as the
        # bare `skills/<child>/x` token, so it re-anchors through
        # `skills_prefix` too — flat package-side, `skills/` plugin-side.
        # Without this an authored command file (packages/goalforge/commands/,
        # shipped verbatim) would read as dangling package-side only. The strip
        # is gated on the first segment really being a child skill, so a
        # non-child `skills/<x>/…` address stays raw instead of colliding with a
        # same-named top-level dir.
        stripped = rest[len("skills/"):] if rest.startswith("skills/") else ""
        seg = stripped.split("/", 1)[0]
        if seg and os.path.isfile(os.path.join(root, seg, "SKILL.md")):
            cands = [skills_prefix + stripped]
        else:
            cands = [rest]
    elif tok.startswith("skills/"):
        cands = [skills_prefix + tok[len("skills/"):]]
    else:
        cands = ["%s/%s" % (child_rel, tok)] if child_rel else []
        cands.append(tok)
    fallback = None
    escaped = False
    for cand in cands:
        norm = posixpath.normpath(cand)
        if norm.startswith(".."):
            escaped = True
            continue
        if norm in (".", ""):
            continue
        if os.path.exists(os.path.join(root, *norm.split("/"))):
            return norm
        fallback = norm
    if fallback is not None:
        return fallback
    return "%s:%s" % (ESCAPE_MARKER, tok) if escaped else None


def load_ignore_list(path):
    """Deliberate exceptions — addresses outside the tree being checked.

    Applied at GENERATION time for the manifest, so the emitted file holds only
    refs expected to resolve and its consumers need no ignore-list of their own.

    Entries are SCOPED, `<from-rel-path>::<token-pattern>` (the shape the
    baseline files already use): an exception suppresses one address named from
    one known set of files, never that address everywhere. The bare legacy
    format is rejected — an unscoped entry silences refs nobody adjudicated.
    """
    pats = []
    try:
        with open(path, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "::" not in line:
                    raise ValueError(
                        "%s:%d: unscoped ignore entry %r — entries are "
                        "`<from-rel-path>::<token-pattern>`" % (path, lineno, line))
                frm, _, tok = line.partition("::")
                pats.append((frm, tok))
    except FileNotFoundError:
        pass
    return pats


def ignored(pats, frm, *cands, used=None):
    """True when a scoped entry covers `cands` named from file `frm`.

    `used` (optional set) collects the entries that fired, so a caller can fail
    on an entry that suppressed nothing at all.
    """
    hit = False
    for pat in pats:
        frm_pat, tok_pat = pat
        if not fnmatch.fnmatchcase(frm, frm_pat):
            continue
        for cand in cands:
            if cand and (fnmatch.fnmatchcase(cand, tok_pat)
                         or cand.startswith(tok_pat)):
                if used is None:
                    return True
                used.add(pat)
                hit = True
                break
    return hit


def collect_refs(root, child_of, prefixes=REF_PREFIXES, ignore_pats=(),
                 skip_top=(), skills_prefix="skills/", used_ignores=None):
    """Sorted, de-duplicated (from, path) refs over every `.md` under `root`.

    `child_of` maps a root-relative file path to its child-skill dir or None;
    `skip_top` names top-level entries to leave out of the walk entirely;
    `used_ignores` (optional set) collects the ignore entries that fired.
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
            try:
                with open(os.path.join(base, name), encoding="utf-8",
                          newline="") as fh:
                    text = fh.read()
            except UnicodeDecodeError:
                continue
            for tok in ref_tokens(text, prefixes):
                if ignored(ignore_pats, rel, tok, used=used_ignores):
                    continue
                target = resolve_ref(root, child_of(rel), tok, skills_prefix)
                if target is None:
                    continue
                if ignored(ignore_pats, rel, target, used=used_ignores):
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
    ap.add_argument("command", choices=["scan", "ignores"])
    ap.add_argument("--root", required=True)
    ap.add_argument("--ignore", default="")
    ap.add_argument("--package", action="store_true",
                    help="package-tree anchors + ${CLAUDE_SKILL_DIR} grammar")
    ap.add_argument("--skip-top", default="",
                    help="comma-separated top-level entries to leave out")
    args = ap.parse_args(argv)

    root = args.root
    if not os.path.isdir(root):
        sys.stderr.write("goalforge_refs: not a directory: %s\n" % root)
        return 2
    pats = load_ignore_list(args.ignore) if args.ignore else []
    skip_top = {s for s in args.skip_top.split(",") if s}
    if args.package:
        prefixes = REF_PREFIXES + SKILL_DIR_PREFIXES
        child_of = package_child_of(root)
        skills_prefix = ""
    else:
        prefixes = REF_PREFIXES
        child_of = plugin_child_of
        skills_prefix = "skills/"
    used = set()
    refs = collect_refs(root, child_of, prefixes, pats, skip_top=skip_top,
                        skills_prefix=skills_prefix, used_ignores=used)
    if args.command == "ignores":
        for frm_pat, tok_pat in pats:
            if (frm_pat, tok_pat) not in used:
                sys.stdout.write("%s::%s\n" % (frm_pat, tok_pat))
        return 0
    for frm, path in refs:
        exists = (not path.startswith(ESCAPE_MARKER + ":")
                  and os.path.exists(os.path.join(root, *path.split("/"))))
        sys.stdout.write("%d\t%s::%s\n" % (1 if exists else 0, frm, path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
