#!/usr/bin/env bash
# interview-contract-sync.sh — MACHINE-LOCAL fixture-vs-installed check.
#
# Asserts that scripts/lint-baselines/interview-contract-enum.txt (the vendored
# pin that ci-lints.sh check C1 reads) still equals the frozen
# `HANDOFF_SUGGESTION` enum of the INSTALLED interview plugin on THIS machine.
#
# THIS SCRIPT IS NOT A CI STEP AND MUST NEVER BECOME ONE (D8-wp13). Do not add
# it to scripts/ci-lints.sh, and do not add it to .github/workflows/. The reason
# is a split between two different claims:
#
#   "the frozen enum is the five members we think it is"
#       -> a property of REPO BYTES. CI-enforceable. Lives in ci-lints.sh, check
#          C1 of the `interview-contract` section, over the vendored fixture.
#
#   "the INSTALLED interview plugin still matches that fixture"
#       -> a property of a MACHINE. NOT CI-enforceable: the Validate Plugins
#          runner (.github/workflows/validate-plugins.yml, ubuntu-latest) has no
#          Claude install and therefore no ~/.claude/plugins/cache. Wiring this
#          read into the gate has only two branches and both are wrong — a hard
#          failure turns the workflow red on every push and PR forever, and a
#          WARN-skip is taken on 100% of CI runs, making the check
#          green-by-construction. Hence: this script, run by a human on a
#          machine that actually has the plugin.
#
# Precedent for the shape: scripts/discovery-probe.sh — repo-tracked, reads
# $HOME, carries an env override for its root, invoked by no workflow step.
#
# Overrides:
#   INTERVIEW_SIGNALS_CONTRACT  path to a signals-contract.md (skips the glob)
#   IC_ENUM_FIXTURE             path to the vendored fixture
#
# Exit 0 = fixture equals the installed contract.
# Exit 1 = drift, or the interview plugin is not installed on this machine.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FIXTURE="${IC_ENUM_FIXTURE:-$REPO_ROOT/scripts/lint-baselines/interview-contract-enum.txt}"

# Version-GLOBBED, never a pinned version directory: pinning one would make the
# check stop seeing the contract the day the plugin is upgraded, which is exactly
# when it needs to fire. Convention borrowed from the engine-drift guard in
# packages/goalforge/evals/run.sh.
contract="${INTERVIEW_SIGNALS_CONTRACT:-$(ls "$HOME"/.claude/plugins/cache/cogwright/interview/*/references/signals-contract.md 2>/dev/null | LC_ALL=C sort -V | tail -1)}"

if [ -z "$contract" ] || [ ! -f "$contract" ]; then
  printf 'interview-contract-sync: the interview plugin is not installed on this machine.\n' >&2
  printf '  looked for: %s/.claude/plugins/cache/cogwright/interview/*/references/signals-contract.md\n' "$HOME" >&2
  printf '  This script is FOR machines that have it. Its absence on a CI runner is\n' >&2
  printf '  by design and is not a failure there — the runner never runs this script.\n' >&2
  exit 1
fi

if [ ! -f "$FIXTURE" ]; then
  printf 'interview-contract-sync: vendored enum fixture missing: %s\n' "$FIXTURE" >&2
  exit 1
fi

# Same extraction the ci-lints C1 check uses: strip `#` comments and blank
# lines, sort under LC_ALL=C, join with single spaces.
fixture_set="$(grep -v '^[[:space:]]*#' "$FIXTURE" | grep -v '^[[:space:]]*$' \
               | LC_ALL=C sort | tr '\n' ' ')"
fixture_set="${fixture_set% }"

# Installed set: column 1 of the `## Frozen ... enum` table, backticks stripped.
installed_set="$(awk '
  /^## Frozen .*enum/ {f=1; next}
  f && /^## / {f=0}
  f && /^\| `/ {
    line=$0
    sub(/^\|[[:space:]]*`/, "", line)
    sub(/`.*$/, "", line)
    if (line != "") print line
  }
' "$contract" | LC_ALL=C sort | tr '\n' ' ')"
installed_set="${installed_set% }"

if [ -z "$installed_set" ]; then
  printf 'interview-contract-sync: could not extract the frozen enum table from %s\n' "$contract" >&2
  printf '  The upstream document shape changed — re-read it before touching the fixture.\n' >&2
  exit 1
fi

if [ "$fixture_set" != "$installed_set" ]; then
  printf 'interview-contract-sync: DRIFT between the vendored fixture and the installed contract\n' >&2
  printf '  contract:  %s\n' "$contract" >&2
  printf '  fixture:   %s\n' "$FIXTURE" >&2
  printf '  installed: %s\n' "$installed_set" >&2
  printf '  vendored:  %s\n' "$fixture_set" >&2
  printf '  The fixture is a VENDORED PIN: update it in a deliberate, reviewed edit\n' >&2
  printf '  that adopts the upstream change, together with IC_ENUM_EXPECTED in\n' >&2
  printf '  scripts/ci-lints.sh. Never auto-sync it — a pin that rewrites itself to\n' >&2
  printf '  match its input can never go red.\n' >&2
  exit 1
fi

printf 'interview-contract-sync: OK — vendored fixture equals the installed contract\n'
printf '  contract: %s\n' "$contract"
printf '  enum:     %s\n' "$installed_set"
