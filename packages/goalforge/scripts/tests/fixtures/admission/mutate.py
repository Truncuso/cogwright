"""mutate.py — write a deliberately broken COPY of a shipped file.

Each known-bad in goalforge-admission.test.sh is a named, anchored mutation:
the anchor must be present exactly once or the mutation fails loudly, so a
refactor that moves the code under test cannot silently turn a known-bad into
a no-op (a known-bad that no longer sabotages anything is not an oracle).

    python3 mutate.py <name> <source> <destination>

A mutation is one (anchor, replacement) pair, or a list of pairs applied in
order when a known-bad has several conditions (each anchor exactly once).
goalforge-workflow-compile.test.sh drives the wp-08 T8-T12 mutants through its
red() helper against the committed package replica.
"""
import sys

Pair = tuple[str, str]

MUTATIONS: dict[str, Pair | list[Pair]] = {
    # b4 known-bad 1: none-means-skip — an empty table (what the no-flag path
    # reads, the shipped table being empty) skips the admission call.
    "skip-admission-no-flag": (
        '    if role == "implement" and propose_only:',
        '    if role == "implement" and propose_only and admitted:',
    ),
    # b4 known-bad 2: the refused branch leaves the foreign provider in place.
    "keep-refused-provider": (
        '            chosen = native["name"]',
        '            pass  # known-bad: the refused foreign provider survives',
    ),
    # b4 known-bad 3: no native row to fall back to, and the refused row is
    # resolved anyway at exit 0 instead of failing closed.
    "no-native-keeps-foreign": (
        '            if native is None:\n'
        '                raise ValueError(\n'
        '                    f"no native provider for fallback: {chosen!r} is refused for "\n'
        '                    f"{task_class} and the dispatch file lists no `kind: native` "\n'
        '                    "provider to resolve instead"\n'
        '                )\n',
        '            if native is None:\n'
        '                native = provider  # known-bad: resolve the refused row anyway\n',
    ),
    # b8: a syntax error in the module the py_compile gate must be listing.
    "syntax-error": (
        'if __name__ == "__main__":',
        'def deliberately broken(:\n\n\nif __name__ == "__main__":',
    ),
    # b8 known-bad 1: the filename drops off the ruff invocation.
    "run-sh-drop-ruff": (
        '  if ruff check --select F,E9,B "$SKILL_DIR/scripts/goalforge-pick-agent.py" '
        '"$SKILL_DIR/scripts/goalforge-admission.py"',
        '  if ruff check --select F,E9,B "$SKILL_DIR/scripts/goalforge-pick-agent.py"',
    ),
    # b8 known-bad 2: the filename drops off the py_compile invocation.
    "run-sh-drop-pycompile": (
        'if python3 -m py_compile "$SKILL_DIR/scripts/goalforge-pick-agent.py" '
        '"$SKILL_DIR/scripts/goalforge-plan-index.py" '
        '"$SKILL_DIR/scripts/goalforge-admission.py"',
        'if python3 -m py_compile "$SKILL_DIR/scripts/goalforge-pick-agent.py" '
        '"$SKILL_DIR/scripts/goalforge-plan-index.py"',
    ),
}

# --- wp-08 T8-T12 known-bads (goalforge-workflow-compile.test.sh red()) -------
_ENTRY_CHECK = (
    '    if entry.is_symlink():\n'
    '        return f"leaf_closure mismatch: the entry file {entry} is a symlink"\n'
)
_DIR_WALK = '            if os.path.islink(os.path.join(dirpath, name)):'
_DIR_WALK_OUT_OF_ROOT_ONLY = (
    '            if os.path.islink(os.path.join(dirpath, name)) and os.path.commonpath('
    '[str(root_real), os.path.realpath(os.path.join(dirpath, name))]) != str(root_real):'
)
_FILE_WALK = '            if os.path.islink(path):'
_FILE_WALK_OUT_OF_ROOT_ONLY = (
    '            if os.path.islink(path) and os.path.commonpath('
    '[str(root_real), os.path.realpath(path)]) != str(root_real):'
)
_GUARD_SET = '    if guard_set and (_control_char(rel) or not TABLE_GUARD_SET.fullmatch(rel)):'

