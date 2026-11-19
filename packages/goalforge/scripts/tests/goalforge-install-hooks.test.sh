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
#   j..y: the multi-hook installer (hook list, --only, legacy upgrade, the
#      per-target guard) and x, the owned consumers of the marker; each case
#      is introduced where it runs
set -uo pipefail

# No case reads the host git configuration (a global core.hooksPath, a
# template dir or an init.defaultBranch would change what the installer sees).
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

INSTALLER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/goalforge-install-hooks.sh"
MARKER='# >>> goalforge-pre-commit >>>'
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

# ══ Multi-hook installer (wp-03): cases j to y ═══════════════════════════════
# The test seam: the installer gains no option and no variable that adds a hook
# entry. A case that needs a second entry copies the installer to
# <tmp>/pkg/scripts/, inserts one entry as the LAST entry of HOOKS (before the
# closing `)` line) and creates a dummy payload for every entry of the copied
# list. Cases that compare a whole hook file select their entries with --only,
# so an entry a later work package adds on the same git hook cannot change the
# expected file.
NEW_OPEN='# >>> goalforge-pre-commit >>>'
NEW_CLOSE='# <<< goalforge-pre-commit <<<'
LEG_OPEN='# >>> sdd-pre-commit >>>'
LEG_CLOSE='# <<< sdd-pre-commit <<<'
SEAM_ID=seamhook
REAL_P="$(cd "$(dirname "$INSTALLER")/../hooks" && pwd)/goalforge-pre-commit.sh"

open_of()  { printf '# >>> goalforge-%s >>>' "$1"; }
close_of() { printf '# <<< goalforge-%s <<<' "$1"; }
body_of()  { printf 'bash "%s" || exit $?' "$1"; }
count_x()  { grep -cxF -- "$2" "$1" 2>/dev/null; } # <file> <exact line>
after_open() { awk -v o="$2" 'f { print; exit } $0 == o { f = 1 }' "$1" 2>/dev/null; }
no_tmp()   { ! compgen -G "$1/.pre-commit.*" >/dev/null; } # <hooks dir>

# block_ok <file> <id> <P> — exactly one open and one close for <id>, and the
# line after the open marker is the block's own payload line.
block_ok() {
  [ "$(count_x "$1" "$(open_of "$2")")" = 1 ] \
    && [ "$(count_x "$1" "$(close_of "$2")")" = 1 ] \
    && [ "$(after_open "$1" "$(open_of "$2")")" = "$(body_of "$3")" ]
}

