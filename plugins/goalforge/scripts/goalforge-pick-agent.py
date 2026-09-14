"""goalforge-pick-agent — stage → agent / model / effort / provider resolver.

wp-03/T2 retired `specialist-map.yaml` (and its `review_pairs`, `--map`,
`proposed_map_entry`, and the `by_writing_kind` sentinel with it). A dispatch
is now resolved from TWO configured inputs, both read as DATA:

  references/dispatch.yaml    (`--dispatch <path>`) — per-stage `model`,
      `effort`, `provider`, `endpoint`, `egress`, plus the ordered
      `providers` preference list. Stage keys equal the ROLE_TIER keys.
  references/expertise-map.yaml — the reading list unioned into the roster
      agent's `expertise:` slot (by_tag → by_task_type → by_extension).
      Read-only here; wp-02 owns it.

The dispatch TARGET is always one roster agent under `agents/` (ROLE_AGENT) —
never a specialist name. `route` (the dispatch sense) is renamed `endpoint`
(ticket-62): `session` for the native provider, `leaf` for an agent-dispatch
`headless_dispatch`.

No hard default anywhere. No silent model/provider fallback: an unknown role,
profile, tier, stage, or an exhausted provider list raises EscalationRequired.

Public API:
    resolve_stage(role, frontmatter, touched_files, dispatch, expertise_map,
                  *, profile, simulations=()) -> dict
        The one call: returns {role, agent, expertise, model, effort,
        provider, endpoint, egress, propose_only} (plus `warn` when a leaf
        overspend was kept).

    next_provider(provider_names, current, exit_code, reason) -> (name, warn)
        Pure provider fall-through per leaf-interface.md §5/§6 hazard 2.

    admission.resolve(role, task_class, provider, model) -> Admission
        The admission table decides the resolver verdict for role
        `implement` — scripts/goalforge-admission.py owns the table, the
        task class and the verdict; references/admission.md is the contract.

    tier_to_dispatch(tier) / resolve_dispatch(role, profile, …) -> {model, effort}
    dispatch_launched_event(pick_result, dispatch_result, *, wp=, task=)

Role key: the canonical key is ``"implement"``. ``ROLE_ALIASES`` maps the
retired names (``implement-code``, ``wp-harden-delta``) one way, warning once.

CLI:
    python3 goalforge-pick-agent.py --task <wp>/overview.md --role implement
    python3 goalforge-pick-agent.py --task <f> --role judge --dispatch <yaml>
    python3 goalforge-pick-agent.py --task <f> --emit-dispatch [--wp <id>]
    python3 goalforge-pick-agent.py --regen-tier-map | --test-tiers
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

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
# source of truth. Bare tier names, never pinned versions — the claude CLI
# resolves the current model for each tier (the no-pinning rule in CLAUDE.md).
# A dispatched subagent brief needs BOTH a model and an effort level, stated
# explicitly (never inherited from the agent's .md defaults).
TIER_DISPATCH: dict[str, dict[str, str]] = {
    "low":    {"model": "sonnet", "effort": "low"},
    "medium": {"model": "opus",   "effort": "low"},
    "high":   {"model": "opus",   "effort": "high"},
    # wp-01/T17: the `implement` role's "production, not escalated" band —
    # sonnet@medium, distinct from the shared `medium` (opus@low) band other
    # roles read. See resolve_role_tier()'s "by_register" branch.
    "sonnet-medium": {"model": "sonnet", "effort": "medium"},
}

# Model-only view of TIER_DISPATCH, derived — never a second table.
COMPLEXITY_MODEL: dict[str, str] = {t: d["model"] for t, d in TIER_DISPATCH.items()}

# Every value admissible as a NATIVE dispatch `model` — the Claude tier
# vocabulary the Agent/Workflow tool resolves, plus the `by_register` sentinel.
# A non-native stage row must carry the PROVIDER's model id, never one of these
# (a leaf exits 2 on a tier name); a native row must carry one of these.
CLAUDE_TIER_MODELS: frozenset[str] = frozenset(
    set(COMPLEXITY_MODEL.values()) | {"haiku", "fable", "by_register"}
)

PKG_ROOT = Path(__file__).resolve().parent.parent
DISPATCH_PATH = PKG_ROOT / "references" / "dispatch.yaml"
EXPERTISE_MAP_PATH = PKG_ROOT / "references" / "expertise-map.yaml"
TIER_MAP_PATH = PKG_ROOT / "references" / "tier-map.md"
AGENTS_DIR = PKG_ROOT / "agents"

# The dispatch-decision ledger performance.md names. Overridable for tests.
DEFAULT_LEDGER = "data/dispatch-decisions.jsonl"

# Leaf exit codes that carry no result → fall through to the next provider
# (leaf-interface.md §5 and §6 hazard 2: unreachable / model-not-found, and
# the two quota subtypes of exit 4, whose turn was REFUSED).
FALLTHROUGH_EXITS = (1, 2)
FALLTHROUGH_REASONS = ("plan_quota_exhausted", "metered_rate_limited")
# Exit 4 subtypes whose turn COMPLETED — the result is kept, the overspend
# is named in a WARN row.
OVERSPEND_REASONS = ("budget_exceeded", "budget_check_failed")


# ---------------------------------------------------------------------------
# Canonical role → model-tier map (single source of truth)
# ---------------------------------------------------------------------------
# Every goalforge dispatcher resolves the model tier for a dispatched ROLE
# here — none of them restates the table. A "tier" is one of
# low|medium|high|sonnet-medium and maps to a concrete model via
# COMPLEXITY_MODEL.
#
# Two autonomy profiles:
#   - "autonomous-minimal": cost-lean — the cheapest tier that still does the
#     job, escalating only on blast radius.
#   - "semi-autonomous": a human reviews the output, so spend for quality at
#     the gates feeding that review. The resolver and CLI default.
#
# Blast radius (auth / schema / migration / exported API / 3+ files) is
# detected deterministically and forces the "high" tier regardless of
# role/profile — a sensitive change is never silently downgraded.

ROLE_TIER_PROFILES = ("autonomous-minimal", "semi-autonomous")

# tier ∈ {low, medium, high}; the sentinel "by_register" defers to the WP's own
# C2 `register`/`severity` fields (preserves per-WP tiering for the `implement`
# role).
ROLE_TIER: dict[str, dict[str, str]] = {
    #  role                  autonomous-minimal   semi-autonomous
    "implement":          {"autonomous-minimal": "by_register",   "semi-autonomous": "by_register"},
    "discovery":          {"autonomous-minimal": "low",           "semi-autonomous": "low"},
    "feature-audit":      {"autonomous-minimal": "medium",        "semi-autonomous": "medium"},  # Tier-1 cold whole-feature review
    "harden-review":      {"autonomous-minimal": "low",           "semi-autonomous": "medium"},  # Tier-2 WP-scoped delta (was wp-harden-delta)
    "wp-verify":          {"autonomous-minimal": "high",          "semi-autonomous": "high"},    # grader — opus@high on every profile (ticket-48)
    "simplify":           {"autonomous-minimal": "medium",        "semi-autonomous": "medium"},
    "judge":              {"autonomous-minimal": "high",          "semi-autonomous": "high"},    # grader — opus@high on every profile (ticket-48)
    "panel":              {"autonomous-minimal": "high",          "semi-autonomous": "high"},    # convened only for complex+irreversible
    "integration-review": {"autonomous-minimal": "medium",        "semi-autonomous": "high"},    # last-WP cross-WP review
    "second_opinion":     {"autonomous-minimal": "low",           "semi-autonomous": "low"},     # one cheap non-native cross-check
}

# One-way aliases for retired role keys: a caller in transition never
# hard-fails, and the warning nudges it to migrate rather than hiding the
# mismatch permanently. wp-03/T2 added `wp-harden-delta` → `harden-review`.
ROLE_ALIASES: dict[str, str] = {
    "implement-code": "implement",
    "wp-harden-delta": "harden-review",
}

# Role → roster agent (agents/*.md `name:`). The dispatch TARGET is always a
# roster agent; the expertise map supplies what it reads, never who runs.
ROLE_AGENT: dict[str, str] = {
    "implement":          "goalforge-implementer",
    "discovery":          "goalforge-researcher",
    "feature-audit":      "goalforge-reviewer",
    "harden-review":      "goalforge-reviewer",
    "wp-verify":          "goalforge-evaluation-expert",
    "simplify":           "goalforge-reviewer",
    "judge":              "goalforge-evaluation-expert",
    "panel":              "goalforge-reviewer",
    "integration-review": "goalforge-reviewer",
    "second_opinion":     "goalforge-reviewer",
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
    ``register``/``severity`` fields instead: ``register: spike`` → ``low``;
    ``register: production`` → ``sonnet-medium``, escalating to ``medium``
    (opus@low) when ``severity: HIGH`` or blast radius fires (matches the
    Dispatch Routing Matrix's "build at complexity high or blast radius →
    opus/low", never opus@high, for this role). ``register: spike`` returns
    ``low`` UNCONDITIONALLY, ahead of the blast-radius/severity check — a
    spike register deliberately overrides blast radius for this role. Every
    other role reads ``ROLE_TIER`` directly. An unknown role or profile
    escalates rather than silently defaulting. ``role`` is alias-normalized
    first."""
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
) -> str:
    """Resolve the concrete model class for a role via the canonical tier map."""
    tier = resolve_role_tier(
        role, profile, register=register, severity=severity,
        blast_radius_hit=blast_radius_hit,
    )
    return COMPLEXITY_MODEL[tier]


