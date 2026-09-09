"""goalforge-pick-agent — specialist / model / route resolver for goalforge execute.

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

    Returns: {specialist, route, discovered_by}
    May include: proposed_map_entry (when discovery names an unknown specialist).
    Model/effort are resolved separately via resolve_dispatch() — wp-01/T17
    removed the `complexity` input entirely; the `implement` role's tier comes
    from the WP's own `register`/`severity` C2 fields instead.

    tier_to_dispatch(tier) / resolve_dispatch(role, profile, …) -> {model, effort}
        Effort-aware dispatch instantiation for a subagent brief (states BOTH
        model and effort explicitly). resolve_role_tier() still returns the bare
        tier string for callers that only need the tier.

    dispatch_launched_event(pick_result, dispatch_result, *, wp=None, task=None)
        Builds a `dispatch.launched` trace-event payload (C6/T20; schema:
        references/trace-events.md) from a pick_agent()+resolve_dispatch() pair.
        Pure — this module never writes to a trace itself (no --feature-dir):
        the CALLER pipes the printed JSON through goalforge-trace-emit.

Role key (wp-01/T17): the canonical role key is ``"implement"`` (matches
``ROLE_TIER``). ``"implement-code"`` — the pre-wp-01 skill name still used by
some callers being migrated — is accepted as an ALIAS: ``resolve_role_tier()``
normalizes it to ``"implement"`` and warns once to stderr. No other alias
exists; an unrecognized role still escalates (no silent default).

CLI:
    python3 goalforge-pick-agent.py --task <wp>/overview.md --role implement
        Resolves the dispatch (specialist + model + effort) for a WP overview.md
        and prints ONE JSON object to stdout — the canonical execute/SKILL.md §3
        invocation. Tier comes from `register`/`severity` (C2), never
        `complexity` (removed, wp-01/T17). Missing `register` → exit 2.
    python3 goalforge-pick-agent.py --task <yaml-file> [--route ollama] [--self-test]
    python3 goalforge-pick-agent.py --task <yaml-file> --emit-dispatch [--wp <id>]
        Resolves specialist + model/effort for the task and prints ONE
        `dispatch.launched` event JSON line to stdout (see
        dispatch_launched_event() above) — never writes to a trace itself.
"""
from __future__ import annotations

import argparse
import json
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
    # wp-01/T17: the `implement` role's "production, not escalated" band —
    # sonnet@medium, distinct from the shared `medium` (opus@low) band other
    # roles read. See resolve_role_tier()'s "by_register" branch.
    "sonnet-medium": {"model": "sonnet", "effort": "medium"},
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
    "sonnet-medium": "deepseek-v4-pro",  # same local class as "medium"
}

OLLAMA_SENTINEL = "__ollama__"
WRITING_KIND_SENTINEL = "__by_writing_kind__"  # task_type: writing → resolve via
                                               # by_writing_kind keyed on the WP's
                                               # `writing_kind` tag (kind-dependent).

SPECIALIST_MAP_PATH = Path(__file__).parent.parent / "references" / "specialist-map.yaml"
TIER_MAP_PATH = Path(__file__).parent.parent / "references" / "tier-map.md"


# ---------------------------------------------------------------------------
# Canonical role → model-tier map (single source of truth)
# ---------------------------------------------------------------------------
# Every goalforge dispatcher (goalforge-execute, goalforge-verify, goalforge-harden)
# resolves the model tier for a dispatched ROLE here — none of them restates the
# table. A "tier" is one of low|medium|high and maps to a concrete model via
# COMPLEXITY_MODEL (api) / OLLAMA_MODELS (ollama). (wp-01/T1 deleted the
# standalone `arbiter/` skill and its `goalforge-arbiter` dispatcher name, and
# wp-01/T17 dropped the `arbiter-grid` role below with it — no dispatcher
# resolves through it any more.)
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

