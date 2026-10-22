#!/usr/bin/env bash
# goalforge-preharden-lint.test.sh — sabotage pairs for V5 (WP-altitude
# command-shape lint + section-lint call, ticket-73/spec C3 G2) added on top
# of goalforge-preharden-lint.sh's existing P1/V1-V4 family. Fixtures live
# under packages/goalforge/evals/fixtures/preharden-lint/ — never inline.
set -uo pipefail
# An inherited GIT_DIR / GIT_COMMON_DIR / ... would redirect the fixture repo's
# own git writes below into whatever repo the caller points at.
unset $(git rev-parse --local-env-vars)

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$SD/../goalforge-preharden-lint.sh"
# The lint writes a gate.result row into <feature-dir>/trace-events.jsonl, so it
# must never run against the checked-in fixture tree (evals/run.sh asserts the
# fixture sha256 manifest is unchanged). Copy to a temp dir and run there.
FIX_SRC="$SD/../../evals/fixtures/preharden-lint"
FIX_TMP_ROOT="$(mktemp -d)"
FIX="$FIX_TMP_ROOT/preharden-lint"
mkdir -p "$FIX"
cp -R "$FIX_SRC/." "$FIX/"
# Clean up the temp root by its own name — never a path derived from $FIX, so a
# later edit to FIX can never turn this into an rm -rf of the fixture tree.
trap 'rm -rf "$FIX_TMP_ROOT"' EXIT
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# ── known-good: schema-6, command-shaped, exact C1 sections -> exit 0 ───────
OUT="$(bash "$LINT" "$FIX/good-wp" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    ok "good-wp (schema-6, command-shaped, C1 sections) -> exit 0"
else
    bad "good-wp -> exit 0 (rc=$rc)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

# ── known-bad: schema-6, prose verification.command -> exit 2 ───────────────
OUT="$(bash "$LINT" "$FIX/bad-command-wp" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$OUT" | grep -qi 'V5'; then
    ok "bad-command-wp (prose command) -> exit 2, V5 finding"
else
    bad "bad-command-wp -> exit 2, V5 finding (rc=$rc)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

# ── known-bad: schema-6, command-shaped, extra H2 section -> exit 2 ─────────
OUT="$(bash "$LINT" "$FIX/extra-section-wp" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then
    ok "extra-section-wp -> exit 2 (section-lint call surfaces through V5)"
else
    bad "extra-section-wp -> exit 2 (rc=$rc)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

# ── schema-5 baseline: prose check: -> WARN only, never ERROR (exit != 2) ───
OUT="$(bash "$LINT" "$FIX/schema5-baseline-wp" 2>&1)"; rc=$?
if [ "$rc" -ne 2 ]; then
    ok "schema5-baseline-wp -> ratchet WARN, never ERROR (rc=$rc, not 2)"
else
    bad "schema5-baseline-wp -> ratchet WARN, never ERROR (rc=$rc)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

# ── known-bad: schema-6 behavior pinned to a live corpus root ──────────────
# b2's wording is taken from the wp-02-agent-roster expertise-map behavior that
# shipped red on a fresh clone: it resolves against ${CLAUDE_CONFIG_DIR:-$HOME/.claude}
# and names no shipped fixture root.
OUT="$(bash "$LINT" "$FIX/v6-live-root-wp" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] \
   && printf '%s' "$OUT" | grep -q 'WARN \[V6\] v6-live-root-wp: b2: oracle resolves against a live corpus root with no shipped fixture root'; then
    ok "v6-live-root-wp -> WARN V6 (heuristic, never ERROR)"
else
    bad "v6-live-root-wp -> WARN V6 (rc=$rc)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

# ── known-good: the SAME live-root literal, but a shipped fixture root is named.
# Exercises the exemption conjunct: deleting `&& ! grep fixture-tokens` from the
# lint must turn this case red.
OUT="$(bash "$LINT" "$FIX/v6-live-root-exempt-wp" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$OUT" | grep -q '\[V6\]'; then
    ok "v6-live-root-exempt-wp -> no V6 line (fixture-root exemption applies)"
