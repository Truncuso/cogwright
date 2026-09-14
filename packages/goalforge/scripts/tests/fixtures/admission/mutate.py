"""mutate.py — write a deliberately broken COPY of a shipped file.

Each known-bad in goalforge-admission.test.sh is a named, anchored mutation:
the anchor must be present exactly once or the mutation fails loudly, so a
refactor that moves the code under test cannot silently turn a known-bad into
a no-op (a known-bad that no longer sabotages anything is not an oracle).

    python3 mutate.py <name> <source> <destination>
"""
import sys

MUTATIONS: dict[str, tuple[str, str]] = {
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


def main(argv: list[str]) -> int:
    if len(argv) != 4 or argv[1] not in MUTATIONS:
        print(f"usage: mutate.py <{'|'.join(MUTATIONS)}> <source> <destination>",
              file=sys.stderr)
        return 2
    anchor, replacement = MUTATIONS[argv[1]]
    with open(argv[2], "r", encoding="utf-8") as fh:
        text = fh.read()
    if text.count(anchor) != 1:
        print(f"ERROR: mutation {argv[1]!r} anchor occurs {text.count(anchor)} "
              f"times in {argv[2]} (want exactly 1) — the known-bad no longer "
              "sabotages anything", file=sys.stderr)
        return 2
    with open(argv[3], "w", encoding="utf-8") as fh:
        fh.write(text.replace(anchor, replacement))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
