#!/usr/bin/env bash
# sdd-onboard.sh — Idempotent SDD bootstrap for a git repository.
#
# Usage:
#   sdd-onboard.sh [<repo-dir>]
#
# Default repo-dir: git rev-parse --show-toplevel from CWD.
# Safe to re-run on an already-onboarded repo — all steps are idempotent.

set -euo pipefail

SDD_INSTALL_HOOKS="$HOME/.claude/skills/sdd/scripts/sdd-install-hooks.sh"

# ── Resolve target repo ────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    REPO_DIR="$1"
else
    REPO_DIR=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "sdd-onboard: ERROR — not in a git repo and no <repo-dir> provided." >&2
        exit 1
    }
fi

if ! git -C "$REPO_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "sdd-onboard: ERROR — '$REPO_DIR' is not a git repository." >&2
    exit 1
fi

REPO_DIR=$(cd "$REPO_DIR" && pwd)
echo "sdd-onboard: target repo → $REPO_DIR"

# ── Step 1: Create plans/ if absent ───────────────────────────────────────────
PLANS_DIR="$REPO_DIR/plans"
if [[ ! -d "$PLANS_DIR" ]]; then
    mkdir -p "$PLANS_DIR"
    cat > "$PLANS_DIR/README.md" <<'EOF'
# SDD Plans

This directory is the root for Spec-Driven Development plan artifacts.
See `CLAUDE.md ## SDD` for the chain overview and status vocabulary.
EOF
    echo "sdd-onboard: created $PLANS_DIR"
else
    echo "sdd-onboard: plans/ already exists — skipping"
fi

# ── Step 2: Install sdd-validate pre-commit hook ───────────────────────────────
echo "sdd-onboard: delegating hook install to sdd-install-hooks.sh"
bash "$SDD_INSTALL_HOOKS" "$REPO_DIR"

# ── Step 3: Stamp ## SDD block into CLAUDE.md ─────────────────────────────────
CLAUDE_MD="$REPO_DIR/CLAUDE.md"

read -r -d '' SDD_BLOCK <<'BLOCK' || true
## SDD

This repo uses the Spec-Driven Development chain (`/spec → /plan → /implement
→ /verify`). Plans live in `plans/<feature>/`. A pre-commit hook runs
`sdd-validate --strict` on touched features (installed via
`sdd-install-hooks.sh`). Status vocabulary: features
`draft→ready→active→completed→archived`; WPs
`draft→spec→hardened→ready→executing→verified`; tasks
`pending→in-progress→implemented→verified` (`implemented` = deterministic eval
passed + committed; `verified` is written only at the WP gate by sdd-verify).
BLOCK

if [[ -f "$CLAUDE_MD" ]]; then
    if grep -qF '## SDD' "$CLAUDE_MD" 2>/dev/null; then
        echo "sdd-onboard: ## SDD block already present in CLAUDE.md — skipping"
    else
        printf '\n%s\n' "$SDD_BLOCK" >> "$CLAUDE_MD"
        echo "sdd-onboard: appended ## SDD block to $CLAUDE_MD"
    fi
else
    printf '%s\n' "$SDD_BLOCK" > "$CLAUDE_MD"
    echo "sdd-onboard: created $CLAUDE_MD with ## SDD block"
fi

echo "sdd-onboard: done. Re-running is safe — all steps are idempotent."
exit 0