# tier ∈ {low, medium, high}; the sentinel "by_register" defers to the WP's own
# C2 `register`/`severity` fields (preserves per-WP tiering for the `implement`
# role — wp-01/T17 dropped the pre-wp-01 `complexity`-keyed sentinel).
ROLE_TIER: dict[str, dict[str, str]] = {
    #  role                  autonomous-minimal   semi-autonomous
    "implement":          {"autonomous-minimal": "by_register",   "semi-autonomous": "by_register"},
    "discovery":          {"autonomous-minimal": "low",           "semi-autonomous": "low"},
    "feature-audit":      {"autonomous-minimal": "medium",        "semi-autonomous": "medium"},  # Tier-1 cold whole-feature review
    "wp-harden-delta":    {"autonomous-minimal": "low",           "semi-autonomous": "medium"},  # Tier-2 WP-scoped delta
    "wp-verify":          {"autonomous-minimal": "medium",        "semi-autonomous": "high"},    # the single WP semantic gate
    "simplify":           {"autonomous-minimal": "medium",        "semi-autonomous": "medium"},
    "judge":              {"autonomous-minimal": "medium",        "semi-autonomous": "medium"},
    "panel":              {"autonomous-minimal": "high",          "semi-autonomous": "high"},    # convened only for complex+irreversible
    "integration-review": {"autonomous-minimal": "medium",        "semi-autonomous": "high"},    # last-WP cross-WP review
}

# wp-01/T17: the canonical role key is "implement" (matches ROLE_TIER above).
# "implement-code" is the pre-wp-01 skill/dispatcher name some callers being
# migrated this WP still pass — accepted as a ONE-WAY alias so a caller in
# transition never hard-fails; the warning nudges it to migrate rather than
# hiding the mismatch permanently. No other alias exists.
ROLE_ALIASES: dict[str, str] = {
    "implement-code": "implement",
}


def _resolve_role_alias(role: str) -> str:
    """Normalize a role key through ROLE_ALIASES, warning once on a hit.

    Pure except for the stderr warning (no state, no I/O side effect beyond
    the warning) — every call with an aliased role warns; callers that already
    pass the canonical key never see output."""
    canonical = ROLE_ALIASES.get(role)
    if canonical is not None:
        print(
            f"goalforge-pick-agent: WARN role {role!r} is a deprecated alias "
            f"for {canonical!r} — pass {canonical!r} directly.",
            file=sys.stderr,
        )
        return canonical
    return role


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
    register: str | None = None,
    severity: str | None = None,
    blast_radius_hit: bool = False,
) -> str:
    """Resolve the model tier (low|medium|sonnet-medium|high) for a dispatched role.

    The single source of truth every SDD dispatcher calls. Blast radius forces
    ``high`` for every role EXCEPT ``implement``, which reads the WP's own C2
    ``register``/``severity`` fields instead (wp-01/T17 dropped the
    per-task ``complexity`` sentinel entirely): ``register: spike`` → ``low``;
    ``register: production`` → ``sonnet-medium``, escalating to ``medium``
    (opus@low) when ``severity: HIGH`` or blast radius fires (matches the
    Dispatch Routing Matrix's "build at complexity high or blast radius →
    opus/low", never opus@high, for this role). ``register: spike`` returns
    ``low`` UNCONDITIONALLY, ahead of the blast-radius/severity check — a
    spike register deliberately overrides blast radius for this role: the
    register is the explicit statement that this WP is exploratory, and that
    verdict outranks a mechanical file-count/path heuristic. Every other role reads
    ``ROLE_TIER`` directly. An unknown role or profile escalates rather than
    silently defaulting (mirrors the no-silent-fallback contract of this
    module). ``role`` is alias-normalized first (T17: ``"implement-code"`` →
    ``"implement"``, warns once)."""
    role = _resolve_role_alias(role)
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
    tier = ROLE_TIER[role][profile]
    if tier == "by_register":
        if register is None:
            raise EscalationRequired(
                f"Role {role!r} is register-driven but no register was given.",
                {"role": role},
            )
        if register not in ("spike", "production"):
            raise ValueError(
                f"Unknown register {register!r}. Expected 'spike' or 'production'."
            )
        if register == "spike":
            return "low"
        if blast_radius_hit or severity == "HIGH":
            return "medium"
        return "sonnet-medium"
    if blast_radius_hit:
        return BLAST_RADIUS_TIER
    return tier


