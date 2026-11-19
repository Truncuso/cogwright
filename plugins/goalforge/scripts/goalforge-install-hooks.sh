#!/usr/bin/env bash
# goalforge-install-hooks.sh — idempotent, chain-safe installer for the goalforge git hooks.
#
# Usage:
#   goalforge-install-hooks.sh [<repo-dir>] [--only <id>]...
#
# Default repo-dir: git rev-parse --show-toplevel from CWD.
# Hooks dir is resolved via:  git -C <repo> rev-parse --git-path hooks
# (respects core.hooksPath and worktrees).
#
# Installs every entry of HOOKS, or only the entries named by --only (repeatable,
# one id per flag; <repo-dir> may stand before or after it). Each entry owns one
# block, opened and closed by its own marker pair:
#   # >>> goalforge-<id> >>>
#   bash "<absolute payload>" || exit $?
#   # <<< goalforge-<id> <<<
#
# Two phases. Phase one validates every selected entry (known id, payload
# present, shared-path guard passed for its target); it creates the hooks
# directory if it is missing and writes no hook file. Phase two handles each
# selected entry in list order:
#   - target absent              → write a shebang and the block, chmod +x.
#   - target carries the block   → no-op ("already installed").
#   - pre-commit only: the target carries the legacy marker pair → rename the
#     two legacy marker lines to the goalforge-pre-commit pair, every other
#     byte and the mode unchanged; both pairs present → left untouched.
#   - otherwise                  → append an empty line and the block; never
#     overwrite.
#
# Exit codes: 0 done; 1 argument error, unknown id or absent payload; 2 refusal
# to write through a shared path.

set -euo pipefail

# The hook list: "<id>|<git_hook>|<payload>", one entry per line. <payload> is
# relative to the package root (the parent of this scripts/ directory); hooks/
# sits at the same relative path in BOTH install routes — packages/goalforge/
# (contributor symlink) and the generated flat plugins/goalforge/.
HOOKS=(
    "pre-commit|pre-commit|hooks/goalforge-pre-commit.sh"
)

# The marker pair of installs made before the hook list existed. Only the
# entry pre-commit reads it, and only to upgrade it.
LEGACY_OPEN_LINE="# >>> sdd-pre-commit >>>"
LEGACY_CLOSE_LINE="# <<< sdd-pre-commit <<<"

PKG_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
    echo "usage: goalforge-install-hooks.sh [<repo-dir>] [--only <id>]..." >&2
    exit 1
}

# ── Arguments ─────────────────────────────────────────────────────────────────
REPO_ARG=""
HAVE_REPO_ARG=0
ONLY=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "goalforge-install-hooks: ERROR — --only needs a hook id." >&2
                usage
            fi
            ONLY+=("$2")
            shift 2
            ;;
        -*)
            echo "goalforge-install-hooks: ERROR — unknown option: $1" >&2
            usage
            ;;
        *)
            if [[ "$HAVE_REPO_ARG" -eq 1 ]]; then
                echo "goalforge-install-hooks: ERROR — more than one <repo-dir>: $REPO_ARG, $1" >&2
                usage
            fi
            REPO_ARG="$1"
            HAVE_REPO_ARG=1
            shift
            ;;
    esac
done

entry_id()      { local e="$1"; printf '%s' "${e%%|*}"; }
entry_githook() { local e="${1#*|}"; printf '%s' "${e%%|*}"; }
entry_payload() { local e="$1"; printf '%s' "${e##*|}"; }

# ── Selection: every entry, or the --only ids in list order ──────────────────
VALID_IDS=""
for entry in "${HOOKS[@]}"; do
    VALID_IDS="${VALID_IDS:+$VALID_IDS }$(entry_id "$entry")"
done

UNKNOWN=""
for want in ${ONLY[@]+"${ONLY[@]}"}; do
    found=0
    for entry in "${HOOKS[@]}"; do
        [[ "$(entry_id "$entry")" == "$want" ]] && found=1
    done
    [[ "$found" -eq 1 ]] || UNKNOWN="${UNKNOWN:+$UNKNOWN }$want"
done
if [[ -n "$UNKNOWN" ]]; then
    echo "goalforge-install-hooks: ERROR — unknown hook id: $UNKNOWN (valid ids: $VALID_IDS)" >&2
    exit 1
fi

