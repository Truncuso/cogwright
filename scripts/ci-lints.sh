#!/usr/bin/env bash
# ci-lints.sh — repo lint dispatcher (CI gate and local pre-flight).
#
# Cross-WP contract — consumed by later work packages that register their own
# sections here; do not change these semantics without updating them:
#
#   --only <section>   repeatable; runs the AND-set of the named sections
#   (no arguments)     runs every registered section
#   unknown section    exit 2, with the valid section list on stderr
#   per section        prints `section <name>: PASS|FAIL (<n> items scanned)`
#   any section fails  exit 1
#   zero sections run  exit 2 — fail-closed, never a silent no-op
#   section scans 0    exit 2 — fail-closed, unless the section opted in via
#                      ALLOW_EMPTY_SECTIONS (empty by design)
#
# Registering a section: add its name to SECTIONS and define `lint_<name>`
# with dashes replaced by underscores. The function prints its violations to
# stderr, sets SCANNED to the number of items it examined (files, or refs for a
# section whose unit is a reference), and returns 0/1.
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
#
# AUTHORITY IS CONDITIONAL: this section trusts the manifest to describe the
# CURRENT tree, which only holds while `scripts/goalforge-generate.sh --check`
# runs in the same CI job (the spec mandates the pairing). Without that drift
# gate a stale manifest passes here while the shipped .md files say something
# else entirely.
# ---------------------------------------------------------------------------
# GF_MANIFEST_FILE / GF_MANIFEST_ROOT: test seams, so a negative-case check can
# point the section at a scratch manifest instead of mutating the real one.
MANIFEST_FILE="${GF_MANIFEST_FILE:-plugins/goalforge/references/reference-manifest.json}"
MANIFEST_ROOT="${GF_MANIFEST_ROOT:-plugins/goalforge}"
# Sorted `<from>::<path>` set of KNOWN-dangling refs whose fix is owned by a
# named later WP. Removal-only: an entry whose ref resolves again fails just as
# loudly as a new dangling ref, so a stale entry is never quietly carried — and
# swapping an entry for a fresh violation is a visible edit to this file, which
# review is the contract that governs (no git-history check enforces it).
MANIFEST_BASELINE="scripts/lint-baselines/reference-manifest.baseline"
# Floor from the wp-02 goal block: a manifest that suddenly carries a handful of
# refs proves nothing about the tree, so an under-populated manifest is a
# failure in its own right. No ALLOW_EMPTY opt-in for this section.
MANIFEST_FLOOR=80

# Dangling `<from>::<path>` refs found by the section currently running.
DANGLING=()

# Deliberate exceptions to the ref grammar, shared by both ref sections.
REF_IGNORE_FILE="scripts/lint-baselines/reference-ignore.txt"

# check_ratchet <baseline-file> — compare DANGLING against a removal-only
# baseline. An unbaselined dangling ref is a violation, and so is an entry whose
# ref resolves again: the pair keeps the baseline honest — it can only shrink on
# its own, and every widening edit shows up in the diff for review.
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

