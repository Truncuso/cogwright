#!/usr/bin/env bash
#
# validate-map.sh — read-only frontmatter + `## Notes`-table shape check for a
# wayfind map.md.
# Contract (AUTHORITATIVE): SKILL.md §"chart flow" step 1 — the in-skill map
#           frontmatter template and the map body-section list.
# references[] entry shape is CANONICAL and cited, never redefined here:
#           ~/.claude/skills/idea/references/provenance-mapping.md
#           (id/type/locator required; note/retrieved optional).
# Provenance note only, NOT an authority (unresolvable from an installed
#           plugin): ~/.claude/plans/_archived/wayfind/spec.md
#           §"map.md frontmatter".
#
#   validate-map.sh <map.md>
#
# READ-ONLY: never writes or mutates the target. No network.
#
# Exit codes:
#   0  valid — frontmatter conforms to the map contract
#   1  invalid — a field violates the contract (stderr NAMES the field)
#   2  fail-close: usage (missing/absent argument)
#
set -euo pipefail

PROG="$(basename "$0")"

die()  { printf '%s: %s\n' "$PROG" "$*" >&2; exit 2; }
bad()  { printf '%s: invalid map (%s): %s\n' "$PROG" "$1" "$2" >&2; exit 1; }

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# Quote-aware trailing-comment strip: remove a ` #…` comment only when the # is
# OUTSIDE any quote AND preceded by whitespace (a `#` inside quotes, or flush
# against a value, is data). Operate on already-trimmed input; re-trim the tail.
strip_comment() {
  local s="$1" out="" ch prev="" in_s=0 in_d=0 i n
  n=${#s}
  for (( i=0; i<n; i++ )); do
    ch="${s:i:1}"
    if [ "$in_s" -eq 0 ] && [ "$in_d" -eq 0 ] && [ "$ch" = "#" ]; then
      case "$prev" in " "|"	") break ;; esac
    fi
    case "$ch" in
      "'") [ "$in_d" -eq 0 ] && in_s=$(( 1 - in_s )) ;;
      '"') [ "$in_s" -eq 0 ] && in_d=$(( 1 - in_d )) ;;
    esac
    out="$out$ch"; prev="$ch"
  done
  out="${out%"${out##*[![:space:]]}"}"
  printf '%s' "$out"
}

unquote() {
  local s="$1"
  case "$s" in
    '"'*'"') s="${s#\"}"; s="${s%\"}" ;;
    "'"*"'") s="${s#\'}"; s="${s%\'}" ;;
  esac
  printf '%s' "$s"
}

# field value = trim → strip trailing comment → unquote.
fieldval() { unquote "$(strip_comment "$(trim "$1")")"; }

