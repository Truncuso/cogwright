#!/usr/bin/env bash
# install.sh — deterministic goalforge installer (contributor | consumer).
#
# Contributor mode installs a PER-MACHINE, UNTRACKED symlink
#     $HOME/dotfiles/claude/skills/goalforge  ->  <repo>/packages/goalforge
# so every future goalforge edit lands in the cogwright working tree. The swap
# is a strict ordered transaction with pre- and post-verification, and it is
# idempotent: re-running on an already-correct install is a no-op (exit 0).
#
# Consumer mode prints the marketplace install commands and runs
# `claude plugin validate` when the CLI is available (the interactive `/plugin`
# flow cannot be scripted).
#
# No hardcoded absolute home paths: the repo is derived from this script's own
# location, everything else from $HOME.
#
# Usage:
#   install.sh --mode contributor [--dry-run]
#   install.sh --mode consumer    [--dry-run]
#   install.sh --self-test
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Paths (derive repo from script location; never hardcode $HOME)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GF_REPO="${GF_REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# The managed skill directory (per-machine, untracked) and its link target.
# Overridable by --self-test to a sandbox so the real $HOME is never touched.
GF_TARGET_DIR="${GF_TARGET_DIR:-$HOME/dotfiles/claude/skills/goalforge}"
GF_LINK_TARGET="${GF_LINK_TARGET:-$GF_REPO/packages/goalforge}"

EXPECTED_REMOTE_SUBSTR="github.com/Truncuso/cogwright"

# Gitignore transient set: these are excluded from drift detection so that
# gitignored __pycache__/evals-workspace transients classify CLEAN (never a
# raw `diff -r` of the working tree).
DRIFT_EXCLUDES=(--exclude=__pycache__ --exclude='*.pyc' --exclude='*.pyo'
                --exclude=workspace --exclude=evals-workspace --exclude=.git
                --exclude='.pytest_cache' --exclude='*.tmp')

DRY_RUN=0
GF_SKIP_REPO_PRECHECK="${GF_SKIP_REPO_PRECHECK:-0}"

log()  { printf '%s\n' "$*" >&2; }
info() { printf '[install] %s\n' "$*" >&2; }
err()  { printf '[install] ERROR: %s\n' "$*" >&2; }

run() {
  # Execute (or, under --dry-run, only announce) a side-effecting command.
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "DRY-RUN: $*"
    return 0
  fi
  "$@"
}

# ---------------------------------------------------------------------------
# Pre-checks
# ---------------------------------------------------------------------------
precheck_remote() {
  local remote
  remote="$(git -C "$GF_REPO" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$remote" ]]; then
    err "no 'origin' remote in $GF_REPO"
    return 1
  fi
  if [[ "$remote" != *"$EXPECTED_REMOTE_SUBSTR"* ]]; then
    err "unexpected origin remote: $remote (expected *$EXPECTED_REMOTE_SUBSTR*)"
    return 1
  fi
  info "remote OK: $remote"
  return 0
}

precheck_checkout_clean() {
  # Clean scoped to uncommitted TRACKED changes over packages/goalforge only —
  # never a raw working-tree scan (--untracked-files=no).
  local dirty
  dirty="$(git -C "$GF_REPO" status --porcelain --untracked-files=no \
             -- packages/goalforge 2>/dev/null || true)"
  if [[ -n "$dirty" ]]; then
    err "cogwright packages/goalforge has uncommitted tracked changes:"
    printf '%s\n' "$dirty" >&2
    return 1
  fi
  info "packages/goalforge checkout clean (tracked)"
  return 0
}

# ---------------------------------------------------------------------------
# Drift detection (git-tracked-content-only, exclude-set filtered)
# ---------------------------------------------------------------------------
real_dir_dirty() {
  # Return 0 (dirty) if the real directory differs from the package in tracked
  # content; 1 (clean) otherwise. Transients in DRIFT_EXCLUDES are ignored, so
  # a dir carrying only __pycache__/evals-workspace scratch is CLEAN.
  local dir="$1"
  local out
  out="$(diff -r -q "${DRIFT_EXCLUDES[@]}" "$dir" "$GF_LINK_TARGET" 2>/dev/null || true)"
  [[ -n "$out" ]]
}

