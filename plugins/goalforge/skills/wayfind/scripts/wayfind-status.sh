#!/usr/bin/env bash
#
# wayfind-status.sh — deterministic, read-only DISCOVERY scan across a plans
# root. Answers "which wayfind efforts are live, and where is each one?" so a
# no-slug `/wayfind` can present a resume list.
#
# Contract (AUTHORITATIVE): SKILL.md §"Auto-phase" — the no-slug discovery
#           entry point and this script's stdout JSON shape.
#
#   wayfind-status.sh <plans-root>    # dir containing <slug>/wayfind/map.md
#   wayfind-status.sh --self-test     # tmpdir-fixture self-test
#
# Convergence, frontier membership and stale-claim detection are NOT computed
# here: this script SHELLS OUT to the sibling wayfind-frontier.sh, which is the
# sole computer of convergence (SKILL.md §Constraints) — frontier / converged /
# stale_claims are passed through verbatim.
#
# `open`, by contrast, is counted DIRECTLY from the effort's ticket files (one
# increment per ticket-*.md with `status: open`). It is NOT derived from the
# sibling's arrays: they are not a partition — a ticket that is open with an
# unsatisfied dep AND a claim appears in BOTH `blocked` and `claimed` — and
# text-slicing the emitted JSON also miscounts a basename containing a comma.
#
# READ-ONLY: never writes into the plans root. No network. Temp files (self-test
# fixtures only) live under mktemp locations.
#
# DEGRADE-NOT-BLOCK: a single malformed effort is reported as
# {"slug": …, "status": …, "error": …} and the scan CONTINUES — one broken map
# never hides the other live efforts.
#
# Exit codes:
#   0  any valid state — zero efforts ({"efforts": []}) included, and a scan
#      containing per-effort error entries, or --self-test with every case
#      passing
#   1  --self-test with one or more failing cases
#   2  fail-close: usage / missing plans root
#
set -euo pipefail

PROG="$(basename "$0")"

die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 2; }

# JSON-escape an arbitrary string for safe interpolation into a JSON string
# literal: backslash, double-quote, and all control chars (< 0x20). Applied to
# EVERY interpolated string (slugs, error text) so a stray metacharacter can
# never break the emitted JSON. (Same helper as the sibling scripts.)
json_escape() {
  local s="$1" out="" i len c code
  len=${#s}
  for (( i = 0; i < len; i++ )); do
    c="${s:i:1}"
    case "$c" in
      '\') out+='\\' ;;
      '"') out+='\"' ;;
      *)
        printf -v code '%d' "'$c"
        if [ "$code" -ge 0 ] && [ "$code" -lt 32 ]; then
          printf -v out '%s\u%04x' "$out" "$code"
        else
          out+="$c"
        fi
        ;;
    esac
  done
  printf '%s' "$out"
}

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

unquote() {
  local s="$1"
  case "$s" in
    '"'*'"') s="${s#\"}"; s="${s%\"}" ;;
    "'"*"'") s="${s#\'}"; s="${s%\'}" ;;
  esac
  printf '%s' "$s"
}

# --- map status ------------------------------------------------------------
# Reads map.md frontmatter; sets M_STATUS to the raw `status:` scalar.
# Returns 1 when the frontmatter is absent or unterminated (malformed map).
# Returns 1 (degrade, never abort) when map.md is not a readable regular file —
# e.g. a directory named map.md, which would otherwise make `read` fail and kill
# the whole scan under `set -u`.
map_status() {
  local file="$1" line="" first=1 in_fm=0 closed=0
  M_STATUS=""
  [ -f "$file" ] && [ -r "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$first" -eq 1 ]; then
      first=0
      if [ "$(trim "$line")" = "---" ]; then in_fm=1; continue; else return 1; fi
    fi
    if [ "$in_fm" -eq 1 ]; then
      if [ "$(trim "$line")" = "---" ]; then closed=1; break; fi
      case "$line" in
        status:*) M_STATUS="$(unquote "$(trim "${line#status:}")")" ;;
      esac
    fi
  done < "$file"
  [ "$closed" -eq 1 ] || return 1
  return 0
}