# mk_seam <name> <git_hook> — sets SEAM (the copied installer) and SEAM_PKG.
# Fails when the installer has no HOOKS=( ... ) list to insert into.
mk_seam() {
  local d="$WORK/seam-$1" entry rel
  SEAM_PKG="$d/pkg"
  SEAM="$SEAM_PKG/scripts/goalforge-install-hooks.sh"
  mkdir -p "$SEAM_PKG/scripts"
  awk -v e="    \"$SEAM_ID|$2|hooks/seam-$2.sh\"" '
    $0 == "HOOKS=(" { inlist = 1 }
    inlist && $0 == ")" { print e; inlist = 0; done = 1 }
    { print }
    END { exit done ? 0 : 1 }' "$INSTALLER" > "$SEAM" || return 1
  while IFS= read -r entry; do
    rel="${entry##*|}"
    mkdir -p "$SEAM_PKG/$(dirname "$rel")"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$SEAM_PKG/$rel"
  done < <(awk 'inlist && $0 == ")" { exit }
                inlist { gsub(/^[ \t]*"|"[ \t]*$/, ""); print }
                $0 == "HOOKS=(" { inlist = 1 }' "$SEAM")
}
seam_p()  { printf '%s/%s' "$(cd "$SEAM_PKG/hooks" && pwd)" "$1"; } # <payload name>
SEAM_NONE="seam: the installer has no HOOKS=( list to insert an entry into"

# mk_legacy <out> <open> <close> <payload> <final-newline yes|no> — the hook
# the old append path wrote, with a user line before and after the block.
mk_legacy() {
  {
    printf '#!/usr/bin/env bash\necho user-before\n\n%s\n' "$2"
    printf '%s\n' "# goalforge integrity check — blocks on goalforge-validate --strict ERROR in touched features"
    printf '%s\n' "# Use 'cmd || exit \$?' (NOT '[[…]] && exit') so a passing check does not leave the"
    printf '%s\n' "# hook's final command exit-code falsy, which would block every commit."
    printf 'bash "%s" || exit $?\n%s\necho user-after' "$4" "$3"
    [ "$5" = yes ] && printf '\n'
  } > "$1"
}

# ── j: real installer, fresh repository -> the new exact pair ───────────────
repo="$(new_repo j)"; hook="$repo/.git/hooks/pre-commit"
bash "$INSTALLER" "$repo" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(count_x "$hook" "$NEW_OPEN")" = 1 ] \
   && [ "$(count_x "$hook" "$NEW_CLOSE")" = 1 ] && [ -x "$hook" ]; then
  ok "j: fresh install writes exactly one goalforge-pre-commit pair, executable"
else
  no "j: fresh install writes exactly one goalforge-pre-commit pair, executable (rc=$rc)"
fi

# ── k: two entries on two git hooks ─────────────────────────────────────────
# case_k <installer> <tag> — 0 when both targets carry their own block.
case_k() {
  local repo pc cm p1 p2
  repo="$(new_repo "k-$2")"; pc="$repo/.git/hooks/pre-commit"; cm="$repo/.git/hooks/commit-msg"
  bash "$1" "$repo" >/dev/null 2>&1 || return 1
  p1="$(seam_p goalforge-pre-commit.sh)"; p2="$(seam_p seam-commit-msg.sh)"
  [ -x "$pc" ] && [ -x "$cm" ] \
    && block_ok "$pc" pre-commit "$p1" && block_ok "$cm" "$SEAM_ID" "$p2" \
    && [ "$(count_x "$pc" "$(open_of "$SEAM_ID")")" = 0 ] \
    && [ "$(count_x "$cm" "$NEW_OPEN")" = 0 ] \
    && [ "$p1" != "$p2" ]
}
if mk_seam k commit-msg; then
  if case_k "$SEAM" seam; then
    ok "k: two entries -> two executable targets, each with its own pair and payload line"
  else
    no "k: two entries -> two executable targets, each with its own pair and payload line"
  fi
else
  no "k: two entries -> two targets ($SEAM_NONE)"
fi

# ── l: a later target that is shared -> refuse before any write ─────────────
# case_l <installer> <symlink|dangling|hardlink> <tag> — 0 when the refusal
# holds: exit 2, shared file unchanged, stderr names commit-msg, no pre-commit.
case_l() {
  local repo pc cm shared pristine err rc
  repo="$(new_repo "l-$3-$2")"; pc="$repo/.git/hooks/pre-commit"; cm="$repo/.git/hooks/commit-msg"
  shared="$WORK/l-shared-$3-$2"; pristine="$WORK/l-pristine-$3-$2"
  case "$2" in
    symlink)  cp "$PRISTINE" "$shared"; cp "$PRISTINE" "$pristine"; ln -s "$shared" "$cm" ;;
    dangling) ln -s "$shared" "$cm" ;;
    hardlink) cp "$PRISTINE" "$shared"; cp "$PRISTINE" "$pristine"; ln "$shared" "$cm" || return 1 ;;
  esac
  err="$(bash "$1" "$repo" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -eq 2 ] || return 1
  if [ "$2" = dangling ]; then [ ! -e "$shared" ] || return 1
  else cmp -s "$shared" "$pristine" || return 1; fi
  case "$err" in *"$repo/.git/hooks/commit-msg"*) ;; *) return 1 ;; esac
  [ ! -e "$pc" ]
}
if mk_seam l commit-msg; then
  for v in symlink dangling hardlink; do
    if case_l "$SEAM" "$v" seam; then
      ok "l ($v): a shared later target refuses (exit 2), shared file unchanged, earlier target not created"
    else
      no "l ($v): a shared later target refuses (exit 2), shared file unchanged, earlier target not created"
    fi
  done
else
  no "l: a shared later target refuses before any write ($SEAM_NONE)"
