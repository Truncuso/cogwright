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
#   section scans 0    exit 2 — fail-closed, unless the section opted in via
#                      ALLOW_EMPTY_SECTIONS (empty by design)
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
SECTIONS=(author-paths manifest package-refs)

# Opt-out list for the per-section zero-scan gate: sections named here may
# legitimately scan zero files and still report PASS. EMPTY BY DESIGN — a lint
# that silently stops matching any file is the failure mode this gate exists to
# catch, so a new section must opt in here deliberately, with a reason.
ALLOW_EMPTY_SECTIONS=()

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

# in_list <needle> <item>... — membership test. No pipeline, so no SIGPIPE.
in_list() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

is_section() { in_list "$1" "${SECTIONS[@]}"; }

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
    line="${line%$'\r'}"                        # CRLF-authored file
    line="${line%"${line##*[![:space:]]}"}"     # trailing whitespace
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
  # -Z terminates the file name with a NUL instead of ':', so a colon inside a
  # path can never be mistaken for the field separator: read the name up to the
  # NUL, then the `<lineno>:<content>` remainder up to the newline.
  local file rest lineno content
  while IFS= read -r -d '' file && IFS= read -r rest; do
    lineno="${rest%%:*}"; content="${rest#*:}"
    carved_out "$file" "$content" && continue
    printf '  %s:%s: %s\n' "$file" "$lineno" "$content" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  done < <(grep -IHEnZ -- "$re" "$@" 2>/dev/null)
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
# Section: manifest
#
# The generator-emitted reference manifest is the single authority for "which
# path does a shipped .md name" — this section never re-derives the token
# grammar, it only checks that every ref the manifest carries exists in the
# plugin tree. The wp-07 doctor reads the same file at install time.
# ---------------------------------------------------------------------------
MANIFEST_FILE="plugins/goalforge/references/reference-manifest.json"
MANIFEST_ROOT="plugins/goalforge"
# Sorted `<from>::<path>` set of KNOWN-dangling refs whose fix is owned by a
# named later WP. Removal-only: a dead entry fails just as loudly as a new
# dangling ref, so the ratchet can never be swapped for a fresh violation.
MANIFEST_BASELINE="scripts/lint-baselines/reference-manifest.baseline"
# Floor from the wp-02 goal block: a manifest that suddenly carries a handful of
# refs proves nothing about the tree, so an under-populated manifest is a
# failure in its own right. No ALLOW_EMPTY opt-in for this section.
MANIFEST_FLOOR=100

# Dangling `<from>::<path>` refs found by the section currently running.
DANGLING=()

# check_ratchet <baseline-file> — compare DANGLING against a removal-only
# baseline. An unbaselined dangling ref is a violation, and so is an entry whose
# ref resolves again: the pair makes the baseline a ratchet that can only
# shrink, never a slot to swap a fresh violation into.
check_ratchet() {
  local bf="$1" line ref
  local -a baseline=()
  if [ -f "$bf" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      case "$line" in ''|'#'*) continue ;; esac
      baseline+=("$line")
    done < "$bf"
  fi

  for ref in ${DANGLING+"${DANGLING[@]}"}; do
    in_list "$ref" ${baseline+"${baseline[@]}"} && continue
    printf '  dangling ref: %s -> %s\n' "${ref%%::*}" "${ref#*::}" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  done

  for ref in ${baseline+"${baseline[@]}"}; do
    in_list "$ref" ${DANGLING+"${DANGLING[@]}"} && continue
    printf '  dead entry in %s (ref resolves now, delete it): %s\n' "$bf" "$ref" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  done
}

lint_manifest() {
  VIOLATIONS=0
  DANGLING=()

  if [ ! -s "$MANIFEST_FILE" ]; then
    printf '  %s: missing or empty — run scripts/goalforge-generate.sh\n' \
      "$MANIFEST_FILE" >&2
    SCANNED=0
    return 1
  fi

  # `<from>::<path>` per ref, in manifest (sorted) order.
  local -a refs=()
  local line
  while IFS= read -r line; do refs+=("$line"); done < <(
    python3 -c 'import json,sys
m=json.load(open(sys.argv[1]))
assert m["schema"]==1, "unsupported manifest schema: %r" % (m.get("schema"),)
for r in m["refs"]:
    print("%s::%s" % (r["from"], r["path"]))' "$MANIFEST_FILE"
  ) || { printf '  %s: unreadable\n' "$MANIFEST_FILE" >&2; SCANNED=0; return 1; }

  SCANNED=${#refs[@]}

  if [ "$SCANNED" -lt "$MANIFEST_FLOOR" ]; then
    printf '  %s: %d refs, below the floor of %d — the extractor stopped matching\n' \
      "$MANIFEST_FILE" "$SCANNED" "$MANIFEST_FLOOR" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  fi

  local ref
  for ref in ${refs+"${refs[@]}"}; do
    [ -e "$MANIFEST_ROOT/${ref#*::}" ] || DANGLING+=("$ref")
  done

  check_ratchet "$MANIFEST_BASELINE"

  [ "$VIOLATIONS" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Section: package-refs
#
# CI-only counterpart to `manifest`: the same token grammar
# (scripts/goalforge_refs.py — one definition, two anchors) over the AUTHORED
# package tree, which has no plugin-root name and therefore never ships a
# manifest of its own. Catches a dangling ref at the source file, before the
# generator carries it into the artifact.
# ---------------------------------------------------------------------------
REF_IGNORE_FILE="scripts/lint-baselines/reference-ignore.txt"
PACKAGE_REFS_BASELINE="scripts/lint-baselines/package-refs-baseline.txt"

lint_package_refs() {
  VIOLATIONS=0
  DANGLING=()

  # GF_PACKAGE_ROOT: scan root, so a negative-case check can point the section
  # at a scratch copy instead of mutating the real tree.
  local root="${GF_PACKAGE_ROOT:-packages/goalforge}"
  if [ ! -d "$root" ]; then
    printf '  %s: not a directory\n' "$root" >&2
    SCANNED=0
    return 1
  fi

  local -a scan=()
  local line
  while IFS= read -r line; do scan+=("$line"); done < <(
    PYTHONDONTWRITEBYTECODE=1 python3 scripts/goalforge_refs.py scan \
      --root "$root" --ignore "$REF_IGNORE_FILE" --package
  )

  SCANNED=${#scan[@]}

  # `<0|1>\t<from>::<path>`, 1 = the path exists in the scanned tree.
  for line in ${scan+"${scan[@]}"}; do
    case "$line" in 0*) DANGLING+=("${line#*$'\t'}") ;; esac
  done

  check_ratchet "$PACKAGE_REFS_BASELINE"

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
    in_list "$s" "${want[@]}" && run+=("$s")
  done

  local ran=0 failed=0 status
  for s in "${run[@]}"; do
    SCANNED=0
    "lint_${s//-/_}"
    status=$?
    ran=$(( ran + 1 ))
    # Fail-closed per section: a lint that matched no file proves nothing.
    if [ "$SCANNED" -eq 0 ] \
       && ! in_list "$s" ${ALLOW_EMPTY_SECTIONS+"${ALLOW_EMPTY_SECTIONS[@]}"}; then
      die 2 "section $s scanned 0 files — refusing to report PASS"
    fi
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
