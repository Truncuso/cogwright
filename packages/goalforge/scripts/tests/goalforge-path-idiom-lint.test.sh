#!/usr/bin/env bash
# goalforge-path-idiom-lint.test.sh — wp-11 oracle for b1, b3, b4, b5.
#
#   b1  goalforge-path-idiom-lint.sh over evals/fixtures/path-idiom/ (known-good
#       exits 0; each known-bad exits 1 naming file:line and its check id), over
#       the live package tree (clean), and over a copy of the live tree with one
#       literal reintroduced (red). Mutants of the lint with one check removed
#       must let their known-bad through (so each check is what rejects it).
#   b3  route coherence: no route-colon-verdict stamp and no "stamped by
#       goalforge-capture" in any wp-11 owned file outside the named allowlist;
#       capture Step 4c/5 still names the in-session goalforge-route.sh call.
#   b4  wayfind chart-flow step 1 states the destination is written once and
#       recommitted only through a grilling ticket shaped like ticket-31.
#   b5  the wave execution route is gone and its signals classify standard.
#
# Every case also runs on a one-edit known-bad copy made at test time and must
# turn red there.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$SD/../.." && pwd)"
LINT="$PKG/scripts/goalforge-path-idiom-lint.sh"
FX="$PKG/evals/fixtures/path-idiom"

T="$(mktemp -d)"
trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== goalforge-path-idiom-lint.test.sh ==="

# ── b1: fixtures ─────────────────────────────────────────────────────────────
# $1 lint, $2 fixture, $3 check id, $4 line -> rc 1 and a "<file>:<line>: [<id>]" line
bad_case() {
    local out rc
    out="$(bash "$1" "$FX/$2" 2>&1)"; rc=$?
    [[ "$rc" -eq 1 ]] && grep -qF -- "$FX/$2:$4: [$3]" <<<"$out"
}
if out="$(bash "$LINT" "$FX/good.md" 2>&1)"; then ok "b1 good.md (sanctioned idiom) -> exit 0"
else bad "b1 good.md -> exit 0: $out"; fi
bad_case "$LINT" bad-literal.md PI1 3      && ok "b1 bad-literal.md -> exit 1, names file:3 [PI1]"      || bad "b1 bad-literal.md -> exit 1 [PI1]"
bad_case "$LINT" bad-second-idiom.md PI2 4 && ok "b1 bad-second-idiom.md -> exit 1, names file:4 [PI2]" || bad "b1 bad-second-idiom.md -> exit 1 [PI2]"
bad_case "$LINT" bad-home-fence.md PI3 4   && ok "b1 bad-home-fence.md -> exit 1, names file:4 [PI3]"   || bad "b1 bad-home-fence.md -> exit 1 [PI3]"
bash "$LINT" "$T/no-such-file.md" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 2 ]] && ok "b1 unreadable input -> exit 2" || bad "b1 unreadable input -> exit 2 (rc=$rc)"

# An unreadable *.md inside a scanned dir, and an unwalkable subdir, must exit 2
# (the lint used to exit 0: awk/find failures were swallowed). The why string
# distinguishes these from the usage-error exit 2. Skipped where chmod cannot
# make a path unreadable (root).
mkdir -p "$T/unread/sub" && printf 'clean\n' >"$T/unread/ok.md" && printf 'x\n' >"$T/unread/locked.md" && chmod 000 "$T/unread/locked.md"
if [[ -r "$T/unread/locked.md" ]]; then echo "  SKIP: unreadable-input cases (chmod cannot restrict this user)"
else
    out="$(bash "$LINT" "$T/unread" 2>&1)"; rc=$?
    [[ "$rc" -eq 2 ]] && grep -qF "cannot read file: $T/unread/locked.md" <<<"$out" \
        && ok "b1 unreadable *.md in a scanned dir -> exit 2 naming the file" || bad "b1 unreadable *.md -> exit 2 (rc=$rc): $out"
    mkdir -p "$T/unwalk/locked" && printf 'x\n' >"$T/unwalk/locked/a.md" && chmod 000 "$T/unwalk/locked"
    out="$(bash "$LINT" "$T/unwalk" 2>&1)"; rc=$?
    [[ "$rc" -eq 2 ]] && grep -qF "cannot scan directory: $T/unwalk" <<<"$out" \
        && ok "b1 unwalkable subdir -> exit 2 naming the directory" || bad "b1 unwalkable subdir -> exit 2 (rc=$rc): $out"
