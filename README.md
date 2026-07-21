# cogwright

**A marketplace of systems for running [Claude Code](https://claude.com/claude-code) as an agentic operating layer** — planning chains, project onboarding, memory, dispatch — built from one heavily-used personal setup and packaged so each system installs standalone.

The thesis: agentic coding gets reliable when the *process* is engineered — goals with verification built in, guardrails enforced outside the model's context, memory that persists, and honest status everywhere. Each plugin here is one of those process systems, extracted and hardened.

## Quickstart

```
/plugin marketplace add Truncuso/cogwright
/plugin install goalforge@cogwright
```

Each plugin is self-contained: installing one never requires another (declared relations degrade gracefully — a missing companion produces a warning, not a failure).

## Installing (contributor vs consumer)

`scripts/install.sh` covers both install modes:

```
scripts/install.sh --mode consumer      # prints the marketplace commands above + runs `claude plugin validate`
scripts/install.sh --mode contributor   # dev mode: symlink your skills dir at this checkout
scripts/install.sh --self-test          # fixture-sandbox self-test (never touches your real $HOME)
```

**Contributor (dev) mode** replaces `~/dotfiles/claude/skills/goalforge` with a
per-machine symlink pointing at `packages/goalforge` in *this* cogwright
checkout, so every future goalforge edit lands in the working tree and `git push`
keeps GitHub current. The swap is a strict, verified transaction:

- **Precondition — a cogwright checkout must be present.** The link target
  (`packages/goalforge`) has to resolve to a real package with a `SKILL.md`;
  contributor mode refuses if it does not.
- **Refuses to clobber drift.** If the existing real dir has uncommitted
  *tracked* changes versus the package it refuses rather than overwrite. Drift is
  measured on tracked content only (gitignored `__pycache__` / `evals/workspace`
  transients are ignored), never a raw `diff -r`.
- **Idempotent.** Re-running on a correct install is a no-op (exit 0). A
  wrong-target or dangling symlink is repaired; a dirty real dir is refused with
  a clear message.
- **Rollback is git.** The dotfiles dir removal is one reversible commit
  (`git revert` restores every tracked file). No in-repo backup dir is created.

**Dangling-link semantics / the symlink is never git-tracked.** dotfiles commits
a `.gitignore` entry for `skills/goalforge` and the installer recreates the link
per machine, so machines that clone dotfiles WITHOUT cogwright get no dangling
link. The cost: **a dotfiles clone alone no longer carries goalforge** — run
`scripts/install.sh --mode contributor` from a cogwright checkout (or install the
plugin via the marketplace) before goalforge is available on a new machine.

## Catalog

| System | Status | What it is |
|---|---|---|
| **goalforge** | **shipped** (v0.1.0) | Goal-and-verification-driven development chain: capture → spec → decompose → harden → execute → verify. Work packages are *goal objects* — outcome, verification strategy, constraints, boundaries — so "done" is machine-decidable wherever possible. 14 skills. |
| **project-onboard** | in development | One front door that sets up a new *or* existing project with the full agentic surface: git + guardrail hooks, intent interview, memory/doc spine, retrieval indexes — interactive for new projects, plan-only auto mode for existing ones. |
| **agent-dispatch** | planned (next) | Route work to the right model/provider (Anthropic, DeepSeek, Z.AI, Ollama, OpenRouter) with explicit model+effort per dispatch. |
| **agentic-memory** | planned *(working name — final name pending)* | File-backed typed memory vault with session injection, semantic recall, and distillation. |
| **idea system** | planned | Capture → refine → review → promote pipeline for ideas, with provenance carried into promoted features. |
| **command-center** | planned | A host application with an **extension point**: other systems contribute pluggable status panels (goalforge WP status, memory browser, dispatch monitor). Under design. |

**Honest-status legend:** *shipped* = installable now, evals pass; *in development* = spec public, code landing; *planned* = design exists, nothing installable yet. Nothing here is labelled further along than it is.

## Adjacent systems (not plugins)

Not everything in the suite is a Claude Code plugin, and this marketplace does not pretend otherwise:

- **tangram** — a TypeScript/npm monorepo for rendering and publishing structured content (interactive lessons and other typed documents). Currently **under re-specification**; it lives in its own repository and will relate to marketplace systems via a typed content-IR contract (`emits-to`), not as a plugin.
- **command-center** — will ship as its own application (host-with-panels), registered here for discovery; panels from marketplace systems plug into it.

## How systems relate

Systems declare relations in a `relations.yaml` beside their `plugin.json`, with five kinds: `requires` (hard), `recommends` (soft — degrade, never block), `vendors` (copied files, gated by a committed allowlist), `provides-slot` / `fills-slot` (extension points, e.g. command-center panels), and `emits-to` (typed artifacts crossing ecosystems). The marketplace renders the resulting map; installing any single system alone always works.

## Authoring and contributing

Each plugin follows the same shape: `skills/` (one directory per skill, `SKILL.md` + scripts + evals), optional `commands/` and `hooks/`, a `.claude-plugin/plugin.json`, and — where content was copied in from elsewhere — a `.vendored-allowlist.txt` naming every vendored file. CI validates plugin structure on every push. Issues and PRs welcome; keep changes surgical and ship evals with new skills.

## Acknowledgements

These systems build on ideas from public creators and communities — see [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md). Attribution is a first-class deliverable here, captured at the moment of adoption, not retrofitted.

## Maintainer & license

Christoph Unger ([Truncuso](https://github.com/Truncuso)). MIT — see [LICENSE](LICENSE).
