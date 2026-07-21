#!/usr/bin/env bash
# discovery-probe.sh — symlink-following skill-enumeration probe.
#
# Emulates a skills-directory walker that enumerates each child of the skills
# root and, for every child that is a directory OR a symlink pointing at a
# directory, treats it as an enumerable skill when it carries a SKILL.md.
# It then asserts that `goalforge/SKILL.md` is REGISTERED (enumerated), not
# merely readable by path.
#
# This is the deterministic half of the wp-18 discovery gate. It exists to
# catch the specific failure mode where a naive walker filters children with an
# lstat-based isDirectory() test (e.g. Node fs.Dirent.isDirectory(), which does
# NOT follow symlinks) and therefore SKIPS a symlinked skill directory — the
# skill would be path-reachable but never registered.
#
# Skills root resolution (first match wins):
#   1. $1                       (explicit arg — used by --self-test fixtures)
#   2. $GOALFORGE_SKILLS_ROOT   (env override)
#   3. $HOME/.claude/skills     (default)
#
# Exit 0 = goalforge enumerated (registered).  Exit 1 = not enumerated.
set -euo pipefail

SKILL_NAME="goalforge"
ROOT="${1:-${GOALFORGE_SKILLS_ROOT:-$HOME/.claude/skills}}"

log() { printf '%s\n' "$*" >&2; }

if [[ ! -d "$ROOT" ]]; then
  log "discovery-probe: skills root does not exist or is not a directory: $ROOT"
  exit 1
fi

# Enumerate children the way a symlink-following walker must: iterate the
# directory entries, and for each entry decide "is this an enumerable skill
# directory?" using a test that FOLLOWS symlinks (`test -d` on the entry path
# dereferences a symlink, unlike lstat/isDirectory()).
registered=()
shopt -s nullglob
for entry in "$ROOT"/*; do
  name="$(basename "$entry")"
  # `-d` follows symlinks: true for a real dir AND a symlink→dir.
  # A lstat-based isDirectory() would return false for the symlink and skip it —
  # that is exactly the bug this probe guards against.
  if [[ -d "$entry" && -f "$entry/SKILL.md" ]]; then
    registered+=("$name")
  fi
done
shopt -u nullglob

for name in "${registered[@]:-}"; do
  if [[ "$name" == "$SKILL_NAME" ]]; then
    # Confirm the SKILL.md actually resolves THROUGH the entry (link or dir).
    if [[ -f "$ROOT/$SKILL_NAME/SKILL.md" ]]; then
      log "discovery-probe: OK — '$SKILL_NAME/SKILL.md' enumerated in $ROOT (symlink-following)"
      exit 0
    fi
  fi
done

log "discovery-probe: FAIL — '$SKILL_NAME' not enumerated in $ROOT"
log "discovery-probe: enumerated skills: ${registered[*]:-<none>}"
exit 1
