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


def leaf_target(root: Path, leaf: str) -> tuple[Path, Path]:
    """``(real leaf root, real entry file)`` — the ONE resolution of the leaf.

    Callers resolve here once and pass both paths on (``closure_mismatch``
    resolves nothing), so the path that is hashed, walked and executed is one
    path, not two realpath calls apart (T9; the remaining window is the
    accepted TOCTOU residual)."""
    root_real = Path(os.path.realpath(root))
    return root_real, Path(os.path.realpath(root_real / leaf))


def closure_mismatch(row: dict, root_real: Path, target: Path) -> str | None:
    """Why the files under the leaf's directory tree differ from ``leaf_closure``.

    ``root_real`` and ``target`` are the caller's ONE resolution
    (``leaf_target``); nothing here resolves the entry again. The closure is
    every regular file under the EXECUTED entry file's real parent directory
    (``target.parent``), recursively, keyed relative to the real leaf root; no
    ``source`` line is parsed. Each is a mismatch: (a) a listed file missing or
    unreadable, (b) a file under the tree absent from the manifest, (c) a
    symlink at the entry path or anywhere under the entry's real parent tree
    (file or directory). A symlinked ancestor above the leaf root, and an
    in-root symlinked directory between the root and the entry's directory,
    are RESOLVED (the real path re-keys the closure, so (b) catches a
    repoint). A tree outside the real root is refused (the leaf-root pin).
    Returns None when the closure holds."""
    entry = root_real / str(row["leaf"])
    if entry.is_symlink():
        return f"leaf_closure mismatch: the entry file {entry} is a symlink"
    tree = str(target.parent)
    manifest = {str(k): str(v).strip().lower() for k, v in row["leaf_closure"].items()}
    if os.path.commonpath([str(root_real), tree]) != str(root_real):
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
    WITHOUT it, because hiding that setting would hide what `git commit` runs.
    ``GIT_NO_REPLACE_OBJECTS`` is set AFTER the scrub: a ``refs/replace`` entry
    would otherwise substitute HEAD bytes the pre-commit guard never saw.
    ``_git`` also passes ``-c core.useReplaceRefs=false``: a repository-local
    ``core.useReplaceRefs=true`` overrides the variable, command-line config
    outranks it (v15 (b))."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env["GIT_NO_REPLACE_OBJECTS"] = "1"
    if isolate_config:
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_CONFIG_GLOBAL"] = os.devnull
    return env