SELECTED=()
for entry in "${HOOKS[@]}"; do
    if [[ ${#ONLY[@]} -eq 0 ]]; then
        SELECTED+=("$entry")
        continue
    fi
    for want in "${ONLY[@]}"; do
        if [[ "$(entry_id "$entry")" == "$want" ]]; then
            SELECTED+=("$entry")
            break
        fi
    done
done

# ── Resolve target repo ────────────────────────────────────────────────────────
if [[ "$HAVE_REPO_ARG" -eq 1 ]]; then
    REPO_DIR="$REPO_ARG"
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

# ── Guard: never write through a path shared with anything outside this repo ──
# A hook that resolves outside the repo points at a SHARED file
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
    local target="$1" repo_dir="$2" reason="$3"
    echo "goalforge-install-hooks: ERROR — refusing to write $target: $reason" >&2
    echo '  Writing here would corrupt a shared file. Install a real hook first:' >&2
    echo "    bash \"\$HOME/.claude/scripts/install-guardrails.sh\" \"$repo_dir\"" >&2
    exit 2
}

# guard_target <target> <repo_dir> — returns only when writing <target> is safe.
guard_target() {
    local target="$1" repo_dir="$2"
    local target_real repo_real common_dir common_real link_count
    if [[ -L "$target" ]]; then
        refuse_shared "$target" "$repo_dir" "it is a symlink to $(readlink "$target")"
    fi

    # Resolve the hook's real location and require it to sit inside the working
    # tree or inside the git common dir (the latter covers linked worktrees, whose
    # hooks live in the MAIN repo's git dir).
    target_real="$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"
    repo_real="$(cd "$repo_dir" && pwd -P)"
    common_dir="$(git -C "$repo_dir" rev-parse --git-common-dir 2>/dev/null || echo "$repo_dir/.git")"
    [[ "$common_dir" == /* ]] || common_dir="$repo_dir/$common_dir"
    common_real="$(cd "$common_dir" 2>/dev/null && pwd -P || echo "$common_dir")"

    if [[ "$target_real" != "$repo_real"/* && "$target_real" != "$common_real"/* ]]; then
        refuse_shared "$target" "$repo_dir" "it resolves to $target_real, outside $repo_real"
    fi

    # A hardlink has no readable target, so link count is the only signal that the
    # same inode answers to another name.
    if [[ -f "$target" ]]; then
        link_count="$(stat -c %h "$target" 2>/dev/null || echo 1)"
        if [[ "$link_count" -gt 1 ]]; then
            refuse_shared "$target" "$repo_dir" "it is a hardlink (link count $link_count)"
        fi
    fi
}

# has_marker <file> <literal> — a line equals <literal> once its surrounding
# whitespace is stripped (the predicate goalforge-admission.py reads blocks by).
strip_ws() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    printf '%s' "${s%"${s##*[![:space:]]}"}"
}
has_marker() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$(strip_ws "$line")" == "$2" ]] && return 0
    done < "$1"
    return 1
}

# ── Phase one: validate every selected entry; write nothing ──────────────────
for entry in "${SELECTED[@]}"; do
    payload="$PKG_ROOT/$(entry_payload "$entry")"
    if [[ ! -f "$payload" ]]; then
        echo "goalforge-install-hooks: ERROR — payload not found for hook id $(entry_id "$entry"): $payload" >&2
        exit 1
    fi
done

mkdir -p "$HOOKS_DIR"
for entry in "${SELECTED[@]}"; do
    guard_target "$HOOKS_DIR/$(entry_githook "$entry")" "$REPO_DIR"
done

# ── Upgrade: rename the legacy marker lines, change nothing else ─────────────
# Written to a temp file beside the target that takes the target's mode, and
# moved over it only after the guard ran again. The exit trap removes the temp
# file on every failure path, a failed mv included.
UPGRADE_TMP=""
trap 'if [[ -n "$UPGRADE_TMP" ]]; then rm -f "$UPGRADE_TMP"; fi' EXIT

upgrade_legacy() { # <target> <open> <close>
    local target="$1" open="$2" close="$3" line nl stripped
    if ! has_marker "$target" "$LEGACY_CLOSE_LINE"; then
        echo "goalforge-install-hooks: WARNING — $target: the legacy block has no close marker; renaming its open marker as it is" >&2
    fi
    UPGRADE_TMP="$(mktemp "$(dirname "$target")/.$(basename "$target").XXXXXX")"
    while :; do
        nl=1
        if ! IFS= read -r line; then
            nl=0
            [[ -n "$line" ]] || break
        fi
        stripped="$(strip_ws "$line")"
        if [[ "$stripped" == "$LEGACY_OPEN_LINE" ]]; then
            line="$open"
        elif [[ "$stripped" == "$LEGACY_CLOSE_LINE" ]]; then
            line="$close"
        fi
        printf '%s' "$line"
        [[ "$nl" -eq 1 ]] || break
        printf '\n'
    done < "$target" > "$UPGRADE_TMP"
    chmod "$(stat -c %a "$target")" "$UPGRADE_TMP"
    guard_target "$target" "$REPO_DIR"
    mv -f "$UPGRADE_TMP" "$target"
    UPGRADE_TMP=""
    echo "goalforge-install-hooks: upgraded the legacy marker lines to the goalforge-pre-commit pair in $target"
}

# ── Phase two: install each selected entry in list order ─────────────────────
for entry in "${SELECTED[@]}"; do
    id="$(entry_id "$entry")"
    target="$HOOKS_DIR/$(entry_githook "$entry")"
    rel="$(entry_payload "$entry")"
    payload="$(cd "$PKG_ROOT/$(dirname "$rel")" && pwd)/$(basename "$rel")"
    open="# >>> goalforge-$id >>>"
    close="# <<< goalforge-$id <<<"
    body="bash \"$payload\" || exit \$?"

    if [[ ! -f "$target" ]]; then
        printf '#!/usr/bin/env bash\n%s\n%s\n%s\n' "$open" "$body" "$close" > "$target"
        chmod +x "$target"
        echo "goalforge-install-hooks: installed $id hook at $target"
        continue
    fi

    if [[ "$id" == pre-commit ]] && has_marker "$target" "$LEGACY_OPEN_LINE" \
       && has_marker "$target" "$open"; then
        echo "goalforge-install-hooks: both marker pairs present in $target — left unchanged; remove the legacy block by hand"
        continue
    fi

    if has_marker "$target" "$open"; then
        echo "goalforge-install-hooks: $id already installed (marker found) — no-op"
        continue
    fi

    if [[ "$id" == pre-commit ]] && has_marker "$target" "$LEGACY_OPEN_LINE"; then
        upgrade_legacy "$target" "$open" "$close"
        continue
    fi

    # The existing hook's exit semantics are preserved: if it exits non-zero,
    # that blocks the commit before our code runs. If it exits 0 (or falls
    # through), the appended block runs and can also block.
    printf '\n%s\n%s\n%s\n' "$open" "$body" "$close" >> "$target"
    echo "goalforge-install-hooks: appended the goalforge-$id block to existing hook at $target"
done
exit 0