MUTATIONS.update({
    # b12 known-bad (n): the full lap-7 N1 code — no entry islink check, a walk
    # of the DECLARED unresolved entry directory, and a walker that refuses
    # only out-of-root symlinks.
    "n1-lap7": [
        (_ENTRY_CHECK, ""),
        ("    tree = str(target.parent)\n", "    tree = os.path.dirname(str(entry))\n"),
        (_DIR_WALK, _DIR_WALK_OUT_OF_ROOT_ONLY),
        (_FILE_WALK, _FILE_WALK_OUT_OF_ROOT_ONLY),
    ],
    # b12 known-bad (l): rule (c) refusing only out-of-root symlinks.
    "walker-out-of-root-only": [
        (_DIR_WALK, _DIR_WALK_OUT_OF_ROOT_ONLY),
        (_FILE_WALK, _FILE_WALK_OUT_OF_ROOT_ONLY),
    ],
    # b12 known-bad (m): refuses a leaf root reached through a symlinked ancestor.
    "refuse-symlinked-ancestor": (
        "    root_real = Path(os.path.realpath(root))\n    return root_real,",
        "    root_real = Path(os.path.realpath(root))\n"
        "    if str(root_real) != os.path.abspath(root):\n"
        "        raise AdmissionTableError(f'leaf root {root} resolves through a symlink')\n"
        "    return root_real,",
    ),
    # T9 structural: closure_mismatch resolves the entry again.
    "closure-realpath-entry": (
        "    tree = str(target.parent)\n",
        "    tree = os.path.dirname(os.path.realpath(entry))\n",
    ),
    # T10 single-resolution structural: the guard check re-resolves the table.
    "resolve-table-dir": (
        "    table_dir = path.parent\n",
        "    table_dir = path.resolve().parent\n",
    ),
    # b15 known-bad (a), admission half: the lap-7 abspath-vs-realpath refusal.
    "lap7-head-refusal": (
        "    file_dir = path.parent\n    try:\n        top = ",
        "    if path.is_symlink() or os.path.realpath(path) != os.path.abspath(path):\n"
        "        raise AdmissionTableError(\n"
        "            f'{what} {path} is a symlink or resolves through one — HEAD binding refused')\n"
        "    file_dir = path.parent\n    try:\n        top = ",
    ),
    # b15 known-bads (a) pick-agent half, (b) and (d): the HEAD read and guard
    # check take the UNRESOLVED canonical path, not the one resolved path.
    "head-read-unresolved-table": (
        "        admission.verify_head_binding(table_path, raw)",
        "        admission.verify_head_binding(admission.ADMITTED_PATH, raw)",
    ),
    # b15 known-bad (a) compile half: the overview is never resolved.
    "brief-abspath": (
        "    real = overview.resolve()",
        "    real = Path(os.path.abspath(overview))",
    ),
    # b15 known-bad (c): no guard-set match on the resolved rel.
    "no-guard-set": (_GUARD_SET, "    if False:"),
    # b15 known-bad (e): re.search with a bare trailing `$`, no control-char check.
    "guard-set-search-dollar": (
        _GUARD_SET,
        '    if guard_set and not re.search(r"(^|/)references/admitted-providers\\.yaml$", rel):',
    ),
    # b15 known-bad (f): an unanchored re.search + \Z.
    "guard-set-search-z": (
        _GUARD_SET,
        '    if guard_set and (_control_char(rel) or not re.search('
        'r"references/admitted-providers\\.yaml\\Z", rel)):',
    ),
    # T12 known-bad: the guard-set match kept, the guarded-repository check dropped.
    "drop-guard-reason": (
        "    unguarded = _guard_reason(table_dir)\n",
        "    unguarded = None\n",
    ),
    # b16 known-bads (a)/(b): the brief always from HEAD / always the work tree.
    "brief-always-head": (
        '        if adm.is_tracked(real, "WP overview"):',
        "        if True:",
    ),
    "brief-always-worktree": (
        '        if adm.is_tracked(real, "WP overview"):',
        "        if False:",
    ),
    # b16 known-bad (c): the ledger row carries no brief_source.
    "brief-source-dropped": (
        '        if brief_source is not None:\n            row["brief_source"] = brief_source\n',
        "",
    ),
    # b16 known-bad (d): any HEAD-read failure falls back to the work tree.
    "brief-fail-open": (
        "    except adm.AdmissionTableError as exc:\n"
        '        raise ValueError(f"leaf brief: {exc}") from None\n'
        "    try:\n"
        '        return real, real.read_bytes(), "worktree"',
        "    except adm.AdmissionTableError:\n"
        "        pass\n"
        "    try:\n"
        '        return real, real.read_bytes(), "worktree"',
    ),
    # b16 known-bad (e): "tracked" asked of the OUTER (package) repository.
    "brief-outer-repo": (
        '    res = _git(["ls-files", "--error-unmatch", "--", path.name], file_dir)',
        '    res = _git(["ls-files", "--error-unmatch", "--", str(path)], PKG_ROOT)',
    ),
})


def main(argv: list[str]) -> int:
    if len(argv) != 4 or argv[1] not in MUTATIONS:
        print(f"usage: mutate.py <{'|'.join(MUTATIONS)}> <source> <destination>",
              file=sys.stderr)
        return 2
    spec = MUTATIONS[argv[1]]
    pairs = spec if isinstance(spec, list) else [spec]
    with open(argv[2], "r", encoding="utf-8") as fh:
        text = fh.read()
    for anchor, replacement in pairs:
        if text.count(anchor) != 1:
            print(f"ERROR: mutation {argv[1]!r} anchor occurs {text.count(anchor)} "
                  f"times in {argv[2]} (want exactly 1) — the known-bad no longer "
                  "sabotages anything", file=sys.stderr)
            return 2
        text = text.replace(anchor, replacement)
    with open(argv[3], "w", encoding="utf-8") as fh:
        fh.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
