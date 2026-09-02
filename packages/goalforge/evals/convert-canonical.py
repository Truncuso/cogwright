#!/usr/bin/env python3
"""convert-canonical.py — rename, not rewrite: the 13 goalforge evals.json files
into the canonical `should_trigger` case shape (T1, normatively defined in
${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/skill-trigger-runner/README.md,
section "The canonical shape (T1)").

Contract (human ruling 2026-09-02):
  * `prompt` and `expected_output` stay BYTE-IDENTICAL. Nothing is reworded.
  * Every other existing key (`id`, `files`, `expectations`, `description`, ...)
    is preserved verbatim.
  * `should_trigger` is DERIVED from the `expected_output` prose, never invented
    and never guessed from the id or the file name.
  * No owner name is invented. A file without `skill_name` (onboard) stays
    without one — the runner derives the skill under test from the directory.

Derivation: a case is a NEGATIVE (should_trigger: false) iff its
`expected_output`, lowercased with NBSP/curly punctuation left alone, contains
one of NEGATIVE_PHRASES below. Everything else is a positive. The phrase list is
closed and literal on purpose: prose classification by anything looser is not
reproducible, and a converter that is not reproducible cannot be idempotent.

Key order per case: id, should_trigger, prompt, expected_output, then every
remaining key in its original order. 2-space indent, ensure_ascii=False,
trailing newline.

Idempotent: a second run produces zero git diff.
"""

from __future__ import annotations

import json
import pathlib
import sys

# The closed, literal phrase list. Matched case-insensitively against
# expected_output. Only the first phrase actually occurs in the current corpus
# (9 cases); the others are the same semantic class and are listed so a newly
# authored case that phrases it differently is still classified, not silently
# scored as a positive.
NEGATIVE_PHRASES = (
    "should not trigger",
    "must not trigger",
    "does not trigger",
    "does not fire",
    "doesn't fire",
    "should not fire",
    "is not invoked",
    "is not triggered",
    "never fires",
)

LEAD_KEYS = ("id", "should_trigger", "prompt", "expected_output")


def is_negative(expected_output: str) -> bool:
    haystack = expected_output.lower()
    return any(phrase in haystack for phrase in NEGATIVE_PHRASES)


def convert_case(case: dict) -> dict:
    out: dict = {}
    if "id" in case:
        out["id"] = case["id"]
    out["should_trigger"] = not is_negative(case.get("expected_output", ""))
    out["prompt"] = case["prompt"]
    out["expected_output"] = case["expected_output"]
    for key, value in case.items():
        if key not in LEAD_KEYS:
            out[key] = value
    return out


def convert_file(path: pathlib.Path) -> tuple[int, int]:
    doc = json.loads(path.read_text(encoding="utf-8"))
    doc["evals"] = [convert_case(c) for c in doc["evals"]]
    path.write_text(
        json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    pos = sum(1 for c in doc["evals"] if c["should_trigger"])
    return pos, len(doc["evals"]) - pos


def main(argv: list[str]) -> int:
    root = pathlib.Path(argv[1]) if len(argv) > 1 else pathlib.Path(__file__).resolve().parent.parent
    files = sorted(root.glob("*/evals/evals.json")) + sorted(root.glob("evals/evals.json"))
    if not files:
        print(f"no evals.json under {root}", file=sys.stderr)
        return 1
    tot_pos = tot_neg = 0
    for path in files:
        pos, neg = convert_file(path)
        tot_pos += pos
        tot_neg += neg
        print(f"{path.relative_to(root)}: positives={pos} negatives={neg}")
    print(f"TOTAL files={len(files)} positives={tot_pos} negatives={tot_neg}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
