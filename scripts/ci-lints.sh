#!/usr/bin/env bash
# ci-lints.sh — repo lint dispatcher (CI gate and local pre-flight).
#
# Cross-WP contract — consumed by later work packages that register their own
# sections here; do not change these semantics without updating them:
#
#   --only <section>   repeatable; runs the AND-set of the named sections
#   (no arguments)     runs every registered section
#   unknown section    exit 2, with the valid section list on stderr
#   per section        prints `section <name>: PASS|FAIL (<n> files scanned)`
#   any section fails  exit 1
#   zero sections run  exit 2 — fail-closed, never a silent no-op
#
# Registering a section: add its name to SECTIONS and define `lint_<name>`
# with dashes replaced by underscores. The function prints its violations to
# stderr, sets SCANNED to the number of files it examined, and returns 0/1.
#
# Usage:
#   ci-lints.sh [--only <section>]...
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Registry of runnable sections, in run order.
SECTIONS=(author-paths)

# Set by each section function; read by the dispatcher for the report line.
SCANNED=0

usage() {
  printf 'usage: ci-lints.sh [--only <section>]...\nsections: %s\n' "${SECTIONS[*]}"
}

die() {
  local code="$1"; shift
  printf 'ci-lints: %s\n' "$*" >&2
  printf 'valid sections: %s\n' "${SECTIONS[*]}" >&2
  exit "$code"
}

is_section() {
  local candidate="$1" s
  for s in "${SECTIONS[@]}"; do
    [ "$s" = "$candidate" ] && return 0
  done
  return 1
}

# Repo-relative file list for the given paths (tracked files only in a repo).
list_files() {
  if git rev-parse --git-dir >/dev/null 2>&1; then
    git ls-files -z -- "$@"
  else
    find "$@" -type f -print0 2>/dev/null
  fi
}

# ---------------------------------------------------------------------------
# Carve-outs — pre-declared, exact path + literal line substring.
# Never a blanket regex weakening: an entry suppresses one known occurrence.
# ---------------------------------------------------------------------------
CARVEOUT_FILE="scripts/lint-baselines/author-paths-carveouts.txt"
CARVEOUTS=()

load_carveouts() {
  CARVEOUTS=()
  [ -f "$CARVEOUT_FILE" ] || return 0
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    CARVEOUTS+=("$line")
  done < "$CARVEOUT_FILE"
}

carved_out() {
  local file="$1" content="$2" entry cpath cpat
  for entry in ${CARVEOUTS+"${CARVEOUTS[@]}"}; do
    cpath="${entry%%::*}"
    cpat="${entry#*::}"
    [ "$file" = "$cpath" ] || continue
    case "$content" in *"$cpat"*) return 0 ;; esac
  done
  return 1
}

# ---------------------------------------------------------------------------
# Section: author-paths
# ---------------------------------------------------------------------------

# Author-machine install paths in every real form, plus the dotfiles prefix.
AUTHOR_PATH_RE='(~|\$HOME|\$\{HOME\})/\.claude/skills/goalforge|\.\./skills/goalforge|\$HOME/dotfiles'
# The upstream slug hardcoded into shipped plugin text (installer copy is fine).
UPSTREAM_SLUG_RE='Truncuso/cogwright'

VIOLATIONS=0

# scan_pattern_set <regex> <file>... — report every non-carved-out match.
scan_pattern_set() {
  local re="$1"; shift
  [ "$#" -gt 0 ] || return 0
  local hit file lineno content
  while IFS= read -r hit; do
    file="${hit%%:*}"; hit="${hit#*:}"
    lineno="${hit%%:*}"; content="${hit#*:}"
    carved_out "$file" "$content" && continue
    printf '  %s:%s: %s\n' "$file" "$lineno" "$content" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  done < <(grep -IHEn -- "$re" "$@" 2>/dev/null)
}

lint_author_paths() {
  load_carveouts
  VIOLATIONS=0

  local -a wide=() plugin_only=()
  local f
  while IFS= read -r -d '' f; do wide+=("$f"); done < <(list_files plugins scripts/install.sh)
  while IFS= read -r -d '' f; do plugin_only+=("$f"); done < <(list_files plugins)

  SCANNED=${#wide[@]}

  scan_pattern_set "$AUTHOR_PATH_RE" ${wide+"${wide[@]}"}
  scan_pattern_set "$UPSTREAM_SLUG_RE" ${plugin_only+"${plugin_only[@]}"}

  [ "$VIOLATIONS" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------
main() {
  local -a want=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --only)
        [ "$#" -ge 2 ] || die 2 "--only requires a section name"
        want+=("$2"); shift 2 ;;
      --only=*) want+=("${1#--only=}"); shift ;;
      -h|--help) usage; return 0 ;;
      *) die 2 "unknown argument: $1" ;;
    esac
  done

  [ "${#want[@]}" -gt 0 ] || want=("${SECTIONS[@]}")

  # --only is a SET: validate each name, drop repeats, keep registry order.
  local s
  for s in "${want[@]}"; do
    is_section "$s" || die 2 "unknown section: $s"
  done
  local -a run=()
  for s in "${SECTIONS[@]}"; do
    printf '%s\n' "${want[@]}" | grep -qxF -- "$s" && run+=("$s")
  done

  local ran=0 failed=0 status
  for s in "${run[@]}"; do
    SCANNED=0
    "lint_${s//-/_}"
    status=$?
    ran=$(( ran + 1 ))
    if [ "$status" -eq 0 ]; then
      printf 'section %s: PASS (%d files scanned)\n' "$s" "$SCANNED"
    else
      printf 'section %s: FAIL (%d files scanned)\n' "$s" "$SCANNED"
      failed=1
    fi
  done

  # Fail-closed: a run that matched no section is an error, not success.
  [ "$ran" -gt 0 ] || die 2 "no sections matched — refusing to report success"
  return "$failed"
}

main "$@"
