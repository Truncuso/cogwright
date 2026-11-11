#!/usr/bin/env bash
# goalforge-privacy-lint.test.sh — b12: the ci-lints.sh privacy-marker section
# pins the plugin's discoverable child set BY NAME and the package Gotcha
# phrase, not merely a child count.
#
# ci-lints.sh does `cd` to its own repo root, so each arm copies the script and
# the trees it reads into a fresh temp repo and runs `--only privacy-marker`.
#
#   arm 0       : unmodified copy, must pass (rc 0).
#   arm a       : one plugin child dir renamed, count stays 13 -> rc 1, stderr
#                 names the old and the new child name.
#   arm b       : a package-only child dir with SKILL.md -> rc 1, stderr names it.
#   arm c       : the Gotcha phrase dropped -> rc 1, stderr carries the phrase.
#   add-one     : one extra plugin child dir -> rc 1 (regression guard).
#   remove-one  : one plugin child dir removed -> rc 1 (regression guard).
#
# rc must be exactly 1: rc 2 is the dispatcher's own error (missing PyYAML,
# zero scanned), which would otherwise pass a "non-zero" check vacuously.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SD/../../../.." && pwd)"
PASS=0; FAIL=0

ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

PHRASE='plugin-discoverable as goalforge:<child>'

# make_repo <dest> — the files the privacy-marker section reads, nothing else.
make_repo() {
    local d="$1" f
    mkdir -p "$d/scripts" "$d/plugins/goalforge" "$d/packages/goalforge"
    cp "$REPO/scripts/ci-lints.sh" "$d/scripts/ci-lints.sh"
    cp "$REPO/plugins/goalforge/SKILL.md" "$d/plugins/goalforge/SKILL.md"
    cp -R "$REPO/plugins/goalforge/skills" "$d/plugins/goalforge/skills"
    cp "$REPO/packages/goalforge/SKILL.md" "$d/packages/goalforge/SKILL.md"
    for f in "$REPO"/packages/goalforge/*/SKILL.md; do
        mkdir -p "$d/packages/goalforge/$(basename "$(dirname "$f")")"
        cp "$f" "$d/packages/goalforge/$(basename "$(dirname "$f")")/SKILL.md"
    done
}

# run_lint <dest> — sets RC and ERR.
run_lint() {
    ERR="$(bash "$1/scripts/ci-lints.sh" --only privacy-marker 2>&1 >/dev/null)"
    RC=$?
}

# expect_fail <label> <dest> <needle>... — rc 1 and every needle in stderr.
expect_fail() {
    local label="$1" d="$2" n miss=""
    shift 2
    run_lint "$d"
    for n in "$@"; do
        grep -qF -- "$n" <<<"$ERR" || miss="$miss '$n'"
    done
    if [[ "$RC" -eq 1 && -z "$miss" ]]; then
        ok "$label"
    else
        bad "$label (rc=$RC, stderr lacks:${miss:- -})"
        echo "$ERR" | sed 's/^/    /'
    fi
}

echo "arm 0: unmodified"
make_repo "$T/arm0"
run_lint "$T/arm0"
if [[ "$RC" -eq 0 ]]; then
    ok "unmodified copy passes"
else
    bad "unmodified copy passes (rc=$RC)"
    echo "$ERR" | sed 's/^/    /'
fi

echo "arm a: plugin child renamed, count unchanged"
make_repo "$T/arma"
mv "$T/arma/plugins/goalforge/skills/archive" "$T/arma/plugins/goalforge/skills/archivist"
expect_fail "renamed plugin child is rejected naming the new name" "$T/arma" "archivist"
# "archive" is a substring of "archivist": require it as its own word.
if grep -qw archive <<<"${ERR//archivist/}"; then
    ok "renamed plugin child stderr names the old name"
else
    bad "renamed plugin child stderr names the old name"
fi

echo "arm b: package-only child"
make_repo "$T/armb"
mkdir -p "$T/armb/packages/goalforge/stray-child"
cp "$T/armb/packages/goalforge/archive/SKILL.md" "$T/armb/packages/goalforge/stray-child/SKILL.md"
expect_fail "package-only child dir is rejected naming it" "$T/armb" "stray-child"

echo "arm c: Gotcha phrase dropped"
make_repo "$T/armc"
python3 - "$T/armc/packages/goalforge/SKILL.md" "$PHRASE" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
s2 = s.replace(sys.argv[2], "")
p.write_text(s2, encoding="utf-8")
sys.exit(0 if s2 != s else 1)
PY
[[ $? -eq 0 ]] || bad "arm c had a Gotcha phrase to drop"
expect_fail "dropped Gotcha phrase is rejected quoting it" "$T/armc" "$PHRASE"

echo "regression guards: add-one, remove-one"
make_repo "$T/add"
cp -R "$T/add/plugins/goalforge/skills/archive" "$T/add/plugins/goalforge/skills/extra-child"
expect_fail "added plugin child is rejected" "$T/add"
make_repo "$T/rm"
rm -rf "$T/rm/plugins/goalforge/skills/wayfind"
expect_fail "removed plugin child is rejected" "$T/rm"

echo
echo "goalforge-privacy-lint.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
