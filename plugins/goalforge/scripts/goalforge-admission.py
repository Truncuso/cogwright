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
        Admission binds the leaf closure as well as the triple: the row's
        ``leaf``/``leaf_sha256`` must match the provider row's leaf path and
        that file's current content, and ``leaf_closure`` must hash every
        regular file under the leaf's directory tree.

CLI:
    python3 goalforge-admission.py [--table <yaml>]      # validate, exit 0|2
    python3 goalforge-admission.py --task-class <wp.md>  # print the key
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
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
# `max_egress` (wp-08) is appended LAST: the declared egress ceiling of the
# admitted dispatch, checked against the dispatch row's declared `egress`.
# `leaf_closure` follows it: leaf-root-relative path -> sha256 of every regular
# file under the leaf's directory tree (see closure_mismatch).
REQUIRED_KEYS: tuple[str, ...] = (
    "task_class", "provider", "model", "evidence", "permission_set", "max_egress",
    "leaf_closure",
)

# The egress classes in their total order (execute/references/dispatch-resolution.md
# § Egress classes). A dispatch is coherent with a row iff its egress ranks at
# or below the row's `max_egress`.
EGRESS_LEVELS: tuple[str, ...] = ("none", "diff-only", "overview", "full")

# The goalforge pre-commit installer's marker block (scripts/goalforge-install-hooks.sh).
HOOK_MARKER_OPEN = "# >>> sdd-pre-commit >>>"
HOOK_MARKER_CLOSE = "# <<< sdd-pre-commit <<<"
PRE_COMMIT_HOOK = PKG_ROOT / "hooks" / "goalforge-pre-commit.sh"

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
    leaf: str = ""
    leaf_sha256: str = ""
    max_egress: str = ""


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
                raise AdmissionTableError(
                    f"admitted-providers row {index}: missing required key {key!r}"
                )
        if row["max_egress"] not in EGRESS_LEVELS:
            # Closed enum: an unknown level must never reach the coherence rank.
            raise AdmissionTableError(
                f"admitted-providers row {index}: max_egress {row['max_egress']!r} "
                f"not in {{{', '.join(EGRESS_LEVELS)}}}"
            )
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
                    "missing or not a string — an admitted row binds the leaf "
                    "closure (leaf path + leaf_sha256 + leaf_closure), not just "
                    "the provider name",
                )
        closure = row["leaf_closure"]
        if not isinstance(closure, dict) or not all(
            isinstance(k, str) and isinstance(v, str) for k, v in closure.items()
        ):
            raise _row_error(index, "leaf_closure", "not a mapping of path -> sha256")
        validated.append(row)
    return validated


def default_leaf_root() -> Path:
    """Root a `providers[].leaf` path is relative to (the Claude corpus)."""
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")


