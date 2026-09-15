"""goalforge-admission — the provider-admission table, task class, and verdict.

The admission table decides the resolver verdict for role ``implement``:
a foreign or local provider resolves as an executing implementer only when
``references/admitted-providers.yaml`` carries a row for the WP's task class
naming that provider AND the resolved model, a closed-kind evidence record,
and a permission set. Contract and rationale: ``references/admission.md``.

This module has NO ledger I/O. ``goalforge-pick-agent.py`` is the one caller
and the one ledger writer — the verdict is returned, never recorded here.

Public API:
    load(path=None, *, required=False) -> list[dict]
        Read and VALIDATE a table. ``None`` reads the shipped table; the
        absent-flag path is never a skip. ``required=True`` (the caller named
        the path) turns a missing file into an error rather than an empty
        table. Raises AdmissionTableError.

    task_class(frontmatter) -> str
        ``<task_type>/<ext>`` from the WP frontmatter's OWN ``owned_files``.

    resolve(role, task_class, provider, model, table, *, leaf_root) -> Admission
        The verdict. ``provider`` is a dispatch.yaml ``providers[]`` row.
        Admission binds the EXECUTABLE as well as the triple: the row's
        ``leaf``/``leaf_sha256`` must match the provider row's leaf path and
        that file's current content.

CLI:
    python3 goalforge-admission.py [--table <yaml>]      # validate, exit 0|2
    python3 goalforge-admission.py --task-class <wp.md>  # print the key
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

try:
    import yaml
except ImportError as exc:  # pragma: no cover
    raise SystemExit("PyYAML required: pip install pyyaml") from exc


PKG_ROOT = Path(__file__).resolve().parent.parent
ADMITTED_PATH = PKG_ROOT / "references" / "admitted-providers.yaml"

# Closed set. `self-report` is deliberately absent: a model's own claim that it
# did the job is not evidence that it did (evaluation.md).
EVIDENCE_KINDS: frozenset[str] = frozenset(
    {"user-experience", "benchmark", "user-addition"}
)

# Every key a row must carry. `evidence` is checked structurally below.
REQUIRED_KEYS: tuple[str, ...] = (
    "task_class", "provider", "model", "evidence", "permission_set",
)

# The executable the row's evidence was gathered against. Checked AFTER the
# keys above so a row missing one of those is still reported by that key.
LEAF_KEYS: tuple[str, ...] = ("leaf", "leaf_sha256")

# The task class of a WP whose owned_files carry no file extension.
NO_EXTENSION = "-"


class AdmissionTableError(Exception):
    """A table that cannot be trusted to decide anything. Caller exits 2."""


@dataclass(frozen=True)
class Admission:
    """Verdict of the provider-admission check for one dispatch."""

    admitted: bool
    reason: str
    evidence_ref: str = ""
    permission_set: list = field(default_factory=list)


# ---------------------------------------------------------------------------
# Table
# ---------------------------------------------------------------------------

def _row_error(index: int, key: str, detail: str) -> AdmissionTableError:
    return AdmissionTableError(
        f"admitted-providers row {index}: key {key!r} — {detail}"
    )


def validate(rows: object) -> list[dict]:
    """Validate the ``admitted:`` list. Raises AdmissionTableError."""
    if rows is None:
        return []
    if not isinstance(rows, list):
        raise AdmissionTableError("`admitted:` is not a list")
    validated: list[dict] = []
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            raise _row_error(index, "admitted", "row is not a mapping")
        for key in REQUIRED_KEYS:
            if not row.get(key):
                raise _row_error(index, key, "missing")
        evidence = row["evidence"]
        if not isinstance(evidence, dict):
            raise _row_error(index, "evidence", "not a mapping")
        kind = evidence.get("kind")
        if not kind:
            raise _row_error(index, "evidence.kind", "missing")
        if kind not in EVIDENCE_KINDS:
            raise _row_error(
                index, "evidence.kind",
                f"{kind!r} is not in {sorted(EVIDENCE_KINDS)}",
            )
        if not evidence.get("ref"):
            raise _row_error(index, "evidence.ref", "missing")
        if not isinstance(row["permission_set"], list):
            # A bare string is truthy and would explode into per-character
            # permissions in the resolution and the ledger.
            raise _row_error(index, "permission_set", "not a list")
        for key in LEAF_KEYS:
            if not isinstance(row.get(key), str) or not row[key].strip():
                raise _row_error(
                    index, key,
                    "missing or not a string — an admitted row binds the EXECUTABLE "
                    "(leaf path + leaf_sha256), not just the provider name",
                )
        validated.append(row)
    return validated


def default_leaf_root() -> Path:
    """Root a `providers[].leaf` path is relative to (the Claude corpus)."""
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")


def _leaf_digest(path: Path) -> str:
    """sha256 of the leaf executable. Raises OSError when it cannot be read."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path: Path | None = None, *, required: bool = False) -> list[dict]:
    """Load and validate a table. ``None`` reads the SHIPPED table.

    A missing SHIPPED table is an empty table, not a skipped check: every
    non-native implement resolution is refused when no row admits it. A missing
    table the CALLER named (``required=True``, i.e. an explicit ``--admitted`` /
    ``--table`` argument) is an error instead — a typo'd override must not
    silently become an empty table that refuses everything at exit 0."""
    target = path or ADMITTED_PATH
    try:
        with open(target, "r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
    except FileNotFoundError:
        if required:
            raise AdmissionTableError(
                f"admission table not found: {target}"
            ) from None
        return []
    except (OSError, UnicodeDecodeError, yaml.YAMLError) as exc:
        # A directory, a permission denial or a binary file is as untrustworthy
        # as a syntax error: every one of them must reach the caller as an
        # AdmissionTableError (exit 2), never as a traceback at exit 1.
        raise AdmissionTableError(f"unreadable admission table {target}: {exc}") from exc
    if not isinstance(data, dict):
        raise AdmissionTableError(f"admission table is not a mapping: {target}")
    return validate(data.get("admitted"))


# ---------------------------------------------------------------------------
# Task class
# ---------------------------------------------------------------------------

def task_class(frontmatter: dict) -> str:
    """``<task_type>/<ext>`` from the WP frontmatter's OWN ``owned_files``.

    The extension is LITERAL and never aliased (`code/py`, `code/sh`,
    `code/yaml`). Directory entries do not count. Ties break on the
    lexicographically smallest extension, so the key does not depend on the
    order the entries happen to be written in; no file entry carries an
    extension at all yields ``-``."""
    kind = frontmatter.get("task_type") or "code"
    counts: Counter[str] = Counter()
    for entry in frontmatter.get("owned_files") or []:
        if not isinstance(entry, str) or entry.endswith("/"):
            continue
        suffix = Path(entry).suffix
        if suffix:
            counts[suffix.lstrip(".").lower()] += 1
    if not counts:
        return f"{kind}/{NO_EXTENSION}"
    top = max(counts.values())
    return f"{kind}/{min(ext for ext, n in counts.items() if n == top)}"


# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------

def _leaf_incoherence(row: dict, provider: dict, root: Path | None) -> str | None:
    """Why this row's admission does not cover the executable that would run.

    The row's evidence was gathered against ONE executable. A dispatch file can
    repoint `providers[].leaf` under an admitted provider name, and the leaf
    file's own content can change under a stable path — neither inherits the
    admission. Returns the refusal reason, or None when the binding holds."""
    name = provider.get("name")
    declared = row.get("leaf")
    if not isinstance(declared, str) or not declared.strip():
        return (
            f"admission row for {name!r} binds no leaf — refused (a row admits "
            "an executable, not a provider name)"
        )
    configured = provider.get("leaf")
    if configured != declared:
        return (
            f"admission row for {name!r} binds leaf {declared!r} but the "
            f"dispatch file's provider row runs {configured!r} — refused "
            "(a repointed leaf does not inherit the admission)"
        )
    target = (root or default_leaf_root()) / declared
    try:
        digest = _leaf_digest(target)
    except OSError as exc:
        return (
            f"admission row for {name!r} binds leaf {declared!r}, which cannot "
            f"be read at {target}: {exc} — refused"
        )
    if digest.lower() != str(row.get("leaf_sha256", "")).strip().lower():
        return (
            f"leaf {declared!r} hashes to {digest} but the admission row for "
            f"{name!r} records {row.get('leaf_sha256')!r} — refused (the "
            "evidence was gathered against different content)"
        )
    return None


def resolve(role: str, klass: str, provider: dict, model: str,
            table: list[dict] | None = None, *,
            leaf_root: Path | None = None) -> Admission:
    """Return the admission verdict for (role, task class, provider, model).

    ``leaf_root`` is the root a `providers[].leaf` path resolves against
    (default: ``CLAUDE_CONFIG_DIR`` or ``~/.claude``)."""
    name = provider.get("name")
    if provider.get("kind") == "native":
        return Admission(True, f"native provider admitted for {role}/{klass}")
    rows = [
        r for r in (table or [])
        if r.get("task_class") == klass and r.get("provider") == name
    ]
    if not rows:
        return Admission(
            False,
            f"no admission row for task class {klass} and provider {name!r} "
            f"(role {role}) — refused",
        )
    for row in rows:
        if row.get("model") == model:
            unbound = _leaf_incoherence(row, provider, leaf_root)
            if unbound:
                return Admission(False, unbound)
            return Admission(
                True,
                f"admitted for {klass} on {name!r}/{model!r} "
                f"(evidence {row['evidence']['kind']})",
                evidence_ref=str(row["evidence"]["ref"]),
                permission_set=list(row["permission_set"]),
            )
    candidates = ", ".join(repr(r.get("model")) for r in rows)
    return Admission(
        False,
        f"admission row(s) for {klass} on {name!r} name model {candidates}, "
        f"resolved model is {model!r} — refused "
        "(admission binds task class, provider AND model)",
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _frontmatter(path: Path) -> dict:
    """YAML frontmatter of a WP overview.md."""
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        raise AdmissionTableError(f"no YAML frontmatter in {path}")
    end = next((i for i, ln in enumerate(lines[1:], 1) if ln.strip() == "---"), None)
    if end is None:
        raise AdmissionTableError(f"unterminated YAML frontmatter in {path}")
    return yaml.safe_load("\n".join(lines[1:end])) or {}


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. Returns exit code."""
    p = argparse.ArgumentParser(
        description="Validate the admission table, or derive a WP's task class."
    )
    p.add_argument("--table", metavar="FILE", default=None,
                   help="Admission table (default: the shipped "
                        "references/admitted-providers.yaml).")
    p.add_argument("--task-class", metavar="FILE", default=None,
                   help="Print the task class derived from this WP's frontmatter.")
    args = p.parse_args(argv)

    try:
        if args.task_class:
            print(task_class(_frontmatter(Path(args.task_class))))
            return 0
        rows = load(Path(args.table), required=True) if args.table else load()
    except AdmissionTableError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print(f"admission table OK: {len(rows)} row(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
