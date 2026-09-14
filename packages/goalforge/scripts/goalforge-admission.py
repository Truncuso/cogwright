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

    resolve(role, task_class, provider, model, table) -> Admission
        The verdict. ``provider`` is a dispatch.yaml ``providers[]`` row.

CLI:
    python3 goalforge-admission.py [--table <yaml>]      # validate, exit 0|2
    python3 goalforge-admission.py --task-class <wp.md>  # print the key
"""
from __future__ import annotations

import argparse
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
        validated.append(row)
    return validated


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
    except yaml.YAMLError as exc:
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

def resolve(role: str, klass: str, provider: dict, model: str,
            table: list[dict] | None = None) -> Admission:
    """Return the admission verdict for (role, task class, provider, model)."""
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
