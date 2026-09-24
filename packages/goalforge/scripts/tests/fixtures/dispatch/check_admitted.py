"""check_admitted.py — the b1 structural oracle over workflow_probe.mjs output (wp-08).

    python3 check_admitted.py <probe exit 0 .json> <probe exit 1 .json> <task_class> <provider> <model>

Prints one line per check, ``ok <name>`` or ``bad <name>: <detail>``; the
calling test counts them. Every check reads what the compiled script DID under
stub hooks (which stage each agent() ran in, what the pipeline items carried),
never the script text.
"""
from __future__ import annotations

import json
import shlex
import sys

CLAUDE_TIERS = {"sonnet", "opus", "haiku"}
WRAPPER = "scripts/goalforge-leaf-exec.sh"


def main(argv: list[str]) -> int:
    ok_run = json.load(open(argv[0], encoding="utf-8"))
    bad_run = json.load(open(argv[1], encoding="utf-8"))
    klass, provider, model = argv[2:5]
    results: list[tuple[str, bool, str]] = []

    def check(name: str, cond: object, detail: object = "") -> None:
        results.append((name, bool(cond), str(detail)))

    pipes = ok_run["pipelines"]
    check("one pipeline carrying ONE leg item", len(pipes) == 1 and len(pipes[0]["items"]) == 1, pipes)
    leg = pipes[0]["items"][0] if pipes and pipes[0]["items"] else {}
    check("leg carries provider + model", leg.get("provider") == provider and leg.get("model") == model, leg)
    check("leg carries an EXPLICIT effort", isinstance(leg.get("effort"), str) and leg.get("effort"), leg.get("effort"))
    check("leg carries evidence_ref", bool(leg.get("evidence_ref")), leg.get("evidence_ref"))
    check("leg carries permission_set", isinstance(leg.get("permission_set"), list) and leg.get("permission_set"), leg.get("permission_set"))
    cont = leg.get("containment") or {}
    check("leg carries the containment block",
          isinstance(cont, dict) and "owned_files" in cont and "verification_command" in cont
          and cont.get("commit") is False, cont)
    check("leg carries leaf + leaf_sha256", bool(leg.get("leaf")) and len(str(leg.get("leaf_sha256"))) == 64, leg)
    check("leg carries the declared-not-enforced marker (enforced: false)", leg.get("enforced") is False, leg.get("enforced"))

    call = str(leg.get("wrapper_call", ""))
    argv_call = shlex.split(call) if call else []
    check("wrapper call is the pinned wrapper keyed by EXACTLY the row key (no hash, no table)",
          argv_call == [WRAPPER, klass, provider, model], argv_call)
    check("wrapper call never names the leaf directly",
          leg.get("leaf") and all(leg["leaf"] not in part for part in argv_call), argv_call)

    agents = [e for e in ok_run["events"] if e["kind"] == "agent"]
    check("runner exit 0: three agent() calls (runner, gate B, gate C)", len(agents) == 3, [a.get("label") for a in agents])
    runner = agents[0] if agents else {}
    props = ((runner.get("schema") or {}).get("properties") or {})
    check("stage 1 is the NATIVE runner agent() with schema {exit_code, stderr}",
          runner.get("stage") == 1 and set(props) == {"exit_code", "stderr"}
          and runner.get("model") in CLAUDE_TIERS and bool(runner.get("effort")), runner)
    check("the runner's only action is the emitted wrapper call, verbatim",
          call and call in str(runner.get("prompt", "")), runner.get("prompt"))
    stages = {a.get("label"): a.get("stage") for a in agents}
    check("gate B is a later pipeline stage than the runner", stages.get("gate B", 0) > 1, stages)
    check("gate C is a later pipeline stage than the runner", stages.get("gate C", 0) > 1, stages)
    check("no agent() node carries the foreign model or a non-Claude tier",
          all(a.get("model") in CLAUDE_TIERS and a.get("model") != model for a in agents),
          [a.get("model") for a in agents])
    check("no agent() node carries the foreign provider",
          all(a.get("provider") in (None,) for a in agents), [a.get("provider") for a in agents])
    logs = [e["message"] for e in ok_run["events"] if e["kind"] == "log"]
    check("the wrapper call is never a log() line", call and all(call not in m for m in logs), logs)

    bad_agents = [e for e in bad_run["events"] if e["kind"] == "agent"]
    check("runner exit 1: gate B and gate C do NOT run (conditioned on exit_code == 0)",
          [a.get("label") for a in bad_agents] == [runner.get("label")], [a.get("label") for a in bad_agents])

    for name, passed, detail in results:
        print(f"ok {name}" if passed else f"bad {name}: {detail}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