# --- argument handling ------------------------------------------------------
[ $# -eq 1 ] || die "usage: $PROG <map.md>"
MAP="$1"
[ -f "$MAP" ] || die "map file not found: $MAP"

# --- read frontmatter -------------------------------------------------------
# Populate: raw scalar per key (M_*), and a flag for list-shaped fields.
M_TYPE=""; M_STATUS=""; M_DEST=""; M_CREATED=""
have_type=0; have_status=0; have_dest=0; have_created=0
cp_islist=0; ref_islist=0; have_cp=0; have_ref=0
# raw element capture for the two list-shaped fields: CP_/REF_INLINE hold the
# `[...]` body for the inline form; CP_/REF_LINES hold the trimmed block-form
# lines (one per line, including a typed entry's sub-keys). No nested parser —
# grouping is by leading `-` and nothing deeper.
CP_INLINE=""; REF_INLINE=""; CP_LINES=""; REF_LINES=""

first=1; in_fm=0; closed=0
# track the key whose block-form list we might be reading
pending=""   # "cp" | "ref" | ""

while IFS= read -r line || [ -n "$line" ]; do
  if [ "$first" -eq 1 ]; then
    first=0
    [ "$(trim "$line")" = "---" ] && { in_fm=1; continue; } || bad "frontmatter" "no opening --- delimiter"
  fi
  [ "$in_fm" -eq 1 ] || continue
  [ "$(trim "$line")" = "---" ] && { closed=1; break; }

  # a block-list continuation line for a pending list key: any INDENTED or blank
  # line belongs to the list; the first dedented non-blank line ends it.
  if [ -n "$pending" ]; then
    t="$(trim "$line")"
    case "$line" in
      [![:space:]]*) pending="" ;;   # dedented, non-blank ⇒ next key begins
    esac
  fi
  if [ -n "$pending" ]; then
    case "$t" in
      -*) [ "$pending" = "cp" ] && cp_islist=1 || ref_islist=1 ;;
    esac
    if [ "$pending" = "cp" ]; then CP_LINES="$CP_LINES$t"$'\n'
    else REF_LINES="$REF_LINES$t"$'\n'; fi
    continue
  fi

  case "$line" in
    type:*)
      [ "$have_type" -eq 0 ] || bad "type" "duplicate key"
      M_TYPE="$(fieldval "${line#type:}")"; have_type=1 ;;
    status:*)
      [ "$have_status" -eq 0 ] || bad "status" "duplicate key"
      M_STATUS="$(fieldval "${line#status:}")"; have_status=1 ;;
    created:*)
      [ "$have_created" -eq 0 ] || bad "created" "duplicate key"
      M_CREATED="$(fieldval "${line#created:}")"; have_created=1 ;;
    destination:*)
      [ "$have_dest" -eq 0 ] || bad "destination" "duplicate key"
      M_DEST="$(fieldval "${line#destination:}")"; have_dest=1 ;;
    context_pointers:*)
      [ "$have_cp" -eq 0 ] || bad "context_pointers" "duplicate key"
      have_cp=1
      v="$(strip_comment "$(trim "${line#context_pointers:}")")"
      case "$v" in
        "["*"]") cp_islist=1; CP_INLINE="${v#[}"; CP_INLINE="${CP_INLINE%]}" ;;
        "") pending="cp" ;;            # possible block form; confirm on next lines
        *) cp_islist=0 ;;             # a bare scalar — not a list
      esac ;;
    references:*)
      [ "$have_ref" -eq 0 ] || bad "references" "duplicate key"
      have_ref=1
      v="$(strip_comment "$(trim "${line#references:}")")"
      case "$v" in
        "["*"]") ref_islist=1; REF_INLINE="${v#[}"; REF_INLINE="${REF_INLINE%]}" ;;
        "") pending="ref" ;;
        *) ref_islist=0 ;;
      esac ;;
  esac
done < "$MAP"

[ "$closed" -eq 1 ] || bad "frontmatter" "unterminated frontmatter block"

# --- assertions -------------------------------------------------------------
[ "$have_type" -eq 1 ] || bad "type" "field missing"
[ "$M_TYPE" = "wayfind-map" ] || bad "type" "expected wayfind-map, got '$M_TYPE'"

[ "$have_status" -eq 1 ] || bad "status" "field missing"
case "$M_STATUS" in
  charting|working) ;;
  *) bad "status" "expected charting|working, got '$M_STATUS'" ;;
esac