else
    bad "v6-live-root-exempt-wp -> no V6 line (rc=$rc)"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

# ── good-wp emits no V6 line (behaviors[] empty -> skipped silently) ───────
OUT="$(bash "$LINT" "$FIX/good-wp" 2>&1)"
if ! printf '%s' "$OUT" | grep -q '\[V6\]'; then
    ok "good-wp emits no V6 line"
else
    bad "good-wp emits no V6 line"
    printf '%s\n' "$OUT" | sed 's/^/        /'
fi

# ── existing P1/V1-V4 self-test must stay green (non-regression) ────────────
if bash "$LINT" --self-test >/tmp/phl-selftest.out 2>&1; then
    ok "existing --self-test (P1/V1-V4) stays green"
else
    bad "existing --self-test (P1/V1-V4) stays green"
    sed 's/^/        /' /tmp/phl-selftest.out
fi

# ── V7/V8 + V2 git whitelist (wp-11 b2) ─────────────────────────────────────
# These WP fixtures are written here, one condition per known-bad, into a temp
# git repo (V7 resolves revisions against the WP's own repository). The
# evals/fixtures/preharden-lint/ tree is outside wp-11's owned files.
# V7 is static: it must never run any part of a verify block, so the side-effect
# fixtures below carry a live marker path / commit and the checks assert NOTHING
# happened.
W="$FIX_TMP_ROOT/v78"
mkdir -p "$W"
MARK_TOUCH="$FIX_TMP_ROOT/marker-touch"
MARK_CHAIN="$FIX_TMP_ROOT/marker-chain"
mkwp() {  # $1 name, $2 goal.constraints flow list ('' = none), $3 task verify body ('' = no task)
    mkdir -p "$W/$1"
    {
        printf -- '---\nname: %s\nstatus: spec\nsha: 0123abc\ngoal:\n  outcome: "fixture"\n' "$1"
        printf '  verification:\n    strategy: deterministic\n    command: "bash run.sh"\n'
        [ -z "$2" ] || printf '  constraints: %s\n' "$2"
        printf -- '---\n\n## Goal\n\nfixture T1\n'
    } >"$W/$1/overview.md"
    [ -z "$3" ] || printf -- '---\nname: task-01-a\nverify: |\n  %s\n---\nbody\n' "$3" >"$W/$1/task-01-a.md"
}
mkwp v7-bad-revision   '' "git rev-parse --verify deadbeefdeadbeefdeadbeef^{commit}"
mkwp v7-bad-range      '' "git diff cafebabecafebabe..HEAD -- overview.md"
mkwp v7-side-effect-touch '' "grep -q T1 overview.md && touch $MARK_TOUCH
  grep -q T1 overview.md; touch $MARK_CHAIN"
mkwp v7-side-effect-commit '' "git commit --allow-empty -qm should-never-land"
mkwp v7-good-revision  '' "git rev-parse --verify --quiet HEAD"
mkwp v7-uncheckable    '' "git rev-parse --verify HEAD:overview.md"
# Narrow V7 (human ruling (b), 2026-10-22): one single-condition fixture per
# kept behavior; each flips verdict under the mutant that drops that behavior.
mkwp v7-bad-triple-dot     '' "git diff HEAD...cafebabe1234"
mkwp v7-bad-slash-range    '' "git log feature/nope..HEAD"
mkwp v7-wp-repo-tag        '' "git rev-parse --verify fixture-only-tag"
mkwp v7-env-leak           '' "git rev-parse --verify victim-only-tag"
# Known-goods: each line is a false ERROR if the SKIP rule it pins is dropped.
mkwp v7-skip-not-first     '' "command git log deadbeef1234..HEAD"
# r4 MEDIUM-2: a quoted "$(git ...)" is an announced SKIP, never silent.
mkwp v7-skip-quoted-subst  '' "[ \"\$(git rev-parse --verify deadbeef1234)\" = x ]"
mkwp v7-skip-git-option    '' "git -C ../other log deadbeef1234..HEAD"
mkwp v7-skip-quoting       '' "git log --grep \"x deadbeef1234..HEAD y\" HEAD"
# r4 MEDIUM-1: a `cd` line, then a git line naming a revision of the other repo.
mkwp v7-skip-cd            '' "cd ../other
  git log deadbeef1234..HEAD"
