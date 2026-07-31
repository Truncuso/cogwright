#!/usr/bin/env bash
#
# validate-ticket.sh — read-only frontmatter shape check for a wayfind ticket.
# Contract (AUTHORITATIVE): SKILL.md §"chart flow" step 2 — the in-skill ticket
#           frontmatter template.
# Provenance note only, NOT an authority (unresolvable from an installed
#           plugin): ~/.claude/plans/_archived/wayfind/spec.md
#           §"ticket-NN-<slug>.md frontmatter".
#
#   validate-ticket.sh <ticket.md>
#
# READ-ONLY: never writes or mutates the target. No network.
#
# Exit codes:
#   0  valid — frontmatter conforms to the ticket contract
#   1  invalid — a field violates the contract (stderr NAMES the field)
#   2  fail-close: usage (missing/absent argument)
#
set -euo pipefail

PROG="$(basename "$0")"

die()  { printf '%s: %s\n' "$PROG" "$*" >&2; exit 2; }
bad()  { printf '%s: invalid ticket (%s): %s\n' "$PROG" "$1" "$2" >&2; exit 1; }

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
[ $# -eq 1 ] || die "usage: $PROG <ticket.md>"
TICKET="$1"
[ -f "$TICKET" ] || die "ticket file not found: $TICKET"

# --- read frontmatter -------------------------------------------------------
T_TYPE=""; T_TT=""; T_STATUS=""; T_CBY=""; T_CAT=""; T_RES=""; T_MODE=""
have_type=0; have_tt=0; have_status=0; have_cby=0; have_cat=0; have_res=0
have_mode=0; deps_islist=0; have_deps=0
DEPS_TOKENS=()

first=1; in_fm=0; closed=0
pending_deps=0

while IFS= read -r line || [ -n "$line" ]; do
  if [ "$first" -eq 1 ]; then
    first=0
    [ "$(trim "$line")" = "---" ] && { in_fm=1; continue; } || bad "frontmatter" "no opening --- delimiter"
  fi
  [ "$in_fm" -eq 1 ] || continue
  [ "$(trim "$line")" = "---" ] && { closed=1; break; }

  if [ "$pending_deps" -eq 1 ]; then
    t="$(trim "$line")"
    case "$t" in
      -*)
        deps_islist=1
        dtok="$(unquote "$(trim "${t#-}")")"
        [ -n "$dtok" ] && DEPS_TOKENS+=("$dtok")
        continue ;;
      "") continue ;;
      *) pending_deps=0 ;;
    esac
  fi

  case "$line" in
    type:*)
      [ "$have_type" -eq 0 ] || bad "type" "duplicate key"
      T_TYPE="$(fieldval "${line#type:}")"; have_type=1 ;;
    ticket_type:*)
      [ "$have_tt" -eq 0 ] || bad "ticket_type" "duplicate key"
      T_TT="$(fieldval "${line#ticket_type:}")"; have_tt=1 ;;
    status:*)
      [ "$have_status" -eq 0 ] || bad "status" "duplicate key"
      T_STATUS="$(fieldval "${line#status:}")"; have_status=1 ;;
    claimed_by:*)
      [ "$have_cby" -eq 0 ] || bad "claimed_by" "duplicate key"
      T_CBY="$(fieldval "${line#claimed_by:}")"; have_cby=1 ;;
    claimed_at:*)
      [ "$have_cat" -eq 0 ] || bad "claimed_at" "duplicate key"
      T_CAT="$(fieldval "${line#claimed_at:}")"; have_cat=1 ;;
    resolution:*)
      [ "$have_res" -eq 0 ] || bad "resolution" "duplicate key"
      T_RES="$(fieldval "${line#resolution:}")"; have_res=1 ;;
    mode:*)
      [ "$have_mode" -eq 0 ] || bad "mode" "duplicate key"
      T_MODE="$(fieldval "${line#mode:}")"; have_mode=1 ;;
    depends_on:*)
      [ "$have_deps" -eq 0 ] || bad "depends_on" "duplicate key"
      have_deps=1
      v="$(strip_comment "$(trim "${line#depends_on:}")")"
      case "$v" in
        "["*"]")
          deps_islist=1
          inner="${v#\[}"; inner="${inner%\]}"
          # split on comma WITHOUT pathname expansion (a bare * must stay literal)
          IFS=',' read -ra _dtoks <<< "$inner" || true
          for _dt in "${_dtoks[@]:-}"; do
            _dt="$(unquote "$(trim "$_dt")")"
            [ -n "$_dt" ] && DEPS_TOKENS+=("$_dt")
          done ;;
        "") pending_deps=1 ;;
        *) deps_islist=0 ;;
      esac ;;
  esac
done < "$TICKET"

[ "$closed" -eq 1 ] || bad "frontmatter" "unterminated frontmatter block"

# --- assertions -------------------------------------------------------------
[ "$have_type" -eq 1 ] || bad "type" "field missing"
[ "$T_TYPE" = "wayfind-ticket" ] || bad "type" "expected wayfind-ticket, got '$T_TYPE'"

[ "$have_tt" -eq 1 ] || bad "ticket_type" "field missing"
case "$T_TT" in
  research|grilling|prototype|task) ;;
  *) bad "ticket_type" "expected research|grilling|prototype|task, got '$T_TT'" ;;
esac

[ "$have_status" -eq 1 ] || bad "status" "field missing"
case "$T_STATUS" in
  open|resolved|out-of-scope) ;;
  *) bad "status" "expected open|resolved|out-of-scope, got '$T_STATUS'" ;;
esac

[ "$have_deps" -eq 1 ] || bad "depends_on" "field missing"
[ "$deps_islist" -eq 1 ] || bad "depends_on" "must be a YAML list (inline [] or block form)"

# every depends_on element must name a ticket (ticket-NN) — a bare glob (*) or
# any other token is rejected, matching the frontier's fail-closed shape check.
for _dt in "${DEPS_TOKENS[@]:-}"; do
  [ -z "$_dt" ] && continue
  [[ "$_dt" =~ ^ticket-[0-9]+$ ]] \
    || bad "depends_on" "element must match ticket-NN, got '$_dt'"
done

[ "$have_cby" -eq 1 ] || bad "claimed_by" "field missing"
[ "$have_cat" -eq 1 ] || bad "claimed_at" "field missing"

# claimed_at, when non-null, must be YYYY-MM-DD
case "$T_CAT" in
  null|"") ;;
  *) [[ "$T_CAT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
       || bad "claimed_at" "non-null value must be YYYY-MM-DD, got '$T_CAT'" ;;
esac

[ "$have_res" -eq 1 ] || bad "resolution" "field missing"

# mode is ONLY valid on ticket_type: task, and its value is pinned to {HITL, AFK}
# (spec: HITL override, AFK default).
if [ "$have_mode" -eq 1 ]; then
  [ "$T_TT" = "task" ] || bad "mode" "field only valid on ticket_type: task (found on ticket_type: $T_TT)"
  case "$T_MODE" in
    HITL|AFK) ;;
    *) bad "mode" "expected HITL|AFK, got '$T_MODE'" ;;
  esac
fi

exit 0