def _leaf_digest(path: Path) -> str:
    """sha256 of the leaf executable. Raises OSError when it cannot be read."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def closure_mismatch(row: dict, root: Path) -> str | None:
    """Why the files under the leaf's directory tree differ from ``leaf_closure``.

    The closure is every regular file under the EXECUTED entry file's real
    parent directory, recursively, keyed relative to the real leaf root; no
    ``source`` line is parsed. The walked tree is therefore the tree the leaf
    runs from. Each is a mismatch: (a) a listed file missing or unreadable,
    (b) a file under the tree absent from the manifest, (c) ANY symlink under
    the tree or at the entry path itself (file or directory), (d) a tree whose
    real path is outside the root. Returns None when the closure holds."""
    root_real = os.path.realpath(root)
    entry = os.path.join(root, str(row["leaf"]))
    if os.path.islink(entry):
        return f"leaf_closure mismatch: the entry file {entry} is a symlink"
    tree = os.path.dirname(os.path.realpath(entry))
    manifest = {str(k): str(v).strip().lower() for k, v in row["leaf_closure"].items()}
    if os.path.commonpath([root_real, tree]) != root_real:
        return f"leaf_closure mismatch: {tree} resolves outside the leaf root {root_real}"
    rel_dir = Path(os.path.relpath(tree, root_real))
    errors: list[OSError] = []
    found: dict[str, Path] = {}
    for dirpath, dirnames, filenames in os.walk(tree, onerror=errors.append):
        for name in dirnames:
            if os.path.islink(os.path.join(dirpath, name)):
                return (f"leaf_closure mismatch: {os.path.join(dirpath, name)} is a "
                        "symlink to a directory")
        for name in filenames:
            path = os.path.join(dirpath, name)
            if os.path.islink(path):
                return f"leaf_closure mismatch: {path} is a symlink"
            key = (rel_dir / os.path.relpath(path, tree)).as_posix()
            if key not in manifest:
                return f"leaf_closure mismatch: {key} is under the leaf tree but not listed"
            found[key] = Path(path)
    if errors:
        return f"leaf_closure mismatch: the leaf tree cannot be walked: {errors[0]}"
    for key, want in sorted(manifest.items()):
        if key not in found or not found[key].is_file():
            return f"leaf_closure mismatch: listed file {key} is missing"
        try:
            digest = _leaf_digest(found[key])
        except OSError as exc:
            return f"leaf_closure mismatch: listed file {key} cannot be read: {exc}"
        if digest != want:
            return f"leaf_closure mismatch: {key} hashes to {digest}, the row records {want}"
    return None


def load(path: Path | None = None, *, required: bool = False) -> list[dict]:
    """Load and validate a table. ``None`` reads the SHIPPED table.

    A missing SHIPPED table is an empty table, not a skipped check: every
    non-native implement resolution is refused when no row admits it. A missing
    table the CALLER named (``required=True``, i.e. an explicit ``--admitted`` /
    ``--table`` argument) is an error instead — a typo'd override must not
    silently become an empty table that refuses everything at exit 0."""
    target = path or ADMITTED_PATH
    try:
        raw = read_table(target)
    except AdmissionTableError:
        if not required and not Path(target).exists():
            return []
        raise
    return parse(raw, target)


def read_table(path: Path) -> bytes:
    """The table file's bytes, read ONCE. Fails CLOSED on any read failure.

    The execution decision (the workflow compile, the leaf wrapper) reads
    through here with no empty-table fallback: a missing or unreadable table
    never degrades to "nothing admitted" at exit 0 — it is its own error."""
    try:
        return Path(path).read_bytes()
    except FileNotFoundError:
        raise AdmissionTableError(
            f"admission table not found: {path} — load failure, failed CLOSED"
        ) from None
    except OSError as exc:
        # A directory or a permission denial is as untrustworthy as a syntax
        # error: it reaches the caller as an AdmissionTableError (exit 2).
        raise AdmissionTableError(
            f"unreadable admission table {path}: {exc} — load failure, failed CLOSED"
        ) from exc


def parse(raw: bytes, source: object) -> list[dict]:
    """Parse and VALIDATE table bytes already read by ``read_table``."""
    try:
        data = yaml.safe_load(raw.decode("utf-8")) or {}
    except (UnicodeDecodeError, yaml.YAMLError) as exc:
        raise AdmissionTableError(
            f"unreadable admission table {source}: {exc} — load failure, failed CLOSED"
        ) from exc
    if not isinstance(data, dict):
        raise AdmissionTableError(f"admission table is not a mapping: {source}")
    return validate(data.get("admitted"))


# ---------------------------------------------------------------------------
# HEAD binding (wp-08 T3) — an admitting table must be the COMMITTED table
# ---------------------------------------------------------------------------
# An uncommitted table edit must not admit anything: the pre-commit guard on
# admitted-providers.yaml is only on the path if the admitting bytes went
# through a commit. This is a cost-raiser, not a trust boundary (a forged hook
# file or plumbing commits stay a recorded residual, wp-08 Risks).

def _git_env(*, isolate_config: bool) -> dict[str, str]:
    """The caller's environment with EVERY ``GIT_*`` variable scrubbed.

    An agent-settable ``GIT_DIR`` / ``GIT_WORK_TREE`` would point the HEAD read
    at a forged repository. ``isolate_config`` additionally hides global and
    system config for the HEAD read itself; the ``core.hooksPath`` lookup runs
    WITHOUT it, because hiding that setting would hide what `git commit` runs."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    if isolate_config:
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_CONFIG_GLOBAL"] = os.devnull
    return env


def _git(args: list[str], cwd: Path, *, isolate_config: bool = True):
    return subprocess.run(
        ["git", "-C", str(cwd), *args], env=_git_env(isolate_config=isolate_config),
        capture_output=True, check=False,
    )


def _marker_hook_paths(text: str) -> list[str]:
    """The paths the installer's marker block invokes (`bash "<path>" ...`)."""
    paths: list[str] = []
    inside = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == HOOK_MARKER_OPEN:
            inside = True
            continue
        if stripped == HOOK_MARKER_CLOSE:
            inside = False
            continue
        m = re.match(r'^bash\s+"([^"]+)"', stripped) if inside else None
        if m:
            paths.append(m.group(1))
    return paths