fi

# ── b1: scan scope (verify r1 D5) and --fenced-only (D2) ─────────────────────
# A symlinked start dir and a symlinked *.md are scanned; an excluded fixture
# tree is pruned (an unwalkable dir inside it is never visited); a directory with
# nothing to scan is an error, not a clean pass.
mkdir -p "$T/real" "$T/scope" && cp "$FX/bad-literal.md" "$T/real/lit.md"
ln -s "$T/real" "$T/scope/linkdir"
out="$(bash "$LINT" "$T/scope/linkdir" 2>&1)"; rc=$?
[[ "$rc" -eq 1 ]] && grep -qF "$T/scope/linkdir/lit.md:3: [PI1]" <<<"$out" \
    && ok "b1 symlinked start directory is scanned" || bad "b1 symlinked start dir (rc=$rc): $out"
mkdir -p "$T/lnk" && ln -s "$T/real/lit.md" "$T/lnk/viafile.md"
out="$(bash "$LINT" "$T/lnk" 2>&1)"; rc=$?
[[ "$rc" -eq 1 ]] && grep -qF "$T/lnk/viafile.md:3: [PI1]" <<<"$out" \
    && ok "b1 symlinked *.md file is scanned" || bad "b1 symlinked *.md (rc=$rc): $out"
mkdir -p "$T/empty/sub"
out="$(bash "$LINT" "$T/empty" 2>&1)"; rc=$?
[[ "$rc" -eq 2 ]] && grep -qF "no *.md to scan under directory: $T/empty" <<<"$out" \
    && ok "b1 directory with no *.md -> exit 2, not a silent pass" || bad "b1 empty dir -> exit 2 (rc=$rc): $out"
mkdir -p "$T/pr/evals/fixtures/locked" && printf 'clean\n' >"$T/pr/ok.md" && chmod 000 "$T/pr/evals/fixtures/locked"
out="$(bash "$LINT" "$T/pr" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && ok "b1 excluded fixture tree is pruned (unwalkable dir inside it not visited)" \
    || bad "b1 fixture prune (rc=$rc): $out"
chmod 755 "$T/pr/evals/fixtures/locked"
printf 'prose `~/.claude/skills/goalforge/a.md` and $CLAUDE_PLUGIN_ROOT\n\n```text\n~/.claude/skills/goalforge/b.md\n```\n' >"$T/fo.md"
out="$(bash "$LINT" --fenced-only "$T/fo.md" 2>&1)"; rc=$?
[[ "$rc" -eq 1 && "$(grep -c . <<<"$out")" -eq 1 ]] && grep -qF "$T/fo.md:4: [PI1]" <<<"$out" \
    && ok "b1 --fenced-only: prose quotation ignored, fenced literal reported" || bad "b1 --fenced-only (rc=$rc): $out"
out="$(bash "$LINT" "$T/fo.md" 2>&1)"
[[ "$(grep -c . <<<"$out")" -eq 3 ]] && ok "b1 default mode still reports the prose lines (fenced-only is opt-in)" \
    || bad "b1 default mode prose lines: $out"

# ── b1: live tree arm + reintroduced literal ─────────────────────────────────
if out="$(bash "$LINT" "$PKG" 2>&1)"; then ok "b1 live packages/goalforge tree is clean"
else bad "b1 live tree is clean"; printf '%s\n' "$out" | sed 's/^/        /'; fi
mkdir -p "$T/pkg" && cp -a "$PKG/." "$T/pkg/"
printf '\nSee `~/.claude/skills/goalforge/references/schema.md`.\n' >>"$T/pkg/capture/SKILL.md"
out="$(bash "$LINT" "$T/pkg" 2>&1)"; rc=$?
if [[ "$rc" -eq 1 ]] && grep -qF -- "$T/pkg/capture/SKILL.md:" <<<"$out" && grep -qF '[PI1]' <<<"$out"; then
    ok "b1 known-bad: live tree with one literal reintroduced -> exit 1 naming capture/SKILL.md"