mkwp v7-skip-shell-stop    '' "git rev-parse --verify HEAD && grep -q x..y run.sh
  git rev-parse --verify HEAD # x..y
  git rev-parse --verify HEAD | grep x..y
  git rev-parse --verify HEAD; echo x..y
  git rev-parse --verify HEAD >x..y
  git rev-parse --verify HEAD <x..y"
mkwp v7-skip-no-verify     '' "git rev-parse --git-path deadbeef1234"
mkwp v7-skip-other-subcmd  '' "git tag --verify v9.9-nope"
mkwp v7-good-dotdot-path   '' "git diff HEAD ../x
  git diff HEAD a/../b"
# r5 N1: `a..b` is a range only for a revision subcommand; `--` ends revisions.
mkwp v7-good-nonrange-subcmd '' "git grep -q foo..bar HEAD"
mkwp v7-good-dashdash-range  '' "git log --oneline -- docs/v1..v2.md"
mkwp v7-good-dashdash-verify '' "git rev-parse --verify HEAD -- file.txt"
mkwp v7-good-optval '' "git rev-parse --default nosuch --prefix sub --verify HEAD"
# r5 N2: a heredoc body line starting with git is data, not a command.
mkwp v7-skip-heredoc       '' "cat > run.sh <<EOF
  git rev-parse --verify no-such-tag
  EOF"
# r5 N5: an uncheckable range beside a checked one is announced, not dropped.
mkwp v7-skip-unchecked-range '' "git log a/..b HEAD..HEAD"
mkwp v8-unquoted-flow      '[Preserve `<missing>`]' ''
mkwp v8-placeholder    '["baseline pinned at <base_sha>"]' ''
mkwp v8-missing-artifact '["the contract in `docs/no-such-contract.md` stays unchanged"]' ''
mkwp v2-git-external   '["baseline pinned at <sha>, contract `overview.md`"]' \
    "grep -q T1 overview.md
  git rev-parse --verify --quiet HEAD"
mkwp pi-literal        '' ''
printf '\n```bash\ncat ~/.claude/skills/goalforge/references/schema.md\n```\n' >>"$W/pi-literal/overview.md"
mkwp pi-prose-quote    '' ''
printf '\nThe defect is the literal `~/.claude/skills/goalforge/references/schema.md`.\n' >>"$W/pi-prose-quote/overview.md"
printf '```bash\ncat ~/.claude/skills/goalforge/x.md\n```\n' >"$W/pi-prose-quote/findings.md"
mkwp pi-p1-owns        '' ''
printf '\n```bash\nbash $CLAUDE_PLUGIN_ROOT/scripts/x.sh\n```\n' >>"$W/pi-p1-owns/overview.md"
FIXGIT=(-c user.name=fixture -c user.email=fixture@example.invalid)
git -C "$W" init -q && git -C "$W" add -A && git -C "$W" "${FIXGIT[@]}" commit -qm fixture \
    && git -C "$W" tag fixture-only-tag \
    || bad "v78 fixture repo could not be committed"
# A second repo the WP must never resolve against (cwd and GIT_* leak cases).
V="$FIX_TMP_ROOT/victim"
git init -q "$V" && git -C "$V" "${FIXGIT[@]}" commit -q --allow-empty -m victim \
    && git -C "$V" tag victim-only-tag || bad "victim repo could not be created"