# --- frontier-JSON accessors -----------------------------------------------
# The sibling emits ONE pinned single-line object:
#   {"frontier": [..], "blocked": [..], "claimed": [..], "stale_claims": [..],
#    "converged": bool}
# These slice that pinned shape; they never re-derive any of its values.

# slice_between <json> <open-key> <close-marker> -> inner text of the array
slice_between() {
  local j="$1" openk="$2" closek="$3" rest
  case "$j" in *"$openk"*) ;; *) return 1 ;; esac
  rest="${j#*"$openk"}"
  case "$rest" in *"$closek"*) ;; *) return 1 ;; esac
  printf '%s' "${rest%%"$closek"*}"
}

# --- open count -------------------------------------------------------------
# count_open_tickets <effort-dir> -> number of ticket-*.md files whose
# frontmatter carries `status: open`. Same tolerant frontmatter parsing as
# map_status; an unreadable ticket file is skipped rather than aborting.
count_open_tickets() {
  local dir="$1" f line first in_fm t_status n=0
  local -a files=()
  shopt -s nullglob
  files=("$dir"/wayfind/ticket-*.md)
  shopt -u nullglob
  for f in "${files[@]}"; do
    [ -f "$f" ] && [ -r "$f" ] || continue
    line=""; first=1; in_fm=0; t_status=""
    while IFS= read -r line || [ -n "$line" ]; do
      if [ "$first" -eq 1 ]; then
        first=0
        if [ "$(trim "$line")" = "---" ]; then in_fm=1; continue; else break; fi
      fi
      if [ "$in_fm" -eq 1 ]; then
        if [ "$(trim "$line")" = "---" ]; then break; fi
        case "$line" in
          status:*) t_status="$(unquote "$(trim "${line#status:}")")" ;;
        esac
      fi
    done < "$f"
    [ "$t_status" = "open" ] && n=$((n + 1))
  done
  printf '%s' "$n"
}

