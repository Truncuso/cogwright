"""sdd-pick-agent — specialist / model / route resolver for SDD execute.

Resolution order (spec §5):
  1. by_tag  match on task tags
  1'. by_task_type  match on the WP/task task_type (research, writing, …).
       `writing` is kind-dependent: resolves via by_writing_kind keyed on the
       WP's `writing_kind` tag (scientific/research/docs); untagged → fall through.
  2. by_extension match on touched file extensions
  3. discover() callable  (discovery-agent fallback)
  4. discover() returns "none"  → raise EscalationRequired

No hard specialist default. No silent model/route fallback.

Public API:
    pick_agent(task_frontmatter, touched_files, specialist_map,
               *, discover=None, ollama_health=None) -> dict

    Returns: {specialist, model, route, discovered_by}
    May include: proposed_map_entry (when discovery names an unknown specialist).

    tier_to_dispatch(tier) / resolve_dispatch(role, profile, …) -> {model, effort}
        Effort-aware dispatch instantiation for a subagent brief (states BOTH
        model and effort explicitly). resolve_role_tier() still returns the bare
        tier string for callers that only need the tier.

CLI:
    python3 sdd-pick-agent.py --task <yaml-file> [--route ollama] [--self-test]
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Callable, Optional

try:
    import yaml
except ImportError as exc:  # pragma: no cover
    raise SystemExit("PyYAML required: pip install pyyaml") from exc


# ---------------------------------------------------------------------------
# Exception
# ---------------------------------------------------------------------------

class EscalationRequired(Exception):
    """Raised when dispatch cannot be resolved without human input.

    Attributes:
        reason: Human-readable explanation.
        context: Dict with extra diagnostic info (optional).
    """

    def __init__(self, reason: str, context: dict | None = None) -> None:
        super().__init__(reason)
        self.reason = reason
        self.context = context or {}


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Effort-aware tier → (model, effort) instantiation — the SINGLE tier→model
# source of truth for the API route (OLLAMA_MODELS below is the deliberately
# leaner local route, not a mirror). Bare tier names, never pinned versions —
# the claude CLI resolves the current model for each tier (the no-pinning rule
# in CLAUDE.md). A dispatched subagent brief needs BOTH a model and an effort
# level, stated explicitly (never inherited from the agent's .md defaults).
# Rationale (tiered-dispatch-routing): opus@low beats sonnet on
# cost-to-intelligence for build work, so medium/high both route to opus. The
# low tier — comprehension legs (discovery) AND low-complexity builds — stays
# sonnet@low as a deliberate cost floor (human decision 2026-07-09; matrix row
# "Low-complexity build"). Pure-mechanical routes stay on haiku/ollama
# (by_tag mechanical → __ollama__) and never reach this map.
TIER_DISPATCH: dict[str, dict[str, str]] = {
    "low":    {"model": "sonnet", "effort": "low"},
    "medium": {"model": "opus",   "effort": "low"},
    "high":   {"model": "opus",   "effort": "high"},
}

# Model-only view of TIER_DISPATCH, derived — never a second table (a manually
# maintained copy here once drifted from the documented policy). Used by
# pick_agent / role_model for the api route.
COMPLEXITY_MODEL: dict[str, str] = {t: d["model"] for t, d in TIER_DISPATCH.items()}

# Local-route models run one model-class leaner than TIER_DISPATCH by design
# (the ollama route exists as the cost/offline option; it is NOT a mirror of
# the API mapping — medium here is sonnet-class, not opus-class).
OLLAMA_MODELS: dict[str, str] = {
    "low": "nemotron-3-nano",
    "medium": "deepseek-v4-pro",
    "high": "deepseek-v3.2",
}

OLLAMA_SENTINEL = "__ollama__"
WRITING_KIND_SENTINEL = "__by_writing_kind__"  # task_type: writing → resolve via
                                               # by_writing_kind keyed on the WP's
                                               # `writing_kind` tag (kind-dependent).

SPECIALIST_MAP_PATH = Path(__file__).parent.parent / "references" / "specialist-map.yaml"


# ---------------------------------------------------------------------------
# Canonical role → model-tier map (single source of truth)
# ---------------------------------------------------------------------------
# Every SDD dispatcher (sdd-execute, sdd-verify, sdd-harden, sdd-arbiter)
# resolves the model tier for a dispatched ROLE here — none of them restates the
# table. A "tier" is one of low|medium|high and maps to a concrete model via
# COMPLEXITY_MODEL (api) / OLLAMA_MODELS (ollama).
#
# Two autonomy profiles:
#   - "autonomous-minimal": cost-lean — the cheapest tier that still does the
#     job, escalating only on blast radius. Default for fully-autonomous runs.
#   - "semi-autonomous": a human reviews the output, so spend for quality at the
#     gates feeding that review (the WP verify pass, the panel, integration).
#
# Blast radius (auth / schema / migration / exported API / 3+ files) is detected
# deterministically and forces the "high" tier regardless of role/profile — a
# sensitive change is never silently downgraded.

ROLE_TIER_PROFILES = ("autonomous-minimal", "semi-autonomous")

# tier ∈ {low, medium, high}; the sentinel "by_complexity" defers to the task's
# own `complexity` (preserves per-task tiering for the `implement` role).
ROLE_TIER: dict[str, dict[str, str]] = {
    #  role                  autonomous-minimal   semi-autonomous
    "implement":          {"autonomous-minimal": "by_complexity", "semi-autonomous": "by_complexity"},
    "discovery":          {"autonomous-minimal": "low",           "semi-autonomous": "low"},
    "feature-audit":      {"autonomous-minimal": "medium",        "semi-autonomous": "medium"},  # Tier-1 cold whole-feature review
    "wp-harden-delta":    {"autonomous-minimal": "low",           "semi-autonomous": "medium"},  # Tier-2 WP-scoped delta
    "wp-verify":          {"autonomous-minimal": "medium",        "semi-autonomous": "high"},    # the single WP semantic gate
    "simplify":           {"autonomous-minimal": "medium",        "semi-autonomous": "medium"},
    "judge":              {"autonomous-minimal": "medium",        "semi-autonomous": "medium"},
    "panel":              {"autonomous-minimal": "high",          "semi-autonomous": "high"},    # convened only for complex+irreversible
    "arbiter-grid":       {"autonomous-minimal": "low",           "semi-autonomous": "medium"},  # mechanical N×axis normalization
    "integration-review": {"autonomous-minimal": "medium",        "semi-autonomous": "high"},    # last-WP cross-WP review
}

BLAST_RADIUS_TIER = "high"
# Deterministic blast-radius signals, matched as whole word segments on touched
# paths (letter-boundaried, optional plural) — "auth" hits src/auth/login.py but
# not skill-authoring.md; "schema" hits db/schemas/ but not schematic.
BLAST_RADIUS_SIGNALS = (
    "auth", "oauth", "schema", "migration", "exported", "public-api",
    "public_api", "rbac", "permission", "secret", "credential",
)
# Doc/prose files are exempt from signal matching — a filename like
# idea-schema.md is not a sensitive change. The file-count threshold still
# counts them.
DOC_EXTENSIONS = (".md", ".markdown", ".txt", ".rst")


def blast_radius(
    touched_files: list[str],
    *,
    signals: tuple[str, ...] = BLAST_RADIUS_SIGNALS,
    file_threshold: int = 3,
) -> bool:
    """Deterministic blast-radius detector: True ⇒ force the high tier.

    Hits when the change spans ``file_threshold``+ files OR a touched
    non-doc path matches a sensitive signal (auth/schema/migration/exported
    API/secrets) as a whole word segment. Pure and offline, so identical
    inputs always yield the same tier — no model in the loop."""
    if len(touched_files) >= file_threshold:
        return True
    patterns = [
        re.compile(rf"(?<![a-z]){re.escape(sig)}s?(?![a-z])") for sig in signals
    ]
    for f in touched_files:
        low = f.lower()
        if low.endswith(DOC_EXTENSIONS):
            continue
        if any(p.search(low) for p in patterns):
            return True
    return False


def resolve_role_tier(
    role: str,
    profile: str = "semi-autonomous",
    *,
    complexity: str | None = None,
    blast_radius_hit: bool = False,
) -> str:
    """Resolve the model tier (low|medium|high) for a dispatched role.

    The single source of truth every SDD dispatcher calls. Blast radius forces
    ``high``. The ``implement`` role stays complexity-driven (preserving per-task
    tiering); every other role reads ``ROLE_TIER``. An unknown role or profile
    escalates rather than silently defaulting (mirrors the no-silent-fallback
    contract of this module)."""
    if profile not in ROLE_TIER_PROFILES:
        raise EscalationRequired(
            f"Unknown autonomy profile {profile!r}. Expected one of: "
            + ", ".join(ROLE_TIER_PROFILES),
            {"profile": profile},
        )
    if role not in ROLE_TIER:
        raise EscalationRequired(
            f"No tier mapping for role {role!r}. Add it to ROLE_TIER "
            "(the canonical role→tier map) — no silent default.",
            {"known_roles": sorted(ROLE_TIER)},
        )
    if blast_radius_hit:
        return BLAST_RADIUS_TIER
    tier = ROLE_TIER[role][profile]
    if tier == "by_complexity":
        if complexity is None:
            raise EscalationRequired(
                f"Role {role!r} is complexity-driven but no complexity was given.",
                {"role": role},
            )
        if complexity not in COMPLEXITY_MODEL:
            raise ValueError(f"Unknown complexity {complexity!r}.")
        return complexity
    return tier


def role_model(
    role: str,
    profile: str = "semi-autonomous",
    *,
    complexity: str | None = None,
    blast_radius_hit: bool = False,
    route: str = "api",
) -> str:
    """Resolve the concrete model id for a role via the canonical tier map."""
    tier = resolve_role_tier(
        role, profile, complexity=complexity, blast_radius_hit=blast_radius_hit
    )
    table = OLLAMA_MODELS if route == "ollama" else COMPLEXITY_MODEL
    return table[tier]


def tier_to_dispatch(tier: str) -> dict[str, str]:
    """Instantiate a tier (low|medium|high) as an explicit ``{model, effort}``.

    The tier→model source of truth (``COMPLEXITY_MODEL`` is its derived
    model-only view): every SDD subagent brief states model AND effort, resolved
    here rather than left to the agent's ``.md`` frontmatter defaults. Pure and offline. An unknown tier raises
    ``EscalationRequired`` (no silent default), mirroring the no-silent-fallback
    contract of this module."""
    if tier not in TIER_DISPATCH:
        raise EscalationRequired(
            f"No dispatch mapping for tier {tier!r}. Expected one of: "
            + ", ".join(TIER_DISPATCH),
            {"tier": tier},
        )
    return dict(TIER_DISPATCH[tier])


def resolve_dispatch(
    role: str,
    profile: str = "semi-autonomous",
    *,
    complexity: str | None = None,
    blast_radius_hit: bool = False,
) -> dict[str, str]:
    """Resolve a role to an explicit ``{model, effort}`` dispatch.

    Composes the canonical role→tier map (``resolve_role_tier``) with
    ``tier_to_dispatch`` — the one call an SDD dispatcher makes to state both
    knobs on a brief. Blast radius forces the high tier (→ opus@high) exactly as
    ``resolve_role_tier`` decides it; unknown role/profile/tier escalates."""
    tier = resolve_role_tier(
        role, profile, complexity=complexity, blast_radius_hit=blast_radius_hit
    )
    return tier_to_dispatch(tier)


# ---------------------------------------------------------------------------
# Core resolver
# ---------------------------------------------------------------------------

def pick_agent(
    task_frontmatter: dict,
    touched_files: list[str],
    specialist_map: dict,
    *,
    discover: Optional[Callable[[dict, list[str], list[str]], dict]] = None,
    ollama_health: Optional[Callable[[], bool]] = None,
) -> dict:
    """Resolve specialist, model, and route for a single SDD task.

    Args:
        task_frontmatter: Parsed YAML frontmatter from the task file.
        touched_files: List of file paths the task will touch.
        specialist_map: Parsed specialist-map.yaml dict (by_tag, by_extension, …).
        discover: Callable(frontmatter, touched_files, known_specialists) → dict
            with keys ``specialist`` (str or "none") and ``complexity``
            (low|medium|high|None). Invoked only when tag+extension lookup fails.
            Defaults to None, meaning no discovery fallback — EscalationRequired
            is raised immediately when map lookup fails and discover is None.
        ollama_health: Callable() → bool. Returns True if the local Ollama
            endpoint is healthy. Required (not optional) when route is ollama;
            if None and route is ollama, EscalationRequired is raised.

    Returns:
        dict with keys:
            specialist (str): agent name
            model (str): model id
            route (str): "api" or "ollama"
            discovered_by (str): "map" or "discovery-agent"
        Optionally also:
            proposed_map_entry (dict): when discover() named an unknown specialist

    Raises:
        EscalationRequired: when no specialist can be resolved, or ollama is down.
        ValueError: when specialist_map is malformed or complexity is unrecognised.
    """
    by_tag: dict[str, str] = specialist_map.get("by_tag", {})
    by_task_type: dict[str, str] = specialist_map.get("by_task_type", {})
    by_writing_kind: dict[str, str] = specialist_map.get("by_writing_kind", {})
    by_extension: dict[str, str] = specialist_map.get("by_extension", {})

    task_tags: list[str] = task_frontmatter.get("tags", []) or []
    task_type: str | None = task_frontmatter.get("task_type")
    writing_kind: str | None = task_frontmatter.get("writing_kind")
    complexity: str | None = task_frontmatter.get("complexity")
    route_hint: str = task_frontmatter.get("route", "api")

    # ------------------------------------------------------------------
    # Step 1 — specialist resolution
    # ------------------------------------------------------------------
    specialist: str | None = None
    discovered_by: str = "map"
    proposed_map_entry: dict | None = None
    extensions = {Path(f).suffix.lower() for f in touched_files if Path(f).suffix}

    # 1a. by_tag
    for tag in task_tags:
        if tag in by_tag:
            specialist = by_tag[tag]
            break

    # 1a'. by_task_type — non-code task_type routes (research, writing, …).
    # After by_tag, before by_extension: a code WP with no by_task_type entry
    # falls through to by_extension exactly as before (code path unchanged).
    # `isinstance(task_type, str)` guards a malformed (list/dict) task_type —
    # using it as a dict key directly would raise TypeError: unhashable type;
    # instead degrade gracefully to extension/discovery → clean escalation.
    if specialist is None and isinstance(task_type, str) and task_type in by_task_type:
        specialist = by_task_type[task_type]
        # `writing` is kind-dependent: the by_task_type value is a sentinel that
        # triggers a second lookup in by_writing_kind, keyed on the WP's
        # `writing_kind` tag. Untagged / unknown kind → specialist stays None so
        # resolution falls through to discovery/escalation (ask which kind).
        if specialist == WRITING_KIND_SENTINEL:
            specialist = (
                by_writing_kind.get(writing_kind)
                if isinstance(writing_kind, str)
                else None
            )
            # A writing WP whose kind doesn't resolve must NOT silently fall
            # through to by_extension (a writing WP touching a .py file would
            # mis-route to a code agent). Escalate, naming the valid kinds, so a
            # human / dispatching agent sets `writing_kind`.
            if specialist is None:
                raise EscalationRequired(
                    "task_type: writing needs a `writing_kind` to route — "
                    f"got {writing_kind!r}. Set one of: "
                    f"{', '.join(sorted(by_writing_kind))}.",
                    {"task": task_frontmatter.get("name"),
                     "writing_kind": writing_kind,
                     "valid_kinds": sorted(by_writing_kind)},
                )

    # 1b. by_extension
    if specialist is None:
        for ext in extensions:
            if ext in by_extension:
                specialist = by_extension[ext]
                break

    # 1c. discovery agent
    if specialist is None:
        if discover is None:
            raise EscalationRequired(
                "No specialist matched by tag or extension and no discovery callable "
                "was provided. Assign a specialist manually or wire the discovery agent.",
                {"tags": task_tags, "extensions": list(extensions)},
            )
        known_specialists = _known_specialists(specialist_map)
        result = discover(task_frontmatter, touched_files, known_specialists)
        if not isinstance(result, dict):
            raise EscalationRequired(
                "Discovery callable returned a non-dict result "
                f"({type(result).__name__}); cannot resolve a specialist. "
                "Human assignment required (AskUserQuestion).",
                {"task": task_frontmatter.get("name"), "touched_files": touched_files},
            )
        discovered_name = result.get("specialist") or "none"
        discovered_complexity: str | None = result.get("complexity")

        if discovered_name == "none":
            raise EscalationRequired(
                "Discovery agent returned 'none': no suitable specialist found. "
                "Human assignment required (AskUserQuestion).",
                {"task": task_frontmatter.get("name"), "touched_files": touched_files},
            )

        # A sentinel is a routing directive, never a dispatchable specialist —
        # discovery must not echo one back (it would leak as the specialist and
        # be proposed for the map). Treat it like "none": escalate.
        if discovered_name in (OLLAMA_SENTINEL, WRITING_KIND_SENTINEL):
            raise EscalationRequired(
                f"Discovery agent returned the sentinel '{discovered_name}', "
                "which is a routing directive, not a specialist. "
                "Human assignment required (AskUserQuestion).",
                {"task": task_frontmatter.get("name"), "touched_files": touched_files},
            )

        # Use discovery's complexity estimate when frontmatter omits it
        if complexity is None and discovered_complexity:
            complexity = discovered_complexity

        if discovered_name not in known_specialists:
            proposed_map_entry = _build_proposed_entry(discovered_name, task_tags, touched_files)

        specialist = discovered_name
        discovered_by = "discovery-agent"

    # ------------------------------------------------------------------
    # Step 2 — route resolution
    # ------------------------------------------------------------------
    # __ollama__ sentinel (by_tag entry) forces ollama route
    ollama_via_sentinel = specialist == OLLAMA_SENTINEL
    route: str

    if ollama_via_sentinel:
        # The tag mapped to __ollama__: need a real specialist, but we
        # don't have one from the map — this is a caller-config error.
        raise EscalationRequired(
            f"Tag mapped to '{OLLAMA_SENTINEL}' but no specialist name provided. "
            "Set an explicit specialist in the task frontmatter.",
            {"by_tag": by_tag},
        )

    if route_hint == "ollama":
        route = "ollama"
    else:
        route = "api"

    # ------------------------------------------------------------------
    # Step 3 — model tier
    # ------------------------------------------------------------------
    if complexity is None:
        raise EscalationRequired(
            "Cannot determine model tier: 'complexity' absent from frontmatter and "
            "discovery agent did not return an estimate.",
            {"task": task_frontmatter.get("name")},
        )
    if complexity not in COMPLEXITY_MODEL:
        raise ValueError(
            f"Unknown complexity '{complexity}'. Expected one of: "
            + ", ".join(COMPLEXITY_MODEL)
        )

    if route == "ollama":
        model = OLLAMA_MODELS[complexity]
        if ollama_health is None or not ollama_health():
            raise EscalationRequired(
                "Ollama route requested but health check failed (endpoint down or "
                "ollama_health callable not provided). No silent API fallback.",
                {"route": "ollama", "model": model},
            )
    else:
        model = COMPLEXITY_MODEL[complexity]

    # ------------------------------------------------------------------
    # Result
    # ------------------------------------------------------------------
    result: dict = {
        "specialist": specialist,
        "model": model,
        "route": route,
        "discovered_by": discovered_by,
    }
    if proposed_map_entry is not None:
        result["proposed_map_entry"] = proposed_map_entry
    return result


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _known_specialists(specialist_map: dict) -> list[str]:
    """Return all concrete specialist names (excludes sentinels)."""
    sentinels = {OLLAMA_SENTINEL, WRITING_KIND_SENTINEL}
    specialists: set[str] = set()
    for section in ("by_tag", "by_task_type", "by_writing_kind", "by_extension"):
        specialists.update(
            v for v in specialist_map.get(section, {}).values()
            if v not in sentinels
        )
    return sorted(specialists)


def _build_proposed_entry(specialist: str, tags: list[str], touched_files: list[str]) -> dict:
    """Build a proposed specialist-map.yaml addition for human review."""
    extensions = sorted({Path(f).suffix.lower() for f in touched_files if Path(f).suffix})
    return {
        "specialist": specialist,
        "suggested_extensions": extensions,
        "suggested_tags": tags,
        "note": "Proposed by discovery-agent. Human review required before merging.",
    }


def load_specialist_map(path: Path | None = None) -> dict:
    """Load specialist-map.yaml from the default location or given path."""
    target = path or SPECIALIST_MAP_PATH
    with open(target, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _cli_discover_stub(
    frontmatter: dict, touched: list[str], known: list[str]
) -> dict:
    """Minimal discovery stub for --self-test mode (no network)."""
    # Simulate returning the first known specialist with low complexity
    if known:
        return {"specialist": known[0], "complexity": "low"}
    return {"specialist": "none", "complexity": None}


def _cli_ollama_stub() -> bool:
    """Minimal ollama-health stub for --self-test mode (no network)."""
    return True


def _test_tiers() -> int:
    """Deterministic tier-selection eval for the canonical role→tier map.

    Asserts the invariants the dispatchers rely on. Returns 0 on success,
    1 on the first failed assertion (no network, no model)."""
    failures: list[str] = []

    def expect(label: str, got, want) -> None:
        if got != want:
            failures.append(f"{label}: got {got!r}, want {want!r}")

    # WP verify is the single semantic gate: cheap when autonomous, opus-tier when
    # a human will review the result.
    expect("wp-verify/auto", resolve_role_tier("wp-verify", "autonomous-minimal"), "medium")
    expect("wp-verify/semi", resolve_role_tier("wp-verify", "semi-autonomous"), "high")
    # Tier-1 feature audit is a medium-tier (→ opus@low) cold review in both profiles.
    expect("feature-audit", resolve_role_tier("feature-audit", "autonomous-minimal"), "medium")
    # Panel is opus-tier (convened only for complex+irreversible).
    expect("panel", resolve_role_tier("panel", "semi-autonomous"), "high")
    # implement stays complexity-driven.
    expect("implement/low", resolve_role_tier("implement", "semi-autonomous", complexity="low"), "low")
    expect("implement/high", resolve_role_tier("implement", "autonomous-minimal", complexity="high"), "high")
    # Blast radius forces high regardless of role/profile/complexity.
    expect(
        "blast-radius override",
        resolve_role_tier("implement", "autonomous-minimal", complexity="low", blast_radius_hit=True),
        "high",
    )
    # Deterministic blast-radius detection.
    expect("br/auth-path", blast_radius(["src/auth/login.py"]), True)
    expect("br/schema-path", blast_radius(["db/schema.sql"]), True)
    expect("br/schemas-plural", blast_radius(["db/schemas/users.sql"]), True)
    expect("br/oauth-path", blast_radius(["src/oauth/callback.py"]), True)
    expect("br/3-files", blast_radius(["a.py", "b.py", "c.py"]), True)
    expect("br/single-safe", blast_radius(["src/util/format.py"]), False)
    # Doc files never trip signals (idea: blast-radius-doc-file-false-positive)…
    expect("br/doc-schema-name", blast_radius(["skills/idea/references/idea-schema.md"]), False)
    expect("br/doc-auth-name", blast_radius(["references/skill-authoring-best-practices.md"]), False)
    # …but still count toward the file threshold.
    expect("br/3-docs", blast_radius(["a.md", "b.md", "c.md"]), True)
    # Word-segment match: "auth" is not a substring hit inside "authoring".
    expect("br/authoring-code", blast_radius(["src/authoring/tool.py"]), False)
    # role_model resolves through the tier map.
    expect("role_model/wp-verify/semi", role_model("wp-verify", "semi-autonomous"), COMPLEXITY_MODEL["high"])

    # Effort-aware dispatch instantiation (tiered-dispatch-routing):
    # low → sonnet@low, medium → opus@low, high → opus@high.
    expect("dispatch/low", tier_to_dispatch("low"), {"model": "sonnet", "effort": "low"})
    expect("dispatch/medium", tier_to_dispatch("medium"), {"model": "opus", "effort": "low"})
    expect("dispatch/high", tier_to_dispatch("high"), {"model": "opus", "effort": "high"})
    # resolve_dispatch composes role→tier with tier_to_dispatch.
    expect(
        "resolve_dispatch/wp-verify/semi",
        resolve_dispatch("wp-verify", "semi-autonomous"),
        {"model": "opus", "effort": "high"},
    )
    # Blast radius forces high → opus@high through the dispatch path too.
    expect(
        "resolve_dispatch/blast",
        resolve_dispatch("implement", "autonomous-minimal", complexity="low", blast_radius_hit=True),
        {"model": "opus", "effort": "high"},
    )
    # Pins the doc-level claim in sdd-harden/references/pre-harden-review.md.
    expect(
        "resolve_dispatch/wp-harden-delta/semi",
        resolve_dispatch("wp-harden-delta", "semi-autonomous"),
        {"model": "opus", "effort": "low"},
    )
    # COMPLEXITY_MODEL is a derived view of TIER_DISPATCH — never a second table.
    expect(
        "complexity-model-derived",
        COMPLEXITY_MODEL,
        {t: d["model"] for t, d in TIER_DISPATCH.items()},
    )
    # Unknown tier escalates, never silently defaults.
    try:
        tier_to_dispatch("mega")
        failures.append("unknown tier did not escalate")
    except EscalationRequired:
        pass

    # Unknown role / profile must escalate, never silently default.
    for bad_role in ("nonexistent-role",):
        try:
            resolve_role_tier(bad_role, "semi-autonomous")
            failures.append(f"unknown role {bad_role!r} did not escalate")
        except EscalationRequired:
            pass
    try:
        resolve_role_tier("wp-verify", "no-such-profile")
        failures.append("unknown profile did not escalate")
    except EscalationRequired:
        pass

    if failures:
        for f in failures:
            print(f"  FAIL: {f}", file=sys.stderr)
        print(f"=== tier eval: {len(failures)} failure(s) ===", file=sys.stderr)
        return 1
    print("=== tier eval: all role→tier invariants pass ===")
    return 0


def _build_cli() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="SDD pick-agent: resolve specialist/model/route for a task."
    )
    p.add_argument("--task", metavar="FILE", help="Path to task YAML/MD file")
    p.add_argument(
        "--test-tiers",
        action="store_true",
        help="Run the deterministic role→tier-map eval and exit (no network).",
    )
    p.add_argument(
        "--route",
        choices=["api", "ollama"],
        default=None,
        help="Override route (ollama invokes health check stub in --self-test)",
    )
    p.add_argument(
        "--self-test",
        action="store_true",
        help="Run with no-network stubs; verify basic paths work",
    )
    p.add_argument(
        "--map",
        metavar="FILE",
        default=None,
        help="Path to specialist-map.yaml (default: references/specialist-map.yaml)",
    )
    return p


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. Returns exit code."""
    args = _build_cli().parse_args(argv)

    if args.test_tiers:
        return _test_tiers()

    if not args.task:
        print("ERROR: --task FILE is required", file=sys.stderr)
        return 2

    task_path = Path(args.task)
    if not task_path.exists():
        print(f"ERROR: task file not found: {task_path}", file=sys.stderr)
        return 2

    # Parse task file (YAML frontmatter between --- delimiters or plain YAML)
    raw = task_path.read_text(encoding="utf-8")
    frontmatter = _parse_frontmatter(raw)
    if frontmatter is None:
        print(f"ERROR: no YAML frontmatter in {task_path}", file=sys.stderr)
        return 2

    # Route override
    if args.route:
        frontmatter["route"] = args.route

    # Load specialist map
    map_path = Path(args.map) if args.map else None
    try:
        specialist_map = load_specialist_map(map_path)
    except FileNotFoundError as exc:
        print(f"ERROR: specialist map not found: {exc}", file=sys.stderr)
        return 2

    # In --self-test mode wire no-network stubs
    discover_fn = _cli_discover_stub if args.self_test else None
    health_fn = _cli_ollama_stub if args.self_test else None

    touched: list[str] = frontmatter.get("_touched_files", []) or []

    try:
        result = pick_agent(
            frontmatter,
            touched,
            specialist_map,
            discover=discover_fn,
            ollama_health=health_fn,
        )
    except EscalationRequired as exc:
        print(f"ESCALATION REQUIRED: {exc.reason}", file=sys.stderr)
        if exc.context:
            print(f"  context: {exc.context}", file=sys.stderr)
        return 1

    print(yaml.dump(result, sort_keys=True, default_flow_style=False), end="")
    return 0


def _parse_frontmatter(text: str) -> dict | None:
    """Extract YAML frontmatter from text (--- delimited) or parse whole text."""
    lines = text.splitlines()
    if lines and lines[0].strip() == "---":
        end = next((i for i, l in enumerate(lines[1:], 1) if l.strip() == "---"), None)
        if end is not None:
            block = "\n".join(lines[1:end])
            return yaml.safe_load(block) or {}
    # Fallback: try parsing whole text as YAML
    try:
        data = yaml.safe_load(text)
        return data if isinstance(data, dict) else None
    except yaml.YAMLError:
        return None


if __name__ == "__main__":
    sys.exit(main())
