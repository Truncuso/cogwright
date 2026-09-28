"""structural.py — AST assertions over goalforge-admission.py (wp-08 T9, T10).

Two no-discriminator structural checks (no deterministic case can show the
swap race they narrow); each prints one `ok ...` / `bad ...` line per check.

    python3 structural.py closure-single-realpath <goalforge-admission.py>
        T9: closure_mismatch takes the caller-resolved target (a `target`
        parameter) and makes ZERO resolve()/realpath/abspath calls — the
        entry is resolved once, by the caller (leaf_target).
    python3 structural.py single-resolution <goalforge-admission.py>
        T10: repo_rel, head_bytes, is_tracked and verify_head_binding make
        ZERO resolve()/realpath/abspath calls; _guard_reason's realpath calls
        take ONLY the hook paths (PRE_COMMIT_HOOK, a marker-block path `p`),
        never the table path, `table_dir` or anything derived from them.
    python3 structural.py table-anchor <goalforge-admission.py>
        T13 (2): verify_head_binding's HEAD read and _guard_reason take the
        binding's top level (`top`, bound only from `binding.top`).
    python3 structural.py shared-binding <goalforge-admission.py>
        T13 (1): verify_leaf calls bind_table and resolves nothing itself.
"""
from __future__ import annotations

import ast
import sys

RESOLVERS = {"resolve", "realpath", "abspath"}
HOOK_ARGS = {"PRE_COMMIT_HOOK", "p"}


def _functions(path: str) -> dict[str, ast.FunctionDef]:
    tree = ast.parse(open(path, encoding="utf-8").read(), path)
    return {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}


def _resolver_calls(fn: ast.FunctionDef) -> list[ast.Call]:
    calls = []
    for node in ast.walk(fn):
        if isinstance(node, ast.Call):
            f = node.func
            name = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
            if name in RESOLVERS:
                calls.append(node)
    return calls


def closure_single_realpath(path: str) -> bool:
    fns = _functions(path)
    fn = fns.get("closure_mismatch")
    if fn is None:
        print("bad T9 structural: no closure_mismatch in", path)
        return False
    params = [a.arg for a in fn.args.args]
    calls = _resolver_calls(fn)
    if "target" in params and not calls:
        print("ok T9 structural: closure_mismatch takes the resolved target, "
              "zero realpath/resolve/abspath calls on the entry")
        return True
    print(f"bad T9 structural: closure_mismatch params {params}, "
          f"{len(calls)} resolver call(s) at line(s) {[c.lineno for c in calls]}")
    return False


def single_resolution(path: str) -> bool:
    fns = _functions(path)
    good = True
    for name in ("repo_rel", "head_bytes", "is_tracked", "verify_head_binding"):
        fn = fns.get(name)
        if fn is None:
            print(f"bad single-resolution: no {name} in {path}")
            good = False
            continue
        calls = _resolver_calls(fn)
        if calls:
            print(f"bad single-resolution: {name} resolves again at line(s) "
                  f"{[c.lineno for c in calls]}")
            good = False
    fn = fns.get("_guard_reason")
    if fn is None:
        print(f"bad single-resolution: no _guard_reason in {path}")
        return False
    for call in _resolver_calls(fn):
        args = [a.id for a in call.args if isinstance(a, ast.Name)]
        if len(call.args) != 1 or not args or args[0] not in HOOK_ARGS:
            print(f"bad single-resolution: _guard_reason resolves a non-hook path "
                  f"at line {call.lineno}")
            good = False
    if good:
        print("ok single-resolution: repo_rel/head_bytes/is_tracked/"
              "verify_head_binding resolve nothing; _guard_reason resolves only "
              "the hook paths")
    return good


_BINDING_TOP = "binding.top"


def _anchor_calls(fn: ast.FunctionDef) -> list[tuple[str, ast.expr | None]]:
    """(callee, its repository-anchor argument) for every git-anchored call:
    ``_show_head``/``_git`` take it second, ``_guard_reason`` first."""
    out = []
    for node in ast.walk(fn):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            pos = {"_show_head": 0, "_git": 1, "_guard_reason": 0}.get(node.func.id)
            if pos is not None:
                out.append((node.func.id, node.args[pos] if len(node.args) > pos else None))
    return out


def table_anchor(path: str) -> bool:
    """T13 (2): the table HEAD read and ``_guard_reason`` run at the binding's
    top level — every anchor argument in verify_head_binding is the name
    ``top``, and ``top`` is bound ONLY from ``binding.top``."""
    fn = _functions(path).get("verify_head_binding")
    if fn is None:
        print(f"bad table-anchor: no verify_head_binding in {path}")
        return False
    good = True
    calls = _anchor_calls(fn)
    names = {c for c, _ in calls}
    if not {"_show_head", "_guard_reason"} <= names:
        print(f"bad table-anchor: verify_head_binding makes no HEAD read or guard check ({sorted(names)})")
        good = False
    for callee, arg in calls:
        if not (isinstance(arg, ast.Name) and arg.id == "top"):
            print(f"bad table-anchor: {callee} is anchored at "
                  f"{ast.unparse(arg) if arg is not None else None}, not the binding's top level")
            good = False
    for node in ast.walk(fn):
        if not isinstance(node, ast.Assign):
            continue
        for target in node.targets:
            elts = target.elts if isinstance(target, ast.Tuple) else [target]
            for i, elt in enumerate(elts):
                if not (isinstance(elt, ast.Name) and elt.id == "top"):
                    continue
                value = (node.value.elts[i] if isinstance(target, ast.Tuple)
                         and isinstance(node.value, ast.Tuple) else node.value)
                if ast.unparse(value) != _BINDING_TOP:
                    print(f"bad table-anchor: top is bound from {ast.unparse(node.value)} "
                          f"at line {node.lineno}, not {_BINDING_TOP}")
                    good = False
    if good:
        print("ok table-anchor: the table HEAD read and _guard_reason run at "
              "binding.top, never at the table's own directory")
    return good


def shared_binding(path: str) -> bool:
    """T13 (1): verify_leaf binds the table through the shared helper
    ``bind_table`` and makes no resolve()/realpath/abspath call of its own."""
    fn = _functions(path).get("verify_leaf")
    if fn is None:
        print(f"bad shared-binding: no verify_leaf in {path}")
        return False
    helper = any(isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
                 and n.func.id == "bind_table" for n in ast.walk(fn))
    calls = _resolver_calls(fn)
    if helper and not calls:
        print("ok shared-binding: verify_leaf calls bind_table and resolves "
              "nothing itself")
        return True
    print(f"bad shared-binding: verify_leaf bind_table call={helper}, "
          f"resolver call(s) at line(s) {[c.lineno for c in calls]}")
    return False


if __name__ == "__main__":
    mode, target = sys.argv[1], sys.argv[2]
    check = {"closure-single-realpath": closure_single_realpath,
             "single-resolution": single_resolution,
             "table-anchor": table_anchor,
             "shared-binding": shared_binding}[mode]
    sys.exit(0 if check(target) else 1)