[ "$have_created" -eq 1 ] || bad "created" "field missing"
[[ "$M_CREATED" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
  || bad "created" "must be YYYY-MM-DD, got '$M_CREATED'"

[ "$have_dest" -eq 1 ] || bad "destination" "field missing"
[ -n "$M_DEST" ] || bad "destination" "must be non-empty"

[ "$have_cp" -eq 1 ] || bad "context_pointers" "field missing"
[ "$cp_islist" -eq 1 ] || bad "context_pointers" "must be a YAML list (inline [] or block form)"

[ "$have_ref" -eq 1 ] || bad "references" "field missing"
[ "$ref_islist" -eq 1 ] || bad "references" "must be a YAML list (inline [] or block form)"

# --- context_pointers: a list of non-empty STRINGS and nothing more ---------
# SKILL.md defines context_pointers as paths/globs the blind-spot pass sweeps,
# so an entry must be a plain non-empty string — never a nested list or a map.
cp_elem() {
  local e; e="$(unquote "$(strip_comment "$(trim "$1")")")"
  [ -n "$e" ] || bad "context_pointers" "list contains an empty entry"
  case "$e" in
    '{'*|'['*|-*) bad "context_pointers" "entry is not a plain string: '$e'" ;;
  esac
}

if [ -n "$CP_INLINE" ]; then
  IFS=',' read -r -a _cp_items <<< "$CP_INLINE"
  for _it in "${_cp_items[@]}"; do cp_elem "$_it"; done
fi
while IFS= read -r _l; do
  [ -n "$_l" ] || continue
  case "$_l" in
    -*) cp_elem "${_l#-}" ;;
    *)  bad "context_pointers" "entry is not a plain string: '$_l'" ;;
  esac
done <<< "$CP_LINES"

# --- references[]: three LEGAL entry forms ---------------------------------
#   (i)   a typed object entry beginning `- id:` — MUST carry `type` + `locator`
#         (`note` / `retrieved` optional). Canonical shape, see header.
#   (ii)  a bare `- <string>` entry — legal and UNCHECKED beyond non-emptiness
#         (reads as `{locator: <string>}`, lossy but legal).
#   (iii) `references: []`.
# Grouping is by leading `-` only; sub-keys are matched by name, never parsed
# as nested YAML.
ref_typed=0; ref_type=0; ref_loc=0; ref_id=""
ref_flush() {
  [ "$ref_typed" -eq 1 ] || return 0
  [ "$ref_type" -eq 1 ] || bad "references" "typed entry '$ref_id' missing required key: type"
  [ "$ref_loc"  -eq 1 ] || bad "references" "typed entry '$ref_id' missing required key: locator"
}

if [ -n "$REF_INLINE" ]; then
  IFS=',' read -r -a _ref_items <<< "$REF_INLINE"
  for _it in "${_ref_items[@]}"; do
    [ -n "$(unquote "$(strip_comment "$(trim "$_it")")")" ] \
      || bad "references" "list contains an empty entry"
  done
fi

while IFS= read -r _l; do
  [ -n "$_l" ] || continue
  case "$_l" in
    -*)
      ref_flush
      ref_typed=0; ref_type=0; ref_loc=0; ref_id=""
      _item="$(trim "${_l#-}")"
      case "$_item" in
        id:*) ref_typed=1; ref_id="$(fieldval "${_item#id:}")" ;;
        *)    [ -n "$(unquote "$(strip_comment "$_item")")" ] \
                || bad "references" "list contains an empty entry" ;;
      esac ;;
    type:*)    ref_type=1 ;;
    locator:*) ref_loc=1 ;;
  esac
done <<< "$REF_LINES"
ref_flush