def _git(args: list[str], cwd: Path, *, isolate_config: bool = True):
    return subprocess.run(
        ["git", "-c", "core.useReplaceRefs=false", "-C", str(cwd), *args],
        env=_git_env(isolate_config=isolate_config),
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
    """Why the repository anchored at ``table_dir`` is not goalforge-guarded.

    ``table_dir`` is the binding's top level. The guard's identity,
    PKG_ROOT/hooks/goalforge-pre-commit.sh, is WALKED like the table
    (``_walk_table``): a symlink at or below the top level (``hooks/`` or the
    hook file) raises AdmissionTableError, so an untracked in-tree symlink
    cannot stand in for the package's own guard (R3-H1)."""
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
    want = str(_walk_table(PRE_COMMIT_HOOK, table_dir, "pre-commit guard"))
    if any(os.path.realpath(p) == want for p in _marker_hook_paths(text)):
        return None
    return (
        f"the table's repository is unguarded: {pre_commit} carries no "
        f"goalforge installer marker block invoking {PRE_COMMIT_HOOK} "
        "(install it with scripts/goalforge-install-hooks.sh)"
    )


# The pre-commit guard's own path set (hooks/goalforge-pre-commit.sh): a table
# admits only from a HEAD path this set matches END TO END — ``re.fullmatch``,
# never ``re.search`` with ``$`` / ``\Z`` (a newline-suffixed or
# ``evilreferences/`` name defeats those).
TABLE_GUARD_SET = re.compile(r"(?:.*/)?references/admitted-providers\.yaml")


def _control_char(text: str) -> bool:
    return any(ord(c) < 32 or ord(c) == 127 for c in text)


def repo_rel(path: Path, what: str) -> tuple[Path, str]:
    """``(file directory, path relative to its PHYSICAL work-tree toplevel)``.

    ``path`` is the caller's ONE resolution of the file (a real path); nothing
    here resolves it again. ``git rev-parse --show-toplevel`` is always
    physical, so a symlinked ancestor is not refused. Outside a work tree
    raises AdmissionTableError (failed CLOSED)."""
    file_dir = path.parent
    try:
        top = _git(["rev-parse", "--show-toplevel"], file_dir)
    except OSError as exc:
        raise AdmissionTableError(
            f"{what} {path}: git is not runnable ({exc}) — HEAD binding "
            "failed CLOSED"
        ) from exc
    if top.returncode != 0:
        raise AdmissionTableError(
            f"{what} {path} is outside a git work tree — the HEAD "
            "binding cannot be checked, failed CLOSED"
        )
    toplevel = top.stdout.decode("utf-8", "surrogateescape").rstrip("\n")
    rel = os.path.relpath(path, toplevel)
    if not path.is_absolute() or rel == os.pardir or rel.startswith(os.pardir + os.sep):
        raise AdmissionTableError(
            f"{what} {path} is not under its work tree's toplevel {toplevel} — "
            "HEAD binding failed CLOSED"
        )
    return file_dir, Path(rel).as_posix()


def is_tracked(path: Path, what: str) -> bool:
    """Whether ``path`` (a real path, resolved by the caller) is in the INDEX
    of the repository enclosing it (``git ls-files --error-unmatch``).

    A staged-but-uncommitted file IS tracked. Outside a work tree, or a
    git failure other than "not in the index", raises AdmissionTableError
    (failed CLOSED)."""
    file_dir, _ = repo_rel(path, what)
    res = _git(["ls-files", "--error-unmatch", "--", path.name], file_dir)
    if res.returncode == 0:
        return True
    if res.returncode == 1:
        return False
    raise AdmissionTableError(
        f"{what} {path}: git ls-files failed (exit {res.returncode}) — failed CLOSED"
    )


def _show_head(cwd: Path, rel: str, what: str, path: Path) -> bytes:
    """``git -C <cwd> show HEAD:<rel>`` bytes; absent from HEAD raises."""
    head = _git(["show", f"HEAD:{rel}"], cwd)
    if head.returncode != 0:
        raise AdmissionTableError(
            f"{what} {path} is absent from HEAD (git show HEAD:{rel} "
            f"found nothing) — an uncommitted {what} is a HEAD mismatch, refused"
        )
    return head.stdout


def head_bytes(path: Path, what: str = "WP overview") -> tuple[bytes, str]:
    """``(git show HEAD:<rel> bytes, rel)`` of the repository enclosing ``path``.

    The BRIEF's HEAD read (the table is bound by ``bind_table`` instead).
    ``path`` is the caller's ONE resolution; this resolves nothing. Read with
    every ``GIT_*`` variable scrubbed; outside a work tree and absent from HEAD
    each raise AdmissionTableError with its own reason, never a skipped read."""
    file_dir, rel = repo_rel(path, what)
    return _show_head(file_dir, rel, what, path), rel


@dataclass(frozen=True)
class TableBinding:
    """The HEAD-bound table's ONE resolution (``bind_table``)."""

    path: Path   # the walked physical table path, inside realpath(PKG_ROOT)
    top: Path    # the physical work-tree top level of realpath(PKG_ROOT)
    rel: str     # ``path`` relative to ``top``


def _within(root: Path, path: Path) -> bool:
    return os.path.commonpath([str(root), str(path)]) == str(root)


def _walk_table(table_path: Path, top: Path, what: str = "admission table") -> Path:
    """Walk ``table_path`` component by component (no full realpath).

    A symlink component located at or below the physical top level ``top`` —
    the file, its directory or any directory between — is refused; a symlink
    component above ``top`` (``~/.claude -> dotfiles/claude``) is resolved
    with one full realpath, which follows its whole target chain. Returns the
    walked physical path. ``what`` names the path in the refusal (the table,
    or the pre-commit guard ``_guard_reason`` walks the same way)."""
    table_path = Path(table_path)
    walked = Path(table_path.anchor) if table_path.is_absolute() else Path(os.getcwd())
    parts = table_path.parts[1:] if table_path.is_absolute() else table_path.parts
    last = len(parts) - 1
    for i, part in enumerate(parts):
        if part == os.pardir:
            walked = walked.parent
            continue
        step = walked / part
        if step.is_symlink() and _within(top, step):
            raise AdmissionTableError(
                f"{what} {table_path}: {step} is a symlink located inside "
                f"the package work tree {top} (component {i + 1} of {last + 1}) — "
                "the binding refuses it, HEAD binding refused"
            )
        if step.is_symlink():
            step = Path(os.path.realpath(step))
        walked = step
    return walked


def _bind_own_script(top: Path) -> None:
    """Refuse unless this script is the committed blob at its tracked path.

    realpath(``__file__``) relative to ``top`` must be present in HEAD with
    the running file's exact bytes (``git -C <top> show HEAD:<rel>``)."""
    own = Path(os.path.realpath(__file__))
    rel = Path(os.path.relpath(own, top)).as_posix()
    try:
        running = own.read_bytes()
    except OSError as exc:
        raise AdmissionTableError(
            f"admission script {own} cannot be read ({exc}) — HEAD binding "
            "failed CLOSED"
        ) from exc
    if _show_head(top, rel, "admission script", own) != running:
        raise AdmissionTableError(
            f"admission script {own} differs from git show HEAD:{rel} — the "
            "package identity is the committed script, HEAD binding refused"
        )


def bind_table() -> TableBinding:
    """The ONE shared binding of the HEAD-bound table (wp-08 T13, H1-v8).

    Called by BOTH bound callers — the compile's
    ``resolve_and_log(bind_head=True)`` and the wrapper's ``verify_leaf`` —
    never by ``resolve_admitted_path`` (``--test-tiers`` and pick-agent
    ``main()`` need no git work tree). It binds ONLY the canonical table,
    ``ADMITTED_PATH`` read at call time — no caller selects a table (v15 (a)).
    The top level is that of realpath(PKG_ROOT) (``git rev-parse
    --show-toplevel``; none fails CLOSED) and must contain realpath(PKG_ROOT):
    a repository-local ``core.worktree`` can move it below the package (v15
    (c)). PKG_ROOT comes from this script's own location, so that location is
    bound too (R3-H1): realpath(``__file__``) must be committed at its path
    under the top level and byte-equal to that HEAD blob — an untracked copy
    or a hard link at a stray path is absent from HEAD and refused; a hard
    link AT the tracked path is the file itself. The walk (``_walk_table``)
    refuses any symlink at or below the top level; the walked path must lie
    inside realpath(PKG_ROOT); rel is taken against the top level. Every git
    call of the binding then runs ``git -C <top>``, so no linked worktree,
    nested or foreign repository, and no path swapped in after the walk
    supplies the HEAD bytes."""
    table_path = ADMITTED_PATH
    pkg_real = Path(os.path.realpath(PKG_ROOT))
    try:
        res = _git(["rev-parse", "--show-toplevel"], pkg_real)
    except OSError as exc:
        raise AdmissionTableError(
            f"admission table {table_path}: git is not runnable ({exc}) — HEAD "
            "binding failed CLOSED"
        ) from exc
    if res.returncode != 0:
        raise AdmissionTableError(
            f"admission table {table_path}: the package root {pkg_real} is outside "
            "a git work tree — the HEAD binding cannot be checked, failed CLOSED"
        )
    top = Path(res.stdout.decode("utf-8", "surrogateescape").rstrip("\n"))
    if not _within(top, pkg_real):
        raise AdmissionTableError(
            f"admission table {table_path}: the work-tree top level {top} does not "
            f"contain the package root {pkg_real} — HEAD binding failed CLOSED"
        )
    _bind_own_script(top)
    walked = _walk_table(table_path, top)
    if not _within(pkg_real, walked):
        raise AdmissionTableError(
            f"admission table {table_path} walks to {walked}, outside the package "
            f"root {pkg_real} — HEAD binding refused"
        )
    rel = os.path.relpath(walked, top)
    return TableBinding(walked, top, Path(rel).as_posix())


def verify_head_binding(binding: TableBinding, raw: bytes) -> None:
    """Refuse table bytes that are not the table's committed HEAD content.

    ``binding`` is the caller's ONE resolution (``bind_table``); ``raw`` are
    the bytes the caller already read from ``binding.path`` and parsed (read
    once). The HEAD read and the guarded-repository check run at the
    binding's top level with its rel — never at the table's own directory —
    and resolve nothing. The guard-set ``fullmatch`` and the control-character
    refusal are defense in depth (the walk already pins the production path).
    Raises AdmissionTableError with a distinct reason per failure."""
    path, top, rel = binding.path, binding.top, binding.rel
    if _control_char(rel):
        raise AdmissionTableError(
            f"admission table {path}: its repository path {rel!r} contains a "
            "control character — HEAD binding refused"
        )
    if not TABLE_GUARD_SET.fullmatch(rel):
        raise AdmissionTableError(
            f"admission table {path} resolves to {rel!r} in its repository, outside the "
            "guarded set (?:.*/)?references/admitted-providers.yaml — the "
            "pre-commit guard never filters it, HEAD binding refused"
        )
    head = _show_head(top, rel, "admission table", path)
    if head != raw:
        raise AdmissionTableError(
            f"admission table {path} differs from git show HEAD:{rel} — HEAD "
            "mismatch: only the committed table admits, refused"
        )
    unguarded = _guard_reason(top)
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
    root_real, target = leaf_target(root or default_leaf_root(), declared)
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
    return closure_mismatch(row, root_real, target)


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


def verify_leaf(klass: str, provider: str, model: str, *,
                leaf_root: Path | None = None) -> Path:
    """Re-derive and re-check the admitted leaf for one row key (the wrapper).

    Binds the canonical table through ``bind_table`` (walk, package-root containment,
    git at the package's top level), reads it once, requires those bytes to be
    the committed HEAD content (``verify_head_binding``), takes the row's ``leaf``,
    ``leaf_sha256`` and ``leaf_closure`` from THAT table only, requires the
    leaf's real path to lie under the leaf root and re-hashes it and its
    closure (``closure_mismatch``). Returns the real path to execute.
    Raises AdmissionTableError on any failure — the leaf is never run then."""
    # The table path's ONE resolution is the shared binding helper, the same
    # one the compile uses: the byte read, the HEAD read and the guard check
    # below all take it and resolve nothing again.
    binding = bind_table()
    table_path = binding.path
    raw = read_table(table_path)
    verify_head_binding(binding, raw)
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
    root, target = leaf_target(leaf_root or default_leaf_root(), str(row["leaf"]))
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
    unbound = closure_mismatch(row, root, target)
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
    p.add_argument("--verify-leaf", nargs=3,
                   metavar=("TASK_CLASS", "PROVIDER", "MODEL"),
                   default=None,
                   help="scripts/goalforge-leaf-exec.sh's check: print the real "
                        "path of the admitted leaf for this row key, exit 2 "
                        "unless the HEAD-bound table, the leaf root and the "
                        "leaf hash all hold.")
    args = p.parse_args(argv)

    try:
        if args.verify_leaf:
            klass, provider, model = args.verify_leaf
            print(verify_leaf(klass, provider, model))
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
