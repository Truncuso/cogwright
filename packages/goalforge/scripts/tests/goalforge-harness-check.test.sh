#!/usr/bin/env bash
# goalforge-harness-check.test.sh — wp-13 b1-b4: the harness dependency contract.
#
#   b1  every vocabulary primitive named in a stage SKILL.md or
#       dispatch-resolution.md has a row in references/harness-dependencies.md;
#       the ruled floor, the hard-required set and the two named fallbacks hold.
#   b2  scripts/goalforge-harness-check.sh exit codes per fixture environment,
#       run under a PATH shim so the outcome never depends on the host toolchain.
#   b3  execute/SKILL.md and dispatch-resolution.md mark every vocabulary
#       primitive they name and stay within the 125-line cap.
#   b4  the execute-entry invocation span sits before `## 2` and, extracted and
#       run, reproduces the b2 outcomes.
#
# Each check is a function over its inputs, so the live files and every
# known-bad copy run the identical code path. Known-bads are built in one
# mktemp -d from the live files; nothing is written elsewhere.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$SD/../.." && pwd)"
FIX="$PKG/evals/fixtures/harness"
CHECK="$PKG/scripts/goalforge-harness-check.sh"
VOCAB="$PKG/references/harness-primitives.txt"
TABLE="$PKG/references/harness-dependencies.md"
EXEC="$PKG/execute/SKILL.md"
DISP="$PKG/execute/references/dispatch-resolution.md"
DOCTOR="$PKG/scripts/goalforge-doctor.sh"
PTR='references/harness-dependencies.md'
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

