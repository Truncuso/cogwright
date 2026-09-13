"""goalforge-workflow-compile — WP checklist → Workflow-tool script (wp-03/T4).

Compiles the `## Checklist` of a WP `overview.md` into a Workflow script under
`run/workflows/<wp-name>.js`. Nothing is dispatched here: the compiler is a
pure text transform whose only configured input is `references/dispatch.yaml`
(`--dispatch <path>`), read as DATA for the per-stage `model`/`effort`.

Node shape — decided by the `{files:}` sets alone:

  1. Two checklist items CONFLICT when their `{files:}` sets intersect.
  2. Items are LAYERED in checklist order: `layer(i) = 0` when item `i`
     conflicts with no earlier item, else `1 + max(layer(j))` over the earlier
     items it conflicts with. A layer is therefore internally disjoint, and an
     overlap is what pushes an item into a later layer — the `pipeline` edge.
  3. Each layer is PACKED into nodes of at most 5 items, balanced: `n` items
     become `ceil(n / 5)` nodes of as equal a size as the count allows (8 → 4
     and 4, not 5 and 3).
  4. NODE SIZE is 3-5 items. A node with fewer than 3 is emitted only when the
     WP has fewer than 3 items in total, or when the node is the REMAINDER of
     a layer too small to fill. Two conflicting items are never packed into
     one node, whatever the count.

Emission — stage `k` is layer `k`'s nodes:

  * `parallel: true`  (WP frontmatter): a stage holding more than one node is
    emitted as `parallel([...])`; stages are chained with `pipeline(...)`.
  * `parallel: false`: one `pipeline(...)` over every node in checklist order,
    no `parallel([...])` call at all.

After the checklist nodes come TWO gate nodes, each an `agent()` call whose
`{model, effort}` come verbatim from a dispatch stage row:

  gate B → `wp-verify`   gate C → `judge`

Gate A is DETERMINISTIC (lint, typecheck, the WP `goal.verification.command`,
diff ⊆ owned files) — no model decides it, so it gets no `agent()` node at all.
It is emitted as one `log()` line naming that verification command.

The SECOND OPINION likewise gets no `agent()` node: its dispatch row runs on a
non-native provider, so its `model` is a PROVIDER model id that
`agent({model: ...})` cannot dispatch. It is emitted as one `log()` line naming
`scripts/goalforge-second-opinion.sh`. No agent node the compiler emits ever
carries a non-Claude model id.

The emitted script calls exactly five functions — `agent`, `parallel`,
`pipeline`, `phase`, `log` — and opens with `export const meta = {`. It
contains no `Date`, no `Math.random`, no `fs`, no imports, and no control
flow: the body is two `phase()` declarations, three `log()` calls, and one
returned expression, so it is deterministic to read and to diff.

CLI:
    python3 goalforge-workflow-compile.py <wp-overview.md>
        [--dispatch <yaml>] [--expertise <yaml>] [--out <dir>]

Exit codes: 0 compiled (the script path plus a one-line invocation hint on
stdout); 2 usage, unreadable input, no or malformed frontmatter, no checklist item, or an
unresolvable dispatch row.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

import yaml

PKG_ROOT = Path(__file__).resolve().parent.parent
DISPATCH_PATH = PKG_ROOT / "references" / "dispatch.yaml"
DEFAULT_OUT_DIR = PKG_ROOT / "run" / "workflows"
PICK_AGENT_PATH = Path(__file__).resolve().parent / "goalforge-pick-agent.py"

MIN_NODE = 3
MAX_NODE = 5

# gate label → dispatch.yaml stage key. The gate set is fixed by verify/SKILL.md.
# Gate A is absent BY DESIGN: it is deterministic and emits a log() line, not an
# agent(). SEAM: goalforge-pick-agent.py --test-tiers reads this tuple (importing
# this module) to assert every grader role the compiler emits is distinct from
# the implementer band (ticket-48).
GATES: tuple[tuple[str, str], ...] = (
    ("gate B", "wp-verify"),
    ("gate C", "judge"),
)

# The second opinion is NOT a gate node: its dispatch row runs on a non-native
# provider, so its `model` is that PROVIDER's id (e.g. an ollama model), which
# `agent({model: ...})` cannot dispatch natively. Like gate A it is emitted as a
# log() line naming the deterministic script that owns the leg.
SECOND_OPINION_SCRIPT = "scripts/goalforge-second-opinion.sh"

ITEM_RE = re.compile(
    r"^-\s*\[[ xX]\]\s*(?P<id>\S+)\s+(?P<text>.*?)\s*\{files:\s*(?P<files>[^}]*)\}"
    r"\s*(?P<behaviors>\[[^\]]*\])?\s*$"
)


def _load_pick_agent():
    """Import goalforge-pick-agent.py by path (its filename is not importable)."""
    spec = importlib.util.spec_from_file_location("goalforge_pick_agent", PICK_AGENT_PATH)
    if spec is None or spec.loader is None:  # pragma: no cover - install defect
        raise SystemExit(f"ERROR: cannot load {PICK_AGENT_PATH}")
    module = importlib.util.module_from_spec(spec)
    # Registered before exec: pick-agent defines dataclasses, which resolve
    # their own module out of sys.modules while the class body executes.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


pick_agent = _load_pick_agent()


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

class ChecklistItem:
    """One `- [ ] Tn <text> {files: a, b} [b1]` row."""

    def __init__(self, item_id: str, text: str, files: list[str], line: str) -> None:
        self.id = item_id
        self.text = text
        self.files = files
        self.line = line

    @property
    def file_set(self) -> frozenset[str]:
        return frozenset(self.files)


def parse_checklist(text: str) -> list[ChecklistItem]:
    """Extract the `## Checklist` items, in document order."""
    items: list[ChecklistItem] = []
    in_checklist = False
    for raw in text.splitlines():
        stripped = raw.strip()
        if stripped.startswith("## "):
            in_checklist = stripped.lower() == "## checklist"
            continue
        if not in_checklist:
            continue
        m = ITEM_RE.match(stripped)
        if m is None:
            continue
        files = [f.strip() for f in m.group("files").split(",") if f.strip()]
        items.append(ChecklistItem(m.group("id"), m.group("text"), files, stripped))
    return items


# ---------------------------------------------------------------------------
# Graph → nodes
# ---------------------------------------------------------------------------

def conflicts(a: ChecklistItem, b: ChecklistItem) -> bool:
    """Two items conflict when their `{files:}` sets intersect."""
    return bool(a.file_set & b.file_set)


def layers(items: list[ChecklistItem]) -> list[list[ChecklistItem]]:
    """Layer items so each layer is internally disjoint; overlap forces a later one."""
    assigned: list[int] = []
    for i, item in enumerate(items):
        depth = 0
        for j in range(i):
            if conflicts(items[j], item):
                depth = max(depth, assigned[j] + 1)
        assigned.append(depth)
    out: list[list[ChecklistItem]] = [[] for _ in range(max(assigned, default=-1) + 1)]
    for item, depth in zip(items, assigned):
        out[depth].append(item)
    return out


def pack(layer: list[ChecklistItem]) -> list[list[ChecklistItem]]:
    """Split one layer into ceil(n / MAX_NODE) nodes of as equal a size as possible."""
    n = len(layer)
    if n == 0:
        return []
    count = -(-n // MAX_NODE)
    base, extra = divmod(n, count)
    nodes: list[list[ChecklistItem]] = []
    start = 0
    for k in range(count):
        size = base + (1 if k < extra else 0)
        nodes.append(layer[start:start + size])
        start += size
    return nodes


def stages(items: list[ChecklistItem]) -> list[list[list[ChecklistItem]]]:
    """Stage k = layer k's nodes. Stage 0's nodes may run concurrently."""
    return [pack(layer) for layer in layers(items) if layer]


# ---------------------------------------------------------------------------
# Emission
# ---------------------------------------------------------------------------

def js(value: str) -> str:
    """A JS string literal — JSON string syntax is a strict subset."""
    return json.dumps(value)


def batch_prompt(
    node: list[ChecklistItem], wp_name: str, persona: str, expertise: list[str]
) -> str:
    lines = [
        f"You are ONE implementer batch for work package {wp_name}.",
        f"Persona: {persona}",
        f"Expertise refs: {', '.join(expertise) if expertise else '(none)'}",
        "Implement exactly these checklist items, verbatim as written:",
    ]
    lines += [f"  {item.line}" for item in node]
    lines += [
        "Touch only the paths in the {files:} sets above.",
        "Run the work package verification command before returning.",
        "Return DATA, never commit.",
    ]
    return "\n".join(lines)


def gate_prompt(label: str, wp_name: str) -> str:
    return (
        f"Run {label} for work package {wp_name} against the diff the batch "
        "nodes produced, using the work package goal object as the rubric. "
        "Return DATA, never commit."
    )


def agent_call(
    *, label: str, phase_name: str, model: str, effort: str, prompt: str, indent: str
) -> str:
    return (
        f"{indent}agent({{ label: {js(label)}, phase: {js(phase_name)}, "
        f"model: {js(model)}, effort: {js(effort)}, prompt: {js(prompt)} }})"
    )


def row_dispatch(module, dispatch: dict, role: str, frontmatter: dict,
                 touched: list[str], expertise_map: dict) -> dict:
    """Resolve one stage row through pick-agent (by_register + expertise aware).

    The expertise map is passed IN (`--expertise <yaml>`, default the package
    file): it is sibling-owned data, so an oracle running against a `--dispatch`
    fixture must be able to pin it too rather than read whatever the live map
    happens to say."""
    return module.resolve_stage(
        role, frontmatter, touched, dispatch,
        expertise_map, profile="semi-autonomous",
    )


def roster_agent_path(module, agent_name: str) -> str:
    """`agents/<file>.md` for a roster agent `name:` — the persona a batch reads."""
    for path in sorted(module.AGENTS_DIR.glob("*.md")):
        for line in path.read_text(encoding="utf-8").splitlines()[:20]:
            if line.startswith("name:") and line.split(":", 1)[1].strip() == agent_name:
                return f"agents/{path.name}"
    return agent_name


def verification_command(frontmatter: dict) -> str:
    """The WP's `goal.verification.command` — gate A's deterministic oracle."""
    goal = frontmatter.get("goal")
    verification = goal.get("verification") if isinstance(goal, dict) else None
    if isinstance(verification, dict):
        return str(verification.get("command") or "")
    return ""


def compile_script(
    frontmatter: dict, items: list[ChecklistItem], dispatch: dict, module,
    expertise_map: dict,
) -> str:
    wp_name = str(frontmatter.get("name") or "unnamed-wp")
    is_parallel = bool(frontmatter.get("parallel"))
    touched = sorted({f for item in items for f in item.files})

    batch = row_dispatch(module, dispatch, "implement", frontmatter, touched,
                         expertise_map)
    persona = roster_agent_path(module, batch["agent"])
    expertise = list(batch["expertise"])
    grouped = stages(items)
    nodes = [node for stage in grouped for node in stage]

    calls: list[str] = []
    if is_parallel:
        for stage in grouped:
            if len(stage) > 1:
                inner = ",\n".join(
                    agent_call(
                        label=f"batch-{nodes.index(node) + 1} [{len(node)} items]",
                        phase_name="batches",
                        model=batch["model"],
                        effort=batch["effort"],
                        prompt=batch_prompt(node, wp_name, persona, expertise),
                        indent="      ",
                    )
                    for node in stage
                )
                calls.append("    parallel([\n" + inner + "\n    ])")
            else:
                calls.append(
                    agent_call(
                        label=f"batch-{nodes.index(stage[0]) + 1} [{len(stage[0])} items]",
                        phase_name="batches",
                        model=batch["model"],
                        effort=batch["effort"],
                        prompt=batch_prompt(stage[0], wp_name, persona, expertise),
                        indent="    ",
                    )
                )
    else:
        for i, node in enumerate(nodes):
            calls.append(
                agent_call(
                    label=f"batch-{i + 1} [{len(node)} items]",
                    phase_name="batches",
                    model=batch["model"],
                    effort=batch["effort"],
                    prompt=batch_prompt(node, wp_name, persona, expertise),
                    indent="    ",
                )
            )

    for label, role in GATES:
        row = module.stage_row(dispatch, role)
        model, effort = row.get("model"), row.get("effort")
        if not model or not effort:
            raise ValueError(f"dispatch stage row {role!r} is missing model and/or effort")
        calls.append(
            agent_call(
                label=label,
                phase_name="gates",
                model=str(model),
                effort=str(effort),
                prompt=gate_prompt(label, wp_name),
                indent="    ",
            )
        )

    command = verification_command(frontmatter)
    gate_a = (
        "gate A is deterministic — no agent node; run: " + command
        if command
        else "gate A is deterministic — no agent node; the WP declares no "
             "goal.verification.command"
    )

    second_opinion = (
        "the second opinion is a leaf leg — no agent node; run: "
        f"{SECOND_OPINION_SCRIPT} <wp> --feature-dir <feature> "
        "--verdict <gate-C verdict> --diff <wp diff>"
    )

    description = (
        f"Compiled from the {wp_name} checklist: {len(items)} items in "
        f"{len(nodes)} batch nodes over {len(grouped)} stages, then gates B/C "
        "(gate A and the second opinion are deterministic legs)."
    )
    body = ",\n".join(calls)
    return (
        "export const meta = {\n"
        f"  name: {js(wp_name)},\n"
        f"  description: {js(description)},\n"
        "  phases: [\n"
        f"    {{ title: \"batches\", detail: {js('Checklist items, batched by {files:} disjointness.')} }},\n"
        f"    {{ title: \"gates\", detail: {js('Gate B and gate C (gate A and the second opinion are deterministic legs).')} }}\n"
        "  ]\n"
        "};\n"
        "\n"
        "// GENERATED by scripts/goalforge-workflow-compile.py — do not hand-edit.\n"
        "export default () => {\n"
        "  phase(\"batches\");\n"
        "  phase(\"gates\");\n"
        f"  log({js(description)});\n"
        f"  log({js(gate_a)});\n"
        f"  log({js(second_opinion)});\n"
        "  return pipeline(\n"
        f"{body}\n"
        "  );\n"
        "};\n"
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _build_cli() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="goalforge-workflow-compile.py",
        description="Compile a WP checklist into a Workflow-tool script.",
    )
    parser.add_argument("overview", help="path to the WP overview.md")
    parser.add_argument("--dispatch", default=None, help="dispatch.yaml (default: the package file)")
    parser.add_argument("--expertise", default=None,
                        help="expertise-map.yaml (default: the package file)")
    parser.add_argument("--out", default=None, help="output directory (default: run/workflows/)")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_cli().parse_args(argv)

    overview = Path(args.overview)
    try:
        text = overview.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"ERROR: unreadable overview: {exc}", file=sys.stderr)
        return 2

    try:
        frontmatter = pick_agent._parse_frontmatter(text)
    except yaml.YAMLError as exc:
        print(f"ERROR: malformed YAML frontmatter in {overview}: {exc}", file=sys.stderr)
        return 2
    if frontmatter is None:
        print(f"ERROR: no YAML frontmatter in {overview}", file=sys.stderr)
        return 2

    items = parse_checklist(text)
    if not items:
        print(f"ERROR: no `## Checklist` items with a {{files:}} set in {overview}",
              file=sys.stderr)
        return 2

    try:
        dispatch = pick_agent.load_dispatch(Path(args.dispatch) if args.dispatch else None)
    except OSError as exc:
        print(f"ERROR: dispatch file not found: {exc}", file=sys.stderr)
        return 2
    except ValueError as exc:
        print(f"ERROR: unreadable dispatch file: {exc}", file=sys.stderr)
        return 2

    expertise_path = Path(args.expertise) if args.expertise else None
    if expertise_path is not None and not expertise_path.is_file():
        print(f"ERROR: expertise map not found: {expertise_path}", file=sys.stderr)
        return 2
    expertise_map = pick_agent.load_expertise_map(expertise_path)

    try:
        script = compile_script(frontmatter, items, dispatch, pick_agent,
                                expertise_map)
    except (ValueError, pick_agent.EscalationRequired) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    out_dir = Path(args.out) if args.out else DEFAULT_OUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{frontmatter.get('name') or 'unnamed-wp'}.js"
    out_path.write_text(script, encoding="utf-8")

    print(f"wrote {out_path}")
    print(f'Workflow({{scriptPath: "{out_path}"}})')
    return 0


if __name__ == "__main__":
    sys.exit(main())
