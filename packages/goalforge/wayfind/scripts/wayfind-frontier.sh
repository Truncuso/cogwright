#!/usr/bin/env bash
#
# wayfind-frontier.sh — deterministic, read-only frontier computation for a
# wayfind effort. Reads plans/<effort>/wayfind/ticket-*.md frontmatter and emits
# a pinned JSON shape describing the decision frontier.
#
# Contract (AUTHORITATIVE): SKILL.md §"work flow" — the inlined CLI contract:
#           stdout JSON keys, their semantics, and the exit mapping.
# Provenance note only, NOT an authority (it ships inside the plugin where no
#           consumer can resolve it): ~/.claude/plans/_archived/wayfind/spec.md
#           §"wayfind-frontier.sh CLI contract".
#
#   wayfind-frontier.sh <effort-dir>   # dir containing wayfind/ticket-*.md
#   wayfind-frontier.sh --self-test    # fixtures self-test
#
# READ-ONLY: never writes into the effort dir. No network. No sed -i / mv /
# redirects into fixtures. Temp files (if any) live under mktemp locations only.
#
# Exit codes:
#   0  valid state — a computed frontier (any state incl. converged), or
#      --self-test with every case passing
#   1  --self-test with one or more failing cases
#   2  fail-close: usage / structural failure (missing dir, no wayfind/, zero
#      tickets, duplicate ticket number, dangling depends_on target) OR
#      malformed ticket frontmatter (stderr names the offending file)
#
set -euo pipefail

PROG="$(basename "$0")"

die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 2; }
warn() { printf '%s: %s\n' "$PROG" "$*" >&2; }

# JSON-escape an arbitrary string for safe interpolation into a JSON string
# literal: backslash, double-quote, and all control chars (< 0x20). Applied to
# EVERY interpolated string (ticket basenames, claimed_by, dep tokens) so a
# quoted/embedded metacharacter can never break the emitted JSON.
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

# Strip a single layer of surrounding matching quotes (single or double) from a
# YAML scalar. A lone quote (length-1 token) is left untouched.
unquote() {
  local s="$1"
  case "$s" in
    '"'*'"') s="${s#\"}"; s="${s%\"}" ;;
    "'"*"'") s="${s#\'}"; s="${s%\'}" ;;
  esac
  printf '%s' "$s"
}

