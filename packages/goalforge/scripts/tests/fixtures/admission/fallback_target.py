"""fallback_target.py — S-1, the native-FALLBACK leg of the kind-coherence check.

`load_dispatch` refuses a dispatch FILE carrying an incoherent native row, so
the fallback-target check is only reachable through the library entry point:
`resolve_stage()` takes an already-parsed dispatch mapping, which a caller can
hand it without going through the loader. This probe does exactly that — a
refused foreign implement row whose only `kind: native` fallback target carries
an agent-dispatch leaf.

Prints ``REFUSED <reason>`` when the resolver fails closed, or
``RESOLVED <provider>`` when it resolves the incoherent target anyway.

    python3 fallback_target.py <path to goalforge-pick-agent.py>
"""
from __future__ import annotations

import importlib.util
import sys

FRONTMATTER: dict = {
    "task_type": "code",
    "owned_files": ["one.py"],
    "register": "production",
    "severity": "HIGH",
}

DISPATCH: dict = {
    "providers": [
        # Declares `native` and carries a leaf: the fallback must not resolve it.
        {"name": "anthropic", "kind": "native",
         "leaf": "skills/agent-dispatch/ollama/scripts/headless_dispatch",
         "propose_only": False},
        {"name": "stub-b", "kind": "foreign",
         "leaf": "skills/agent-dispatch/stub-b/scripts/headless_dispatch",
         "propose_only": True},
    ],
    "stages": {
        "implement": {
            "model": "by_register", "effort": "by_register",
            "provider": "stub-b", "endpoint": "leaf", "egress": "overview",
        },
    },
}


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: fallback_target.py <goalforge-pick-agent.py>", file=sys.stderr)
        return 2
    spec = importlib.util.spec_from_file_location("goalforge_pick_agent", argv[1])
    if spec is None or spec.loader is None:
        print(f"ERROR: cannot import {argv[1]}", file=sys.stderr)
        return 2
    pick = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = pick
    spec.loader.exec_module(pick)
    try:
        result = pick.resolve_stage(
            "implement", FRONTMATTER, [], DISPATCH, {}, admitted=[],
        )
    except ValueError as exc:
        print(f"REFUSED {exc}")
        return 0
    print(f"RESOLVED {result.get('provider')}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