# --- `## Notes` body pass (OPTIONAL section, fixed-shape table) -------------
# A SECOND, body-only pass that runs after the frontmatter loop closed. Bounded
# to a line-scanner over the `## Notes` block: locate the heading, read to the
# next `## ` or EOF, split rows on `|`. No general markdown parsing.
if grep -q '^## Notes[[:space:]]*$' "$MAP"; then
  NOTES="$(awk 'inx && /^## /{exit} inx{print} /^## Notes[[:space:]]*$/{inx=1}' "$MAP")"
  rows=(); while IFS= read -r _l; do
    case "$(trim "$_l")" in '|'*) rows+=("$(trim "$_l")") ;; esac
  done <<< "$NOTES"

  [ "${#rows[@]}" -ge 2 ] \
    || bad "## Notes" "section present but carries no | ticket_type | machinery | model | effort | table"

  cells() {                      # $1 = row → CELLS[] (trimmed, outer pipes dropped)
    local r="$1"; r="${r#|}"; r="${r%|}"
    local _old="$IFS"; IFS='|'; read -r -a CELLS <<< "$r"; IFS="$_old"
    local i; for i in "${!CELLS[@]}"; do CELLS[$i]="$(trim "${CELLS[$i]}")"; done
  }

  cells "${rows[0]}"
  [ "${#CELLS[@]}" -eq 4 ] \
    || bad "## Notes" "header row must have exactly 4 columns, got ${#CELLS[@]}"
  [ "${CELLS[0]}" = "ticket_type" ] && [ "${CELLS[1]}" = "machinery" ] \
    && [ "${CELLS[2]}" = "model" ] && [ "${CELLS[3]}" = "effort" ] \
    || bad "## Notes" "header row must be | ticket_type | machinery | model | effort |"

  cells "${rows[1]}"
  [ "${#CELLS[@]}" -eq 4 ] \
    || bad "## Notes" "delimiter row must have exactly 4 columns, got ${#CELLS[@]}"
  for c in "${CELLS[@]}"; do
    [[ "$c" =~ ^:?-+:?$ ]] || bad "## Notes" "row 2 must be the table delimiter, got '$c'"
  done

  for (( r=2; r<${#rows[@]}; r++ )); do
    cells "${rows[$r]}"
    [ "${#CELLS[@]}" -eq 4 ] \
      || bad "## Notes" "override row must have exactly 4 columns, got ${#CELLS[@]}: ${rows[$r]}"
    # enum kept in lockstep with validate-ticket.sh and the SKILL.md dispatch
    # table: an override row may target ANY ticket_type that has a table row,
    # `learning` included (references/learning-goals.md §3).
    case "${CELLS[0]}" in
      research|grilling|prototype|task|learning) ;;
      *) bad "## Notes" "ticket_type must be research|grilling|prototype|task|learning, got '${CELLS[0]}'" ;;
    esac
    for c in "${CELLS[@]}"; do
      [ -n "$c" ] || bad "## Notes" "override row has an empty cell: ${rows[$r]}"
    done
  done
fi

# --- `## Learning goals` body pass (OPTIONAL section, row shape) ------------
# Learning goals are OPT-IN: an ABSENT section is valid on every map, which is
# why this pass is guarded by the same grep as `## Notes` above. When present,
# each list row must be `- <kebab-slug>: <non-empty objective>`; the documented
# `(why: <driver>)` tail is a CONVENTION carried inside the objective text, not
# a validated field. Contract: references/learning-goals.md §2.
# Same bounded line-scanner shape as the `## Notes` pass — locate the heading,
# read to the next `## ` or EOF. No general markdown parsing.
if grep -q '^## Learning goals[[:space:]]*$' "$MAP"; then
  LG="$(awk 'inx && /^## /{exit} inx{print} /^## Learning goals[[:space:]]*$/{inx=1}' "$MAP")"
  lg_rows=0
  while IFS= read -r _l; do
    _t="$(trim "$_l")"
    case "$_t" in
      "") continue ;;
      -*) ;;
      # a non-list, non-blank line in the section is prose the pointer-index
      # contract does not allow — the section carries rows and nothing else.
      *) bad "## Learning goals" "section carries a non-row line: '$_t'" ;;
    esac
    lg_rows=$((lg_rows + 1))
    [[ "$_t" =~ ^-[[:space:]]+([a-z0-9]+(-[a-z0-9]+)*):[[:space:]]+(.+)$ ]] \
      || bad "## Learning goals" "row must be '- <kebab-slug>: <objective>', got '$_t'"
    [ -n "$(trim "${BASH_REMATCH[3]}")" ] \
      || bad "## Learning goals" "row has an empty objective: '$_t'"
  done <<< "$LG"

  # a present-but-empty section is a section that should have been left out —
  # the same posture as the `## Notes` "present but carries no table" rule.
  [ "$lg_rows" -ge 1 ] \
    || bad "## Learning goals" "section present but carries no '- <slug>: <objective>' row"
fi

exit 0
