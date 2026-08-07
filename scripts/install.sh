#!/usr/bin/env bash
# install.sh — deterministic goalforge installer (contributor | consumer).
#
# Contributor mode installs a PER-MACHINE, UNTRACKED symlink
#     <skills>/goalforge  ->  <repo>/packages/goalforge
# where <skills> is ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills — the standard
# Claude Code skills home — so every future goalforge edit lands in the
# cogwright working tree. Override the whole path with GF_TARGET_DIR. The swap
# is a strict ordered transaction with pre- and post-verification, and it is
# idempotent: re-running on an already-correct install is a no-op (exit 0).
#
# Alongside goalforge, the same per-link state machine materializes the sibling
# package skills as top-level symlinks:
#     <skills>/prototype  ->  <repo>/packages/goalforge/prototype
#     <skills>/wayfind    ->  <repo>/packages/goalforge/wayfind
# interview/ stays PRIVATE — it is deliberately NOT linked at the top level.
#
# An install left behind by an older dotfiles-rooted layout is DETECTED and
# reported on stderr, never migrated: sibling prototype/wayfind links there are
# yours to remove by hand.
#
# The origin remote is checked against GF_EXPECTED_REMOTE (default: the
# upstream slug). A mismatch — a fork — is a WARNING, not a failure.
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
GF_TARGET_DIR="${GF_TARGET_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/goalforge}"
GF_LINK_TARGET="${GF_LINK_TARGET:-$GF_REPO/packages/goalforge}"

# Legacy (pre-rewrite) skills root. Kept ONLY so an install left there can be
# reported; nothing is ever moved, removed, or relinked out of it.
GF_LEGACY_SKILLS_DIR="${GF_LEGACY_SKILLS_DIR:-$HOME/dotfiles/claude/skills}"

# Expected origin remote; a mismatch (fork) warns and continues.
GF_EXPECTED_REMOTE="${GF_EXPECTED_REMOTE:-github.com/Truncuso/cogwright}"

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
    info "WARNING: no 'origin' remote in $GF_REPO — cannot verify the upstream"
    info "WARNING: continuing anyway — set GF_SKIP_REPO_PRECHECK=1 to skip this check"
    return 0
  fi
  if [[ "$remote" != *"$GF_EXPECTED_REMOTE"* ]]; then
    info "WARNING: unexpected origin remote: $remote (expected *$GF_EXPECTED_REMOTE*)"
    info "WARNING: continuing anyway — set GF_EXPECTED_REMOTE to silence this on a fork"
    return 0
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
  local link_target="${2:-$GF_LINK_TARGET}"
  local out
  out="$(diff -r -q "${DRIFT_EXCLUDES[@]}" "$dir" "$link_target" 2>/dev/null || true)"
  [[ -n "$out" ]]
}

# ---------------------------------------------------------------------------
# Target-state classification
# ---------------------------------------------------------------------------
classify_target() {
  local t="${1:-$GF_TARGET_DIR}"
  local lt="${2:-$GF_LINK_TARGET}"
  if [[ -L "$t" ]]; then
    if [[ ! -e "$t" ]]; then
      echo "symlinked-dangling"; return 0
    fi
    local resolved target
    resolved="$(readlink -f "$t" 2>/dev/null || true)"
    target="$(readlink -f "$lt" 2>/dev/null || true)"
    if [[ -n "$resolved" && "$resolved" == "$target" && -f "$t/SKILL.md" ]]; then
      echo "symlinked-correct-target"; return 0
    fi
    echo "symlinked-wrong-target"; return 0
  fi
  if [[ ! -e "$t" ]]; then
    echo "absent"; return 0
  fi
  if [[ -d "$t" ]]; then
    if real_dir_dirty "$t" "$lt"; then echo "real-dir-dirty"; else echo "real-dir-clean"; fi
    return 0
  fi
  # A plain file where a dir/link is expected — treat as a wrong, non-symlink state.
  echo "real-dir-dirty"; return 0
}

# ---------------------------------------------------------------------------
# Post-verification
# ---------------------------------------------------------------------------
post_verify() {
  # SKILL.md resolves through the link AND (for goalforge, run_probe=1) the
  # discovery probe enumerates it. Sibling links (run_probe=0) only assert
  # SKILL.md resolution — the probe is goalforge-specific.
  local target_dir="${1:-$GF_TARGET_DIR}"
  local run_probe="${2:-1}"
  if [[ ! -f "$target_dir/SKILL.md" ]]; then
    err "post-verify: SKILL.md does not resolve through $target_dir"
    return 1
  fi
  if [[ "$run_probe" -eq 1 ]]; then
    local probe="$SCRIPT_DIR/discovery-probe.sh"
    if [[ -x "$probe" || -f "$probe" ]]; then
      if ! bash "$probe" "$(dirname "$target_dir")" >/dev/null 2>&1; then
        err "post-verify: discovery probe failed to enumerate goalforge"
        return 1
      fi
    fi
    info "post-verify OK: SKILL.md resolves + discovery probe enumerates goalforge"
  else
    info "post-verify OK: SKILL.md resolves through $target_dir"
  fi
  return 0
}

