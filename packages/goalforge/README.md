---
name: goalforge
description: "Router and index for the goalforge (Spec-Driven Development) planning skill chain, v3.0.0. Points to the child skills (capture → spec → decompose → harden → execute → verify plus the support stages) and holds the shared schema, templates, and specialist map. Use goalforge when you need to find the right planning skill, understand the folder/frontmatter contract, or are invoked via /spec /plan /implement /verify."
---

# goalforge — Skill Chain Index

**Chain:** `capture → spec → decompose → harden → execute → verify`

Orchestrated by `goalforge-run` (`run/chain.yaml`). Flat on-disk layout:
`plans/<feature>/<wp-id>/files`. Status lives in frontmatter — no lifecycle folders.
`goalforge` is the canonical and ONLY name of this chain; the legacy `sdd-*`
aliases were retired 2026-07-21.

## Child Skills

| Skill | Contract |
|---|---|
| `goalforge-capture` | Free-text intent → feature `overview.md` (status: draft) + route |
| `goalforge-spec` | Write `spec.md`; define measurable goal + verification criteria (draft → ready) |
| `goalforge-decompose` | Break the spec into WP `overview.md` files — WP overview + checklist, no task stubs; `--add-wp` mode |
| `goalforge-harden` | Resolve open questions; advance to `ready` |
| `goalforge-execute` | Dispatch one owner for the whole WP; one commit, no per-task checkpoint; `ready`/`executing` → `implemented` |
| `goalforge-verify` | Three gates (A deterministic, B fresh-context review, C goal judge) over the WP's single commit; `implemented → verified` |
| `goalforge-redecompose` | Reconcile a re-decomposition on a learning event |
| `goalforge-archive` | completed → archived (supersede edges) |
| `goalforge-onboard` | Onboard an existing repo into the chain |
| `goalforge-plan-index` | Plan index generation |
| `goalforge-run` | Chain orchestrator (route-aware); wires the chain via `chain.yaml` |

`prototype/` and `wayfind/` are non-chain tenants co-located in this package
(not chain stages). Details: `SKILL.md`.

## Shared References

| File | Purpose |
|---|---|
| `references/schema.md` | v3 frontmatter schemas, edge vocabulary |
| `references/state-machine.md` | Status machine + transition rules |
| `references/templates/` | Canonical file templates (frontmatter-first, placeholder tokens) |
| `references/dispatch.yaml` | per-stage model, effort, provider, endpoint, egress class |

## Install

Pick **one** route. Installing both registers every hook twice, and a doubled
`PreToolUse` gate blocks twice while a doubled `SessionStart` hook prints the
orientation block twice.

1. **Plugin (normal).** Add a row for this plugin to `enabledPlugins` in
   `~/.claude/settings.json`. Claude Code then reads `hooks/hooks.json` from the
   plugin root and `${CLAUDE_PLUGIN_ROOT}` resolves for you.
2. **Dev symlink (contributor).** Symlink this package where the harness looks
   for it. Nothing else is needed — every hook resolves its siblings through
   `readlink -f` on its own path, so the symlinked route finds them too.

### Hooks the plugin registers

Wired in `hooks/hooks.json`; the registration is asserted by
`hooks/tests/goalforge-hooks-json.test.sh`.

| Hook | Event | Matcher |
|---|---|---|
| `goalforge-launch-gate.sh` | PreToolUse | `Agent\|Workflow` |
| `goalforge-single-writer.sh` | PreToolUse | `Edit\|Write\|MultiEdit\|ctx_patch\|ctx_call` |
| `goalforge-transition-guard.sh` | PreToolUse | `Edit` |
| `goalforge-open-questions-gate.sh` | PreToolUse | `Edit` |
| `goalforge-context-fill.sh` | SessionStart | `startup\|clear\|compact` |
| `goalforge-session-start.sh` | SessionStart | `startup\|clear\|compact` |
| `goalforge-frontmatter-touch.sh` | PostToolUse | `Edit\|Write\|MultiEdit` |

If a `~/.claude/settings.json` still registers its own copies of any of these
by absolute path, that is a **double registration** — remove those rows when
the plugin is installed. `goalforge-plans-root.sh` (a sourced library),
`goalforge-pre-commit.sh` (a git hook, installed by
`scripts/goalforge-install-hooks.sh`) and `goalforge-quota-read.sh` (the quota
adapter the launch gate calls) are deliberately NOT hook registrations.

### Environment switches

| Variable | Default | Effect |
|---|---|---|
| `GOALFORGE_LAUNCH_GATE` | `1` | `0` disables the dispatch launch gate entirely — it exits 0 and prints nothing whatever the quota says. The teardown seam for a guardrail that can refuse your own dispatch. |
| `GOALFORGE_LAUNCH_THRESHOLD_PCT` | `10` | Remaining-5h-quota percentage below which a new `Agent`/`Workflow` dispatch is refused. A non-integer value falls back to the default. |
| `GOALFORGE_QUOTA_FIXTURE` | *(unset)* | Path to a JSON object supplying `five_h_remaining_pct` / `seven_d_remaining_pct`. Unset, unreadable or unparseable ⇒ quota unknown ⇒ the gate never blocks. The installed Claude Code exposes no remaining-quota figure locally (see the header of `hooks/goalforge-quota-read.sh`), so on this host the gate is dormant unless you supply one. |
| `GOALFORGE_LAUNCH_MARKER_DIR` | `${TMPDIR:-/tmp}/goalforge-launch-gate/<session-id>` | Where the once-per-session WARN marker lives. Created by the hook, reaped by the OS — goalforge never deletes it. |
| `GOALFORGE_SESSION_START` | `1` | `0` suppresses the SessionStart orientation block. |
| `GOALFORGE_HANDOFFS_DIR` | `<git root>/docs/handoffs` | Where the orientation block looks for handoffs at `status: ready`. |
| `GOALFORGE_CONTEXT_BUDGET_BYTES` | `800000` | Denominator of the context-fill estimate (~200k tokens at ~4 bytes/token). |
| `SDD_PLANS_DIR` | *(resolution order)* | Explicit plans root; otherwise `<git root>/plans`, then `$HOME/.claude/plans`. When it is set but names no directory, the session-start hook prints nothing rather than falling back to another root. |

The `goalforge-<child>` names in the tables above are the **historical bare
names**; each child's `SKILL.md` now carries `name:` equal to its directory
basename. Both identities, and the one deliberate divergence (`run/`), are
tabulated in `references/alias-map.md`.

## Status Machine (WP)

`draft → spec → hardened → ready → executing → verified`

`draft → ready` (feature gate) and `hardened → ready` (WP gate) are human-gated. `archived` is
terminal, reached only via explicit user action. Details:
`references/state-machine.md`.

## Related Skills

| Skill | Relationship |
|---|---|
| `implement` | Reused inside `goalforge-execute` sub-cycle |
| `verify-and-simplify` | Reused inside `goalforge-execute` sub-cycle |
| `wayfind` | Optional pre-capture on-ramp; graduates a converged decision map into `goalforge-capture` |
| `prototype` | Co-tenant; spike/prototype execution in a worktree |
| `goalforge-validate.sh` | Schema + status-vs-evidence + link + staleness checks |