fi

# ── l-bad: known-bad arm — a guard that runs only on its first call ─────────
if mk_seam lbad commit-msg; then
  MUTANT="$SEAM_PKG/scripts/mutant-install-hooks.sh"
  awk '{ print } $0 == "guard_target() {" { print "    _gt_calls=$(( ${_gt_calls:-0} + 1 )); [ \"$_gt_calls\" -lt 2 ] || return 0" }' \
    "$SEAM" > "$MUTANT"
  l_red=0
  for v in symlink dangling hardlink; do case_l "$MUTANT" "$v" mutant || l_red=1; done
  if ! cmp -s "$MUTANT" "$SEAM" && grep -qF '_gt_calls' "$MUTANT" \
     && case_k "$MUTANT" mutant && [ "$l_red" -eq 1 ]; then
    ok "l-bad: a guard skipped after its first call passes k and turns l red"
  else
    no "l-bad: a guard skipped after its first call passes k and turns l red (l_red=$l_red)"
  fi
else
  no "l-bad: a guard skipped after its first call passes k and turns l red ($SEAM_NONE)"
fi

# ── m: two entries on ONE git hook -> two blocks in one file ────────────────
if mk_seam m pre-commit; then
  repo="$(new_repo m)"; pc="$repo/.git/hooks/pre-commit"
  bash "$SEAM" "$repo" >/dev/null 2>&1; rc=$?
  l1="$(grep -nxF "$NEW_OPEN" "$pc" 2>/dev/null | cut -d: -f1)"
  l2="$(grep -nxF "$(open_of "$SEAM_ID")" "$pc" 2>/dev/null | cut -d: -f1)"
  if [ "$rc" -eq 0 ] && block_ok "$pc" pre-commit "$(seam_p goalforge-pre-commit.sh)" \
     && block_ok "$pc" "$SEAM_ID" "$(seam_p seam-pre-commit.sh)" \
     && [ -n "$l1" ] && [ -n "$l2" ] && [ "$l1" -lt "$l2" ]; then
    cp "$pc" "$WORK/m-first"
    bash "$SEAM" "$repo" >/dev/null 2>&1; rc=$?
    if [ "$rc" -eq 0 ] && cmp -s "$pc" "$WORK/m-first"; then
      ok "m: two entries on one git hook -> two blocks in list order; a second run is identical"
    else
      no "m: two entries on one git hook -> second run not identical (rc=$rc)"
    fi
  else
    no "m: two entries on one git hook -> two blocks in list order (rc=$rc)"
  fi
else
  no "m: two entries on one git hook ($SEAM_NONE)"
fi

# ── n: an absent payload refuses before any write ───────────────────────────
if mk_seam n commit-msg; then
  repo="$(new_repo n)"
  rm -f "$SEAM_PKG/hooks/seam-commit-msg.sh"
  err="$(bash "$SEAM" "$repo" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -eq 1 ] && [[ "$err" == *"$SEAM_PKG/hooks/seam-commit-msg.sh"* ]] \
     && [ ! -e "$repo/.git/hooks/pre-commit" ] && [ ! -e "$repo/.git/hooks/commit-msg" ]; then
    ok "n: an absent payload exits 1 naming the path; no target created"
  else
    no "n: an absent payload exits 1 naming the path; no target created (rc=$rc, err=${err//$'\n'/ | })"
  fi
else
  no "n: an absent payload exits 1 naming the path ($SEAM_NONE)"
fi

# ── o / o2: --only selects entries ──────────────────────────────────────────
if mk_seam o commit-msg; then
  repo="$(new_repo o)"
  bash "$SEAM" "$repo" --only "$SEAM_ID" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 0 ] && block_ok "$repo/.git/hooks/commit-msg" "$SEAM_ID" "$(seam_p seam-commit-msg.sh)" \
     && [ ! -e "$repo/.git/hooks/pre-commit" ]; then
    ok "o: --only <id> writes that entry's target and no other"
  else
    no "o: --only <id> writes that entry's target and no other (rc=$rc)"
  fi
  repo="$(new_repo o2)"
  bash "$SEAM" "$repo" --only pre-commit --only "$SEAM_ID" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 0 ] && block_ok "$repo/.git/hooks/commit-msg" "$SEAM_ID" "$(seam_p seam-commit-msg.sh)" \
     && block_ok "$repo/.git/hooks/pre-commit" pre-commit "$(seam_p goalforge-pre-commit.sh)"; then
    ok "o2: two --only flags select two entries"
  else
    no "o2: two --only flags select two entries (rc=$rc)"
  fi
