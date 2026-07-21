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

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
