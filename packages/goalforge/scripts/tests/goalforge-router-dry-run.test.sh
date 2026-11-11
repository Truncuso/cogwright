#!/usr/bin/env bash
# goalforge-router-dry-run.test.sh — oracle for b6 (goalforge-router.sh --dry-run).
#
#   unknown slug        exit 3, stderr names $FIXTURE_ROOT/<slug>    (both trees)
#   fixture feature     exit 0, all 7 steps RESOLVED                 (both trees)
#   git-repo            SDD_PLANS_DIR unset, cwd inside a git repo holding
#                       plans/<feature>/ -> exit 0                   (both trees)
#   missing chain.yaml  temp tree, exit 1 before any feature check
#   prefix-less step    temp tree, `skill: capture` -> `capture: UNRESOLVED`, exit 1
#   poisoned HOME       HOME holds skills stubs for every step; every RESOLVED
#                       path lies under the router's own tree, none under $HOME;
#                       the temp-tree prefix-less step stays UNRESOLVED
#   broken child        poisoned HOME, temp tree with one goalforge/<child>
#                       SKILL.md deleted -> `goalforge/<child>: UNRESOLVED`, exit 1
#
# Every run is hermetic: HOME is a temp dir, CLAUDE_SKILLS_ROOT is unset, and
# the SDD_PLANS_DIR arms run from a non-git `mktemp -d` cwd so the git-root leg
# of goalforge_plans_roots cannot pick up a developer's local plans tree.
set -uo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$SD/../.." && pwd)"
PKG_ROUTER="$PKG/run/scripts/goalforge-router.sh"
PLUGIN_ROUTER="$PKG/../../plugins/goalforge/skills/run/scripts/goalforge-router.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

unset CLAUDE_SKILLS_ROOT SDD_PLANS_DIR
EMPTY_HOME="$T/home-empty"; mkdir -p "$EMPTY_HOME"
CWD="$T/cwd"; mkdir -p "$CWD"
FIXTURE_ROOT="$T/plans"; mkdir -p "$FIXTURE_ROOT/fixture-feature"
SLUG="no-such-feature-$$"

# $1 cwd, $2 HOME, $3 SDD_PLANS_DIR ("" = unset), $4.. router args -> OUT, ERR, RC
run_router() {
    local cwd="$1" home="$2" plans="$3"; shift 3
    RC=0
    if [ -n "$plans" ]; then
        OUT="$(cd "$cwd" && HOME="$home" SDD_PLANS_DIR="$plans" bash "$@" 2>"$T/err")" || RC=$?
    else
        OUT="$(cd "$cwd" && HOME="$home" bash "$@" 2>"$T/err")" || RC=$?
    fi
    ERR="$(cat "$T/err")"
}

echo "=== goalforge-router-dry-run.test.sh ==="

for tree in package plugin; do
    if [ "$tree" = package ]; then R="$PKG_ROUTER"; else R="$PLUGIN_ROUTER"; fi
    if [ ! -f "$R" ]; then bad "$tree tree: router not found at $R"; continue; fi

    run_router "$CWD" "$EMPTY_HOME" "$FIXTURE_ROOT" "$R" --dry-run "$SLUG"
    if [ "$RC" -eq 3 ] && grep -qF -- "$FIXTURE_ROOT/$SLUG" <<<"$ERR"; then
        ok "$tree tree: unknown slug exits 3 naming $FIXTURE_ROOT/<slug>"
    else
        bad "$tree tree: unknown slug must exit 3 naming the path (rc=$RC, stderr=$ERR)"
    fi

    run_router "$CWD" "$EMPTY_HOME" "$FIXTURE_ROOT" "$R" --dry-run fixture-feature
    n="$(grep -c ': RESOLVED (' <<<"$OUT" || true)"
    if [ "$RC" -eq 0 ] && [ "$n" -eq 7 ] && ! grep -q UNRESOLVED <<<"$OUT"; then
        ok "$tree tree: fixture feature exits 0 with all 7 steps RESOLVED"
    else
        bad "$tree tree: fixture feature must exit 0 with 7 RESOLVED (rc=$RC, resolved=$n)"
    fi

    REPO="$T/repo-$tree"; mkdir -p "$REPO/plans/git-feature/sub"
    git -C "$REPO" init -q
    run_router "$REPO/plans/git-feature/sub" "$EMPTY_HOME" "" "$R" --dry-run git-feature
    if [ "$RC" -eq 0 ]; then
        ok "$tree tree: git-repo plans/<feature> resolves with SDD_PLANS_DIR unset (exit 0)"
    else
        bad "$tree tree: git-repo case must exit 0 (rc=$RC, stderr=$ERR)"
    fi

    # cwd = repo root: only a "$PWD/." anchor (not "$PWD") finds the git root here.
    run_router "$REPO" "$EMPTY_HOME" "" "$R" --dry-run git-feature
    if [ "$RC" -eq 0 ]; then
        ok "$tree tree: git-repo case from the repo root exits 0"
    else
        bad "$tree tree: git-repo case from the repo root must exit 0 (rc=$RC, stderr=$ERR)"
    fi

    # Exit-3 stderr names every candidate root, in resolver order.
    run_router "$REPO" "$EMPTY_HOME" "$FIXTURE_ROOT" "$R" --dry-run "$SLUG"
    want="goalforge-router: feature directory not found: $FIXTURE_ROOT/$SLUG
