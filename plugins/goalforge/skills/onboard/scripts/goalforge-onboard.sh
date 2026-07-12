#!/usr/bin/env bash
# goalforge-onboard.sh — Idempotent SDD bootstrap for a git repository.
#
# Usage:
#   goalforge-onboard.sh [<repo-dir>]
#
# Default repo-dir: git rev-parse --show-toplevel from CWD.
# Safe to re-run on an already-onboarded repo — all steps are idempotent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDD_INSTALL_HOOKS="$SCRIPT_DIR/../../../scripts/goalforge-install-hooks.sh"

# ── Resolve target repo ────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    REPO_DIR="$1"
else
    REPO_DIR=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "goalforge-onboard: ERROR — not in a git repo and no <repo-dir> provided." >&2
        exit 1
    }
fi

if ! git -C "$REPO_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "goalforge-onboard: ERROR — '$REPO_DIR' is not a git repository." >&2
    exit 1
fi

REPO_DIR=$(cd "$REPO_DIR" && pwd)
echo "goalforge-onboard: target repo → $REPO_DIR"

# ── Step 1: Create plans/ if absent ───────────────────────────────────────────
PLANS_DIR="$REPO_DIR/plans"
if [[ ! -d "$PLANS_DIR" ]]; then
    mkdir -p "$PLANS_DIR"
    cat > "$PLANS_DIR/README.md" <<'EOF'
# SDD Plans

This directory is the root for Spec-Driven Development plan artifacts.
See `CLAUDE.md ## SDD` for the chain overview and status vocabulary.
EOF
    echo "goalforge-onboard: created $PLANS_DIR"
else
    echo "goalforge-onboard: plans/ already exists — skipping"
fi

# ── Step 2: Install goalforge-validate pre-commit hook ───────────────────────────────
echo "goalforge-onboard: delegating hook install to goalforge-install-hooks.sh"
bash "$SDD_INSTALL_HOOKS" "$REPO_DIR"

# ── Step 3: Stamp ## SDD block into CLAUDE.md ─────────────────────────────────
CLAUDE_MD="$REPO_DIR/CLAUDE.md"

read -r -d '' SDD_BLOCK <<'BLOCK' || true
## SDD

This repo uses the Spec-Driven Development chain (`/spec → /plan → /implement
→ /verify`). Plans live in `plans/<feature>/`. A pre-commit hook runs
`goalforge-validate --strict` on touched features (installed via
`goalforge-install-hooks.sh`). Status vocabulary: features
`draft→ready→active→completed→archived`; WPs
`draft→spec→hardened→ready→executing→verified`; tasks
`pending→in-progress→implemented→verified` (`implemented` = deterministic eval
passed + committed; `verified` is written only at the WP gate by goalforge-verify).
BLOCK

if [[ -f "$CLAUDE_MD" ]]; then
    if grep -qF '## SDD' "$CLAUDE_MD" 2>/dev/null; then
        echo "goalforge-onboard: ## SDD block already present in CLAUDE.md — skipping"
    else
        printf '\n%s\n' "$SDD_BLOCK" >> "$CLAUDE_MD"
        echo "goalforge-onboard: appended ## SDD block to $CLAUDE_MD"
    fi
else
    printf '%s\n' "$SDD_BLOCK" > "$CLAUDE_MD"
    echo "goalforge-onboard: created $CLAUDE_MD with ## SDD block"
fi

echo "goalforge-onboard: done. Re-running is safe — all steps are idempotent."
exit 0
