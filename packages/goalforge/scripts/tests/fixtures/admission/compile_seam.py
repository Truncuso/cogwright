"""compile_seam.py — drive goalforge-workflow-compile.py IN-PROCESS (wp-08).

The compiler has no admission-table option by design (ruling 1, option A):
the only route to a table is the in-process attribute
``goalforge_admission.ADMITTED_PATH``, read at call time by pick-agent. This
probe loads a compiler by path, patches THAT attribute (never a compiler-local
copy), optionally wraps ``resolve_and_log`` with a call-counting spy, and runs
the compiler's own ``main()`` — the shipped CLI surface — with the given argv.

    python3 compile_seam.py compile <compile.py> <table|-> <spy.json|-> -- <argv...>
        table '-' leaves ADMITTED_PATH unpatched (the canonical table).
        Exit status is main()'s.
    python3 compile_seam.py cli <compile.py>
        Prints {dest of each positional} ∪ {option strings}, one per line.
    python3 compile_seam.py default-source <pick-agent.py>
        Prints resolve_admitted_path(None)[1] with nothing patched.
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


def _load(path: str, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _compile(argv: list[str]) -> int:
    compile_path, table, spy_out, sep, *rest = argv
    if sep != "--":
        raise SystemExit("usage: compile <compile.py> <table|-> <spy|-> -- <argv...>")
    module = _load(compile_path, "goalforge_workflow_compile")
    pick = module.pick_agent
    if table != "-":
        # THE seam: the admission module's own attribute, the object pick-agent
        # reads at call time. Equal to sys.modules["goalforge_admission"].
        pick.admission.ADMITTED_PATH = Path(table)
    record = {"calls": 0, "decisions": []}
    if spy_out != "-":
        real = pick.resolve_and_log

        def spy(*args, **kwargs):
            record["calls"] += 1
            result = real(*args, **kwargs)
            record["decisions"].append(result.get("admission_decision"))
            return result

        pick.resolve_and_log = spy
    try:
        return module.main(rest)
    finally:
        if spy_out != "-":
            Path(spy_out).write_text(json.dumps(record), encoding="utf-8")


def _cli(argv: list[str]) -> int:
    module = _load(argv[0], "goalforge_workflow_compile")
    names: set[str] = set()
    for action in module._build_cli()._actions:
        if action.option_strings:
            names.update(action.option_strings)
        else:
            names.add(action.dest)
    print("\n".join(sorted(names)))
    return 0


def _default_source(argv: list[str]) -> int:
    module = _load(argv[0], "goalforge_pick_agent")
    print(module.resolve_admitted_path(None)[1])
    return 0


if __name__ == "__main__":
    mode, *args = sys.argv[1:]
    sys.exit({"compile": _compile, "cli": _cli, "default-source": _default_source}[mode](args))