goalforge-router: feature directory not found: $(cd "$REPO" && pwd -P)/plans/$SLUG
goalforge-router: feature directory not found: $EMPTY_HOME/.claude/plans/$SLUG"
    if [ "$RC" -eq 3 ] && [ "$ERR" = "$want" ]; then
        ok "$tree tree: exit-3 stderr lists all three candidate roots in resolver order"
    else
        bad "$tree tree: exit-3 stderr must list every candidate root in order (rc=$RC, stderr=$ERR)"
    fi

    # A regular file named like the slug is not a feature directory.
    : > "$FIXTURE_ROOT/plain-file-slug"
    run_router "$CWD" "$EMPTY_HOME" "$FIXTURE_ROOT" "$R" --dry-run plain-file-slug
    if [ "$RC" -eq 3 ]; then
        ok "$tree tree: a regular file named like the slug exits 3"
    else
        bad "$tree tree: a regular file named like the slug must exit 3 (rc=$RC)"
    fi
    rm -f "$FIXTURE_ROOT/plain-file-slug"
done

# ── temp tree in package layout ──────────────────────────────────────────────
# $1 dir, $2 router source -> run/scripts router, run/chain.yaml, hooks helper,
# and an own SKILL.md for every child of the real chain plus `capture`.
make_tree() {
    local d="$1" src="$2" c
    mkdir -p "$d/run/scripts" "$d/hooks"
    cp "$src" "$d/run/scripts/goalforge-router.sh"
    cp "$PKG/hooks/goalforge-plans-root.sh" "$d/hooks/goalforge-plans-root.sh"
    for c in capture spec decompose harden execute verify redecompose; do
        mkdir -p "$d/$c"; printf -- '---\nname: %s\n---\n' "$c" > "$d/$c/SKILL.md"
    done
}
PREFIXLESS_CHAIN='steps:
  - skill: goalforge/spec
  - skill: capture
'
PREFIXED_CHAIN='steps:
  - skill: goalforge/capture
  - skill: goalforge/spec
'

# Missing chain.yaml: exit 1, and the feature check never runs (the slug is unknown,
# so a router that checks the feature first exits 3).
MC="$T/tree-missing-chain"; make_tree "$MC" "$PKG_ROUTER"
run_router "$CWD" "$EMPTY_HOME" "$FIXTURE_ROOT" "$MC/run/scripts/goalforge-router.sh" --dry-run "$SLUG"
if [ "$RC" -eq 1 ] && grep -qF 'chain.yaml not found' <<<"$ERR"; then
    ok "missing chain.yaml exits 1 before any feature check"
else
    bad "missing chain.yaml must exit 1 before the feature check (rc=$RC, stderr=$ERR)"
fi

# Plans-root helper missing (no hooks dir in the tree): exit 1 with a named error.
for tree in package plugin; do
    if [ "$tree" = package ]; then R="$PKG_ROUTER"; else R="$PLUGIN_ROUTER"; fi
    [ -f "$R" ] || continue
    NH="$T/tree-no-helper-$tree"; make_tree "$NH" "$R"; rm -rf "$NH/hooks"
    printf '%s' "$PREFIXED_CHAIN" > "$NH/run/chain.yaml"
    run_router "$CWD" "$EMPTY_HOME" "$FIXTURE_ROOT" "$NH/run/scripts/goalforge-router.sh" --dry-run fixture-feature
    if [ "$RC" -eq 1 ] && grep -qx 'goalforge-router: plans-root helper not found' <<<"$ERR"; then
        ok "$tree router: missing plans-root helper exits 1 naming it"
    else
        bad "$tree router: missing plans-root helper must exit 1 naming it (rc=$RC, stderr=$ERR)"
    fi
