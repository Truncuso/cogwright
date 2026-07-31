#!/usr/bin/env bash
#
# validate-map.sh — read-only frontmatter shape check for a wayfind map.md.
# Contract (AUTHORITATIVE): SKILL.md §"chart flow" step 1 — the in-skill map
#           frontmatter template.
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

  # a block-list continuation line ("  - item") for a pending list key
  if [ -n "$pending" ]; then
    t="$(trim "$line")"
    case "$t" in
      -*) [ "$pending" = "cp" ] && cp_islist=1 || ref_islist=1; continue ;;
      "") continue ;;
      *) pending="" ;;   # next key begins; fall through to parse it
    esac
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
        "["*"]") cp_islist=1 ;;
        "") pending="cp" ;;            # possible block form; confirm on next lines
        *) cp_islist=0 ;;             # a bare scalar — not a list
      esac ;;
    references:*)
      [ "$have_ref" -eq 0 ] || bad "references" "duplicate key"
      have_ref=1
      v="$(strip_comment "$(trim "${line#references:}")")"
      case "$v" in
        "["*"]") ref_islist=1 ;;
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

exit 0
