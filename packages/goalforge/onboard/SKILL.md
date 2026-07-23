---
name: goalforge-onboard
description: >
  Bootstraps the Spec-Driven Development chain in a repository: creates the
  plans/ root, installs the goalforge-validate pre-commit hook (via
  goalforge-install-hooks.sh), and stamps a minimal ## SDD pointer into the repo
  CLAUDE.md. Use when setting up SDD in a new or existing repo, when the user
  says "onboard this repo to SDD", "set up the SDD chain here", "install the SDD git hook",
  or "scaffold plans/". Uses the current status vocabulary only — not
  the legacy GSD lifecycle. Idempotent: safe to re-run.
metadata:
  version: 1.1.0
hooks:
  Stop:
    - hooks:
        - type: command
          command: "$HOME/.claude/scripts/skill-measure.sh goalforge-onboard"
---

# goalforge-onboard

Bootstraps the SDD chain in a repository. Three idempotent steps:

1. **Create `plans/`** — creates `plans/README.md` at the repo root if `plans/`
   is absent; leaves it untouched if it already exists.
2. **Install the pre-commit hook** — delegates entirely to
   `goalforge-install-hooks.sh`, which handles the chain-safe append-to-existing-hook
   case and the idempotency marker (`# >>> sdd-pre-commit >>>`).
3. **Stamp `## SDD` into `CLAUDE.md`** — appends a pointer block documenting
   the chain, plans root, hook, and status vocabulary. Creates a minimal
   `CLAUDE.md` if none exists; skips if a `## SDD` heading is already present.

## Usage

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/goalforge-onboard.sh [<repo-dir>]
```

`<repo-dir>` defaults to `git rev-parse --show-toplevel` from the current
working directory. Aborts with a clear message if the target is not a git
repository.

## What it delegates

Hook installation is fully delegated to the existing installer:

```
$HOME/.claude/skills/goalforge/scripts/goalforge-install-hooks.sh <repo-dir>
```

`goalforge-onboard` does not reimplement hook logic.

## Gotchas

- **Current vocabulary only.** The stamped `## SDD` block uses the current
  status vocabulary: WPs `draft→spec→hardened→ready→executing→verified`; tasks
  `pending→in-progress→implemented→verified` (`implemented` is the interim
  post-eval+commit state; `verified` is written only at the WP gate by
  `goalforge-verify`). It does NOT reference the legacy GSD 10-state lifecycle. Keep the
  stamped block in lockstep with `goalforge/references/schema.md` — it is the canonical
  vocabulary onboarded repos inherit.
- **Not a GitHub-issues setup.** This skill does not create GitHub issues,
  triage labels, milestones, or projects. That was the removed
  `setup-sdd-repo` surface. `goalforge-onboard` is purely on-disk scaffolding.
- **Idempotent everywhere.** Re-running is safe: `plans/` is not clobbered,
  the `## SDD` block is not duplicated, and the pre-commit hook marker check
  (`# >>> sdd-pre-commit >>>`) prevents double-installation.
- **The hook validates TOUCHED features under `--strict`, not commit hash.**
  It is a drift guard, not a verification step. Hash-based verification
  happens in `goalforge-verify` at verify-time, not in the pre-commit hook.