else
  no "o: --only <id> writes that entry's target and no other ($SEAM_NONE)"
  no "o2: two --only flags select two entries ($SEAM_NONE)"
fi

# ── p / p2: an unknown id writes nothing ────────────────────────────────────
if mk_seam p commit-msg; then
  repo="$(new_repo p)"
  err="$(bash "$SEAM" "$repo" --only nosuch 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -eq 1 ] && [[ "$err" == *nosuch* ]] && [[ "$err" == *pre-commit* ]] \
     && [[ "$err" == *"$SEAM_ID"* ]] \
     && [ ! -e "$repo/.git/hooks/pre-commit" ] && [ ! -e "$repo/.git/hooks/commit-msg" ]; then
    ok "p: --only nosuch exits 1 naming it and every valid id; no target created"
  else
    no "p: --only nosuch exits 1 naming it and every valid id (rc=$rc, err=${err//$'\n'/ | })"
  fi
  repo="$(new_repo p2)"
  err="$(bash "$SEAM" "$repo" --only pre-commit --only nosuch 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -eq 1 ] && [[ "$err" == *nosuch* ]] && [ ! -e "$repo/.git/hooks/pre-commit" ]; then
    ok "p2: an unknown id beside a valid one exits 1; pre-commit not created"
  else
    no "p2: an unknown id beside a valid one exits 1; pre-commit not created (rc=$rc)"
  fi
else
  no "p: --only nosuch exits 1 naming it and every valid id ($SEAM_NONE)"
  no "p2: an unknown id beside a valid one exits 1 ($SEAM_NONE)"
fi

# ── q: <repo-dir> before or after --only ────────────────────────────────────
if mk_seam q commit-msg; then
  r1="$(new_repo q1)"; r2="$(new_repo q2)"
  bash "$SEAM" "$r1" --only "$SEAM_ID" >/dev/null 2>&1; rc1=$?
  bash "$SEAM" --only "$SEAM_ID" "$r2" >/dev/null 2>&1; rc2=$?
  if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] \
     && [ -f "$r1/.git/hooks/commit-msg" ] && cmp -s "$r1/.git/hooks/commit-msg" "$r2/.git/hooks/commit-msg" \
     && [ ! -e "$r1/.git/hooks/pre-commit" ] && [ ! -e "$r2/.git/hooks/pre-commit" ]; then
    ok "q: <repo-dir> before or after --only gives the same result"
  else
    no "q: <repo-dir> before or after --only gives the same result (rc=$rc1/$rc2)"
  fi
else
  no "q: <repo-dir> before or after --only ($SEAM_NONE)"
fi

# ── r: a legacy block is left alone when pre-commit is not selected ─────────
if mk_seam r pre-commit; then
  repo="$(new_repo r)"; pc="$repo/.git/hooks/pre-commit"
  printf '#!/usr/bin/env bash\necho user-before\n\n%s\nbash "/legacy/goalforge-pre-commit.sh" || exit $?\n%s\n' \
    "$LEG_OPEN" "$LEG_CLOSE" > "$pc"
  chmod 755 "$pc"
  { cat "$pc"; printf '\n%s\n%s\n%s\n' "$(open_of "$SEAM_ID")" "$(body_of "$(seam_p seam-pre-commit.sh)")" "$(close_of "$SEAM_ID")"; } > "$WORK/r-expected"
  bash "$SEAM" "$repo" --only "$SEAM_ID" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 0 ] && cmp -s "$pc" "$WORK/r-expected"; then
    ok "r: --only <other id> appends its block and leaves the legacy lines untouched"
  else
    no "r: --only <other id> appends its block and leaves the legacy lines untouched (rc=$rc)"
  fi