def tier_to_dispatch(tier: str) -> dict[str, str]:
    """Instantiate a tier (low|medium|high) as an explicit ``{model, effort}``.

    Every SDD subagent brief states model AND effort, resolved here rather
    than left to the agent's ``.md`` frontmatter defaults. Pure and offline.
    An unknown tier raises ``EscalationRequired`` (no silent default)."""
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
    knobs on a brief."""
    tier = resolve_role_tier(
        role, profile, register=register, severity=severity,
        blast_radius_hit=blast_radius_hit,
    )
    return tier_to_dispatch(tier)


# ---------------------------------------------------------------------------
# dispatch.yaml + expertise-map.yaml (both read as DATA)
# ---------------------------------------------------------------------------

def load_dispatch(path: Path | None = None) -> dict:
    """Load references/dispatch.yaml (or an explicit ``--dispatch`` path)."""
    target = path or DISPATCH_PATH
    with open(target, "r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    if not isinstance(data, dict):
        raise ValueError(f"dispatch file is not a mapping: {target}")
    return data


def load_expertise_map(path: Path | None = None) -> dict:
    """Load references/expertise-map.yaml (wp-02-owned data, read-only here)."""
    target = path or EXPERTISE_MAP_PATH
    try:
        with open(target, "r", encoding="utf-8") as fh:
            return yaml.safe_load(fh) or {}
    except FileNotFoundError:
        return {}


def stage_row(dispatch: dict, role: str) -> dict:
    """Return the dispatch.yaml stage row for ``role``. No silent default."""
    stages = dispatch.get("stages") or {}
    row = stages.get(role)
    if not isinstance(row, dict):
        raise EscalationRequired(
            f"No stage row for {role!r} in the dispatch file. Add it to "
            "`stages:` — no silent default.",
            {"known_stages": sorted(stages)},
        )
    return row


def provider_row(dispatch: dict, name: str) -> dict:
    """Return the `providers:` entry named ``name``. No silent default."""
    for p in dispatch.get("providers") or []:
        if isinstance(p, dict) and p.get("name") == name:
            return p
    raise EscalationRequired(
        f"Provider {name!r} is not in the dispatch file's `providers:` list.",
        {"provider": name},
    )


def resolve_expertise(
    expertise_map: dict, frontmatter: dict, touched_files: list[str]
) -> list[str]:
    """Union the expertise bundles for a WP: by_tag → by_task_type → by_extension.

    Order preserved, duplicates dropped. No catch-all default: an unmatched WP
    gets an empty bundle and the roster agent runs on its baseline `skills:`."""
    refs: list[str] = []

    def add(bundle: object) -> None:
        if isinstance(bundle, list):
            for ref in bundle:
                if isinstance(ref, str) and ref not in refs:
                    refs.append(ref)

    by_tag = expertise_map.get("by_tag") or {}
    for tag in frontmatter.get("tags") or []:
        if isinstance(tag, str):
            add(by_tag.get(tag))

    task_type = frontmatter.get("task_type")
    if isinstance(task_type, str):
        add((expertise_map.get("by_task_type") or {}).get(task_type))

    by_extension = expertise_map.get("by_extension") or {}
    for f in touched_files:
        ext = Path(f).suffix.lower()
        if ext:
            add(by_extension.get(ext))
    return refs


# ---------------------------------------------------------------------------
# Admission — the admission table decides the resolver verdict
# ---------------------------------------------------------------------------
# `scripts/goalforge-admission.py` owns the table, the deterministic task-class
# key and the verdict function (contract: `references/admission.md`). This
# module is its ONLY caller and the ONLY ledger writer: the verdict comes back
# as data and is recorded here, never there. Compile-level dispatch of a
# non-native implement row stays refused until `wp-08-admitted-execution`.

ADMISSION_PATH = PKG_ROOT / "scripts" / "goalforge-admission.py"


def _load_admission():
    """Import goalforge-admission.py by path (its filename is not importable)."""
    spec = importlib.util.spec_from_file_location("goalforge_admission", ADMISSION_PATH)
    if spec is None or spec.loader is None:  # pragma: no cover
        raise EscalationRequired(f"cannot import the admission module at {ADMISSION_PATH}")
    module = importlib.util.module_from_spec(spec)
    # Registered before exec: the module defines dataclasses, which resolve
    # their annotations through sys.modules.
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


admission = _load_admission()
Admission = admission.Admission


def _verification_command(frontmatter: dict) -> str:
    """The WP's ``goal.verification.command`` — the containment block's oracle."""
    goal = frontmatter.get("goal")
    verification = goal.get("verification") if isinstance(goal, dict) else None
    if isinstance(verification, dict):
        return str(verification.get("command") or "")
    return ""


# ---------------------------------------------------------------------------
# Provider fall-through (leaf-interface.md §5 / §6 hazard 2)
# ---------------------------------------------------------------------------

def next_provider(
    provider_names: list[str],
    current: str,
    exit_code: int,
    reason: str | None = None,
) -> tuple[str, bool]:
    """Decide the provider after a leaf terminated with ``exit_code``/``reason``.

    Pure. Returns ``(provider_name, warn)``:

      * exit 1 / 2, or exit 4 with reason ``plan_quota_exhausted`` /
        ``metered_rate_limited`` — the turn was REFUSED and carries no
        result, so fall through to the NEXT name in preference order.
      * exit 4 with ``budget_exceeded`` / ``budget_check_failed`` — the turn
        COMPLETED and its result is kept; returns ``(current, True)`` so the
        caller emits a WARN row naming the overspend.
      * exit 0 / 3 (and any unmodelled code) — keep ``current``.

    Raises ``EscalationRequired`` when the list is exhausted."""
    if current not in provider_names:
        raise EscalationRequired(
            f"Provider {current!r} is not in the configured preference order.",
            {"providers": provider_names},
        )
    if exit_code == 4 and reason in OVERSPEND_REASONS:
        return current, True
    falls_through = exit_code in FALLTHROUGH_EXITS or (
        exit_code == 4 and reason in FALLTHROUGH_REASONS
    )
    if not falls_through:
        return current, False
    idx = provider_names.index(current) + 1
    if idx >= len(provider_names):
        raise EscalationRequired(
            "Every configured provider was exhausted "
            f"(last: {current!r}, exit {exit_code}"
            + (f", reason {reason!r}" if reason else "")
            + "). No silent fallback — human routing decision required.",
            {"providers": provider_names, "exit_code": exit_code, "reason": reason},
        )
    return provider_names[idx], False


def parse_simulation(spec: str) -> tuple[int, str | None]:
    """Parse a ``--simulate-leaf "<exit>[:<reason>]"`` value."""
    code, _, reason = spec.partition(":")
    try:
        return int(code), (reason or None)
    except ValueError as exc:
        raise ValueError(
            f"--simulate-leaf expects <exit>[:<reason>], got {spec!r}"
        ) from exc


def _walk_providers(
    dispatch: dict, start: str, simulations: list[tuple[int, str | None]]
) -> tuple[str, bool]:
    """Replay simulated leaf terminations from ``start``, one per attempt."""
    names = [
        p["name"] for p in (dispatch.get("providers") or [])
        if isinstance(p, dict) and "name" in p
    ]
    current = start
    warn = False
    for exit_code, reason in simulations:
        nxt, w = next_provider(names, current, exit_code, reason)
        warn = warn or w
        if nxt == current:
            break
        current = nxt
    return current, warn


# ---------------------------------------------------------------------------
# Dispatch decision ledger (degrade-not-block)
# ---------------------------------------------------------------------------

def ledger_path() -> Path:
    """Resolve the dispatch decision ledger (``GOALFORGE_DISPATCH_LEDGER``)."""
    explicit = os.environ.get("GOALFORGE_DISPATCH_LEDGER")
    if explicit:
        return Path(explicit)
    root = os.environ.get("CLAUDE_CONFIG_DIR") or str(Path.home() / ".claude")
    return Path(root) / DEFAULT_LEDGER


def append_ledger_row(row: dict, path: Path | None = None) -> bool:
    """Append one dispatch decision row (propose-only | admitted | refused).

    One shape, one writer (references/admission.md § The ledger row).
    Degrade-not-block on OSError."""
    target = path or ledger_path()
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        with open(target, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(row, sort_keys=True) + "\n")
        return True
    except OSError as exc:
        print(
            f"goalforge-pick-agent: WARN could not append the dispatch "
            f"decision ledger row to {target}: {exc}",
            file=sys.stderr,
        )
        return False


# ---------------------------------------------------------------------------
# Core resolver
# ---------------------------------------------------------------------------

def resolve_stage(
    role: str,
    frontmatter: dict,
    touched_files: list[str],
    dispatch: dict,
    expertise_map: dict,
    *,
    profile: str = "semi-autonomous",
    simulations: list[tuple[int, str | None]] | None = None,
    admitted: list[dict] | None = None,
) -> dict:
    """Resolve one stage dispatch from dispatch.yaml + expertise-map.yaml.

    The stage row's ``model``/``effort`` WIN when explicit; the ``by_register``
    sentinel (the `implement` row) resolves through the register/severity/
    blast-radius logic in ``resolve_role_tier``. Provider starts at the stage
    row's ``provider`` and falls through the preference order per
    ``next_provider`` for each simulated leaf termination.

    For role ``implement`` the admission table decides the resolver verdict:
    ``admitted`` is the LOADED table (``None`` reads the shipped one — there is
    no none-means-skip path). A refused non-native provider is replaced by the
    dispatch file's first ``kind: native`` provider; with no native row to fall
    back to, ``ValueError`` (caller → exit 2)."""
    role = _resolve_role_alias(role)
    if role not in ROLE_AGENT:
        raise EscalationRequired(
            f"No roster agent for role {role!r} — no silent default.",
            {"known_roles": sorted(ROLE_AGENT)},
        )
    row = stage_row(dispatch, role)

    register = frontmatter.get("register")
    if register is not None and str(register).strip() == "prototype":
        # schema-5 spelling normalizes to `spike` on READ ONLY, mirroring
        # goalforge-validate.sh's normalize_register().
        register = "spike"
    severity = frontmatter.get("severity")
    blast_hit = blast_radius(touched_files, file_threshold=8)

    if row.get("model") == "by_register" or row.get("effort") == "by_register":
        band = resolve_dispatch(
            role, profile,
            register=register, severity=severity, blast_radius_hit=blast_hit,
        )
        model = band["model"] if row.get("model") == "by_register" else row["model"]
        effort = band["effort"] if row.get("effort") == "by_register" else row["effort"]
    else:
        model, effort = row.get("model"), row.get("effort")
    if not model or not effort:
        raise EscalationRequired(
            f"Stage row {role!r} is missing model and/or effort.", {"row": row}
        )

    start = row.get("provider")
    if not start:
        raise EscalationRequired(
            f"Stage row {role!r} names no provider.", {"row": row}
        )
    chosen, warn = _walk_providers(dispatch, start, simulations or [])
    provider = provider_row(dispatch, chosen)

    # The task class is derived from the WP's OWN `owned_files`, never from
    # `touched_files`: a per-invocation file list would make the admission key
    # vary by caller.
    task_class = admission.task_class(frontmatter)
    if role == "implement":
        table = admission.load() if admitted is None else admitted
        verdict = admission.resolve(role, task_class, provider, model, table)
    else:
        verdict = Admission(provider.get("kind") == "native", "non-implement role")
    propose_only = provider.get("kind") != "native"

    extra: dict = {}
    if role == "implement" and propose_only:
        extra["admission_reason"] = verdict.reason
        propose_only = False
        if verdict.admitted:
            extra.update(
                admission_decision="admitted",
                evidence_ref=verdict.evidence_ref,
                permission_set=verdict.permission_set,
                containment={
                    "owned_files": list(frontmatter.get("owned_files") or []),
                    "verification_command": _verification_command(frontmatter),
                    "commit": False,
                },
            )
            print(
                "goalforge-pick-agent: WARN containment and permission_set are "
                "declared, not enforced by this package",
                file=sys.stderr,
            )
        else:
            native = next(
                (p for p in dispatch.get("providers") or []
                 if isinstance(p, dict) and p.get("kind") == "native"),
                None,
            )
            if native is None:
                raise ValueError(
                    f"no native provider for fallback: {chosen!r} is refused for "
                    f"{task_class} and the dispatch file lists no `kind: native` "
                    "provider to resolve instead"
                )
            extra.update(
                admission_decision="refused",
                refused_provider=chosen,
                refused_model=model,
            )
            # The fallback's band is the implement STAGE row's, resolved as for
            # a native provider — provider rows carry no model, so the refused
            # row's provider model id never survives.
            band = resolve_dispatch(
                role, profile,
                register=register, severity=severity, blast_radius_hit=blast_hit,
            )
            chosen = native["name"]
            row_model = row.get("model")
            model = (
                row_model
                if row_model != "by_register" and row_model in CLAUDE_TIER_MODELS
                else band["model"]
            )
            effort = row.get("effort") if row.get("effort") != "by_register" else band["effort"]

    result: dict = {
        "role": role,
        "agent": ROLE_AGENT[role],
        "expertise": resolve_expertise(expertise_map, frontmatter, touched_files),
        "model": model,
        "effort": effort,
        "provider": chosen,
        "endpoint": row.get("endpoint", "session"),
        "egress": row.get("egress", "none"),
        "propose_only": propose_only,
        "task_class": task_class,
        **extra,
    }
    if warn:
        result["warn"] = "leaf overspend kept (budget stop after a completed turn)"
    return result


# ---------------------------------------------------------------------------
# dispatch.launched event (C6/T20) — pure payload builder, no trace I/O here
# ---------------------------------------------------------------------------
# This module resolves WHO/WHAT to dispatch; it never has a --feature-dir and
# never writes to a trace. The CALLER pipes this payload through
# goalforge-trace-emit --feature-dir <dir>.

def dispatch_launched_event(
    pick_result: dict,
    dispatch_result: dict,
    *,
    wp: str | None = None,
    task: str | None = None,
) -> dict:
    """Build a `dispatch.launched` trace-event payload (schema:
    references/trace-events.md) from a resolve_stage() result.

    Only non-empty fields are included — the schema marks every field on this
    event type optional, so an unresolved wp/task/provider is omitted rather
    than sent as an empty string."""
    event: dict = {"type": "dispatch.launched"}
    if wp:
        event["wp"] = wp
    if task:
        event["task"] = task
    agent = pick_result.get("agent")
    if agent:
        event["agent"] = agent
    model = dispatch_result.get("model")
    if model:
        event["model"] = model
    effort = dispatch_result.get("effort")
    if effort:
        event["effort"] = effort
    provider = pick_result.get("provider")
    if provider:
        event["provider"] = provider
    return event


# ---------------------------------------------------------------------------
# tier-map.md projection (generated view of ROLE_TIER — no runtime md parsing)
# ---------------------------------------------------------------------------
# tier-map.md is a GENERATED, human-readable projection of ROLE_TIER — the dict
# stays the single authoritative source. render_tier_map() emits it; the
# --test-tiers eval drift-checks the on-disk file against this render.

_TIER_MAP_HEADER = """<!-- GENERATED FILE — do not hand-edit.
     Human-readable projection of the authoritative ROLE_TIER dict in
     scripts/goalforge-pick-agent.py. Regenerate from the dict; the
     `goalforge-pick-agent.py --test-tiers` eval drift-checks this projection
     against ROLE_TIER (no runtime markdown parsing anywhere). -->