# --- --self-test: tmpdir fixtures + assert every facet ----------------------
if [ "${1:-}" = "--self-test" ]; then
  src="${BASH_SOURCE[0]}"
  while [ -h "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"; case "$src" in /*) ;; *) src="$dir/$src" ;; esac
  done
  SCRIPT_DIR="$(cd -P "$(dirname "$src")" && pwd)"
  SELF="$SCRIPT_DIR/$(basename "$src")"

  # Pin reference "now" so the sibling's 7-day stale boundary is wall-clock free.
  export WAYFIND_NOW="${WAYFIND_NOW:-2026-07-16}"

  ST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/wf_status_st.XXXXXX")"
  ST_ERRFILE="$ST_TMP/stderr"
  trap 'rm -rf "$ST_TMP"' EXIT

  st_fail=0
  fail() { printf 'FAIL [%s]: %s\n' "$1" "$2" >&2; st_fail=$((st_fail + 1)); }
  pass() { printf 'ok   [%s]\n' "$1"; }
  contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac }

  run_case() {
    set +e
    OUT="$(bash "$SELF" "$1" 2>"$ST_ERRFILE")"; RC=$?
    set -e
    ERR="$(cat "$ST_ERRFILE" 2>/dev/null || true)"
  }

  HAVE_PY=0
  if command -v python3 >/dev/null 2>&1; then HAVE_PY=1; fi
  is_valid_json() {
    if [ "$HAVE_PY" -eq 1 ]; then
      printf '%s' "$1" | python3 -c 'import sys,json; json.loads(sys.stdin.read())' >/dev/null 2>&1
    else
      contains "$1" '"efforts"'
    fi
  }

  # fixture builders -------------------------------------------------------
  mk_map() { # mk_map <effort-dir> <status>
    mkdir -p "$1/wayfind"
    { printf -- '---\n'
      printf 'type: wayfind-map\n'
      printf 'status: %s\n' "$2"
      printf 'destination: "fixture"\n'
      printf 'created: 2026-07-10\n'
      printf -- '---\n\n## Destination\nfixture\n'
    } > "$1/wayfind/map.md"
  }
  mk_ticket() { # mk_ticket <effort-dir> <name> <status> <deps> [claimed_by] [claimed_at]
    { printf -- '---\n'
      printf 'type: wayfind-ticket\n'
      printf 'ticket_type: grilling\n'
      printf 'status: %s\n' "$3"
      printf 'depends_on: %s\n' "$4"
      printf 'claimed_by: %s\n' "${5:-null}"
      printf 'claimed_at: %s\n' "${6:-null}"
      printf 'resolution: null\n'
      printf -- '---\n\n## Question\nfixture\n'
    } > "$1/wayfind/$2.md"
  }

  # 1. empty plans root -> {"efforts": []}, exit 0
  ROOT_EMPTY="$ST_TMP/empty"; mkdir -p "$ROOT_EMPTY"
  run_case "$ROOT_EMPTY"
  name=zero-efforts
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0: $ERR"
  elif [ "$OUT" != '{"efforts": []}' ]; then fail "$name" "unexpected stdout: $OUT"
  else pass "$name"; fi

  # 2. mixed root: working effort listed with frontier/open; charting listed;
  #    a `graduated` map skipped; a non-effort dir ignored.
  ROOT="$ST_TMP/mixed"; mkdir -p "$ROOT/not-an-effort"
  mk_map "$ROOT/alpha" working
  mk_ticket "$ROOT/alpha" ticket-01-first open '[]'
  mk_ticket "$ROOT/alpha" ticket-02-second open '[ticket-01]'
  mk_map "$ROOT/beta" charting
  mk_ticket "$ROOT/beta" ticket-01-seed open '[]'
  mk_map "$ROOT/gamma" graduated
  mk_ticket "$ROOT/gamma" ticket-01-done resolved '[]'
  run_case "$ROOT"
  name=mixed-root
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0: $ERR"
  elif ! is_valid_json "$OUT"; then fail "$name" "stdout is not valid JSON: $OUT"
  elif ! contains "$OUT" '{"slug": "alpha", "status": "working", "frontier": ["ticket-01-first"], "open": 2, "converged": false, "stale_claims": []}'; then
    fail "$name" "alpha entry wrong: $OUT"
  elif ! contains "$OUT" '"slug": "beta", "status": "charting"'; then fail "$name" "charting effort not listed: $OUT"
  elif contains "$OUT" '"gamma"'; then fail "$name" "non-active map listed: $OUT"
  else pass "$name"; fi

  # 3. degrade-not-block: a malformed effort yields an error entry AND the
  #    healthy sibling is still reported (scan continues).
  ROOT_DEG="$ST_TMP/degraded"
  mk_map "$ROOT_DEG/aaa-broken" working          # no tickets -> sibling exits 2
  mk_map "$ROOT_DEG/zzz-healthy" working
  mk_ticket "$ROOT_DEG/zzz-healthy" ticket-01-live open '[]'
  run_case "$ROOT_DEG"
  name=degrade-not-block
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0 (a broken effort killed the scan): $ERR"
  elif ! is_valid_json "$OUT"; then fail "$name" "stdout is not valid JSON: $OUT"
  elif ! contains "$OUT" '"slug": "aaa-broken", "status": "working", "error":'; then
    fail "$name" "broken effort not reported as an error entry: $OUT"
  elif ! contains "$OUT" '"slug": "zzz-healthy", "status": "working", "frontier": ["ticket-01-live"]'; then
    fail "$name" "healthy effort dropped after a broken one: $OUT"
  else pass "$name"; fi

  # 4. converged effort: converged true, empty frontier, open 0
  ROOT_CONV="$ST_TMP/conv"
  mk_map "$ROOT_CONV/done" working
  mk_ticket "$ROOT_CONV/done" ticket-01-done resolved '[]'
  run_case "$ROOT_CONV"
  name=converged
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0: $ERR"
  elif ! contains "$OUT" '"frontier": [], "open": 0, "converged": true, "stale_claims": []'; then
    fail "$name" "converged shape wrong: $OUT"
  else pass "$name"; fi

  # 5. stale claim + claimed ticket: claim counts toward `open`, is absent from
  #    `frontier`, and surfaces verbatim in `stale_claims` (sibling-computed).
  ROOT_STALE="$ST_TMP/stale"
  mk_map "$ROOT_STALE/held" working
  mk_ticket "$ROOT_STALE/held" ticket-01-held open '[]' session-dead 2026-07-01
  run_case "$ROOT_STALE"
  name=stale-claim
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0: $ERR"
  elif ! contains "$OUT" '"frontier": [], "open": 1, "converged": false, "stale_claims": ["ticket-01-held"]'; then
    fail "$name" "stale-claim shape wrong: $OUT"
  else pass "$name"; fi

  # 6. read-only: the plans root is byte-identical across a scan
  name=read-only
  hash_dir() { find "$1" -type f -exec md5sum {} \; | LC_ALL=C sort | md5sum; }
  before="$(hash_dir "$ROOT")"
  run_case "$ROOT"
  after="$(hash_dir "$ROOT")"
  if [ "$before" != "$after" ]; then fail "$name" "plans root mutated ($before != $after)"
  else pass "$name"; fi

  # 7. fail-close: a missing plans root -> exit 2 + stderr
  run_case "$ST_TMP/does-not-exist-$$"
  name=fail-close-missing-root
  if [ "$RC" -ne 2 ]; then fail "$name" "exit $RC != 2"
  elif [ -z "$ERR" ]; then fail "$name" "expected non-empty stderr"
  else pass "$name"; fi

  # 8. malformed map frontmatter -> error entry, not a dead scan
  ROOT_BADMAP="$ST_TMP/badmap"; mkdir -p "$ROOT_BADMAP/broken-map/wayfind"
  printf 'no frontmatter here\n' > "$ROOT_BADMAP/broken-map/wayfind/map.md"
  run_case "$ROOT_BADMAP"
  name=malformed-map
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0: $ERR"
  elif ! contains "$OUT" '{"slug": "broken-map", "error":'; then fail "$name" "malformed map not reported: $OUT"
  else pass "$name"; fi

  # 9. regression: a ticket that is open + dep-unsatisfied + claimed appears in
  #    BOTH the sibling's `blocked` and `claimed` arrays — deriving `open` from
  #    them counted it twice (reported 3, truth 2).
  ROOT_DBL="$ST_TMP/double"
  mk_map "$ROOT_DBL/dbl" working
  mk_ticket "$ROOT_DBL/dbl" ticket-01-first open '[]'
  mk_ticket "$ROOT_DBL/dbl" ticket-02-held open '[ticket-01]' session-x
  run_case "$ROOT_DBL"
  name=blocked-and-claimed-not-double-counted
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0: $ERR"
  elif ! contains "$OUT" '"frontier": ["ticket-01-first"], "open": 2, "converged": false'; then
    fail "$name" "expected open 2 (ticket counted once): $OUT"
  else pass "$name"; fi

  # 10. regression: a comma inside a ticket basename inflated the count when
  #     `open` was text-sliced out of the sibling's JSON (reported 2, truth 1).
  ROOT_COMMA="$ST_TMP/comma"
  mk_map "$ROOT_COMMA/comma" working
  mk_ticket "$ROOT_COMMA/comma" 'ticket-01-a,b' open '[]'
  run_case "$ROOT_COMMA"
  name=comma-in-basename
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0: $ERR"
  elif ! is_valid_json "$OUT"; then fail "$name" "stdout is not valid JSON: $OUT"
  elif ! contains "$OUT" '"open": 1'; then fail "$name" "expected open 1: $OUT"
  else pass "$name"; fi

  # 11. degrade-not-block: map.md present as a DIRECTORY becomes an error entry
  #     and the healthy sibling effort is still reported (scan continues).
  ROOT_MAPDIR="$ST_TMP/mapdir"
  mkdir -p "$ROOT_MAPDIR/aaa-mapdir/wayfind/map.md"
  mk_map "$ROOT_MAPDIR/zzz-healthy" working
  mk_ticket "$ROOT_MAPDIR/zzz-healthy" ticket-01-live open '[]'
  run_case "$ROOT_MAPDIR"
  name=map-is-a-directory
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0 (an unreadable map killed the scan): $ERR"
  elif ! is_valid_json "$OUT"; then fail "$name" "stdout is not valid JSON: $OUT"
  elif ! contains "$OUT" '{"slug": "aaa-mapdir", "error":'; then
    fail "$name" "unreadable map not reported as an error entry: $OUT"
  elif ! contains "$OUT" '"slug": "zzz-healthy", "status": "working", "frontier": ["ticket-01-live"], "open": 1'; then
    fail "$name" "healthy effort dropped after an unreadable map: $OUT"
  else pass "$name"; fi

  if [ "$st_fail" -eq 0 ]; then
    printf '\nself-test: ALL PASS (WAYFIND_NOW=%s)\n' "$WAYFIND_NOW"
    exit 0
  fi
  printf '\nself-test: %d case(s) FAILED\n' "$st_fail" >&2
  exit 1
fi

# --- argument handling ------------------------------------------------------
[ $# -eq 1 ] || die "usage: $PROG <plans-root>"
PLANS_ROOT="$1"
[ -d "$PLANS_ROOT" ] || die "plans root not found: $PLANS_ROOT"

# Resolve the sibling frontier script relative to THIS script, never cwd — it is
# the sole computer of convergence; this script never re-implements it.
src="${BASH_SOURCE[0]}"
while [ -h "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"; case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$src")" && pwd)"
FRONTIER="$SCRIPT_DIR/wayfind-frontier.sh"

# --- scan -------------------------------------------------------------------
shopt -s nullglob
MAPS=("$PLANS_ROOT"/*/wayfind/map.md)
shopt -u nullglob

