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
SECTIONS=(author-paths manifest package-refs version privacy-marker)

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
# version — three-way agreement on the single version authority.
#
# packages/goalforge/SKILL.md `metadata.version` is the only hand-bumped value;
# plugins/goalforge/.claude-plugin/plugin.json `version` is generated from it and
# the README catalog quotes it. This section asserts all three agree.
#
# Semantics are pinned FAIL-CLOSED, because an equality-only comparison passes
# when all three sides are empty:
#   - the SKILL.md value MUST match ^[0-9]+\.[0-9]+\.[0-9]+$
#   - an absent or empty value on ANY of the three sides is a FAIL
#   - a missing plugin.json `version` key is a FAIL (distinct from an empty one)
#
# The scan unit is the three sides, so SCANNED is always 3 — "stopped matching"
# cannot silently pass here, it surfaces as an absent-value FAIL instead.
# ---------------------------------------------------------------------------

lint_version() {
  VIOLATIONS=0

  # GF_SKILL_MD / GF_PLUGIN_JSON / GF_README: per-side overrides, so a negative
  # case can point one side at a scratch copy instead of mutating the real tree.
  local skill_md="${GF_SKILL_MD:-packages/goalforge/SKILL.md}"
  local plugin_json="${GF_PLUGIN_JSON:-plugins/goalforge/.claude-plugin/plugin.json}"
  local readme="${GF_README:-README.md}"

  SCANNED=3

  # ── SKILL.md metadata.version — the authority ──
  local sv=""
  if [ ! -f "$skill_md" ]; then
    printf '  %s: not a file\n' "$skill_md" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  else
    sv="$(awk '/^---$/{f++;next} f==1 && /^  version:/{gsub(/[" ]/,"",$2);print $2;exit}' "$skill_md")"
    if ! printf '%s' "$sv" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      printf '  %s: metadata.version is absent, empty, or not semver: %s\n' \
        "$skill_md" "'$sv'" >&2
      VIOLATIONS=$(( VIOLATIONS + 1 ))
      sv=""
    fi
  fi

  # ── plugin.json version — generated ──
  local pv="" rc=0
  pv="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(3) if "version" not in d else print(d["version"] if isinstance(d["version"], str) else "")' \
        "$plugin_json" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 3 ]; then
    printf '  %s: no "version" key\n' "$plugin_json" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
    pv=""
  elif [ "$rc" -ne 0 ]; then
    printf '  %s: unreadable or not JSON\n' "$plugin_json" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
    pv=""
  elif [ -z "$pv" ]; then
    printf '  %s: "version" is empty\n' "$plugin_json" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  fi

  # ── README catalog quote — the goalforge row's (vX.Y.Z) ──
  local rv=""
  if [ ! -f "$readme" ]; then
    printf '  %s: not a file\n' "$readme" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  else
    rv="$(sed -n 's/^| \*\*goalforge\*\* |[^|]*(v\([^)]*\)).*/\1/p' "$readme" | head -n1)"
    if [ -z "$rv" ]; then
      printf '  %s: no goalforge catalog row carrying a (vX.Y.Z) quote\n' "$readme" >&2
      VIOLATIONS=$(( VIOLATIONS + 1 ))
    fi
  fi

  # ── Agreement — only meaningful once every side produced a value ──
  if [ -n "$sv" ] && [ -n "$pv" ] && [ "$pv" != "$sv" ]; then
    printf '  %s: version %s != %s metadata.version %s\n' \
      "$plugin_json" "$pv" "$skill_md" "$sv" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  fi
  if [ -n "$sv" ] && [ -n "$rv" ] && [ "$rv" != "$sv" ]; then
    printf '  %s: goalforge catalog quotes v%s != %s metadata.version %s\n' \
      "$readme" "$rv" "$skill_md" "$sv" >&2
    VIOLATIONS=$(( VIOLATIONS + 1 ))
  fi

  [ "$VIOLATIONS" -eq 0 ]
}

# ---------------------------------------------------------------------------
# privacy-marker — the child skills route back to the parent front door.
#
# The generator (rewrite class ix) prefixes every generated CHILD skill
# description with a fixed marker; the parent description is untouched. This
# section proves that on the SHIPPED artifact, over PARSED frontmatter rather
# than grep, because the assertion is about the description VALUE a plugin
# loader sees — a raw text match would pass on a marker that landed outside the
# scalar, or inside a comment.
#
# python3 + PyYAML is a declared HARD dependency here (as it is for the wp-07
# doctor dep check): an unparseable frontmatter must FAIL, and only a real YAML
# parse can tell that apart from a marker that is merely absent.
#
# Scan unit is the child SKILL.md, so SCANNED is the child count. The expected
# count is PINNED: a child silently dropped by the generator, or added at
# source without review, is exactly what this section exists to catch. Bump it
# deliberately in the change that adds or removes a child — together with the
# skill count quoted in the goalforge catalog row, README.md:90.
#
# The marker literal itself lives INSIDE the python heredoc, not in a shell
# variable passed through argv — see the note there.
# ---------------------------------------------------------------------------

