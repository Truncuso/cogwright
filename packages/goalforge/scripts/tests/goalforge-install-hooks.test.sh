#!/usr/bin/env bash
# goalforge-install-hooks.test.sh
# EXTERNAL harness for goalforge-install-hooks.sh.
# Hermetic: every case runs in its own throwaway git repo under a trap-cleaned
# tmpdir; the shared template fixture is a file inside that tmpdir, never the
# real ~/.claude/hooks/templates/git/pre-commit.
#
# Cases:
#   a: no pre-commit hook          -> installs wrapper (exit 0), marker present
#   b: hook already carries marker -> no-op (exit 0), byte-identical
#   c: real hook, no marker        -> chain-safe append (exit 0), original kept
#   d: pre-commit is a SYMLINK to a shared template -> BLOCK (exit 2),
#      shared template byte-identical (the 2026-09-04 corruption regression)
#   e: pre-commit is a DANGLING symlink             -> BLOCK (exit 2),
#      link target still not created (`-f` is false here, so the guard must
#      run before the "no existing hook" case)
#   f: the hooks DIRECTORY is a symlink to a shared dir -> BLOCK (exit 2);
#      the hook file itself is regular, so a per-file -L check misses this
#   g: core.hooksPath points OUTSIDE the repo            -> BLOCK (exit 2)
#   h: core.hooksPath points INSIDE the repo (.githooks) -> ALLOW (exit 0);
#      guards the false positive that case g's containment check could cause
#   i: pre-commit is a HARDLINK to a shared file         -> BLOCK (exit 2),
#      shared file unchanged (no symlink to detect — link count is the signal)
set -uo pipefail

INSTALLER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/goalforge-install-hooks.sh"
MARKER='# >>> sdd-pre-commit >>>'
PASS=0
FAIL=0
ok(){ echo "PASS: $1"; PASS=$((PASS+1)); }
no(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Stand-ins for ~/.claude/hooks/templates/git/ — the shared surface that must
# never be written through. PRISTINE is the untouched comparison copy.
SHARED_DIR="$WORK/shared-templates"
mkdir -p "$SHARED_DIR"
SHARED="$SHARED_DIR/pre-commit"
printf '#!/usr/bin/env bash\n# shared guardrail template\nexit 0\n' > "$SHARED"
PRISTINE="$WORK/pristine-pre-commit"
cp "$SHARED" "$PRISTINE"

new_repo() { # new_repo <name> -> echoes repo path
  local d="$WORK/$1"
  mkdir -p "$d"
  git -C "$d" init -q
  echo "$d"
}

# ── a: no existing hook ──────────────────────────────────────────────────────
repo="$(new_repo a)"
if bash "$INSTALLER" "$repo" >/dev/null 2>&1 \
   && grep -qF "$MARKER" "$repo/.git/hooks/pre-commit" \
   && [ -x "$repo/.git/hooks/pre-commit" ]; then
  ok "a: fresh install writes an executable marked hook"
else
  no "a: fresh install writes an executable marked hook"
fi

# ── b: already installed -> idempotent no-op ─────────────────────────────────
# Asserted positively first: an installer that silently wrote nothing would
# otherwise satisfy "unchanged" trivially.
repo="$(new_repo b)"
bash "$INSTALLER" "$repo" >/dev/null 2>&1
hook="$repo/.git/hooks/pre-commit"
if [ -s "$hook" ] && grep -qF "$MARKER" "$hook"; then
  cp "$hook" "$WORK/b-after-first"
  bash "$INSTALLER" "$repo" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ] && cmp -s "$hook" "$WORK/b-after-first"; then
    ok "b: second run is a byte-identical no-op"
  else
    no "b: second run is a byte-identical no-op (rc=$rc)"
  fi
else
  no "b: first run did not produce a marked non-empty hook to compare against"
fi