verify_target_resolves() {
  local link_target="${1:-$GF_LINK_TARGET}"
  local label="${2:-goalforge}"
  if [[ ! -d "$link_target" || ! -f "$link_target/SKILL.md" ]]; then
    err "link target does not resolve to a $label package: $link_target"
    err "is the cogwright checkout present? (contributor mode requires it)"
    return 1
  fi
  return 0
}

create_link() {
  local target_dir="${1:-$GF_TARGET_DIR}"
  local link_target="${2:-$GF_LINK_TARGET}"
  run ln -s "$link_target" "$target_dir"
}

# ---------------------------------------------------------------------------
# Real-dir → symlink swap (strict ordered transaction with tar backup)
# ---------------------------------------------------------------------------
swap_real_dir() {
  # swap_real_dir <label> <target_dir> <link_target> <run_probe> <retain_on_success>
  # Backs up the real dir to a scratch tarball, replaces it with the symlink,
  # and restores from the tarball if post-verify fails. retain_on_success=1
  # (dirty real dirs) keeps the tarball on success — it is the only remaining
  # copy of pre-swap content that differed from the tracked package.
  # retain_on_success=0 (clean real dirs) removes it on success: a pure
  # rollback aid, redundant with the package once the swap has verified.
  local label="$1" target_dir="$2" link_target="$3" run_probe="$4"
  local retain_on_success="${5:-0}"
  info "$label: swapping real dir for symlink (transaction)"
  local scratch=""
  if [[ "$DRY_RUN" -eq 0 ]]; then
    scratch="$(mktemp -d "${TMPDIR:-/tmp}/goalforge-presymlink.XXXXXX")"
    if tar -czf "$scratch/backup.tar.gz" -C "$(dirname "$target_dir")" \
           "$(basename "$target_dir")" 2>/dev/null; then
      if [[ "$retain_on_success" -eq 1 ]]; then
        info "scratch tarball (dirty-dir backup, retained on success): $scratch/backup.tar.gz"
      else
        info "scratch tarball (transient rollback tarball, removed on success): $scratch/backup.tar.gz"
      fi
    else
      info "scratch tarball skipped (non-fatal)"
    fi
  fi
  run rm -rf "$target_dir"
  create_link "$target_dir" "$link_target"
  if [[ "$DRY_RUN" -eq 0 ]] && ! post_verify "$target_dir" "$run_probe"; then
    err "post-verify failed — restoring real dir from scratch tarball"
    rm -f "$target_dir"
    if [[ -n "$scratch" && -f "$scratch/backup.tar.gz" ]]; then
      tar -xzf "$scratch/backup.tar.gz" \
          -C "$(dirname "$target_dir")" 2>/dev/null || true
    fi
    return 1
  fi
  if [[ -n "$scratch" ]]; then
    if [[ "$retain_on_success" -eq 1 && -f "$scratch/backup.tar.gz" ]]; then
      info "dirty-dir backup retained: $scratch/backup.tar.gz"
    else
      rm -rf "$scratch" 2>/dev/null || true
    fi
  fi
  info "$label: swap complete"
  return 0
}

# ---------------------------------------------------------------------------
# Per-link state machine — installs ONE symlink through the full
# classify → verify → (no-op | repair | swap) → post-verify cycle.
#
#   install_link <label> <target_dir> <link_target> <run_probe> <allow_dirty_swap>
#
# allow_dirty_swap=0 (goalforge): a real dir with tracked drift is REFUSED to
# protect uncommitted edits to the tracked package.
# allow_dirty_swap=1 (siblings):  a real dir — including a legacy standalone
# skill whose content differs wholesale — is swapped (with tar backup), since
# drift vs the new package child is expected and a refuse-gate would block the
# migration permanently.
# ---------------------------------------------------------------------------
install_link() {
  local label="$1" target_dir="$2" link_target="$3" run_probe="$4" allow_dirty_swap="$5"
  local state
  state="$(classify_target "$target_dir" "$link_target")"
  info "$label target state: $state  ($target_dir)"

  # Link target must resolve before ANY swap/repair/create.
  if ! verify_target_resolves "$link_target" "$label"; then
    return 1
  fi

  case "$state" in
    symlinked-correct-target)
      info "$label already installed correctly — no-op"
      return 0
      ;;
    absent)
      run mkdir -p "$(dirname "$target_dir")" 2>/dev/null || true
      create_link "$target_dir" "$link_target"
      ;;
    symlinked-wrong-target|symlinked-dangling)
      info "repairing $state — relinking $label to $link_target"
      run rm -f "$target_dir"
      create_link "$target_dir" "$link_target"
      ;;
    real-dir-clean)
      swap_real_dir "$label" "$target_dir" "$link_target" "$run_probe" 0 || return 1
      return 0
      ;;
    real-dir-dirty)
      if [[ "$allow_dirty_swap" -eq 1 ]]; then
        info "$label: legacy real dir with drift — swapping (tarball retained on success)"
        swap_real_dir "$label" "$target_dir" "$link_target" "$run_probe" 1 || return 1
        return 0
      fi
      err "refusing to clobber: real dir has uncommitted tracked drift vs package"
      err "  dir:     $target_dir"
      err "  package: $link_target"
      err "resolve the drift (commit/revert) then re-run."
      return 1
      ;;
    *)
      err "unknown target state: $state"
      return 1
      ;;
  esac

  if [[ "$DRY_RUN" -eq 0 ]]; then
    post_verify "$target_dir" "$run_probe" || return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Contributor mode — goalforge + sibling package skills