# Cap on the parsed description length. THE UNIT IS CHARACTERS, by decision:
# it is what a YAML-level reader counts, and it is stable under the em dash the
# marker carries. The unit the plugin LOADER enforces is unpinned upstream, so
# this is our unit, not a mirror of theirs. Worst case in the tree today is
# archive at 1023 characters — 1 character of headroom — which is 1031 BYTES in
# UTF-8: if the loader turns out to cap bytes, that child is already over
# today. Tracked residual (wp-09 / feature-2). Note the marker alone consumes
# 61 characters of every child's budget.
PRIVACY_MAX_DESC=1024
PRIVACY_EXPECTED_CHILDREN=18

lint_privacy_marker() {
  VIOLATIONS=0

  if ! python3 -c 'import yaml' 2>/dev/null; then
    die 2 "privacy-marker requires python3 + PyYAML (declared hard dependency)"
  fi

  local n rc=0
  n="$(python3 - "$PRIVACY_MAX_DESC" "$PRIVACY_EXPECTED_CHILDREN" <<'PY'
import glob, sys, yaml

# MARKER is a PYTHON LITERAL, mirroring MARKER in scripts/goalforge-generate.sh
# — deliberately NOT passed through argv. It carries an em dash, and argv is
# decoded with the process locale: under an ASCII locale (LC_ALL=C with UTF-8
# mode off) the em dash arrives surrogate-escaped and every child false-FAILs
# against a description read as UTF-8. Python SOURCE is always decoded as UTF-8
# (PEP 3120), so the literal is locale-proof.
MARKER = "goalforge-internal — use entry commands; do not auto-trigger"
# The distinctive TAIL, asserted on the parent. The marker's head words recur
# in ordinary prose; this phrase does not.
TAIL = "do not auto-trigger"

max_desc, expected = int(sys.argv[1]), int(sys.argv[2])
parent = "plugins/goalforge/SKILL.md"
children = sorted(glob.glob("plugins/goalforge/skills/*/SKILL.md"))
bad = 0


def description(path):
    """Parsed top-level `description`, or None with the reason printed."""
    try:
        raw = open(path, encoding="utf-8").read()
    except OSError as exc:
        print("  %s: unreadable (%s)" % (path, exc), file=sys.stderr)
        return None
    # Line-based delimiter scan, mirroring inject_marker in the generator: a
    # substring split on "---" would cut a description that itself contains a
    # triple hyphen and false-FAIL on unparseable frontmatter.
    lines = raw.split("\n")
    if not lines or lines[0].strip() != "---":
        print("  %s: no leading YAML frontmatter block" % path, file=sys.stderr)
        return None
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        print("  %s: unterminated YAML frontmatter block" % path, file=sys.stderr)
        return None
    try:
        fm = yaml.safe_load("\n".join(lines[1:end]))
    except yaml.YAMLError as exc:
        print("  %s: frontmatter does not parse as YAML (%s)"
              % (path, str(exc).replace("\n", " ")), file=sys.stderr)
        return None
    if not isinstance(fm, dict) or not isinstance(fm.get("description"), str):
        print("  %s: no string `description` in frontmatter" % path, file=sys.stderr)
        return None
    return fm["description"]


print(len(children))  # SCANNED, on stdout; violations go to stderr

if len(children) != expected:
    print("  plugins/goalforge/skills/: %d child SKILL.md, expected %d"
          % (len(children), expected), file=sys.stderr)
    bad += 1

for path in children:
    desc = description(path)
    if desc is None:
        bad += 1
        continue
    if not desc.startswith(MARKER):
        print("  %s: description does not start with the privacy marker" % path,
              file=sys.stderr)
        bad += 1
    # Prefix INTEGRITY, not mere presence: exactly one marker (a re-run of the
    # generator over already-generated output would stack a second one), and
    # the original trigger wording still there behind it.
    elif desc.count(MARKER) != 1:
        print("  %s: description carries the privacy marker %d times, expected 1"
              % (path, desc.count(MARKER)), file=sys.stderr)
        bad += 1
    elif len(desc) <= len(MARKER) + 1:
        print("  %s: description is the bare privacy marker — the original "
              "wording did not survive injection" % path, file=sys.stderr)
        bad += 1
    if len(desc) > max_desc:
        print("  %s: description is %d chars, over the %d cap"
              % (path, len(desc), max_desc), file=sys.stderr)
        bad += 1

parent_desc = description(parent)
if parent_desc is None:
    bad += 1
elif TAIL in parent_desc:
    print("  %s: parent description carries the child marker (%r)"
          % (parent, TAIL), file=sys.stderr)
    bad += 1

sys.exit(1 if bad else 0)
PY
  )" || rc=$?

  SCANNED="${n:-0}"
  VIOLATIONS="$rc"

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