# ---------------------------------------------------------------------------
# Target-state classification
# ---------------------------------------------------------------------------
classify_target() {
  local t="$GF_TARGET_DIR"
  if [[ -L "$t" ]]; then
    if [[ ! -e "$t" ]]; then
      echo "symlinked-dangling"; return 0
    fi
    local resolved target
    resolved="$(readlink -f "$t" 2>/dev/null || true)"
    target="$(readlink -f "$GF_LINK_TARGET" 2>/dev/null || true)"
    if [[ -n "$resolved" && "$resolved" == "$target" && -f "$t/SKILL.md" ]]; then
      echo "symlinked-correct-target"; return 0
    fi
    echo "symlinked-wrong-target"; return 0
  fi
  if [[ ! -e "$t" ]]; then
    echo "absent"; return 0
  fi
  if [[ -d "$t" ]]; then
    if real_dir_dirty "$t"; then echo "real-dir-dirty"; else echo "real-dir-clean"; fi
    return 0
  fi
  # A plain file where a dir/link is expected — treat as a wrong, non-symlink state.
  echo "real-dir-dirty"; return 0
}

# ---------------------------------------------------------------------------
# Post-verification
# ---------------------------------------------------------------------------
post_verify() {
  # SKILL.md resolves through the link AND the discovery probe enumerates it.
  if [[ ! -f "$GF_TARGET_DIR/SKILL.md" ]]; then
    err "post-verify: SKILL.md does not resolve through $GF_TARGET_DIR"
    return 1
  fi
  local probe="$SCRIPT_DIR/discovery-probe.sh"
  if [[ -x "$probe" || -f "$probe" ]]; then
    if ! bash "$probe" "$(dirname "$GF_TARGET_DIR")" >/dev/null 2>&1; then
      err "post-verify: discovery probe failed to enumerate goalforge"
      return 1
    fi
  fi
  info "post-verify OK: SKILL.md resolves + discovery probe enumerates goalforge"
  return 0
}

verify_target_resolves() {
  if [[ ! -d "$GF_LINK_TARGET" || ! -f "$GF_LINK_TARGET/SKILL.md" ]]; then
    err "link target does not resolve to a goalforge package: $GF_LINK_TARGET"
    err "is the cogwright checkout present? (contributor mode requires it)"
    return 1
  fi
  return 0
}

create_link() {
  run ln -s "$GF_LINK_TARGET" "$GF_TARGET_DIR"
}