def role_model(
    role: str,
    profile: str = "semi-autonomous",
    *,
    register: str | None = None,
    severity: str | None = None,
    blast_radius_hit: bool = False,
    route: str = "api",
) -> str:
    """Resolve the concrete model id for a role via the canonical tier map."""
    tier = resolve_role_tier(
        role, profile, register=register, severity=severity,
        blast_radius_hit=blast_radius_hit,
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
    register: str | None = None,
    severity: str | None = None,
    blast_radius_hit: bool = False,
) -> dict[str, str]:
    """Resolve a role to an explicit ``{model, effort}`` dispatch.

    Composes the canonical role→tier map (``resolve_role_tier``) with
    ``tier_to_dispatch`` — the one call an SDD dispatcher makes to state both
    knobs on a brief. Blast radius forces the high tier (→ opus@high) exactly as
    ``resolve_role_tier`` decides it, EXCEPT for ``implement`` (register/severity
    driven, caps at opus@low); unknown role/profile/tier escalates."""
    tier = resolve_role_tier(
        role, profile, register=register, severity=severity,
        blast_radius_hit=blast_radius_hit,
    )
    return tier_to_dispatch(tier)


# ---------------------------------------------------------------------------
# dispatch.launched event (C6/T20) — pure payload builder, no trace I/O here
# ---------------------------------------------------------------------------
# This module resolves WHO/WHAT to dispatch; it never has a --feature-dir and
# never writes to a trace (matches its existing pure/offline contract — see
# blast_radius()/tier_to_dispatch() above). The CALLER pipes this payload
# through goalforge-trace-emit --feature-dir <dir>.

def dispatch_launched_event(
    pick_result: dict,
    dispatch_result: dict,
    *,
    wp: str | None = None,
    task: str | None = None,
) -> dict:
    """Build a `dispatch.launched` trace-event payload (schema:
    references/trace-events.md) from a pick_agent()/resolve_dispatch() pair.

    Only non-empty fields are included — the schema marks every field on this
    event type optional, so an unresolved wp/task/provider is omitted rather
    than sent as an empty string."""
    event: dict = {"type": "dispatch.launched"}
    if wp:
        event["wp"] = wp
    if task:
        event["task"] = task
    agent = pick_result.get("specialist")
    if agent:
        event["agent"] = agent
    model = dispatch_result.get("model")
    if model:
        event["model"] = model
    effort = dispatch_result.get("effort")
    if effort:
        event["effort"] = effort
    provider = pick_result.get("route")
    if provider:
        event["provider"] = provider
    return event


# ---------------------------------------------------------------------------
# tier-map.md projection (generated view of ROLE_TIER — no runtime md parsing)
# ---------------------------------------------------------------------------
# tier-map.md is a GENERATED, human-readable projection of ROLE_TIER — the dict
# stays the single authoritative source. render_tier_map() emits it; the
# --test-tiers eval drift-checks the on-disk file against this render (the
# generation-drift gate). Nothing in the resolution path ever PARSES the md.

_TIER_MAP_HEADER = """<!-- GENERATED FILE — do not hand-edit.
     Human-readable projection of the authoritative ROLE_TIER dict in
     scripts/goalforge-pick-agent.py. Regenerate from the dict; the
     `goalforge-pick-agent.py --test-tiers` eval drift-checks this projection
     against ROLE_TIER (no runtime markdown parsing anywhere). -->

# Dispatch Tier Map (role → tier × effort)

Projection of `ROLE_TIER` (scripts/goalforge-pick-agent.py) — the single
authoritative source. Tiers are bare (`haiku`/`sonnet`/`opus`/`fable`); effort is
bare (`low`/`medium`/`high`/`xhigh`/`max`). No pinned vendor model IDs.

- **tier** — the `low`/`medium`/`high` band from `ROLE_TIER[role][profile]`.
- **model** — the concrete model class via `COMPLEXITY_MODEL`
  (`low → sonnet`, `medium → opus`, `high → opus`).
- **effort** — the derived dispatch effort via `tier_to_dispatch`
  (`low → low`, `medium → low`, `high → high`).

Blast radius (auth / schema / migration / exported API / 3+ files) is detected
deterministically and forces the `high` tier (→ `opus` @ `high`) for every role
EXCEPT `implement`, which caps at `medium` (→ `opus` @ `low` — see
Register-conditioned rows below) — a sensitive change is never silently
downgraded.

## Roles

| role | autonomous-minimal (tier / model / effort) | semi-autonomous (tier / model / effort) |
|------|---------------------------------------------|------------------------------------------|
"""

