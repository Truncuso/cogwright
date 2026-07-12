"""sdd-goal-eval — pure goal-completion router + effective-goal resolver (schema v4).

The PURE half of the simulated `/goal` loop (design §4). It decides
deterministic/numeric goals in-script (binary signal) and, for judge/human,
RETURNS a directive — it never dispatches a skill or runs AskUserQuestion.
The `sdd-execute` agent (WP-03) acts on the directive.

Public API:
    resolve_effective_goal(wp_fm, *, spec_fm=None, legacy=None) -> dict
        Single back-compat owner. WP goal block ⊕ inherited spec fields
        (per-field cascade) + legacy fallback. WP-03 calls THIS, never
        re-implements cascade/fallback.

    default_strategy_for(task_type) -> str | None
        Default-only task_type→strategy lookup. An explicit WP strategy
        always wins (callers apply this only when strategy is unset).

    evaluate(effective_goal, *, run=subprocess-based) -> dict
        The pure router. Returns {met, reason, strategy, directive?}.
        deterministic/numeric → met decided here; judge/human → directive only.

CLI:
    python3 sdd-goal-eval.py --wp <overview.md> [--spec <spec.md>]
      → prints the verdict JSON; exit 0 iff met (for deterministic/numeric).
      For judge/human the directive is emitted and exit is 2 (not-decided-here).
"""
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path
from typing import Any, Callable, Optional

try:
    import yaml
except ImportError as exc:  # pragma: no cover
    raise SystemExit("PyYAML required: pip install pyyaml") from exc


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

STRATEGY_ENUM = {"deterministic", "numeric", "judge", "human"}
NUMERIC_OPS: dict[str, Callable[[float, float], bool]] = {
    "<":  lambda a, b: a < b,
    "<=": lambda a, b: a <= b,
    ">":  lambda a, b: a > b,
    ">=": lambda a, b: a >= b,
    "==": lambda a, b: a == b,
    "!=": lambda a, b: a != b,
}

# Default-only: supplies a strategy when the WP omits one. Explicit always wins.
TASK_TYPE_DEFAULT_STRATEGY: dict[str, str] = {
    "code":         "deterministic",
    "research":     "deterministic",
    "ops":          "deterministic",
    "writing":      "judge",
    "optimization": "numeric",
    "analysis":     "judge",
}

# Fields that never cascade from the spec (each goal declares its own).
_NEVER_INHERIT = ("outcome", "verification")
_SCALAR_FIELDS = ("iteration_policy", "blocked_stop")
_LIST_FIELDS = ("constraints", "boundaries")


# ---------------------------------------------------------------------------
# Effective-goal resolution (single back-compat owner)
# ---------------------------------------------------------------------------

def _union_dedupe(wp_list: Optional[list], spec_list: Optional[list]) -> list:
    """WP ∪ spec, order-preserving, deduped — a WP never drops a spec constraint."""
    out: list = []
    for item in list(wp_list or []) + list(spec_list or []):
        if item not in out:
            out.append(item)
    return out


def resolve_effective_goal(
    wp_fm: dict,
    *,
    spec_fm: Optional[dict] = None,
    legacy: Optional[dict] = None,
) -> dict:
    """Resolve the effective goal for a WP. The ONE place cascade + legacy live.

    Args:
        wp_fm:   the WP overview.md frontmatter (dict).
        spec_fm: the inherited feature spec frontmatter, when `inherits_from`
                 is set and the spec exists (caller loads it; this stays pure).
        legacy:  optional {outcome, check} derived from a WP that has no goal
                 block (legacy `## Goal` + task `verify:`); treated as
                 strategy=deterministic.

    Returns: a complete goal dict {outcome, verification:{strategy,check},
             constraints, boundaries, iteration_policy, blocked_stop, task_type}.
    """
    goal = wp_fm.get("goal")

    # ── Legacy fallback: no goal block → deterministic from legacy inputs ──
    if not isinstance(goal, dict):
        if legacy is None:
            legacy = {}
        return {
            "outcome": legacy.get("outcome", ""),
            "verification": {
                "strategy": "deterministic",
                "check": legacy.get("check", ""),
            },
            "constraints": [],
            "boundaries": [],
            "iteration_policy": "",
            "blocked_stop": "",
            "task_type": wp_fm.get("task_type"),
            "_legacy": True,
        }

    eff: dict[str, Any] = {}

    # outcome / verification: never inherited — taken verbatim from the WP goal.
    for f in _NEVER_INHERIT:
        eff[f] = goal.get(f)

    spec_goal = (spec_fm or {}).get("goal") if isinstance(spec_fm, dict) else None
    spec_goal = spec_goal if isinstance(spec_goal, dict) else {}

    # scalars: WP overrides; inherit spec only when unset on the WP.
    for f in _SCALAR_FIELDS:
        wp_val = goal.get(f)
        eff[f] = wp_val if wp_val not in (None, "") else spec_goal.get(f, "")

    # lists: union-with-dedupe (WP ∪ spec).
    for f in _LIST_FIELDS:
        eff[f] = _union_dedupe(goal.get(f), spec_goal.get(f))

    # task_type: WP value, else spec's.
    eff["task_type"] = wp_fm.get("task_type") or (spec_fm or {}).get("task_type")

    # default-only strategy: fill from task_type iff the WP omitted strategy.
    ver = eff.get("verification")
    if isinstance(ver, dict) and not ver.get("strategy"):
        default = default_strategy_for(eff.get("task_type"))
        if default:
            ver = dict(ver)
            ver["strategy"] = default
            eff["verification"] = ver

    return eff