done

# Prefix-less step naming a real child: UNRESOLVED, exit 1.
PL="$T/tree-prefixless"; make_tree "$PL" "$PKG_ROUTER"; printf '%s' "$PREFIXLESS_CHAIN" > "$PL/run/chain.yaml"
run_router "$CWD" "$EMPTY_HOME" "$FIXTURE_ROOT" "$PL/run/scripts/goalforge-router.sh" --dry-run fixture-feature
if [ "$RC" -eq 1 ] && grep -q '^capture: UNRESOLVED$' <<<"$OUT"; then
    ok "prefix-less step (skill: capture) is UNRESOLVED, exit 1"
else
    bad "prefix-less step must be UNRESOLVED with exit 1 (rc=$RC, out=$OUT)"
fi

# ── poisoned HOME ────────────────────────────────────────────────────────────
POISON="$T/home-poison"
for c in capture spec decompose harden execute verify redecompose; do
    mkdir -p "$POISON/.claude/skills/goalforge/$c"
    printf -- '---\nname: %s\n---\n' "$c" > "$POISON/.claude/skills/goalforge/$c/SKILL.md"
done
mkdir -p "$POISON/.claude/skills/capture"
printf -- '---\nname: capture\n---\n' > "$POISON/.claude/skills/capture/SKILL.md"
POISON_REAL="$(realpath "$POISON")"

for tree in package plugin; do
    if [ "$tree" = package ]; then R="$PKG_ROUTER"; else R="$PLUGIN_ROUTER"; fi
    [ -f "$R" ] || continue
    own="$(realpath "$(dirname "$R")/../..")"
    run_router "$CWD" "$POISON" "$FIXTURE_ROOT" "$R" --dry-run fixture-feature
    paths="$(sed -n 's/^.*: RESOLVED (\(.*\))$/\1/p' <<<"$OUT")"
    n=0; stray=""
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        n=$((n+1))
        rp="$(realpath "$p")"
        case "$rp" in "$POISON_REAL"/*) stray="$stray $rp"; continue ;; esac
        case "$rp" in "$own"/*) ;; *) stray="$stray $rp" ;; esac
    done <<<"$paths"
    if [ "$RC" -eq 0 ] && [ "$n" -eq 7 ] && [ -z "$stray" ]; then
        ok "$tree tree, poisoned HOME: all 7 RESOLVED paths lie under $own, none under \$HOME"
    else
        bad "$tree tree, poisoned HOME: RESOLVED paths must lie under the router's own tree (rc=$RC, resolved=$n, stray=$stray)"
    fi
done

run_router "$CWD" "$POISON" "$FIXTURE_ROOT" "$PL/run/scripts/goalforge-router.sh" --dry-run fixture-feature
if [ "$RC" -eq 1 ] && grep -q '^capture: UNRESOLVED$' <<<"$OUT"; then
    ok "poisoned HOME: prefix-less step stays UNRESOLVED, exit 1"
else
    bad "poisoned HOME: prefix-less step must stay UNRESOLVED (rc=$RC, out=$OUT)"
fi

# Broken child: the temp tree's own goalforge/capture SKILL.md is deleted; the
# poisoned HOME still has one, so only a router that falls back to $HOME resolves it.
BC="$T/tree-broken-child"; make_tree "$BC" "$PKG_ROUTER"; printf '%s' "$PREFIXED_CHAIN" > "$BC/run/chain.yaml"
rm -f "$BC/capture/SKILL.md"
run_router "$CWD" "$POISON" "$FIXTURE_ROOT" "$BC/run/scripts/goalforge-router.sh" --dry-run fixture-feature
if [ "$RC" -eq 1 ] && grep -q '^goalforge/capture: UNRESOLVED$' <<<"$OUT"; then
    ok "poisoned HOME: a deleted own goalforge/capture SKILL.md is UNRESOLVED, exit 1"
else
    bad "poisoned HOME: deleted own SKILL.md must print goalforge/capture: UNRESOLVED and exit 1 (rc=$RC, out=$OUT)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