else bad "b1 known-bad: reintroduced literal stays green (rc=$rc)"; fi

# ── b1: mutants — each check removed lets its own known-bad through ──────────
sed 's#^        (fence || !fo) \&\& /\\\$CLAUDE_PLUGIN_ROOT/ {#        0 {#' "$LINT" >"$T/m-pi2.sh"
sed 's#^        fence \&\& shell \&\& #        0 \&\& #' "$LINT" >"$T/m-pi3.sh"
sed 's#index(\$0, pi1)#0#' "$LINT" >"$T/m-pi1.sh"
for m in "pi1 bad-literal.md PI1 3" "pi2 bad-second-idiom.md PI2 4" "pi3 bad-home-fence.md PI3 4"; do
    set -- $m
    if cmp -s "$LINT" "$T/m-$1.sh"; then bad "mutant m-$1 is not a mutant (sed matched nothing)"
    elif bad_case "$T/m-$1.sh" "$2" "$3" "$4"; then bad "mutant m-$1 (check $3 removed) still rejects $2"
    else ok "mutant killed: m-$1 (check $3 removed) lets $2 through"; fi
done


# ── b1: the GENERATED plugin copy (scripts/goalforge-generate.sh output) ─────
# The generator rewrites author install paths to ${CLAUDE_PLUGIN_ROOT}; the lint
# must survive that rewrite: sanctioned idiom clean, the literal still PI1.
PLINT="$PKG/../../plugins/goalforge/scripts/goalforge-path-idiom-lint.sh"
pi1_lit='~/.claude/skills/'; pi1_lit+=goalforge
printf '```bash\nbash ${CLAUDE_PLUGIN_ROOT}/scripts/x.sh\n```\n' >"$T/plugin-good.md"
printf '```bash\ncat %s/references/schema.md\n```\n' "$pi1_lit" >"$T/plugin-bad.md"
plugin_lint() {  # $1 lint -> 0 when the fenced idiom is clean and the literal is PI1
    local out
    out="$(bash "$1" --fenced-only "$T/plugin-good.md" 2>&1)" || { echo "sanctioned idiom flagged: $out"; return 1; }
    out="$(bash "$1" --fenced-only "$T/plugin-bad.md" 2>&1)"
    [[ $? -eq 1 ]] && grep -qF "$T/plugin-bad.md:2: [PI1]" <<<"$out" || { echo "literal not PI1: $out"; return 1; }
}
if [[ ! -f "$PLINT" ]]; then bad "b1 generated plugin lint missing: $PLINT"
elif out="$(plugin_lint "$PLINT")"; then ok "b1 generated plugin lint: \${CLAUDE_PLUGIN_ROOT} clean, author literal -> PI1"
else bad "b1 generated plugin lint: $out"; fi
# Known-bad: the pre-fix generator output (PI1 literal rewritten to the idiom).
sed "s|^pi1_lit=.*|pi1_lit='\${CLAUDE_PLUGIN_ROOT}'|" "$PLINT" >"$T/m-plugin-rewritten.sh"
if cmp -s "$PLINT" "$T/m-plugin-rewritten.sh"; then bad "mutant m-plugin-rewritten is not a mutant"
elif plugin_lint "$T/m-plugin-rewritten.sh" >/dev/null; then bad "b1 known-bad: rewritten PI1 literal stays green"
else ok "b1 known-bad: PI1 literal rewritten to \${CLAUDE_PLUGIN_ROOT} -> red"; fi
# ── b3: route coherence over the wp-11 owned files ───────────────────────────
OWNED=(
  scripts/goalforge-path-idiom-lint.sh scripts/tests/goalforge-path-idiom-lint.test.sh
  scripts/goalforge-preharden-lint.sh scripts/tests/goalforge-preharden-lint.test.sh
  capture/SKILL.md archive/SKILL.md plan-index/SKILL.md wayfind/SKILL.md spec/SKILL.md
  references/schema.md references/dispatch-template.md scripts/goalforge-route.sh
  wayfind/references/ticket-fanout.md references/state-machine.md
  scripts/goalforge-transition.sh references/templates/feature-overview.md
  scripts/tests/goalforge-respec.test.sh
  evals/fixtures/respec/known-bad/b4e-sm-row-draft-completed.md
  evals/fixtures/respec/known-bad/b4g-transition-ignore-route.sh
  evals/fixtures/respec/known-bad/b4h-transition-missing-route-fast.sh
)
STAMP_RE='route:[[:space:]]*(fast|standard|wave)'
# Verdict words held in variables so this file never spells a stamp itself.
F=fast; S=standard; CAP=goalforge-capture
# Allowlist: goalforge-route.sh's self-test printf lines (throwaway classifier
# inputs, legacy pins) and capture/SKILL.md Step 5's in-session next-action prose.
allowed() {  # $1 rel path, $2 line text
    case "$1" in
        scripts/goalforge-route.sh) [[ "$2" =~ ^[[:space:]]*printf\ --\ \'---\\nroute: ]] ;;
        capture/SKILL.md)           [[ "$2" == "Next (route: $S):"* || "$2" == "Next (route: $F):"* ]] ;;
        *) return 1 ;;
    esac
}
coherence() {  # $1 package root -> prints offending "rel:line: text", rc 1 on any
    local root="$1" rel ln text rc=0
    for rel in "${OWNED[@]}"; do
        [[ -f "$root/$rel" ]] || continue
        while IFS=: read -r ln text; do
            allowed "$rel" "$text" && continue
            echo "$rel:$ln: $text"; rc=1
        done < <(grep -nE -- "$STAMP_RE" "$root/$rel")
        while IFS=: read -r ln text; do echo "$rel:$ln: $text"; rc=1; done \
            < <(grep -nF -- "stamped by $CAP" "$root/$rel")
    done
    return "$rc"
}
step45() {  # $1 capture SKILL.md -> the Step 4c .. Fast path range
    awk '/^### Step 4c/{g=1} /^## Fast path/{g=0} g' "$1"
}
positive() {  # $1 capture SKILL.md
    local r; r="$(step45 "$1")"
    grep -qF 'goalforge-route.sh' <<<"$r" && grep -qF "Next (route: $F):" <<<"$r" \
        && grep -qF "Next (route: $S):" <<<"$r"
}
if out="$(coherence "$PKG")"; then ok "b3 no route stamp and no capture-stamp citation in owned files (allowlist only)"
else bad "b3 route coherence"; printf '%s\n' "$out" | sed 's/^/        /'; fi
positive "$PKG/capture/SKILL.md" && ok "b3 capture Step 4c/5 names the in-session goalforge-route.sh call and its next actions" \
    || bad "b3 capture Step 4c/5 positive arm"