# check_dead_ignores <root> [extractor-flag...] — the ignore list gets the same
# dead-entry leg as the baselines: an entry that suppresses NOTHING in the scan
# names an address that no longer occurs, and is a violation. The plugin-side
# call passes no --skip-top, so an entry firing only inside a PRESERVE'd file
# still counts as live (the manifest emitter skips those files; counting them
# here trades a weaker check for zero false failures).
check_dead_ignores() {
  local root="$1"; shift
  local out line
  if ! out=$(PYTHONDONTWRITEBYTECODE=1 python3 scripts/goalforge_refs.py ignores \
               --root "$root" --ignore "$REF_IGNORE_FILE" "$@" 2>&1); then
    printf '  %s: ignore-list scan failed\n%s\n' "$REF_IGNORE_FILE" "$out" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
    return 0
  fi
  [ -n "$out" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '  dead entry in %s (suppresses nothing, delete it): %s\n' \
      "$REF_IGNORE_FILE" "$line" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  done <<<"$out"
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

  # `<from>::<path>` per ref, in manifest (sorted) order. The extractor's exit
  # status is captured for real: an unreadable or schema-wrong manifest must
  # fail the section, never leave it reporting on an empty ref list.
  local out
  if ! out=$(python3 -c 'import json,sys
m=json.load(open(sys.argv[1]))
assert m["schema"]==1, "unsupported manifest schema: %r" % (m.get("schema"),)
for r in m["refs"]:
    print("%s::%s" % (r["from"], r["path"]))' "$MANIFEST_FILE" 2>&1); then
    printf '  %s: unreadable\n%s\n' "$MANIFEST_FILE" "$out" >&2
    SCANNED=0
    return 1
  fi

  local -a refs=()
  local line
  if [ -n "$out" ]; then
    while IFS= read -r line; do refs+=("$line"); done <<<"$out"
  fi

  SCANNED=${#refs[@]}

  if [ "$SCANNED" -lt "$MANIFEST_FLOOR" ]; then
    printf '  %s: %d refs, below the floor of %d — the extractor stopped matching\n' \
      "$MANIFEST_FILE" "$SCANNED" "$MANIFEST_FLOOR" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  fi

  # Consumer-side validation: the manifest is data this section did not
  # produce, so a `path` is checked for shape before it is dereferenced. It must
  # be plugin-root-RELATIVE and stay inside the root (no absolute path, no `..`
  # segment), and it must name a FILE — a directory target is a ref the grammar
  # was supposed to exclude, not a resolving ref.
  local ref path
  for ref in ${refs+"${refs[@]}"}; do
    path="${ref#*::}"
    case "$path" in
      /*|..|../*|*/..|*/../*)
        printf '  %s: path escapes the plugin root: %s -> %s\n' \
          "$MANIFEST_FILE" "${ref%%::*}" "$path" >&2
        VIOLATIONS=$(( VIOLATIONS + 1 ))
        continue ;;
    esac
    [ -f "$MANIFEST_ROOT/$path" ] || DANGLING+=("$ref")
  done

  check_ratchet "$MANIFEST_BASELINE"
  check_dead_ignores "$MANIFEST_ROOT"

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
PACKAGE_REFS_BASELINE="scripts/lint-baselines/package-refs-baseline.txt"
# Floor, same rationale as MANIFEST_FLOOR: a scan that suddenly finds a handful
# of refs proves nothing about the package tree (66 measured today).
PACKAGE_REFS_FLOOR=55

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

  # --skip-top evals: the generator excludes evals/ from the artifact, so a ref
  # authored there is never shipped and never belongs in this scan.
  # The extractor's exit status is captured for real — a failed extraction fails
  # the section instead of silently scanning nothing.
  local out
  if ! out=$(PYTHONDONTWRITEBYTECODE=1 python3 scripts/goalforge_refs.py scan \
               --root "$root" --ignore "$REF_IGNORE_FILE" --package \
               --skip-top evals 2>&1); then
    printf '  %s: reference extractor failed\n%s\n' "$root" "$out" >&2
    SCANNED=0
    return 1
  fi

  local -a scan=()
  local line
  if [ -n "$out" ]; then
    while IFS= read -r line; do scan+=("$line"); done <<<"$out"
  fi

  SCANNED=${#scan[@]}

  if [ "$SCANNED" -lt "$PACKAGE_REFS_FLOOR" ]; then
    printf '  %s: %d refs, below the floor of %d — the extractor stopped matching\n' \
      "$root" "$SCANNED" "$PACKAGE_REFS_FLOOR" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  fi

  # `<0|1>\t<from>::<path>`, 1 = the path exists in the scanned tree.
  for line in ${scan+"${scan[@]}"}; do
    case "$line" in 0*) DANGLING+=("${line#*$'\t'}") ;; esac
  done

  check_ratchet "$PACKAGE_REFS_BASELINE"
  check_dead_ignores "$root" --package --skip-top evals

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
      die 2 "section $s scanned 0 items — refusing to report PASS"
    fi
    if [ "$status" -eq 0 ]; then
      printf 'section %s: PASS (%d items scanned)\n' "$s" "$SCANNED"
    else
      printf 'section %s: FAIL (%d items scanned)\n' "$s" "$SCANNED"
      failed=1
    fi
  done

  # Fail-closed: a run that matched no section is an error, not success.
  [ "$ran" -gt 0 ] || die 2 "no sections matched — refusing to report success"
  return "$failed"
}

main "$@"
