#!/usr/bin/env bash
# goalforge-reader.sh — reader-slug resolution and profile access (spec.md C8).
#
# The reader profile is MACHINE STATE, not a typed memory fact: no
# `references/rules/memory.md` frontmatter, no MEMORY.md pointer, no QMD
# re-index. It sits under `<repo>/.memory/user/` for locality and gitignore
# scope only (wp-07 R2, user 2026-09-17). Contract: references/reader-profile.md.
#
# Usage:
#   goalforge-reader.sh --slug    [--repo <dir>] [--feature-dir <dir>]
#   goalforge-reader.sh --profile [--repo <dir>] [--feature-dir <dir>]
#   goalforge-reader.sh mark-seen <id> [--repo <dir>] [--feature-dir <dir>]
#   goalforge-reader.sh --seen    [--repo <dir>]      # one seen id per line
#
# Exit codes:
#   0  resolved (or anonymous: exactly one WARN on stderr, no profile path)
#   2  REFUSED — an asserted slug that is not `^[a-z0-9][a-z0-9._-]*$`, or a
#      resolved profile path outside `<repo>/.memory/user/`. Nothing is read or
#      written and no profile path is emitted.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 - "$HERE" "$@" <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path

SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
PROFILE_NAME = "goalforge-communication-profile.md"
ANON = "anonymous"

argv = sys.argv[2:]


def die(msg: str) -> None:
    print(f"goalforge-reader: {msg}", file=sys.stderr)
    raise SystemExit(2)


def opt(name: str):
    if name in argv:
        i = argv.index(name)
        if i + 1 >= len(argv):
            die(f"{name} needs a value")
        return argv[i + 1]
    return None


def repo_root() -> Path:
    explicit = opt("--repo")
    if explicit:
        return Path(explicit).resolve()
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True).stdout
        return Path(out.strip()).resolve()
    except (OSError, subprocess.CalledProcessError):
        die("not inside a git repository and no --repo given")


def check_asserted(value: str, source: str) -> str:
    """A slug the caller ASSERTED (env, goalforge.yaml). Bad value = refusal.

    `.`, `..`, `../../etc`, `a/b`, `` and `Mixed@Case` all fail the anchored
    pattern, so none of them can reach a path join.
    """
    if not SLUG_RE.match(value):
        die(f"refusing reader slug {value!r} from {source}: "
            r"must match ^[a-z0-9][a-z0-9._-]*$")
    return value


def from_yaml(root: Path):
    """Rung 2: `reader:` in <repo-root>/goalforge.yaml.

    The file is OPTIONAL — absent is a skip, never an error. Only a top-level
    `reader:` key is read; no YAML library is required or assumed.
    """
    path = root / "goalforge.yaml"
    if not path.is_file():
        return None
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    for line in text.splitlines():
        m = re.match(r"^reader:\s*[\"']?([^\"'#\s]*)[\"']?\s*(?:#.*)?$", line)
        if m:
            return check_asserted(m.group(1), "goalforge.yaml")
    return None


def from_email(root: Path):
    """Rung 3: the LOCAL-PART of `git config user.email`, lowercased.

    Derived, not asserted, so an unusable local-part degrades to anonymous
    instead of refusing. The full address is never stored or printed.
    """
    try:
        out = subprocess.run(["git", "-C", str(root), "config", "user.email"],
                             capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    email = out.strip()
    if "@" not in email:
        return None
    local = email.split("@", 1)[0].strip().lower()
    return local if SLUG_RE.match(local) else None


def warn_once(msg: str) -> None:
    feature_dir = opt("--feature-dir")
    if not feature_dir:
        print(f"goalforge-reader: WARN {msg}", file=sys.stderr)
        return
    marker = Path(feature_dir) / ".goalforge-reader-warned"
    if marker.exists():
        return
    print(f"goalforge-reader: WARN {msg}", file=sys.stderr)
    try:
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text("warned\n", encoding="utf-8")
    except OSError:
        pass  # degrade-not-block: a WARN we cannot record is still a WARN


def resolve_slug(root: Path) -> str:
    # Rung 1: GOALFORGE_READER. PRESENT-but-empty is an assertion, so it is
    # refused rather than skipped; only an UNSET variable falls through.
    env = os.environ.get("GOALFORGE_READER")
    if env is not None:
        return check_asserted(env, "GOALFORGE_READER")
    slug = from_yaml(root)
    if slug:
        return slug
    slug = from_email(root)
    if slug:
        return slug
    warn_once("no reader slug (GOALFORGE_READER / goalforge.yaml / "
              "git user.email all unset); profile disabled for this run")
    return ANON


def profile_path(root: Path, slug: str) -> Path:
    """Resolve the profile path and PROVE it is inside <repo>/.memory/user/.

    Containment is checked with Path.resolve(), not a string prefix test, so a
    symlinked or traversing component cannot smuggle a write out of the tree.
    """
    base = (root / ".memory" / "user").resolve()
    candidate = (base / slug / PROFILE_NAME).resolve()
    if base != candidate and base not in candidate.parents:
        die(f"refusing profile path outside {base}: {candidate}")
    return candidate


def read_seen(path: Path) -> list[str]:
    if not path.is_file():
        return []
    seen, in_block = [], False
    for line in path.read_text(encoding="utf-8").splitlines():
        if re.match(r"^seen:\s*$", line):
            in_block = True
            continue
        if in_block:
            m = re.match(r"^\s*-\s*([^\s(]+)", line)
            if m:
                seen.append(m.group(1))
                continue
            if line.strip():
                in_block = False
    return seen


def main() -> int:
    root = repo_root()
    slug = resolve_slug(root)

    if "--slug" in argv:
        print(slug)
        return 0

    if slug == ANON:
        # Profile disabled: no path, no read, no write. The chain never blocks.
        return 0

    path = profile_path(root, slug)

    if "--profile" in argv:
        print(path)
        return 0
    if "--seen" in argv:
        for item in read_seen(path):
            print(item)
        return 0
    if "mark-seen" in argv:
        ident = opt("mark-seen")
        if not ident:
            die("mark-seen needs an id")
        if ident in read_seen(path):
            return 0
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.is_file():
            path.write_text(
                f"# goalforge communication profile — {slug}\n"
                "# Machine state (spec.md C8). Not a typed memory fact.\n"
                "\nseen:\n", encoding="utf-8")
        text = path.read_text(encoding="utf-8")
        if re.search(r"^seen:\s*$", text, flags=re.M):
            text = re.sub(r"^seen:\s*$", f"seen:\n- {ident}", text,
                          count=1, flags=re.M)
        else:
            text = text.rstrip("\n") + f"\n\nseen:\n- {ident}\n"
        path.write_text(text, encoding="utf-8")
        return 0

    die("one of --slug, --profile, --seen or mark-seen <id> is required")
    return 2


raise SystemExit(main())
PY