cp "$PKG/capture/SKILL.md" "$T/pkg/capture/SKILL.md"
sed -i "s/^### Step 4c.*\$/&\\n\\nStamp \`route: $F\` into overview.md frontmatter./" "$T/pkg/capture/SKILL.md"
coherence "$T/pkg" >/dev/null && bad "b3 known-bad: a re-added capture stamp stays green" \
    || ok "b3 known-bad: a re-added capture route stamp -> red"
cp "$PKG/spec/SKILL.md" "$T/pkg/spec/SKILL.md"
printf '\nA fast feature (overview frontmatter, stamped by %s).\n' "$CAP" >>"$T/pkg/spec/SKILL.md"
cp "$PKG/capture/SKILL.md" "$T/pkg/capture/SKILL.md"
coherence "$T/pkg" >/dev/null && bad "b3 known-bad: spec/SKILL.md citing the capture stamp stays green" \
    || ok "b3 known-bad: spec/SKILL.md citing the capture stamp -> red"
sed 's/goalforge-route\.sh/goalforge-classifier.sh/g' "$PKG/capture/SKILL.md" >"$T/capture-noroute.md"
positive "$T/capture-noroute.md" && bad "b3 known-bad: Step 4c without the classifier call stays green" \
    || ok "b3 known-bad: Step 4c without the classifier call -> red"

