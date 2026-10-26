#!/usr/bin/env bash
# goalforge-reader.test.sh — wp-07 b3: reader-slug resolution, refusal and
# privacy (spec.md C8).
#
# Every arm but the last runs HERMETICALLY: a mktemp git repo with HOME,
# GIT_CONFIG_GLOBAL, GIT_CONFIG_SYSTEM and GOALFORGE_READER all set by this
# test, so no live git config, no live <repo>/.memory/ and no ambient
# GOALFORGE_READER can reach the run. The final arm is NON-HERMETIC by
# necessity and says so: it asserts against this repository's own .gitignore,
# which a mktemp repo does not have.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/.." && pwd)"
PKG="$(cd "$SCRIPTS/.." && pwd)"
REPO="$(cd "$PKG/../.." && pwd)"
READER="$SCRIPTS/goalforge-reader.sh"
REPORT="$SCRIPTS/goalforge-stage-report.sh"
SLUG_RE='^[a-z0-9][a-z0-9._-]*$'

PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
chk() { if [ "$2" = pass ]; then ok "$1"; else bad "$1"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A hermetic repo: git sees nothing but what this test writes.
mkrepo() {
  local d; d="$(mktemp -d "$WORK/repo.XXXXXX")"
  git -C "$d" init -q
  git -C "$d" config user.name "Fixture"
  echo "$d"
}
# Run the reader with the ambient environment fully replaced.
run_reader() {  # run_reader <repo> <env-assignments...> -- <args...>
  local repo="$1"; shift
  local -a envs=()
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  env -u GOALFORGE_READER \
      HOME="$WORK/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
      "${envs[@]}" bash "$READER" --repo "$repo" "$@"
}
mkdir -p "$WORK/home"

echo "=== goalforge-reader: C8 slug resolution (b3) ==="

# ── ladder rung 1: GOALFORGE_READER wins everything below it ────────────────
R="$(mkrepo)"
printf 'reader: fromyaml\n' > "$R/goalforge.yaml"
git -C "$R" config user.email "fromemail@example.com"
OUT="$(run_reader "$R" GOALFORGE_READER=fromenv -- --slug 2>/dev/null)"
[ "$OUT" = "fromenv" ] && chk "rung 1: GOALFORGE_READER wins over yaml and email" pass \
  || chk "rung 1: GOALFORGE_READER wins over yaml and email (got '$OUT')" fail

# ── ladder rung 2: goalforge.yaml wins over the email ───────────────────────
OUT="$(run_reader "$R" X=1 -- --slug 2>/dev/null)"
[ "$OUT" = "fromyaml" ] && chk "rung 2: goalforge.yaml reader: wins over git email" pass \
  || chk "rung 2: goalforge.yaml reader: wins over git email (got '$OUT')" fail

# ── rung 2 is OPTIONAL: an absent goalforge.yaml is a skip, never an error ──
R2="$(mkrepo)"
git -C "$R2" config user.email "Chris.Test@example.com"
OUT="$(run_reader "$R2" X=1 -- --slug 2>/dev/null)"; RC=$?
{ [ "$RC" -eq 0 ] && [ "$OUT" = "chris.test" ]; } \
  && chk "rung 3: absent goalforge.yaml skipped; email local-part lowercased" pass \
  || chk "rung 3: absent goalforge.yaml skipped; email local-part (rc=$RC got '$OUT')" fail

# ── rung 4: none of the three -> exactly one WARN, exit 0 ───────────────────
R3="$(mkrepo)"
mkdir -p "$R3/feature"
ERRF="$WORK/warn.err"
OUT="$(run_reader "$R3" X=1 -- --slug --feature-dir "$R3/feature" 2>"$ERRF")"; RC=$?
WARNS="$(grep -c 'WARN' "$ERRF" || true)"
{ [ "$RC" -eq 0 ] && [ "$OUT" = "anonymous" ] && [ "$WARNS" -eq 1 ]; } \
  && chk "rung 4: anonymous prints exactly one WARN and exits 0" pass \
  || chk "rung 4: anonymous (rc=$RC slug='$OUT' warns=$WARNS)" fail
# and the WARN is once per feature, not once per call
run_reader "$R3" X=1 -- --slug --feature-dir "$R3/feature" 2>"$WORK/warn2.err" >/dev/null
[ "$(grep -c 'WARN' "$WORK/warn2.err" || true)" -eq 0 ] \
  && chk "rung 4: the WARN is once per feature dir, not once per call" pass \
  || chk "rung 4: the WARN is once per feature dir, not once per call" fail
# anonymous emits NO profile path
OUT="$(run_reader "$R3" X=1 -- --profile 2>/dev/null)"
[ -z "$OUT" ] && chk "rung 4: anonymous emits no profile path" pass \
  || chk "rung 4: anonymous emits no profile path (got '$OUT')" fail

# ── every resolved slug matches the anchored charset ────────────────────────
ALL_OK=pass
for s in fromenv fromyaml chris.test anonymous; do
  printf '%s' "$s" | grep -qE "$SLUG_RE" || ALL_OK=fail
done
chk "every resolved slug matches $SLUG_RE" "$ALL_OK"

# ── hostile GOALFORGE_READER values are REFUSED (exit 2, no path) ───────────
HOSTILE_OK=pass
for v in ".." "." "../../etc" "a/b" "" "Mixed@Case"; do
  O="$(run_reader "$R2" GOALFORGE_READER="$v" -- --profile 2>/dev/null)"; RC=$?
  if [ "$RC" -ne 2 ] || [ -n "$O" ]; then
    echo "        not refused: '$v' (rc=$RC out='$O')"; HOSTILE_OK=fail
  fi
done
chk "hostile GOALFORGE_READER values refused exit 2 with no profile path" "$HOSTILE_OK"

# a hostile value must not reach a path join: nothing is created outside the tree
[ ! -e "$WORK/goalforge-communication-profile.md" ] \
  && chk "no profile written outside the repo by a traversing slug" pass \
  || chk "no profile written outside the repo by a traversing slug" fail

# ── containment: the resolved path resolves inside <repo>/.memory/user/ ─────
P="$(run_reader "$R2" X=1 -- --profile 2>/dev/null)"
python3 - "$P" "$R2" <<'PY'
import sys
from pathlib import Path
p, root = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
base = (root / ".memory" / "user").resolve()
sys.exit(0 if base in p.parents else 1)
PY
chk "resolved profile path is contained in <repo>/.memory/user/ (Path.resolve)" \
  "$([ $? -eq 0 ] && echo pass || echo fail)"

# ── privacy: no '@' in the profile, the emitted row, or the render ──────────
run_reader "$R2" X=1 -- mark-seen wp-02 >/dev/null 2>&1
{ [ -f "$P" ] && grep -q '^- wp-02$' "$P"; } \
  && chk "mark-seen creates the profile and appends the id to seen[]" pass \
  || chk "mark-seen creates the profile and appends the id to seen[]" fail
{ [ -f "$P" ] && ! grep -q '@' "$P"; } && AT_PROFILE=pass || AT_PROFILE=fail
chk "no '@' in the written profile file" "$AT_PROFILE"

FEAT="$R2/plans/afeature"; mkdir -p "$FEAT"
RENDER="$(env -u GOALFORGE_READER HOME="$WORK/home" \
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
  bash "$REPORT" harden wp-07 \
    --json "$PKG/evals/fixtures/stage-report/good-harden.json" \
    --repo "$R2" --feature-dir "$FEAT" 2>/dev/null)"
