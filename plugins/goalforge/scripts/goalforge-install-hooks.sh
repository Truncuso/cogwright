#!/usr/bin/env bash
# sdd-install-hooks.sh — idempotent, chain-safe installer for sdd-pre-commit.sh.
#
# Usage:
#   sdd-install-hooks.sh [<repo-dir>]
#
# Default repo-dir: git rev-parse --show-toplevel from CWD.
# Hooks dir is resolved via:  git -C <repo> rev-parse --git-path hooks
# (respects core.hooksPath and worktrees).
#
# Behavior:
#   - No pre-commit exists → write a minimal wrapper, chmod +x.
#   - pre-commit exists with marker  → no-op ("already installed").
#   - pre-commit exists without marker → append a guarded block; never overwrite.
#
# Idempotency marker: # >>> sdd-pre-commit >>>

set -euo pipefail

MARKER_OPEN="# >>> sdd-pre-commit >>>"
MARKER_CLOSE="# <<< sdd-pre-commit <<<"
# Resolve the pre-commit hook package-relative (local authority), falling back
# to the installed dotfiles goalforge path.
_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -f "$_SCRIPT_DIR/../hooks/goalforge-pre-commit.sh" ]]; then
    SDD_HOOK_PATH="$(cd "$_SCRIPT_DIR/../hooks" && pwd)/goalforge-pre-commit.sh"
else
    SDD_HOOK_PATH="$HOME/.claude/skills/goalforge/hooks/goalforge-pre-commit.sh"
fi

# ── Resolve target repo ────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    REPO_DIR="$1"
else
    REPO_DIR=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "sdd-install-hooks: ERROR — not in a git repo and no <repo-dir> provided." >&2
        exit 1
    }
fi

# Canonicalize REPO_DIR
REPO_DIR=$(cd "$REPO_DIR" && pwd)

# ── Resolve hooks dir (respects custom hooksPath / worktrees) ─────────────────
HOOKS_DIR=$(git -C "$REPO_DIR" rev-parse --git-path hooks 2>/dev/null) || {
    echo "sdd-install-hooks: ERROR — cannot resolve hooks dir for $REPO_DIR" >&2
    exit 1
}

# --git-path returns a relative path when inside a standard repo; resolve it
if [[ "$HOOKS_DIR" != /* ]]; then
    HOOKS_DIR="$REPO_DIR/$HOOKS_DIR"
fi

mkdir -p "$HOOKS_DIR"
TARGET="$HOOKS_DIR/pre-commit"

# ── Case 1: no existing hook → write a minimal wrapper ────────────────────────
if [[ ! -f "$TARGET" ]]; then
    cat > "$TARGET" <<EOF
#!/usr/bin/env bash
$MARKER_OPEN
bash "$SDD_HOOK_PATH" || exit \$?
$MARKER_CLOSE
EOF
    chmod +x "$TARGET"
    echo "sdd-install-hooks: installed pre-commit hook at $TARGET"
    exit 0
fi

# ── Case 2: hook exists with marker → no-op (idempotent) ─────────────────────
if grep -qF "$MARKER_OPEN" "$TARGET" 2>/dev/null; then
    echo "sdd-install-hooks: already installed (marker found) — no-op"
    exit 0
fi

# ── Case 3: hook exists without marker → chain-safe append ───────────────────
# The existing hook's exit semantics are preserved: if it exits non-zero,
# that blocks the commit before our code runs. If it exits 0 (or falls
# through), the appended block runs and can also block on SDD drift.
cat >> "$TARGET" <<EOF

$MARKER_OPEN
# sdd integrity check — blocks on sdd-validate --strict ERROR in touched features
# Use 'cmd || exit \$?' (NOT '[[…]] && exit') so a passing check does not leave the
# hook's final command exit-code falsy, which would block every commit.
bash "$SDD_HOOK_PATH" || exit \$?
$MARKER_CLOSE
EOF

echo "sdd-install-hooks: appended sdd-pre-commit block to existing hook at $TARGET"
exit 0