else
  no "r: --only <other id> leaves the legacy lines untouched ($SEAM_NONE)"
fi

# ── s: the upgrade renames the two legacy marker lines, nothing else ────────
repo="$(new_repo s)"; pc="$repo/.git/hooks/pre-commit"
sentinel="$WORK/s-sentinel"
printf '#!/usr/bin/env bash\n: > "%s"\nexit 1\n' "$sentinel" > "$WORK/s-payload.sh"
mk_legacy "$pc" "$LEG_OPEN" "$LEG_CLOSE" "$WORK/s-payload.sh" yes
mk_legacy "$WORK/s-expected" "$NEW_OPEN" "$NEW_CLOSE" "$WORK/s-payload.sh" yes
chmod 755 "$pc"
bash "$INSTALLER" --only pre-commit "$repo" >/dev/null 2>&1; rc=$?
why=""
[ "$rc" -eq 0 ] || why="rc=$rc"
grep -qF 'sdd-pre-commit' "$pc" && why="$why legacy-line-left"
[ "$(count_x "$pc" "$NEW_OPEN")" = 1 ] && [ "$(count_x "$pc" "$NEW_CLOSE")" = 1 ] || why="$why pair-count"
cmp -s "$pc" "$WORK/s-expected" || why="$why bytes"
[ "$(stat -c %a "$pc")" = 755 ] || why="$why mode=$(stat -c %a "$pc")"
no_tmp "$repo/.git/hooks" || why="$why temp-left"
cp "$pc" "$WORK/s-first"
bash "$INSTALLER" --only pre-commit "$repo" >/dev/null 2>&1 || why="$why rerun-rc"
cmp -s "$pc" "$WORK/s-first" || why="$why rerun-changed"
echo x > "$repo/f"; git -C "$repo" add f
if git -C "$repo" -c user.name=t -c user.email=t@t commit -qm s >/dev/null 2>&1; then why="$why commit-passed"; fi
[ -e "$sentinel" ] || why="$why hook-not-run"
if [ -z "$why" ]; then
  ok "s: legacy upgrade renames the marker lines only; mode kept; idempotent; git still runs the hook"
else
  no "s: legacy upgrade renames the marker lines only; mode kept; idempotent; git still runs the hook ($why)"
fi

# ── t: as s, the last line has no trailing newline ──────────────────────────
repo="$(new_repo t)"; pc="$repo/.git/hooks/pre-commit"
mk_legacy "$pc" "$LEG_OPEN" "$LEG_CLOSE" /legacy/goalforge-pre-commit.sh no
mk_legacy "$WORK/t-expected" "$NEW_OPEN" "$NEW_CLOSE" /legacy/goalforge-pre-commit.sh no
chmod 755 "$pc"
bash "$INSTALLER" --only pre-commit "$repo" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && cmp -s "$pc" "$WORK/t-expected"; then
  ok "t: a missing final newline stays missing through the upgrade"
else
  no "t: a missing final newline stays missing through the upgrade (rc=$rc)"
fi

# ── u: unterminated legacy block -> renamed as it is, with a warning ────────
repo="$(new_repo u)"; pc="$repo/.git/hooks/pre-commit"
printf '#!/usr/bin/env bash\n%s\nbash "/legacy/x.sh" || exit $?\necho user-after\n' "$LEG_OPEN" > "$pc"
printf '#!/usr/bin/env bash\n%s\nbash "/legacy/x.sh" || exit $?\necho user-after\n' "$NEW_OPEN" > "$WORK/u-expected"
chmod 755 "$pc"
err="$(bash "$INSTALLER" --only pre-commit "$repo" 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && cmp -s "$pc" "$WORK/u-expected" && [[ "$err" == *"no close marker"* ]]; then
  ok "u: an unterminated legacy block is renamed as it is, with a 'no close marker' warning"
else
  no "u: an unterminated legacy block is renamed as it is, with a warning (rc=$rc, err=${err//$'\n'/ | })"
fi

