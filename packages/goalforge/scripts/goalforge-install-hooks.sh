#!/usr/bin/env bash
# goalforge-install-hooks.sh — idempotent, chain-safe installer for goalforge-pre-commit.sh.
#
# Usage:
#   goalforge-install-hooks.sh [<repo-dir>]
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
# Resolve the pre-commit hook script-relative. hooks/ is a sibling of scripts/
# in BOTH install routes — packages/goalforge/ (contributor symlink) and the
# generated flat plugins/goalforge/ — so this needs no author path and no
# ${CLAUDE_PLUGIN_ROOT} (which is unset outside a plugin run and would abort
# under `set -u`). The canonicalizing branch is preferred so the path baked
# into the generated git hook carries no `..` climb.
_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -d "$_SCRIPT_DIR/../hooks" ]]; then
    SDD_HOOK_PATH="$(cd "$_SCRIPT_DIR/../hooks" && pwd)/goalforge-pre-commit.sh"
else
    SDD_HOOK_PATH="$_SCRIPT_DIR/../hooks/goalforge-pre-commit.sh"
fi

# ── Resolve target repo ────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    REPO_DIR="$1"
else
    REPO_DIR=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "goalforge-install-hooks: ERROR — not in a git repo and no <repo-dir> provided." >&2
        exit 1
    }
fi

# Canonicalize REPO_DIR
REPO_DIR=$(cd "$REPO_DIR" && pwd)

# ── Resolve hooks dir (respects custom hooksPath / worktrees) ─────────────────
HOOKS_DIR=$(git -C "$REPO_DIR" rev-parse --git-path hooks 2>/dev/null) || {
    echo "goalforge-install-hooks: ERROR — cannot resolve hooks dir for $REPO_DIR" >&2
    exit 1
}

# --git-path returns a relative path when inside a standard repo; resolve it
if [[ "$HOOKS_DIR" != /* ]]; then
    HOOKS_DIR="$REPO_DIR/$HOOKS_DIR"
fi

mkdir -p "$HOOKS_DIR"
TARGET="$HOOKS_DIR/pre-commit"

# ── Guard: never write through a path shared with anything outside this repo ──
# A pre-commit that resolves outside the repo points at a SHARED file
# (historically ~/.claude/hooks/templates/git/pre-commit, installed as a
# symlink). Appending through it corrupts that file for every repo pointing at
# it. Three doors lead there, so all three are closed:
#   - the hook file is a symlink;
#   - the hooks DIRECTORY is a symlink, or core.hooksPath points outside the
#     repo (a repo-local core.hooksPath such as .githooks/ stays allowed);
#   - the hook file is a hardlink to a file with another name.
# Checked before the existence cases: `-f` is false for a dangling symlink, and
# `cat >` would follow it just the same.
refuse_shared() {
    echo "goalforge-install-hooks: ERROR — refusing to write $TARGET: $1" >&2
    echo '  Writing here would corrupt a shared file. Install a real hook first:' >&2
    echo "    bash \"\$HOME/.claude/scripts/install-guardrails.sh\" \"$REPO_DIR\"" >&2
    exit 2
}

if [[ -L "$TARGET" ]]; then
    refuse_shared "it is a symlink to $(readlink "$TARGET")"
fi

# Resolve the hook's real location and require it to sit inside the working
# tree or inside the git common dir (the latter covers linked worktrees, whose
# hooks live in the MAIN repo's git dir).
TARGET_REAL="$(cd "$(dirname "$TARGET")" && pwd -P)/$(basename "$TARGET")"
REPO_REAL="$(cd "$REPO_DIR" && pwd -P)"
COMMON_DIR="$(git -C "$REPO_DIR" rev-parse --git-common-dir 2>/dev/null || echo "$REPO_DIR/.git")"
[[ "$COMMON_DIR" == /* ]] || COMMON_DIR="$REPO_DIR/$COMMON_DIR"
COMMON_REAL="$(cd "$COMMON_DIR" 2>/dev/null && pwd -P || echo "$COMMON_DIR")"

if [[ "$TARGET_REAL" != "$REPO_REAL"/* && "$TARGET_REAL" != "$COMMON_REAL"/* ]]; then
    refuse_shared "it resolves to $TARGET_REAL, outside $REPO_REAL"
fi

# A hardlink has no readable target, so link count is the only signal that the
# same inode answers to another name.
if [[ -f "$TARGET" ]]; then
    LINK_COUNT="$(stat -c %h "$TARGET" 2>/dev/null || echo 1)"
    if [[ "$LINK_COUNT" -gt 1 ]]; then
        refuse_shared "it is a hardlink (link count $LINK_COUNT)"
    fi
fi

# ── Case 1: no existing hook → write a minimal wrapper ────────────────────────
if [[ ! -f "$TARGET" ]]; then
    cat > "$TARGET" <<EOF
#!/usr/bin/env bash
$MARKER_OPEN
bash "$SDD_HOOK_PATH" || exit \$?
$MARKER_CLOSE
EOF
    chmod +x "$TARGET"
    echo "goalforge-install-hooks: installed pre-commit hook at $TARGET"
    exit 0
fi

# ── Case 2: hook exists with marker → no-op (idempotent) ─────────────────────
if grep -qF "$MARKER_OPEN" "$TARGET" 2>/dev/null; then
    echo "goalforge-install-hooks: already installed (marker found) — no-op"
    exit 0
fi

# ── Case 3: hook exists without marker → chain-safe append ───────────────────
# The existing hook's exit semantics are preserved: if it exits non-zero,
# that blocks the commit before our code runs. If it exits 0 (or falls
# through), the appended block runs and can also block on SDD drift.
cat >> "$TARGET" <<EOF

$MARKER_OPEN
# goalforge integrity check — blocks on goalforge-validate --strict ERROR in touched features
# Use 'cmd || exit \$?' (NOT '[[…]] && exit') so a passing check does not leave the
# hook's final command exit-code falsy, which would block every commit.
bash "$SDD_HOOK_PATH" || exit \$?
$MARKER_CLOSE
EOF

echo "sdd-install-hooks: appended sdd-pre-commit block to existing hook at $TARGET"
exit 0