def _guard_reason(table_dir: Path) -> str | None:
    """Why the repository anchored at ``table_dir`` is not goalforge-guarded."""
    for scope in ("--global", "--system"):
        res = _git(["config", scope, "--get", "core.hooksPath"], table_dir,
                   isolate_config=False)
        if res.returncode == 0:
            value = res.stdout.decode("utf-8", "replace").strip()
            return (
                f"a {scope[2:]} core.hooksPath is set ({value!r}) — the "
                "repository's own pre-commit is not what `git commit` runs; "
                "admission failed CLOSED"
            )
        if res.returncode != 1:
            return (
                f"the {scope[2:]} core.hooksPath lookup failed "
                f"(git exit {res.returncode}) — admission failed CLOSED"
            )
    res = _git(["rev-parse", "--git-path", "hooks"], table_dir)
    if res.returncode != 0:
        return "the repository's hooks directory cannot be resolved — failed CLOSED"
    hooks = Path(res.stdout.decode("utf-8", "replace").strip())
    if not hooks.is_absolute():
        hooks = table_dir / hooks
    pre_commit = hooks / "pre-commit"
    try:
        text = pre_commit.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        text = ""
    want = os.path.realpath(PRE_COMMIT_HOOK)
    if any(os.path.realpath(p) == want for p in _marker_hook_paths(text)):
        return None
    return (
        f"the table's repository is unguarded: {pre_commit} carries no "
        f"goalforge installer marker block invoking {PRE_COMMIT_HOOK} "
        "(install it with scripts/goalforge-install-hooks.sh)"
    )


def head_bytes(path: Path, what: str = "admission table") -> tuple[bytes, str]:
    """``(git show HEAD:<path> bytes, the HEAD-relative path)``, read FAIL-CLOSED.

    The repository is anchored at the file's OWN directory with every ``GIT_*``
    variable scrubbed; outside a work tree and absent from HEAD each raise
    AdmissionTableError with its own reason, never a skipped read. A symlinked
    file, or a path whose real path differs from its unresolved absolute path,
    is refused: the HEAD path read must be the path the guard filters."""
    absolute = Path(os.path.abspath(path))
    if absolute.is_symlink() or os.path.realpath(absolute) != str(absolute):
        raise AdmissionTableError(
            f"{what} {path} is a symlink or resolves through one (real path "
            f"{os.path.realpath(absolute)}) — HEAD binding refused"
        )
    file_dir = absolute.parent
    name = absolute.name
    try:
        prefix = _git(["rev-parse", "--show-prefix"], file_dir)
    except OSError as exc:
        raise AdmissionTableError(
            f"{what} {path}: git is not runnable ({exc}) — HEAD binding "
            "failed CLOSED"
        ) from exc
    if prefix.returncode != 0:
        raise AdmissionTableError(
            f"{what} {path} is outside a git work tree — the HEAD "
            "binding cannot be checked, failed CLOSED"
        )
    rel = prefix.stdout.decode("utf-8", "replace").strip() + name
    head = _git(["show", f"HEAD:{rel}"], file_dir)
    if head.returncode != 0:
        raise AdmissionTableError(
            f"{what} {path} is absent from HEAD (git show HEAD:{rel} "
            f"found nothing) — an uncommitted {what} is a HEAD mismatch, refused"
        )
    return head.stdout, rel


def verify_head_binding(path: Path, raw: bytes) -> None:
    """Refuse table bytes that are not the table's committed HEAD content.

    ``raw`` are the bytes the caller already read and parsed (read once); the
    HEAD read is ``head_bytes``; and the repository must carry the goalforge
    pre-commit guard. Raises AdmissionTableError with a distinct reason per
    failure."""
    head, rel = head_bytes(path)
    table_dir = Path(path).resolve().parent
    if head != raw:
        raise AdmissionTableError(
            f"admission table {path} differs from git show HEAD:{rel} — HEAD "
            "mismatch: only the committed table admits, refused"
        )
    unguarded = _guard_reason(table_dir)
    if unguarded:
        raise AdmissionTableError(f"admission table {path}: {unguarded}")


def egress_within(egress: object, max_egress: object) -> bool:
    """``egress <= max_egress`` over none < diff-only < overview < full."""
    if egress not in EGRESS_LEVELS or max_egress not in EGRESS_LEVELS:
        return False
    return EGRESS_LEVELS.index(egress) <= EGRESS_LEVELS.index(max_egress)


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
    return closure_mismatch(row, root or default_leaf_root())


