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


if __name__ == "__main__":
    mode, target = sys.argv[1], sys.argv[2]
    check = {"closure-single-realpath": closure_single_realpath,
             "single-resolution": single_resolution}[mode]
    sys.exit(0 if check(target) else 1)