# lexicographic order so the listing is deterministic
if [ "${#MAPS[@]}" -gt 0 ]; then
  mapfile -t MAPS < <(printf '%s\n' "${MAPS[@]}" | LC_ALL=C sort)
fi

FERR="$(mktemp "${TMPDIR:-/tmp}/wf_status_err.XXXXXX")"
trap 'rm -f "$FERR"' EXIT

entries=()

for map in "${MAPS[@]}"; do
  # Keep the effort dir as the caller wrote it (no symlink resolution) so the
  # slug is the plans-root entry name the user will type back at /wayfind.
  effort_dir="$(dirname "$(dirname "$map")")"
  slug="$(basename "$effort_dir")"
  slug_j="$(json_escape "$slug")"

  if ! map_status "$map"; then
    entries+=("{\"slug\": \"$slug_j\", \"error\": \"malformed map frontmatter: $(json_escape "$map")\"}")
    continue
  fi

  # Only ACTIVE efforts are discovery targets. Anything else (graduated,
  # abandoned, an unrecognised value) is silently out of scope for a resume list.
  case "$M_STATUS" in
    working|charting) ;;
    *) continue ;;
  esac
  status_j="$(json_escape "$M_STATUS")"

  # Sole computer of convergence — shelled out to, never re-implemented.
  set +e
  fjson="$(bash "$FRONTIER" "$effort_dir" 2>"$FERR")"; frc=$?
  set -e
  ferr="$(tr '\n' ' ' < "$FERR" 2>/dev/null || true)"
  ferr="$(trim "$ferr")"

  if [ "$frc" -ne 0 ]; then
    entries+=("{\"slug\": \"$slug_j\", \"status\": \"$status_j\", \"error\": \"$(json_escape "${ferr:-wayfind-frontier.sh exited $frc}")\"}")
    continue
  fi

  f_inner="$(slice_between "$fjson" '"frontier": [' ']' || true)"
  s_inner="$(slice_between "$fjson" '"stale_claims": [' ']' || true)"

  case "$fjson" in
    *'"converged": true'*)  converged=true ;;
    *'"converged": false'*) converged=false ;;
    *) entries+=("{\"slug\": \"$slug_j\", \"status\": \"$status_j\", \"error\": \"unparseable frontier output\"}"); continue ;;
  esac

  # `open` is counted DIRECTLY from the ticket files — the sibling's arrays are
  # not a partition (blocked ∩ claimed ≠ ∅), so deriving from them double-counts.
  open="$(count_open_tickets "$effort_dir")"

  entries+=("{\"slug\": \"$slug_j\", \"status\": \"$status_j\", \"frontier\": [$(trim "$f_inner")], \"open\": $open, \"converged\": $converged, \"stale_claims\": [$(trim "$s_inner")]}")
done

join() { local sep="$1"; shift; local out="" first=1 x
  for x in "$@"; do
    if [ "$first" -eq 1 ]; then out="$x"; first=0; else out="$out$sep$x"; fi
  done
  printf '%s' "$out"
}

printf '{"efforts": [%s]}\n' "$(join ', ' "${entries[@]}")"

exit 0
