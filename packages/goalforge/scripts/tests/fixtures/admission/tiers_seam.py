"""tiers_seam.py — run goalforge-pick-agent.py --test-tiers IN-PROCESS on fixtures (wp-08 T4).

``--test-tiers`` reads the dispatch file through ``load_dispatch()`` (which
reads the module's ``DISPATCH_PATH`` at call time) and the admission table
through ``goalforge_admission.ADMITTED_PATH``. Both are patched here, in
process; the CLI grows no flag for either.

    python3 tiers_seam.py <pick-agent.py> <dispatch.yaml|-> <table|->

'-' leaves that input unpatched (the shipped file). Exit status and output are
``_test_tiers()``'s own (failures on stderr, one ``FAIL:`` line each).
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from typing import Any


def main(argv: list[str]) -> int:
    pick_path, dispatch, table = argv
    spec = importlib.util.spec_from_file_location("goalforge_pick_agent", pick_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"cannot load {pick_path}")
    module: Any = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    if dispatch != "-":
        module.DISPATCH_PATH = Path(dispatch)
    if table != "-":
        module.admission.ADMITTED_PATH = Path(table)
    return module._test_tiers()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