# ── b4: wayfind destination-settling step ────────────────────────────────────
step1() { awk '/^\*\*1\. Write `map\.md`\*\*/{g=1; next} /^\*\*2\./{g=0} g' "$1"; }
settles() {
    local r; r="$(step1 "$1")"
    grep -qF 'written once' <<<"$r" && grep -qF 'grilling ticket' <<<"$r" && grep -qF 'ticket-31' <<<"$r"
}
settles "$PKG/wayfind/SKILL.md" && ok "b4 wayfind step 1 names 'written once', 'grilling ticket', ticket-31" \
    || bad "b4 wayfind destination-settling step"
grep -v 'written once' "$PKG/wayfind/SKILL.md" >"$T/wayfind-nosettle.md"
settles "$T/wayfind-nosettle.md" && bad "b4 known-bad: step 1 without 'written once' stays green" \
    || ok "b4 known-bad: step 1 without 'written once' -> red"
{ step1 "$PKG/wayfind/SKILL.md" >/dev/null; printf '**1. Write `map.md`**\n\n**2. Seed**\n\nwritten once, grilling ticket, ticket-31\n'; } >"$T/wayfind-outside.md"
settles "$T/wayfind-outside.md" && bad "b4 known-bad: phrases outside step 1 pass" \
    || ok "b4 known-bad: phrases outside the step-1 range -> red"

# ── b5: wave execution route deleted, signals remapped to standard ───────────
ROUTE="$PKG/scripts/goalforge-route.sh"
wave_gone() {  # $1 package root
    local root="$1" rc=0
    grep -qE '"route":[[:space:]]*"fast"\|"standard"\|"wave"|"route":"fast"\|"standard"\|"wave"|route, confidence = "wave"' \
        "$root/scripts/goalforge-route.sh" && { echo "wave still in the route enum"; rc=1; }
    grep -qF 'Wave-route brief instance' "$root/references/dispatch-template.md" && { echo "Wave-route brief instance heading present"; rc=1; }
    [[ -d "$root/evals/wave-route" ]] && { echo "evals/wave-route/ still present"; rc=1; }
    grep -qF 'retired 2026-09-27, ticket-84' "$root/wayfind/references/ticket-fanout.md" || { echo "ticket-fanout.md lacks the execute-wave retirement"; rc=1; }
    return "$rc"
}
if out="$(wave_gone "$PKG")"; then ok "b5 no wave enum, no Wave-route heading, no evals/wave-route/, execute-wave retired in ticket-fanout.md"
else bad "b5 wave route deleted: $out"; fi
f89() { bash "$1" --self-test 2>&1 | grep -E '^  (PASS|FAIL): F(8|9) '; }
out="$(f89 "$ROUTE")"
if bash "$ROUTE" --self-test >/dev/null 2>&1 && [[ "$(grep -c 'PASS: F[89] .*-> standard/clear' <<<"$out")" -eq 2 ]]; then
    ok "b5 goalforge-route.sh --self-test green with F8/F9 -> standard"
else bad "b5 route --self-test F8/F9 -> standard: $out"; fi
sed 's/strong = \[s for s in tripped if s in ("R1", "R2", "R3", "R4", "R6")\]/strong = [s for s in tripped if s in ("R1", "R2", "R3", "R4")]/' "$ROUTE" >"$T/m-route-noremap.sh"
if cmp -s "$ROUTE" "$T/m-route-noremap.sh"; then bad "mutant m-route-noremap is not a mutant"
elif bash "$T/m-route-noremap.sh" --self-test >/dev/null 2>&1; then bad "b5 known-bad: fan-out signal not remapped to standard stays green"
else ok "b5 known-bad: fan-out signal dropped from the strong set -> self-test red"; fi
mkdir -p "$T/pkg/evals/wave-route"
wave_gone "$T/pkg" >/dev/null && bad "b5 known-bad: an evals/wave-route/ dir stays green" \
    || ok "b5 known-bad: evals/wave-route/ present -> red"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