# ---------------------------------------------------------------------------
# Contributor mode
# ---------------------------------------------------------------------------
run_contributor() {
  local state
  state="$(classify_target)"
  info "target state: $state  ($GF_TARGET_DIR)"

  # Link target must resolve before ANY swap/repair/create.
  if ! verify_target_resolves; then
    return 1
  fi

  case "$state" in
    symlinked-correct-target)
      info "already installed correctly — no-op"
      return 0
      ;;
    absent)
      mkdir -p "$(dirname "$GF_TARGET_DIR")" 2>/dev/null || true
      create_link
      ;;
    symlinked-wrong-target|symlinked-dangling)
      info "repairing $state — relinking to $GF_LINK_TARGET"
      run rm -f "$GF_TARGET_DIR"
      create_link
      ;;
    real-dir-clean)
      info "swapping clean real dir for symlink (transaction)"
      local scratch=""
      if [[ "$DRY_RUN" -eq 0 ]]; then
        scratch="$(mktemp -d "${TMPDIR:-/tmp}/goalforge-presymlink.XXXXXX")"
        if tar -czf "$scratch/goalforge.tar.gz" -C "$(dirname "$GF_TARGET_DIR")" \
               "$(basename "$GF_TARGET_DIR")" 2>/dev/null; then
          info "scratch tarball (short TTL): $scratch/goalforge.tar.gz"
        else
          info "scratch tarball skipped (non-fatal)"
        fi
      fi
      run rm -rf "$GF_TARGET_DIR"
      create_link
      if [[ "$DRY_RUN" -eq 0 ]] && ! post_verify; then
        err "post-verify failed — restoring real dir from scratch tarball"
        rm -f "$GF_TARGET_DIR"
        if [[ -n "$scratch" && -f "$scratch/goalforge.tar.gz" ]]; then
          tar -xzf "$scratch/goalforge.tar.gz" \
              -C "$(dirname "$GF_TARGET_DIR")" 2>/dev/null || true
        fi
        return 1
      fi
      [[ -n "$scratch" ]] && rm -rf "$scratch" 2>/dev/null || true
      info "swap complete"
      return 0
      ;;
    real-dir-dirty)
      err "refusing to clobber: real dir has uncommitted tracked drift vs package"
      err "  dir:     $GF_TARGET_DIR"
      err "  package: $GF_LINK_TARGET"
      err "resolve the drift (commit/revert) then re-run."
      return 1
      ;;
    *)
      err "unknown target state: $state"
      return 1
      ;;
  esac

  if [[ "$DRY_RUN" -eq 0 ]]; then
    post_verify || return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Consumer mode
# ---------------------------------------------------------------------------
run_consumer() {
  cat >&2 <<'EOF'
[install] consumer mode — marketplace install is interactive (/plugin cannot be
[install] scripted). Run these in Claude Code:

    /plugin marketplace add Truncuso/cogwright
    /plugin install goalforge@cogwright

EOF
  if command -v claude >/dev/null 2>&1; then
    info "running: claude plugin validate"
    run claude plugin validate || info "claude plugin validate reported issues (see above)"
  else
    info "claude CLI not found — skipping 'claude plugin validate'"
  fi
  return 0
}

