"""phrase.py — whitespace-normalized phrase counting for the b7/b8 ratchets.

Prose wraps; the literal a ratchet asserts does not. Counting over a
whitespace-collapsed copy of the file makes the assertion about the SENTENCE,
not about where the author happened to break the line.

    python3 phrase.py <file> <phrase>   # prints the occurrence count
"""
import re
import sys


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: phrase.py <file> <phrase>", file=sys.stderr)
        return 2
    with open(argv[1], "r", encoding="utf-8") as fh:
        text = re.sub(r"\s+", " ", fh.read())
    print(text.count(re.sub(r"\s+", " ", argv[2])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
