#!/usr/bin/env bash
# Regression test for goalforge-pre-commit.sh — block + allow cases.
# Focus: the full-tree-feature-gated validation fix. A staged feature carrying a
# legitimate CROSS-FEATURE edge ([[sibling-feature]]) must ALLOW (the sibling
# resolves in a full-tree walk); a staged feature with its OWN schema error must
# BLOCK. Hermetic: builds a throwaway git repo, stages, runs the hook, asserts rc.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/goalforge-pre-commit.sh"
VALIDATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/goalforge-validate.sh"
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass+1)); }
no() { echo "FAIL: $1 — $2"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q
git -C "$TMP" config user.email t@t.t
git -C "$TMP" config user.name t

mk_feature() { # <slug> <status> [relationships-block]
    local slug="$1" status="$2" rel="${3:-}"
    local d="$TMP/plans/$slug"
    mkdir -p "$d"
    {
        echo "---"
        echo "name: $slug"
        echo "title: $slug"
        echo "status: $status"
        echo "created: 2026-06-29"
        echo "feature: $slug"
        echo "work_packages: []"
        printf '%s' "$rel"
        echo "---"
        echo ""
        echo "## Problem"
        echo "x"
    } > "$d/overview.md"
}

run_hook() { # runs the hook with the staged index of $TMP; echoes rc
    ( cd "$TMP" && GOALFORGE_VALIDATE_SCRIPT="$VALIDATE" bash "$HOOK" >/dev/null 2>&1 )
    echo $?
}

# A stable sibling target so the cross-feature wikilink resolves on a full walk.
mk_feature foundation ready
git -C "$TMP" add -A >/dev/null; git -C "$TMP" commit -qm seed

# ── ALLOW: a clean feature whose overview carries a cross-feature edge ─────────
REL=$'relationships:\n  - depends_on: [[foundation]]\n'
mk_feature consumer ready "$REL"
git -C "$TMP" add plans/consumer/overview.md >/dev/null
rc=$(run_hook)
if [[ "$rc" -eq 0 ]]; then ok "allow-cross-feature-edge"; else no "allow-cross-feature-edge" "rc=$rc (expected 0)"; fi
git -C "$TMP" add -A >/dev/null; git -C "$TMP" commit -qm consumer

# ── BLOCK: a feature with its OWN invalid status enum ─────────────────────────
mk_feature broken not-a-valid-status
git -C "$TMP" add plans/broken/overview.md >/dev/null
rc=$(run_hook)
if [[ "$rc" -eq 1 ]]; then ok "block-own-error"; else no "block-own-error" "rc=$rc (expected 1)"; fi

# ── BLOCK with a POISONED CLAUDE_PLUGIN_ROOT ──────────────────────────────────
# The hook runs in whatever environment the invoking git tool carries, so its
# default validator address must not be steerable by one: with the same broken
# feature staged, a bogus CLAUDE_PLUGIN_ROOT and NO GOALFORGE_VALIDATE_SCRIPT,
# the script-relative default must still resolve and still block. If the hook
# ever reads that variable again this case turns green-to-red (skip notice on
# stderr, rc 0).
rc=$( ( cd "$TMP" && CLAUDE_PLUGIN_ROOT=/nonexistent bash "$HOOK" >/dev/null 2>&1 ); echo $? )
if [[ "$rc" -eq 1 ]]; then ok "block-with-poisoned-CLAUDE_PLUGIN_ROOT"; else no "block-with-poisoned-CLAUDE_PLUGIN_ROOT" "rc=$rc (expected 1)"; fi

# ── PLANS-REPO-ROOTED layout (goalforge-plans-root.sh leg 2b) ──────────────────
# The plans tree kept as its OWN git repo — the git root is itself named
# `plans`, so staged paths are rooted directly at the feature (no `plans/`
# path segment at all). Without the fix, the plans/<feature>/ predicate
# extracts zero features from every such path and the hook never validates.
TMP2="$(mktemp -d)/plans"
mkdir -p "$TMP2"
trap 'rm -rf "$TMP"; rm -rf "$(dirname "$TMP2")"' EXIT
git -C "$TMP2" init -q
git -C "$TMP2" config user.email t@t.t
git -C "$TMP2" config user.name t

mk_feature_rooted() { # <slug> <status> [relationships-block]
    local slug="$1" status="$2" rel="${3:-}"
    local d="$TMP2/$slug"
    mkdir -p "$d"
    {
        echo "---"
        echo "name: $slug"
        echo "title: $slug"
        echo "status: $status"
        echo "created: 2026-06-29"
        echo "feature: $slug"
        echo "work_packages: []"
        printf '%s' "$rel"
        echo "---"
        echo ""
        echo "## Problem"
        echo "x"
    } > "$d/overview.md"
}

run_hook_rooted() { # runs the hook with the staged index of $TMP2; echoes rc
    ( cd "$TMP2" && GOALFORGE_VALIDATE_SCRIPT="$VALIDATE" bash "$HOOK" >/dev/null 2>&1 )
    echo $?
}

mk_feature_rooted foundation2 ready
git -C "$TMP2" add -A >/dev/null; git -C "$TMP2" commit -qm seed

# ── ALLOW (plans-repo-rooted): a clean feature ─────────────────────────────────
mk_feature_rooted consumer2 ready
git -C "$TMP2" add consumer2/overview.md >/dev/null
rc=$(run_hook_rooted)
if [[ "$rc" -eq 0 ]]; then ok "plans-repo-rooted: allow-clean-feature"; else no "plans-repo-rooted: allow-clean-feature" "rc=$rc (expected 0)"; fi
git -C "$TMP2" add -A >/dev/null; git -C "$TMP2" commit -qm consumer2

# ── BLOCK (plans-repo-rooted): a feature with its OWN invalid status enum ──────
mk_feature_rooted broken2 not-a-valid-status
git -C "$TMP2" add broken2/overview.md >/dev/null
rc=$(run_hook_rooted)
if [[ "$rc" -eq 1 ]]; then ok "plans-repo-rooted: block-own-error"; else no "plans-repo-rooted: block-own-error" "rc=$rc (expected 1)"; fi
git -C "$TMP2" reset >/dev/null

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