# Dispatch Tier Map (role → tier × effort)

Projection of `ROLE_TIER` (scripts/goalforge-pick-agent.py) — the single
authoritative source for the BAND. Tiers are bare (`haiku`/`sonnet`/`opus`/
`fable`); effort is bare (`low`/`medium`/`high`/`xhigh`/`max`). No pinned
vendor model IDs. The per-stage `model`/`effort`/`provider`/`endpoint`/
`egress` actually dispatched are configured in `references/dispatch.yaml`,
whose stage keys equal the roles below.

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

`judge` and `wp-verify` are graders: ticket-48 re-bands both to `high`
(opus@high) on BOTH profiles, so every grader resolution differs from every
`implement` resolution in persona AND in model or effort.

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
  escalating only on blast radius.
- **semi-autonomous** — a human reviews the output, so spend for quality at the
  gates feeding that review (the `panel`, the last-WP `integration-review`).
  The resolver and CLI default.
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
# CLI
# ---------------------------------------------------------------------------

def _compiler_gates() -> tuple[tuple[str, str], ...]:
    """The `(label, role)` gate tuple `goalforge-workflow-compile.py` emits.

    Read from the compiler itself (imported by path — its filename is not
    importable) so the grader set asserted by ``--test-tiers`` cannot drift
    from the roles actually dispatched.

    An unreadable or unloadable compiler RAISES: `--test-tiers` is an oracle,
    and a silent ``()`` here would make its grader loop vacuous. The caller
    asserts the returned tuple is non-empty."""
    path = Path(__file__).resolve().parent / "goalforge-workflow-compile.py"
    spec = importlib.util.spec_from_file_location("goalforge_workflow_compile", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load the workflow compiler at {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return tuple(module.GATES)


def _test_tiers() -> int:
    """Deterministic tier-selection eval for the canonical role→tier map.

    Asserts the invariants the dispatchers rely on, iterating
    ROLE_TIER_PROFILES where a claim is profile-wide. Returns 0 on success,
    1 on any failed assertion (no network, no model)."""
    failures: list[str] = []

    def expect(label: str, got, want) -> None:
        if got != want:
            failures.append(f"{label}: got {got!r}, want {want!r}")

    # ── bands ────────────────────────────────────────────────────────────
    # Graders are opus@high on EVERY profile (ticket-48).
    for profile in ROLE_TIER_PROFILES:
        for grader in ("judge", "wp-verify"):
            expect(f"{grader}/{profile}", resolve_role_tier(grader, profile), "high")
            expect(
                f"dispatch/{grader}/{profile}",
                resolve_dispatch(grader, profile),
                {"model": "opus", "effort": "high"},
            )
    expect("feature-audit", resolve_role_tier("feature-audit", "autonomous-minimal"), "medium")
    expect("panel", resolve_role_tier("panel", "semi-autonomous"), "high")
    expect("second_opinion/auto", resolve_role_tier("second_opinion", "autonomous-minimal"), "low")
    expect("second_opinion/semi", resolve_role_tier("second_opinion", "semi-autonomous"), "low")
    expect("harden-review/semi", resolve_dispatch("harden-review", "semi-autonomous"),
           {"model": "opus", "effort": "low"})
    # implement is register-driven: spike → low.
    expect("implement/spike", resolve_role_tier("implement", "semi-autonomous", register="spike"), "low")
    expect(
        "implement/production",
        resolve_role_tier("implement", "autonomous-minimal", register="production"),
        "sonnet-medium",
    )
    expect(
        "implement/production-high-severity",
        resolve_role_tier("implement", "semi-autonomous", register="production", severity="HIGH"),
        "medium",
    )
    expect(
        "implement/production-blast-radius",
        resolve_role_tier(
            "implement", "autonomous-minimal", register="production", blast_radius_hit=True,
        ),
        "medium",
    )
    try:
        resolve_role_tier("implement", "semi-autonomous")
        failures.append("missing register did not escalate")
    except EscalationRequired:
        pass
    expect(
        "blast-radius override (non-implement)",
        resolve_role_tier("simplify", "autonomous-minimal", blast_radius_hit=True),
        "high",
    )

    # ── ticket-48 distinctness: grader vs implement, on BOTH profiles ────
    # The grader set is EVERY grader role the workflow compiler emits as an
    # agent() node — read from its GATES tuple so the two cannot drift. The
    # second opinion is absent from GATES by design (a log() line, not an
    # agent node: its row runs on a non-native provider), so no filter here.
    graders = tuple(role for _, role in _compiler_gates())
    if not graders:
        failures.append("compiler GATES exposed no grader role")
    for profile in ROLE_TIER_PROFILES:
        for register in ("spike", "production"):
            for severity in (None, "HIGH"):
                impl = resolve_dispatch(
                    "implement", profile, register=register, severity=severity,
                )
                for grader in graders:
                    grade = resolve_dispatch(grader, profile)
                    label = f"ticket-48/{grader}/{profile}/{register}/{severity}"
                    if ROLE_AGENT[grader] == ROLE_AGENT["implement"]:
                        failures.append(f"{label}: persona not distinct")
                    if (impl["model"], impl["effort"]) == (grade["model"], grade["effort"]):
                        failures.append(
                            f"{label}: model AND effort both equal implement's "
                            f"{impl!r}"
                        )

    # ── blast radius ─────────────────────────────────────────────────────
    expect("br/auth-path", blast_radius(["src/auth/login.py"]), True)
    expect("br/schema-path", blast_radius(["db/schema.sql"]), True)
    expect("br/schemas-plural", blast_radius(["db/schemas/users.sql"]), True)
    expect("br/oauth-path", blast_radius(["src/oauth/callback.py"]), True)
    expect("br/3-files", blast_radius(["a.py", "b.py", "c.py"]), True)
    expect("br/single-safe", blast_radius(["src/util/format.py"]), False)
    expect("br/doc-schema-name", blast_radius(["skills/idea/references/idea-schema.md"]), False)
    expect("br/doc-auth-name", blast_radius(["references/skill-authoring-best-practices.md"]), False)
    expect("br/3-docs", blast_radius(["a.md", "b.md", "c.md"]), True)
    expect("br/authoring-code", blast_radius(["src/authoring/tool.py"]), False)
    expect("role_model/judge/semi", role_model("judge", "semi-autonomous"), COMPLEXITY_MODEL["high"])

    # ── tier instantiation ───────────────────────────────────────────────
    expect("dispatch/low", tier_to_dispatch("low"), {"model": "sonnet", "effort": "low"})
    expect("dispatch/medium", tier_to_dispatch("medium"), {"model": "opus", "effort": "low"})
    expect("dispatch/high", tier_to_dispatch("high"), {"model": "opus", "effort": "high"})
    expect(
        "resolve_dispatch/implement-blast",
        resolve_dispatch(
            "implement", "autonomous-minimal", register="production", blast_radius_hit=True,
        ),
        {"model": "opus", "effort": "low"},
    )
    expect(
        "complexity-model-derived",
        COMPLEXITY_MODEL,
        {t: d["model"] for t, d in TIER_DISPATCH.items()},
    )
    try:
        tier_to_dispatch("mega")
        failures.append("unknown tier did not escalate")
    except EscalationRequired:
        pass
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
    # One-way role aliases resolve exactly like their canonical key.
    expect(
        "role-alias/implement-code",
        resolve_role_tier("implement-code", "semi-autonomous", register="spike"),
        resolve_role_tier("implement", "semi-autonomous", register="spike"),
    )
    expect(
        "role-alias/wp-harden-delta",
        resolve_dispatch("wp-harden-delta", "semi-autonomous"),
        resolve_dispatch("harden-review", "semi-autonomous"),
    )
    expect(
        "dispatch_launched_event/full",
        dispatch_launched_event(
            {"agent": "goalforge-implementer", "provider": "anthropic"},
            {"model": "opus", "effort": "high"},
            wp="wp-01-slim-core", task="T19",
        ),
        {"type": "dispatch.launched", "wp": "wp-01-slim-core", "task": "T19",
         "agent": "goalforge-implementer", "model": "opus", "effort": "high",
         "provider": "anthropic"},
    )
    expect(
        "dispatch_launched_event/omits-empty",
        dispatch_launched_event({"agent": "goalforge-implementer", "provider": "anthropic"},
                                {"model": "opus", "effort": "high"}),
        {"type": "dispatch.launched", "agent": "goalforge-implementer",
         "model": "opus", "effort": "high", "provider": "anthropic"},
    )

    # ── provider fall-through (pure) ─────────────────────────────────────
    chain = ["anthropic", "stub-a", "stub-b"]
    expect("fallthrough/unreachable", next_provider(chain, "anthropic", 1), ("stub-a", False))
    expect("fallthrough/model-not-found", next_provider(chain, "stub-a", 2), ("stub-b", False))
    expect(
        "fallthrough/plan-quota",
        next_provider(chain, "anthropic", 4, "plan_quota_exhausted"),
        ("stub-a", False),
    )
    expect(
        "fallthrough/rate-limit",
        next_provider(chain, "anthropic", 4, "metered_rate_limited"),
        ("stub-a", False),
    )
    expect(
        "keep-on-overspend/budget-exceeded",
        next_provider(chain, "anthropic", 4, "budget_exceeded"),
        ("anthropic", True),
    )
    expect(
        "keep-on-overspend/budget-check-failed",
        next_provider(chain, "anthropic", 4, "budget_check_failed"),
        ("anthropic", True),
    )
    expect("keep/success", next_provider(chain, "anthropic", 0), ("anthropic", False))
    expect("keep/timeout", next_provider(chain, "anthropic", 3), ("anthropic", False))
    try:
        next_provider(chain, "stub-b", 1)
        failures.append("exhausted provider list did not escalate")
    except EscalationRequired:
        pass

    # ── row-equality: dispatch.yaml stages == ROLE_TIER keys ─────────────
    try:
        shipped = load_dispatch()
    except (OSError, ValueError) as exc:
        shipped = {}
        failures.append(f"dispatch.yaml unreadable: {exc}")
    stages = shipped.get("stages") or {}
    if stages:
        if sorted(stages) != sorted(ROLE_TIER):
            failures.append(
                f"dispatch.yaml stage keys {sorted(stages)} != ROLE_TIER keys "
                f"{sorted(ROLE_TIER)}"
            )
        for grader in ("judge", "wp-verify"):
            row = stages.get(grader) or {}
            if (row.get("model"), row.get("effort")) != ("opus", "high"):
                failures.append(
                    f"ticket-48: dispatch.yaml {grader} row is "
                    f"{row.get('model')}/{row.get('effort')}, want opus/high"
                )
        # Every NON-grader row equals the semi-autonomous ROLE_TIER projection.
        # Exceptions, both narrow and both stated in dispatch.yaml's header:
        #   * the `by_register` sentinel (implement) defers to the WP register;
        #   * a row on a provider whose kind is not `native` carries that
        #     PROVIDER's model id, so only `effort` is comparable.
        kinds = {
            p.get("name"): p.get("kind")
            for p in (shipped.get("providers") or []) if isinstance(p, dict)
        }
        # Every role the compiler emits as an `agent()` node must sit on a
        # NATIVE provider row. Checked BEFORE the projection loop below, which
        # `continue`s past the `implement` row (its tier is the `by_register`
        # sentinel) and so could never see this class.
        for agent_role in ("implement", *(role for _, role in _compiler_gates())):
            row = stages.get(agent_role) or {}
            kind = kinds.get(row.get("provider"))
            if kind != "native":
                failures.append(
                    f"dispatch.yaml stage {agent_role!r} is emitted as an "
                    f"agent() node but its provider {row.get('provider')!r} "
                    f"has kind {kind!r}, not 'native'"
                )
        for name, row in stages.items():
            if name in ("judge", "wp-verify") or name not in ROLE_TIER:
                continue
            tier = ROLE_TIER[name]["semi-autonomous"]
            if tier == "by_register":
                continue
            want = tier_to_dispatch(tier)
            if kinds.get(row.get("provider")) == "native":
                got = {"model": row.get("model"), "effort": row.get("effort")}
            else:
                # A non-native row carries the PROVIDER's own model id, so the
                # model is not comparable to the tier projection — but it must
                # still NOT be a Claude tier name: a tier there exits 2 at the
                # leaf (model not found), and reaching `agent({model: ...})`
                # with a provider id is undispatchable. Both directions are the
                # B3/N2 failure class, so both are asserted.
                if row.get("model") in CLAUDE_TIER_MODELS:
                    failures.append(
                        f"dispatch.yaml stage {name!r} runs on a non-native "
                        f"provider but its model {row.get('model')!r} is a "
                        f"Claude tier name — a leaf exits 2 on it. Use the "
                        f"provider's own model id."
                    )
                want = {"effort": want["effort"]}
                got = {"effort": row.get("effort")}
            if got != want:
                failures.append(
                    f"dispatch.yaml stage {name!r} is {got!r}, want the "
                    f"semi-autonomous ROLE_TIER projection {want!r}"
                )

        provider_names = [
            p.get("name") for p in (shipped.get("providers") or []) if isinstance(p, dict)
        ]
        for name, row in stages.items():
            if row.get("provider") not in provider_names:
                failures.append(
                    f"stage {name!r} names provider {row.get('provider')!r}, "
                    "absent from `providers:`"
                )
            if row.get("endpoint") not in ("session", "leaf"):
                failures.append(f"stage {name!r} endpoint {row.get('endpoint')!r} invalid")
            if row.get("egress") not in ("none", "diff-only", "overview", "full"):
                failures.append(f"stage {name!r} egress {row.get('egress')!r} invalid")

    # ── roster personas exist on disk ────────────────────────────────────
    roster = set()
    for f in sorted(AGENTS_DIR.glob("*.md")):
        for line in f.read_text(encoding="utf-8").splitlines()[:20]:
            if line.startswith("name:"):
                roster.add(line.split(":", 1)[1].strip())
                break
    for role, agent in ROLE_AGENT.items():
        if roster and agent not in roster:
            failures.append(f"role {role!r} names agent {agent!r}, absent from agents/")

    # ── retired input must be gone ───────────────────────────────────────
    if (PKG_ROOT / "references" / "specialist-map.yaml").exists():
        failures.append("references/specialist-map.yaml still on disk (retired by wp-03)")

    # Generation-drift gate: the on-disk tier-map.md must equal render_tier_map()
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
        description="goalforge pick-agent: resolve agent/model/effort/provider "
                    "for a stage from references/dispatch.yaml."
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
        "--dispatch",
        metavar="FILE",
        default=None,
        help="Path to dispatch.yaml (default: references/dispatch.yaml next to "
             "this package).",
    )
    p.add_argument(
        "--admitted",
        metavar="FILE",
        default=None,
        help="Admission table (default: the shipped "
             "references/admitted-providers.yaml). Absent is NOT a skip — the "
             "shipped table is read and decides the verdict.",
    )
    p.add_argument(
        "--simulate-leaf",
        metavar="EXIT[:REASON]",
        action="append",
        default=None,
        help="Test seam: replay one leaf termination per provider attempt, in "
             "order (e.g. --simulate-leaf 1 --simulate-leaf 0). Repeatable.",
    )
    p.add_argument(
        "--emit-dispatch",
        action="store_true",
        help="After resolving --task, print ONE `dispatch.launched` event JSON "
             "line to stdout instead of the resolution object. This module "
             "never writes to a trace (no --feature-dir) — pipe the printed "
             "line through goalforge-trace-emit.",
    )
    p.add_argument(
        "--role",
        default="implement",
        help="Stage/role to resolve — a dispatch.yaml `stages:` key (default: "
             "implement; 'implement-code' and 'wp-harden-delta' accepted as "
             "warned aliases).",
    )
    p.add_argument(
        "--profile",
        choices=ROLE_TIER_PROFILES,
        default="semi-autonomous",
        help="Autonomy profile for the by_register band.",
    )
    p.add_argument(
        "--wp",
        default=None,
        help="WP id to stamp on the --emit-dispatch event and the ledger row.",
    )
    return p


def _escalate(exc: EscalationRequired) -> int:
    print(f"ESCALATION REQUIRED: {exc.reason}", file=sys.stderr)
    if exc.context:
        print(f"  context: {exc.context}", file=sys.stderr)
    return 1


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

    frontmatter = _parse_frontmatter(task_path.read_text(encoding="utf-8"))
    if frontmatter is None:
        print(f"ERROR: no YAML frontmatter in {task_path}", file=sys.stderr)
        return 2

    # No `--admitted` flag means the SHIPPED table, never a skipped check.
    admitted_path = Path(args.admitted) if args.admitted else admission.ADMITTED_PATH
    try:
        admitted_table = admission.load(admitted_path)
    except admission.AdmissionTableError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    try:
        dispatch = load_dispatch(Path(args.dispatch) if args.dispatch else None)
    except FileNotFoundError as exc:
        print(f"ERROR: dispatch file not found: {exc}", file=sys.stderr)
        return 2
    except (ValueError, yaml.YAMLError) as exc:
        print(f"ERROR: unreadable dispatch file: {exc}", file=sys.stderr)
        return 2
    expertise_map = load_expertise_map()

    try:
        simulations = [parse_simulation(s) for s in (args.simulate_leaf or [])]
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    touched: list[str] = (
        frontmatter.get("_touched_files") or frontmatter.get("owned_files") or []
    )

    # A `by_register` stage row needs the WP's own C2 `register:`; every other
    # row carries an explicit band and does not.
    try:
        row = stage_row(dispatch, _resolve_role_alias(args.role))
    except EscalationRequired as exc:
        return _escalate(exc)
    if row.get("model") == "by_register" and frontmatter.get("register") is None:
        print(
            f"ERROR: {task_path} has no 'register:' (required, C2 WP frontmatter)",
            file=sys.stderr,
        )
        return 2

    try:
        resolution = resolve_stage(
            args.role, frontmatter, touched, dispatch, expertise_map,
            profile=args.profile, simulations=simulations,
            admitted=admitted_table,
        )
    except EscalationRequired as exc:
        return _escalate(exc)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if "warn" in resolution:
        print(
            json.dumps(
                {
                    "type": "dispatch.warn",
                    "role": resolution["role"],
                    "provider": resolution["provider"],
                    "reason": "budget-stop-after-completed-turn",
                    "detail": resolution["warn"],
                },
                sort_keys=True,
            ),
            file=sys.stderr,
        )

    # ONE row per dispatch decision, through the ONE writer. On a `refused` row
    # the provider/model named are the ones that were REFUSED, not the native
    # provider resolved in their place.
    decision = resolution.get("admission_decision")
    if decision or resolution["propose_only"]:
        append_ledger_row({
            "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "wp": args.wp or "",
            "role": resolution["role"],
            "provider": resolution.get("refused_provider") or resolution["provider"],
            "model": resolution.get("refused_model") or resolution["model"],
            "effort": resolution["effort"],
            "endpoint": resolution["endpoint"],
            "decision": decision or "propose-only",
            "task_class": resolution.get("task_class", ""),
            "reason": resolution.get("admission_reason", "") if decision else "",
            "evidence_ref": resolution.get("evidence_ref", ""),
            "admitted_source": str(admitted_path.resolve()),
            "admitted_override": bool(args.admitted),
        })

    if args.emit_dispatch:
        event = dispatch_launched_event(
            resolution, resolution,
            wp=args.wp, task=frontmatter.get("name") or task_path.stem,
        )
        print(json.dumps(event, sort_keys=True))
        return 0

    print(json.dumps(resolution, sort_keys=True))
    return 0


def _parse_frontmatter(text: str) -> dict | None:
    """Extract YAML frontmatter from text (--- delimited) or parse whole text."""
    lines = text.splitlines()
    if lines and lines[0].strip() == "---":
        end = next((i for i, ln in enumerate(lines[1:], 1) if ln.strip() == "---"), None)
        if end is not None:
            block = "\n".join(lines[1:end])
            return yaml.safe_load(block) or {}
    try:
        data = yaml.safe_load(text)
        return data if isinstance(data, dict) else None
    except yaml.YAMLError:
        return None


if __name__ == "__main__":
    sys.exit(main())