v78() {  # $1 lint, $2 wp, $3 want rc, $4 want check id ('' = no finding), $5 want why substring ('' = any)
    local out rc
    out="$(bash "$1" "$W/$2" 2>&1)"; rc=$?
    [ "$rc" -eq "$3" ] || { echo "rc=$rc want $3: $out"; return 1; }
    if [ -n "$4" ]; then
        printf '%s' "$out" | grep -q "ERROR \[$4\] $2" || { echo "no [$4] line: $out"; return 1; }
        [ -z "${5:-}" ] || printf '%s' "$out" | grep -qF -- "$5" || { echo "why string '$5' missing: $out"; return 1; }
    else
        ! printf '%s' "$out" | grep -qE '^(WARN|ERROR) ' || { echo "unexpected finding: $out"; return 1; }
    fi
}
# "id rc check why" — the why string proves each known-bad fails for its intended reason.
while IFS='|' read -r id rc chk why; do
    [ -n "$id" ] || continue
    if r="$(v78 "$LINT" "$id" "$rc" "$chk" "$why")"; then ok "$id -> exit $rc${chk:+, $chk finding ($why)}"
    else bad "$id -> exit $rc${chk:+, $chk finding ($why)}"; printf '%s\n' "$r" | sed 's/^/        /'; fi
done <<'CASES'
v7-bad-revision|2|V7|unresolvable revision `deadbeefdeadbeefdeadbeef^{commit}`
v7-bad-range|2|V7|unresolvable revision `cafebabecafebabe`
v8-placeholder|2|V8|placeholder <base_sha>
v8-missing-artifact|2|V8|docs/no-such-contract.md
v2-git-external|0||
v7-good-revision|0||
v7-uncheckable|0||
v7-bad-triple-dot|2|V7|unresolvable revision `cafebabe1234`
v7-bad-slash-range|2|V7|unresolvable revision `feature/nope`
v7-skip-not-first|0||
v7-skip-quoted-subst|0||
v7-skip-git-option|0||
v7-skip-quoting|0||
v7-skip-cd|0||
v7-skip-shell-stop|0||
v7-skip-no-verify|0||
v7-skip-other-subcmd|0||
v7-good-dotdot-path|0||
v7-good-nonrange-subcmd|0||
v7-good-dashdash-range|0||
v7-good-dashdash-verify|0||
v7-good-optval|0||
v7-skip-heredoc|0||
v7-skip-unchecked-range|0||
pi-prose-quote|0||
v8-unquoted-flow|2|V8|placeholder <missing>
CASES
# Every unchecked part of a block is announced by exactly one INFO SKIP line
# naming why, so "passed" and "never ran" differ.
# b2 oracle note (verify r1, D7): the oracle's "pre-WP script" arm is not run
# here; the why-string asserts above prove each rejection comes from V7/V8.
while IFS='|' read -r id why; do
    OUT="$(bash "$LINT" "$W/$id" 2>&1)"
    n="$(printf '%s\n' "$OUT" | grep -c "^INFO \[V7\] $id: task-01-a.md: SKIP not statically checked: ")"
    [ "$n" -eq 1 ] && printf '%s' "$OUT" | grep -qF -- "$why" \
        && ok "$id: one INFO SKIP line naming '$why'" || bad "$id: one INFO SKIP naming '$why' (got $n): $OUT"
done <<'SKIPS'
v7-skip-not-first|1x first word is not git
v7-skip-quoted-subst|1x first word is not git
v7-skip-git-option|1x git option before the subcommand
v7-skip-quoting|1x git line with quoting or expansion
v7-skip-cd|1x block changes directory (cd/pushd), nothing checked
v7-skip-shell-stop|6x text after a shell operator or comment
v7-skip-no-verify|1x no checkable rev-parse --verify operand or a..b range
v7-skip-other-subcmd|1x no checkable rev-parse --verify operand or a..b range
v7-uncheckable|1x no checkable rev-parse --verify operand or a..b range
v7-side-effect-touch|2x first word is not git
v7-skip-heredoc|1x block has a heredoc (<<), nothing checked
v7-skip-unchecked-range|1x revision word not statically checkable
SKIPS
OUT="$(bash "$LINT" "$W/v7-good-revision" 2>&1)"
printf '%s' "$OUT" | grep -qF 'SKIP not statically checked' \
    && bad "v7-good-revision: fully checked block prints a SKIP line: $OUT" \
    || ok "v7-good-revision: fully checked block prints no SKIP line"
# WP-repo binding: a tag only the WP's repo has resolves with cwd in another repo.
OUT="$(cd "$V" && bash "$LINT" "$W/v7-wp-repo-tag" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok "v7-wp-repo-tag: resolved in the WP repo with cwd in another repo" \
    || { bad "v7-wp-repo-tag with cwd in another repo (rc=$rc)"; printf '%s\n' "$OUT" | sed 's/^/        /'; }