# ── c: real hook without the marker -> chain-safe append ─────────────────────
repo="$(new_repo c)"
printf '#!/usr/bin/env bash\necho pre-existing\n' > "$repo/.git/hooks/pre-commit"
chmod +x "$repo/.git/hooks/pre-commit"
if bash "$INSTALLER" "$repo" >/dev/null 2>&1 \
   && grep -qF 'echo pre-existing' "$repo/.git/hooks/pre-commit" \
   && grep -qF "$MARKER" "$repo/.git/hooks/pre-commit"; then
  ok "c: appends to an existing hook without dropping it"
else
  no "c: appends to an existing hook without dropping it"
fi

# ── d: symlinked hook -> refuse, shared template untouched ───────────────────
repo="$(new_repo d)"
ln -s "$SHARED" "$repo/.git/hooks/pre-commit"
out="$(bash "$INSTALLER" "$repo" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && cmp -s "$SHARED" "$PRISTINE"; then
  ok "d: refuses a symlinked hook (exit 2), shared template unchanged"
else
  no "d: refuses a symlinked hook (rc=$rc, out=${out//$'\n'/ | })"
fi

# ── e: dangling symlink -> refuse, target not created ────────────────────────
repo="$(new_repo e)"
ln -s "$WORK/does-not-exist" "$repo/.git/hooks/pre-commit"
out="$(bash "$INSTALLER" "$repo" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && [ ! -e "$WORK/does-not-exist" ]; then
  ok "e: refuses a dangling symlink (exit 2) instead of creating its target"
else
  no "e: refuses a dangling symlink (rc=$rc, out=${out//$'\n'/ | })"
fi

# ── f: symlinked hooks DIRECTORY, regular hook file inside it ────────────────
repo="$(new_repo f)"
rm -rf "$repo/.git/hooks"
ln -s "$SHARED_DIR" "$repo/.git/hooks"
out="$(bash "$INSTALLER" "$repo" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && cmp -s "$SHARED" "$PRISTINE"; then
  ok "f: refuses a symlinked hooks directory (exit 2), shared template unchanged"
else
  no "f: refuses a symlinked hooks directory (rc=$rc, out=${out//$'\n'/ | })"
fi

# ── g: core.hooksPath pointing outside the repo ──────────────────────────────
repo="$(new_repo g)"
git -C "$repo" config core.hooksPath "$SHARED_DIR"
out="$(bash "$INSTALLER" "$repo" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && cmp -s "$SHARED" "$PRISTINE"; then
  ok "g: refuses an out-of-repo core.hooksPath (exit 2), shared template unchanged"
else
  no "g: refuses an out-of-repo core.hooksPath (rc=$rc, out=${out//$'\n'/ | })"
fi

# ── h: repo-local core.hooksPath is still allowed (false-positive guard) ─────
repo="$(new_repo h)"
git -C "$repo" config core.hooksPath .githooks
out="$(bash "$INSTALLER" "$repo" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qF "$MARKER" "$repo/.githooks/pre-commit"; then
  ok "h: allows a repo-local core.hooksPath (.githooks)"
else
  no "h: allows a repo-local core.hooksPath (rc=$rc, out=${out//$'\n'/ | })"
fi

# ── i: hardlinked hook -> refuse, shared file untouched ──────────────────────
repo="$(new_repo i)"
if ln "$SHARED" "$repo/.git/hooks/pre-commit" 2>/dev/null; then
  out="$(bash "$INSTALLER" "$repo" 2>&1)"; rc=$?
  if [ "$rc" -eq 2 ] && cmp -s "$SHARED" "$PRISTINE"; then
    ok "i: refuses a hardlinked hook (exit 2), shared file unchanged"
  else
    no "i: refuses a hardlinked hook (rc=$rc, out=${out//$'\n'/ | })"
  fi
else
  no "i: could not create a hardlink fixture (filesystem does not support it)"
fi

echo "---"
echo "goalforge-install-hooks: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