# --- --self-test: bundle fixtures + assert every facet ----------------------
if [ "${1:-}" = "--self-test" ]; then
  # Resolve fixture root relative to THIS script, never cwd.
  src="${BASH_SOURCE[0]}"
  while [ -h "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"; case "$src" in /*) ;; *) src="$dir/$src" ;; esac
  done
  SCRIPT_DIR="$(cd -P "$(dirname "$src")" && pwd)"
  FIXROOT="$SCRIPT_DIR/../evals/fixtures/frontier"
  SELF="$SCRIPT_DIR/$(basename "$src")"

  # Pin reference "now" to the fixture date unless the env already sets it,
  # so the 7-day stale boundary is never wall-clock dependent.
  export WAYFIND_NOW="${WAYFIND_NOW:-2026-07-16}"

  # Single temp file for captured stderr, cleaned up on exit (no PID litter).
  ST_ERRFILE="$(mktemp "${TMPDIR:-/tmp}/wf_self_err.XXXXXX")"
  trap 'rm -f "$ST_ERRFILE"' EXIT

  # Detect a JSON validator once (python3 preferred; else strict grep fallback).
  HAVE_PY=0
  if command -v python3 >/dev/null 2>&1; then HAVE_PY=1; fi

  st_fail=0
  fail() { printf 'FAIL [%s]: %s\n' "$1" "$2" >&2; st_fail=$((st_fail + 1)); }
  pass() { printf 'ok   [%s]\n' "$1"; }

  # run_case <fixture-subpath> -> sets RC, OUT, ERR
  run_case() {
    local target="$1"
    set +e
    OUT="$(bash "$SELF" "$target" 2>"$ST_ERRFILE")"; RC=$?
    set -e
    ERR="$(cat "$ST_ERRFILE" 2>/dev/null || true)"
  }
  contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac }

  # is_valid_json <string> -> 0 iff parses as JSON (python3, else strict grep)
  is_valid_json() {
    if [ "$HAVE_PY" -eq 1 ]; then
      printf '%s' "$1" | python3 -c 'import sys,json; json.loads(sys.stdin.read())' >/dev/null 2>&1
    else
      # Fallback: reject the finding-2 unescaped-quote collision ("" "") and
      # require all five contract keys to be present.
      case "$1" in
        *'""'*'""'*) return 1 ;;
      esac
      contains "$1" '"frontier"' && contains "$1" '"blocked"' \
        && contains "$1" '"claimed"' && contains "$1" '"stale_claims"' \
        && contains "$1" '"converged"'
    fi
  }

  # 1. frontier-basic: ticket-02-design in frontier; converged false; exit 0
  run_case "$FIXROOT/frontier-basic"
  name=frontier-basic
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0"
  elif ! contains "$OUT" '"frontier": ["ticket-02-design"]'; then fail "$name" "ticket-02-design not sole frontier: $OUT"
  elif ! contains "$OUT" '"converged": false'; then fail "$name" "converged not false: $OUT"
  else pass "$name"; fi

  # 2. out-of-scope-dep: ticket-02-followup in frontier (dep via out-of-scope)
  run_case "$FIXROOT/out-of-scope-dep"
  name=out-of-scope-dep
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0"
  elif ! contains "$OUT" '"ticket-02-followup"'; then fail "$name" "followup not in frontier: $OUT"
  elif contains "$OUT" '"frontier": []'; then fail "$name" "frontier unexpectedly empty: $OUT"
  else pass "$name"; fi

  # 3. converged: converged true; frontier empty; exit 0
  run_case "$FIXROOT/converged"
  name=converged
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0"
  elif ! contains "$OUT" '"converged": true'; then fail "$name" "converged not true: $OUT"
  elif ! contains "$OUT" '"frontier": []'; then fail "$name" "frontier not empty: $OUT"
  else pass "$name"; fi

  # 4. claimed-active: claimed obj age_days 2; stale empty; converged false
  run_case "$FIXROOT/claimed-active"
  name=claimed-active
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0"
  elif ! contains "$OUT" '"ticket": "ticket-02-active", "by": "session-abc123", "age_days": 2'; then fail "$name" "expected active claim age_days 2: $OUT"
  elif ! contains "$OUT" '"stale_claims": []'; then fail "$name" "stale_claims not empty: $OUT"
  elif ! contains "$OUT" '"converged": false'; then fail "$name" "converged not false: $OUT"
  else pass "$name"; fi

  # 5. claimed-stale: stale_claims contains ticket-02-stale; stderr WARN non-empty
  run_case "$FIXROOT/claimed-stale"
  name=claimed-stale
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0"
  elif ! contains "$OUT" '"stale_claims": ["ticket-02-stale"]'; then fail "$name" "ticket-02-stale not in stale_claims: $OUT"
  elif [ -z "$ERR" ]; then fail "$name" "expected non-empty stderr WARN"
  else pass "$name"; fi

  # 6. blocked-dependent: blocked obj {ticket, waiting_on} shape
  run_case "$FIXROOT/blocked-dependent"
  name=blocked-dependent
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0"
  elif ! contains "$OUT" '{"ticket": "ticket-02-blocked", "waiting_on": ["ticket-01"]}'; then fail "$name" "blocked object shape wrong: $OUT"
  else pass "$name"; fi

  # 7. read-only: md5 of frontier-basic/wayfind unchanged across a run
  name=read-only
  hash_dir() { find "$1" -type f -exec md5sum {} \; | LC_ALL=C sort | md5sum; }
  before="$(hash_dir "$FIXROOT/frontier-basic/wayfind")"
  run_case "$FIXROOT/frontier-basic"
  after="$(hash_dir "$FIXROOT/frontier-basic/wayfind")"
  if [ "$before" != "$after" ]; then fail "$name" "wayfind dir mutated ($before != $after)"
  else pass "$name"; fi

  # 8. malformed: exit 2 AND stderr names the offending file
  run_case "$FIXROOT/malformed"
  name=malformed
  if [ "$RC" -ne 2 ]; then fail "$name" "exit $RC != 2"
  elif ! contains "$ERR" 'ticket-01-broken.md'; then fail "$name" "stderr does not name offending file: $ERR"
  else pass "$name"; fi

  # 9. fail-close: nonexistent / no-wayfind-subdir / empty-map -> exit 2 + stderr
  for fc in "$FIXROOT/does-not-exist-$$" "$FIXROOT/no-wayfind-subdir" "$FIXROOT/empty-map"; do
    run_case "$fc"
    name="fail-close:$(basename "$fc")"
    if [ "$RC" -ne 2 ]; then fail "$name" "exit $RC != 2"
    elif [ -z "$ERR" ]; then fail "$name" "expected non-empty stderr"
    else pass "$name"; fi
  done

  # 10. quoted-deps: quoted flow dep (["ticket-01"]) resolves -> dependent in
  #     frontier; a single-quoted claimed_by with an embedded double-quote is
  #     JSON-escaped -> stdout is valid JSON (regression: findings 1 + 2).
  run_case "$FIXROOT/quoted-deps"
  name=quoted-deps
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0: $ERR"
  elif ! contains "$OUT" '"ticket-02-dependent"'; then fail "$name" "quoted dep did not resolve; dependent not in frontier: $OUT"
  elif ! is_valid_json "$OUT"; then fail "$name" "stdout is not valid JSON: $OUT"
  else pass "$name"; fi

  # 11. dup-nn: two tickets sharing ticket-02 -> exit 2, stderr names both
  #     (regression: finding 3).
  run_case "$FIXROOT/dup-nn"
  name=dup-nn
  if [ "$RC" -ne 2 ]; then fail "$name" "exit $RC != 2"
  elif ! { contains "$ERR" 'ticket-02-alpha.md' && contains "$ERR" 'ticket-02-beta.md'; }; then
    fail "$name" "stderr does not name both duplicates: $ERR"
  else pass "$name"; fi

  # 12. glob-dep: depends_on [*] -> malformed exit 2, stderr names the file
  #     (regression: finding 4 — no pathname expansion of dep tokens).
  run_case "$FIXROOT/glob-dep"
  name=glob-dep
  if [ "$RC" -ne 2 ]; then fail "$name" "exit $RC != 2"
  elif ! contains "$ERR" 'ticket-01-glob.md'; then fail "$name" "stderr does not name offending file: $ERR"
  else pass "$name"; fi

  # 13. resolved-stale-claim: a RESOLVED ticket carrying an aged claim stamp is
  #     neither `claimed` nor `stale_claims`, and emits no stderr WARN (the
  #     claim block is gated on status == open).
  run_case "$FIXROOT/resolved-stale-claim"
  name=resolved-stale-claim
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0: $ERR"
  elif ! contains "$OUT" '"stale_claims": []'; then fail "$name" "resolved ticket reported stale: $OUT"
  elif ! contains "$OUT" '"claimed": []'; then fail "$name" "resolved ticket reported claimed: $OUT"
  elif [ -n "$ERR" ]; then fail "$name" "expected empty stderr, got: $ERR"
  elif ! contains "$OUT" '"frontier": ["ticket-02-live"]'; then fail "$name" "open dependent not in frontier: $OUT"
  else pass "$name"; fi

  # 14. dangling-dep: depends_on target with no matching ticket-NN -> exit 2,
  #     stderr names the referencing file AND the unresolvable token.
  run_case "$FIXROOT/dangling-dep"
  name=dangling-dep
  if [ "$RC" -ne 2 ]; then fail "$name" "exit $RC != 2 (silent deadlock): $OUT"
  elif ! { contains "$ERR" 'ticket-01-orphan.md' && contains "$ERR" 'ticket-99'; }; then
    fail "$name" "stderr does not name both the file and the token: $ERR"
  else pass "$name"; fi

  # 15. pad-mismatch: depends_on [ticket-1] against ticket-01-base.md -> the
  #     zero-padding rule violation is a dangling ref, not a silent deadlock.
  run_case "$FIXROOT/pad-mismatch"
  name=pad-mismatch
  if [ "$RC" -ne 2 ]; then fail "$name" "exit $RC != 2 (silent deadlock): $OUT"
  elif ! { contains "$ERR" 'ticket-02-unpadded-ref.md' && contains "$ERR" 'ticket-1 '; }; then
    fail "$name" "stderr does not name both the file and the unpadded token: $ERR"
  else pass "$name"; fi

  # 16. blocked-and-claimed: an open ticket with BOTH unsatisfied deps and a
  #     claim stamp appears in BOTH `blocked` (with its waiting_on edge — the
  #     diagnostic that keeps dep-cycles through claimed nodes traceable) AND
  #     `claimed`. The overlap is INTENTIONAL: the arrays are not a partition
  #     (SKILL.md §work flow "at least one").
  run_case "$FIXROOT/blocked-and-claimed"
  name=blocked-and-claimed
  if [ "$RC" -ne 0 ]; then fail "$name" "exit $RC != 0: $ERR"
  elif ! contains "$OUT" '"waiting_on": ["ticket-01"]'; then fail "$name" "waiting_on edge lost for claimed+blocked ticket: $OUT"
  elif ! contains "$OUT" '"blocked": [{"ticket": "ticket-02-dep"'; then fail "$name" "ticket-02-dep missing from blocked: $OUT"
  elif ! contains "$OUT" '"by": "session-abc123"'; then fail "$name" "ticket-02-dep missing from claimed: $OUT"
  elif ! contains "$OUT" '"frontier": ["ticket-01-base"]'; then fail "$name" "frontier wrong: $OUT"
  else pass "$name"; fi

  if [ "$st_fail" -eq 0 ]; then
    printf '\nself-test: ALL PASS (WAYFIND_NOW=%s)\n' "$WAYFIND_NOW"
    exit 0
  fi
  printf '\nself-test: %d case(s) FAILED\n' "$st_fail" >&2
  exit 1
fi

# --- argument handling ------------------------------------------------------
[ $# -eq 1 ] || die "usage: $PROG <effort-dir>"
EFFORT_DIR="$1"

[ -d "$EFFORT_DIR" ] || die "effort dir not found: $EFFORT_DIR"
WAYFIND_DIR="$EFFORT_DIR/wayfind"
[ -d "$WAYFIND_DIR" ] || die "no wayfind/ subdir under: $EFFORT_DIR"

# Reference "now" — env-injectable so the later self-test is wall-clock free.
NOW="${WAYFIND_NOW:-$(date +%F)}"
NOW_EPOCH="$(date -u -d "$NOW" +%s 2>/dev/null)" \
  || die "invalid WAYFIND_NOW date: $NOW (expected YYYY-MM-DD)"

STALE_DAYS=7   # hard constant (v1), not configurable

# --- enumerate tickets ------------------------------------------------------
shopt -s nullglob
TICKET_FILES=("$WAYFIND_DIR"/ticket-*.md)
shopt -u nullglob
[ "${#TICKET_FILES[@]}" -gt 0 ] || die "no ticket-*.md files in: $WAYFIND_DIR"

# --- parse one ticket's frontmatter -----------------------------------------
# Sets P_STATUS P_TYPE P_DEPS (space-separated ticket-NN) P_CBY P_CAT.
# Returns 1 on malformed frontmatter.
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

parse_ticket() {
  local file="$1"
  P_STATUS=""; P_TYPE=""; P_DEPS=""; P_CBY=""; P_CAT=""
  local line first=1 in_fm=0 closed=0 deps_raw=""

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$first" -eq 1 ]; then
      first=0
      if [ "$(trim "$line")" = "---" ]; then in_fm=1; continue; else return 1; fi
    fi
    if [ "$in_fm" -eq 1 ]; then
      if [ "$(trim "$line")" = "---" ]; then closed=1; break; fi
      case "$line" in
        status:*)      P_STATUS="$(trim "${line#status:}")" ;;
        ticket_type:*) P_TYPE="$(trim "${line#ticket_type:}")" ;;
        depends_on:*)  deps_raw="$(trim "${line#depends_on:}")" ;;
        claimed_by:*)  P_CBY="$(trim "${line#claimed_by:}")" ;;
        claimed_at:*)  P_CAT="$(trim "${line#claimed_at:}")" ;;
      esac
    fi
  done < "$file"

  # unterminated frontmatter -> malformed
  [ "$closed" -eq 1 ] || return 1

  # status must be a known enum value
  case "$P_STATUS" in
    open|resolved|out-of-scope) ;;
    *) return 1 ;;
  esac

  # depends_on must be a well-formed [..] list
  case "$deps_raw" in
    "["*"]") ;;
    *) return 1 ;;
  esac
  local inner="${deps_raw#[}"; inner="${inner%]}"
  inner="${inner//,/ }"
  # read -ra splits on whitespace WITHOUT pathname expansion, so a glob token
  # (e.g. depends_on: [*]) can never fabricate deps from the cwd listing.
  local -a dep_tokens=()
  IFS=' ' read -ra dep_tokens <<< "$inner"
  local d
  for d in "${dep_tokens[@]}"; do
    d="$(trim "$d")"
    d="$(unquote "$d")"
    [ -n "$d" ] || continue
    # every dep must be a bare ticket-number reference; anything else (a glob
    # survivor, a stray token) is malformed frontmatter.
    [[ "$d" =~ ^ticket-[0-9]+$ ]] || return 1
    P_DEPS="${P_DEPS:+$P_DEPS }$d"
  done

  # normalize null-ish claim fields, stripping any surrounding quotes first
  P_CBY="$(unquote "$P_CBY")"
  P_CAT="$(unquote "$P_CAT")"
  case "$P_CBY" in null|"") P_CBY="" ;; esac
  case "$P_CAT" in null|"") P_CAT="" ;; esac

  # claimed_at (when present) must be exactly YYYY-MM-DD — a time-of-day
  # component would shift the 7-day stale boundary. Contract pins the date form.
  if [ -n "$P_CAT" ]; then
    [[ "$P_CAT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  fi
  return 0
}

# --- first pass: parse every ticket, index by basename & nn -----------------
declare -A ST DEPS CBY CAT FILE
declare -A NN_STATUS NN_FILE
BASES=()

for f in "${TICKET_FILES[@]}"; do
  base="$(basename "$f" .md)"
  if ! parse_ticket "$f"; then
    die "malformed frontmatter: $f"
  fi
  rest="${base#ticket-}"; num="${rest%%-*}"; nn="ticket-$num"
  # a duplicate ticket number makes the dep map ambiguous (last-writer-wins
  # would silently corrupt resolution) — fail-close, naming both files.
  if [ -n "${NN_FILE[$nn]:-}" ]; then
    die "duplicate ticket number $nn: ${NN_FILE[$nn]} and $f (inconsistent map)"
  fi
  NN_FILE["$nn"]="$f"
  BASES+=("$base")
  FILE["$base"]="$f"
  ST["$base"]="$P_STATUS"
  DEPS["$base"]="$P_DEPS"
  CBY["$base"]="$P_CBY"
  CAT["$base"]="$P_CAT"
  NN_STATUS["$nn"]="$P_STATUS"
done

# --- dangling-dep pass: every depends_on token must name an existing ticket --
# Runs AFTER the whole index is built, so a legitimate FORWARD reference
# (ticket-02 depending on ticket-07) resolves normally. A token with no
# matching ticket-NN — a typo, a deleted ticket, or a zero-padding mismatch
# (ticket-1 vs ticket-01) — would otherwise deadlock the map forever at exit 0:
# permanently unsatisfied, never converged, never reported. Same fail-close
# class as duplicate-NN.
for base in "${BASES[@]}"; do
  for dep in ${DEPS[$base]}; do
    [ -n "${NN_STATUS[$dep]:-}" ] \
      || die "dangling depends_on: ${FILE[$base]} references $dep (no matching ticket-NN)"
  done
done

# dep satisfied iff the matching ticket is resolved or out-of-scope
dep_satisfied() {
  local s="${NN_STATUS[$1]:-}"
  [ "$s" = "resolved" ] || [ "$s" = "out-of-scope" ]
}

# --- second pass: compute frontier / blocked / claimed / stale --------------
frontier_items=()
blocked_items=()
claimed_items=()
stale_items=()
open_count=0

# iterate in lexicographic order so arrays are deterministic
mapfile -t SORTED_BASES < <(printf '%s\n' "${BASES[@]}" | LC_ALL=C sort)

for base in "${SORTED_BASES[@]}"; do
  status="${ST[$base]}"
  [ "$status" = "open" ] && open_count=$((open_count + 1))

  # unsatisfied deps (for both frontier gating and blocked diagnostics)
  unsat=()
  for dep in ${DEPS[$base]}; do
    dep_satisfied "$dep" || unsat+=("$dep")
  done

  claimed_by="${CBY[$base]}"
  base_j="$(json_escape "$base")"

  # frontier: open AND all deps satisfied AND unclaimed
  if [ "$status" = "open" ] && [ "${#unsat[@]}" -eq 0 ] && [ -z "$claimed_by" ]; then
    frontier_items+=("\"$base_j\"")
  fi

  # blocked: open AND >=1 unsatisfied dep (human-diagnostic only). DELIBERATELY
  # not gated on claim state: a claimed ticket with unsatisfied deps appears in
  # BOTH blocked and claimed — the waiting_on edge is diagnostic information
  # (dep-cycles through claimed nodes stay traceable); dropping it would make a
  # claimed-ticket deadlock indistinguishable from healthy live work. The
  # arrays overlap by design; consumers must not treat them as a partition.
  if [ "$status" = "open" ] && [ "${#unsat[@]}" -gt 0 ]; then
    mapfile -t unsat_sorted < <(printf '%s\n' "${unsat[@]}" | LC_ALL=C sort)
    waiting=""
    for w in "${unsat_sorted[@]}"; do
      waiting="${waiting:+$waiting, }\"$(json_escape "$w")\""
    done
    blocked_items+=("{\"ticket\": \"$base_j\", \"waiting_on\": [$waiting]}")
  fi

  # claimed: OPEN ticket with claimed_by set (claim is stamp-only, so a claimed
  # ticket is open by construction). Gating on status keeps a leftover claim
  # stamp on a resolved/out-of-scope ticket out of `claimed` and `stale_claims`
  # — otherwise a done ticket emits a false stale WARN forever.
  if [ "$status" = "open" ] && [ -n "$claimed_by" ]; then
    claimed_at="${CAT[$base]}"
    age=0
    if [ -n "$claimed_at" ]; then
      if cepoch="$(date -u -d "$claimed_at" +%s 2>/dev/null)"; then
        age=$(( (NOW_EPOCH - cepoch) / 86400 ))
      else
        die "malformed frontmatter: invalid claimed_at ($claimed_at) in $base"
      fi
    fi
    claimed_items+=("{\"ticket\": \"$base_j\", \"by\": \"$(json_escape "$claimed_by")\", \"age_days\": $age}")
    if [ "$age" -gt "$STALE_DAYS" ]; then
      stale_items+=("\"$base_j\"")
      warn "stale claim: $base held by $claimed_by for $age days (>$STALE_DAYS)"
    fi
  fi
done

# converged: zero open tickets (a claimed ticket is open ⇒ blocks convergence)
if [ "$open_count" -eq 0 ]; then converged=true; else converged=false; fi

# --- emit deterministic JSON ------------------------------------------------
join() { local sep="$1"; shift; local out="" first=1 x
  for x in "$@"; do
    if [ "$first" -eq 1 ]; then out="$x"; first=0; else out="$out$sep$x"; fi
  done
  printf '%s' "$out"
}

printf '{"frontier": [%s], "blocked": [%s], "claimed": [%s], "stale_claims": [%s], "converged": %s}\n' \
  "$(join ', ' "${frontier_items[@]}")" \
  "$(join ', ' "${blocked_items[@]}")" \
  "$(join ', ' "${claimed_items[@]}")" \
  "$(join ', ' "${stale_items[@]}")" \
  "$converged"

exit 0
