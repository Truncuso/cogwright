#!/usr/bin/env bash
# goalforge-harness-check.sh — declare-or-degrade check for harness primitives.
#
# Usage: goalforge-harness-check.sh <availability-file>
#
# <availability-file> holds `<primitive>=present|absent` lines (`#` comments and
# blank lines skipped). Primitives and their class come from the table in
# references/harness-dependencies.md. Toolchain primitives are always probed: an
# observed absence wins, and a declaration may only force `absent` (never mask a
# missing tool). Session tools cannot be observed from a script, so they come
# from the declaration and an undeclared one counts as absent (never a silent
# pass). A repeated key is a usage error.
#
# Exit: 0 clean, or WARN lines for absent degradable primitives (stderr)
#       1 a hard-required primitive is absent (FAIL line names it)
#       2 usage error, unreadable file, unknown primitive, malformed or repeated line
set -euo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TABLE="$SD/../references/harness-dependencies.md"

die() { printf 'usage error: %s\n' "$*" >&2; exit 2; }

[[ $# -eq 1 ]] || die "goalforge-harness-check.sh <availability-file>"
AVAIL="$1"
[[ -r "$AVAIL" ]] || die "cannot read availability file: $AVAIL"
[[ -r "$TABLE" ]] || die "cannot read $TABLE"

# Table rows -> primitive<TAB>kind<TAB>class<TAB>needs<TAB>degrade
rows="$(awk -F'|' '
  function trim(s) { gsub(/^[ \t`]+|[ \t`]+$/, "", s); return s }
  NF == 8 && (trim($5) == "hard-required" || trim($5) == "degradable") {
    printf "%s\t%s\t%s\t%s\t%s\n", trim($2), trim($3), trim($5), trim($6), trim($7)
  }' "$TABLE")"
[[ -n "$rows" ]] || die "no table rows parsed from $TABLE"

declare -A DECL=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" || "$line" == \#* ]] && continue
  [[ "$line" == *=* ]] || die "malformed line (want <primitive>=present|absent): $line"
  key="${line%=*}"; val="${line##*=}"
  key="${key%"${key##*[![:space:]]}"}"; val="${val#"${val%%[![:space:]]*}"}"
  [[ -n "$key" && ( "$val" == present || "$val" == absent ) ]] \
    || die "malformed line (want <primitive>=present|absent): $line"
  grep -qxF -- "$key" < <(awk -F'\t' '$4 == "-" {print $1}' <<<"$rows") \
    || die "unknown primitive in availability file: $key"
  [[ -z "${DECL[$key]:-}" ]] || die "repeated primitive in availability file: $key"
  DECL["$key"]="$val"
done <"$AVAIL"

probe() {  # probe <primitive> -> present|absent
  case "$1" in
    PyYAML) python3 -c 'import yaml' >/dev/null 2>&1 && echo present || echo absent ;;
    *) command -v "$1" >/dev/null 2>&1 && echo present || echo absent ;;
  esac
}

declare -A STATE=()
rc=0
while IFS=$'\t' read -r prim kind class needs degrade; do
  [[ "$needs" == "-" ]] || continue
  if [[ "$kind" == toolchain ]]; then
    st="$(probe "$prim")"
    if [[ "${DECL[$prim]:-}" == absent ]]; then st=absent
    elif [[ "${DECL[$prim]:-}" == present && "$st" == absent ]]; then
      printf 'note: %s declared present but the probe observed it absent\n' "$prim" >&2
    fi
  elif [[ -n "${DECL[$prim]:-}" ]]; then st="${DECL[$prim]}"
  else st=absent; printf 'note: %s undeclared, counted as absent\n' "$prim" >&2
  fi
  STATE["$prim"]="$st"
  [[ "$st" == absent ]] || continue
  if [[ "$class" == hard-required ]]; then
    printf 'FAIL: hard-required %s absent; breaches the minimum floor (Agent tool + goalforge-doctor.sh toolchain)\n' "$prim" >&2
    rc=1
  else
    printf 'WARN: %s absent; fallback: %s\n' "$prim" "$degrade" >&2
  fi
done <<<"$rows"

# Derived rows follow their Needs primitive.
while IFS=$'\t' read -r prim kind class needs degrade; do
  [[ "$needs" != "-" && "${STATE[$needs]:-}" == absent ]] || continue
  printf 'WARN: %s unavailable (needs %s); fallback: %s\n' "$prim" "$needs" "$degrade" >&2
done <<<"$rows"

[[ $rc -ne 0 ]] || echo "harness-check: ok"
exit $rc