# ── u2: a lone legacy close marker is not a block ───────────────────────────
repo="$(new_repo u2)"; pc="$repo/.git/hooks/pre-commit"
printf '#!/usr/bin/env bash\necho user\n%s\n' "$LEG_CLOSE" > "$pc"
chmod 755 "$pc"
{ cat "$pc"; printf '\n%s\n%s\n%s\n' "$NEW_OPEN" "$(body_of "$REAL_P")" "$NEW_CLOSE"; } > "$WORK/u2-expected"
bash "$INSTALLER" --only pre-commit "$repo" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && cmp -s "$pc" "$WORK/u2-expected"; then
  cp "$pc" "$WORK/u2-first"
  bash "$INSTALLER" --only pre-commit "$repo" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 0 ] && cmp -s "$pc" "$WORK/u2-first"; then
    ok "u2: a lone legacy close marker is left as it is and the block is appended; idempotent"
  else
    no "u2: a lone legacy close marker -> second run not identical (rc=$rc)"
  fi
else
  no "u2: a lone legacy close marker is left as it is and the block is appended (rc=$rc)"
fi

# ── v / v2: both pairs present -> left untouched with a notice ──────────────
mk_both() {
  printf '#!/usr/bin/env bash\n%s\nbash "/legacy/x.sh" || exit $?\n%s\n\n%s\nbash "/new/y.sh" || exit $?\n%s\n' \
    "$LEG_OPEN" "$LEG_CLOSE" "$NEW_OPEN" "$NEW_CLOSE" > "$1"
  chmod 755 "$1"
}
repo="$(new_repo v)"; pc="$repo/.git/hooks/pre-commit"
mk_both "$pc"; cp "$pc" "$WORK/v-before"
out="$(bash "$INSTALLER" --only pre-commit "$repo" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && cmp -s "$pc" "$WORK/v-before" && [[ "$out" == *"both marker pairs present"* ]]; then
  ok "v: a hook holding both pairs is left byte-identical with a notice"
else
  no "v: a hook holding both pairs is left byte-identical with a notice (rc=$rc, out=${out//$'\n'/ | })"
fi
if mk_seam v2 commit-msg; then
  repo="$(new_repo v2)"; pc="$repo/.git/hooks/pre-commit"
  mk_both "$pc"; cp "$pc" "$WORK/v2-before"
  bash "$SEAM" "$repo" --only pre-commit --only "$SEAM_ID" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 0 ] && cmp -s "$pc" "$WORK/v2-before" \
     && block_ok "$repo/.git/hooks/commit-msg" "$SEAM_ID" "$(seam_p seam-commit-msg.sh)"; then
    ok "v2: both pairs on pre-commit -> untouched, and the later entry is still installed"
  else
    no "v2: both pairs on pre-commit -> untouched, and the later entry is still installed (rc=$rc)"
  fi
else
  no "v2: both pairs on pre-commit, later entry still installed ($SEAM_NONE)"
fi

# ── w: a failed move leaves the hook byte-identical, no temp file ───────────
repo="$(new_repo w)"; pc="$repo/.git/hooks/pre-commit"
mk_legacy "$pc" "$LEG_OPEN" "$LEG_CLOSE" /legacy/goalforge-pre-commit.sh yes
chmod 755 "$pc"; cp "$pc" "$WORK/w-before"
mkdir -p "$WORK/w-bin"; printf '#!/bin/sh\nexit 1\n' > "$WORK/w-bin/mv"; chmod +x "$WORK/w-bin/mv"
PATH="$WORK/w-bin:$PATH" bash "$INSTALLER" --only pre-commit "$repo" >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ] && cmp -s "$pc" "$WORK/w-before" && no_tmp "$repo/.git/hooks"; then
  ok "w: a failed mv exits non-zero, hook byte-identical, no temp file left"
else
  no "w: a failed mv exits non-zero, hook byte-identical, no temp file left (rc=$rc)"
fi

