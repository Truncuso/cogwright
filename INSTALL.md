# Installing cogwright plugins

This guide covers installing **goalforge** (and the other plugins in this
marketplace) on your own machine. You do not need to be a cogwright contributor
to follow it.

Two routes:

- **[Plugin route](#plugin-route-recommended)** — the normal path. Claude Code
  manages the clone and updates for you.
- **[Manual route](#manual-route)** — clone the repo and point your Claude Code
  skills directory at it. Use this if you want to modify goalforge, pin a
  specific commit, or run it without the plugin system.

---

## Prerequisites

goalforge is a set of skills plus ~35 shell/Python scripts. The skills load
without anything installed, but the scripts — which the chain calls for
validation, status, frontier computation, and state transitions — need the
following on your `PATH`.

### Required

| Tool | Why | Check |
|---|---|---|
| Claude Code | host | `claude --version` |
| `git` ≥ 2.30 | plan state, transitions, hooks | `git --version` |
| `bash` ≥ 4.0 | associative arrays, `mapfile` | `bash --version` |
| `python3` ≥ 3.9 | validation, plan index, trace tooling | `python3 --version` |
| **PyYAML** | every frontmatter parser | `python3 -c "import yaml; print(yaml.__version__)"` |
| **`jq`** ≥ 1.6 | ~90 script call sites; the single-writer hook silently disables itself without it | `jq --version` |
| `flock` | concurrency lock on status transitions | `command -v flock` |
| `timeout` | dispatch timeouts | `command -v timeout` |
| `realpath` | path resolution | `command -v realpath` |
| `tar`, `diff`, `sed`, `awk` | installer + drift checks | POSIX baseline |

### Optional

| Tool | Improves |
|---|---|
| `ripgrep` (`rg`) | faster migration/rewire sweeps (falls back to `grep`) |
| `gh` | GitHub operations from chain skills |

### Platform notes

**Linux (Debian/Ubuntu)**

```bash
sudo apt-get install -y git jq python3 python3-pip util-linux coreutils
pip3 install --user pyyaml
```

**Fedora/RHEL**

```bash
sudo dnf install -y git jq python3 python3-pip util-linux coreutils
pip3 install --user pyyaml
```

**macOS** — the stock system ships bash 3.2 and lacks `flock`, `timeout`, and
`realpath`. goalforge is **not currently tested on macOS**; install the GNU
toolchain first and expect rough edges:

```bash
brew install bash jq python3 coreutils util-linux
pip3 install pyyaml
# ensure Homebrew bash and gnubin are ahead of /usr/bin on your PATH
```

**Windows** — use WSL2 and follow the Linux instructions. Native Windows is not
supported.

### Verify prerequisites (after install)

Once goalforge is installed, `goalforge-doctor.sh` checks every prerequisite
above — the seven binaries, PyYAML, and the bash major version — plus the
things only a real install can be asked about (layout, reference manifest,
plans-root resolution, git hook). Run it as the first step after installing,
via either route below; see [Verify the install](#verify-the-install).

---

## Plugin route (recommended)

Inside Claude Code:

```
/plugin marketplace add Truncuso/cogwright
/plugin install goalforge@cogwright
```

Restart Claude Code (or start a new session) so skills, commands, and hooks are
picked up.

### What this installs

The marketplace is cloned to `~/.claude/plugins/marketplaces/cogwright/`. After
installing `goalforge` you have:

| Surface | What you get |
|---|---|
| **Skills** | `goalforge` (front door) plus 18 skills: the 15 chain stages (`goalforge-capture`, `-spec`, `-decompose`, `-harden`, `-interview`, `-execute`, `-verify`, `-redecompose`, `-archive`, `-recap`, `-onboard`, `-watchdog`, `-plan-index`, `-arbiter`, `-run`), `goalforge-brief`, plus the co-tenants `wayfind` and `prototype` |
| **Commands** | `/spec`, `/plan`, `/implement`, `/verify`, `/wayfind` |
| **Hooks** | three `PreToolUse` guards + one `PostToolUse` touch — see [Hooks installed](#hooks-installed) |
| **Scripts** | `${CLAUDE_PLUGIN_ROOT}/scripts/goalforge-*.sh` (validation, status, transitions, frontier, rollup, archive) |
| **References** | schemas, state machine, templates, tier map, specialist map |

Nothing is written outside `~/.claude/plugins/`. Your shell profile, dotfiles,
and existing skills are untouched.

### Where your plans live

goalforge writes plan state to a **PLANS_ROOT**, resolved in this order:

1. `$SDD_PLANS_DIR` if set
2. `<git-root>/plans/` — the repo you are working in (normal case)
3. `~/.claude/plans/` — global fallback when you are not in a repo

Feature layout is flat: `plans/<feature>/<wp>/`, with status in frontmatter.
There are no lifecycle folders to maintain.

### Updating

```
/plugin marketplace update cogwright
```

### Installing the other plugins

```
/plugin install interview@cogwright
```

Most plugins install standalone: a companion declared as `recommends` degrades
to a named fallback rather than failing. A `requires` edge is hard — goalforge
hard-requires the `interview` plugin, so installing goalforge installs interview
with it. That dependency is resolved at install time from `interview--v<version>`
git tags on the interview source repository, matched against the range in
goalforge's generated `plugin.json`; the matched tag's `ref`/`sha` override the
marketplace entry's pin. No satisfying tag means the goalforge install fails
outright — a hard edge, not a degrade.

---

## Manual route

Use this if you want to edit goalforge, pin a commit, or run without the plugin
system.

### 1. Clone

```bash
git clone https://github.com/Truncuso/cogwright.git ~/src/cogwright
cd ~/src/cogwright
```

To pin a known-good revision:

```bash
git checkout <commit-or-tag>
```

### 2. Point your skills directory at the package

The authored source of truth is `packages/goalforge/` (the nested v2 package).
`plugins/goalforge/` is a *generated* flattened artifact — do not edit it.

Symlink the package into your Claude Code skills directory:

```bash
SKILLS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
mkdir -p "$SKILLS"
ln -s ~/src/cogwright/packages/goalforge "$SKILLS/goalforge"
ln -s ~/src/cogwright/packages/goalforge/prototype "$SKILLS/prototype"
ln -s ~/src/cogwright/packages/goalforge/wayfind   "$SKILLS/wayfind"
```

`interview/` is intentionally not linked at the top level — it is a private
child invoked by `goalforge-harden`.

**The slash commands are plugin-route only.** `/spec`, `/plan`, `/implement`,
`/verify`, and `/wayfind` are shipped as plugin command files; Claude Code
loads command files from installed plugins, not from a symlinked skills
directory, so on this manual route they are inert. Drive the chain through the
front door instead: invoke the `goalforge` skill (the symlinked parent, which
routes to its children), or read a child's procedure directly from
`<skills-dir>/goalforge/<child>/SKILL.md`. The children are private — they have
no Skill-tool name of their own and calling one by name fails with "Unknown
skill".

### 3. Or use the bundled installer

`scripts/install.sh` automates step 2 with pre/post-verification, drift refusal,
and idempotent re-runs. It defaults to the maintainer's layout, so override the
two env vars for your own machine:

```bash
GF_TARGET_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/goalforge" \
GF_SKIP_REPO_PRECHECK=1 \
  bash scripts/install.sh --mode contributor --dry-run   # preview
```

Drop `--dry-run` to apply.

| Variable | Purpose | Default |
|---|---|---|
| `GF_TARGET_DIR` | where the `goalforge` symlink is created | `$HOME/dotfiles/claude/skills/goalforge` |
| `GF_LINK_TARGET` | what it points at | `<repo>/packages/goalforge` |
| `GF_SKIP_REPO_PRECHECK` | set to `1` to skip the origin-remote and clean-checkout gates | `0` |

`GF_SKIP_REPO_PRECHECK=1` is **required if you cloned a fork** — the default
precheck only accepts an `origin` matching `github.com/Truncuso/cogwright`.

Installer behavior worth knowing:

- **Idempotent.** Re-running on a correct install is a no-op (exit 0).
- **Repairs** a wrong-target or dangling symlink.
- **Refuses to clobber.** An existing real directory with content differing from
  the package is refused rather than overwritten (transients like
  `__pycache__/` and `evals/workspace/` are ignored).
- **Backs up before swapping.** Replaced directories are tarred to a scratch
  path, printed on stderr, and restored automatically if post-verification fails.

Sanity-check the installer itself — it runs 8 cases in a sandbox and never
touches your real `$HOME`:

```bash
bash scripts/install.sh --self-test
```

### 4. Optional: the git pre-commit validator

goalforge ships a pre-commit hook that blocks a commit leaving a touched feature
with a `goalforge-validate --strict` error. Install it into a project repo:

```bash
cd /path/to/your/project
bash ~/src/cogwright/packages/goalforge/scripts/goalforge-install-hooks.sh .
```

The hook finds `goalforge-validate.sh` script-relative to itself — no
environment variable is involved, so nothing in the ambient environment of
whatever tool invokes git can point it elsewhere or silently disable it.
(`GOALFORGE_VALIDATE_SCRIPT` overrides that address, but it exists for the
hook's own regression tests; do not set it in normal use.)

It is chain-safe: an existing `pre-commit` hook is appended to inside
`# >>> sdd-pre-commit >>>` markers, never overwritten, and it exits 0 on every
error path so it can't break your commit flow.

---

## Hooks installed

Installing the goalforge **plugin** activates four hooks automatically. All four
share one **PLANS_ROOT resolution**: `$SDD_PLANS_DIR` if set, else the
`plans/` directory of the edited file's git root, else `~/.claude/plans`. A file
outside every resolved root takes a silent no-op fast path — the hooks are inert
in repositories that do not use goalforge.

**`goalforge-single-writer` (PreToolUse, matcher `Edit|Write|MultiEdit`)** —
blocks direct tool-surface edits to the `status:` and `goal_approved_version:`
frontmatter fields of `overview.md`, `spec.md`, `task-*.md` under a plans root
(and any edit to an already-authored `brief-task-*.md`, which is write-once).
Those fields have a single sanctioned writer, `goalforge-transition.sh`.

- Creating a new plan file with an initial `status:` is **allowed** — the guard
  only protects existing values.
- Without `jq` on `PATH` the hook allows everything through silently. Install
  `jq`.

**`goalforge-transition-guard` (PreToolUse, matcher `Edit`)** — blocks a
`status:` edit whose old → new edge is not in `references/state-machine.md`,
naming the refused edge on stderr.

**`goalforge-open-questions-gate` (PreToolUse, matcher `Edit`)** — blocks a work
package's `→ ready` transition while its `## Open Questions` section still holds
an unresolved bullet.

Both gates match `Edit` **only**: they judge an edit by its `old_string` /
`new_string` snippets, which a `Write` or `MultiEdit` payload does not carry in
that form. That is not a hole — a status change arriving through either of those
tools is blocked outright by `goalforge-single-writer`, whose field guard covers
all three tools. The narrow matchers keep the two gates from advertising a
coverage they cannot deliver.

**`goalforge-frontmatter-touch` (PostToolUse, matcher `Edit|Write|MultiEdit`)** —
bumps `updated:` (and `stage_updated:` if present) to today in an edited plans
`.md`. It reads only the payload's `file_path`, so all three tools are genuinely
in scope. Idempotent; never writes when the values are already current.

- The first edit of a plan file each day rewrites it underneath Claude Code, so
  the session has to re-read that file once before its next edit lands. Later
  edits the same day change nothing and cost nothing.

Every one of them exits 0 on any internal error — a hook never breaks your
session because it itself failed.

To change a status, use the chain (`/verify`, the stage skills) or call
`goalforge-transition.sh` directly — do not hand-edit.

---

## Verify the install

### 1. Skills are discoverable

In Claude Code:

```
explain goalforge
```

The `goalforge` front-door skill should load and list the chain stages. Also try
`/wayfind` — it should be recognised as a command.

### 2. The doctor is green

```bash
GF="$HOME/.claude/plugins/marketplaces/cogwright/plugins/goalforge"   # plugin route
# GF="$HOME/src/cogwright/packages/goalforge"                          # manual route

bash "$GF/scripts/goalforge-doctor.sh"
```

The doctor checks the prerequisites (`git python3 jq flock timeout realpath
tar` plus PyYAML), the bash major version, the layout of the tree it lives in,
the reference manifest, PLANS_ROOT resolution, and the git pre-commit
validator of the project repo you run it from. It exits **0** when everything is green or only warnings fired, and
**1** on a hard failure — a missing prerequisite, a dangling or (on the plugin
route) missing reference manifest, or a tree that does not look like a
goalforge install. Every failure line starts with a stable token
(`MISSING DEP:`, `DANGLING REF:`, `MANIFEST MISSING`, `BAD ROOT:`), so it is
clear which check fired.

Warnings never fail the default run. `MISSING DEP: PyYAML` → `pip3 install
pyyaml`; `WARN: bash<4` is the stock macOS bash (see
[Platform notes](#platform-notes)).

On the **plugin route** you can require a fully clean bill of health:

```bash
bash "$GF/scripts/goalforge-doctor.sh" --strict
```

`--strict` promotes warnings to failures, with two exemptions — warnings no
healthy install can act on:

- **the absent reference manifest on the manual route** (it is emitted
  plugin-side only, so no manual install ever carries one);
- **the git pre-commit hook of the project repo you ran the doctor from** (the
  plugin route installs *by* git clone, so promoting this would be red
  everywhere).

Each exemption means that warning alone never turns `--strict` red; other
warnings still do — `WARN: bash<4`, for instance, is promoted.

To check the doctor itself rather than your install, `--self-test` runs an
offline suite that proves each of its failure checks actually fires.

### 3. End-to-end smoke test on a throwaway repo

```bash
mkdir -p /tmp/gf-smoke && cd /tmp/gf-smoke && git init -q
mkdir -p plans/demo-feature/wp-01-demo
cat > plans/demo-feature/wp-01-demo/overview.md <<'EOF'
---
name: wp-01-demo
title: "Smoke test work package"
status: draft
schema_version: 5
plan: demo-feature
task_type: code
---
## Goal
Confirm goalforge validation runs.
EOF

bash "$GF/scripts/goalforge-validate.sh" plans
bash "$GF/scripts/goalforge-status.sh"   plans
```

Expected: both commands complete and report on `demo-feature`. Validation
warnings about missing fields are fine — a crash or an import error is not.

Clean up: `rm -rf /tmp/gf-smoke`.

### 4. The single-writer hook is live (plugin route)

Ask Claude to edit the `status:` line of
`/tmp/gf-smoke/plans/demo-feature/wp-01-demo/overview.md` with the Edit tool. The
attempt should be blocked with a single-writer message. If it succeeds, check
that `jq` is installed and that the plugin's hooks were loaded (restart Claude
Code).

---

## Uninstall

### Plugin route

```
/plugin uninstall goalforge@cogwright
/plugin marketplace remove cogwright
```

This removes the skills, the slash commands, and the four event hooks. Your
`plans/` directories are **not** touched — they are your content.

### Manual route

```bash
SKILLS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
rm -f "$SKILLS/goalforge" "$SKILLS/prototype" "$SKILLS/wayfind"   # symlinks only
rm -rf ~/src/cogwright                                            # the clone
```

`rm -f` on a symlink removes the link, never the target. Confirm with
`ls -l "$SKILLS"` before deleting anything that is not a symlink.

### Remove the git pre-commit hook

The installer appends a marked block. Delete the lines between and including:

```
# >>> sdd-pre-commit >>>
# <<< sdd-pre-commit <<<
```

in `<your-repo>/.git/hooks/pre-commit`. If that block is the entire file, delete
the file.

### Leftovers to check

```bash
ls ~/.claude/plugins/marketplaces/cogwright   # should not exist after removal
grep -rn 'sdd-pre-commit' .git/hooks/ 2>/dev/null
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ERROR: PyYAML not available` | missing PyYAML | `pip3 install pyyaml` (match the `python3` on your PATH) |
| Script exits with no output / `jq: command not found` | missing `jq` | install `jq` |
| `flock: command not found` (macOS) | util-linux missing | `brew install util-linux` and put it ahead of `/usr/bin` |
| `declare -A: invalid option` (macOS) | bash 3.2 | `brew install bash`, put it first on `PATH` |
| `refusing to clobber: real dir has uncommitted tracked drift` | your skills dir has a real `goalforge/` directory that differs from the package | commit/revert/move it, then re-run |
| `unexpected origin remote` | you cloned a fork | `GF_SKIP_REPO_PRECHECK=1` |
| `link target does not resolve to a goalforge package` | wrong `GF_LINK_TARGET`, or clone incomplete | point at `<repo>/packages/goalforge` |
| `/spec`, `/plan`, `/implement`, `/verify` are unknown commands | you are on the manual skills-dir route, where command files are inert | install via the plugin route, or invoke the `goalforge` front door |

---

## Known limitations (current release)

Stated plainly so you are not debugging a documented gap:

1. **The entry commands are plugin-route only.** `/spec`, `/plan`,
   `/implement`, `/verify`, and `/wayfind` ship with the plugin, but Claude
   Code loads command files from installed plugins only — on the manual
   skills-dir route they are inert. There, drive the chain through the front
   door — invoke the `goalforge` skill, which routes to its children — or read
   the stage procedure directly from `<skills-dir>/goalforge/<child>/SKILL.md`.
   The children are private: they have no Skill-tool name and calling one by
   name fails with "Unknown skill".
2. **A few references reach into skills that are not part of this marketplace**
   (`idea`, `autopilot`). The couplings are real — several stages (capture,
   spec, harden, execute, run, wayfind) name those skills — but **no
   `recommends:` row in
   `${CLAUDE_PLUGIN_ROOT}/relations.yaml` declares them**, so unlike the
   soft-declared companions (`research-analyst`, `adr-write`) they carry no
   named fallback. Those passages degrade *undeclared*: the section
   simply has nothing to route to. Nothing blocks — the rest of the chain is
   unaffected — but do not expect a documented degradation path for them.
   Declaring the two rows is an open item — file or follow it on the issue
   tracker linked at the end of this file.
3. **Child skills are individually discoverable — suppression is soft.** In the
   package they are private children of the `goalforge` front door; flattened
   into a plugin they become top-level skills. Every child description
   therefore carries the fixed prefix
   `goalforge-internal — use entry commands; do not auto-trigger`, which routes
   the model back to the entry commands and the `goalforge` front door.
   Residual risk: a description is a *hint*, not an enforcement point — nothing
   in Claude Code blocks a child from being selected, so a strongly matching
   request may still trigger one directly. Drive the chain through `/spec`,
   `/plan`, `/implement`, `/verify` (or the `goalforge` skill) and treat a
   direct child trigger as a routing miss, not a supported entry point.
4. **`evals/` is not shipped.** The plugin artifact excludes the eval harness, so
   there is no bundled acceptance test. Use the smoke test above, or clone the
   repo and run evals from `packages/goalforge/evals/`.
5. **macOS is untested.** See the platform notes.

Bug reports and PRs welcome: <https://github.com/Truncuso/cogwright/issues>.
See [CONTRIBUTING.md](CONTRIBUTING.md) — note that `packages/` is the authored
tree and `plugins/` is generated by `scripts/goalforge-generate.sh`; edit
`packages/`, then regenerate.
````