_TIER_MAP_FOOTER = """
## Register-conditioned rows

The `implement` role carries the `by_register` sentinel in both autonomy
profiles: it does not fix a tier, it defers to the WP's own C2 `register`/
`severity` fields — `register: spike` → `low`; `register: production` →
`sonnet-medium`, escalating to `medium` (opus@low, never opus@high) when
`severity: HIGH` or blast radius fires. This preserves per-WP tiering for the
code-writing role while every other role reads its fixed band from
`ROLE_TIER`.

## Autonomy profiles

- **autonomous-minimal** — cost-lean: the cheapest tier that still does the job,
  escalating only on blast radius. Default for fully-autonomous runs.
- **semi-autonomous** — a human reviews the output, so spend for quality at the
  gates feeding that review (the WP `wp-verify` pass, the `panel`, the
  last-WP `integration-review`).
"""


def _tier_cell(value: str) -> str:
    """Render one ROLE_TIER cell as `tier / model / effort` (or the sentinel)."""
    if value == "by_register":
        return "by_register"
    return f"{value} / {COMPLEXITY_MODEL[value]} / {TIER_DISPATCH[value]['effort']}"


def render_tier_map() -> str:
    """Render tier-map.md verbatim from ROLE_TIER — the projection generator.

    Pure and offline. The single writer of tier-map.md; `--test-tiers` compares
    the on-disk file to this output (generation-drift gate) and `--regen-tier-map`
    writes it. No caller ever parses the markdown back."""
    rows = [
        f"| {role} | {_tier_cell(pr['autonomous-minimal'])} | {_tier_cell(pr['semi-autonomous'])} |"
        for role, pr in ROLE_TIER.items()
    ]
    return _TIER_MAP_HEADER + "\n".join(rows) + "\n" + _TIER_MAP_FOOTER


# ---------------------------------------------------------------------------
# Core resolver
# ---------------------------------------------------------------------------