# ── y: argument errors -> exit 1 with a usage line, nothing written ─────────
y_case() { # <label> <repo>... -- <args...>
  local label="$1" r err rc fine=1; shift
  local -a repos=()
  while [ "$1" != "--" ]; do repos+=("$1"); shift; done; shift
  err="$(bash "$INSTALLER" "$@" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -eq 1 ] || fine=0
  [[ "$err" == *"usage:"* ]] || fine=0
  for r in "${repos[@]}"; do
    compgen -G "$r/.git/hooks/*" | grep -qv '\.sample$' && fine=0
  done
  if [ "$fine" -eq 1 ]; then ok "y ($label): exit 1, usage line, nothing written"
  else no "y ($label): exit 1, usage line, nothing written (rc=$rc, err=${err//$'\n'/ | })"; fi
}
repo="$(new_repo y1)"; y_case "--only without a value" "$repo" -- "$repo" --only
repo="$(new_repo y2)"; y_case "unknown option" "$repo" -- "$repo" --bogus
r1="$(new_repo y3a)"; r2="$(new_repo y3b)"; y_case "two directories" "$r1" "$r2" -- "$r1" "$r2"

# ── x: the owned consumers name the new pair (section-scoped literals) ──────
ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
md_section() { # <file> <heading line> — the lines up to the next ## or ### heading
  awk -v h="$2" '$0 == h { f = 1; next } f && /^###? / { exit } f { print }' "$1"
}
x_check() { # <label> <condition...>
  local label="$1"; shift
  if "$@"; then ok "x: $label"; else no "x: $label"; fi
}
INST_MD="$ROOT/INSTALL.md"
REMOVE_SEC="$(md_section "$INST_MD" '### Remove the git pre-commit hook')"
LEFT_SEC="$(md_section "$INST_MD" '### Leftovers to check')"
x_install_pair() { grep -qxF "$NEW_OPEN" "$INST_MD" && grep -qxF "$NEW_CLOSE" "$INST_MD"; }
x_remove_marker() { grep -qE "^# (>>>|<<<) goalforge-" <<<"$REMOVE_SEC"; }
x_leftover_names() { [[ "$LEFT_SEC" == *sdd-pre-commit* && "$LEFT_SEC" == *goalforge-* ]]; }
x_sdd_scoped() {
  [ "$(grep -c sdd-pre-commit "$INST_MD")" -eq $(( $(grep -c sdd-pre-commit <<<"$REMOVE_SEC") + $(grep -c sdd-pre-commit <<<"$LEFT_SEC") )) ]
}
x_installer_literals() {
  [ "$(grep -c sdd-pre-commit "$INST_SH")" -eq 2 ] \
    && [ "$(grep -cE '^[A-Z_]+="# (>>>|<<<) sdd-pre-commit (>>>|<<<)"$' "$INST_SH")" -eq 2 ] \
    && ! grep -qF sdd-install-hooks "$INST_SH"
}
x_evals_json() { grep -qF "$NEW_OPEN" "$EVJ" && ! grep -qF sdd-pre-commit "$EVJ" && ! grep -qF "sdd marker" "$EVJ"; }
x_lint_files() {
  ! grep -qF sdd-pre-commit "$ROOT/scripts/ci-lints.sh" \
    && ! grep -qF sdd-pre-commit "$ROOT/scripts/lint-baselines/retired-vocab-carveouts.txt"
}
INST_SH="$ROOT/packages/goalforge/scripts/goalforge-install-hooks.sh"
EVJ="$ROOT/packages/goalforge/onboard/evals/evals.json"
x_check "INSTALL.md holds both exact new marker lines" x_install_pair
x_check "INSTALL.md uninstall section holds a goalforge- marker line" x_remove_marker
x_check "INSTALL.md leftover check names sdd-pre-commit and goalforge-" x_leftover_names
x_check "INSTALL.md: every sdd-pre-commit lies in the uninstall or leftover section" x_sdd_scoped
x_check "installer: sdd-pre-commit only on the two legacy-constant lines; no sdd-install-hooks" x_installer_literals
x_check "onboard/SKILL.md holds the exact new open literal" \
  grep -qF "$NEW_OPEN" "$ROOT/packages/goalforge/onboard/SKILL.md"
x_check "evals.json holds the new open literal and neither sdd-pre-commit nor 'sdd marker'" x_evals_json
x_check "ci-lints.sh and the carve-out file hold no sdd-pre-commit" x_lint_files

echo "---"
echo "goalforge-install-hooks: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
