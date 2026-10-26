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
    python3 structural.py canonical-only <goalforge-admission.py>
        v15 (a): no table-path parameter on bind_table / verify_leaf /
        --verify-leaf, and the sibling wrapper passes only the row key.
    python3 structural.py own-script-once <goalforge-admission.py>
        M1-r4a: the script's own path is resolved ONCE at module scope
        (`_OWN`, assigned exactly once; PKG_ROOT = _OWN.parent.parent) and
        _bind_own_script binds `_OWN` with ZERO resolve()/realpath/abspath
        calls of its own.
"""
from __future__ import annotations

import ast
import os
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


_WRAPPER_CALL = '--verify-leaf "$1" "$2" "$3")'


def canonical_only(path: str) -> bool:
    """v15 (a): bind_table and verify_leaf take no table-path parameter,
    ``--verify-leaf`` takes exactly the 3-part row key, and the sibling
    goalforge-leaf-exec.sh passes exactly that key."""
    fns = _functions(path)
    good = True
    bind, leaf = fns.get("bind_table"), fns.get("verify_leaf")
    if bind is None or bind.args.args or bind.args.kwonlyargs:
        print(f"bad canonical-only: bind_table takes parameters or is missing in {path}")
        good = False
    if leaf is None or [a.arg for a in leaf.args.args] != ["klass", "provider", "model"]:
        print(f"bad canonical-only: verify_leaf positional parameters are not "
              f"(klass, provider, model) in {path}")
        good = False
    nargs = [kw.value.value for n in ast.walk(ast.parse(open(path, encoding="utf-8").read()))
             if isinstance(n, ast.Call) and n.args
             and isinstance(n.args[0], ast.Constant) and n.args[0].value == "--verify-leaf"
             for kw in n.keywords if kw.arg == "nargs" and isinstance(kw.value, ast.Constant)]
    if nargs != [3]:
        print(f"bad canonical-only: --verify-leaf nargs {nargs}, want [3]")
        good = False
    wrapper = os.path.join(os.path.dirname(path), "goalforge-leaf-exec.sh")
    text = open(wrapper, encoding="utf-8").read()
    if text.count("--verify-leaf") != 1 or _WRAPPER_CALL not in text:
        print(f"bad canonical-only: {wrapper} does not pass exactly the row key "
              f"({_WRAPPER_CALL!r})")
        good = False
    if good:
        print("ok canonical-only: bind_table and verify_leaf take no table path, "
              "--verify-leaf and the wrapper pass only the row key")
    return good


def own_script_once(path: str) -> bool:
    tree = ast.parse(open(path, encoding="utf-8").read(), path)
    good = True
    own = [n for n in tree.body if isinstance(n, ast.Assign)
           and any(isinstance(t, ast.Name) and t.id == "_OWN" for t in n.targets)]
    pkg = [n for n in tree.body if isinstance(n, ast.Assign)
           and any(isinstance(t, ast.Name) and t.id == "PKG_ROOT" for t in n.targets)]
    if len(own) != 1:
        print(f"bad own-script-once: _OWN is assigned {len(own)} time(s) at module scope, want 1")
        good = False
    if len(pkg) != 1 or ast.unparse(pkg[0].value) != "_OWN.parent.parent":
        print("bad own-script-once: PKG_ROOT is not derived as _OWN.parent.parent")
        good = False
    fn = _functions(path).get("_bind_own_script")
    if fn is None:
        print(f"bad own-script-once: no _bind_own_script in {path}")
        return False
    calls = _resolver_calls(fn)
    uses = any(isinstance(n, ast.Name) and n.id == "_OWN" for n in ast.walk(fn))
    if calls or not uses:
        print(f"bad own-script-once: _bind_own_script binds _OWN={uses}, resolves "
              f"again at line(s) {[c.lineno for c in calls]}")
        good = False
    if good:
        print("ok own-script-once: the script path is resolved once at module "
              "scope; PKG_ROOT and _bind_own_script both take _OWN")
    return good


if __name__ == "__main__":
    mode, target = sys.argv[1], sys.argv[2]
    check = {"closure-single-realpath": closure_single_realpath,
             "single-resolution": single_resolution,
             "table-anchor": table_anchor,
             "shared-binding": shared_binding,
             "canonical-only": canonical_only,
             "own-script-once": own_script_once}[mode]
    sys.exit(0 if check(target) else 1)