# ---------------------------------------------------------------------------
report_legacy_target() {
  # Detect-and-report only: an install under the legacy skills root is left
  # exactly as it is. No silent migration — the prototype/wayfind siblings
  # there are derived from that root, so moving them is a human decision.
  local legacy="$GF_LEGACY_SKILLS_DIR/goalforge"
  [[ "$legacy" == "$GF_TARGET_DIR" ]] && return 0
  [[ -e "$legacy" || -L "$legacy" ]] || return 0
  info "NOTE: a legacy goalforge install still exists at $legacy"
  info "NOTE: it is NOT migrated — remove it and its prototype/wayfind siblings by hand"
  return 0
}

run_contributor() {
  local skills_dir
  skills_dir="$(dirname "$GF_TARGET_DIR")"

  report_legacy_target

  # goalforge — fatal-first (preserves the original single-link semantics:
  # a broken goalforge install aborts before any sibling work).
  install_link goalforge "$GF_TARGET_DIR" "$GF_LINK_TARGET" 1 0 || return 1

  # Sibling package skills, linked alongside goalforge. interview/ stays
  # PRIVATE — no top-level link. Legacy standalone real dirs are swapped (with
  # tar backup) into symlinks, hence allow_dirty_swap=1. Best-effort: attempt
  # both so one broken sibling does not suppress the other; aggregate status.
  local rc=0
  install_link prototype "$skills_dir/prototype" "$GF_LINK_TARGET/prototype" 0 1 || rc=1
  install_link wayfind   "$skills_dir/wayfind"   "$GF_LINK_TARGET/wayfind"   0 1 || rc=1
  return "$rc"
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

  # Build a minimal but structurally-real goalforge package fixture, including
  # the prototype/wayfind sibling children the installer links top-level.
  make_pkg() {
    local pkg="$1"
    mkdir -p "$pkg/capture" "$pkg/evals" "$pkg/scripts" \
             "$pkg/prototype" "$pkg/wayfind"
    printf '# goalforge\nfront door\n'   > "$pkg/SKILL.md"
    printf '# capture\n'                  > "$pkg/capture/SKILL.md"
    printf '# prototype\n'                > "$pkg/prototype/SKILL.md"
    printf '# wayfind\n'                  > "$pkg/wayfind/SKILL.md"
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
    # Hermetic: report_legacy_target must stat the sandbox, never the real $HOME.
    # (Re-exec cases run under `env -i` and pass this explicitly themselves.)
    export GF_LEGACY_SKILLS_DIR="$casedir/home/dotfiles/claude/skills"
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
    assert "sibling prototype linked into package" \
      test "$(readlink -f "$skills/prototype")" = "$(readlink -f "$pkg/prototype")" || return 1
    assert "sibling wayfind linked into package" \
      test "$(readlink -f "$skills/wayfind")" = "$(readlink -f "$pkg/wayfind")" || return 1
    assert "interview stays private (no top-level link)" \
      test ! -e "$skills/interview" || return 1
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

  # --- Case 8: sibling legacy real dir (foreign content) → swapped w/ backup ---
  case_sibling_legacy_dir() {
    local d="$1"
    local pkg="$d/pkg" skills="$d/home/dotfiles/claude/skills"
    make_pkg "$pkg"; mkdir -p "$skills"
    # A legacy standalone wayfind dir whose content differs wholesale.
    mkdir -p "$skills/wayfind"
    printf '# old standalone wayfind\n' > "$skills/wayfind/SKILL.md"
    printf 'legacy\n'                   > "$skills/wayfind/legacy.txt"
    local cls
    cls="$(GF_LINK_TARGET="$pkg/wayfind" GF_TARGET_DIR="$skills/wayfind" classify_target)"
    assert "legacy sibling dir classified real-dir-dirty" \
      test "$cls" = "real-dir-dirty" || return 1
    local out
    out="$(GF_LINK_TARGET="$pkg" GF_TARGET_DIR="$skills/goalforge" \
      run_contributor 2>&1)" || return 1
    assert "legacy wayfind swapped to symlink" test -L "$skills/wayfind" || return 1
    assert "swap: wayfind resolves into package child" \
      test "$(readlink -f "$skills/wayfind")" = "$(readlink -f "$pkg/wayfind")" || return 1
    assert "swap emitted a scratch tarball backup" \
      grep -q "scratch tarball" <<<"$out" || return 1
    local retained_line retained_path tar_listing
    retained_line="$(grep -o "dirty-dir backup retained: .*" <<<"$out" || true)"
    retained_path="${retained_line#dirty-dir backup retained: }"
    assert "dirty-dir backup tarball retained on success" \
      test -n "$retained_path" -a -f "$retained_path" || return 1
    tar_listing="$(tar -tzf "$retained_path" 2>/dev/null || true)"
    assert "retained tarball contains the legacy content (recoverable)" \
      grep -q "wayfind/legacy.txt" <<<"$tar_listing" || return 1
    rm -rf "$(dirname "$retained_path")" 2>/dev/null || true
  }

  # --- Case 9: default GF_TARGET_DIR (re-exec: the default binds at SOURCE
  # --- time, so it can only be exercised by a fresh process under a sandbox
  # --- HOME — the real $HOME is never read or written by this case) ---
  case_default_target_dir() {
    local d="$1"
    local pkg="$d/pkg" home="$d/home"
    local legacy_root="$home/dotfiles/claude/skills"
    make_pkg "$pkg"; mkdir -p "$home"
    # Pre-existing legacy install under the SANDBOX legacy root: this is what
    # report_legacy_target must detect, report, and leave strictly alone.
    mkdir -p "$legacy_root/goalforge"
    printf 'legacy marker\n' > "$legacy_root/goalforge/SKILL.md"
    local out
    out="$(env -i HOME="$home" PATH="$PATH" CLAUDE_CONFIG_DIR= \
        GF_SKIP_REPO_PRECHECK=1 GF_LINK_TARGET="$pkg" \
        GF_LEGACY_SKILLS_DIR="$legacy_root" \
        bash "$SCRIPT_DIR/install.sh" --mode contributor 2>&1)" || return 1
    assert "default target lands under the sandbox skills home" \
      test -L "$home/.claude/skills/goalforge" || return 1
    assert "default target resolves to the package" \
      test "$(readlink -f "$home/.claude/skills/goalforge")" = "$(readlink -f "$pkg")" || return 1
    assert "legacy install reported on stderr" \
      grep -q "NOTE: a legacy goalforge install still exists at $legacy_root/goalforge" \
        <<<"$out" || return 1
    assert "legacy install NOT migrated (still a real dir, not a link)" \
      test -d "$legacy_root/goalforge" -a ! -L "$legacy_root/goalforge" || return 1
    assert "legacy install untouched (marker intact)" \
      grep -q "legacy marker" "$legacy_root/goalforge/SKILL.md" || return 1
  }

  # --- Case 10: fork origin remote → precheck WARNS and the install proceeds
  # --- (GF_SKIP_REPO_PRECHECK deliberately unset via env -i) ---
  case_fork_remote_warns() {
    local d="$1"
    local pkg="$d/pkg" home="$d/home" repo="$d/repo"
    make_pkg "$pkg"; mkdir -p "$home" "$repo"
    git -C "$repo" init -q >/dev/null 2>&1 || return 1
    git -C "$repo" remote add origin https://example.invalid/fork.git >/dev/null 2>&1 || return 1
    local out
    out="$(env -i HOME="$home" PATH="$PATH" CLAUDE_CONFIG_DIR= \
             GF_REPO="$repo" GF_LINK_TARGET="$pkg" \
             GF_LEGACY_SKILLS_DIR="$home/dotfiles/claude/skills" \
             bash "$SCRIPT_DIR/install.sh" --mode contributor 2>&1)" || return 1
    assert "fork remote reported as a warning" \
      grep -q "WARNING: unexpected origin remote" <<<"$out" || return 1
    assert "install proceeded past the fork remote" \
      test -L "$home/.claude/skills/goalforge" || return 1
  }

  printf '=== goalforge installer self-test (10 cases) ===\n'
  run_case fresh
  run_case installed_correct
  run_case installed_wrong_target
  run_case dangling
  run_case dirty_with_transient_only
  run_case dirty_real
  run_case missing_checkout
  run_case sibling_legacy_dir
  run_case default_target_dir
  run_case fork_remote_warns
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