# Env clearing: an inherited GIT_DIR / GIT_COMMON_DIR must not make a revision
# that exists only in that other repo resolve.
for ev in GIT_DIR GIT_COMMON_DIR; do
    OUT="$(env "$ev=$V/.git" bash "$LINT" "$W/v7-env-leak" 2>&1)"; rc=$?
    [ "$rc" -eq 2 ] && printf '%s' "$OUT" | grep -qF 'unresolvable revision `victim-only-tag`' \
        && ok "v7-env-leak: $ev leak cleared -> exit 2 naming victim-only-tag" \
        || { bad "v7-env-leak under $ev (rc=$rc)"; printf '%s\n' "$OUT" | sed 's/^/        /'; }
done
# GIT_COMMON_DIR does not redirect ref lookup (the tag arm above is a regression
# guard) but it does redirect object lookup: probed 2026-09-29, a victim-only
# commit sha resolves in the WP repo under GIT_COMMON_DIR=<victim>/.git. It is
# outside the pre-r2 five-variable list, so this arm is what distinguishes the
# full `--local-env-vars` clearing (GIT_NAMESPACE, GIT_INDEX_FILE, GIT_CONFIG_*,
# GIT_GRAFT_FILE, GIT_SHALLOW_FILE changed neither tag nor sha resolution).
VSHA="$(git -C "$V" rev-parse HEAD)"
mkwp v7-env-leak-sha '' "git rev-parse --verify $VSHA"
OUT="$(env "GIT_COMMON_DIR=$V/.git" bash "$LINT" "$W/v7-env-leak-sha" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$OUT" | grep -qF "unresolvable revision \`$VSHA\`" \
    && ok "v7-env-leak-sha: GIT_COMMON_DIR leak cleared -> exit 2 naming the victim sha" \
    || { bad "v7-env-leak-sha under GIT_COMMON_DIR (rc=$rc)"; printf '%s\n' "$OUT" | sed 's/^/        /'; }
# The range fixture's resolvable side (HEAD) must not be blamed.
OUT="$(bash "$LINT" "$W/v7-bad-range" 2>&1)"
printf '%s' "$OUT" | grep -q 'unresolvable revision `HEAD`' \
    && bad "v7-bad-range blames the resolvable side HEAD" || ok "v7-bad-range blames only the unresolvable side"

# ── V7 never executes a verify block ────────────────────────────────────────
HEAD_BEFORE="$(git -C "$W" rev-parse HEAD)"; COUNT_BEFORE="$(git -C "$W" rev-list --count HEAD)"
OUT="$(bash "$LINT" "$W/v7-side-effect-touch" 2>&1)"; rc=$?
if [ "$rc" -ne 2 ] && [ ! -e "$MARK_TOUCH" ] && [ ! -e "$MARK_CHAIN" ] \
   && printf '%s' "$OUT" | grep -q 'INFO \[V7\] v7-side-effect-touch: task-01-a.md: 0 revision token(s) statically checked; gate not run'; then
    ok "v7-side-effect-touch: no marker written (gate not run), INFO names it"
else bad "v7-side-effect-touch: marker written or wrong output (rc=$rc)"; printf '%s\n' "$OUT" | sed 's/^/        /'; fi
OUT="$(bash "$LINT" "$W/v7-side-effect-commit" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(git -C "$W" rev-list --count HEAD)" = "$COUNT_BEFORE" ] \
   && [ "$(git -C "$W" rev-parse HEAD)" = "$HEAD_BEFORE" ]; then
    ok "v7-side-effect-commit: no commit landed in the WP repo (gate not run)"
else bad "v7-side-effect-commit: a commit landed or lint failed (rc=$rc)"; printf '%s\n' "$OUT" | sed 's/^/        /'; fi