def resolve(role: str, klass: str, provider: dict, model: str,
            table: list[dict] | None = None, *,
            leaf_root: Path | None = None,
            egress: str | None = None) -> Admission:
    """Return the admission verdict for (role, task class, provider, model).

    ``leaf_root`` is the root a `providers[].leaf` path resolves against
    (default: ``CLAUDE_CONFIG_DIR`` or ``~/.claude``). ``egress`` is the
    dispatch row's declared egress class: when given, a matching row whose
    ``max_egress`` ranks below it is refused (`egress incoherent`)."""
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
            if egress is not None and not egress_within(egress, row.get("max_egress")):
                return Admission(
                    False,
                    f"egress incoherent: the dispatch row declares egress "
                    f"{egress!r} but the admission row for {klass} on "
                    f"{name!r}/{model!r} caps it at max_egress "
                    f"{row.get('max_egress')!r} — refused",
                )
            return Admission(
                True,
                f"admitted for {klass} on {name!r}/{model!r} "
                f"(evidence {row['evidence']['kind']})",
                evidence_ref=str(row["evidence"]["ref"]),
                permission_set=list(row["permission_set"]),
                leaf=str(row["leaf"]),
                leaf_sha256=str(row["leaf_sha256"]).strip().lower(),
                max_egress=str(row["max_egress"]),
            )
    candidates = ", ".join(repr(r.get("model")) for r in rows)
    return Admission(
        False,
        f"admission row(s) for {klass} on {name!r} name model {candidates}, "
        f"resolved model is {model!r} — refused "
        "(admission binds task class, provider AND model)",
    )


def admits_any(provider: dict, model: str, egress: str,
               table: list[dict] | None = None, *,
               leaf_root: Path | None = None) -> str | None:
    """The EXISTENTIAL rule for a WP-less config self-check (``--test-tiers``).

    With no WP there is no task class, so the row passes iff SOME admission
    row, for ANY task class, admits (provider, model) with a bound, current
    leaf and ``max_egress >= egress``. Returns None when one does, else the
    refusal reason. The per-WP task-class decision stays with the compile."""
    name = provider.get("name")
    classes = sorted({
        str(r.get("task_class")) for r in (table or [])
        if r.get("provider") == name and r.get("model") == model
    })
    if not classes:
        return (
            f"no admission row for (*, {name}, {model}) — refused (the implement "
            "row runs on a non-native provider no row admits)"
        )
    reasons = []
    for klass in classes:
        verdict = resolve("implement", klass, provider, model, table,
                          leaf_root=leaf_root, egress=egress)
        if verdict.admitted:
            return None
        reasons.append(verdict.reason)
    return "; ".join(reasons)


def verify_leaf(table_path: Path, klass: str, provider: str, model: str, *,
                leaf_root: Path | None = None) -> Path:
    """Re-derive and re-check the admitted leaf for one row key (the wrapper).

    Reads the table once, requires those bytes to be the committed HEAD
    content (``verify_head_binding``), takes the row's ``leaf``,
    ``leaf_sha256`` and ``leaf_closure`` from THAT table only, requires the
    leaf's real path to lie under the leaf root and re-hashes it and its
    closure (``closure_mismatch``). Returns the real path to execute.
    Raises AdmissionTableError on any failure — the leaf is never run then."""
    raw = read_table(table_path)
    verify_head_binding(table_path, raw)
    rows = [
        r for r in parse(raw, table_path)
        if r.get("task_class") == klass and r.get("provider") == provider
        and r.get("model") == model
    ]
    if len(rows) != 1:
        raise AdmissionTableError(
            f"no single admission row for ({klass}, {provider}, {model}) in the "
            f"HEAD-bound table {table_path} — refused"
        )
    row = rows[0]
    root = Path(os.path.realpath(leaf_root or default_leaf_root()))
    target = Path(os.path.realpath(root / str(row["leaf"])))
    if root not in target.parents:
        raise AdmissionTableError(
            f"leaf {row['leaf']!r} resolves to {target}, outside the leaf root "
            f"{root} — refused, not executed"
        )
    try:
        digest = _leaf_digest(target)
    except OSError as exc:
        raise AdmissionTableError(
            f"leaf {target} cannot be read: {exc} — refused, not executed"
        ) from exc
    if digest != str(row["leaf_sha256"]).strip().lower():
        raise AdmissionTableError(
            f"leaf_sha256 mismatch: {target} hashes to {digest} but the "
            f"HEAD-bound admission row records {row['leaf_sha256']!r} — "
            "refused, not executed"
        )
    unbound = closure_mismatch(row, root)
    if unbound:
        raise AdmissionTableError(f"{unbound} — refused, not executed")
    return target


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
    p.add_argument("--verify-leaf", nargs=4,
                   metavar=("TABLE", "TASK_CLASS", "PROVIDER", "MODEL"),
                   default=None,
                   help="scripts/goalforge-leaf-exec.sh's check: print the real "
                        "path of the admitted leaf for this row key, exit 2 "
                        "unless the HEAD-bound table, the leaf root and the "
                        "leaf hash all hold.")
    args = p.parse_args(argv)

    try:
        if args.verify_leaf:
            table, klass, provider, model = args.verify_leaf
            print(verify_leaf(Path(table), klass, provider, model))
            return 0
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