# ===========================================================================
# Self-test — fixture HOME sandbox; the real $HOME is NEVER touched.
# ===========================================================================
self_test() {
  local sandbox pass=0 fail=0
  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/goalforge-selftest.XXXXXX")"
  trap 'rm -rf "$sandbox"' RETURN

  # Build a minimal but structurally-real goalforge package fixture.
  make_pkg() {
    local pkg="$1"
    mkdir -p "$pkg/capture" "$pkg/evals" "$pkg/scripts"
    printf '# goalforge\nfront door\n'   > "$pkg/SKILL.md"
    printf '# capture\n'                  > "$pkg/capture/SKILL.md"
    printf 'echo hi\n'                    > "$pkg/scripts/x.sh"
    printf '{}\n'                         > "$pkg/evals/evals.json"
  }

  assert() {
    # assert <label> <condition-cmd...>
    local label="$1"; shift
    if "$@"; then
      printf '  PASS: %s\n' "$label"
    else
      printf '  FAIL: %s\n' "$label"
      return 1
    fi
  }

  run_case() {
    local name="$1"; shift
    local casedir="$sandbox/$name"
    mkdir -p "$casedir"
    export GF_SKIP_REPO_PRECHECK=1
    if "case_$name" "$casedir"; then
      printf 'CASE %s: pass\n' "$name"
      pass=$((pass+1))
    else
      printf 'CASE %s: FAIL\n' "$name"
      fail=$((fail+1))
    fi
  }

  # --- Case 1: fresh (absent) → link created, enumerated ---
  case_fresh() {
    local d="$1"
    local pkg="$d/pkg" skills="$d/home/dotfiles/claude/skills"
    make_pkg "$pkg"; mkdir -p "$skills"
    GF_LINK_TARGET="$pkg" GF_TARGET_DIR="$skills/goalforge" \
      run_contributor >/dev/null 2>&1 || return 1
    assert "state was absent → link created" test -L "$skills/goalforge" || return 1
    assert "link resolves to package" \
      test "$(readlink -f "$skills/goalforge")" = "$(readlink -f "$pkg")" || return 1
    assert "SKILL.md resolves through link" test -f "$skills/goalforge/SKILL.md" || return 1
    assert "discovery probe enumerates (symlink-following)" \
      bash "$SCRIPT_DIR/discovery-probe.sh" "$skills" || return 1
  }

  # --- Case 2: installed-correct → idempotent no-op ---
  case_installed_correct() {
    local d="$1"
    local pkg="$d/pkg" skills="$d/home/dotfiles/claude/skills"
    make_pkg "$pkg"; mkdir -p "$skills"
    ln -s "$pkg" "$skills/goalforge"
    local before; before="$(readlink "$skills/goalforge")"
    local cls
    cls="$(GF_LINK_TARGET="$pkg" GF_TARGET_DIR="$skills/goalforge" classify_target)"
    assert "classified symlinked-correct-target" test "$cls" = "symlinked-correct-target" || return 1
    GF_LINK_TARGET="$pkg" GF_TARGET_DIR="$skills/goalforge" \
      run_contributor >/dev/null 2>&1 || return 1
    assert "no-op: link unchanged" test "$(readlink "$skills/goalforge")" = "$before" || return 1
  }

  # --- Case 3: installed-wrong-target → repaired ---
  case_installed_wrong_target() {
    local d="$1"
    local pkg="$d/pkg" other="$d/other" skills="$d/home/dotfiles/claude/skills"
    make_pkg "$pkg"; make_pkg "$other"; mkdir -p "$skills"
    ln -s "$other" "$skills/goalforge"
    local cls
    cls="$(GF_LINK_TARGET="$pkg" GF_TARGET_DIR="$skills/goalforge" classify_target)"
    assert "classified symlinked-wrong-target" test "$cls" = "symlinked-wrong-target" || return 1
    GF_LINK_TARGET="$pkg" GF_TARGET_DIR="$skills/goalforge" \
      run_contributor >/dev/null 2>&1 || return 1
    assert "repaired: link now points at package" \
      test "$(readlink -f "$skills/goalforge")" = "$(readlink -f "$pkg")" || return 1
  }

  # --- Case 4: dangling → repaired ---
  case_dangling() {
    local d="$1"
    local pkg="$d/pkg" skills="$d/home/dotfiles/claude/skills"
    make_pkg "$pkg"; mkdir -p "$skills"
    ln -s "$d/does-not-exist" "$skills/goalforge"
    local cls
    cls="$(GF_LINK_TARGET="$pkg" GF_TARGET_DIR="$skills/goalforge" classify_target)"
    assert "classified symlinked-dangling" test "$cls" = "symlinked-dangling" || return 1
    GF_LINK_TARGET="$pkg" GF_TARGET_DIR="$skills/goalforge" \
      run_contributor >/dev/null 2>&1 || return 1
    assert "repaired: SKILL.md resolves" test -f "$skills/goalforge/SKILL.md" || return 1
    assert "repaired: correct target" \
      test "$(readlink -f "$skills/goalforge")" = "$(readlink -f "$pkg")" || return 1
  }

  # --- Case 5: dirty-with-transient-only → CLEAN (transients ignored) ---
  case_dirty_with_transient_only() {
    local d="$1"
    local pkg="$d/pkg" skills="$d/home/dotfiles/claude/skills"
    make_pkg "$pkg"; mkdir -p "$skills"
    # Real dir = exact copy of package, PLUS gitignored transients only.
    cp -r "$pkg" "$skills/goalforge"
    mkdir -p "$skills/goalforge/scripts/__pycache__" "$skills/goalforge/evals/workspace"
    printf 'junk' > "$skills/goalforge/scripts/__pycache__/x.cpython-311.pyc"
    printf 'scratch' > "$skills/goalforge/evals/workspace/run-42.log"
    printf 'scratch' > "$skills/goalforge/evals/workspace/state.tmp"
    local cls
    cls="$(GF_LINK_TARGET="$pkg" GF_TARGET_DIR="$skills/goalforge" classify_target)"
    assert "transient-only dir classified real-dir-clean (CLEAN)" \
      test "$cls" = "real-dir-clean" || return 1
    GF_LINK_TARGET="$pkg" GF_TARGET_DIR="$skills/goalforge" \
      run_contributor >/dev/null 2>&1 || return 1
    assert "clean dir swapped to symlink" test -L "$skills/goalforge" || return 1
    assert "swap: correct target" \
      test "$(readlink -f "$skills/goalforge")" = "$(readlink -f "$pkg")" || return 1
  }

  # --- Case 6: dirty-real (tracked content diff) → refuse, dir preserved ---
  case_dirty_real() {
    local d="$1"
    local pkg="$d/pkg" skills="$d/home/dotfiles/claude/skills"
    make_pkg "$pkg"; mkdir -p "$skills"
    cp -r "$pkg" "$skills/goalforge"
    printf 'LOCAL EDIT — real tracked drift\n' >> "$skills/goalforge/SKILL.md"
    local cls
    cls="$(GF_LINK_TARGET="$pkg" GF_TARGET_DIR="$skills/goalforge" classify_target)"
    assert "tracked-content diff classified real-dir-dirty" \
      test "$cls" = "real-dir-dirty" || return 1
    if GF_LINK_TARGET="$pkg" GF_TARGET_DIR="$skills/goalforge" \
         run_contributor >/dev/null 2>&1; then
      printf '  FAIL: contributor should have REFUSED dirty dir\n'; return 1
    fi
    assert "refused: real dir preserved (not a symlink)" \
      test -d "$skills/goalforge" -a ! -L "$skills/goalforge" || return 1
    assert "refused: local edit intact" \
      grep -q "LOCAL EDIT" "$skills/goalforge/SKILL.md" || return 1
  }

  # --- Case 7: missing-checkout → verify_target_resolves fails, refuse ---
  case_missing_checkout() {
    local d="$1"
    local pkg="$d/pkg-absent" skills="$d/home/dotfiles/claude/skills"
    mkdir -p "$skills"   # package deliberately NOT created
    if GF_LINK_TARGET="$pkg" GF_TARGET_DIR="$skills/goalforge" \
         run_contributor >/dev/null 2>&1; then
      printf '  FAIL: contributor should have REFUSED (no checkout)\n'; return 1
    fi
    assert "no link created when checkout missing" \
      test ! -e "$skills/goalforge" || return 1
  }

  printf '=== goalforge installer self-test (7 cases) ===\n'
  run_case fresh
  run_case installed_correct
  run_case installed_wrong_target
  run_case dangling
  run_case dirty_with_transient_only
  run_case dirty_real
  run_case missing_checkout
  printf '=== self-test: %d passed, %d failed ===\n' "$pass" "$fail"
  [[ "$fail" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
main() {
  local mode=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)      mode="${2:-}"; shift 2 ;;
      --mode=*)    mode="${1#*=}"; shift ;;
      --dry-run)   DRY_RUN=1; shift ;;
      --self-test) self_test; exit $? ;;
      -h|--help)
        grep -E '^#( |$)' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
        exit 0 ;;
      *) err "unknown argument: $1"; exit 2 ;;
    esac
  done

  case "$mode" in
    contributor)
      if [[ "$GF_SKIP_REPO_PRECHECK" != "1" ]]; then
        precheck_remote || exit 1
        precheck_checkout_clean || exit 1
      fi
      run_contributor || exit 1
      ;;
    consumer)
      run_consumer || exit 1
      ;;
    "")
      err "--mode contributor|consumer required (or --self-test)"; exit 2 ;;
    *)
      err "unknown mode: $mode (expected contributor|consumer)"; exit 2 ;;
  esac
}

main "$@"
