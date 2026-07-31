#!/usr/bin/env bash
#
# validate-linkage.sh — read-only CROSS-FILE linkage check for a wayfind effort:
# the map's `## Decisions so far` pointers, the ticket statuses, and the
# `resolution:` findings targets must agree. The first script that reads a map
# or ticket BODY at all.
# Contract (AUTHORITATIVE): SKILL.md §"work flow" — the End-the-session
#           validator invocation point; §"chart flow" steps 1-2 for the map body
#           sections and the ticket frontmatter template.
# Provenance note only, NOT an authority (unresolvable from an installed
#           plugin): ~/.claude/plans/_archived/wayfind/spec.md
#
#   validate-linkage.sh <effort-dir>   # dir containing wayfind/map.md + tickets
#
# READ-ONLY: never writes or mutates the effort dir. No network.
#
# NOT a convergence computer. SKILL.md's Constraints make wayfind-frontier.sh the
# SOLE computer of convergence; this script never counts open tickets as a
# convergence signal and never emits the word in its output. Forking that
# authority would be a silent contract break.
#
# Exit codes:
#   0  clean — every linkage invariant holds (also: an effort with ZERO tickets)
#   1  linkage violations — each one NAMED on stdout
#   2  fail-close: usage / structural error (missing dir, no wayfind/, no map.md
#      once tickets exist, malformed ticket frontmatter — stderr names the file)
#
# DELIBERATE DIVERGENCE from wayfind-frontier.sh's exit mapping: an effort dir
# with zero tickets exits 0, not 2. The frontier fail-closes on zero tickets so
# it can never emit `converged: true` over an empty map; a linkage checker has no
# such hazard — zero tickets means zero linkage to violate.
#
set -euo pipefail

PROG="$(basename "$0")"

die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 2; }

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

unquote() {
  local s="$1"
  case "$s" in
    '"'*'"') s="${s#\"}"; s="${s%\"}" ;;
    "'"*"'") s="${s#\'}"; s="${s%\'}" ;;
  esac
  printf '%s' "$s"
}

# --- argument handling ------------------------------------------------------
[ $# -eq 1 ] || die "usage: $PROG <effort-dir>"
# This script takes NO options. Reject any `--*` token by name — letting it fall
# through into effort-dir handling reports "effort dir not found: --self-test",
# which misdescribes the mistake.
case "$1" in
  --*) die "unknown option: $1 (usage: $PROG <effort-dir>)" ;;
esac
EFFORT_DIR="$1"
[ -d "$EFFORT_DIR" ] || die "effort dir not found: $EFFORT_DIR"
WAYFIND_DIR="$EFFORT_DIR/wayfind"
[ -d "$WAYFIND_DIR" ] || die "no wayfind/ subdir under: $EFFORT_DIR"

shopt -s nullglob
TICKET_FILES=("$WAYFIND_DIR"/ticket-*.md)
shopt -u nullglob

# zero tickets ⇒ zero linkage to violate (see the divergence note above)
[ "${#TICKET_FILES[@]}" -gt 0 ] || exit 0

MAP="$WAYFIND_DIR/map.md"
[ -f "$MAP" ] || die "no map.md in: $WAYFIND_DIR (tickets exist, so the map is required)"

# --- map `## Decisions so far` pointers -------------------------------------
# Bounded line-scanner: locate the heading, read to the next `## ` or EOF, and
# collect every `ticket-NN` token on the way. No markdown parsing.
# NOTE: a pointer naming a ticket that does not exist is NOT checked here — the
# three invariants this script owns are listed in SKILL.md's End-the-session step.
POINTED=" "
while read -r nn; do
  case "$POINTED" in *" $nn "*) continue ;; esac
  POINTED="$POINTED$nn "
done < <(
  awk 'inx && /^## /{exit} inx{print} /^## Decisions so far[[:space:]]*$/{inx=1}' "$MAP" \
    | grep -o 'ticket-[0-9]\+' | LC_ALL=C sort -u
)

# --- read each ticket's status + resolution ---------------------------------
violations=0
report() { printf '%s: linkage violation (%s): %s\n' "$PROG" "$1" "$2"; violations=$((violations + 1)); }

declare -A NN_STATUS
BASES=()

for f in "${TICKET_FILES[@]}"; do
  base="$(basename "$f" .md)"
  # basename split: `ticket-01-slug` → nn token `ticket-01`
  rest="${base#ticket-}"; nn="ticket-${rest%%-*}"

  status=""; resolution=""; first=1; in_fm=0; closed=0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$first" -eq 1 ]; then
      first=0
      [ "$(trim "$line")" = "---" ] && { in_fm=1; continue; } || break
    fi
    [ "$in_fm" -eq 1 ] || continue
    [ "$(trim "$line")" = "---" ] && { closed=1; break; }
    case "$line" in
      status:*)     status="$(unquote "$(trim "${line#status:}")")" ;;
      resolution:*) resolution="$(unquote "$(trim "${line#resolution:}")")" ;;
    esac
  done < "$f"

  [ "$closed" -eq 1 ] || die "malformed frontmatter: $f"
  case "$status" in
    open|resolved|out-of-scope) ;;
    *) die "malformed frontmatter: $f (status '$status')" ;;
  esac

  NN_STATUS["$nn"]="$status"
  BASES+=("$base")

  # invariant 1 — every RESOLVED ticket is pointed at from `## Decisions so far`
  if [ "$status" = "resolved" ]; then
    case "$POINTED" in
      *" $nn "*) ;;
      *) report "missing map pointer" "$base is resolved but $nn is absent from map.md ## Decisions so far" ;;
    esac
  fi

  # invariant 3 — every `resolution:` target file exists (shape is task-03's
  # validate-ticket.sh; EXISTENCE is owned here, where the effort dir is known)
  case "$resolution" in
    null|"") ;;
    /*) [ -f "$resolution" ] || report "missing findings" "$base resolution target does not exist: $resolution" ;;
    *)  target="$WAYFIND_DIR/${resolution#./}"
        [ -f "$target" ] || report "missing findings" "$base resolution target does not exist: $resolution" ;;
  esac
done

# invariant 2 — no map pointer targets an OPEN ticket
for nn in $POINTED; do
  if [ "${NN_STATUS[$nn]:-}" = "open" ]; then
    report "pointer to open ticket" "map.md ## Decisions so far points at $nn, which is still open"
  fi
done

[ "$violations" -eq 0 ] || exit 1
exit 0
