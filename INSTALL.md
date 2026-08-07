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

### Verify prerequisites in one shot

```bash
for c in git bash python3 jq flock timeout realpath tar; do
  command -v "$c" >/dev/null && echo "ok   $c" || echo "MISS $c"
done
python3 -c "import yaml" 2>/dev/null && echo "ok   PyYAML" || echo "MISS PyYAML"
bash -c '((BASH_VERSINFO[0]>=4))' && echo "ok   bash>=4" || echo "MISS bash>=4"
```

Every line should read `ok`.

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
| **Commands** | `/wayfind` |
| **Hooks** | one `PreToolUse` guard — see [Hooks installed](#hooks-installed) |
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

Each plugin is self-contained — installing one never requires another. Declared
companions degrade gracefully (a missing `interview-loop` falls back to a
one-question-at-a-time loop in the main session, not an error).

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
GOALFORGE_VALIDATE_SCRIPT="$HOME/src/cogwright/packages/goalforge/scripts/goalforge-validate.sh" \
  bash ~/src/cogwright/packages/goalforge/scripts/goalforge-install-hooks.sh .
```

It is chain-safe: an existing `pre-commit` hook is appended to inside
`# >>> sdd-pre-commit >>>` markers, never overwritten, and it exits 0 on every
error path so it can't break your commit flow.

---

## Hooks installed

Installing the goalforge **plugin** activates one hook automatically:

**`goalforge-single-writer` (PreToolUse, matcher `Edit|Write|MultiEdit`)** —
blocks direct tool-surface edits to the `status:` and `goal_approved_version:`
frontmatter fields in `<git-root>/plans/**` and `~/.claude/plans/**` (files named
`overview.md`, `spec.md`, `task-*.md`). Those fields have a single sanctioned
writer, `goalforge-transition.sh`.

- Creating a new plan file with an initial `status:` is **allowed** — the guard
  only protects existing values.
- Files outside a `plans/` root are never touched.
- Without `jq` on `PATH` the hook allows everything through silently. Install
  `jq`.

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

### 2. Scripts run

```bash
GF="$HOME/.claude/plugins/marketplaces/cogwright/plugins/goalforge"   # plugin route
# GF="$HOME/src/cogwright/packages/goalforge"                          # manual route

bash "$GF/scripts/goalforge-validate.sh" --help
```

Expected: usage output. If you see
`ERROR: PyYAML not available` → `pip3 install pyyaml`.

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

This removes the skills, the `/wayfind` command, and the PreToolUse hook. Your
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
| A skill references `~/.claude/skills/goalforge/...` and the file is missing | known path-leak bug, see below | read the same relative path under `${CLAUDE_PLUGIN_ROOT}` instead |
| `/spec`, `/plan`, `/implement`, `/verify` are unknown commands | not shipped yet, see below | invoke the skills by name |

---

## Known limitations (current release)

Stated plainly so you are not debugging a documented gap:

1. **Only `/wayfind` ships as a command.** The `/spec`, `/plan`, `/implement`,
   and `/verify` entry points described in the README and ARCHITECTURE docs are
   not yet part of the plugin. Until they are, drive the chain by invoking the
   skills directly by name — `goalforge-capture`, `goalforge-spec`,
   `goalforge-decompose`, `goalforge-harden`, `goalforge-execute`,
   `goalforge-verify` — or ask the `goalforge-run` orchestrator to drive it.
2. **Some skill text points at `~/.claude/skills/goalforge/...`.** Those are
   leftover maintainer-machine paths. The same file exists under
   `${CLAUDE_PLUGIN_ROOT}/` — for a child skill's own assets, under
   `${CLAUDE_PLUGIN_ROOT}/skills/<child>/`. Scripts referenced this way are all
   present in `${CLAUDE_PLUGIN_ROOT}/scripts/`.
3. **A few references reach into skills that are not part of this marketplace**
   (`idea`, `autopilot`). Those sections degrade — treat them as optional.
4. **Child skills are individually discoverable.** In the package they are
   private children of the `goalforge` front door; flattened into a plugin they
   become top-level skills and may trigger on their own.
5. **`evals/` is not shipped.** The plugin artifact excludes the eval harness, so
   there is no bundled acceptance test. Use the smoke test above, or clone the
   repo and run evals from `packages/goalforge/evals/`.
6. **macOS is untested.** See the platform notes.
7. **Version strings disagree** — `plugin.json` carries a commit SHA, the README
   catalog says v0.1.0, and the skill frontmatter says 3.0.0. The commit SHA in
   `plugin.json` is the reliable identifier of what you installed.

Bug reports and PRs welcome: <https://github.com/Truncuso/cogwright/issues>.
See [CONTRIBUTING.md](CONTRIBUTING.md) — note that `packages/` is the authored
tree and `plugins/` is generated by `scripts/goalforge-generate.sh`; edit
`packages/`, then regenerate.
````