def pick_agent(
    task_frontmatter: dict,
    touched_files: list[str],
    specialist_map: dict,
    *,
    discover: Optional[Callable[[dict, list[str], list[str]], object]] = None,
    ollama_health: Optional[Callable[[], bool]] = None,
) -> dict:
    """Resolve specialist and route for a single SDD task.

    Model/effort are NOT resolved here (wp-01/T17 removed the `complexity`
    input entirely) — pair this with `resolve_dispatch()`, which reads the
    WP's own `register`/`severity` C2 fields instead.

    Args:
        task_frontmatter: Parsed YAML frontmatter from the task file.
        touched_files: List of file paths the task will touch.
        specialist_map: Parsed specialist-map.yaml dict (by_tag, by_extension, …).
        discover: Callable(frontmatter, touched_files, known_specialists) → dict
            with key ``specialist`` (str or "none"). Invoked only when
            tag+extension lookup fails. Defaults to None, meaning no discovery
            fallback — EscalationRequired is raised immediately when map lookup
            fails and discover is None.
        ollama_health: Callable() → bool. Returns True if the local Ollama
            endpoint is healthy. Required (not optional) when route is ollama;
            if None and route is ollama, EscalationRequired is raised.

    Returns:
        dict with keys:
            specialist (str): agent name
            route (str): "api" or "ollama"
            discovered_by (str): "map" or "discovery-agent"
        Optionally also:
            proposed_map_entry (dict): when discover() named an unknown specialist

    Raises:
        EscalationRequired: when no specialist can be resolved, or ollama is down.
        ValueError: when specialist_map is malformed.
    """
    by_tag: dict[str, str] = specialist_map.get("by_tag", {})
    by_task_type: dict[str, str] = specialist_map.get("by_task_type", {})
    by_writing_kind: dict[str, str] = specialist_map.get("by_writing_kind", {})
    by_extension: dict[str, str] = specialist_map.get("by_extension", {})

    task_tags: list[str] = task_frontmatter.get("tags", []) or []
    task_type: str | None = task_frontmatter.get("task_type")
    writing_kind: str | None = task_frontmatter.get("writing_kind")
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
        discover_result = discover(task_frontmatter, touched_files, known_specialists)
        if not isinstance(discover_result, dict):
            raise EscalationRequired(
                "Discovery callable returned a non-dict result "
                f"({type(discover_result).__name__}); cannot resolve a specialist. "
                "Human assignment required (AskUserQuestion).",
                {"task": task_frontmatter.get("name"), "touched_files": touched_files},
            )
        discovered_name = discover_result.get("specialist") or "none"

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
        if ollama_health is None or not ollama_health():
            raise EscalationRequired(
                "Ollama route requested but health check failed (endpoint down or "
                "ollama_health callable not provided). No silent API fallback.",
                {"route": "ollama"},
            )
    else:
        route = "api"

    # ------------------------------------------------------------------
    # Result
    # ------------------------------------------------------------------
    result: dict = {
        "specialist": specialist,
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
    _frontmatter: dict, _touched: list[str], known: list[str]
) -> dict:
    """Minimal discovery stub for --self-test mode (no network)."""
    # Simulate returning the first known specialist
    if known:
        return {"specialist": known[0]}
    return {"specialist": "none"}


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
    # implement is register-driven (wp-01/T17): spike → low.
    expect("implement/spike", resolve_role_tier("implement", "semi-autonomous", register="spike"), "low")
    # production, no escalation → sonnet-medium.
    expect(
        "implement/production",
        resolve_role_tier("implement", "autonomous-minimal", register="production"),
        "sonnet-medium",
    )
    # production + severity HIGH → medium (opus@low, never opus@high — matches
    # the Dispatch Routing Matrix's "build ... blast radius → opus/low").
    expect(
        "implement/production-high-severity",
        resolve_role_tier("implement", "semi-autonomous", register="production", severity="HIGH"),
        "medium",
    )
    # production + blast radius → medium too, capped below the generic `high`
    # every other role gets from blast radius.
    expect(
        "implement/production-blast-radius",
        resolve_role_tier(
            "implement", "autonomous-minimal", register="production", blast_radius_hit=True,
        ),
        "medium",
    )
    # Missing register on a register-driven role escalates (no silent default).
    try:
        resolve_role_tier("implement", "semi-autonomous")
        failures.append("missing register did not escalate")
    except EscalationRequired:
        pass
    # Blast radius still forces the generic `high` for every OTHER role.
    expect(
        "blast-radius override (non-implement)",
        resolve_role_tier("wp-verify", "autonomous-minimal", blast_radius_hit=True),
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
    # implement's blast-radius escalation caps at opus@low through the
    # dispatch path too (never opus@high — see resolve_role_tier).
    expect(
        "resolve_dispatch/implement-blast",
        resolve_dispatch(
            "implement", "autonomous-minimal", register="production", blast_radius_hit=True,
        ),
        {"model": "opus", "effort": "low"},
    )
    # Pins the wp-harden-delta dispatch tier (opus@low).
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

    # Role alias (T17): "implement-code" resolves exactly like "implement".
    expect(
        "role-alias/implement-code",
        resolve_role_tier("implement-code", "semi-autonomous", register="spike"),
        resolve_role_tier("implement", "semi-autonomous", register="spike"),
    )
    expect(
        "role-alias/resolve_dispatch",
        resolve_dispatch("implement-code", "autonomous-minimal", register="production"),
        resolve_dispatch("implement", "autonomous-minimal", register="production"),
    )
    # dispatch_launched_event: only non-empty fields present, matches trace-events.md.
    expect(
        "dispatch_launched_event/full",
        dispatch_launched_event(
            {"specialist": "python-pro", "route": "api"},
            {"model": "opus", "effort": "high"},
            wp="wp-01-slim-core", task="T19",
        ),
        {"type": "dispatch.launched", "wp": "wp-01-slim-core", "task": "T19",
         "agent": "python-pro", "model": "opus", "effort": "high", "provider": "api"},
    )
    expect(
        "dispatch_launched_event/omits-empty",
        dispatch_launched_event({"specialist": "python-pro", "route": "api"},
                                 {"model": "opus", "effort": "high"}),
        {"type": "dispatch.launched", "agent": "python-pro", "model": "opus",
         "effort": "high", "provider": "api"},
    )

    # Generation-drift gate: the on-disk tier-map.md must equal render_tier_map()
    # (ROLE_TIER is authoritative; the md is a generated projection, never parsed).
    try:
        on_disk = TIER_MAP_PATH.read_text(encoding="utf-8")
    except FileNotFoundError:
        on_disk = None
    if on_disk != render_tier_map():
        failures.append(
            "tier-map.md drift: regenerate with --regen-tier-map "
            "(ROLE_TIER changed without updating the projection)"
        )

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
        "--regen-tier-map",
        action="store_true",
        help="Regenerate references/tier-map.md from ROLE_TIER and exit (no network).",
    )
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
    p.add_argument(
        "--emit-dispatch",
        action="store_true",
        help="After resolving --task, print ONE `dispatch.launched` event JSON "
             "line to stdout instead of the specialist/model/route YAML. This "
             "module never writes to a trace (no --feature-dir) — pipe the "
             "printed line through goalforge-trace-emit.",
    )
    p.add_argument(
        "--role",
        default="implement",
        help="Role for tier resolution — used both by --emit-dispatch and by "
             "the plain --task invocation (default: implement; 'implement-code' "
             "accepted as a warned alias).",
    )
    p.add_argument(
        "--profile",
        choices=ROLE_TIER_PROFILES,
        default="semi-autonomous",
        help="Autonomy profile for tier resolution.",
    )
    p.add_argument(
        "--wp",
        default=None,
        help="WP id to stamp on the --emit-dispatch event (optional).",
    )
    return p


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. Returns exit code."""
    args = _build_cli().parse_args(argv)

    if args.regen_tier_map:
        TIER_MAP_PATH.write_text(render_tier_map(), encoding="utf-8")
        print(f"wrote {TIER_MAP_PATH}")
        return 0

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

    touched: list[str] = frontmatter.get("_touched_files") or frontmatter.get("owned_files") or []
    register: str | None = frontmatter.get("register")
    # `prototype` (schema-5 spelling) normalizes to `spike` on READ ONLY —
    # never written back. Mirrors goalforge-validate.sh's normalize_register()
    # (wp-01 round 2, gate B new finding) so the two scripts agree on the
    # same field instead of diverging (validate.sh accepts it, this script
    # used to raise ValueError).
    if register is not None and str(register).strip() == "prototype":
        register = "spike"
    severity: str | None = frontmatter.get("severity")
    blast_hit = blast_radius(touched, file_threshold=8)

    if args.emit_dispatch:
        try:
            result = pick_agent(
                frontmatter, touched, specialist_map,
                discover=discover_fn, ollama_health=health_fn,
            )
        except EscalationRequired as exc:
            print(f"ESCALATION REQUIRED: {exc.reason}", file=sys.stderr)
            if exc.context:
                print(f"  context: {exc.context}", file=sys.stderr)
            return 1
        try:
            dispatch = resolve_dispatch(
                args.role, args.profile,
                register=register, severity=severity, blast_radius_hit=blast_hit,
            )
        except EscalationRequired as exc:
            print(f"ESCALATION REQUIRED: {exc.reason}", file=sys.stderr)
            if exc.context:
                print(f"  context: {exc.context}", file=sys.stderr)
            return 1
        except ValueError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 2
        event = dispatch_launched_event(
            result, dispatch,
            wp=args.wp, task=frontmatter.get("name") or task_path.stem,
        )
        print(json.dumps(event, sort_keys=True))
        return 0

    # Plain `--task <wp>/overview.md --role implement` (default role, no
    # --emit-dispatch) — execute/SKILL.md §3's canonical invocation. Prints
    # ONE JSON object with model + effort (wp-01/T17: no `complexity` input
    # anywhere in this path — the tier comes from the WP's own C2
    # `register`/`severity`). Specialist resolution is best-effort here: a WP
    # `overview.md` carries no `tags:` (C2), so an unmatched task_type/
    # extension is not fatal — model+effort is the contract this call makes.
    if register is None:
        print(
            f"ERROR: {task_path} has no 'register:' (required, C2 WP frontmatter)",
            file=sys.stderr,
        )
        return 2
    try:
        dispatch = resolve_dispatch(
            args.role, args.profile,
            register=register, severity=severity, blast_radius_hit=blast_hit,
        )
    except EscalationRequired as exc:
        print(f"ESCALATION REQUIRED: {exc.reason}", file=sys.stderr)
        if exc.context:
            print(f"  context: {exc.context}", file=sys.stderr)
        return 1
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    output: dict = {"role": args.role, **dispatch}
    try:
        picked = pick_agent(
            frontmatter, touched, specialist_map,
            discover=discover_fn, ollama_health=health_fn,
        )
        if picked.get("specialist"):
            output["specialist"] = picked["specialist"]
    except EscalationRequired:
        pass  # specialist is best-effort in this path

    print(json.dumps(output, sort_keys=True))
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