# ── B: passed and never-ran read differently ────────────────────────────────
OUT="$(bash "$LINT" "$W/v7-good-revision" 2>&1)"
printf '%s' "$OUT" | grep -q 'INFO \[V7\] v7-good-revision: task-01-a.md: 1 revision token(s) statically checked; gate not run' \
    && ok "v7-good-revision: INFO says 1 token checked, gate not run" || bad "v7-good-revision INFO line: $OUT"
OUT="$(bash "$LINT" "$FIX/good-wp" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$OUT" | grep -q 'INFO \[V7\] good-wp: no task verify: blocks to check; V7 ran no gate'; then
    ok "good-wp (schema-6, no task files) -> exit 0 with the V7 nothing-to-check INFO"
else bad "good-wp V7 nothing-to-check INFO (rc=$rc)"; printf '%s\n' "$OUT" | sed 's/^/        /'; fi

# ── C: path-idiom lint is wired into the preharden lint ─────────────────────
OUT="$(bash "$LINT" "$W/pi-literal" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$OUT" | grep -qE "^WARN \[PI1\] $W/pi-literal/overview\.md:[0-9]+: literal author install path"; then
    ok "pi-literal: path-idiom finding reaches the preharden output (WARN [PI1], exit 1)"
else bad "pi-literal: PI1 not surfaced (rc=$rc)"; printf '%s\n' "$OUT" | sed 's/^/        /'; fi
OUT="$(bash "$LINT" "$W/v7-good-revision" 2>&1)"
printf '%s' "$OUT" | grep -q '\[PI' && bad "clean WP shows a PI finding: $OUT" || ok "clean WP shows no PI finding"
# D2: P1 owns $CLAUDE_PLUGIN_ROOT in WP docs; PI2 never reports the same token.
OUT="$(bash "$LINT" "$W/pi-p1-owns" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$OUT" | grep -q '^WARN \[P1\] overview.md' && ! printf '%s' "$OUT" | grep -q '\[PI2\]'; then
    ok "pi-p1-owns: one P1 finding, no PI2 on the same token"
else bad "pi-p1-owns: P1 only (rc=$rc)"; printf '%s\n' "$OUT" | sed 's/^/        /'; fi
# D via the wiring: an unreadable task doc is an ERROR (exit 2), not a silent pass.
if [ -r "$W" ] && mkdir -p "$W/pi-unreadable" && cp "$W/v7-good-revision/overview.md" "$W/pi-unreadable/overview.md" \
   && printf 'x\n' >"$W/pi-unreadable/task-02-b.md" && chmod 000 "$W/pi-unreadable/task-02-b.md" && [ ! -r "$W/pi-unreadable/task-02-b.md" ]; then
    OUT="$(bash "$LINT" "$W/pi-unreadable" 2>&1)"; rc=$?
    if [ "$rc" -eq 2 ] && printf '%s' "$OUT" | grep -q 'ERROR \[PI\] pi-unreadable: path-idiom lint could not scan (exit 2): not a readable file'; then
        ok "pi-unreadable: unreadable task doc -> ERROR [PI], exit 2"
    else bad "pi-unreadable: exit 2 with ERROR [PI] (rc=$rc)"; printf '%s\n' "$OUT" | sed 's/^/        /'; fi
    chmod 644 "$W/pi-unreadable/task-02-b.md"
else echo "  SKIP: pi-unreadable (cannot make a file unreadable, e.g. running as root)"; fi

for c in V7 V8 PI; do
    grep -q "^#   $c " "$LINT" && ok "script header names $c in its check list" || bad "script header names $c"
done
sed -n '/^# Exit:/,/^# Offline/p' "$LINT" | grep -q 'V7' \
    && sed -n '/^# Exit:/,/^# Offline/p' "$LINT" | grep -q 'V8' \
    && sed -n '/^# Exit:/,/^# Offline/p' "$LINT" | grep -q 'PI' \
    && ok "exit-code contract names V7, V8 and PI" || bad "exit-code contract names V7, V8 and PI"
# The header's read-only claim is only true while no verify text is executed.
grep -qE 'bash -c|timeout [0-9]+|GIT_DIR=|export GIT_DIR' "$LINT" \
    && bad "lint still carries an executing path (bash -c / timeout / exported GIT_DIR)" \
    || ok "lint carries no verify-block executing path"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