vocab_names() { grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$'; }
# table_rows <table> -> primitive<TAB>kind<TAB>avail<TAB>class<TAB>needs<TAB>degrade
table_rows() {
  awk -F'|' 'function t(s){gsub(/^[ \t`]+|[ \t`]+$/,"",s);return s}
    NF==8 && (t($5)=="hard-required"||t($5)=="degradable"){
      printf "%s\t%s\t%s\t%s\t%s\t%s\n",t($2),t($3),t($4),t($5),t($6),t($7)}' "$1"
}
live_files() { ls "$PKG"/*/SKILL.md; echo "$DISP"; }

# make_env <dir> [--without <cmd>]... [--no-pyyaml]
# A PATH directory for the checker: real awk/grep/dirname/bash, stub exit-0
# toolchain commands, and a python3 that either passes `import yaml` (stub) or
# is the real interpreter with site-packages cut off (--no-pyyaml). A --without
# command is simply absent, so the probe observes it missing.
make_env() {
  local d="$1" c w noy=0; shift
  local -a without=()
  while [[ $# -gt 0 ]]; do
    case "$1" in --without) without+=("$2"); shift 2 ;; --no-pyyaml) noy=1; shift ;; *) shift ;; esac
  done
  mkdir -p "$d"
  for c in awk grep dirname bash; do ln -sf "$(command -v "$c")" "$d/$c"; done
  for c in git python3 jq flock timeout realpath tar; do
    for w in ${without+"${without[@]}"}; do [[ "$w" == "$c" ]] && continue 2; done
    if [[ $c == python3 && $noy -eq 1 ]]; then
      printf '#!/bin/sh\nexec "%s" -S -E "$@"\n' "$(command -v python3)" > "$d/$c"
    else
      printf '#!/bin/sh\nexit 0\n' > "$d/$c"
    fi
    chmod +x "$d/$c"
  done
}
make_env "$T/shim-full"
make_env "$T/shim-nojq" --without jq
make_env "$T/shim-noyaml" --no-pyyaml
# run_with <shim> <checker> <availability-file>...
run_with() { local sh="$1"; shift; env PATH="$sh" "$BASH" "$@" 2>&1; }

# check_b2 <checker> -> 0 when the checker honours the exit-code contract
check_b2() {
  local ck="$1" rc=0 out code
  chk() {  # chk <label> <want-code> <want-substring> <shim> <availability-file>
    out="$(run_with "$4" "$ck" "$5")"; code=$?
    [[ $code -eq $2 && "$out" == *"$3"* ]] || { echo "    $1: rc=$code want $2 ~ '$3'"; rc=1; }
  }
  chk "complete" 0 "harness-check: ok" "$T/shim-full" "$FIX/env-complete.txt"
  out="$(run_with "$T/shim-full" "$ck" "$FIX/env-complete.txt")"
  [[ "$out" != *WARN* ]] || { echo "    complete: unexpected WARN"; rc=1; }
  chk "missing degradable" 0 "WARN: Workflow tool absent; fallback: batching degrades to the C5 single owner" "$T/shim-full" "$FIX/env-missing-degradable.txt"
  out="$(run_with "$T/shim-full" "$ck" "$FIX/env-missing-degradable.txt")"
  [[ "$out" == *"admitted non-native implement"*"first native provider"* ]] || { echo "    no derived WARN after Workflow tool"; rc=1; }
  chk "missing hard-required" 1 "FAIL: hard-required Agent tool absent" "$T/shim-full" "$FIX/env-missing-hard.txt"
  out="$(run_with "$T/shim-full" "$ck" "$FIX/env-missing-hard.txt")"
  [[ "$out" == *"minimum floor"* ]] || { echo "    FAIL line lacks the floor"; rc=1; }
  chk "malformed line" 2 "malformed line" "$T/shim-full" "$FIX/env-malformed.txt"
  printf 'Agent tool=present\nNo Such Tool=present\n' > "$T/unknown.txt"
  chk "unknown primitive" 2 "unknown primitive" "$T/shim-full" "$T/unknown.txt"
  chk "duplicate key" 2 "repeated primitive" "$T/shim-full" "$FIX/env-duplicate.txt"
  command sed 's/^jq=present/jq=absent/' "$FIX/env-complete.txt" > "$T/no-jq.txt"
  chk "jq=absent forces absent" 1 "jq absent" "$T/shim-full" "$T/no-jq.txt"
  grep -v '^Agent tool' "$FIX/env-complete.txt" > "$T/undeclared.txt"
  chk "undeclared session tool" 1 "Agent tool absent" "$T/shim-full" "$T/undeclared.txt"
  # probe path: toolchain left to the probe, observed absence wins
  chk "probe: jq off PATH" 1 "hard-required jq absent" "$T/shim-nojq" "$FIX/env-session-only.txt"
  chk "probe: PyYAML missing" 1 "hard-required PyYAML absent" "$T/shim-noyaml" "$FIX/env-session-only.txt"
  chk "probe: all present" 0 "harness-check: ok" "$T/shim-full" "$FIX/env-session-only.txt"
  chk "declaration cannot mask absent jq" 1 "hard-required jq absent" "$T/shim-nojq" "$FIX/env-complete.txt"
  out="$(run_with "$T/shim-full" "$ck" 2>&1)"; code=$?
  [[ $code -eq 2 ]] || { echo "    no argument: rc=$code"; rc=1; }
  return $rc
}

# check_b1 <vocab> <table> <file>... -> 0 when the contract holds
check_b1() {
  local vocab="$1" table="$2"; shift 2
  local rc=0 n rows name hits=0 doctor_deps
  rows="$(table_rows "$table")"
  # ruled name floor, deriving the toolchain from the doctor, not from the vocab
  doctor_deps="$(sed -n 's/^DEPS=(\(.*\))/\1/p' "$DOCTOR")"
  for n in "Agent tool" "Workflow tool" AskUserQuestion PyYAML $doctor_deps; do
    vocab_names "$vocab" | grep -qxF -- "$n" || { echo "    vocabulary lacks ruled name: $n"; rc=1; }
  done
  # every session tool has at least one hit (non-empty assertion)
  for n in "Agent tool" "Workflow tool" AskUserQuestion; do
    grep -qwF -- "$n" "$@" 2>/dev/null || { echo "    no file names session tool: $n"; rc=1; }
  done
  # every hit has a row
  while IFS= read -r name; do
    grep -qwF -- "$name" "$@" 2>/dev/null || continue
    hits=$((hits+1))
    cut -f1 <<<"$rows" | grep -qxF -- "$name" || { echo "    no table row for named primitive: $name"; rc=1; }
  done < <(vocab_names "$vocab")
  # row shape + hard-required set == the OQ3 floor
  local prim kind avail class needs degrade floor got
  while IFS=$'\t' read -r prim kind avail class needs degrade; do
    [[ -n "$kind" && -n "$avail" ]] || { echo "    row lacks kind/availability: $prim"; rc=1; }
    if [[ "$class" == degradable && ( -z "$degrade" || "$degrade" == none* ) ]]; then
      echo "    degradable row without a named degrade path: $prim"; rc=1
    fi
  done <<<"$rows"
  floor="$(printf '%s\n' "Agent tool" PyYAML $doctor_deps | sort)"
  got="$(awk -F'\t' '$4=="hard-required"{print $1}' <<<"$rows" | sort)"
  [[ "$floor" == "$got" ]] || { echo "    hard-required set != floor (Agent tool + doctor toolchain)"; rc=1; }
  # named fallbacks
  local wf adm
  wf="$(awk -F'\t' '$1=="Workflow tool"{print $6}' <<<"$rows")"
  adm="$(awk -F'\t' '$1=="admitted non-native implement"{print $6}' <<<"$rows")"
  for n in "single owner" "uniform effort" WARN "per-agent effort"; do
    grep -qF -- "$n" <<<"$wf" || { echo "    Workflow row lacks: $n"; rc=1; }
  done
  for n in "first native provider" WARN; do
    grep -qF -- "$n" <<<"$adm" || { echo "    admitted-implement row lacks: $n"; rc=1; }
  done
  return $rc
}

# check_b3 <file> -> every vocabulary primitive the file names is, on each line
# that carries it AND the pointer path, marked with its own table class; at least
# one such line exists.
check_b3() {
  local f="$1" rc=0 name class mark line n
  while IFS= read -r name; do
    grep -qwF -- "$name" "$f" || continue
    class="$(table_rows "$TABLE" | awk -F'\t' -v n="$name" '$1==n{print $4}')"
    case "$class" in hard-required) mark='hard-required' ;; degradable) mark='degradable' ;; *) echo "    $name: no table class"; rc=1; continue ;; esac
    n=0
    while IFS= read -r line; do
      n=$((n+1))
      grep -qiE -- "$mark" <<<"$line" || { echo "    $(basename "$f"): $name carries the wrong mark (want $class)"; rc=1; }
    done < <(grep -wF -- "$name" "$f" | grep -F -- "$PTR")
    [[ $n -gt 0 ]] || { echo "    $(basename "$f"): $name unmarked"; rc=1; }
  done < <(vocab_names "$VOCAB")
  return $rc
}

# span_of <execute-skill> -> line number of the check span, or empty
SPAN_RE='`bash \$\{CLAUDE_PLUGIN_ROOT\}/scripts/goalforge-harness-check\.sh <availability-file>`'
# check_b4 <execute-skill> -> span exists before `## 2`; run against fixtures
check_b4() {
  local f="$1" rc=0 span_ln h2_ln span cmd out code
  span_ln="$(grep -nE -- "$SPAN_RE" "$f" | head -1 | cut -d: -f1)"
  h2_ln="$(grep -n '^## 2' "$f" | head -1 | cut -d: -f1)"
  [[ -n "$span_ln" ]] || { echo "    no check span in $(basename "$f")"; return 1; }
  [[ -n "$h2_ln" && "$span_ln" -lt "$h2_ln" ]] || { echo "    span not before ## 2"; rc=1; }
  span="$(grep -oE -- "$SPAN_RE" "$f" | head -1)"; span="${span#\`}"; span="${span%\`}"
  grep -F -- "$span" "$f" | grep -qE 'non-zero exit stops the run per §5.*exit 1.*exit 2' \
    || { echo "    span line lacks the non-zero-exit stop (§5, exit 1/2)"; rc=1; }
  for env in missing-degradable missing-hard-required; do
    case "$env" in missing-degradable) src=env-missing-degradable.txt ;; *) src=env-missing-hard.txt ;; esac
    cmd="${span//<availability-file>/$FIX/$src}"
    out="$(env PATH="$T/shim-full" CLAUDE_PLUGIN_ROOT="$PKG" "$BASH" -c "$cmd" 2>&1)"; code=$?
    if [[ $env == missing-degradable ]]; then
      [[ $code -eq 0 && "$out" == *"WARN: Workflow tool"* ]] || { echo "    $env: rc=$code"; rc=1; }
    else
      [[ $code -eq 1 && "$out" == *"Agent tool"* ]] || { echo "    $env: rc=$code"; rc=1; }
    fi
  done
  return $rc
}

expect_red() {  # expect_red <label> <fn> args... : the check must fail
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then bad "known-bad not caught: $label"; else ok "known-bad red: $label"; fi
}

# ── b1 ──────────────────────────────────────────────────────────────────────
echo "[ b1: vocabulary hits carry rows ]"
mapfile -t LIVE < <(live_files)
if out="$(check_b1 "$VOCAB" "$TABLE" "${LIVE[@]}")"; then ok "live files: every hit has a row, floor holds"; else bad "live files"; echo "$out"; fi

grep -vF '| `git` |' "$TABLE" > "$T/table-no-git.md"
expect_red "(i) table with git row removed" check_b1 "$VOCAB" "$T/table-no-git.md" "${LIVE[@]}"
printf 'Frobnicator tool\n' | cat "$VOCAB" - > "$T/vocab-frob.txt"
printf 'Uses the Frobnicator tool.\n' > "$T/stage-frob.md"
expect_red "(ii) stage copy naming a vocabulary primitive with no row" check_b1 "$T/vocab-frob.txt" "$TABLE" "${LIVE[@]}" "$T/stage-frob.md"
expect_red "(iii) vocabulary holding only Agent tool" check_b1 "$FIX/vocab-only-agent.txt" "$TABLE" "${LIVE[@]}"
mkdir -p "$T/noask"; : > "$T/noask/list"
for f in "${LIVE[@]}"; do grep -vwF AskUserQuestion "$f" > "$T/noask/$(echo "$f" | tr / _)"; echo "$T/noask/$(echo "$f" | tr / _)" >> "$T/noask/list"; done
mapfile -t NOASK < "$T/noask/list"
expect_red "(iv) file list with no AskUserQuestion hit" check_b1 "$VOCAB" "$TABLE" "${NOASK[@]}"
command sed 's/| hard-required | - | none: the floor |$/| degradable | - | none: the floor |/' "$TABLE" > "$T/table-soft-floor.md"
expect_red "floor row downgraded to degradable" check_b1 "$VOCAB" "$T/table-soft-floor.md" "${LIVE[@]}"

# ── b2 ──────────────────────────────────────────────────────────────────────
echo "[ b2: check script per environment ]"
if out="$(check_b2 "$CHECK")"; then ok "live checker: every environment outcome holds"; else bad "live checker"; echo "$out"; fi
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/always-ok.sh"
expect_red "(b2) checker exiting 0 on everything" check_b2 "$T/always-ok.sh"
# a checker that believes declarations and never probes
printf '%s\n' '#!/usr/bin/env bash' 'grep -q "=absent" "$1" && exit 1' 'exit 0' > "$T/trusting.sh"
expect_red "(b2) checker trusting declarations, never probing" check_b2 "$T/trusting.sh"

# ── b3 ──────────────────────────────────────────────────────────────────────
echo "[ b3: markings and line cap ]"
for f in "$EXEC" "$DISP"; do
  if out="$(check_b3 "$f")"; then ok "$(basename "$f"): every named primitive marked"; else bad "$(basename "$f")"; echo "$out"; fi
  command sed "s#$PTR##g" "$f" > "$T/nopointer-$(basename "$f")"
  expect_red "pointers deleted from $(basename "$f")" check_b3 "$T/nopointer-$(basename "$f")"
done
command sed '/^4\. Before any dispatch/ s/hard-required per `references\/harness-dependencies.md`: /hard-required per `references\/harness-dependencies.md`: Workflow tool, /' "$EXEC" > "$T/exec-wfhard.md"
expect_red "Workflow tool listed as hard-required" check_b3 "$T/exec-wfhard.md"
lines="$(wc -l < "$EXEC")"
[[ $lines -le 125 ]] && ok "execute/SKILL.md $lines lines (cap 125)" || bad "execute/SKILL.md $lines lines"

# ── b4 ──────────────────────────────────────────────────────────────────────
echo "[ b4: execute-entry invocation ]"
if out="$(check_b4 "$EXEC")"; then ok "live span before ## 2 and reproduces b2 outcomes"; else bad "live span"; echo "$out"; fi
grep -vE -- "$SPAN_RE" "$EXEC" > "$T/exec-nospan.md"
expect_red "span removed" check_b4 "$T/exec-nospan.md"
{ grep -vE -- "$SPAN_RE" "$EXEC"; grep -E -- "$SPAN_RE" "$EXEC"; } > "$T/exec-late.md"
expect_red "span placed after ## 2" check_b4 "$T/exec-late.md"
command sed 's/ a non-zero exit stops the run per §5 (exit 1 floor breach, exit 2 bad declaration)//' "$EXEC" > "$T/exec-nostop.md"
expect_red "span line without the non-zero-exit stop" check_b4 "$T/exec-nostop.md"

echo ""
echo "goalforge-harness-check.test.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