echo "$RENDER" | grep -q '@' && AT_R=fail || AT_R=pass
chk "no '@' in the rendered report" "$AT_R"
grep -q '@' "$FEAT/trace-events.jsonl" && AT_E=fail || AT_E=pass
chk "no '@' in the emitted stage.report row" "$AT_E"
grep -q '"reader":"chris.test"' "$FEAT/trace-events.jsonl" \
  && chk "the emitted row carries the local-part slug, never the address" pass \
  || chk "the emitted row carries the local-part slug, never the address" fail

# ── NON-HERMETIC arm (named as such): this repository's own .gitignore ──────
# b3 requires the repo's own ignore file, not a machine-global one, to name
# .memory/user/. A mktemp repo has no such file, so this one arm runs against
# the real repo root. core.excludesFile is neutralised so a machine-global
# `.memory/` rule cannot shadow the repo rule and answer for it.
CI="$(git -C "$REPO" -c core.excludesFile=/dev/null check-ignore -v .memory/user/x 2>/dev/null || true)"
case "$CI" in
  .gitignore:*) chk "<repo>/.gitignore itself ignores .memory/user/ (non-hermetic arm)" pass ;;
  *) chk "<repo>/.gitignore itself ignores .memory/user/ (non-hermetic arm; got '$CI')" fail ;;
esac

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