def default_strategy_for(task_type: Optional[str]) -> Optional[str]:
    """Default-only lookup. Returns None when task_type has no mapping."""
    if not task_type:
        return None
    return TASK_TYPE_DEFAULT_STRATEGY.get(task_type)


def should_invoke_testing(effective_goal: dict) -> bool:
    """Whether a WP's test authoring should route through the `testing` skill.

    Pure conjunction: the WP is code work (`task_type == 'code'`) AND its goal is
    deterministically verified (`verification.strategy == 'deterministic'`).

    The `task_type == 'code'` clause is load-bearing: `default_strategy_for` maps
    `research`/`ops` → `deterministic` too, so the strategy clause alone would
    over-fire on non-code WPs. A `research+deterministic` goal returns False here.

    Purity mirrors `evaluate`/`default_strategy_for` — script-decides,
    agent-dispatches. This NEVER invokes `testing`; the caller (`sdd-execute`
    Step 5) acts on the returned bool, passing a `use_testing` hint when True.
    """
    if effective_goal.get("task_type") != "code":
        return False
    ver = effective_goal.get("verification") or {}
    return ver.get("strategy") == "deterministic"


# ---------------------------------------------------------------------------
# The pure router
# ---------------------------------------------------------------------------

def _run_cmd(cmd: str) -> subprocess.CompletedProcess:
    """Run a goal `check`/`bench` command, capturing output. Isolated so tests inject.

    Trust boundary: `cmd` originates from the plan's own goal block (a local,
    author-authored plan file) — the same trust level as the engine's existing
    task `verify:` commands. It is NOT external/untrusted input, so `shell=True`
    is consistent with how the SDD engine already runs verification commands.
    """
    return subprocess.run(
        cmd, shell=True, capture_output=True, text=True, check=False,
    )


def evaluate(
    effective_goal: dict,
    *,
    run: Callable[[str], subprocess.CompletedProcess] = _run_cmd,
) -> dict:
    """Pure router. Decide deterministic/numeric; RETURN directives for judge/human.

    Returns {met, reason, strategy, directive?}. Never dispatches a skill and
    never prompts — purity is a hard constraint (design §4).
    """
    ver = effective_goal.get("verification") or {}
    strategy = ver.get("strategy")
    check = ver.get("check")

    if strategy not in STRATEGY_ENUM:
        return {
            "met": False,
            "reason": f"unknown or missing strategy: {strategy!r}",
            "strategy": strategy,
        }

    if strategy == "deterministic":
        if not (isinstance(check, str) and check.strip()):
            return {"met": False, "reason": "deterministic check is empty",
                    "strategy": strategy}
        proc = run(check)
        met = proc.returncode == 0
        reason = ("check passed (exit 0)" if met
                  else f"check failed (exit {proc.returncode})")
        return {"met": met, "reason": reason, "strategy": strategy}

    if strategy == "numeric":
        if not isinstance(check, dict):
            return {"met": False, "reason": "numeric check is not a mapping",
                    "strategy": strategy}
        bench = check.get("bench")
        metric = check.get("metric")
        op = check.get("op")
        threshold = check.get("threshold")
        if op not in NUMERIC_OPS:
            return {"met": False, "reason": f"invalid op: {op!r}",
                    "strategy": strategy}
        proc = run(str(bench))
        if proc.returncode != 0:
            return {"met": False,
                    "reason": f"bench failed (exit {proc.returncode})",
                    "strategy": strategy}
        try:
            data = json.loads(proc.stdout)
            value = data[metric]
        except (json.JSONDecodeError, KeyError, TypeError) as exc:
            return {"met": False,
                    "reason": f"could not extract metric {metric!r}: {exc}",
                    "strategy": strategy}
        # The metric must be numeric to compare — a string/None value (bench bug)
        # would raise TypeError on the comparison; report it as not-met instead.
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return {"met": False,
                    "reason": f"metric {metric!r} is not numeric: {value!r}",
                    "strategy": strategy}
        met = NUMERIC_OPS[op](value, threshold)
        return {"met": met,
                "reason": f"{metric}={value} {op} {threshold} → {met}",
                "strategy": strategy}

    if strategy == "judge":
        # RETURN a directive — the agent dispatches `judge` and maps the verdict.
        if not isinstance(check, dict):
            return {"met": False, "reason": "judge check is not a mapping",
                    "strategy": strategy}
        return {
            "met": None,            # undecided here — the agent decides post-dispatch
            "reason": "judge dispatch required (pure script does not dispatch)",
            "strategy": strategy,
            "directive": {
                "dispatch": "judge",
                "artifact": check.get("artifact"),
                "rubric": check.get("rubric"),
                "block_on": check.get("block_on"),
            },
        }

    # strategy == "human"
    return {
        "met": None,                # non-blocking gate — the agent pauses/exits
        "reason": "human gate (non-blocking in autonomous loop)",
        "strategy": strategy,
        "directive": {"gate": check},
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _load_fm(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        return {}
    return yaml.safe_load("\n".join(lines[1:end])) or {}


def main(argv: Optional[list[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Pure goal-completion router.")
    ap.add_argument("--wp", required=True, help="WP overview.md path")
    ap.add_argument("--spec", help="inherited feature spec.md path (optional)")
    args = ap.parse_args(argv)

    wp_fm = _load_fm(Path(args.wp))
    spec_fm = _load_fm(Path(args.spec)) if args.spec else None
    eff = resolve_effective_goal(wp_fm, spec_fm=spec_fm)
    verdict = evaluate(eff)
    print(json.dumps(verdict, indent=2))

    # Binary exit only for the in-script strategies; judge/human are undecided (2).
    if verdict.get("met") is True:
        return 0
    if verdict.get("met") is False:
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
